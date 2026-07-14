CAI.Battlefield = CAI.Battlefield or {}
local B = CAI.Battlefield

function B.New()
    return {
        enemies = {},
        dangers = {},
        goodCover = {},
        badCover = {},
        deadAllies = {},
        suppressedAt = {},
        blockedPaths = {},
        spatialMap = {
            chokepoints = {},
            highGround = {},
            flankRoutes = {},
            rooms = {},
            doorways = {},
            lastScan = 0,
            scanIdx = 0,
        },
        patrolVisited = {},
    }
end

local function posKey(pos)
    return math.floor(pos.x / 64) .. ":" .. math.floor(pos.y / 64) .. ":" .. math.floor(pos.z / 64)
end
B.PosKey = posKey

function B.ReportEnemy(squad, enemy, pos, spotter)
    if not squad then return end
    if not CAI.Util.IsTargetable(enemy) then return end
    if enemy:GetClass() == "npc_bullseye" then return end
    squad.blackboard.enemies[enemy] = { pos = pos, t = CurTime(), spotter = spotter }
    if CAI.CVBool("cai_comms") then
        for _, member in ipairs(squad.members) do
            local d = CAI.Manager and CAI.Manager.Get(member)
            if d and member ~= spotter then
                CAI.Memory.HearEnemy(d, enemy, pos)
            end
        end
    end
end

function B.ReportDanger(squad, pos, radius, reason)
    if not squad then return end
    local d = squad.blackboard.dangers
    d[#d + 1] = { pos = pos, radius = radius, t = CurTime(), reason = reason }
    if #d > 16 then table.remove(d, 1) end
    if CAI.CVBool("cai_comms") then
        for _, member in ipairs(squad.members) do
            local md = CAI.Manager and CAI.Manager.Get(member)
            if md then CAI.Memory.AddDanger(md, pos, radius, reason) end
        end
    end
end

function B.MarkCover(squad, pos, success)
    if not squad then return end
    local key = posKey(pos)
    local map = success and squad.blackboard.goodCover or squad.blackboard.badCover
    map[key] = (map[key] or 0) + 1
end

function B.CoverHistory(squad, pos)
    if not squad then return 0 end
    local key = posKey(pos)
    local good = squad.blackboard.goodCover[key] or 0
    local bad = squad.blackboard.badCover[key] or 0
    if good + bad == 0 then return 0 end
    return math.Clamp((good - bad) / math.max(good + bad, 1), -1, 1)
end

function B.Prune(squad)
    local now = CurTime()
    for ent, rec in pairs(squad.blackboard.enemies) do
        if not IsValid(ent) or now - rec.t > CAI.Config.Memory.EnemyTTL then
            squad.blackboard.enemies[ent] = nil
        end
    end
    for i = #squad.blackboard.dangers, 1, -1 do
        if now - squad.blackboard.dangers[i].t > CAI.Config.Memory.DangerTTL then
            table.remove(squad.blackboard.dangers, i)
        end
    end
    local sm = squad.blackboard.spatialMap
    for i = #sm.chokepoints, 1, -1 do
        if now - sm.chokepoints[i].discoveredAt > CAI.Config.SpatialMap.ChokepointTTL then
            table.remove(sm.chokepoints, i)
        end
    end
    for i = #sm.flankRoutes, 1, -1 do
        if now - sm.flankRoutes[i].discoveredAt > CAI.Config.SpatialMap.RouteTTL then
            table.remove(sm.flankRoutes, i)
        end
    end
    for i = #sm.doorways, 1, -1 do
        if now - sm.doorways[i].discoveredAt > CAI.Config.SpatialMap.ChokepointTTL then
            table.remove(sm.doorways, i)
        end
    end
end

function B.ReportChokepoint(squad, pos, width)
    if not squad then return end
    local sm = squad.blackboard.spatialMap
    for _, cp in ipairs(sm.chokepoints) do
        if cp.pos:DistToSqr(pos) < 100 * 100 then return end
    end
    if #sm.chokepoints >= CAI.Config.SpatialMap.MaxChokepoints then return end
    sm.chokepoints[#sm.chokepoints + 1] = {
        pos = Vector(pos), width = width, discoveredAt = CurTime(),
    }
end

function B.ReportHighGround(squad, pos, advantage)
    if not squad then return end
    local sm = squad.blackboard.spatialMap
    for _, hg in ipairs(sm.highGround) do
        if hg.pos:DistToSqr(pos) < 150 * 150 then return end
    end
    if #sm.highGround >= CAI.Config.SpatialMap.MaxHighGround then return end
    sm.highGround[#sm.highGround + 1] = {
        pos = Vector(pos), advantage = advantage, discoveredAt = CurTime(),
    }
end

function B.ReportDoorway(squad, pos, normal)
    if not squad then return end
    local sm = squad.blackboard.spatialMap
    for _, dg in ipairs(sm.doorways) do
        if dg.pos:DistToSqr(pos) < 80 * 80 then return end
    end
    if #sm.doorways >= CAI.Config.SpatialMap.MaxDoorways then return end
    sm.doorways[#sm.doorways + 1] = {
        pos = Vector(pos), normal = Vector(normal), discoveredAt = CurTime(),
    }
end

function B.ReportFlankRoute(squad, fromPos, toPos, path)
    if not squad then return end
    local sm = squad.blackboard.spatialMap
    if #sm.flankRoutes >= CAI.Config.SpatialMap.MaxFlankRoutes then return end
    sm.flankRoutes[#sm.flankRoutes + 1] = {
        from = Vector(fromPos), to = Vector(toPos),
        path = path or {}, discoveredAt = CurTime(),
    }
end

function B.GetNearestChokepoint(squad, pos, maxDist)
    if not squad then return nil end
    local sm = squad.blackboard.spatialMap
    local best, bestD = nil, maxDist * maxDist
    for _, cp in ipairs(sm.chokepoints) do
        local d = pos:DistToSqr(cp.pos)
        if d < bestD then best, bestD = cp, d end
    end
    return best
end

function B.GetFlankingRoute(squad, fromPos, toPos)
    if not squad then return nil end
    local sm = squad.blackboard.spatialMap
    local best, bestScore = nil, -math.huge
    for _, route in ipairs(sm.flankRoutes) do
        local dFrom = fromPos:DistToSqr(route.from)
        local dTo = toPos:DistToSqr(route.to)
        local score = -(dFrom + dTo)
        if score > bestScore then best, bestScore = route, score end
    end
    return best
end

function B.GetRoomAt(squad, pos)
    if not squad then return nil end
    local sm = squad.blackboard.spatialMap
    for _, room in ipairs(sm.rooms) do
        if pos:DistToSqr(room.center) < room.radius * room.radius then
            return room
        end
    end
    return nil
end

function B.GetPatrolPoints(squad, pos, radius)
    if not squad then return {} end
    local sm = squad.blackboard.spatialMap
    local radSqr = radius * radius
    local out = {}
    local function add(p, kind)
        if p and pos:DistToSqr(p) < radSqr then
            out[#out + 1] = { pos = p, key = posKey(p), kind = kind }
        end
    end
    for _, cp in ipairs(sm.chokepoints) do add(cp.pos, "chokepoint") end
    for _, hg in ipairs(sm.highGround) do add(hg.pos, "highground") end
    for _, dw in ipairs(sm.doorways) do add(dw.pos, "doorway") end
    for _, rm in ipairs(sm.rooms) do add(rm.center, "room") end
    return out
end

function B.PatrolVisitedAt(squad, key)
    if not squad then return 0 end
    return squad.blackboard.patrolVisited[key] or 0
end

function B.MarkPatrolVisited(squad, key)
    if not squad or not key then return end
    squad.blackboard.patrolVisited[key] = CurTime()
end

function B.PrunePatrolVisited(squad, ttl)
    if not squad then return end
    local pv = squad.blackboard.patrolVisited
    local cutoff = CurTime() - ttl
    for k, t in pairs(pv) do
        if t < cutoff then pv[k] = nil end
    end
end

CAI.Prof.WrapFn(B, "ReportEnemy", "battlefield_repenemy")
