local BR = CAI.Brain

BR.ExecPhase[CAI.PHASE.POST_CONTACT] = function(data)
    local npc = data.ent
    local wep = npc:GetActiveWeapon()
    if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 and not wep:IsReloading() then
        local reloading = npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_RELOAD)
        if not reloading then
            npc:SetSchedule(SCHED_RELOAD)
        end
        return
    end
    if not data._pcSince then
        data._pcSince = CurTime()
        return
    end
    if CurTime() - data._pcSince > math.Rand(2, 4) then
        data._pcSince = nil
        data.planPending = "post_contact_done"
    end
end
