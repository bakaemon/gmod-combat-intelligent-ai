local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action (lost target): valid enemy, but not currently visible.
-- Ordered to match the original lost branch: squad suppress order, separated
-- from squad, flank, then investigate / search / re-acquire.
table.insert(BR.COA.Target, function(ctx)
    local data, npc, enemy, rec = ctx.data, ctx.npc, ctx.enemy, ctx.rec
    if not IsValid(enemy) or ctx.visible then return end

    if data.suppressUntil and CurTime() < data.suppressUntil then
        return CAI.STATE.SUPPRESS, "squad_suppress_order"
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and data.role ~= CAI.ROLE.FLANKER
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700 then
        BR.StopSuppressing(data)
        return CAI.STATE.REGROUP, "separated_from_squad"
    end
    if data.flank then
        return CAI.STATE.FLANK, "flank_in_progress"
    end

    local patience = 1.5 + (data.personality.stats.patience or 0) * 3
    local staleFor = rec and (CurTime() - rec.t) or math.huge
    if staleFor < patience then
        if rec and npc:GetPos():DistToSqr(rec.pos) < 350 * 350 then
            if ctx.dangerAvoid and CAI.Memory.AvoidPos(data, rec.pos,
                CAI.Config.SelfPreserve.DangerAvoid.AllyDeathRadius) then
                return CAI.STATE.COVER, "await_reacquire"
            end
            if ctx.holdUnknown and ctx.squadCovering()
               and not (data.squadPlan == "push" or data.squadPlan == "flank") then
                return CAI.STATE.COVER, "await_reacquire"
            end
            data.investigatePos = rec.pos
            data.investigateUntil = CurTime() + 6
            return CAI.STATE.INVESTIGATE, "heard_close"
        end
        data.investigatePos = rec.pos
        data.investigateUntil = CurTime() + 6
        return CAI.STATE.INVESTIGATE, "reacquire_advance"
    end

    if data.search then
        return CAI.STATE.SEARCH, "search_in_progress"
    end
    if (CurTime() - (data.awaitAt or 0)) < 3 and not CAI.CVBool("cai_search") then
        data.awaitAt = data.awaitAt or CurTime()
        return CAI.STATE.COVER, "await_reacquire"
    end
    if CAI.CVBool("cai_search") then
        return CAI.STATE.SEARCH, "enemy_vanished"
    end
    return CAI.STATE.COVER, "await_reacquire"
end)
