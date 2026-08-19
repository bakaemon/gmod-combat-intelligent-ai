# Modding Guide

## Section 1: How to Add a New Weapon Archetype Behavior

This guide walks through adding custom behavior for a **Pistol** weapon archetype. The same pattern applies to any archetype (shotgun,  sniper,  lmg,  smg,  rocket,  or custom weapon pack archetypes).

## Overview

The brain uses a **central hook system** instead of scattered tables. To add behavior,  you register a function at a specific `(module,  scope)` pair:

```lua
BR.RegisterHook(module,  scope,  function(ctx_or_data)
    -- your logic here
end)
```

There are three layers where behavior can live:

| Layer | Purpose | When it runs |
|---|---|---|
| **Reaction** (`brain/react/`) | Reflexes ,  dodging,  jinking,  reloading | Every tick,  before planning |
| **Plan/OODA** (`brain/ooda/`) | Decision making ,  what phase to enter | When plan expires or is urgent |
| **Execution** (`brain/exec/`) | Carrying out the plan ,  moving,  shooting | Every tick,  after planning |

## Two Architectural Patterns

**Pattern A ,  Three-way split** (all → ranged → melee): Used by react,  pretarget,  target modules. Scopes use a category prefix (`all_`,  `ranged_`,  `melee_`).

**Pattern B ,  Archetype fallback** (arch → category generic): Used by exec/engage. Scopes are flat (`"ranged"`,  `"shotgun"`,  etc.).

## Adding Pistol Behavior at Each Layer

### 1. Adding a Pistol Execution Handler (Pattern B)

The exec/engage module handles combat behavior. Pistols are a ranged archetype,  so the handler goes alongside the existing ranged generic in `brain/exec/engage/`.

Create `lua/combat_intelligence_ai/server/brain/exec/engage/pistol.lua`:

```lua
local function handler(data)
    -- Example: pistols fire faster,  prefer close range
    local npc = data.ent
    local enemy = data.combatTarget
    if not IsValid(enemy) then return end

    local dist = npc:GetPos():Distance(enemy:GetPos())
    local ownIdeal = CAI.WeaponIntel.OwnIdeal(npc)

    if dist < ownIdeal * 0.5 then
        -- Close range: rapid fire
        npc:SetSchedule(SCHED_RANGE_ATTACK1)
        npc:SetCurrentWeaponProficiency(0.5)
    elseif dist < ownIdeal * 1.5 then
        -- Medium range: advance and fire
        BR.Prefire(npc)
        npc:SetSchedule(SCHED_CHASE_ENEMY)
    else
        -- Long range: close distance
        npc:SetSchedule(SCHED_CHASE_ENEMY)
    end
end
BR.RegisterHook("brain/exec/engage",  "pistol",  handler)
```

**Loader update:** Add the include to `brain/exec/engage.lua` ,  the engage module loader:
```lua
include(ROOT .. "pistol.lua")  -- add after existing arch files
```

The order among arch includes doesn't matter ,  the loader tries each arch by name,  not by include order.

**How it works:** The `engage.lua` loader tries arch scopes first ,  `BR.Call("brain/exec/engage",  "pistol",  data)`. If your pistol handler exists,  it runs. If not (or if it returns early),  the loader falls through to the "ranged" generic.

### 2. Adding a Pistol COA Decision (Pattern A)

The ooda/target module handles planning decisions. Pistol-specific COA logic goes under the `ranged/` category directory in `brain/ooda/target/ranged/`.

Create `lua/combat_intelligence_ai/server/brain/ooda/target/ranged/pistol_engage_target.lua`:

```lua
local function handler(ctx)
    if ctx.phase then return end
    local data,  npc,  enemy = ctx.data,  ctx.npc,  ctx.enemy
    if not IsValid(enemy) then return end

    local dist = npc:GetPos():Distance(enemy:GetPos())
    local agg = CAI.WeaponIntel.EffectiveAggression(data)

    -- Pistols: aggressive close-range engagement
    if dist < 400 then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "direct_fire"
        ctx.duration = 2
        ctx.reason = "pistol_close_range"
    elseif agg > 0.6 then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "aggressive_push"
        ctx.duration = 3
        ctx.reason = "pistol_aggressive"
    else
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "direct_fire"
        ctx.duration = 2.5
        ctx.reason = "pistol_engage"
    end
end
BR.RegisterHook("brain/ooda/target",  "ranged_pistol_engage_target",  handler)
```

**Loader update:** Add the include to `brain/ooda/target.lua`:
```lua
include(ROOT .. "ranged/pistol_engage_target.lua")  -- add after ranged/engage_target.lua
```

**Naming convention:** The scope uses `ranged_pistol_engage_target` ,  `{category}_{archetype}_{behavior}`. The loader tries arch-specific before the category generic,  so `ranged_pistol_engage_target` runs before `ranged_engage_target`.

**Important:** The directory is `ranged/` because pistols are a ranged weapon. The scope prefix `ranged_` tells the loader this is a ranged override. The file name `pistol_engage_target.lua` follows the `{arch}_{behavior}` pattern for readability.

### 3. Adding a Pistol Reflex (Pattern A)

The react module handles reflexes. Pistol-specific reflexes go under `brain/react/ranged/` since pistols are ranged weapons.

Create `lua/combat_intelligence_ai/server/brain/react/ranged/pistol_reload.lua`:

```lua
local function handler(data,  dt)
    local npc = data.ent
    local wep = npc:GetActiveWeapon()
    if not IsValid(wep) then return end

    -- Pistols reload faster
    if wep:Clip1() == 0 and not npc:IsCurrentSchedule(SCHED_RELOAD) then
        npc:SetSchedule(SCHED_RELOAD)
        data.lastReloadAt = CurTime()
    end
end
BR.RegisterHook("brain/react",  "ranged_pistol_reload",  handler)
```

**Loader update:** Add the include to `brain/react.lua`:
```lua
include(ROOT .. "ranged/pistol_reload.lua")  -- add after ranged/melee_dodge.lua
```

**Naming convention:** `ranged_pistol_reload` ,  `{category}_{archetype}_{behavior}`. The `ranged_` prefix is necessary because the react loader only calls scopes with this prefix when the NPC is ranged.

## Resolution Order Summary

For a Pistol NPC,  the hook resolution at each layer is:

**Exec/engage:**
1. `BR.Call("brain/exec/engage",  "pistol",  data)` ← your handler
2. If no handler or handler returns: `BR.Call("brain/exec/engage",  "ranged",  data)` ,  generic ranged

**OODA/Target:**
1. `BR.CallScopes("brain/ooda/target",  ctx)` runs ALL scopes,  each gates on `ctx.phase`
2. Your `ranged_pistol_engage_target` runs alongside `ranged_engage_target`
3. The first handler to set `ctx.phase` wins (melee_engage_target has its own `if IsMelee gate`)

**React:**
1. `BR.CallScopes("brain/react",  data,  dt)` runs ALL scopes,  each gates on its own conditions
2. Your `ranged_pistol_reload` runs alongside other ranged reflexes
3. Each handler mutates `data.reflex` directly

## Quick Reference: File Locations

| Layer | Directory | Scope Pattern | Example |
|---|---|---|---|
| Exec (Pattern B) | `brain/exec/engage/` | `"pistol"` | `BR.RegisterHook("brain/exec/engage",  "pistol",  fn)` |
| OODA/Target (Pattern A) | `brain/ooda/target/ranged/` | `"ranged_pistol_engage_target"` | `BR.RegisterHook("brain/ooda/target",  "ranged_pistol_engage_target",  fn)` |
| React (Pattern A) | `brain/react/ranged/` | `"ranged_pistol_reload"` | `BR.RegisterHook("brain/react",  "ranged_pistol_reload",  fn)` |

## Rules to Remember

1. **Scope names cannot contain `/`** ,  use underscores instead
2. **Pattern A prefixes** ,  use `all_`,  `ranged_`,  `melee_` for weapon-agnostic and category-specific scopes
3. **Pattern B flat** ,  no prefix,  the module IS the category
4. **Every file** ,  logic first,  `BR.RegisterHook(...)` as the very last line
5. **COA handlers** ,  set `ctx.phase`,  `ctx.intent`,  `ctx.duration`,  `ctx.reason`; add `if ctx.phase then return end` at the top
6. **Exec handlers** ,  call `npc:SetSchedule(...)`,  `BR.Prefire(...)` directly; take `data` as argument
7. **Reflex handlers** ,  mutate `data.reflex.bias` and `data.reflex.urgency`; take `(data,  dt)` as arguments

---

## Section 2: How to Modify Existing Behavior

This section covers modifying existing behavior using the **melee** archetype as an example. The goal is to show where changes live, not to prescribe specific modifications.

### The Three Layers

Every behavior is split across three layers. To modify melee behavior, you need to know which layer controls what:

| Layer | File | What it controls |
|---|---|---|
| **COA Decision** | `brain/ooda/target/melee/engage_target.lua` | When to chase, ambush, or flee |
| **Combat** | `brain/exec/engage/melee.lua` | How to swing, step, and move |
| **Morale** | `brain/ooda/pretarget/melee/morale_break.lua` | What happens when morale breaks |

### How to Find the Right File

Start with what you want to change, then look up which layer handles it:

| If you want to change... | Look in... | Layer |
|---|---|---|
| NPC dodging, running from grenades, jinking under fire | `brain/react/` (reflex category) | Reaction |
| Weapon reload behavior | `brain/react/ranged/` | Reaction |
| When the NPC decides to chase, flank, suppress, or ambush | `brain/ooda/target/` (target category) | Planning/COA |
| Squad-level orders (suppress, flank, bound) | `brain/ooda/squadorder/` | Planning/COA |
| Pre-combat behavior (morale breaks, panic, room clearing) | `brain/ooda/pretarget/` | Planning/COA |
| How the NPC moves during combat | `brain/exec/` (phase handler) | Execution |
| How the NPC attacks, swings, or fires | `brain/exec/engage/` (archetype) | Execution |
| Cover behavior, withdrawal, or post-combat patrol | `brain/exec/` (phase handler) | Execution |

Once you know the layer, the archetype determines which file within that layer:

| If your NPC is... | Look in... |
|---|---|
| Melee (knife, crowbar, unarmed) | `melee/` subdirectory |
| Ranged (rifle, smg, pistol, shotgun, sniper, lmg, rocket) | `ranged/` subdirectory |
| Any archetype with a specific override | `{archetype_name}.lua` at the layer root |

1. **Identify what you want to change.** Do you want to change WHEN the NPC decides to chase? That's the COA layer (brain/ooda/). Do you want to change HOW the NPC swings? That's the exec layer (brain/exec/).

2. **Find the file.** Each layer has a subdirectory matching the archetype. For melee, that's `melee/`. The file name describes the behavior: `engage_target.lua` for COA decisions, `melee.lua` for combat execution, `morale_break.lua` for morale reactions.

3. **Open the file.** Every file follows the same structure: local logic at the top, `BR.RegisterHook(...)` at the very bottom. The handler function takes either `ctx` (COA layer) or `data` (exec/combat layer).

### Example: Making Melee NPCs Chase More Aggressively

File: `brain/ooda/target/melee/engage_target.lua`

This file computes a "rush" score and compares it to a threshold. To make melee NPCs chase more often, find the threshold check (around line 74) and lower the threshold:

```lua
-- Change this line:
if rush >= mcfg.RushThreshold then
-- To make it easier to trigger:
if rush >= mcfg.RushThreshold * 0.7 then
```

The `ctx.phase` and `ctx.intent` assignments that follow determine what happens when the threshold is met. The structure is: if condition -> set ctx.phase, ctx.intent, ctx.duration, ctx.reason.

### Example: Changing Melee Swing Behavior

File: `brain/exec/engage/melee.lua`

This file is a finite state machine with two phases: "swing" and "step". The `data.meleePhase` variable tracks which phase the NPC is in. To change what happens during a swing:

1. Find the `if data.meleePhase == "swing"` block (around line 14)
2. The `npc:SetSchedule(SCHED_MELEE_ATTACK1)` call (line 59) is where the actual swing happens
3. The `npc:SetSchedule(SCHED_CHASE_ENEMY)` call (line 61) is the fallback if the swing would miss

### General Pattern

Every behavior file in the system follows this pattern:

```
module/                          <- parent directory (e.g., brain/ooda/target/)
  category/                      <- all/, ranged/, or melee/
    behavior_name.lua             <- what the file does (e.g., engage_target.lua)
```

The file registers a handler at its scope name. The parent loader (`module.lua` at the same level as `module/`) includes the file. To modify behavior, edit the file. To add new behavior, create a new file and add an include line to the parent loader.