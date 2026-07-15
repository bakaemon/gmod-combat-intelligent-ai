local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action (visible): the core firefight. Reposition to the weapon's
-- ideal range and fire while staying friendly-fire aware; handle point-blank,
-- rocket/shotgun threats, starvation, aggressive push, and squad retreat.
table.insert(BR.COA.Target, function(ctx)
    -- Known, close, recently-perceived enemy: commit to a CQB push instead of
    -- dropping to INVESTIGATE/SEARCH on a transient LOS gap. The executor
    -- advances / establishes a sightline (exec/engage.lua), so the NPC pushes
    -- to re-acquire rather than freezing or creeping.
    if not ctx.visible and ctx.enemy and ctx.rec and not ctx.data.flank
       and ctx.npc:GetPos():Distance(ctx.enemy:GetPos()) < CAI.Config.Engage.BlindPushRange
       and CurTime() - ctx.rec.t < 2.0 then
        return CAI.STATE.ENGAGE, "cqb_known_push"
    end
    if not ctx.visible then return end
    local data, npc, enemy = ctx.data, ctx.npc, ctx.enemy

    local resp = data.enemyWeaponResponse
    local agg = CAI.WeaponIntel.EffectiveAggression(data)
    local dist = npc:GetPos():Distance(enemy:GetPos())

    if dist < 500 then
        return CAI.STATE.ENGAGE, "close_range_engage"
    end

    data.coverBounces = data.coverBounces or 0
    if data.state ~= CAI.STATE.COVER then data.lastEngageAt = CurTime() end
    local coverStuck = data.state == CAI.STATE.COVER and (data.coverSearchFailures or 0) >= 2
    local starved = CurTime() - (data.lastEngageAt or CurTime()) > 6
                     or data.coverBounces >= 3
                     or coverStuck

    if resp and resp.scatter then
        return CAI.STATE.COVER, "rocket_threat"
    end
    if resp and resp.keepDistance and dist < resp.idealDist * 0.6 then
        return CAI.STATE.COVER, "shotgun_too_close"
    end
    if starved and dist < 2000 then
        data.coverBounces = 0
        data.lastEngageAt = CurTime()
        return CAI.STATE.ENGAGE, "hold_and_fight"
    end
    if data.squadPlan == "push" or agg > 0.72 or dist < 600 then
        return CAI.STATE.ENGAGE, "aggressive_push"
    end
    if data.squadPlan == "retreat" then
        return CAI.STATE.RETREAT, "squad_retreat"
    end

    data.coverBounces = 0
    data.lastEngageAt = CurTime()
    return CAI.STATE.ENGAGE, "engage_target"
end)
