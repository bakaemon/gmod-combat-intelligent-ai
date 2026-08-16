local BR = CAI.Brain

local function hasCover(data)
    if data._coverCheckAt and CurTime() - data._coverCheckAt < 0.5 then
        return data._coverAvailable
    end
    local enemy, rec = CAI.Memory.FreshestEnemy(data)
    data._coverCheckAt = CurTime()
    data._coverAvailable = CAI.Cover.FindBest(data, enemy, rec and rec.pos) ~= nil
    return data._coverAvailable
end

BR.RegisterHook("brain/ooda/target", "all_lost_target_coa", function(ctx)
    if ctx.phase then return end
    local data, npc, enemy, rec = ctx.data, ctx.npc, ctx.enemy, ctx.rec
    if not IsValid(enemy) or ctx.visible then return end

    if data.suppressUntil and CurTime() < data.suppressUntil then
        if data.squad and #data.squad.members > 1
           and data.role ~= CAI.ROLE.SUPPRESSOR then
        else
            ctx.phase = CAI.PHASE.ENGAGE
            ctx.intent = "suppress"
            ctx.duration = 3
            ctx.reason = "squad_suppress_order"
            return
        end
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and data.role ~= CAI.ROLE.FLANKER
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700 then
        BR.StopSuppressing(data)
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "regroup"
        ctx.duration = 4
        ctx.reason = "separated_from_squad"
        return
    end
    if data.flank then
        ctx.phase = CAI.PHASE.MANEUVER
        ctx.intent = "flank"
        ctx.duration = 1.5
        ctx.reason = "flank_in_progress"
        return
    end

    local patience = 1.5 + (data.personality.stats.patience or 0) * 3
    local staleFor = rec and (CurTime() - rec.t) or math.huge
    if staleFor < patience then
        if rec and npc:GetPos():DistToSqr(rec.pos) < 350 * 350 then
            if ctx.dangerAvoid and CAI.Memory.AvoidPos(data, rec.pos,
                CAI.Config.SelfPreserve.DangerAvoid.AllyDeathRadius) then
                if hasCover(data) then
                    ctx.phase = CAI.PHASE.COVER
                    ctx.intent = "hold"
                    ctx.duration = 2
                    ctx.reason = "await_reacquire"
                    return
                end
            end
            if ctx.holdUnknown and ctx.squadCovering()
               and not (data.squadPlan == "push" or data.squadPlan == "flank") then
                if hasCover(data) then
                    ctx.phase = CAI.PHASE.COVER
                    ctx.intent = "hold"
                    ctx.duration = 2
                    ctx.reason = "await_reacquire"
                    return
                end
            end
            data.investigatePos = rec.pos
            data.investigateUntil = CurTime() + 6
            ctx.phase = CAI.PHASE.PRE_CONTACT
            ctx.intent = "investigate"
            ctx.duration = 5
            ctx.reason = "heard_close"
            return
        end
        data.investigatePos = rec.pos
        data.investigateUntil = CurTime() + 6
        ctx.phase = CAI.PHASE.PRE_CONTACT
        ctx.intent = "investigate"
        ctx.duration = 5
        ctx.reason = "reacquire_advance"
        return
    end

    if data.search then
        ctx.phase = CAI.PHASE.PRE_CONTACT
        ctx.intent = "search"
        ctx.duration = 4
        ctx.reason = "search_in_progress"
        return
    end
    if (CurTime() - (data.awaitAt or 0)) < 3 and not CAI.CVBool("cai_search") then
        data.awaitAt = data.awaitAt or CurTime()
        if hasCover(data) then
            ctx.phase = CAI.PHASE.COVER
            ctx.intent = "hold"
            ctx.duration = 2
            ctx.reason = "await_reacquire"
            return
        end
    end
    if CAI.CVBool("cai_search") then
        ctx.phase = CAI.PHASE.PRE_CONTACT
        ctx.intent = "search"
        ctx.duration = 4
        ctx.reason = "enemy_vanished"
        return
    end
    if hasCover(data) then
        ctx.phase = CAI.PHASE.COVER
        ctx.intent = "hold"
        ctx.duration = 2
        ctx.reason = "await_reacquire"
    end
end)