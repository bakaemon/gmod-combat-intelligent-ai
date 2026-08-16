local BR = CAI.Brain

BR.RegisterHook("brain/react", "ranged_empty_reload", function(data, dt)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(npc) then return end
    if not CAI.IsDry(data) then return end
    if npc.SelectWeightedSequence then
        local seq = npc:SelectWeightedSequence(ACT_RELOAD)
        if seq == nil or seq < 0 then return end
    end

    local enemy = npc.GetEnemy and npc:GetEnemy()
    local threatened = IsValid(enemy)

    if threatened and data.phase ~= CAI.PHASE.WITHDRAW and CurTime() - (data._dryPhaseAt or 0) > 1 then
        data._dryPhaseAt = CurTime()
        BR.SetPhase(data, CAI.PHASE.COVER, "reloading", "dry_reload", true)
    end

    CAI.TryReload(data, threatened)
end)