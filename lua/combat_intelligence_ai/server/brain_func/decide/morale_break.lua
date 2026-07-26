local BR = CAI.Brain

table.insert(BR.COA.PreTarget, function(ctx)
    if not CAI.Morale.IsBroken(ctx.data) then return end
    if CAI.CVBool("cai_meleepanic") then
        local npc = ctx.npc
        local ee = npc.GetEnemy and npc:GetEnemy()
        if IsValid(ee) and CAI.Util.IsTargetable(ee)
           and npc:GetPos():DistToSqr(ee:GetPos()) < 110 * 110 then
            local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
            if not IsValid(wep) or (wep.Clip1 and wep:Clip1() == 0) then
                return CAI.PHASE.ENGAGE, "melee", 1, "cornered_melee"
            end
        end
    end
    return CAI.PHASE.WITHDRAW, "flee", 5, "morale_broken"
end)
