local ROOT = "combat_intelligence_ai/server/brain/ooda/"
include(ROOT .. "squadorder.lua")
include(ROOT .. "pretarget.lua")
include(ROOT .. "target.lua")

local function buildCtx(data)
    local npc = data.ent
    local enemy, rec = CAI.Target.Evaluate(data)
    if IsValid(enemy) then data.combatTarget, data.combatRec = enemy, rec end
    local visible = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
    if visible then
        data.lastVisEnemy, data.lastVisAt = enemy, CurTime()
    elseif IsValid(enemy) and data.lastVisEnemy == enemy
       and CurTime() - (data.lastVisAt or 0) < CAI.Config.LastVisGrace then
        visible = true
    end
    data.search, data.awaitAt = nil, nil
    return {
        data = data, npc = npc, enemy = enemy, rec = rec, visible = visible,
        holdUnknown = CAI.CVBool("cai_hold_unknown"),
        dangerAvoid = CAI.CVBool("cai_danger_avoid"),
        squadCovering = data.squad and function()
            return CAI.Squad.AnyoneEngaging(data.squad, npc)
                or CAI.Squad.Suppressing(data.squad, npc)
        end or function() return false end,
    }
end

local function loader(data)
    local ctx = buildCtx(data)
    BR.Call("brain/ooda/squadorder", BR.HOOK_LOADER, ctx)
    if ctx.phase then
        BR.SetPhase(data, ctx.phase, ctx.intent, ctx.reason, data.planPending ~= nil)
        data.plan.expiresAt = CurTime() + (ctx.duration or 5)
        data.planPending = nil
        return
    end
    BR.Call("brain/ooda/pretarget", BR.HOOK_LOADER, ctx)
    if ctx.phase then
        BR.SetPhase(data, ctx.phase, ctx.intent, ctx.reason, data.planPending ~= nil)
        data.plan.expiresAt = CurTime() + (ctx.duration or 5)
        data.planPending = nil
        return
    end
    BR.Call("brain/ooda/target", BR.HOOK_LOADER, ctx)
    if ctx.phase then
        BR.SetPhase(data, ctx.phase, ctx.intent, ctx.reason, data.planPending ~= nil)
        data.plan.expiresAt = CurTime() + (ctx.duration or 5)
        data.planPending = nil
        return
    end
    ctx.phase, ctx.intent, ctx.duration, ctx.reason = CAI.PHASE.PRE_CONTACT, "patrol", 5, "fallback"
    BR.SetPhase(data, ctx.phase, ctx.intent, ctx.reason, data.planPending ~= nil)
    data.plan.expiresAt = CurTime() + (ctx.duration or 5)
    data.planPending = nil
end
BR.RegisterHook("brain/ooda", BR.HOOK_LOADER, loader)