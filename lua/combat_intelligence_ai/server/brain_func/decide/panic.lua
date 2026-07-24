local BR = CAI.Brain

table.insert(BR.COA.PreTarget, function(ctx)
    local data, npc = ctx.data, ctx.npc
    if CAI.Suppression.IsPanicked(data) and (data.personality.stats.courage or 0) < 0.2 then
        return CAI.PHASE.WITHDRAW, "flee", 4, "suppression_panic"
    end
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then
        local _, rec = CAI.Memory.FreshestEnemy(data)
        if (rec and CurTime() - rec.t < 8) or data.suppression > 10
           or CurTime() - (data.lastHurtAt or 0) < 6 then
            return CAI.PHASE.WITHDRAW, "flee", 4, "unarmed_flee"
        end
    end
end)
