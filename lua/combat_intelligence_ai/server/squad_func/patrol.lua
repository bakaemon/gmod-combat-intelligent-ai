local SF = CAI.SquadFunc

function SF.PlanPatrol(squad)
    local leader = squad.leader
    if not IsValid(leader) then return end
    local now = CurTime()
    local patrolInterval = CAI.Config.Plan.Interval or 0.5
    if squad._patrolAt and now - squad._patrolAt < patrolInterval then return end
    squad._patrolAt = now

    local leaderPos = leader:GetPos()
    local RADIUS = 1500

    if squad.patrolPos then
        local arrived = leader:GetPos():DistToSqr(squad.patrolPos) < 120 * 120
        if not arrived then return end
        CAI.SpatialMap.RecordTemp(squad, squad.patrolPos, -CAI.Config.Heatmap.PatrolDecrement)
    end

    local chosen, chosenKey
    local sm = squad.blackboard.spatialMap
    local cellSize = CAI.Config.Cover.CellSize
    local heatCfg = CAI.Config.Heatmap
    local cellR = math.ceil(heatCfg.PatrolRadius / cellSize)
    local cx, cy = math.floor(leaderPos.x / cellSize), math.floor(leaderPos.y / cellSize)
    local bestUncleared, bestUnclearedKey, bestDist = nil, nil, math.huge
    for dx = -cellR, cellR do
        for dy = -cellR, cellR do
            local key = (cx + dx) .. ":" .. (cy + dy)
            local h = sm.heatmap[key]
            if h and h.temp >= heatCfg.Baseline - 2 then
                local cellCenter = Vector((cx + dx + 0.5) * cellSize, (cy + dy + 0.5) * cellSize, leaderPos.z)
                local d = leaderPos:DistToSqr(cellCenter)
                if d < bestDist then
                    bestUncleared, bestUnclearedKey, bestDist = key, key, d
                end
            end
        end
    end
    if bestUncleared and bestUnclearedKey then
        local matchX, matchY = bestUnclearedKey:match("^(-?%d+):(-?%d+)$")
        if matchX and matchY then
            local center = Vector((tonumber(matchX) + 0.5) * cellSize, (tonumber(matchY) + 0.5) * cellSize, leaderPos.z)
            local cand = CAI.Nav.RandomPointNear(center, cellSize * 0.5, true)
            if cand then
                local safe = CAI.Nav.SafeGround(cand)
                if safe then
                    local reachAreas = CAI.Nav.ReachableAreas(leaderPos)
                    if reachAreas then
                        local area = navmesh.GetNearestNavArea(safe)
                        if IsValid(area) and reachAreas[area] then
                            chosen, chosenKey = safe, CAI.Battlefield.PosKey(safe)
                        end
                    end
                end
            end
        end
    end

    local best, bestKey, bestD = nil, nil, math.huge
    for _, poi in ipairs(CAI.Battlefield.GetPatrolPoints(squad, leaderPos, RADIUS)) do
        local d = leaderPos:DistToSqr(poi.pos)
        if d < bestD and d > 300 * 300 then
            local key = poi.key or CAI.Battlefield.PosKey(poi.pos)
            if not key or CAI.Battlefield.PatrolVisitedAt(squad, key) == 0 then
                best, bestKey, bestD = poi.pos, key, d
            end
        end
    end
    if best then chosen, chosenKey = best, bestKey end

    if not chosen then
        for _ = 1, 6 do
            local cand = CAI.Nav.RandomPointNear(leaderPos, RADIUS, true)
            if cand and cand:DistToSqr(leaderPos) > 300 * 300 then
                local key = cand and CAI.Battlefield.PosKey(cand)
                if not key or CAI.Battlefield.PatrolVisitedAt(squad, key) == 0 then
                    chosen, chosenKey = cand, key
                    break
                end
            end
        end
    end

    if not chosen then
        for _, yaw in ipairs({ 0, 45, -45, 90, -90, 135, -135, 180 }) do
            local dir = Angle(0, yaw, 0):Forward()
            local cand = CAI.Nav.SafeGround(leaderPos + dir * 400)
            if cand then
                chosen, chosenKey = cand, CAI.Battlefield.PosKey(cand)
                break
            end
        end
    end

    if chosen then
        squad.patrolPos = chosen
        squad.patrolKey = chosenKey
        if chosenKey then CAI.Battlefield.MarkPatrolVisited(squad, chosenKey) end
    end
end
