# Plan: Suppress Role Assignment

## Expected Fixes
1. **"Asking LastKnownPosition for enemy that's not in my memory!!"** — NPCs in suppress with visible enemies no longer go through the bullseye system, eliminating the engine error during firefight
2. **Incorrect suppression assignment** — Only the designated fraction of squad members enter suppress. The rest engage via direct fire, flank, or push COAs. No more "everyone suppresses" behavior.

## Problem
- All squad NPCs enter suppress even with visible enemies at close range
- `suppress_order.lua` has no visibility gate — runs in SquadOrder group, returns suppress whenever `suppressUntil` is set
- `lost_target_coa.lua` also checks `suppressUntil` in the Target group without a role gate — same bypass
- No squad-level coordination on how many NPCs should suppress vs engage directly

## Solution
Suppress is a squad-distributed role, not an individual free-for-all. Squad planning assigns the SUPPRESSOR role to a subset of members based on squad size. Only those NPCs enter suppress. The rest engage directly (flank, push, direct fire).

### Design decisions

1. **Visibility gate applies to everyone**, including designated SUPPRESSORs. Suppress in this plan means "fire at last-known position when you can't see the enemy." Covering fire against a visible enemy is out of scope.

2. **Solo NPCs bypass the role gate.** A solo NPC has no squad (or a 1-member squad), so the role check would block them from suppressing. The role gate includes an exception: `if ctx.data.squad and #ctx.data.squad.members > 1 and ...`.

3. **`lost_target_coa.lua` gets the same role gate** on its suppress sub-branch only, not on the investigate/search/cover branches.

4. **Two suppressors briefly overlapping** (due to role re-assignment before timer expiry) is acceptable.

### COA gates

#### `suppress_order.lua` (SquadOrder group)

```lua
table.insert(BR.COA.SquadOrder, function(ctx)
    if not IsValid(ctx.enemy) then return end
    if ctx.visible then return end
    if ctx.data.squad and #ctx.data.squad.members > 1
       and ctx.data.role ~= CAI.ROLE.SUPPRESSOR then return end
    if ctx.data.suppressUntil and CurTime() < ctx.data.suppressUntil then
        return CAI.PHASE.ENGAGE, "suppress", 3, "squad_suppress_order"
    end
end)
```

Four gates: (1) no enemy → skip, (2) visible → skip to direct fire, (3) non-suppressor in a multi-member squad → skip, (4) no `suppressUntil` or expired → skip.

#### `lost_target_coa.lua` (Target group)

Add the same role gate to the suppress sub-branch:

```lua
-- Inside lost_target_coa, the suppressUntil check:
if data.suppressUntil and CurTime() < data.suppressUntil then
    if data.squad and #data.squad.members > 1
       and data.role ~= CAI.ROLE.SUPPRESSOR then
        -- fall through to investigate/search/cover
    else
        return CAI.PHASE.ENGAGE, "suppress", 3, "squad_suppress_order"
    end
end
```

The downstream branches (investigate, search, cover) are unaffected — non-suppressors with no LOS fall through to them naturally.

### Squad planning: role distribution

The squad plan's tactical tick (`squad_func/plan.lua`) counts current SUPPRESSORs, checks combat state, then fills the gap:

```lua
local inCombat = false
local currentSuppressors = 0
for _, m in ipairs(squad.members) do
    local d = CAI.Manager.Get(m)
    if d then
        if d.combatTarget then inCombat = true end
        if d.role == CAI.ROLE.SUPPRESSOR then currentSuppressors = currentSuppressors + 1 end
    end
end
local maxSuppressors = math.max(1, math.floor(#squad.members * C.SquadTactics.SuppressorRatio))
```

- If `currentSuppressors < maxSuppressors` and `inCombat` is true: assign unassigned members (or ASSAULTER-role members) as SUPPRESSOR, set `suppressUntil`.
- If `currentSuppressors >= maxSuppressors`: remaining members get FLANKER, PUSHER, or ASSAULTER — no `suppressUntil` set.

No new trigger needed: `squad_func/plan.lua` already runs periodically. On each tick, it checks and adjusts.

### Config

`sh_config.lua` — add under `C.SquadTactics`:

```lua
SuppressorRatio = 0.33,  -- fraction of squad assigned as suppressors
```

### Implementation Order

| Step | What | Files |
|------|------|-------|
| 1 | Visibility + role gate | `suppress_order.lua` |
| 2 | Role gate on suppress sub-branch | `lost_target_coa.lua` |
| 3 | Config | `sh_config.lua` |
| 4 | Squad role distribution | `squad_func/plan.lua` |
| 5 | Bounding logic role gate | `squad_func/plan.lua` |

Steps 1-2 are independent and can be done in parallel. Step 3 must precede step 4 because `plan.lua` references `C.SquadTactics.SuppressorRatio`. Steps 4-5 both touch `plan.lua` and can be done together.

### Files Changed

| File | Change |
|------|--------|
| `suppress_order.lua` | Add `if ctx.visible then return end` + role gate with solo bypass |
| `lost_target_coa.lua` | Add role gate with solo bypass on the `suppressUntil` sub-branch |
| `sh_config.lua` | Add `C.SquadTactics.SuppressorRatio = 0.33` |
| `squad_func/plan.lua` | **New logic**: count current suppressors vs `maxSuppressors`, check `inCombat` state, assign SUPPRESSOR role to unassigned or ASSAULTER members to fill gap. **Existing bounding logic**: gate line 153 `d.suppressUntil` assignment behind role check — only set for SUPPRESSORs, not entire fireTeam. The current code only extends `suppressUntil` for existing SUPPRESSORs — it does not count them or assign the role dynamically. The entire counting + ratio check + role assignment block is new. |

### Backwards Compatibility

- **Solo NPCs** (no squad or squad size 1): role gate is skipped (solo bypass), they suppress via `suppressUntil` as before — no regression.
- **Small squads** (size 2-3): `maxSuppressors = 1` — one suppresses, rest engage directly.
- **Large squads** (size 8): `maxSuppressors = 2` — two suppress, six maneuver.
- **Non-suppressors with stale `suppressUntil` from OnComm broadcasts**: role gate blocks them from suppress_order. `lost_target_coa` also blocks them. They fall through to investigate/search/cover — correct behavior.
- **Bounding logic in plan.lua lines 133-156**: currently sets `suppressUntil` on entire fireTeam. Updated to only set it for SUPPRESSOR role members. Non-SUPPRESSOR fireTeam members skip it and proceed naturally.