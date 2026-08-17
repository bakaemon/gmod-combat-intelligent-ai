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
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "flee"
        ctx.duration = 4
        ctx.reason = "morale_broken"
        return
    end
    local mcfg = CAI.Config.Melee
    local pounceSqr = mcfg.Ambush.PounceDist * mcfg.Ambush.PounceDist
    if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < pounceSqr then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "melee"
        ctx.duration = 2
        ctx.reason = "melee_chase"
        return
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
            ctx.phase = CAI.PHASE.MANEUVER
            ctx.intent = "flank"
            ctx.duration = 2.5
            ctx.reason = "sneak_on_sniper"
            return
        end
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "melee"
        ctx.duration = 2.5
        ctx.reason = "melee_ambush"
        return
    end
    if arch == "shotgun" and agg < mcfg.ShotgunOverride then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "melee"
        ctx.duration = 2.5
        ctx.reason = "melee_ambush"
        return
    end
    if rush >= mcfg.RushThreshold then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "melee"
        ctx.duration = 2
        ctx.reason = "melee_chase"
        return
    end
    ctx.phase = CAI.PHASE.ENGAGE
    ctx.intent = "melee"
    ctx.duration = 2.5
    ctx.reason = "melee_ambush"
end)