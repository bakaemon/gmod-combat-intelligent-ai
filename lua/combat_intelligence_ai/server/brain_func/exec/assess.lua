local BR = CAI.Brain

BR.ExecPhase[CAI.PHASE.ASSESS] = function(data)
    local npc = data.ent
    local enemy, rec = BR.CombatTarget(data)
    if IsValid(enemy) then
        if npc.SetEnemy then npc:SetEnemy(enemy) end
    end
    if not data._assessAt then
        data._assessAt = CurTime() + math.Rand(1, 2.5)
        npc:SetSchedule(SCHED_COMBAT_FACE)
        return
    end
    if CurTime() >= data._assessAt then
        data._assessAt = nil
        data.planPending = "assess_done"
    end
end
