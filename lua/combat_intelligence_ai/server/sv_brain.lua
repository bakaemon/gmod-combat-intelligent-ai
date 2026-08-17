--[[
    sv_brain.lua: the Combat Intelligence AI "brain" (loader).

    This file only wires up the brain. The actual logic lives in the sibling
    brain_func/ directory, each module populating the CAI.Brain (BR) table:

        state.lua     -> BR.SetPhase, BR.Prefire, BR.FireSchedule
        perceive.lua  -> BR.Perceive
        sense.lua     -> BR.CombatTarget, BR.MeleeThreatScan
        decide.lua    -> BR.COA (OODA COA modules)
        exec.lua      -> BR.ExecPhase[phase] (per-phase handlers)
        react.lua     -> BR.IsCommitted, BR.UnderFire, BR.Reflex
        ooda.lua      -> BR.OODA (OODA cycle)
        think.lua     -> BR.Think (per-tick orchestrator)

    Per-NPC decision core. Driven every scheduler tick (see sv_manager.lua,
    timer "CAI_Scheduler") under a per-tick budget. For each managed NPC it runs
    a strict 3-tier loop over the per-NPC record `data` (CAI.Manager.NPCs[npc]):

        Tier 1: Reflex  -> movement bias + urgency flag (never changes phase)
        Tier 2: OODA    -> observe/orient/decide/commit (may change phase+intent)
        Tier 3: Exec    -> executes current phase+intent (never changes phase)

    Phases are the CAI.PHASE enum (shared/sh_config.lua). Intents are strings
    like "patrol", "direct_fire", "flank", "hold", etc. Both are surfaced by
    cai_debug.
--]]

CAI.Brain = CAI.Brain or {}
local BR = CAI.Brain

local BRAIN = "combat_intelligence_ai/server/brain_func/"

include(BRAIN .. "state.lua")
include(BRAIN .. "perceive.lua")
include(BRAIN .. "sense.lua")
include(BRAIN .. "decide.lua")          -- OODA COA modules
include(BRAIN .. "exec.lua")
include(BRAIN .. "react.lua")           -- BR.IsCommitted, BR.UnderFire, BR.Reflex
include(BRAIN .. "ooda.lua")            -- BR.OODA (OODA cycle)
include(BRAIN .. "think.lua")

include("combat_intelligence_ai/server/squad_func/init.lua")

CAI.Prof.WrapFn(BR, "Prefire", "brain_prefire")
