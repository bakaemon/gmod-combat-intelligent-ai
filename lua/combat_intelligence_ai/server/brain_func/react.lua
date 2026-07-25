local BR = CAI.Brain

BR.ReflexHandlers = BR.ReflexHandlers or {}

function BR.Reflex(data, dt)
    local biasVec = Vector(0, 0, 0)
    local topUrgency = nil

    for _, handler in ipairs(BR.ReflexHandlers) do
        local bv, urg = handler(data, dt)
        if bv then biasVec = biasVec + bv end
        if urg == "urgent" then
            topUrgency = "urgent"
        elseif urg == "attention" and topUrgency ~= "urgent" then
            topUrgency = "attention"
        end
    end

    if not data.reflex then data.reflex = {} end
    data.reflex.bias = biasVec
    data.reflex.urgency = topUrgency
end

local C = CAI.Config

--[[
    react.lua: the Reflex layer (OODA mode)

    Evade is modelled here as a LOW-LEVEL DEFENSIVE RULE, not a brain state.
    It runs every tick AFTER the state machine (see think.lua) and only ever
    biases MOVEMENT — it never calls SetPhase, so it cannot interrupt
    phases.

    Design rules:
      * It follows the plan's intent; it never changes the phase or the plan's
        high-level destination.
      * If the plan is already in effective cover or suppressing, it yields.
      * While repositioning under fire it runs-and-guns: with move-shoot available
        it issues SCHED_CHASE_ENEMY so the NPC fires while moving.
      * Committed weapon wind-ups are never interrupted.
--]]

function BR.IsCommitted(data)
    local npc = data.ent
    if not (npc.IsCurrentSchedule) then return false end
    -- Committed weapon wind-ups (basic fire, secondary attacks, melee swings)
    -- are uninterruptible so the flinch layer never resets a live shot or a
    -- grenade wind-up mid-sequence.
    return npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1)
        or npc:IsCurrentSchedule(SCHED_RANGE_ATTACK2)
        or npc:IsCurrentSchedule(SCHED_MELEE_ATTACK1)
end

local function BR_UnderFire(data)
    return (data.suppression or 0) > C.Flinch.UnderFireAt
end

local DIR = "combat_intelligence_ai/server/brain_func/react/"

-- Shared utilities
include(DIR .. "shared.lua")

-- Reflex handlers
include(DIR .. "reflexes/grenade_dodge.lua")
include(DIR .. "reflexes/melee_dodge.lua")
include(DIR .. "reflexes/suppression_jink.lua")
include(DIR .. "reflexes/reload_reflex.lua")

-- Retaliate: brief fire-back after taking damage (called from think.lua after exec)
include(DIR .. "retaliate.lua")