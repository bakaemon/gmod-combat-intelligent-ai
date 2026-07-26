local BR = CAI.Brain

table.insert(BR.COA.Target, function(ctx)
    local data, npc, enemy, rec = ctx.data, ctx.npc, ctx.enemy, ctx.rec

    if CAI.WeaponIntel.IsMelee(npc) then
        if IsValid(enemy) and not CAI.Util.IsTargetable(enemy) then
            data.memory.enemies[enemy] = nil
            rec = nil
        end
        if not rec or CurTime() - rec.t >= 5 then return end
        if CAI.Morale.IsBroken(data) then
            return CAI.PHASE.WITHDRAW, "flee", 4, "morale_broken"
        end
        local mcfg = CAI.Config.Melee
        local pounceSqr = mcfg.Ambush.PounceDist * mcfg.Ambush.PounceDist
        if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < pounceSqr then
            return CAI.PHASE.ENGAGE, "melee", 2, "melee_chase"
        end
        local arch = "unarmed"
        if IsValid(enemy) then
            local ew = enemy.GetActiveWeapon and enemy:GetActiveWeapon()
            if IsValid(ew) then
                arch = CAI.WeaponIntel.IsMeleeThreat(enemy) and "melee" or CAI.WeaponIntel.Classify(ew)
            end
        end
        local support = 0
        if data.squad then
            for _, m in ipairs(data.squad.members) do
                if IsValid(m) and m ~= npc and CAI.Util.Alive(m)
                   and m:GetPos():DistToSqr(npc:GetPos()) < mcfg.SupportRadius * mcfg.SupportRadius then
                    support = support + 1
                end
            end
        end
        local agg = CAI.WeaponIntel.EffectiveAggression(data)
        local courage = data.personality.stats.courage or 0
        local rush = (mcfg.RushBase[arch] or 0)
                   + agg * 0.5 + courage * 0.25
                   + support * mcfg.SupportBonus
        if arch == "pistol" and support >= mcfg.PistolPackSize then
            rush = rush + 0.4
        end
        if arch == "sniper" and rush < mcfg.RushThreshold + 0.3 then
            if data.flank or CurTime() - (data.lastFlankAt or 0) > 6 then
                return CAI.PHASE.MANEUVER, "flank", 2.5, "sneak_on_sniper"
            end
            return CAI.PHASE.ENGAGE, "melee", 2.5, "melee_ambush"
        end
        if arch == "shotgun" and agg < mcfg.ShotgunOverride then
            return CAI.PHASE.ENGAGE, "melee", 2.5, "melee_ambush"
        end
        if rush >= mcfg.RushThreshold then
            return CAI.PHASE.ENGAGE, "melee", 2, "melee_chase"
        end
        return CAI.PHASE.ENGAGE, "melee", 2.5, "melee_ambush"
    end

    if not ctx.visible and enemy and rec and not data.flank
       and npc:GetPos():Distance(enemy:GetPos()) < CAI.Config.Engage.BlindPushRange
       and CurTime() - rec.t < 2.0 then
        return CAI.PHASE.ENGAGE, "direct_fire", 2.5, "cqb_known_push"
    end
    if not ctx.visible then return end

    local resp = data.enemyWeaponResponse
    local agg = CAI.WeaponIntel.EffectiveAggression(data)
    local dist = npc:GetPos():Distance(enemy:GetPos())

    if dist < 500 then
        return CAI.PHASE.ENGAGE, "direct_fire", 2, "close_range_engage"
    end

    data.coverBounces = data.coverBounces or 0
    if not CAI.PhaseIs(data, CAI.PHASE.COVER) then data.lastEngageAt = CurTime() end
    local coverStuck = CAI.PhaseIs(data, CAI.PHASE.COVER) and (data.coverSearchFailures or 0) >= 2
    local starved = CurTime() - (data.lastEngageAt or CurTime()) > 6
                     or data.coverBounces >= 3
                     or coverStuck

    if resp and resp.scatter then
        return CAI.PHASE.COVER, "hold", 2, "rocket_threat"
    end
    if resp and resp.keepDistance and dist < resp.idealDist * 0.6 then
        return CAI.PHASE.COVER, "hold", 2, "shotgun_too_close"
    end
    if starved and dist < 2000 then
        data.coverBounces = 0
        data.lastEngageAt = CurTime()
        return CAI.PHASE.ENGAGE, "direct_fire", 2.5, "hold_and_fight"
    end
    if data.squadPlan == "push" or agg > 0.72 or dist < 600 then
        return CAI.PHASE.ENGAGE, "direct_fire", 3, "aggressive_push"
    end
    if data.squadPlan == "retreat" then
        return CAI.PHASE.WITHDRAW, "tactical", 4, "squad_retreat"
    end

    data.coverBounces = 0
    data.lastEngageAt = CurTime()
    return CAI.PHASE.ENGAGE, "direct_fire", 2.5, "engage_target"
end)
