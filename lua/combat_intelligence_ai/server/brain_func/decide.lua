local BR = CAI.Brain

-- Decide: the brain's "thinking". A facilitator that owns the basic decision
-- logic (target acquisition, visibility, shared helpers) and then consults the
-- course-of-action (COA) modules in brain_func/decide/ in priority order. Each
-- COA returns (state, reason) or nil; the first non-nil wins.
-- Pure: never moves the NPC or sets schedules, just picks a state + reason.
BR.COA = BR.COA or {}
BR.COA.PreTarget = {}
BR.COA.Target = {}

local DIR = "combat_intelligence_ai/server/brain_func/decide/"

-- PreTarget courses of action: immediate overrides that need no combat target.
include(DIR .. "emergency_relocate.lua")
include(DIR .. "grenade_scatter.lua")
include(DIR .. "flank_protect.lua")
include(DIR .. "melee_swarm.lua")
include(DIR .. "morale_broken.lua")
include(DIR .. "morale_panic.lua")
include(DIR .. "melee_chase.lua")
include(DIR .. "room_clear.lua")

-- Target-dependent courses of action, in priority order. Visible-branch
-- variants run first; lost-target variants live inside lost_target.lua at their
-- original internal positions to preserve the cascade order.
include(DIR .. "flank.lua")
include(DIR .. "cover_hold.lua")
include(DIR .. "squad_flank_order.lua")
include(DIR .. "squad_suppress_order.lua")
include(DIR .. "separated_from_squad.lua")
include(DIR .. "squad_bound_order.lua")
include(DIR .. "engage.lua")
include(DIR .. "lost_target.lua")
include(DIR .. "squad_aware.lua")
include(DIR .. "patrol.lua")

-- Validation: every registered COA must be a callable.
for _, phase in ipairs({ BR.COA.PreTarget, BR.COA.Target }) do
    for _, coa in ipairs(phase) do
        assert(isfunction(coa), "decide: registered COA is not a function")
    end
end
assert(#BR.COA.PreTarget > 0 and #BR.COA.Target > 0, "decide: no COAs registered")

BR.Decide = function(data)
    local S = CAI.STATE
    local npc = data.ent

    data.combatTarget = nil
    data.combatRec = nil

    -- Phase 1: immediate-override courses of action that need no target.
    for _, coa in ipairs(BR.COA.PreTarget) do
        local st, r = coa(data, npc)
        if st then return st, r end
    end

    -- Basic logic: acquire the combat target and derive visibility.
    local enemy, rec = CAI.Target.Evaluate(data)
    if IsValid(enemy) then
        data.combatTarget, data.combatRec = enemy, rec
    end
    local visible = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
    if visible then
        data.lastVisEnemy, data.lastVisAt = enemy, CurTime()
        data.search, data.awaitAt = nil, nil
    elseif IsValid(enemy) and data.lastVisEnemy == enemy
       and CurTime() - (data.lastVisAt or 0) < CAI.Config.LastVisGrace then
        visible = true
    end

    local holdUnknown = CAI.CVBool("cai_hold_unknown")
    local dangerAvoid = CAI.CVBool("cai_danger_avoid")
    local function squadCovering()
        return data.squad and (CAI.Squad.AnyoneEngaging(data.squad, npc)
            or CAI.Squad.Suppressing(data.squad, npc)) or false
    end
    local ctx = {
        data = data, npc = npc, S = S,
        enemy = enemy, rec = rec, visible = visible,
        holdUnknown = holdUnknown, dangerAvoid = dangerAvoid,
        squadCovering = squadCovering,
    }

    -- Phase 3: target-dependent courses of action, then patrol fallback.
    for _, coa in ipairs(BR.COA.Target) do
        local st, r = coa(ctx)
        if st then return st, r end
    end
    return S.PATROL, "all_quiet"
end
