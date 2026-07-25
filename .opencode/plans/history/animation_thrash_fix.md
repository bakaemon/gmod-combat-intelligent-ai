# Animation Thrash Fix: Phase & Schedule Stabilization

## Objective
Stop animation transition errors (running→standing, walking→shooting, etc.), schedule
failures (SCHED_HIDE_AND_RELOAD, SCHED_ESTABLISH_LINE_OF_FIRE), and shoot-idle flicker
by throttling phase changes and schedule calls at two levels: the OODA decision loop and
the engine schedule layer.

## Root Causes (Investigation 2025-07)
1. **33 direct `npc:SetSchedule()` calls across codebase**, many with zero cooldown --
   schedules fired multiple times per second. The most frequent offender is
   `SCHED_ESTABLISH_LINE_OF_FIRE` (12 call sites), followed by
   `SCHED_TAKE_COVER_FROM_ENEMY` (7 sites).
2. **`pinned.lua:45-46` triggers `COVER/reload` every OODA tick** when clip==0 -- the
   reload decider has no cooldown. The only throttle is `cover.lua:79`'s 3.5s
   `forceReloadAt` guard, but the *decision to try* happens every tick.
3. **Reflex urgency (`"urgent"` / `"attention"`) bypasses all phase commitment checks**
   in `SetPhase` (`state.lua:16-28`). Grenade dodge returns `"urgent"` when blast <1s
   away, suppression_jink returns `"attention"` when pinned. These are set every tick
   by `BR.Reflex` (think.lua:30) and trigger OODA re-evaluation (think.lua:35).
4. **Cover pop/duck cycle** (`cover.lua:103-135`) issues `SCHED_TAKE_COVER_FROM_ENEMY`
   on every duck transition, and `FireSchedule` (`SCHED_ESTABLISH_LINE_OF_FIRE`) on
   every pop. These flip every ~1-3s, conflicting with any active reload.
5. **`planPending` override window is too short** (`state.lua:14`): 0.5s before a
   `planPending` flag forces re-plan. Exec handlers set `planPending` freely on minor
   friction (no cover found, squad formation broken, etc.).
6. **`Unhandled animation event 3014`** -- Source engine bug (citizen model lacks pistol
   anim event). Not fixable in Lua, but frequency is proportional to
   `SCHED_ESTABLISH_LINE_OF_FIRE` call rate.

## Changes

### 1. Global schedule cooldown via `Entity.SetSchedule` patch (`sv_brain.lua`)
Patch `Entity.SetSchedule` to check a per-NPC cooldown before issuing any schedule to
a CAI-controlled NPC. Covers all 33 call sites with zero code changes to exec handlers.
SCHED_RELOAD is exempted so the reload always works. Additionally, when a reload is in
progress (`data._reloadingAt`), all non-reload schedules are blocked for 1.5s to
prevent mid-animation interruption.

```lua
local oldSetSched = Entity.SetSchedule
function Entity:SetSchedule(sched)
    local data = CAI.Manager.NPCs[self]
    if not data then return oldSetSched(self, sched) end

    -- Always allow SCHED_RELOAD through.
    if sched == SCHED_RELOAD then
        data.lastSchedAt = CurTime()
        return oldSetSched(self, sched)
    end

    -- Block non-reload schedules while a reload animation is in progress.
    if data._reloadingAt and CurTime() - data._reloadingAt < 1.5 then
        return
    end

    -- Generic schedule throttle: no more than once per SchedCooldown.
    if data.lastSchedAt and CurTime() - data.lastSchedAt < (CAI.Config.Engage.SchedCooldown or 0.2) then
        return
    end

    data.lastSchedAt = CurTime()
    return oldSetSched(self, sched)
end
```

Non-CAI entities pass through unmodified (the `CAI.Manager.NPCs[self]` guard).

### 2. Phase change throttle (`ooda.lua`)
Skip OODA re-evaluation if phase changed within `C.OODA.PhaseCooldown` seconds and
no urgent reflex is active. This prevents the SquadOrder + urgency combo from forcing
re-plans every tick:

```lua
-- At top of BR.OODA, before any COA iteration
local urgency = data.reflex and data.reflex.urgency
if not data.planPending and not (urgency == "urgent") then
    if CurTime() - (data.phaseSince or 0) < CAI.Config.OODA.PhaseCooldown then
        return
    end
end
```

The `planPending` bypass ensures the NPC can still react when stuck. The `urgent`
bypass ensures immediate threats (grenade blast <1s) still force re-plan.

### 3. Increase `planPending` override window + bypass fix (`state.lua`)
Change the hardcoded `0.5` on line 14 to `CAI.Config.OODA.PhaseCooldown` AND add an
`overrideCommitment` path when `planPending` triggered the OODA call.

When OODA is triggered by `planPending` (not just plan expiry), OODA passes
`overrideCommitment = true` to SetPhase. This ensures that when an exec handler
explicitly requests re-plan via `planPending`, the commitment check does not silently
consume the flag.

**In OODA:** When calling `BR.SetPhase`, pass `true` for `overrideCommitment` if
`data.planPending` was set (the check already runs at the top — just save the flag
before clearing it):

```lua
-- ooda.lua line 59 (before BR.SetPhase call)
local hadPending = data.planPending ~= nil
BR.SetPhase(data, phase, intent, reason, hadPending)
```

**In state.lua:** The `overrideCommitment` parameter already exists (line 3:
`function BR.SetPhase(data, newPhase, intent, reason, overrideCommitment)`).
The `planPendingStuck` on line 14 already checks both `planPending` and
`CurTime() - data.phaseSince > 0.5`. With the change to 1.5s, the `0.5` becomes
`CAI.Config.OODA.PhaseCooldown`:

```lua
local planPendingStuck = planPending and (CurTime() - data.phaseSince > CAI.Config.OODA.PhaseCooldown)
```

No other changes needed in SetPhase — the existing `overrideCommitment` path (checked
on lines 16 and 22) already bypasses both the commitment check and the
planPendingStuck check when true.

This means a phase must run for 1.5s before `planPending` can force a re-plan on its
own (was 0.5s), BUT when OODA was specifically triggered by `planPending` and finds a
valid new phase, the overrideCommitment flag ensures the change actually takes effect.

### 4. Move reload out of phase system: empty-mag reflex + tactical reload in exec

Two distinct reload cases that share no phase management:

#### 4a. Empty-mag reload (reaction layer)

New reflex in `react/reflexes/reload_reflex.lua` — when `Clip1() == 0` and not
already reloading, issue `SCHED_RELOAD` directly and set `data._reloadingAt` to
protect from interruption. No phase change, no bias, no urgency.

```lua
local BR = CAI.Brain

table.insert(BR.ReflexHandlers, function(data, dt)
    local npc = data.ent
    local wep = npc:GetActiveWeapon()
    if not IsValid(wep) or not wep.Clip1 or wep:Clip1() > 0 then return end
    local reloading = npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_RELOAD)
    if reloading then return end
    data._reloadingAt = CurTime()
    npc:SetSchedule(SCHED_RELOAD)
end)
```

**Removed from phase system:**
- `pinned.lua:44-47`: remove the `Clip1() == 0` → `COVER/reload` return
- `cover.lua:75-98`: remove the `reloading_cover` handler (empty-mag reload)
- `post_contact.lua:6-11`: remove direct `SCHED_RELOAD` call

#### 4b. Tactical reload (exec opportunistic)

A low-mag reload when the weapon can still fire. This is not a reflex — it is a
tactical choice that should only happen when the NPC is already safe. Each exec
handler checks opportunistically, using `_tacticalReloadAt` to self-throttle and
`_reloadingAt` to protect the animation from interruption:

```lua
local wep = npc:GetActiveWeapon()
if IsValid(wep) and wep.Clip1 and wep:Clip1() > 0 and wep:Clip1() < (wep.GetMaxClip1 and wep:GetMaxClip1() or wep:Clip1()) * 0.3 then
    local reloading = npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_RELOAD)
    if not reloading and CurTime() > (data._tacticalReloadAt or 0) then
        data._tacticalReloadAt = CurTime() + 2.0
        data._reloadingAt = CurTime()
        npc:SetSchedule(SCHED_RELOAD)
    end
end
```

Placement:
- **cover.lua**: inside the "arrived at cover" block (line 100), after the duck/pop
  cycle (after line 135). The NPC is safely behind cover, reload runs during the
  duck hold. When done, the next pop cycle fires naturally.
- **engage.lua (suppress sub-phase, lines 6-123)**: at the end of the suppress block,
  before the final return. The NPC is in a safe fire-at-pos pattern behind cover.
- **engage.lua (non-visible-enemy branches, lines 478-517)**: at the start of each
  branch, before the movement or fire schedule. Reloading before advancing or
  backing off is safer than doing it mid-maneuver.

The `Entity.SetSchedule` patch exempts `SCHED_RELOAD` and blocks all other schedules
while `_reloadingAt < 1.5s`, so the reload animation is never interrupted. Neither
`_reloadingAt` nor `_tacticalReloadAt` is cleared by `SetPhase` — they expire
naturally via their time-based guards.

### 5. Config additions (`sh_config.lua`)
Add the new config values:

```lua
C.OODA = {
    PhaseCooldown = 1.5,  -- minimum seconds before phase can change (state.lua + ooda.lua)
}

-- Under C.Engage (existing section at lines 67-76):
SchedCooldown = 0.2,   -- minimum gap between SetSchedule calls (Entity.SetSchedule patch)
```

Placement: `C.OODA` goes near the top after `CAI.ROLE` / `C.NPCClasses`. The
`C.Engage` additions go inside the existing block at lines 67-76.

## Files touched

| File | Change |
|------|--------|
| `server/sv_brain.lua` | Add `Entity.SetSchedule` patch (with SCHED_RELOAD bypass) |
| `server/brain_func/ooda.lua` | PhaseCooldown guard at top; pass `overrideCommitment=true` to SetPhase when `planPending` triggered OODA |
| `server/brain_func/state.lua` | line 14: hardcoded 0.5 → `C.OODA.PhaseCooldown` |
| `server/brain_func/decide/pinned.lua` | Remove lines 44-47 (clip==0 → `COVER/reload`) |
| `server/brain_func/exec/cover.lua` | Remove lines 75-98 (reloading_cover handler); add tactical reload check after duck/pop cycle inside "arrived at cover" block |
| `server/brain_func/exec/engage.lua` | Add tactical reload check in suppress sub-phase and non-visible-enemy branches |
| `server/brain_func/exec/post_contact.lua` | Remove lines 6-11 (direct SCHED_RELOAD call) |
| `server/brain_func/react/reflexes/reload_reflex.lua` | **New file** — reflex that calls `SCHED_RELOAD` when clip empty |
| `server/brain_func/react.lua` | Add `include("reflexes/reload_reflex.lua")` after suppression_jink |
| `shared/sh_config.lua` | Add `C.OODA.PhaseCooldown`, `C.Engage.SchedCooldown` |

**Explicitly NOT touched** (the `Entity.SetSchedule` patch covers all schedule-related
thrashing in these):
- `exec/engage.lua` — all 12+ SetSchedule calls are throttled by the global patch
- `react/retaliate.lua` — SetSchedule call throttled by the global patch
- `state.lua` FireSchedule/Prefire — SetSchedule calls throttled by the global patch

## Verification
- `luac5.1 -p` on all changed files
- In-game: observe citizen/combine NPCs in combat for animation errors, reload cycling,
  schedule failures
- Check that CAI NPCs still fire, take cover, and reload (behavior should be identical
  except no schedule issued faster than once per `SchedCooldown`)
