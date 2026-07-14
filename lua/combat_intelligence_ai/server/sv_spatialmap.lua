CAI.SpatialMap = CAI.SpatialMap or {}
local SM = CAI.SpatialMap
local B = CAI.Battlefield

local function posKey(pos)
    return math.floor(pos.x / 128) .. ":" .. math.floor(pos.y / 128)
end

local function TraceDown(pos)
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 64),
        endpos = pos - Vector(0, 0, 200),
        mask = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then return tr.HitPos + Vector(0, 0, 2) end
    return nil
end

local function GetAreaWidth(area)
    if not IsValid(area) then return 0 end
    local corners = {
        area:GetCorner(0), area:GetCorner(1),
        area:GetCorner(2), area:GetCorner(3),
    }
    local minSqr, maxSqr = math.huge, 0
    for i = 1, 4 do
        for j = i + 1, 4 do
            if IsValid(corners[i]) and IsValid(corners[j]) then
                local d = corners[i]:DistToSqr(corners[j])
                if d < minSqr then minSqr = d end
                if d > maxSqr then maxSqr = d end
            end
        end
    end
    return math.sqrt(minSqr)
end

local function DetectChokepoint(area)
    if not IsValid(area) then return nil end
    local neighbors = area:GetAdjacentAreas()
    if not neighbors or #neighbors == 0 then return nil end
    local numConnections = #neighbors
    local width = GetAreaWidth(area)
    local cfg = CAI.Config.SpatialMap
    if numConnections <= cfg.DoorwayMaxConnections and width < cfg.ChokepointWidth then
        return { pos = area:GetCenter(), width = width }
    end
    return nil
end

local function DetectHighGround(area)
    if not IsValid(area) then return nil end
    local center = area:GetCenter()
    local neighbors = area:GetAdjacentAreas()
    if not neighbors or #neighbors < 2 then return nil end
    local neighborAvgZ = 0
    local count = 0
    for _, n in ipairs(neighbors) do
        if IsValid(n) then
            neighborAvgZ = neighborAvgZ + n:GetCenter().z
            count = count + 1
        end
    end
    if count == 0 then return nil end
    neighborAvgZ = neighborAvgZ / count
    local heightAdv = center.z - neighborAvgZ
    if heightAdv < CAI.Config.SpatialMap.HighGroundThreshold then return nil end
    local exposedEdges = 0
    for _, dir in ipairs({ Vector(1,0,0), Vector(-1,0,0), Vector(0,1,0), Vector(0,-1,0) }) do
        local tr = util.TraceLine({
            start = center + Vector(0, 0, 48),
            endpos = center + Vector(0, 0, 48) + dir * 400,
            mask = MASK_SOLID_BRUSHONLY,
        })
        if not tr.Hit then exposedEdges = exposedEdges + 1 end
    end
    if exposedEdges < 2 then return nil end
    return { pos = center, advantage = heightAdv / 48 }
end

local function DetectDoorway(area)
    if not IsValid(area) then return nil end
    local neighbors = area:GetAdjacentAreas()
    if not neighbors then return nil end
    local cfg = CAI.Config.SpatialMap
    if #neighbors ~= cfg.DoorwayMaxConnections then return nil end
    local width = GetAreaWidth(area)
    if width > cfg.ChokepointWidth then return nil end
    local c0, c1 = neighbors[1]:GetCenter(), neighbors[2]:GetCenter()
    if not c0 or not c1 then return nil end
    local toFar = (c0 - c1)
    toFar.z = 0
    if toFar:LengthSqr() < 1 then return nil end
    local normal = toFar:GetNormalized()
    return { pos = area:GetCenter(), normal = normal }
end

local function BuildRoom(startArea, visited)
    if not IsValid(startArea) then return nil end
    local queue = { startArea }
    visited[startArea:GetID()] = true
    local areas = { startArea }
    local maxRooms = 12
    local iterations = 0
    while #queue > 0 and iterations < maxRooms * 6 do
        iterations = iterations + 1
        local current = table.remove(queue, 1)
        local neighbors = current:GetAdjacentAreas() or {}
        for _, n in ipairs(neighbors) do
            if IsValid(n) and not visited[n:GetID()] then
                local center = n:GetCenter()
                local sizeX = n:GetSizeX() or 0
                local sizeY = n:GetSizeY() or 0
                local areaSize = sizeX * sizeY
                if areaSize > 500 then
                    visited[n:GetID()] = true
                    queue[#queue + 1] = n
                    areas[#areas + 1] = n
                end
            end
        end
    end
    if #areas < CAI.Config.SpatialMap.RoomMinAreas then return nil end
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    local sumZ = 0
    local entries = {}
    local exits = {}
    for _, a in ipairs(areas) do
        local c = a:GetCenter()
        if c.x < minX then minX = c.x end
        if c.x > maxX then maxX = c.x end
        if c.y < minY then minY = c.y end
        if c.y > maxY then maxY = c.y end
        sumZ = sumZ + c.z
        local neighbors = a:GetAdjacentAreas() or {}
        local internalNeighbors = 0
        for _, n in ipairs(neighbors) do
            if IsValid(n) and visited[n:GetID()] then
                internalNeighbors = internalNeighbors + 1
            end
        end
        local totalNeighbors = #neighbors
        if totalNeighbors > 0 and internalNeighbors < totalNeighbors then
            local isEntry = false
            for _, e in ipairs(entries) do
                if c:DistToSqr(e) < 200 * 200 then isEntry = true break end
            end
            if not isEntry then
                entries[#entries + 1] = c
            end
        end
    end
    local center = Vector((minX + maxX) / 2, (minY + maxY) / 2, sumZ / #areas)
    local radius = math.max(maxX - minX, maxY - minY) / 2
    return {
        center = center,
        radius = math.max(radius, 200),
        size = #areas,
        entries = entries,
    }
end

local function DetectFlankRoute(fromArea, toArea)
    if not IsValid(fromArea) or not IsValid(toArea) then return nil end
    local fromCenter = fromArea:GetCenter()
    local toCenter = toArea:GetCenter()
    local directDir = (toCenter - fromCenter)
    directDir.z = 0
    if directDir:LengthSqr() < 200 * 200 then return nil end
    local directLen = directDir:Length()
    directDir:Normalize()
    local right = Vector(-directDir.y, directDir.x, 0)
    local midPoint = fromCenter + directDir * (directLen * 0.5) + right * (directLen * 0.4)
    local midArea = navmesh.GetNearestNavArea(midPoint, false, 500, false, true)
    if not IsValid(midArea) then return nil end
    local midCenter = midArea:GetCenter()
    local deviation = midCenter:Distance(fromCenter + directDir * (directLen * 0.5))
    if deviation < 100 then return nil end
    local path = { fromCenter, midCenter, toCenter }
    return { from = fromCenter, to = toCenter, path = path }
end

function SM.Scan(squad)
    if not squad then return end
    local now = CurTime()
    local sm = squad.blackboard.spatialMap
    local cfg = CAI.Config.SpatialMap
    if now - sm.lastScan < cfg.ScanInterval then return end
    sm.lastScan = now
    local allAreas = navmesh.GetAllNavAreas() or {}
    local areaCount = #allAreas
    local startIdx = sm.scanIdx or 0
    local budget = cfg.ScanBudget
    local sampled = {}
    for i = startIdx + 1, math.min(startIdx + budget, areaCount) do
        if IsValid(allAreas[i]) then
            sampled[#sampled + 1] = allAreas[i]
        end
    end
    sm.scanIdx = (startIdx + budget) % math.max(areaCount, 1)
    allAreas = sampled
    local chokepointsFound = 0
    local highGroundFound = 0
    local doorwaysFound = 0
    for _, area in ipairs(allAreas) do
        local cp = DetectChokepoint(area)
        if cp then
            B.ReportChokepoint(squad, cp.pos, cp.width)
            chokepointsFound = chokepointsFound + 1
        end
        local hg = DetectHighGround(area)
        if hg then
            B.ReportHighGround(squad, hg.pos, hg.advantage)
            highGroundFound = highGroundFound + 1
        end
        local dg = DetectDoorway(area)
        if dg then
            B.ReportDoorway(squad, dg.pos, dg.normal)
            doorwaysFound = doorwaysFound + 1
        end
    end
    local visited = {}
    local leader = squad.leader
    if IsValid(leader) then
        local leaderArea = navmesh.GetNearestNavArea(leader:GetPos(), false, 600, false, true)
        if IsValid(leaderArea) then
            local room = BuildRoom(leaderArea, visited)
            if room then
                local existing = false
                for _, r in ipairs(sm.rooms) do
                    if r.center:DistToSqr(room.center) < 300 * 300 then
                        existing = true
                        break
                    end
                end
                if not existing and #sm.rooms < cfg.MaxRooms then
                    sm.rooms[#sm.rooms + 1] = room
                end
            end
        end
    end
    if #sm.flankRoutes < cfg.MaxFlankRoutes and #allAreas >= 2 then
        for i = 1, math.min(3, #allAreas) do
            local a1 = allAreas[math.random(#allAreas)]
            local a2 = allAreas[math.random(#allAreas)]
            if a1 ~= a2 then
                local route = DetectFlankRoute(a1, a2)
                if route then
                    local duplicate = false
                    for _, r in ipairs(sm.flankRoutes) do
                        if r.from:DistToSqr(route.from) < 200 * 200
                           and r.to:DistToSqr(route.to) < 200 * 200 then
                            duplicate = true
                            break
                        end
                    end
                    if not duplicate then
                        B.ReportFlankRoute(squad, route.from, route.to, route.path)
                    end
                end
            end
        end
    end
end

function SM.DiscoverDoorway(squad, pos, normal)
    if not squad then return end
    B.ReportDoorway(squad, pos, normal)
end

function SM.DiscoverFlankRoute(squad, fromPos, toPos)
    if not squad then return end
    B.ReportFlankRoute(squad, fromPos, toPos, { fromPos, toPos })
end

timer.Create("CAI_SpatialMapScan", 1.0, 0, function()
    if not CAI.Enabled() then return end
    for _, squad in pairs(CAI.Squad.Squads) do
        SM.Scan(squad)
    end
end)

CAI.Prof.WrapFn(SM, "Scan", "spatialmap_scan")
