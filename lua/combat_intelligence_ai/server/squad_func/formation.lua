local SF = CAI.SquadFunc

function SF.SquadIndex(squad, npc)
    for i, m in ipairs(squad.members) do
        if m == npc then return i end
    end
    return nil
end

function SF.FormationSlot(squad, index)
    local leader = squad.leader
    if not IsValid(leader) then return nil end
    local offsets = CAI.Config.Formations[squad.formation] or CAI.Config.Formations.WEDGE
    local o = offsets[math.min(index, #offsets)]
    if not o then return nil end
    local fwd = leader:GetForward(); fwd.z = 0; fwd:Normalize()
    local right = leader:GetRight(); right.z = 0; right:Normalize()
    return leader:GetPos() + fwd * o[1] + right * o[2]
end

function SF.UpdateFormation(squad, inCombat, indoors)
    if not CAI.CVBool("cai_formations") then return end
    local nearChokepoint = false
    local isCorridor = false
    local sm = squad.blackboard and squad.blackboard.spatialMap
    if sm and IsValid(squad.leader) then
        local cp = CAI.Battlefield.GetNearestChokepoint(squad, squad.leader:GetPos(), 400)
        if cp then nearChokepoint = true end
        local leaderArea = navmesh.GetNearestNavArea(squad.leader:GetPos())
        if IsValid(leaderArea) and leaderArea.GetSizeX and leaderArea:GetSizeX() < 80 then
            isCorridor = true
        end
    end
    if inCombat then
        if nearChokepoint or isCorridor then
            squad.formation = "STACK"
        else
            squad.formation = "LINE"
        end
    elseif isCorridor then
        squad.formation = "FILE"
    elseif indoors then
        squad.formation = math.random() < 0.5 and "FILE" or "STACK"
    elseif #squad.members >= 5 then
        squad.formation = "DIAMOND"
    else
        squad.formation = "WEDGE"
    end
end

function SF.PositionSpacing(data, pos, minDist)
    local squad = data.squad
    if not squad then return true end
    for _, m in ipairs(squad.members) do
        if IsValid(m) and m ~= data.ent then
            if m:GetPos():DistToSqr(pos) < minDist * minDist then
                return false
            end
        end
    end
    return true
end

function SF.FormationCheck(data)
    local squad = data.squad
    if not squad or #squad.members <= 1 then return true end
    local radius = CAI.Config.SquadTactics.FormationBreakRadius or 600
    local radiusSq = radius * radius
    for _, m in ipairs(squad.members) do
        if IsValid(m) and m ~= data.ent then
            if data.ent:GetPos():DistToSqr(m:GetPos()) < radiusSq then
                return true
            end
        end
    end
    return false
end

function SF.SquadCenterOfMass(squad, filterSelf, maxDist)
    local count, acc = 0, Vector()
    for _, m in ipairs(squad.members) do
        if IsValid(m) and (not filterSelf or m ~= filterSelf) then
            local d = maxDist and filterSelf and filterSelf:GetPos():DistToSqr(m:GetPos()) or 0
            if not maxDist or d < maxDist * maxDist then
                acc = acc + m:GetPos()
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    return acc / count
end
