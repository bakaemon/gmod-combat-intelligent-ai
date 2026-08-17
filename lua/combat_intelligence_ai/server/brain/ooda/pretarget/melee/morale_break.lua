local BR = CAI.Brain

BR.RegisterHook("brain/ooda/pretarget", "melee_morale_break", function(ctx)
    if ctx.phase then return end
    if not CAI.Morale.IsBroken(ctx.data) then return end

    local npc = ctx.npc
    local ee = npc.GetEnemy and npc:GetEnemy()
    if IsValid(ee) and CAI.Util.IsTargetable(ee)
       and npc:GetPos():DistToSqr(ee:GetPos()) < 110 * 110 then
        local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
        if not IsValid(wep) or (wep.Clip1 and wep:Clip1() == 0) then
            ctx.phase = CAI.PHASE.ENGAGE
            ctx.intent = "melee"
            ctx.duration = 1
            ctx.reason = "cornered_melee"
            return
        end
    end
    ctx.phase = CAI.PHASE.WITHDRAW
    ctx.intent = "flee"
    ctx.duration = 5
    ctx.reason = "morale_broken"
end)