# CAI.FireAim — Bullseye Lifecycle Abstraction

## Problem

Bullseye creation, cleanup, and enemy-pointer management are scattered across 5 files
with inconsistent patterns. The stale-enemy race ("Asking LastKnownPosition for enemy
that's not in my memory!!") occurs because:

1. Tick cleanup runs AFTER exec — a multi-frame schedule from the previous tick still
   references the bullseye after it's removed.
2. There's no central authority for "when do we keep a position aim vs. aim at the real enemy."

## Solution

A single module `CAI.FireAim` that owns the entire "point the NPC's fire at a world
position" lifecycle. The bullseye entity becomes an internal implementation detail.

## API

```lua
CAI.FireAim.Aim(data, pos, ttl)
  -- Point NPC's fire at a world position.
  -- Creates/moves the bullseye, sets as enemy, updates engine memory.
  -- ttl (optional): auto-release after N seconds (used by Prefire at 1.2s).
  -- Replaces inline bullseye creation in Prefire and suppress handler.

CAI.FireAim.Stop(data)
  -- Release position aim: remove bullseye, clear enemy pointer to NULL.
  -- Replaces BR.StopSuppressing body (kept as thin wrapper for backward compat).

CAI.FireAim.ClearEnemy(data)
  -- Only clear the enemy pointer WITHOUT removing the bullseye entity.
  -- Called from SetPhase when leaving suppress phase to prevent stale-schedule lookups.

CAI.FireAim.Tick(data)
  -- Auto-cleanup. Runs BEFORE exec in think.lua.
  -- Releases if: no suppress phase AND no active TTL.
  -- If TTL expired and NPC still has bullseye as enemy → Release.
  -- If TTL expired and NPC acquired a real enemy → silently remove bullseye.
```

## Internal State

`data._fireAimUntil` (replaces `data.prefireUntil`) — set by `Aim` when ttl is provided,
cleared by `Stop`.

## Changes

| File | Change |
|------|--------|
| **NEW: `server/sv_fireaim.lua`** | ~40 lines: `Aim`, `Stop`, `ClearEnemy`, `Tick` |
| `state.lua:121-139` (Prefire) | Replace inline bullseye create → `CAI.FireAim.Aim(data, aim, 1.2)` |
| `state.lua:65-74` (StopSuppressing) | Replace body → `CAI.FireAim.Stop(data)` (thin one-line wrapper) |
| `state.lua:62` (SetPhase, end of function) | Add unconditionally: `CAI.FireAim.ClearEnemy(data)`. No conditional needed — `ClearEnemy` internally checks `data.suppBullseye and npc:GetEnemy() == data.suppBullseye`, so it's a no-op unless the enemy is literally the bullseye (which can only happen when leaving suppress). |
| `engage.lua:72-91` (suppress handler) | Replace inline bullseye create → `CAI.FireAim.Aim(data, aim)` |
| `think.lua:49-59` (cleanup block) | Move BEFORE exec (line 41), replace with `CAI.FireAim.Tick(data)` |
| `sv_manager.lua:114` (death cleanup) | Replace `if IsValid(data.suppBullseye) then data.suppBullseye:Remove() end` → `CAI.FireAim.Stop(data)` |
| `cai_init.lua` | Add `Server("server/sv_fireaim.lua")` |
| `sv_brain.lua:7` (doc comment) | Update comment to reflect moved functions |

## No-change callers (backward compat via `BR.StopSuppressing` wrapper)

All 8 `BR.StopSuppressing(data)` calls in:
- `engage.lua` (lines 9, 16, 26, 38, 45, 94)
- `lost_target_coa.lua` (line 13)

These remain untouched — `StopSuppressing` is now a one-liner calling `CAI.FireAim.Stop`.

## Subtleties

- **TTL override**: When the suppress handler calls `Aim(data, aim)` without a TTL after
  Prefire had previously set a TTL via `Aim(data, aim, 1.2)`, the TTL is cleared. This is
  correct — within the suppress phase, the squad-managed duration replaces the reflex TTL.
- **`_fireAimUntil` not cleared by `SetPhase`**: The TTL field is cleared explicitly by
  `Aim` (when called without ttl, it defaults to nil) and by `Stop`. It is NOT cleared
  by `SetPhase` — the Tick handles cleanup based on phase state, not an inline field wipe.

## Verification

- `luac5.1 -p` on all changed files
- Spawn NPCs, trigger suppression fire: observe bullseye creation
- Phase change away from suppress: no stale-enemy errors
- Prefire with TTL: auto-cleans up after 1.2s
- NPC death: bullseye cleaned up
- `sv_target.lua:61` (target eval suppression skip) unchanged — reads `data.suppBullseye` which is still set by `Aim`
