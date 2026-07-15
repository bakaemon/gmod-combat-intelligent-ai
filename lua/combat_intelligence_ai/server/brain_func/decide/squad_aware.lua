local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: no visible enemy, but the squad is pushing/flanking into a
-- nearby friendly battle; commit to investigating it (or hold unknown angles).
table.insert(BR.COA.Target, function(ctx)
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
        if data.state == CAI.STATE.PATROL then
            commitment = 10
        elseif data.state == CAI.STATE.IDLE then
            commitment = 5
        elseif data.state == CAI.STATE.COVER then
            if data.suppression > CAI.Config.Suppression.PinnedAt then
                commitment = 80
            elseif data.suppression > 30 then
                commitment = 50
            else
                commitment = 20
            end
        elseif data.state == CAI.STATE.INVESTIGATE then
            commitment = 15
        elseif data.state == CAI.STATE.SEARCH then
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
            if ctx.holdUnknown and not (data.wantBound and data.boundTarget)
               and not (data.squadPlan == "push" or data.squadPlan == "flank") then
                return CAI.STATE.COVER, "await_reacquire"
            end
            data.investigatePos = battlePos
            data.investigateUntil = CurTime() + 15
            return CAI.STATE.INVESTIGATE, "nearby_battle"
        end
    end

    if data.reinforceTarget then
        return CAI.STATE.REGROUP, "reinforcing"
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 1100 * 1100 then
        return CAI.STATE.REGROUP, "rejoin_squad"
    end
    if data.investigatePos and CurTime() < (data.investigateUntil or 0) then
        return CAI.STATE.INVESTIGATE, "heard_something"
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700 then
        return CAI.STATE.REGROUP, "rejoin_squad"
    end
end)
