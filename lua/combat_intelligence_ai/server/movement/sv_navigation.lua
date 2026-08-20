CAI.Nav = CAI.Nav or {}
local N = CAI.Nav

local EXPECTED_SPEED = 110
local TIMEOUT_SLACK = 2.5
local MIN_HARD_TIMEOUT = 10
local MAX_HARD_TIMEOUT = 60
local PROGRESS_EPSILON = 48
local NO_PROGRESS_WINDOW = 7
local STALL_WINDOW = 2.5
local STALL_EPSILON = 24
local SETTLE_TIME = 1.5
local MAX_RECOVERIES = 3

function N.HasGoal(data)
    return data.moveGoal ~= nil and data.moveTarget ~= nil
end

function N.GoalOwner(data)
    return data.moveGoal and data.moveGoal.owner
end

function N.EngineDest(goal)
    return goal.detour or goal.pos
end

function N.ClearGoal(data)
    data.moveGoal = nil
    data.moveTarget = nil
    data.moveIssuedAt = nil
    data.stuckChecks = 0
end

function N.Orphan(data)
    local goal = data.moveGoal
    if not goal then
        data.moveTarget = nil
        data.moveIssuedAt = nil
        return
    end
    goal.owner = nil
    goal.orphanedAt = CurTime()
end

function N.Claim(data, owner)
    local goal = data.moveGoal
    if not goal then return end
    if not goal.owner and CAI.MoveGoal then CAI.MoveGoal.Bump("orphanReclaimed") end
    goal.owner = owner
    goal.orphanedAt = nil
end

local function hardTimeout(goal)
    local d = goal.startDist or 0
    return math.Clamp(d / EXPECTED_SPEED * TIMEOUT_SLACK, MIN_HARD_TIMEOUT, MAX_HARD_TIMEOUT)
end

function N.MoveTo(data, pos, mode, owner)
    local npc = data.ent
    if not IsValid(npc) or not pos then return false end

    if data.reflex and data.reflex.bias then
        pos = pos + data.reflex.bias
    end

    owner = owner or data.phaseIntent
    local sched = mode == "walk" and SCHED_FORCED_GO or SCHED_FORCED_GO_RUN
    local now = CurTime()
    local goal = data.moveGoal

    if goal and data.moveTarget and goal.pos:DistToSqr(pos) < 48 * 48 then
        N.Claim(data, owner)
        goal.mode = mode
        data.moveTarget = goal.pos
        data.moveMode = mode

        local inGo = npc.IsCurrentSchedule and npc:IsCurrentSchedule(sched)
        if inGo and now - (goal.issuedAt or 0) < 2 then return true end

        goal.issuedAt = now
        data.moveIssuedAt = now
        npc:SetLastPosition(N.EngineDest(goal))
        npc:SetSchedule(sched)
        return true
    end

    local here = npc:GetPos()
    local dist = here:Distance(pos)

    npc:SetLastPosition(pos)
    npc:SetSchedule(sched)

    data.moveGoal = {
        pos = pos,
        mode = mode,
        owner = owner,
        startedAt = now,
        issuedAt = now,
        startDist = dist,
        bestDist = dist,
        bestAt = now,
        stallPos = here,
        stallAt = now,
        recoveries = 0,
    }
    data.moveTarget = pos
    data.moveMode = mode
    data.moveIssuedAt = now
    data.fighting = nil
    data.combatMoveAt = data.combatMoveAt or now
    data.stuckPos = here
    data.stuckChecks = 0

    if CAI.MoveGoal then CAI.MoveGoal.Bump("issued") end
    return true
end

function N.ReflexMove(data, pos, mode)
    local npc = data.ent
    if not IsValid(npc) or not pos then return nil end

    if data.moveTarget then
        local dir = pos - data.moveTarget
        dir.z = 0
        if dir:LengthSqr() > 1 then
            return dir:GetNormalized() * 200
        end
        return nil
    end

    N.MoveTo(data, pos, mode or "run")
    return nil
end

function N.Arrived(data, tolerance)
    local goal = data.moveGoal
    if not goal or not data.moveTarget then return false end
    tolerance = tolerance or 70
    return data.ent:GetPos():DistToSqr(goal.pos) < tolerance * tolerance
end

function N.CheckStuck(data)
    local npc = data.ent
    local goal = data.moveGoal

    if not goal or not data.moveTarget then
        data.stuckChecks = 0
        return false
    end
    if N.Arrived(data) then
        data.stuckChecks = 0
        return false
    end

    local now = CurTime()
    local here = npc:GetPos()
    local remaining = here:Distance(goal.pos)

    if remaining < (goal.bestDist or remaining) - PROGRESS_EPSILON then
        goal.bestDist = remaining
        goal.bestAt = now
        data.stuckChecks = 0
    end

    if here:DistToSqr(goal.stallPos or here) > STALL_EPSILON * STALL_EPSILON then
        goal.stallPos = here
        goal.stallAt = now
    end

    data.stuckPos = here

    if now - (goal.startedAt or now) > hardTimeout(goal) then
        goal.timedOut = true
        N.Recover(data)
        return true
    end

    if now - (goal.issuedAt or goal.startedAt or now) < SETTLE_TIME then return false end
    if goal.detour then return false end

    if now - (goal.stallAt or now) > STALL_WINDOW then
        N.Recover(data)
        return true
    end

    if now - (goal.bestAt or now) > NO_PROGRESS_WINDOW then
        N.Recover(data)
        return true
    end

    return false
end

function N.Recover(data)
    local npc = data.ent
    local goal = data.moveGoal
    data.stuckChecks = 0

    if data.squad then
        CAI.Battlefield.ReportDanger(data.squad, npc:GetPos(), 100, "blocked_path")
        local bp = data.squad.blackboard.blockedPaths
        bp[#bp + 1] = { pos = npc:GetPos(), t = CurTime() }
        if #bp > 10 then table.remove(bp, 1) end
    end

    local function bail()
        N.ClearGoal(data)
        npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
        if CAI.MoveGoal then CAI.MoveGoal.Bump("abandoned") end
    end

    if not goal then
        local area = navmesh.GetNearestNavArea(npc:GetPos())
        if IsValid(area) then
            local neighbors = area:GetAdjacentAreas()
            if neighbors and #neighbors > 0 then
                local pick = neighbors[math.random(#neighbors)]
                if IsValid(pick) then
                    N.MoveTo(data, pick:GetRandomPoint(), "run", "recover")
                    return
                end
            end
        end
        bail()
        return
    end

    goal.recoveries = (goal.recoveries or 0) + 1
    if CAI.MoveGoal then CAI.MoveGoal.Bump("recovered") end

    if goal.recoveries > MAX_RECOVERIES then
        bail()
        return
    end

    local here = npc:GetPos()
    local area = navmesh.GetNearestNavArea(here)
    local hop

    if IsValid(area) then
        local neighbors = area:GetAdjacentAreas()
        if neighbors and #neighbors > 0 then
            local best, bestScore = nil, math.huge
            for _, n in ipairs(neighbors) do
                if IsValid(n) then
                    local c = n:GetCenter()
                    local score = c:Distance(goal.pos)
                    if goal.recoveries > 1 then score = score + math.Rand(0, 250) end
                    if score < bestScore then best, bestScore = n, score end
                end
            end
            if IsValid(best) then
                local p = best:GetRandomPoint()
                if p and not N.IsDeepWater(p) then hop = p end
            end
        end
    end

    if not hop then
        hop = N.SafeOffset(here, (goal.pos - here):GetNormalized(), 220)
    end

    if not hop then
        bail()
        return
    end

    local now = CurTime()
    goal.detour = hop
    goal.detourAt = now
    goal.issuedAt = now
    goal.bestDist = here:Distance(goal.pos)
    goal.bestAt = now
    goal.stallPos = here
    goal.stallAt = now
    data.moveIssuedAt = now

    npc:SetLastPosition(hop)
    npc:SetSchedule(SCHED_FORCED_GO_RUN)
    if CAI.MoveGoal then CAI.MoveGoal.Bump("detoured") end
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
        local dest = N.SafeGround(from + d * dist)
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