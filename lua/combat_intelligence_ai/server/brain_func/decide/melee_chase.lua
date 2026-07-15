local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: a melee-weapon NPC chases down a fresh enemy memory.
table.insert(BR.COA.PreTarget, function(data, npc)
    if CAI.WeaponIntel.IsMelee(npc) then
        local me, mrec = CAI.Memory.FreshestEnemy(data)
        if IsValid(me) and not CAI.Util.IsTargetable(me) then
            data.memory.enemies[me] = nil
            mrec = nil
        end
        if mrec and CurTime() - mrec.t < 5 then
            if CAI.Morale.IsBroken(data) then return CAI.STATE.RETREAT, "morale_broken" end
            return CAI.STATE.ENGAGE, "melee_chase"
        end
    end
end)
