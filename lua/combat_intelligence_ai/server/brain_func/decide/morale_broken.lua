local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: morale broken. Flee unless cornered with an empty weapon
-- (desperate melee swing) when cai_meleepanic is on.
table.insert(BR.COA.PreTarget, function(data, npc)
    if CAI.Morale.IsBroken(data) then
        if CAI.CVBool("cai_meleepanic") then
            local ee = npc.GetEnemy and npc:GetEnemy()
            if IsValid(ee) and CAI.Util.IsTargetable(ee)
               and npc:GetPos():DistToSqr(ee:GetPos()) < 110 * 110 then
                local wep = npc:GetActiveWeapon()
                if not IsValid(wep) or (wep.Clip1 and wep.Clip1() == 0) then
                    return CAI.STATE.ENGAGE, "cornered_melee"
                end
            end
        end
        return CAI.STATE.RETREAT, "morale_broken"
    end
end)
