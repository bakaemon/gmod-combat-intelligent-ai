local BR = CAI.Brain

BR.RegisterHook("brain/ooda/target", "all_squad_aware", function(ctx)
    if ctx.phase then return end
    local data, npc, enemy = ctx.data, ctx.npc, ctx.enemy
    if IsValid(enemy) or not data.squad
       or not (data.squad.plan == "push" or data.squad.plan == "flank") then
        return
    end

    local helpScore = 0
    local battlePos = nil
    local cfg = CAI.Config.SquadTactics
    for _, snd in ipairs(data.memory.sounds) do
        if snd.type == "battle" and CurTime() - snd.t < cfg.BattleAwarenessDuration then
            local dist = npc:GetPos():Distance(snd.pos)
            if dist < cfg.BattleAwarenessRadius then
                local distScore = math.Clamp(40 * (1 - dist / cfg.BattleAwarenessRadius), 0, 40)
                local freshScore = math.Clamp(20 * (1 - (CurTime() - snd.t) / cfg.BattleAwarenessDuration), 0, 20)
                local total = distScore + freshScore
                if total > helpScore then
                    helpScore = total
                    battlePos = snd.pos
                end
            end
        end
    end
    if helpScore > 0 and battlePos then
        local commitment = 0
        if CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "patrol") then
            commitment = 10
        elseif CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "idle") then
            commitment = 5
        elseif CAI.PhaseIs(data, CAI.PHASE.COVER) then
            if data.suppression > CAI.Config.Suppression.PinnedAt then
                commitment = 80
            elseif data.suppression > 30 then
                commitment = 50
            else
                commitment = 20
            end
        elseif CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "investigate") then
            commitment = 15
        elseif CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "search") then
            commitment = 25
        else
            commitment = 60
        end
        local courage = data.personality.stats.courage or 0
        local aggression = data.personality.stats.aggression or 0
        helpScore = helpScore + (courage * 10) + (aggression * 8)
        if data.morale > 70 then helpScore = helpScore + 10 end
        if data.morale < 25 then helpScore = helpScore - 20 end
        if helpScore > commitment then
            if ctx.holdUnknown and ctx.squadCovering()
               and not (data.squadPlan == "push" or data.squadPlan == "flank") then
                ctx.phase = CAI.PHASE.COVER
                ctx.intent = "hold"
                ctx.duration = 2
                ctx.reason = "await_reacquire"
                return
            end
            data.investigatePos = battlePos
            data.investigateUntil = CurTime() + 15
            ctx.phase = CAI.PHASE.PRE_CONTACT
            ctx.intent = "investigate"
            ctx.duration = 5
            ctx.reason = "nearby_battle"
            return
        end
    end

    if data.reinforceTarget then
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "regroup"
        ctx.duration = 4
        ctx.reason = "reinforcing"
        return
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 1100 * 1100 then
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "regroup"
        ctx.duration = 4
        ctx.reason = "rejoin_squad"
        return
    end
    if data.investigatePos and CurTime() < (data.investigateUntil or 0) then
        ctx.phase = CAI.PHASE.PRE_CONTACT
        ctx.intent = "investigate"
        ctx.duration = 5
        ctx.reason = "heard_something"
        return
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700 then
        ctx.phase = CAI.PHASE.WITHDRAW
        ctx.intent = "regroup"
        ctx.duration = 4
        ctx.reason = "rejoin_squad"
    end
end)