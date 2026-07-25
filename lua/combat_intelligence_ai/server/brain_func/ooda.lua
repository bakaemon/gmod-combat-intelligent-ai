local BR = CAI.Brain

function BR.OODA(data)
    local npc = data.ent

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

    local ctx = {
        data = data,
        npc = npc,
        enemy = enemy,
        rec = rec,
        visible = visible,
        holdUnknown = CAI.CVBool("cai_hold_unknown"),
        dangerAvoid = CAI.CVBool("cai_danger_avoid"),
        squadCovering = data.squad and function()
            return CAI.Squad.AnyoneEngaging(data.squad, npc)
                or CAI.Squad.Suppressing(data.squad, npc)
        end or function() return false end,
    }

    local phase, intent, duration, reason

    for _, coa in ipairs(BR.COA.OODA.SquadOrder) do
        phase, intent, duration, reason = coa(ctx)
        if phase then break end
    end
    if not phase then
        for _, coa in ipairs(BR.COA.OODA.PreTarget) do
            phase, intent, duration, reason = coa(ctx)
            if phase then break end
        end
    end
    if not phase then
        for _, coa in ipairs(BR.COA.OODA.Target) do
            phase, intent, duration, reason = coa(ctx)
            if phase then break end
        end
    end

    if not phase then
        phase = CAI.PHASE.PRE_CONTACT
        intent = "patrol"
        duration = 5
        reason = "fallback"
    end

    BR.SetPhase(data, phase, intent, reason)
    data.plan.expiresAt = CurTime() + duration
    data.planPending = nil
end
