local BR = CAI.Brain

BR.RegisterHook("brain/react", "ranged_empty_reload", function(data, dt)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(data.ent) then return end
    local wep = npc:GetActiveWeapon()
    if not IsValid(wep) or not wep.Clip1 or wep:Clip1() > 0 then return end
    if npc.SelectWeightedSequence then
        local seq = npc:SelectWeightedSequence(ACT_RELOAD)
        if seq == nil or seq < 0 then return end
    end
    local reloading = npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_RELOAD)
    if reloading then return end
    data._reloadingAt = CurTime()
    npc:SetSchedule(SCHED_RELOAD)
end)