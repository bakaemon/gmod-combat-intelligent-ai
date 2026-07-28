local BR = CAI.Brain

BR.RegisterHook("brain/ooda/target", "melee_engage_target", function(ctx)
    if ctx.phase then return end
    if not CAI.WeaponIntel.IsMelee(ctx.npc) then return end
    local data, npc, enemy, rec = ctx.data, ctx.npc, ctx.enemy, ctx.rec

    if IsValid(enemy) and not CAI.Util.IsTargetable(enemy) then
        data.memory.enemies[enemy] = nil
        rec = nil
    end
    if not rec or CurTime() - rec.t >= 5 then return end

    if CAI.Morale.IsBroken(data) then
        data.meleeThreatSeen = nil
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "flee"
        ctx.duration = 4
        ctx.reason = "morale_broken"
        return
    end

    local mcfg = CAI.Config.Melee

    local threat
    if IsValid(enemy) and ctx.visible then
        threat = CAI.WeaponIntel.ThreatClass(enemy)
        data.meleeThreatSeen = threat
        data.meleeThreatAt = CurTime()
    else
        threat = data.meleeThreatSeen or "unarmed"
    end

    if data.meleeLastThreat ~= threat then
        if data.meleeLastThreat ~= nil then data.planPending = true end
        data.meleeLastThreat = threat
    end

    local dist = IsValid(enemy) and npc:GetPos():Distance(enemy:GetPos()) or math.huge

    if dist < mcfg.GunPanicDist then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "melee"
        ctx.duration = 2
        ctx.reason = "melee_chase"
        return
    end

    if threat == "gun" then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "melee"
        ctx.duration = 2.5
        ctx.reason = "melee_ambush"
        return
    end

    -- No gun: charge.
    ctx.phase = CAI.PHASE.ENGAGE
    ctx.intent = "melee"
    ctx.duration = 2
    ctx.reason = "melee_chase"
end)