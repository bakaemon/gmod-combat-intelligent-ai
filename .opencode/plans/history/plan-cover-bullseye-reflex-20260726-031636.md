# Plan: Cover Map + Bullseye Pre-Spawn + Reflex Abstraction

## Overview

Four architectural changes to fix performance issues and enable emergent tactical behavior:

1. **Pre-spawned bullseye per NPC** — Eliminate entity create/destroy churn and the "LastKnownPosition" engine error spike
2. **Spatial cover map** — Squad-interval pre-computed cover positions for fast nearest-cover queries (jink, push)
3. **Reflex movement abstraction** — `N.ReflexMove()` helper that decides "bias existing movement" vs "create new movement"; preserves existing `BR.Reflex` bias-accumulation pattern
4. **Cover-waypoint push pipeline** — Aggressive push advances between cover spots instead of straight-line

---

## Part A: Pre-Spawned Bullseye (Per-NPC)

### Problem
- `CAI.FireAim.Aim()` creates `npc_bullseye` on first call, removes it on `Stop()`
- Create/destroy churns entity list; TTL expiry window causes "Asking LastKnownPosition for enemy that's not in my memory!!" engine error (stale engine pointer race)

### Solution
- Pre-spawn one bullseye at `MG.Register()` time, store in `data.suppBullseye`
- `Aim()`: teleport to target pos + `SetEnemy(bull)` — no more create branch
- `Stop()`: teleport to void (`Vector(0,0,-16000)`) + `SetEnemy(NULL)` — **entity persists**
- `MG.Unregister()`: `data.suppBullseye:Remove()` (only actual destroy)
- `SF_BULLSEYE_NPC_EXEMPT` flag (196608, already set) prevents engine re-acquisition of the void-pos bullseye

### Files
| File | Changes |
|------|---------|
| `sv_manager.lua` | `MG.Register`: call `CAI.FireAim.Alloc(data)`; `MG.Unregister`: call `data.suppBullseye:Remove()` |
| `sv_fireaim.lua` | New `CAI.FireAim.Alloc(data)` creates bullseye at void pos; `Aim()`: teleport-only (remove create-branch); `Stop()`: teleport to void + `SetEnemy(NULL)` (no `Remove()`) |

---

## Part B: Spatial Cover Map (Squad-Interval Pre-Compute)

### Problem
- `CAI.Cover.FindBest()` does full gather + 10-weight scoring per call (~1.5ms)
- Jink reflex calls `FindBest` every tick (cached in `data._reflexCover` — never cleared, stale)
- Jink needs a *nearby* cover spot fast, not the global optimum

### Solution
- New `SM.ScanCover(squad)` function: gathers cover candidates around squad AO using its **own independent budget** (separate from the nav-area chokepoint/high-ground/doorway scan)
- Runs every **2nd** spatial-map tick (0.5Hz instead of 1Hz) to keep overhead low
- Stores in `squad.blackboard.spatialMap.cover[gridKey]`: `{ pos, weight, validatedAt }`
- Simplified 4-weight scoring: LOS-blocked, distance-from-NPC, crowd penalty, danger-zone penalty — skip flank/escape/history/dark
- `gridKey` uses `CAI.Config.Cover.CellSize` (128u); MaxPerCell = 6
- TTL 8s, stale entries evicted on each scan
- `CV.QueryNearby(data, origin, radius, opts)` reads spatial map, returns nearest valid spot. Falls back to away-from-enemy bias if no cover entries found yet (squad's first scan hasn't completed within 1-2s of spawn)
- Config: `C.Cover.CellSize = 128`, `C.Cover.MapTTL = 8`, `C.Cover.MaxPerCell = 6`, `C.Cover.NearbyRadius = 500`, `C.Cover.ScanBudget = 10`

### Squad Safety Heatmap (validation foundation)

The spatial cover map is paired with a **radiating safety heatmap** on the squad blackboard to collectively validate whether **areas** are safe or dangerous. Instead of marking individual spots, each event radiates heat outward with falloff, creating a continuous danger gradient.

**Data structure** (per grid cell, same `gridKey` as cover map):

```lua
squad.blackboard.heatmap[gridKey] = {
    danger = n,        -- accumulated danger heat
    safety = n,        -- accumulated safety heat from safe occupation
    updatedAt = t,     -- last time either value changed
    lastDangerAt = t,  -- last time danger was incremented at epicenter (for future corner-sweep)
}
```

**RecordDanger — radiates outward from origin:**

```lua
function SM.RecordDanger(squad, pos, amount, radius)
    radius = radius or C.Heatmap.RadiateRadius
    local cellSize = C.Cover.CellSize
    local cellR = math.ceil(radius / cellSize)
    local cx, cy = math.floor(pos.x / cellSize), math.floor(pos.y / cellSize)
    for dx = -cellR, cellR do
        for dy = -cellR, cellR do
            local dist = (math.sqrt(dx*dx + dy*dy) * cellSize) + cellSize * 0.5
            if dist <= radius then
                local falloff = 1 - dist / radius
                local sm = squad.blackboard.spatialMap
                local key = (cx + dx) .. ":" .. (cy + dy)
                local h = sm.heatmap[key]
                if not h then h = { danger = 0, safety = 0, updatedAt = 0, lastDangerAt = 0 }; sm.heatmap[key] = h end
                h.danger = h.danger + amount * falloff
                h.updatedAt = CurTime()
                if dist < cellSize * 0.5 then h.lastDangerAt = CurTime() end
            end
        end
    end
end
```

`RecordSafety` uses the same radiating pattern — credited cover at position X radiates safety outward so nearby spots also benefit.

**When danger is incremented:**
- Cover compromised: `exec/cover.lua` → `UpdateCoverStatus` → `Battlefield.MarkCover(pos, false)` → calls `SM.RecordDanger(squad, pos)`
- Jink reflex: only when the NPC is NOT at a safe cover position and creates movement (not when holding position). Reports the fired-upon position into the heatmap.

**When safety is incremented:**
- Cover credited: `UpdateCoverStatus` (6s safe occupation without exposure) → `Battlefield.MarkCover(pos, true)` → calls `SM.RecordSafety(squad, pos)`

**Decay: additive.** Every spatial map scan tick, using time since last scan as delta:

```lua
local elapsed = CurTime() - sm.lastScan  -- time since last scan (~5s)
for key, h in pairs(sm.heatmap) do
    h.danger = math.max(0, h.danger - C.Heatmap.DecayRate * elapsed)
    h.safety = math.max(0, h.safety - C.Heatmap.DecayRate * elapsed)
    if h.danger < 1 and h.safety < 1 then sm.heatmap[key] = nil end
end
```

Additive decay preserves `lastDangerAt` as a meaningful signal until danger fully decays — needed for future corner-sweep.

**Integration with QueryNearby:**
`CV.QueryNearby` reads the heatmap cell for each cover candidate and factors `netHeat = safety - danger` into the score. Candidates in cells with `netHeat < -C.Heatmap.DangerThreshold` are deprioritized or skipped. Single O(1) lookup per candidate.

**SM.QueryHeat — per-tick position safety check for jink gate:**

```lua
function SM.QueryHeat(squad, pos)
    local cellSize = C.Cover.CellSize
    local key = math.floor(pos.x / cellSize) .. ":" .. math.floor(pos.y / cellSize)
    local h = squad.blackboard.spatialMap.heatmap[key]
    if not h then return 0 end
    return h.safety - h.danger
end
```

Called from the jink reflex once per tick when the NPC is at a cover position. Returns `0` (no data) or `safety - danger` (positive = safe, negative = dangerous).

**Config** (`sh_config.lua`):

```lua
C.Heatmap = {
    DangerIncrement = 10,    -- per compromise or jink event
    SafetyIncrement = 5,     -- per 6s safe occupation
    RadiateRadius = 200,     -- how far danger/safety radiates from origin
    DecayRate = 2,           -- per second, additive decay
    DangerThreshold = 15,    -- netHeat below this → skip candidate
}
```

### Files
| File | Changes |
|------|---------|
| `sv_spatialmap.lua` | Add `SM.ScanCover(squad)` with its own `coverScanIdx`/`coverBudget` iteration; called from `SM.Scan` every 2nd tick; add `SM.RecordDanger`, `SM.RecordSafety`, `SM.QueryHeat` heatmap functions with decay on scan |
| `sv_cover.lua` | Add `CV.QueryNearby(data, origin, radius, opts)` reading spatial cover map + heatmap score |
| `sh_config.lua` | Add `C.Cover.CellSize`, `C.Cover.MapTTL`, `C.Cover.MaxPerCell`, `C.Cover.NearbyRadius`; add `C.Heatmap` block |
| `sv_battlefield.lua` | Add danger-increment call in `MarkCover(pos, false)` path; add safety-increment call in `MarkCover(pos, true)` path |

---

## Part C: Abstracted Reflex Movement

### Problem
- Three reflexes (jink, grenade_dodge, melee_dodge) return `(biasVec, urgency)`
- `data.reflex.bias` only consumed by `N.MoveTo()` — never called during suppress → jink bias dead
- Decision "bias vs. create new movement" scattered across handlers

### Solution
- **`sv_navigation.lua`**: Add `N.ReflexMove(data, pos, mode)` — returns `biasVec` or `nil`:
  ```lua
  function N.ReflexMove(data, pos, mode)
      -- If NPC has no active destination: create movement, no bias
      -- If NPC has active destination: compute bias toward pos
      -- Returns: biasVec (for BR.Reflex to accumulate) or nil
  end
  ```
- **`BR.Reflex` stays as-is** (accumulates bias from all handlers, sets `data.reflex.bias`). No change to the accumulation pattern.
- Each reflex handler calls `N.ReflexMove` to get its biasVec, then returns `(biasVec, urgency)` as before:
  - `suppression_jink.lua` with heatmap evaluation gate:
    ```
    if sup <= UnderFireAt → return

    if at cover (data.cover or _pushCoverPhase == "peek"):
        netHeat = SM.QueryHeat(squad, npcPos)
        if netHeat >= -threshold:
            → Cover safe, hold. Return nil, urgency. No RecordDanger.
        else:
            → Cover hot, flee. CV.QueryNearby → N.ReflexMove → RecordDanger(src)

    else (moving or standing):
        CV.QueryNearby → N.ReflexMove → RecordDanger(src)

    return biasVec, urgency
    ```
  - `grenade_dodge.lua`: compute away pos → `N.ReflexMove` → return `(biasVec, urgency)`
  - `melee_dodge.lua`: compute away pos → `N.ReflexMove` → return `(biasVec, urgency)`
- **Comment fix** in `react.lua`: outdated `-- only biases MOVEMENT` → reflexes CAN call `N.ReflexMove` which may call `N.MoveTo`, but never change phase/destination

### Bias-accumulation safety
`N.ReflexMove` does **not** mutate `data.reflex.bias` directly. It returns a fresh vector. `BR.Reflex` accumulates all returned vectors (same as now). Each tick `BR.Reflex` starts with `Vector(0,0,0)` so there is no stale accumulation across ticks.

### Files
| File | Changes |
|------|---------|
| `sv_navigation.lua` | Add `N.ReflexMove(data, pos, mode)` returns biasVec or nil |
| `react.lua` | Update doc comment only (reflex CAN issue movement via `N.ReflexMove`) |
| `suppression_jink.lua` | Full rewrite: use `CV.QueryNearby` + `N.ReflexMove`; remove `data._reflexCover` |
| `grenade_dodge.lua` | Rewrite: compute away pos → `N.ReflexMove` |
| `melee_dodge.lua` | Rewrite: compute away pos → `N.ReflexMove` |

---

## Part D: Cover-Waypoint Push Pipeline

### Problem
- `aggressive_push` advances in straight line toward enemy, ignores cover
- No bounding between cover spots during push — NPCs are predictable and exposed
- Existing timing (`pushBurstAt`, `pushAt`, `fireUntil`, `creepAt`) manages burst-fire-and-move cycles but has no spatial awareness

### Solution
Modify `engage.lua` `aggressive_push` block (lines 361-412) with three cover-waypoint phases, controlled by `data._pushCoverPhase`:

```
1. "acquire" — NPC has no current cover waypoint
   Query CV.QueryNearby(data, npc:GetPos(), 600, { towardEnemy = true })
   If cover found nearer to enemy than NPC:
     set data._pushCover = coverPos
     set data._pushCoverPhase = "move"
     N.MoveTo(data, coverPos, "run")
   If no cover found:
     fall through to existing straight-line advance (old behavior)

2. "move" — NPC is moving toward cover waypoint
   On arrival (N.Arrived(data, 80)):
     set data._pushCoverPhase = "peek"
     data._pushPeekUntil = CurTime() + BurstDuration (1.2s)
     FireSchedule or Prefire (peek-shoot)
   While moving:
     same as old "creep" logic — fire burst if visible, keep advancing

3. "peek" — NPC is firing from cover
   When CurTime() > _pushPeekUntil:
     set data._pushCoverPhase = "acquire" (find next cover)
   Danger avoid or taking fire → early exit peek, re-duck to cover

Fallback: if _pushCoverPhase is nil (not set) or _pushCover is nil → existing
straight-line advance code runs unchanged. This preserves all old behavior.
```

Key integration points with existing code:
- `pushBurstAt` / `pushAt` timers only consulted during "move" phase (when NPC is between cover spots, not arriving at cover)
- `fireUntil` respected during all phases
- `tryMoveShoot()` only called when no cover waypoint available (fallback)
- Max 3 cover hops (`data._pushHops`) before forcing direct advance to prevent stalls
- `data._pushCover`, `data._pushCoverPhase`, `data._pushCoverAt`, `data._pushPeekUntil`, `data._pushHops` cleared in `BR.SetPhase` (add to the clearance list in `state.lua`)

### Files
| File | Changes |
|------|---------|
| `engage.lua` | Refactor `aggressive_push` lines 361-412 to use cover-waypoint pipeline |
| `state.lua` | Add `_pushCover`, `_pushCoverPhase`, `_pushCoverAt`, `_pushPeekUntil`, `_pushHops` to `BR.SetPhase` clearance |

---

## Implementation Order

| Step | What | Files |
|------|------|-------|
| 1 | Bullseye pre-spawn | `sv_manager.lua`, `sv_fireaim.lua` |
| 2 | Spatial cover map + heatmap + QueryNearby | `sv_spatialmap.lua`, `sv_cover.lua`, `sv_battlefield.lua`, `sh_config.lua` |
| 3 | `N.ReflexMove` | `sv_navigation.lua` |
| 4 | Rewrite 3 reflexes | `suppression_jink.lua`, `grenade_dodge.lua`, `melee_dodge.lua` |
| 5 | Comment fix in react.lua | `react.lua` |
| 6 | Cover-waypoint push | `engage.lua`, `state.lua` |

Steps 3-4-5 can be done in one batch since they form a single cohesive change (reflex movement).

---

## Testing Checkpoints

1. **Bullseye**: Spawn 10 NPCs, engage in combat — verify no bullseye create/destroy in console (only 10 bullseyes total). Verify `Tick` teleports to void when suppression ends.

2. **Cover map**: Start squad combat, watch `CV.QueryNearby` return valid positions. Profile: jink tick cost should drop from ~1.5ms (full `FindBest`) to ~0.1ms (spatial map lookup).

3. **Reflex move**: NPC under suppression without destination → moves to cover. NPC with active move target → biases toward cover. Grenade/melee dodge triggers movement when stationary.

4. **Push pipeline**: Squad with advantage pushes → NPCs bound between cover spots visible in navmesh debug (`nav_edit 1`). After 3 cover hops, NPC falls back to direct advance.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Pre-spawned bullseye re-acquired by engine | `SF_BULLSEYE_NPC_EXEMPT` flag prevents auto-acquisition; `ClearEnemy` + void pos ensures no valid target |
| Spatial cover map stale | 8s TTL + per-scan LOS validation; `QueryNearby` falls back to away-from-enemy bias |
| Heatmap gradient decays but feedback loop is slow | Jink reports danger on every evasion tick; compromise path is immediate; additive decay prevents signal loss between scans |
| `N.ReflexMove` + `BR.Reflex` bias double-counting | `N.ReflexMove` returns a vector, never mutates `data.reflex.bias`; `BR.Reflex` resets to `Vector(0,0,0)` each tick |
| Push waypoint stall (NPC stuck between covers) | Max 3 hops (`_pushHops`), then direct-advance fallback; `data._pushCoverPhase` prevents re-query mid-move |
| Push phase-cleared fields missing in SetPhase | Add all new `_push*` fields to the clearance list in `state.lua:44-62` |

---

## Backwards Compatibility

- `CAI.Cover.FindBest()` unchanged — still used by `exec/cover.lua` for active cover selection (not by reflexes)
- `CAI.FireAim.Aim/Stop/ClearEnemy` signatures unchanged
- Reflex handler signature unchanged: `(data, dt) -> (biasVec, urgency)`
- `BR.Reflex` unchanged (still accumulates bias, sets `data.reflex.bias`)
- No new phases or OODA changes
- `aggressive_push` fallback preserves all old straight-line logic when no cover waypoints found