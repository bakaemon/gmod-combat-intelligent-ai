# Plan: Cover Phase Fixes

## Problems
1. **Plan invalidation race** (`sv_cover.lua:240-241`) — When cover is compromised, `UpdateCoverStatus` finds new cover and immediately sets `plan.expiresAt = CurTime()`, causing the OODA to change phase before the NPC moves to the new position.
2. **`lost_target_coa.lua` returns COVER blindly** — 4 return paths without checking `FindBest`. NPC stands vulnerable while the exec handler searches.
3. **No squad-level cover cache** — `FindBest` runs the expensive `GatherSpots` + `ScoreSpot` pipeline every call (~1.5ms). Per-NPC, per-OODA-tick. No sharing of results between squad members.

## Expected Fixes
1. NPCs move to newly-found cover after compromise instead of being yanked into a new phase
2. `lost_target_coa.lua` only returns COVER when cover is actually available
3. Squad-level cover cache with three tiers — fast grid query, proactive refresh, reactive fallback. All tiers populate the cache.

## Fix 1: Plan invalidation race (`sv_cover.lua:240-241`)

**Root cause**: `data.planPending = "cover_blown"` + `data.plan.expiresAt = CurTime()` at lines 240-241, immediately after finding new cover at line 237. The phase replans before the NPC moves to the new cover.

**Fix**: Remove the `planPending` and `plan.expiresAt` lines. Let the NPC move to the newly-found cover and only force a replan if the search itself fails.

Current at lines 237-241:
```lua
data.cover = { pos = newPos, since = CurTime() }
                data.forceRecover = nil
                CAI.Nav.MoveTo(data, newPos, "run")
data.planPending = "cover_blown"
data.plan.expiresAt = CurTime()
```

Fixed — only remove `planPending` and `plan.expiresAt` (lines 240-241), keep `forceRecover` and `MoveTo`:
```lua
data.cover = { pos = newPos, since = CurTime() }
                data.forceRecover = nil
                CAI.Nav.MoveTo(data, newPos, "run")
```

The `planPending` on line 244 (after 4 failed FindBest calls) already handles the true failure case. The compromise case just needs to set the new cover and let the search path in the exec handler handle re-evaluation naturally — the NPC stays in COVER phase, the next tick sees `data.cover` is set, and continues the move-to-cover flow.

## Fix 2: `lost_target_coa.lua` — gate COVER returns with FindBest

**Root cause**: Lines 31, 35, 51, 56 return COVER without checking if cover exists. The exec handler searches on the first frame, but the NPC stands in the open while waiting.

**Fix**: Before each COVER return, call `FindBest` and only return COVER if a position is found. With the new tiered cache (Fix 3), `FindBest` is now cheap for most calls — it queries the cache first. Extract the search into a `hasCover` helper and check it before each COVER return.

```lua
local function hasCover(data)
    if data._coverCheckAt and CurTime() - data._coverCheckAt < 0.5 then
        return data._coverAvailable
    end
    local enemy, rec = CAI.Memory.FreshestEnemy(data)
    data._coverCheckAt = CurTime()
    data._coverAvailable = CAI.Cover.FindBest(data, enemy, rec and rec.pos) ~= nil
    return data._coverAvailable
end
```

Then gate each COVER return:
```lua
if hasCover(data) then return CAI.PHASE.COVER, "hold", 2, "await_reacquire" end
```

If no cover found, the COA doesn't return — the NPC falls through to investigate/search/cover in the downstream branches.

## Fix 3: Squad-level cover cache (three tiers)

**Root cause**: `FindBest` runs the expensive `GatherSpots` → `ScoreSpot` pipeline every call. The `spatialMap.cover` grid already exists (populated by `SM.ScanCover`) but `FindBest` ignores it. `QueryNearby` reads the grid but is called by nothing. Each NPC pays the full cost independently.

**Fix**: Replace the `FindBest` implementation with a three-tier system. All tiers store results in `spatialMap.cover`, so the first expensive search for an area populates the cache for all squad members.

### Tier 1: Fast grid query (replaces the front of FindBest)

`FindBest` starts by calling `QueryNearby` with the NPC's position (not the enemy's):

```lua
function CV.FindBest(data, enemy, enemyPos)
    local npc = data.ent
    local npcPos = IsValid(npc) and npc:GetPos()
    -- Tier 1: fast cache query near the NPC
    local cached = npcPos and CV.QueryNearby(data, npcPos, C.Cover.SearchRadius)
    if cached then return cached end

    -- Tier 2/3: expensive search (see below)
    ...
end
```

`QueryNearby` already:
- Queries `spatialMap.cover` cells within `radius` of `origin`
- Filters by `temp < DangerThreshold` (heatmap)
- Returns nearest valid position or nil

This is ~0.05ms — 30x faster than the full pipeline.

### Tier 2: Proactive cache refresh (squad-level timer, 2.0s interval)

A squad-level timer detects when any squad member is far from cached cover cells. If so, it triggers an immediate refresh — limited to 1-2 fallback searches per tick to avoid lag spikes:

```lua
timer.Create("CAI_CoverCacheRefresh", 2.0, 0, function()
    if not CAI.Enabled() then return end
    for squad in pairs(CAI.Squad.All()) do
    local sm = squad.blackboard.spatialMap
    local budget = 2
    for _, m in ipairs(squad.members) do
        if budget <= 0 then break end
        local d = CAI.Manager.Get(m)
        if d and IsValid(m) then
            local closest = CV.QueryNearby(d, m:GetPos(), C.Cover.SearchRadius)
            if not closest then
                local enemy, rec = CAI.Memory.FreshestEnemy(d)
                local pos = CV.FindBestFallback(d, enemy, rec and rec.pos)
                if pos then
                    -- Store in spatialMap.cover for the squad
                    local key = math.floor(pos.x / C.Cover.CellSize) .. ":" .. math.floor(pos.y / C.Cover.CellSize)
                    if not sm.cover[key] then sm.cover[key] = {} end
                    if #sm.cover[key] < C.Cover.MaxPerCell then
                        table.insert(sm.cover[key], { pos = pos, weight = 0, validatedAt = CurTime() })
                    end
                end
            end
        end
    end
end
```

The detection condition: `QueryNearby` within `SearchRadius` returns nil → no cached cover in range → trigger refresh.

### Tier 3: Reactive FindBest fallback

When `QueryNearby` returns nil AND the cache refresh hasn't run yet, `FindBest` falls through to the expensive path. Result is stored in the cache:

```lua
function CV.FindBestFallback(data, enemy, enemyPos)
    local npc = data.ent
    local origin = IsValid(npc) and npc:GetPos()
    if not origin then return nil end
    local spots = CV.GatherSpots(origin, enemyPos, nil)
    local best, bestScore = nil, -math.huge
    for _, sp in ipairs(spots) do
        local s = CV.ScoreSpot(data, sp, enemy, enemyPos)
        if s > bestScore then best, bestScore = sp, s end
    end
    if best then
        -- Store in cache
        local sm = data.squad and data.squad.blackboard.spatialMap
        if sm then
            local key = math.floor(best.x / C.Cover.CellSize) .. ":" .. math.floor(best.y / C.Cover.CellSize)
            if not sm.cover[key] then sm.cover[key] = {} end
            if #sm.cover[key] < C.Cover.MaxPerCell then
                table.insert(sm.cover[key], { pos = best, weight = 0, validatedAt = CurTime() })
            end
        end
        return best
    end
    return nil
end
```

Tier 2 and 3 both call this same function — the only difference is the trigger. Tier 2 runs proactively from the detection timer. Tier 3 runs reactively from `FindBest`'s fallback path.

### Cache update on FindBest success

After any successful `FindBest` call (Tier 2 or 3), the result is stored in `spatialMap.cover` under the appropriate grid cell key. Subsequent `QueryNearby` calls from any squad member will find it.

### Invalidation

`MarkCover(pos, false)` already calls `RecordTemp` which heats the cell. `QueryNearby` filters out cells with `temp >= DangerThreshold`. Stale entries in hot cells are effectively invisible — they're not removed, just skipped at query time.

### Dependency: CV.GatherSpots

`FindBestFallback` calls `CV.GatherSpots(origin, enemyPos, nil)` which was previously a local function in `sv_cover.lua`. It must be exposed on the `CV` table:

```lua
CV.GatherSpots = GatherSpots
```

This was already added in an earlier implementation step — verify it's still present before deploying Fix 3.

## Implementation Order

| Step | What | Files |
|------|------|-------|
| 1 | Remove `planPending` + `plan.expiresAt` in compromise path | `sv_cover.lua` |
| 2 | Gate `lost_target_coa.lua` COVER returns with cached `FindBest` | `lost_target_coa.lua` |
| 3 | Restructure `FindBest` into three tiers + cache refresh timer | `sv_cover.lua`, `squad_func/plan.lua`, `sh_config.lua` |

## Files Changed

| File | Change |
|------|--------|
| `sv_cover.lua:232-241` | Remove `planPending` + `plan.expiresAt` from compromise path (lines 240-241) |
| `sv_cover.lua` | Restructure `FindBest` to query cache first (`QueryNearby` with NPC's pos), fall back to `FindBestFallback` which stores in `spatialMap.cover`; verify `CV.GatherSpots` is exposed |
| `lost_target_coa.lua` | Gate each COVER return behind `hasCover(data)` check using `FindBest` with 0.5s per-NPC cache |
| `squad_func/plan.lua` | Add cache refresh timer: detect NPCs far from cached cover, trigger `FindBestFallback` (max 2/tick), store in `spatialMap.cover` |
| `sh_config.lua` | No new config needed — existing `C.Cover.SearchRadius`, `C.Cover.CellSize`, `C.Cover.MaxPerCell` already apply |

## Backwards Compatibility

- `CV.FindBest` signature unchanged — still `(data, enemy, enemyPos)`. Internal restructuring is transparent.
- `CV.QueryNearby` unchanged — already reads `spatialMap.cover` and heatmap. No change needed.
- `CV.FindBestFallback` is new — contains the old `GatherSpots` + `ScoreSpot` pipeline. Extracted from `FindBest`.
- `lost_target_coa.lua` behavior change: only returns COVER when cover is available. Previously returned COVER even without cover, which the exec handler then handled with a search loop.
- Compromise path: removing `planPending` means the NPC stays in COVER phase after compromise and moves to the newly-found cover.
- Cache entries in `spatialMap.cover` are shared through the existing squad blackboard system. No new data structures needed.