local BR = CAI.Brain

BR.RegisterHook("brain/ooda/pretarget", "all_panic", function(ctx)
    if ctx.phase then return end
    local data, npc = ctx.data, ctx.npc
    if CAI.Suppression.IsPanicked(data) and (data.personality.stats.courage or 0) < 0.2 then
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "flee"
        ctx.duration = 4
        ctx.reason = "suppression_panic"
        return
    end
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then
        local _, rec = CAI.Memory.FreshestEnemy(data)
        if (rec and CurTime() - rec.t < 8) or data.suppression > 10
           or CurTime() - (data.lastHurtAt or 0) < 6 then
            ctx.phase = CAI.PHASE.WITHDRAW
            ctx.intent = "flee"
            ctx.duration = 4
            ctx.reason = "unarmed_flee"
        end
    end
end)