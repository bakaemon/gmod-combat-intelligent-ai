CAI.Nav = CAI.Nav or {}
local N = CAI.Nav

function N.MoveTo(data, pos, mode)
    local npc = data.ent
    if not IsValid(npc) or not pos then return false end

    local sched = mode == "walk" and SCHED_FORCED_GO or SCHED_FORCED_GO_RUN
    if data.moveTarget and data.moveTarget:DistToSqr(pos) < 48 * 48
       and CurTime() - (data.moveIssuedAt or 0) < 2
       and npc.IsCurrentSchedule and npc:IsCurrentSchedule(sched) then
        return true
    end

    npc:SetLastPosition(pos)
    npc:SetSchedule(sched)
    data.moveTarget = pos
    data.moveMode = mode
    data.moveIssuedAt = CurTime()
    data.fighting = nil
    data.combatMoveAt = data.combatMoveAt or CurTime()
    data.stuckPos = npc:GetPos()
    data.stuckChecks = 0
    return true
end

function N.Arrived(data, tolerance)
    if not data.moveTarget then return true end
    tolerance = tolerance or 70
    return data.ent:GetPos():DistToSqr(data.moveTarget) < tolerance * tolerance
end

function N.CheckStuck(data)
    local npc = data.ent
    if not data.moveTarget or N.Arrived(data) then
        data.stuckChecks = 0
        return false
    end

    local inGo = npc.IsCurrentSchedule and
        (npc:IsCurrentSchedule(SCHED_FORCED_GO) or npc:IsCurrentSchedule(SCHED_FORCED_GO_RUN))
    if inGo then
        if CurTime() - (data.moveIssuedAt or 0) > (CAI.Config.Nav and CAI.Config.Nav.StuckHardTimeout or 5) then
            N.Recover(data)
            return true
        end
        data.stuckChecks = 0
        return false
    end

    if CurTime() - (data.moveIssuedAt or 0) < 1.5 then return false end

    local moved = npc:GetPos():DistToSqr(data.stuckPos or npc:GetPos())
    data.stuckPos = npc:GetPos()

    if moved < 30 * 30 then
        data.stuckChecks = (data.stuckChecks or 0) + 1
    else
        data.stuckChecks = 0
    end

    if data.stuckChecks >= 4 then
        N.Recover(data)
        return true
    end
    return false
end

function N.Recover(data)
    local npc = data.ent
    data.stuckChecks = 0

    if data.squad then
        CAI.Battlefield.ReportDanger(data.squad, npc:GetPos(), 100, "blocked_path")
        local bp = data.squad.blackboard.blockedPaths
        bp[#bp + 1] = { pos = npc:GetPos(), t = CurTime() }
        if #bp > 10 then table.remove(bp, 1) end
    end

    local area = navmesh.GetNearestNavArea(npc:GetPos())
    if IsValid(area) then
        local neighbors = area:GetAdjacentAreas()
        if neighbors and #neighbors > 0 then
            local pick = neighbors[math.random(#neighbors)]
            if IsValid(pick) then
                data.moveTarget = nil
                N.MoveTo(data, pick:GetRandomPoint(), "run")
                return
            end
        end
    end

    data.moveTarget = nil
    npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
end

local function DryPoint(p)
    if not p then return nil end
    if N.IsDeepWater(p) then return nil end
    return p
end

function N.RandomPointNear(origin, radius, farBias)
    local areas = navmesh.Find(origin, radius, 120, 240)
    if not areas or #areas == 0 then return nil end
    if farBias then
        local minSqr = (radius * 0.5) * (radius * 0.5)
        local far = {}
        for _, a in ipairs(areas) do
            if IsValid(a) and a:GetCenter():DistToSqr(origin) > minSqr then
                far[#far + 1] = a
            end
        end
        if #far > 0 then areas = far end
    end
    local area = areas[math.random(#areas)]
    if not IsValid(area) then return nil end
    return DryPoint(area:GetRandomPoint())
end

function N.EnableDoorUse(npc)
    if npc.CapabilitiesAdd then
        npc:CapabilitiesAdd(bit.bor(CAP_OPEN_DOORS or 0, CAP_AUTO_DOORS or 0, CAP_MOVE_GROUND or 0, CAP_MOVE_JUMP or 0))
    end
end

function N.IsDeepWater(pos)
    return bit.band(util.PointContents(pos + Vector(0, 0, 36)), CONTENTS_WATER) ~= 0
end

function N.SafeGround(pos)
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 40),
        endpos = pos - Vector(0, 0, 300),
        mask = MASK_SOLID_BRUSHONLY,
    })
    if not tr.Hit then return nil end
    if pos.z - tr.HitPos.z > 160 then return nil end
    if N.IsDeepWater(tr.HitPos) then return nil end
    return tr.HitPos + Vector(0, 0, 2)
end

function N.IsGroundSpot(pos)
    if not pos then return false end
    local a = navmesh.GetNearestNavArea(pos)
    if not IsValid(a) or not a:Contains(pos) then return false end
    return true
end

function N.SafeOffset(from, dir, dist)
    local yaw = dir:Angle().y
    for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
        local d = Angle(0, yaw + off, 0):Forward()
        dest = N.SafeGround(from + d * dist)
        if dest then return dest end
    end
    return nil
end

function N.ReachableAreas(origin, maxNodes)
    local start = navmesh.GetNearestNavArea(origin)
    if not IsValid(start) then return nil end
    local seen, queue, out = { [start] = true }, { start }, { [start] = true }
    maxNodes = maxNodes or 256
    while #queue > 0 and #out < maxNodes do
        local cur = table.remove(queue, 1)
        local adj = cur:GetAdjacentAreas() or {}
        for _, n in ipairs(adj) do
            if IsValid(n) and not seen[n] then
                seen[n] = true
                out[n] = true
                queue[#queue + 1] = n
            end
        end
    end
    return out
end

CAI.Prof.WrapFn(N, "RandomPointNear", "nav_randompoint")
CAI.Prof.WrapFn(N, "SafeGround", "nav_safeground")
CAI.Prof.WrapFn(N, "SafeOffset", "nav_safeoffset")
CAI.Prof.WrapFn(N, "ReachableAreas", "nav_reachable")

