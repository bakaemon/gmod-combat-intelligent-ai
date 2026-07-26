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

table.insert(BR.COA.Target, function(ctx)
    local data, npc, enemy, rec = ctx.data, ctx.npc, ctx.enemy, ctx.rec
    if not IsValid(enemy) or ctx.visible then return end

    if data.suppressUntil and CurTime() < data.suppressUntil then
        if data.squad and #data.squad.members > 1
           and data.role ~= CAI.ROLE.SUPPRESSOR then
        else
            return CAI.PHASE.ENGAGE, "suppress", 3, "squad_suppress_order"
        end
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and data.role ~= CAI.ROLE.FLANKER
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700 then
        BR.StopSuppressing(data)
        return CAI.PHASE.WITHDRAW, "regroup", 4, "separated_from_squad"
    end
    if data.flank then
        return CAI.PHASE.MANEUVER, "flank", 1.5, "flank_in_progress"
    end

    local patience = 1.5 + (data.personality.stats.patience or 0) * 3
    local staleFor = rec and (CurTime() - rec.t) or math.huge
    if staleFor < patience then
        if rec and npc:GetPos():DistToSqr(rec.pos) < 350 * 350 then
            if ctx.dangerAvoid and CAI.Memory.AvoidPos(data, rec.pos,
                CAI.Config.SelfPreserve.DangerAvoid.AllyDeathRadius) then
                if hasCover(data) then return CAI.PHASE.COVER, "hold", 2, "await_reacquire" end
            end
            if ctx.holdUnknown and ctx.squadCovering()
               and not (data.squadPlan == "push" or data.squadPlan == "flank") then
                if hasCover(data) then return CAI.PHASE.COVER, "hold", 2, "await_reacquire" end
            end
            data.investigatePos = rec.pos
            data.investigateUntil = CurTime() + 6
            return CAI.PHASE.PRE_CONTACT, "investigate", 5, "heard_close"
        end
        data.investigatePos = rec.pos
        data.investigateUntil = CurTime() + 6
        return CAI.PHASE.PRE_CONTACT, "investigate", 5, "reacquire_advance"
    end

    if data.search then
        return CAI.PHASE.PRE_CONTACT, "search", 4, "search_in_progress"
    end
    if (CurTime() - (data.awaitAt or 0)) < 3 and not CAI.CVBool("cai_search") then
        data.awaitAt = data.awaitAt or CurTime()
        if hasCover(data) then return CAI.PHASE.COVER, "hold", 2, "await_reacquire" end
    end
    if CAI.CVBool("cai_search") then
        return CAI.PHASE.PRE_CONTACT, "search", 4, "enemy_vanished"
    end
    if hasCover(data) then return CAI.PHASE.COVER, "hold", 2, "await_reacquire" end
end)
