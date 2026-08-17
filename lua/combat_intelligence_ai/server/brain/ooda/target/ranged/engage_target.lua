local BR = CAI.Brain

BR.RegisterHook("brain/ooda/target", "ranged_engage_target", function(ctx)
    if ctx.phase then return end
    local data, npc, enemy, rec = ctx.data, ctx.npc, ctx.enemy, ctx.rec

    if not ctx.visible and enemy and rec and not data.flank
       and npc:GetPos():Distance(enemy:GetPos()) < CAI.Config.Engage.BlindPushRange
       and CurTime() - rec.t < 2.0 then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "direct_fire"
        ctx.duration = 2.5
        ctx.reason = "cqb_known_push"
        return
    end
    if not ctx.visible then return end

    local resp = data.enemyWeaponResponse
    local agg = CAI.WeaponIntel.EffectiveAggression(data)
    local dist = npc:GetPos():Distance(enemy:GetPos())

    if dist < 500 then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "direct_fire"
        ctx.duration = 2
        ctx.reason = "close_range_engage"
        return
    end

    data.coverBounces = data.coverBounces or 0
    if not CAI.PhaseIs(data, CAI.PHASE.COVER) then data.lastEngageAt = CurTime() end
    local coverStuck = CAI.PhaseIs(data, CAI.PHASE.COVER) and (data.coverSearchFailures or 0) >= 2
    local starved = CurTime() - (data.lastEngageAt or CurTime()) > 6
                     or data.coverBounces >= 3
                     or coverStuck

    if resp and resp.scatter then
        ctx.phase = CAI.PHASE.COVER
        ctx.intent = "hold"
        ctx.duration = 2
        ctx.reason = "rocket_threat"
        return
    end
    if resp and resp.keepDistance and dist < resp.idealDist * 0.6 then
        ctx.phase = CAI.PHASE.COVER
        ctx.intent = "hold"
        ctx.duration = 2
        ctx.reason = "shotgun_too_close"
        return
    end
    if starved and dist < 2000 then
        data.coverBounces = 0
        data.lastEngageAt = CurTime()
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "direct_fire"
        ctx.duration = 2.5
        ctx.reason = "hold_and_fight"
        return
    end
    if data.squadPlan == "push" or agg > 0.72 or dist < 600 then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "direct_fire"
        ctx.duration = 3
        ctx.reason = "aggressive_push"
        return
    end
    if data.squadPlan == "retreat" then
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "tactical"
        ctx.duration = 4
        ctx.reason = "squad_retreat"
        return
    end

    data.coverBounces = 0
    data.lastEngageAt = CurTime()
    ctx.phase = CAI.PHASE.ENGAGE
    ctx.intent = "direct_fire"
    ctx.duration = 2.5
    ctx.reason = "engage_target"
end)