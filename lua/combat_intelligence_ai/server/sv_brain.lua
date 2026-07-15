--[[
    sv_brain.lua: the Combat Intelligence AI "brain" (loader).

    This file only wires up the brain. The actual logic lives in the sibling
    brain_func/ directory, each module populating the CAI.Brain (BR) table:

        state.lua    -> BR.SetState, BR.StopSuppressing, BR.Prefire
        perceive.lua -> BR.Perceive
        sense.lua    -> BR.CombatTarget, BR.MeleeThreatScan
        decide.lua   -> BR.Decide
        exec.lua     -> BR.Exec[0..11]  (the per-state handlers)
        think.lua    -> BR.Think        (the per-tick orchestrator)

    Per-NPC decision core. Driven every scheduler tick (see sv_manager.lua,
    timer "CAI_Scheduler") under a per-tick budget. For each managed NPC it runs
    a strict 3-phase loop over the per-NPC record `data` (CAI.Manager.NPCs[npc]):

        1. Perceive  -> update senses / memory (never moves the NPC)
        2. Decide    -> pure priority cascade, returns (state, reason), read-only
        3. Execute   -> BR.Exec[state] actually moves / fires / sets schedules

    States are the CAI.STATE enum (shared/sh_config.lua). `reason` strings are
    surfaced by cai_debug, so keep them descriptive.
--]]

CAI.Brain = CAI.Brain or {}
local BR = CAI.Brain

local BRAIN = "combat_intelligence_ai/server/brain_func/"

include(BRAIN .. "state.lua")
include(BRAIN .. "perceive.lua")
include(BRAIN .. "sense.lua")
include(BRAIN .. "decide.lua")
include(BRAIN .. "exec.lua")
include(BRAIN .. "react.lua")       -- BR.IsCommitted, BR.UnderFire, BR.Flinch
include(BRAIN .. "think.lua")

CAI.Prof.WrapFn(BR, "Prefire", "brain_prefire")
