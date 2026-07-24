# OODA Combat Architecture — Implementation Plan

## Principle

Replace the polling state machine with a three-tier OODA-driven architecture. Key insight: an NPC can execute a high-level plan while simultaneously reacting to immediate threats — the reaction biases movement but doesn't cancel the plan.

**No runtime compatibility bridge.** A `cai_ooda_mode` convar allows dev-time toggling (server restart required), but both paths are never wired simultaneously in production. This is an atomic cut-over.

---

## Audit References (Pre-Migration Inventory)

### Current state architecture

```
CAI.STATE = { IDLE=0, PATROL=1, ENGAGE=2, COVER=3, FLANK=4, SUPPRESS=5,
               SEARCH=6, RETREAT=7, INVESTIGATE=8, REGROUP=9,
               ROOM_CLEAR=10, BOUNDED=11 }
BR.Exec[0..11]  — per-state exec handlers (12 files)
BR.COA.PreTarget[1..8] + BR.COA.Target[1..10]  — COA cascade (18 files)
```

### All data.state/CAI.STATE references by file

**SUBSYS (need updating)**:

| File | Lines | What it does | Complexity |
|------|-------|-------------|------------|
| `state.lua` | 6,37,38,55,58 | SetState def, state write, COVER/PATROL exit checks | High |
| `think.lua` | 46-48,56,68,73 | redispatch loop, Exec lookup, SUPPRESS cleanup | High |
| `sv_squad.lua` | 136,137,141,143,159,160,161,166,169,181,185,204,205,218,333 | 9 state checks, 3 SetState calls, 3 d.state reads on other NPCs | High |
| `sv_debug.lua` | 30,52,118,119 | state read, net.WriteUInt(5), STATE_NAMES lookup, state age | Medium |
| `sv_sound.lua` | 45,53 | state check (IDLE/PATROL), SetState to INVESTIGATE | Low |
| `sv_morale.lua` | 36,88,91 | state checks (IDLE/PATROL), SetState to INVESTIGATE | Low |
| `sv_target.lua` | 60 | state check (SUPPRESS) for bullseye guard | Low |
| `sv_darkness.lua` | 101 | state check (!IDLE) for darkness vision | Low |
| `sv_cover.lua` | 238 | SetState to COVER (cover_blown_relocate) | Low |
| `perceive.lua` | 25 | state check (COVER) for forceRecover | Low |
| `react/flinch.lua` | 138,184 | state checks (SUPPRESS, ENGAGE) for legacy flinch | Low |
| `sv_manager.lua` | 44 | CAI.STATE.IDLE in data init | Low |
| `sv_brain.lua` | 7,11,20,22 | comments only, no runtime impact | None |

**DECIDE files (to be deleted — 18 files)**:

All return `CAI.STATE.*` values. Some also read `data.state` for decision logic:
- `engage.lua:29-30` — reads data.state ==/!= CAI.STATE.COVER for cover-stuck detection
- `cover_hold.lua:20-22` — reads data.state to check "passive" states
- `squad_aware.lua:32-46` — reads data.state for commitment scoring

**EXEC files (to be deleted — 12 files)**:

30 `SetState` calls across 10 files:
- `suppress.lua` — 5 calls (COVER, ENGAGE, SEARCH)
- `flank.lua` — 5 calls (ENGAGE, COVER, SEARCH)
- `room_clear.lua` — 5 calls (PATROL, ENGAGE)
- `regroup.lua` — 4 calls (PATROL, ENGAGE)
- `bounded.lua` — 3 calls (COVER, REGROUP, ENGAGE)
- `cover.lua` — 2 calls (ENGAGE, REGROUP)
- `search.lua` — 2 calls (PATROL)
- `investigate.lua` — 2 calls (ENGAGE, PATROL)
- `retreat.lua` — 2 calls (COVER, ENGAGE)
- `idle.lua`, `patrol.lua`, `engage.lua` — 0 calls each

**SHARED files**:
- `sh_config.lua:4-17` — CAI.STATE definition
- `sh_config.lua:19-20` — CAI.STATE_NAMES reverse mapping
- `sh_text.lua:3-14` — T.States text labels (indexed by STATE value)

**CLIENT files**:
- `cl_debug.lua:9` — net.ReadUInt(5) for state
- `cl_debug.lua:30-37` — STATE_COLORS (keyed by old STATE values 2-7)
- `cl_debug.lua:56,61` — color + name lookups

**Zero-dependency files** (no state references):
`sv_suppression.lua`, `sv_memory.lua`, `sv_navigation.lua`, `sh_net.lua`

---

## Reusability Analysis

### COA Files (decide/*.lua) — ~95% condition logic transfers verbatim

All decision conditions (suppression checks, distance checks, morale, weapon intel, squad state, melee threat scans, probability rolls) copy across unchanged. Only three categories change:

| Change type | Count | Details |
|-------------|-------|---------|
| `data.state` → `CAI.PhaseIs()` | 3 files | `cover_hold.lua:20-22` (5 reads), `engage.lua:29-30` (2 reads), `squad_aware.lua:32-47` (5 reads) |
| Return value mapping | 16 files | Every `CAI.STATE.X` return becomes `PHASE.Y, "intent", duration`. See full map below. |
| Duration added | all | New 3rd return value `commitment_duration` (seconds) |

**Full state→phase return mapping**:

| Old return | New return | Files |
|------------|------------|-------|
| `CAI.STATE.PATROL` | `PHASE.PRE_CONTACT, "patrol", 5` | patrol.lua |
| `CAI.STATE.INVESTIGATE` | `PHASE.PRE_CONTACT, "investigate", 4-5` | lost_target.lua, squad_aware.lua |
| `CAI.STATE.SEARCH` | `PHASE.PRE_CONTACT, "search", 4` | lost_target.lua |
| `CAI.STATE.ENGAGE` | `PHASE.ENGAGE, var, 2-2.5` | engage.lua (9 variants), melee_chase.lua, melee_swarm.lua |
| `CAI.STATE.SUPPRESS` | `PHASE.ENGAGE, "suppress", 3` | lost_target.lua, squad_suppress_order.lua |
| `CAI.STATE.COVER` | `PHASE.COVER, var, 2-2.5` | cover_hold.lua, engage.lua, lost_target.lua, squad_aware.lua |
| `CAI.STATE.FLANK` | `PHASE.MANEUVER, "flank", 1.5-4` | flank_protect.lua, flank.lua, lost_target.lua, melee_chase.lua, squad_flank_order.lua |
| `CAI.STATE.ROOM_CLEAR` | `PHASE.MANEUVER, "room_clear", 4` | room_clear.lua |
| `CAI.STATE.BOUNDED` | `PHASE.MANEUVER, "bound", 3` | squad_bound_order.lua |
| `CAI.STATE.RETREAT` | `PHASE.WITHDRAW, var, 3-5` | morale_broken.lua, morale_panic.lua, cover_hold.lua, engage.lua, melee_swarm.lua |
| `CAI.STATE.REGROUP` | `PHASE.WITHDRAW, "regroup", 4` | lost_target.lua, separated_from_squad.lua, squad_aware.lua |

**Deleted COAs** (2 files — handled by reflex):
- `emergency_relocate.lua` — `data.forceRecover` → reflex bias toward cover
- `grenade_scatter.lua` — `data.scatterUntil` → `data.reflex.grenadePos/grenadeUntil`

**All transient fields survive unchanged** (only grenade scatter moves under `data.reflex`): `data.flank`, `data.pinnedCover`, `data.coverBounces`, `data.lastEngageAt`, `data.investigatePos`, `data.suppressUntil`, `data.reinforceTarget`, `data.search`, `data.awaitAt`, `data.escapeCentroid`, `data.pbEnemy`, `data.coverSearchFailures`, `data.squadPlan`, `data.scatterUntil` → `data.reflex.grenadePos/grenadeUntil`. No other structural changes.

### Exec Files (exec/*.lua) — ~97% logic transfers verbatim

All movement, navigation, combat, schedule-setting, and squad coordination logic copies unchanged. Only changes are `SetState` → `planPending`:

| File | Lines | SetState calls | Convert to |
|------|-------|---------------|------------|
| `idle.lua` | ~3 | 0 | Copy verbatim to `exec/pre_contact.lua` |
| `patrol.lua` | 108 | 0 | Copy verbatim to `exec/pre_contact.lua` |
| `engage.lua` | 416 | 0 | Copy verbatim to `exec/engage.lua` |
| `search.lua` | 17 | 2 | `data.planPending = "nothing_to_search"/"search_over"` |
| `investigate.lua` | 33 | 2 | `data.planPending = "spotted"/"investigation_over"` |
| `cover.lua` | 119 | 2 | `data.planPending = "no_cover"/"reloaded_regroup"` |
| `retreat.lua` | 213 | 2 | `data.planPending = "reloading_cover"/"engage_target"` |
| `regroup.lua` | 46 | 4 | `data.planPending = "no_squad"/"spotted"/"reinforced"/"in_formation"` |
| `bounded.lua` | ~50 | 3 | `data.planPending = "no_bound"/"bound_done"/"push"` |
| `suppress.lua` | 126 | 5 | `data.planPending = "nothing"/"too_close"/"no_los"/"no_target"/"done"` |
| `flank.lua` | 171 | 5 | `data.planPending = "contact"/"unavailable"/"completed"/"arrived_nosearch"/"arrived"` |
| `room_clear.lua` | ~100 | 5 | `data.planPending = "no_door"/"enemy"/"timeout"/"cleared"/"error"` |

### Subsystem Files — 100% logic reuse

All subsystem logic (squad coordination, morale, sound, target, darkness, cover, perceive, react) transfers completely. Only equality checks against `CAI.STATE.*` remap to `CAI.PhaseIs()` calls. No behavioral logic changes.

---

## Three-Tier Architecture

| Tier | Name | Runs | Scope | Can change phase? |
|------|------|------|-------|-------------------|
| 1 | **Reflex** | Every think tick | Movement bias only. Sets urgency flags. | No |
| 2 | **OODA** | On plan expiry or urgent trigger | Picks new (phase, intent, duration). Commits. | Yes |
| 3 | **Exec** | Every think tick | Executes current phase + intent. Signals completion. | No |

### The flow

```
BR.Think(data, dt):
  1. OBSERVE: Perceive, memory fade, suppression decay, morale regen, proficiency, CheckStuck
     → early exit if !CAI.Util.Alive(npc)
  2. TIER 1 - REFLEX: BR.Reflex(data, dt)
     → movement bias only, no SetPhase
     → may set reflex.urgency flag (hierarchical: grenade > melee > suppression)
   3. TIER 2 - OODA: only if plan expired OR urgency is set OR planPending is set
     a. OBSERVE: CAI.Target.Evaluate
     b. ORIENT: build context table (enemy, visibility, suppression, morale, danger)
     c. DECIDE: run COA cascade → (phase, intent, duration, reason)
     d. COMMIT: SetPhase (if changed) + set plan.expiresAt
     e. Clear planPending
  4. TIER 3 - EXEC: BR.ExecPhase[data.phase](data, dt)
     → never calls SetPhase
     → sets data.planPending when work completes naturally
  5. Cleanup: prefire/bullseye expiry, health regen
```

### LOD awareness for reflex

Low-LOD NPCs (far away, think every 1-3s) need sub-second reflex for grenades.
- Reflex always runs regardless of LOD (cheap — only vector math + urgency flag)
- Grenade/melee threat detection hooks into the scheduler tick, not the think tick
- If reflex urgency reaches "urgent", force an immediate OODA cycle (skip LOD delay)

---

## Phase Enum (replaces CAI.STATE)

```
PHASE = {
    PRE_CONTACT = 0,   -- patrolling, searching, investigating, idle
    ASSESS      = 1,   -- brief evaluation after threat detection (1-3s)
    ENGAGE      = 2,   -- active firefight: direct_fire, suppress, point_blank
    MANEUVER    = 3,   -- moving under fire: flank, bound, room_clear, reposition
    COVER       = 4,   -- deliberate cover: hold, peek_shoot, reload, wait
    WITHDRAW    = 5,   -- breaking contact: tactical, flee, regroup
    POST_CONTACT = 6,  -- after fight: rearm, consolidate, listen
}
```

Each phase has an **intent** string. Valid intent values map to old state names:

| Phase | Valid Intents | Replaces old states |
|-------|--------------|---------------------|
| PRE_CONTACT | "patrol", "search", "investigate", "idle" | PATROL(1), SEARCH(6), INVESTIGATE(8), IDLE(0) |
| ASSESS | "assess", "evaluate" | — (new) |
| ENGAGE | "direct_fire", "suppress", "point_blank", "melee" | ENGAGE(2), SUPPRESS(5) |
| MANEUVER | "flank", "bound", "room_clear", "reposition" | FLANK(4), ROOM_CLEAR(10), BOUNDED(11) |
| COVER | "hold", "peek_shoot", "reload", "wait" | COVER(3) |
| WITHDRAW | "tactical", "flee", "regroup" | RETREAT(7), REGROUP(9) |
| POST_CONTACT | "rearm", "consolidate", "listen" | — (new) |

### Helper function

```lua
function CAI.PhaseIs(data, phase, intent)
    if data.phase ~= phase then return false end
    if intent and data.phaseIntent ~= intent then return false end
    return true
end
```

All old `data.state == CAI.STATE.X` checks become `CAI.PhaseIs(data, PHASE.Y, "intent")`.

---

## Data Model Changes

### New per-NPC fields (sv_manager.lua MG.Register)

```lua
data.phase = PHASE.PRE_CONTACT         -- replaces data.state
data.phaseIntent = "patrol"            -- NEW: sub-behavior within phase
data.prevPhase = nil                   -- replaces prevState
data.phaseSince = CurTime()            -- replaces stateSince
data.lastDecision = "registered"
data.plan = {
    expiresAt = CurTime() + 5,         -- when to next run OODA
    started = CurTime(),
    reason = "registered",
    committedUntil = CurTime() + 0.5,  -- minimum commitment (sunk-cost updated)
}
data.reflex = {
    bias = nil,                        -- { vec = Vector, until = number } accumulated movement bias
    urgency = nil,                     -- nil / "attention" / "urgent"
    grenadePos = nil,
    grenadeUntil = nil,
    emergencyCover = nil,
    emergencyUntil = nil,
    meleeThreatAt = nil,
}
data.planPending = nil                 -- set by exec or squad to trigger early OODA
```

`data.state`, `data.stateSince`, `data.prevState` are **removed**. Every old reference is updated.

### Data init migration

`MG.Register` (runs on NPC spawn) initializes the new fields. Existing NPCs on a running server will lack them — a **server restart or map change** is required. The entire AI relies on `data.phase`, so old NPCs without it will no-op (phase defaults to nil, exec handler does nothing) until restart.

---

## The Reflex Layer (react/ — modular)

`react.lua` is a module loader. Individual handlers live under `react/`:

```
server/brain_func/react.lua                 -- loader
server/brain_func/react/shared.lua          -- BR.IsCommitted + BR.UnderFire (both modes)
server/brain_func/react/reflexes/           -- BR.Reflex handlers (mode=1)
    grenade_dodge.lua                       -- dodge vector away from grenade
    melee_dodge.lua                         -- backpedal from melee threat
    suppression_jink.lua                    -- bias toward cover or away from fire
server/brain_func/react/flinch.lua          -- legacy BR.Flinch (mode=0)
```

Architecture: `BR.Reflex.Handlers[]` — each file does `table.insert(BR.Reflex.Handlers, fn(data, dt))`, returning `(bias_vec, urgency)` or nil. `BR.Reflex` iterates all handlers, accumulates bias vectors, and tracks the highest urgency level.

### Design rules
- Runs every think tick (including low-LOD)
- Produces only a movement bias vector + animation override
- Never calls SetPhase
- Can set `reflex.urgency` flag to influence next OODA cycle

### Actions handled
1. **Under-fire jinking** (existing Flinch logic for mode=0; suppression_jink for mode=1)
2. **Grenade dodge** — bias away from `reflex.grenadePos`
3. **Melee proximity dodge** — backpedal from nearest melee threat

### Urgency hierarchy (single winner per tick)

Priority order (highest wins):
1. Melee enemy within PointBlank → `"urgent"`
2. Grenade blast radius → `"urgent"` if within 1s of detonation, else `"attention"`
3. Suppression > PinnedAt → `"attention"`
4. Single shot received → `nil` (movement bias only)

"urgent" > "attention" > nil. `BR.Reflex` picks the highest across all handlers.

### Movement bias application
Bias is applied in `CAI.Nav.MoveTo`: planned destination + `reflex.bias.vec`
This is the key architectural change: reflex modifies *where* the NPC moves, not *what* the NPC plans to do.

### LOD handling for reflex
- Reflex itself runs every think tick (trivially cheap)
- Grenade dodge uses hooks from `sv_suppression.lua` to set `reflex.grenadePos/Until` immediately, not waiting for the next think tick
- If urgency reaches "urgent", an immediate OODA cycle is forced (skip LOD delay, overrides plan)

---

## The OODA Cycle (ooda.lua)

### COA registration

```lua
BR.COA = BR.COA or {}
BR.COA.PreTarget = BR.COA.PreTarget or {}   -- runs before target eval
BR.COA.Target = BR.COA.Target or {}         -- runs after target eval
```

Each COA file does:
```lua
table.insert(BR.COA.Target, function(ctx)
    if not condition then return end
    return PHASE.ENGAGE, "direct_fire", 2.5, "engage_target"
end)
```

Include order determines priority (first to return non-nil wins).

### COA signature
```
(ctx) → (phase, intent, commitment_duration, reason)  or  nil
```

ctx table:
```lua
{
    data, npc,
    enemy, rec, visible,
    suppressed = bool,
    panic = bool,
    morale = number,
    inDanger = bool, dangerInfo,
    enemyDist = number,
    weaponEmpty = bool,
    inMelee = bool, meleeCount, meleeDist,
}
```

### COA priority order

**PreTarget** (no enemy needed):
1. `morale_break.lua` — broken morale → (WITHDRAW, flee, 5s); if cornered (WITHDRAW, flee, 3s -> fallback to (ENGAGE, melee, 1s))
2. `panic.lua` — panicked coward or unarmed → (WITHDRAW, flee, 4s)
3. `flank_protect.lua` — keep existing flank alive → (MANEUVER, flank, 1.5s)
4. `melee_threat.lua` — swarmed by melee (non-melee NPCs) → (ENGAGE, point_blank, 2s) if can fight, else (WITHDRAW, flee, 3s)
5. `room_clear_coa.lua` — squad door clearing → (MANEUVER, room_clear, 4s)

**Target** (need combat target):
1. `pinned.lua` — suppressed → (COVER, hold, 2.5s) if cover and passive; (COVER, hold, 2.5s) if cover and passed roll; else (WITHDRAW, tactical, 3s). Respects "passive" states: if currently in combat phase, uses cached roll (4-7s) to prevent flapping.
2. `engage_target.lua` — visible enemy, normal engagement → (ENGAGE, direct_fire, 2.5s) or variants. Handles CQB push, rocket/shotgun avoidance, engagement starvation break, aggressive push, squad retreat.
3. `lost_target_coa.lua` — enemy valid, not visible → patience-based decision tree. Squad suppress → (ENGAGE, suppress, 3s); separated → (WITHDRAW, regroup, 4s); flanking → (MANEUVER, flank, 1.5s); close to LKP → (COVER, hold, 2s) or (PRE_CONTACT, investigate, 4s); far → (PRE_CONTACT, investigate, 5s); search enabled → (PRE_CONTACT, search, 4s); fallback → (COVER, wait, 2s)
4. `suppress_order.lua` — squad suppress order active → (ENGAGE, suppress, 3s)
5. `flank_order.lua` — squad flank order → (MANEUVER, flank, 4s)
6. `bound_order.lua` — squad bound order → (MANEUVER, bound, 3s)
7. `separated.lua` — visible enemy, leader > 700u away, out of range → (WITHDRAW, regroup, 4s)
8. `squad_aware.lua` — no enemy, squad pushing/flanking, hears battle → investigate/battle-cover decision with commitment scoring. Squads sounds with helpScore > commitment → (PRE_CONTACT, investigate, 5s)
9. `pre_contact.lua` — fallback → (PRE_CONTACT, patrol, 5s)

### Files to create in decide/
- `morale_break.lua` (replaces morale_broken.lua + morale_panic.lua)
- `panic.lua` (replaces morale_panic.lua panic path)
- `flank_protect.lua` (keep, update return signature)
- `melee_threat.lua` (replaces melee_swarm.lua)
- `room_clear_coa.lua` (replaces room_clear.lua)
- `pinned.lua` (replaces cover_hold.lua)
- `engage_target.lua` (replaces engage.lua + melee_chase.lua)
- `lost_target_coa.lua` (replaces lost_target.lua)
- `suppress_order.lua` (replaces squad_suppress_order.lua)
- `flank_order.lua` (replaces squad_flank_order.lua)
- `bound_order.lua` (replaces squad_bound_order.lua)
- `separated.lua` (replaces separated_from_squad.lua)
- `squad_aware.lua` (replaces squad_aware.lua + investigate.lua portion)
- `pre_contact.lua` (replaces patrol.lua + default fallback)

### Deleted (handled by reflex)
- `emergency_relocate.lua` → reflex bias toward nearby cover
- `grenade_scatter.lua` → reflex bias away from grenade

### Deleted (folded)
- `melee_swarm.lua`, `melee_chase.lua` → `melee_threat.lua` + `engage_target.lua`
- `flank.lua` → `flank_protect.lua`
- `squad_aware.lua` old → new `squad_aware.lua` with intent-based commitment

---

## Phase Handlers (exec/*.lua)

### Rule: NEVER call SetPhase
Instead, set `data.planPending = "reason_string"` to trigger early OODA on the next think tick.

### planPending timeout guard
If `SetPhase` rejects a transition (commitment not expired, not urgent), but `planPending` is set, the NPC would be stuck doing nothing. **Guard**: if the current phase has run for >0.5s and `planPending` is set, `SetPhase` allows the transition regardless of commitment. Uses `data.phaseSince` as proxy (not a dedicated `planPendingSince` timer) — acceptable because the guard is a safety net against deadlock, not precise timing.

### Mapping from old to new

| Old file | New file | SetState calls → planPending |
|----------|----------|------------------------------|
| exec/idle.lua | exec/pre_contact.lua | None (was no-op) |
| exec/patrol.lua | exec/pre_contact.lua | None (stays in phase) |
| exec/search.lua | exec/pre_contact.lua | 2 → planPending |
| exec/investigate.lua | exec/pre_contact.lua | 2 → planPending |
| exec/engage.lua | exec/engage.lua | Already clean (0 calls) |
| exec/suppress.lua | exec/engage.lua | 5 → planPending |
| exec/cover.lua | exec/cover.lua | 2 → planPending |
| exec/flank.lua | exec/maneuver.lua | 5 → planPending |
| exec/bounded.lua | exec/maneuver.lua | 3 → planPending |
| exec/room_clear.lua | exec/maneuver.lua | 5 → planPending |
| exec/retreat.lua | exec/withdraw.lua | 2 → planPending |
| exec/regroup.lua | exec/withdraw.lua | 4 → planPending |

### New exec files
- `exec/pre_contact.lua` — patrol, search, investigate, idle (merged from 4 old files)
- `exec/assess.lua` — brief evaluation phase, threat assessment
- `exec/engage.lua` — direct_fire, suppress, point_blank (merged from 2 old files)
- `exec/maneuver.lua` — flank, bound, room_clear, reposition (merged from 3 old files)
- `exec/cover.lua` — hold, peek_shoot, reload, wait
- `exec/withdraw.lua` — tactical retreat, flee, regroup (merged from 2 old files)
- `exec/post_contact.lua` — after fight cleanup, rearm

---

## Plan Commitment Model

```lua
data.plan.expiresAt = CurTime() + commitment_duration
data.plan.committedUntil = data.plan.expiresAt  -- SetPhase sets this
```

### Commitment durations (config: CAI.Config.Plan.PhaseDuration)

| Phase | Range | Notes |
|-------|-------|-------|
| PRE_CONTACT | 3-6s | Long, no pressure |
| ASSESS | 1-2.5s | Brief evaluation |
| ENGAGE | 1.5-3.5s | Combat commitment |
| MANEUVER | 2.5-5s | Positional movement |
| COVER | 1.5-3s | Moderate |
| WITHDRAW | 3-6s | Sticky, hard to interrupt |
| Default | 1.5s | Fallback |

### Sunk cost bonus

+0.3s per full second in same phase (integer floors), applied to `committedUntil` in SetPhase:
```lua
local sunkCost = math.floor(CurTime() - oldPhaseSince) * 0.3
data.plan.committedUntil = CurTime() + commitment_duration + sunkCost
```
Makes the NPC increasingly stubborn about plan changes over time.

### What overrides commitment
- `reflex.urgency == "urgent"` — immediate replan (ignores committedUntil)
- `reflex.urgency == "attention"` — allows phase change only if current plan is >50% expired
- `planPending` stuck for >0.5s — force override (deadlock guard)
- Normal plan expiry — standard OODA cycle

---

## SetPhase (rewrites state.lua)

```lua
function BR.SetPhase(data, newPhase, intent, reason, overrideCommitment)
    -- No-op if already in same phase+intent
    if data.phase == newPhase and data.phaseIntent == intent then return end
    
    -- Commitment check
    local committedUntil = data.plan and data.plan.committedUntil or 0
    local urgency = data.reflex and data.reflex.urgency
    local urgent = urgency == "urgent"
    local attention = urgency == "attention"
    local planPending = data.planPending
    local planPendingStuck = planPending and (CurTime() - data.phaseSince > 0.5)
    
    if not urgent and not attention and not planPendingStuck and not overrideCommitment then
        if CurTime() < committedUntil then
            -- Commitment still active, reject transition
            return
        end
    end
    -- "attention" allows phase change if current plan is >50% expired
    if attention and not urgent and not planPendingStuck and not overrideCommitment then
        local elapsed = CurTime() - data.phaseSince
        local total = committedUntil - data.phaseSince
        if elapsed < total * 0.5 then
            return
        end
    end
    
    -- Store previous phase + capture phaseSince before overwrite
    local oldPhaseSince = data.phaseSince or CurTime()
    data.prevPhase = data.phase
    
    -- Set new phase
    data.phase = newPhase
    data.phaseIntent = intent
    data.phaseSince = CurTime()
    data.lastDecision = reason
    
    -- Set commitment with sunk-cost bonus (use oldPhaseSince before it was overwritten)
    local defDuration = CAI.Config.Plan.PhaseDuration[newPhase] or 1.5
    local sunkCost = math.floor(CurTime() - oldPhaseSince) * 0.3
    data.plan.committedUntil = CurTime() + defDuration + sunkCost
    data.plan.expiresAt = data.plan.committedUntil
    data.plan.reason = reason
    
    -- Clear transient fields (same as current SetState)
    data.fighting = nil
    data.coverPhase = nil
    data.coverPhaseEnd = nil
    data.suppFaced = nil
    data.fleeSched = nil
    data.investFaced = nil
    data.retreatDest = nil
    data.ambush = nil
    data.meleePhase = nil
    data.moveTarget = nil
    data.moveIssuedAt = nil
    data.patrolTarget = nil
    if data.phase ~= PHASE.COVER then
        data.cover = nil
    end
    
    -- Clear planPending
    data.planPending = nil
    
    -- Clear urgency (OODA has responded)
    if data.reflex then data.reflex.urgency = nil end
end
```

---

## Grenade Handling (example of reflex > plan)

**Old**: Grenade → scatterUntil → grenade_scatter.lua COA → RETREAT state (clears everything)

**New**:
```
Tick 0: Grenade spawns, suppression hook sets data.reflex.grenadePos/Until
Tick 0: BR.Reflex runs → computes dodge vector away from grenade
         → applies as movement bias
         → sets urgency = "urgent" if within blast timer
         → NPC stays in current phase (e.g., ENGAGE)
         → NPC's movement is biased away from grenade while still fighting
Tick 0: urgency=="urgent" → immediate OODA cycle
         → COA checks: grenade still active?
         → If yes and still in danger: COA may choose WITHDRAW or MANEUVER
         → If grenade expired (dodge already moved NPC to safety): COA chooses normal behavior
```

The NPC dodges the grenade WITHOUT changing state on first tick. The dodge is a movement bias, not a state transition. OODA runs only if the threat persists.

---

## Squad Integration

Squad commands (`sv_squad.lua`) continue to set flags (`data.suppressUntil`, `data.wantFlank`, etc.):
- These flags are read **only during the OODA cycle**, not every tick
- Squad commands can also set `data.planPending = "squad_order"` to trigger early OODA
- The exec handler continues its current phase until the plan expires or planPending triggers

### Dual-mode pattern for all Phase 4 changes

Every subsystem update follows the same dual-mode guard pattern. State _checks_ become:

```lua
-- Single line in each subsystem:
if CAI.CVBool("cai_ooda_mode")
    and CAI.PhaseIs(data, PHASE.PRE_CONTACT, "idle")  -- mode=1
   or not CAI.CVBool("cai_ooda_mode")
    and data.state == CAI.STATE.IDLE                    -- mode=0
then
```

State _writes_ (SetState) become:

```lua
if CAI.CVBool("cai_ooda_mode") then
    data.planPending = "reason"    -- triggers OODA cycle
    data.plan.expiresAt = CurTime()
else
    BR.SetState(data, CAI.STATE.X, "reason")
end
```

### sv_squad.lua changes

| Location | Old | New (mode=0) | New (mode=1) |
|----------|-----|--------------|--------------|
| State checks (9 sites) | `data.state == STATE.X` | same (unchanged) | `CAI.PhaseIs(data, PHASE.Y, intent)` |
| `SetState(data, CAI.STATE.COVER)` | SetState | same | `planPending = "squad_cover"` |
| `SetState(data, CAI.STATE.REGROUP)` | SetState | same | `planPending = "squad_regroup"` |
| `SetState(data, CAI.STATE.REGROUP, "help_request")` | SetState | same | `planPending = "squad_help"` |

---

## Other Subsystem Updates (Dual-Mode)

Each subsystem wraps state references in a dual-mode guard. Mode=0 keeps the exact original code; mode=1 uses the new PhaseIs/planPending pattern.

### sv_sound.lua
- Line 43: `if data.state >= IDLE and data.state <= PATROL` → dual-mode:
  - mode=0: same
  - mode=1: `if CAI.PhaseIs(data, PHASE.PRE_CONTACT)`
- Line 51: `SetState(data, INVESTIGATE, "heard_sound")` → dual-mode:
  - mode=0: same
  - mode=1: `planPending = "heard_sound"`, `plan.expiresAt = CurTime()`

### sv_morale.lua
- Lines 34,86: `data.state == IDLE or data.state == PATROL` → dual-mode:
  - mode=0: same
  - mode=1: `CAI.PhaseIs(data, PHASE.PRE_CONTACT)`
- Line 89: `SetState(data, INVESTIGATE, "squadmate_down")` → dual-mode:
  - mode=0: same
  - mode=1: `planPending = "squadmate_down"`, `plan.expiresAt = CurTime()`

### sv_target.lua
- Line 58: `data.state == CAI.STATE.SUPPRESS` → dual-mode:
  - mode=0: same
  - mode=1: `CAI.PhaseIs(data, PHASE.ENGAGE, "suppress")`

### sv_darkness.lua
- Line 99: `data.state ~= IDLE` → dual-mode:
  - mode=0: same
  - mode=1: `data.phase ~= PHASE.PRE_CONTACT or data.phaseIntent ~= "idle"`

### sv_cover.lua
- Line 236: `SetState(data, COVER, "cover_blown_relocate")` → dual-mode:
  - mode=0: same
  - mode=1: `planPending = "cover_blown"`, `plan.expiresAt = CurTime()`

### perceive.lua
- Line 24: `data.state == COVER` → dual-mode:
  - mode=0: same
  - mode=1: `CAI.PhaseIs(data, PHASE.COVER)`

### react/flinch.lua (legacy mode=0 only — no dual-mode needed, dead when mode=1)
- Keep as-is. `BR.Flinch` only runs in mode=0 (guarded in think.lua).
- Reflex handlers (`react/reflexes/*.lua`) have NO state checks — they bias movement unconditionally.

### think.lua (already rewritten for dual-mode)
- OODA path uses `PhaseIs` checks; legacy path keeps `data.state` checks.

### sv_debug.lua + cl_debug.lua (Phase 5)
- Send both `data.phase` and `data.phaseIntent` over net when mode=1
- Keep `CAI.STATE` net send for mode=0
- Add `PHASE_COLORS` alongside `STATE_COLORS`
- Add `T.Phases` alongside `T.States`

---

## Dual-Mode Convar (for safe migration)

Add `cai_ooda_mode` convar (default 0):
- **0**: Legacy mode — keep `CAI.STATE`, `BR.Exec[0..11]`, old `BR.Decide`, `BR.Flinch`
- **1**: OODA mode — use `CAI.PHASE`, `BR.ExecPhase[phase]`, new OODA cycle, `BR.Reflex` handlers

Both modes coexist in the codebase during development. `think.lua` routes at runtime:
- mode=0: `BR.Decide` → `BR.SetState` → `BR.Exec[state]` + `BR.Flinch`
- mode=1: `BR.Reflex` → `BR.OODA` → `BR.SetPhase` → `BR.ExecPhase[phase]` + reflex bias

Both `decide.lua` (OODA COAs) and `decide_legacy.lua` (legacy COAs + BR.Decide) are always loaded — the runtime path uses only the tables relevant to the current mode. Same for `react/`: both `flinch.lua` and `reflexes/*.lua` are always loaded; think.lua calls the correct function.

This allows:
1. Incremental development (test Phase 1 while Phase 2 is being written)
2. Instant rollback by toggling the convar
3. A/B comparison of NPC behavior

When migration is complete and stable, the legacy path and convar are removed.

---

## File Structure Changes

### New files
```
server/brain_func/ooda.lua                -- OODA cycle
server/brain_func/decide_legacy.lua       -- legacy COA loader + BR.Decide (mode=0)
server/brain_func/react/shared.lua        -- BR.IsCommitted + BR.UnderFire (both modes)
server/brain_func/react/reflexes/grenade_dodge.lua
server/brain_func/react/reflexes/melee_dodge.lua
server/brain_func/react/reflexes/suppression_jink.lua
server/brain_func/react/flinch.lua        -- legacy BR.Flinch (mode=0)
server/brain_func/decide/morale_break.lua
server/brain_func/decide/panic.lua
server/brain_func/decide/flank_protect.lua (rewritten)
server/brain_func/decide/melee_threat.lua
server/brain_func/decide/room_clear_coa.lua
server/brain_func/decide/pinned.lua
server/brain_func/decide/engage_target.lua
server/brain_func/decide/lost_target_coa.lua
server/brain_func/decide/suppress_order.lua
server/brain_func/decide/flank_order.lua
server/brain_func/decide/bound_order.lua
server/brain_func/decide/separated.lua
server/brain_func/decide/squad_aware.lua (rewritten)
server/brain_func/decide/pre_contact.lua
server/brain_func/exec/pre_contact.lua
server/brain_func/exec/assess.lua
server/brain_func/exec/maneuver.lua
server/brain_func/exec/withdraw.lua
server/brain_func/exec/post_contact.lua
```

### Moved to `decide/legacy/`
```
decide/legacy/emergency_relocate.lua
decide/legacy/grenade_scatter.lua
decide/legacy/melee_swarm.lua
decide/legacy/melee_chase.lua
decide/legacy/morale_panic.lua
decide/legacy/morale_broken.lua
decide/legacy/flank.lua
decide/legacy/squad_flank_order.lua
decide/legacy/squad_suppress_order.lua
decide/legacy/squad_bound_order.lua
decide/legacy/separated_from_squad.lua
decide/legacy/squad_aware.lua (old)
decide/legacy/cover_hold.lua
decide/legacy/engage.lua
decide/legacy/lost_target.lua
decide/legacy/room_clear.lua
decide/legacy/patrol.lua
```

### Moved to `exec/legacy/`
```
exec/legacy/idle.lua
exec/legacy/patrol.lua
exec/legacy/suppress.lua
exec/legacy/search.lua
exec/legacy/investigate.lua
exec/legacy/regroup.lua
exec/legacy/room_clear.lua
exec/legacy/bounded.lua
exec/legacy/retreat.lua
exec/legacy/flank.lua
```

### Modified files
```
sv_brain.lua            — add decide_legacy.lua include
sv_manager.lua          — update data init (remove state/stateSince/prevState)
shared/sh_config.lua    — add CAI.PHASE, CAI.PHASE_NAMES, Plan config
shared/sh_text.lua      — replace T.States with T.Phases
shared/sh_net.lua       — update state net transfers to phase+intent
client/cl_debug.lua     — read phase+intent, PHASE_COLORS
server/sv_target.lua    — update SUPPRESS check
server/sv_morale.lua    — update IDLE/PATROL checks
server/sv_squad.lua     — update all state checks + SetState → planPending
server/sv_navigation.lua — add reflex bias to MoveTo
server/sv_debug.lua     — send phase+intent instead of state
server/sv_sound.lua     — update IDLE/PATROL checks + SetState → planPending
server/sv_darkness.lua  — update IDLE check
server/sv_cover.lua     — update SetState → planPending
server/brain_func/state.lua — rewrite to SetPhase
server/brain_func/think.lua — rewrite
server/brain_func/react.lua — rewrite to modular loader (react/ subfiles)
server/brain_func/perceive.lua — update COVER check
server/brain_func/exec/engage.lua — update CAI.STATE refs to PHASE (0 SetState calls, copies verbatim)
server/brain_func/exec/cover.lua — update CAI.STATE refs + SetState → planPending (2 calls)
server/brain_func/exec.lua — define BR.ExecPhase, load new exec files
server/brain_func/decide.lua — rewrite to OODA COA registration
```

---

## Migration Strategy

### Phase 0: Pre-Migration Setup
1. Add `cai_ooda_mode` convar (0=legacy, 1=OODA)
2. Create `CAI.PHASE` enum alongside `CAI.STATE` in `sh_config.lua`
3. Create `CAI.PhaseIs()` helper function

### Phase 1: Foundation (OODA path)
4. Add new data fields to `MG.Register` in `sv_manager.lua` (only used when mode=1)
5. Write `BR.SetPhase` in `state.lua`
6. Write `react/` module: `react.lua` loader, `react/shared.lua`, `react/reflexes/*.lua` handlers, `react/flinch.lua`
7. Write `ooda.lua` with OODA cycle
8. Write new `think.lua` with reflex → OODA → exec flow
9. Update `sv_brain.lua` includes + convar routing

### Phase 2: Exec Handlers
10. Write/rewrite 7 phase-based exec files (5 new, 2 updated in place)
11. Register `BR.ExecPhase[phase]` in `exec.lua` (alongside `BR.Exec`)
12. Move old state-based exec files to `exec/legacy/` — preserves `cai_ooda_mode=0` through Phases 2-3

### Phase 3: COA Modules
13. Write new COA modules (14 files)
14. Move old COA modules to `decide/legacy/`

### Phase 4: Subsystem Updates (Dual-Mode — each check wraps `if cai_ooda_mode then PhaseIs else data.state ==`)
15. Update `sv_squad.lua` — all state checks + SetState → planPending/mode-guard
16. Update `sv_target.lua` — SUPPRESS check
17. Update `sv_morale.lua` — IDLE/PATROL checks + SetState → planPending/mode-guard
18. Update `sv_sound.lua` — IDLE/PATROL checks + SetState → planPending/mode-guard
19. Update `sv_darkness.lua` — IDLE check
20. Update `sv_cover.lua` — SetState → planPending/mode-guard
21. Update `perceive.lua` — COVER check
22. Update `sv_navigation.lua` — add reflex bias to MoveTo

### Phase 5: Debug + Network (Dual-Mode — send phase+intent for mode=1, state for mode=0)
23. Update `sv_debug.lua` — send phase+intent when mode=1
24. Update `cl_debug.lua` — PHASE_COLORS, phase+intent display when mode=1
25. Update `sh_text.lua` — T.Phases labels
26. Update `sh_net.lua` — wire format for phase+intent

### Phase 6: Cleanup
27. Remove `exec/legacy/` and `decide/legacy/` directories (old exec + old COA)
28. Remove `CAI.STATE` enum and `CAI.STATE_NAMES` from `sh_config.lua`
29. Remove `BR.Exec` table and old `exec.lua` loader
30. Remove `cai_ooda_mode` convar and legacy routing
31. Syntax check with `luac5.1 -p` on every changed file
32. Manual smoke test: spawn NPCs with various roles, verify behavior visually
