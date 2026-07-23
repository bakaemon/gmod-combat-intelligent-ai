local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: suppression panic, or flee when unarmed and threatened.
table.insert(BR.COA.PreTarget, function(data, npc)
    if CAI.Suppression.IsPanicked(data) and (data.personality.stats.courage or 0) < 0.2 then
        return CAI.STATE.RETREAT, "suppression_panic"
    end
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then
        local _, rec = CAI.Memory.FreshestEnemy(data)
        if (rec and CurTime() - rec.t < 8) or data.suppression > 10
           or CurTime() - (data.lastHurtAt or 0) < 6 then
            return CAI.STATE.RETREAT, "unarmed_flee"
        end
    end
end)
