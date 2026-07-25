# Plan: Unified Temperature Heatmap + Patrol Integration + CQB Clearing

## Design
Replace the separate `{ danger, safety }` heatmap with a single unified `temp` variable per grid cell. Temperature is the single source of truth for both danger avoidance and patrol targeting. The heatmap represents **information state**:

- `temp = 25` (baseline) = unknown, uncleared
- `temp < 25` (cold) = visually cleared, safe
- `temp > 25` (hot) = danger, active threat

Patrols cool cells by walking (aura) and looking (LOS cone). The planner chases cells at or above baseline (uncleared), not cold ones.

## Unified heatmap data structure

```lua
-- Before:  { danger = n, safety = n, updatedAt = t, lastDangerAt = t }
-- After:   { temp = 25, updatedAt = t, lastDangerAt = t }
```

`temp` starts at 25 (neutral) for every new cell. `lastDangerAt` is preserved for future corner-sweep queries.

## Config (`sh_config.lua`)

```lua
C.Heatmap = {
    Baseline = 25,              -- neutral starting point
    HeatIncrement = 10,         -- per danger event (cover compromised, jink fire)
    PatrolDecrement = 5,        -- per patrol visit or safe occupation
    HeatDecayRate = 0.25,       -- temp > 25 drifts toward 25 at this rate
    SafetyDecayRate = 0.4,      -- temp < 25 drifts toward 25 at this rate (faster = paranoia)
    RadiateRadius = 200,        -- how far temp change radiates from event origin
    DangerThreshold = 35,       -- temp above this → danger; jink holds below this
    AuraRadiateRadius = 100,    -- radius of the cool aura around the NPC during patrol
    AuraCoolRate = 0.5,         -- temp reduction per patrol tick for aura
    ConeRange = 500,            -- range of the LOS cooling cone
    ConeFOV = 90,               -- field of view of the cone (degrees)
    ConeRays = 5,               -- number of rays cast in the cone
    ConeCoolRate = 1,           -- temp reduction per patrol tick for each cone ray
    PatrolRadius = 1200,        -- range for patrol target search
}
```

## Temperature events

| Event | Delta | Source |
|-------|-------|--------|
| Cover compromised | +HeatIncrement | `Battlefield.MarkCover(pos, false)` |
| Jink reflex | +HeatIncrement | `suppression_jink.lua` after fleeing |
| Patrol aura (per tick) | -AuraCoolRate | `pre_contact.lua` during patrol movement — `RecordTemp(squad, npcPos, -AuraCoolRate, AuraRadiateRadius)` |
| Patrol LOS cone (per tick) | -ConeCoolRate | `pre_contact.lua` during patrol movement — 5 rays across 90° FOV, `RecordTemp` at each ray endpoint |
| Safe occupation (6s) | -PatrolDecrement | `Battlefield.MarkCover(pos, true)` |

All events call a single `SM.RecordTemp(squad, pos, delta, radius)` function. When a heatmap cell is first created, `temp` starts at `C.Heatmap.Baseline + delta` (clamped 0-50). Subsequent calls add `delta` to the existing `temp` (clamped 0-50).

## Degradation

During `SM.Scan` (1s spatial map timer), capture the previous scan timestamp before it's overwritten, then iterate heatmap cells and apply directional decay:

```lua
local elapsed = CurTime() - sm.lastScan  -- capture BEFORE sm.lastScan is updated
for key, h in pairs(sm.heatmap) do
    if h.temp > C.Heatmap.Baseline then
        h.temp = math.max(C.Heatmap.Baseline, h.temp - C.Heatmap.HeatDecayRate * elapsed)
    elseif h.temp < C.Heatmap.Baseline then
        h.temp = math.min(C.Heatmap.Baseline, h.temp + C.Heatmap.SafetyDecayRate * elapsed)
    end
    if h.temp >= C.Heatmap.Baseline - 2 and h.temp <= C.Heatmap.Baseline + 2 then
        sm.heatmap[key] = nil  -- prune near-neutral cells
    end
end
```

## Patrol — three-layer clearing model

The patrol uses three mechanisms to cool cells, each operating at a different scale:

### 1. Aura (presence clearing)
Every patrol tick, the NPC's position radiates a small cooling effect outward to `AuraRadiateRadius`. This clears the immediate ground the NPC walks on — already implemented via `RecordTemp` with a small radius.

### 2. LOS cone (visual clearing)
Every patrol tick, 5 rays are cast across the NPC's forward 90° FOV out to `ConeRange`. Each ray endpoint calls `RecordTemp(squad, endPos, -ConeCoolRate)`. This visual arc covers doorways, side corridors, and corners the NPC sees as they walk — without explicit corner detection.

### 3. Patrol planner destination clearing
When the leader arrives at `patrolPos`, `RecordTemp(squad, pos, -PatrolDecrement)` strongly cools that cell. This marks major waypoints as fully cleared.

## Patrol planner (`squad_func/patrol.lua`) — chase neutral, not cold

The planner queries cells **at or above baseline** (uncleared/unknown), not cold ones:

1. Query spatial map for heatmap cells within `PatrolRadius` of leader
2. Filter to cells with `temp >= C.Heatmap.Baseline - 2` (uncleared or just below)
3. Pick the cell closest to baseline from the filtered set
4. If any found: pick a random valid ground position within that cell (`CAI.Nav.RandomPointNear` at cell center with ~64u search radius), validate with `SafeGround` + navmesh, set as target
5. On leader arrival at `patrolPos`, call `SM.RecordTemp(squad, pos, -PatrolDecrement)`
6. Fallback: if all cells are cold or near-neutral, use existing random-point selection unchanged

This naturally routes the patrol toward uncleared areas (T-junction cross-branches, uncleared rooms, blind corners) because those cells are still at neutral 25 while the patrolled path is below 25.

## Natural clearing of T-junctions and corners

No explicit corner detection needed. The three layers work together:

- NPC walks up the T-junction's stem
- LOS cone (forward sweep, 90° FOV, 5 rays) catches the left and right arms as the NPC's facing oscillates during movement
- Cells in the side arms get cooled toward baseline
- Patrol planner sees the side arm cells still near neutral (25) — still needs checking
- Patrol planner selects a patrol point in the side arm → NPC walks there → cone sweeps it fully → cells drop below baseline → cleared
- Next tick, the other arm is still warmer → patrol selects that one

## SM.RecordTemp — radiating, replaces RecordDanger/RecordSafety

```lua
function SM.RecordTemp(squad, pos, delta, radius)
    -- Same radiating loop as RecordDanger/RecordSafety
    -- Clamp temp to 0-50
end
```

## Files changed

| File | Change |
|------|--------|
| `sv_spatialmap.lua` | Replace `RecordDanger`/`RecordSafety` with `RecordTemp`; update decay in `SM.Scan` |
| `sv_cover.lua` | Update `QueryNearby` to read `temp` instead of `safety - danger`. Filter becomes `h.temp < C.Heatmap.DangerThreshold`. |
| `sv_battlefield.lua` | Update `MarkCover` to call `RecordTemp(squad, pos, +HeatIncrement)` / `RecordTemp(squad, pos, -PatrolDecrement)` |
| `suppression_jink.lua` | Update `RecordDanger` call to `RecordTemp(squad, src, +HeatIncrement)`; `QueryHeat` to `QueryTemp` |
| `squad_func/patrol.lua` | Query cells with `temp >= Baseline - 2` (uncleared) instead of cold cells; apply `-PatrolDecrement` on arrival |
| `exec/pre_contact.lua` | Add aura cooling + LOS cone cooling during patrol tick |
| `sh_config.lua` | Replace old `C.Heatmap` block with new unified config including aura + cone + patrol radius |

## Implementation Order

| Step | What | Files |
|------|------|-------|
| ✅ | Config + RecordTemp + QueryTemp + decay | `sh_config.lua`, `sv_spatialmap.lua`, `sv_cover.lua`, `sv_battlefield.lua`, `suppression_jink.lua` |
| ✅ | Patrol planner inverted query | `squad_func/patrol.lua` |
| 🔲 | Patrol executor aura + cone | `exec/pre_contact.lua` |

## Backwards compatibility

- `SM.QueryTemp(squad, pos)` replaces `SM.QueryHeat` and returns `temp` (0-50). The jink heatmap gate becomes `QueryTemp(pos) < C.Heatmap.DangerThreshold` (below 35 → safe enough to hold, don't flee).
- `RecordDanger` and `RecordSafety` are removed — replaced by `RecordTemp(squad, pos, delta)`. No external callers exist beyond CAI.
- The old heatmap data structure ( `{ danger, safety }` ) is replaced by `{ temp }`. Existing heatmap entries are discarded — all start at `temp = 25` because spatial map entries are created fresh on first write.