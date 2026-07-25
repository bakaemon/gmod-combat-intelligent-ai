# Squad Architecture Overhaul

## Principle

Replace the current per-NPC independent decision-making with a **squad-first** architecture. Individual COAs are subordinate to squad orders. Spatial memory, patrol routing, and tactical planning become squad-level concerns, not per-NPC.

The decision pipeline becomes:

```
SquadOrder (role-based) → PreTarget (emergency) → Target (individual)
```

Squad orders fire **without** requiring `ctx.visible` — squad flags already encode intent from the squad planner.

---

## Audit: Current Squad Infrastructure

### What exists already (in sv_squad.lua)

| Function | Purpose | Migrate? |
|----------|---------|----------|
| `SQ.Create` | Squad table factory | Keep |
| `SQ.AddMember` / `SQ.RemoveMember` | Membership management | Keep |
| `SQ.Place` | Auto-place NPC into nearest squad | Keep |
| `SQ.AssignRoles` | Role assignment (LEADER, SUPPRESSOR, etc.) | Keep |
| `SQ.Broadcast` / `SQ.OnComm` | Squad comms system | Keep |
| `SQ.AnyoneEngaging` / `SQ.Suppressing` | Squad-level state queries | Keep |
| `SQ.FormationSlot` | Formation-relative position from leader | Keep |
| `SQ.UpdateFormation` | Formation type (WEDGE/LINE/etc) selection | Keep |
| `SQ.Plan` | Tactical planner (push/flank/hold/retreat) | **Migrate to squad_func/plan.lua** |

### What's broken

1. **COA priority**: Squad orders (`suppress_order.lua`, `flank_order.lua`, `bound_order.lua`, `separated.lua`) are in the Target list AFTER `engage_target.lua`. They never fire when an enemy is visible because `engage_target` wins first. All 4 also require `ctx.visible` — making them doubly unreachable.

2. **Minimal ctx in ooda.lua**: The `ctx` table passed to COAs is:
   ```lua
   { data, npc, enemy, rec, visible }
   ```
   Missing: `holdUnknown`, `dangerAvoid`, `squadCovering` — 3 COA files reference these as nil.

3. **No squad patrol**: `exec/pre_contact.lua` picks random patrol points per NPC. Squad members wander independently with only loose de-clumping.

4. **No formation during combat**: `FormationSlot` is only used in `exec/withdraw.lua:regroup`. No combat exec handler maintains formation spacing.

5. **All squad logic in one file**: `sv_squad.lua` is 471 lines mixing membership, comms, planning, and formation. No module boundary.

---

## New Module: `squad_func/`

```
server/squad_func/
  init.lua        — namespace CAI.SquadFunc, loader
  plan.lua        — tactical planner (replaces SQ.Plan logic)
  patrol.lua      — squad patrol planner (single objective + formation routing)
  formation.lua   — formation state, spacing checks, slot calculation
  spatial.lua     — squad-shared spatial memory (merged enemy positions)
```

### squad_func/init.lua

```lua
CAI.SquadFunc = CAI.SquadFunc or {}
local SF = CAI.SquadFunc
```

Called from `sv_brain.lua` (or a new loader). Defines the namespace, then includes submodules.

### squad_func/plan.lua — Tactical planner

Replaces `SQ.Plan`'s decision body (lines 274-460 of sv_squad.lua). Runs every 0.5s timer like the current `SQ.Plan`.

**Logic moved over verbatim** from `SQ.Plan`:
- Battlefield pruning
- Role assignment (calls `SQ.AssignRoles`)
- Enemy count / morale / ammo / injured aggregation
- Squad plan selection: retreat / hold / push / flank / regroup
- Per-member flag setting: `suppressUntil`, `wantFlank`, `wantBound`, `squadPlan`
- Fire-team / maneuver-team bound target computation
- Stagger offset

**Changes from current SQ.Plan:**
- After computing `squad.plan`, also set a `squad.objectivePos` field — the squad's collective movement target (last known enemy position, patrol objective, etc.)
- Store `squad.lastContactPos` — where the squad last had enemy contact (for patrol routing)

### squad_func/patrol.lua — Squad patrol planner

New module. Runs per-squad when all members are in PRE_CONTACT (no combat).

**Objective selection (every 0.5s timer):**
```
If squad has a patrol objective and it hasn't been reached:
  → keep current objective
Else:
  → pick a new objective from CAI.Battlefield.GetPatrolPoints(squad, leaderPos, RADIUS)
  → if none found, pick a random nav point within RADIUS of leader
  → if still none, fall back to current leader position (hold formation)
```

**Per-member routing:**
- The squad patrol planner sets `squad.patrolPos` and `squad.patrolKey`
- Each member's OODA reads `squad.patrolPos` via `ctx` (if in PRE_CONTACT and not searching/investigating)
- Leader: moves to `squad.patrolPos` directly
- Followers: compute their formation slot relative to leader's current position + formation-relative offset toward patrol objective

**exec/pre_contact.lua changes:**
- When in a squad with an active patrol objective AND the NPC is a follower:
  - Compute `FormationSlot(squad, idx)` relative to leader
  - `MoveTo(formationSlot, "walk")`
- Leader uses the squad patrol objective as patrol target
- When not in a squad: keep current independent patrol logic

### squad_func/formation.lua — Formation state

Migrates `SQ.FormationSlot` and `SQ.UpdateFormation` logic from sv_squad.lua. Adds:

**PositionSpacing check:**
```lua
function SF.PositionSpacing(data, pos, minDist)
    local squad = data.squad
    if not squad then return true end
    for _, m in ipairs(squad.members) do
        if IsValid(m) and m ~= data.ent then
            if m:GetPos():DistToSqr(pos) < minDist * minDist then
                return false  -- too close to another member
            end
        end
    end
    return true
end
```

**FormationCheck helper:** Returns true if NPC is >FormationBreakRadius from ALL squad members (cohesion check):

```lua
function SF.FormationCheck(data)
    local squad = data.squad
    if not squad or #squad.members <= 1 then return true end
    local radius = CAI.Config.SquadTactics.FormationBreakRadius or 600
    local radiusSq = radius * radius
    for _, m in ipairs(squad.members) do
        if IsValid(m) and m ~= data.ent then
            if data.ent:GetPos():DistToSqr(m:GetPos()) < radiusSq then
                return true  -- at least one squadmate within range
            end
        end
    end
    return false  -- isolated
end
```

Called from exec handlers (bound, direct_fire) every OODA tick. When false, the NPC sets `planPending` to force a re-plan that SquadOrder's `separated` will catch.

**SquadCenterOfMass helper:**
```lua
function SF.SquadCenterOfMass(squad, filterSelf, maxDist)
    local count, acc = 0, Vector()
    for _, m in ipairs(squad.members) do
        if IsValid(m) and (not filterSelf or m ~= filterSelf) then
            local d = maxDist and filterSelf and filterSelf:GetPos():DistToSqr(m:GetPos()) or 0
            if not maxDist or d < maxDist * maxDist then
                acc = acc + m:GetPos()
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    return acc / count
end
```

**Clustering prevention for exec handlers:**
- `exec/engage.lua`: At end of direct_fire path, if in a squad and another member is within 200 units, nudge sideways
- `exec/cover.lua`: When picking cover, reject positions too close to other squad members; prefer positions within mutual support range (200-500 units of at least one ally)

### squad_func/spatial.lua — Squad-shared spatial memory

**Squad enemy map merge:**
- Each think tick (or every 0.5s via the squad timer), each NPC writes its freshest enemy position to a shared map on the squad object:
  ```lua
  if not squad.sharedEnemies then squad.sharedEnemies = {} end
  local enemy, rec = CAI.Memory.FreshestEnemy(data)
  if rec then
      squad.sharedEnemies[data.ent] = { pos = rec.pos, t = CurTime(), enemy = enemy }
  end
  ```
- `CAI.SquadFunc.FreshestEnemy(squad)` returns the most recent shared enemy across all members
- NPCs can read `squad.sharedEnemies` for zero-latency enemy sharing

**Integration:**
- `CAI.Target.Evaluate` could prefer squad-shared enemy over individual memory
- `ooda.lua` ctx could include `squadEnemy = SF.FreshestEnemy(squad)`

This is optional/lowest-priority — the existing comms-based sharing works with latency. Mark as **Phase 2** if desired.

---

## COA Architecture Changes

### New evaluation order

```lua
-- ooda.lua
local phase, intent, duration, reason

-- 1. SquadOrder (role-based, highest priority)
for _, coa in ipairs(BR.COA.OODA.SquadOrder) do
    phase, intent, duration, reason = coa(ctx)
    if phase then break end
end

-- 2. PreTarget (emergency, needs squad override override)
if not phase then
    for _, coa in ipairs(BR.COA.OODA.PreTarget) do
        phase, intent, duration, reason = coa(ctx)
        if phase then break end
    end
end

-- 3. Target (individual decision)
if not phase then
    for _, coa in ipairs(BR.COA.OODA.Target) do
        phase, intent, duration, reason = coa(ctx)
        if phase then break end
    end
end
```

### SquadOrder COA channel

New channel in `decide.lua`:

```lua
BR.COA.OODA.SquadOrder = {}

include(DIR .. "suppress_order.lua")  -- now inserts into SquadOrder
include(DIR .. "flank_order.lua")     -- now inserts into SquadOrder
include(DIR .. "bound_order.lua")     -- now inserts into SquadOrder
include(DIR .. "separated.lua")       -- now inserts into SquadOrder
```

### SquadOrder COA changes

Each of the 4 files changes from `table.insert(BR.COA.Target, ...)` to `table.insert(BR.COA.SquadOrder, ...)` **and removes the `ctx.visible` guard:**

**suppress_order.lua:**
```lua
table.insert(BR.COA.SquadOrder, function(ctx)
    if ctx.data.suppressUntil and CurTime() < ctx.data.suppressUntil then
        return CAI.PHASE.ENGAGE, "suppress", 3, "squad_suppress_order"
    end
end)
```

**flank_order.lua:**
```lua
table.insert(BR.COA.SquadOrder, function(ctx)
    if ctx.data.wantFlank then
        ctx.data.wantFlank = nil
        return CAI.PHASE.MANEUVER, "flank", 4, "squad_flank_order"
    end
end)
```

**bound_order.lua:**
```lua
table.insert(BR.COA.SquadOrder, function(ctx)
    if ctx.data.wantBound and ctx.data.boundTarget then
        ctx.data.wantBound = nil
        return CAI.PHASE.MANEUVER, "bound", 3, "squad_bound_order"
    end
end)
```

**separated.lua:**
```lua
table.insert(BR.COA.SquadOrder, function(ctx)
    local data, npc = ctx.data, ctx.npc
    if not data.squad or not IsValid(data.squad.leader) then return end
    if data.squad.leader == npc or data.role == CAI.ROLE.FLANKER then return end
    local radius = CAI.Config.SquadTactics.FormationBreakRadius or 600
    if npc:GetPos():DistToSqr(data.squad.leader:GetPos()) <= radius * radius then return end
    -- Don't regroup if actively engaging a nearby enemy
    local enemyRange = ctx.enemy and npc:GetPos():Distance(ctx.enemy:GetPos()) or math.huge
    if enemyRange <= CAI.WeaponIntel.OwnRange(npc) then return end
    return CAI.PHASE.WITHDRAW, "regroup", 4, "separated_from_squad"
end)
```

### Target COA list (reduced)

After removing the 4 squad files, the Target list is:

```lua
include(DIR .. "pinned.lua")
include(DIR .. "engage_target.lua")
include(DIR .. "lost_target_coa.lua")
include(DIR .. "squad_aware.lua")
include(DIR .. "pre_contact.lua")
```

### PreTarget (unchanged)

```lua
include(DIR .. "flank_protect.lua")
include(DIR .. "melee_threat.lua")
include(DIR .. "morale_break.lua")
include(DIR .. "panic.lua")
include(DIR .. "room_clear_coa.lua")
```

### Richer ctx for all COAs

```lua
local ctx = {
    data = data, npc = npc,
    enemy = enemy, rec = rec, visible = visible,
    holdUnknown = CAI.CVBool("cai_hold_unknown"),
    dangerAvoid = CAI.CVBool("cai_danger_avoid"),
    squadCovering = data.squad and function()
        return CAI.Squad.AnyoneEngaging(data.squad, npc)
            or CAI.Squad.Suppressing(data.squad, npc)
    end or function() return false end,
}
```

Note: `squadCovering` creates a new closure each OODA tick. Acceptable for now — optimize only if profiling shows overhead.

---

## Exec Handler Changes

### exec/pre_contact.lua (patrol only)

When in a squad with an active patrol objective, REPLACE individual patrol logic:

```lua
local squad = data.squad
if intent == "patrol" and squad and squad.patrolPos then
    if npc == squad.leader then
        -- Leader moves to patrol objective
        if data.moveTarget and not CAI.Nav.Arrived(data, 80) then return end
        CAI.Nav.MoveTo(data, squad.patrolPos, "walk")
    else
        -- Follower computes formation slot relative to leader
        local idx = CAI.SquadFunc.SquadIndex(squad, npc)
        local slot = idx and CAI.Squad.FormationSlot(squad, idx)
        if slot then
            CAI.Nav.MoveTo(data, slot, "walk")
        end
    end
    return
end
```

When NOT in squad or no squad patrolPos: use current independent patrol logic.

### exec/engage.lua (formation spacing)

At the end of the `direct_fire` path (after line ~510, before returning), add:

```lua
-- Squad spacing: avoid clustering
if data.squad then
    local minDist = CAI.Config.SquadTactics.MinSpacing or 150
    for _, m in ipairs(data.squad.members) do
        if IsValid(m) and m ~= npc then
            local dSq = npc:GetPos():DistToSqr(m:GetPos())
            if dSq < minDist * minDist then
                local away = (npc:GetPos() - m:GetPos()):GetNormalized()
                local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, minDist)
                if dest then CAI.Nav.MoveTo(data, dest, "run") end
                break
            end
        end
    end
end
```

### exec/withdraw.lua (squad-aware retreat)

Replace the individual `awayFromEnemies()` helper with a squad-aware direction that blends away-from-enemies with toward-allies:

```lua
local function retreatDirection(data, npc)
    -- Push away from all known enemies (existing logic)
    local push = Vector()
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and CAI.Util.Alive(ent) and rec.pos then
            local v = npc:GetPos() - rec.pos
            v.z = 0
            local len = v:Length()
            if len > 1 then push = push + v * (1 / len) end
        end
    end
    push.z = 0

    -- Pull toward squad center of mass
    local pull = Vector()
    local center = data.squad and CAI.SquadFunc.SquadCenterOfMass(data.squad, npc, 2000)
    if center then
        pull = center - npc:GetPos()
        pull.z = 0
    end

    -- Blend: 70% away from enemies, 30% toward allies
    local combined
    if push:LengthSqr() > 1 then
        push:Normalize()
        if pull:LengthSqr() > 1 then
            pull:Normalize()
            combined = push * 0.7 + pull * 0.3
        else
            combined = push
        end
    elseif pull:LengthSqr() > 1 then
        combined = pull
    else
        return nil
    end
    combined.z = 0
    return combined:GetNormalized()
end
```

Replace all calls to `awayFromEnemies(data, npc)` with `retreatDirection(data, npc)` throughout `withdraw.lua`. The fallback escape direction (line 80-83) and `safeRetreat` validation already work with any direction vector — no other changes needed.

**Regroup during retreat** — when in a squad and no immediate enemy threat, the existing `regroup` intent (line 213) already uses `FormationSlot` for squad-relative positioning. No change needed.

### exec/maneuver.lua (formation cohesion during bound)

During bound movement, the maneuver team drifts laterally while fire team suppresses. Without a formation check, bounders can isolate 400+ units from squad — easy picking.

**Bound path** (line 148-189), check formation cohesion before each movement tick:

```lua
if data.phaseIntent == "bound" then
    -- Formation cohesion: abort bound if isolated from squad
    if data.squad and not CAI.SquadFunc.FormationCheck(data) then
        data.boundTarget = nil
        data.boundArrived = nil
        data.planPending = "bound_too_far"
        return
    end
    -- ... rest of existing bound logic ...
```

When `FormationCheck` returns false (no squadmate within `FormationBreakRadius`), the bound target is cleared and `planPending` triggers a re-plan on the next OODA cycle. SquadOrder's `separated` then catches the NPC and issues `WITHDRAW/regroup`.

**Flank path** (line 102-146) intentionally deviates from formation — flankers are exempt. The 25s stale timer already bounds maximum separation. No cohesion check needed.

### exec/cover.lua (squad-aware cover)

**Spacing rejection** (after `FindBest` returns, before accepting cover):

```lua
if pos and data.squad then
    for _, m in ipairs(data.squad.members) do
        if IsValid(m) and m ~= npc and npc:GetPos():DistToSqr(m:GetPos()) < 150 * 150 then
            pos = nil  -- too close to squadmate, find different cover
            break
        end
    end
end
```

**Mutual support preference** — after spacing rejection, if pos is accepted but far from all squad members, try to nudge toward squad center:

```lua
if pos and data.squad and #data.squad.members > 1 then
    local closest = math.huge
    local center = CAI.SquadFunc.SquadCenterOfMass(data.squad, npc)
    for _, m in ipairs(data.squad.members) do
        if IsValid(m) and m ~= npc then
            local d = pos:DistToSqr(m:GetPos())
            if d < closest then closest = d end
        end
    end
    -- If no squadmate within 600 units, nudge cover toward squad center
    if closest > 600 * 600 and center then
        local dir = (center - pos):GetNormalized()
        dir.z = 0
        local nudged = CAI.Nav.SafeOffset(pos, dir, 300)
        if nudged then pos = nudged end
    end
end
```

---

## File Manifest

### New files (5)

| File | Lines | What it does |
|------|-------|-------------|
| `server/squad_func/init.lua` | ~15 | Namespace declaration, submodule loader |
| `server/squad_func/plan.lua` | ~200 | Tactical planner (migrated from SQ.Plan logic) |
| `server/squad_func/patrol.lua` | ~100 | Squad patrol objective planner + formation routing |
| `server/squad_func/formation.lua` | ~60 | Formation slot, update, spacing checks |
| `server/squad_func/spatial.lua` | ~80 | Squad-shared enemy map merge (Phase 2) |

### Modified files (12)

| File | Changes |
|------|---------|
| `sv_brain.lua` | Add `include` for `squad_func/init.lua` |
| `sv_squad.lua` | Remove `SQ.Plan` body, `SQ.FormationSlot`, `SQ.UpdateFormation` logic. Update timer (line 462) to call `CAI.SquadFunc.Plan(squad)`. Remove or redirect `Prof.WrapFn(SQ, "Plan")` |
| `decide.lua` | Add `BR.COA.OODA.SquadOrder = {}`, include 4 squad COAs in SquadOrder, remaining Target reduced |
| `ooda.lua` | Add SquadOrder iteration loop, enrich ctx with `holdUnknown`, `dangerAvoid`, `squadCovering` |
| `suppress_order.lua` | Change `Target` → `SquadOrder`, remove `ctx.visible` guard |
| `flank_order.lua` | Change `Target` → `SquadOrder`, remove `ctx.visible` guard |
| `bound_order.lua` | Change `Target` → `SquadOrder`, remove `ctx.visible` guard |
| `separated.lua` | Change `Target` → `SquadOrder`, remove `ctx.visible` guard |
| `exec/pre_contact.lua` | Add squad patrol branch (formation-keeping) |
| `exec/engage.lua` | Add squad clustering check + formation cohesion abort at end of direct_fire |
| `exec/maneuver.lua` | Add formation cohesion check during bound — abort if isolated from squad, triggers re-plan |
| `exec/withdraw.lua` | Replace `awayFromEnemies()` with squad-aware `retreatDirection()` blending away-from-enemies + toward-allies |
| `exec/cover.lua` | Add squad spacing rejection + mutual support range preference in cover selection |
| `squad_func/plan.lua` | Compute `squadIndex` for each member during plan tick (alongside role assignment) so formation slot lookup is O(1) |
| `squad_func/formation.lua` | Add `FormationCheck`, `SquadCenterOfMass`, `PositionSpacing` helpers for cohesion |

### Configuration additions

In `sh_config.lua`, add fields to the existing `C.SquadTactics` table (line 581):

```lua
    MinSpacing = 150,              -- minimum distance between squad members in combat
    PatrolFormation = true,        -- enable formation-keeping during patrol
    FormationBreakRadius = 600,    -- max distance from nearest squadmate before considered isolated; triggers regroup
```

---

## Migration Steps

### Step 1: Create squad_func/ module files
1. `squad_func/init.lua` — namespace + loader
2. `squad_func/plan.lua` — migrate SQ.Plan body
3. `squad_func/patrol.lua` — new squad patrol planner
4. `squad_func/formation.lua` — migrate SF.FormationSlot + UpdateFormation, add SpacingCheck
5. `squad_func/spatial.lua` — shared enemy map (Phase 2, skip for now)

### Step 2: Modify ooda.lua + decide.lua
6. Add SquadOrder channel to decide.lua COA tables
7. Add SquadOrder iteration loop to ooda.lua
8. Enrich ctx table with holdUnknown, dangerAvoid, squadCovering

### Step 3: Rewrite 4 squad COAs
9. suppres_order.lua → SquadOrder, remove visible guard
10. flank_order.lua → SquadOrder, remove visible guard
11. bound_order.lua → SquadOrder, remove visible guard
12. separated.lua → SquadOrder, remove visible guard

### Step 4: Update exec handlers
13. exec/pre_contact.lua — add squad patrol formation branch
14. exec/engage.lua — add clustering check + formation cohesion abort
15. exec/maneuver.lua — add formation cohesion check during bound (abort if isolated)
16. exec/withdraw.lua — replace `awayFromEnemies()` with `retreatDirection()` (blends away-from-enemies + toward-allies via SquadCenterOfMass)
17. exec/cover.lua — add spacing rejection + mutual support range preference

### Step 5: Clean up sv_squad.lua
18. Remove `SQ.Plan` body (lines 274-460), update timer to call `CAI.SquadFunc.Plan(squad)`, update/remove `CAI.Prof.WrapFn(SQ, "Plan")`
19. Remove `SQ.FormationSlot` (lines 233-242) and `SQ.UpdateFormation` (lines 244-272) — migrated to squad_func/formation.lua
20. Keep `SQ.Create`, `SQ.AddMember`, `SQ.RemoveMember`, `SQ.Place`, `SQ.AssignRoles`, `SQ.Broadcast`, `SQ.OnComm`, `SQ.AnyoneEngaging`, `SQ.Suppressing`

### Step 6: Add squadIndex to plan tick
21. In `CAI.SquadFunc.Plan`, after `SQ.AssignRoles(squad)`, iterate members and set `data.squadIndex = i` so formation slot lookup is O(1) without re-scanning `squad.members`

### Step 7: Syntax check + smoke test
22. `luac5.1 -p` on all changed files
23. Manual smoke test: spawn 4 NPCs of same faction, verify they patrol in formation, respond to squad orders, maintain spacing, bounders abort and regroup if isolated, retreating NPCs move toward squad center
