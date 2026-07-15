local BR = CAI.Brain

-- PATROL: wander the map, avoiding recent ground, allies' posts, and death
-- zones. Uses squad patrol points when available, else random reachable spots.
BR.Exec[1] = function(data)
    local npc = data.ent
    if not CAI.CVBool("cai_patrol") then
        if math.random() < 0.03 then CAI.Voice.Speak(data, "idle") end
        return
    end
    if data.moveTarget then
        if CAI.Nav.Arrived(data, 80) then
        elseif npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_IDLE_STAND) then
            data.moveTarget = nil
        else
            return
        end
    end
    local pat = data.personality.stats.patience or 0
    local dwellEnd = data.patrolAt or 0
    if CurTime() < dwellEnd then return end
    data.patrolAt = CurTime() + math.Rand(1, 2) * (1 + pat * 0.8)

    local RADIUS, DEDUP, DECLUMP, TTL = 1500, 400, 500, 30
    local origin = npc:GetPos()
    local squad = data.squad
    if squad then CAI.Battlefield.PrunePatrolVisited(squad, TTL) end

    local reach = CAI.Nav.ReachableAreas(origin)
    local function reachable(p)
        if not p then return false end
        if reach == nil then return true end
        local a = navmesh.GetNearestNavArea(p)
        return IsValid(a) and reach[a] == true
    end

    data.patrolHistory = data.patrolHistory or {}
    local hist = data.patrolHistory

    local function accept(p, key)
        if not p then return false end
        if not reachable(p) then return false end
        if p:DistToSqr(origin) < 300 * 300 then return false end
        if CAI.Memory.NearAllyDeath(data, p, CAI.Config.SelfPreserve.DangerAvoid.AllyDeathRadius) then return false end
        for _, h in ipairs(hist) do
            if p:DistToSqr(h) < DEDUP * DEDUP then return false end
        end
        if squad then
            for _, m in ipairs(squad.members) do
                if IsValid(m) and m ~= npc then
                    local md = CAI.Manager.Get(m)
                    if md and md.patrolTarget and p:DistToSqr(md.patrolTarget) < DECLUMP * DECLUMP then
                        return false
                    end
                end
            end
            if key and CAI.Battlefield.PatrolVisitedAt(squad, key) > 0 then return false end
        end
        return true
    end

    local chosen, chosenKey

    if squad and math.random() > 0.7 then
        local best, bestKey, bestD = nil, nil, math.huge
        for _, poi in ipairs(CAI.Battlefield.GetPatrolPoints(squad, origin, RADIUS)) do
            if accept(poi.pos, poi.key) then
                local d = origin:DistToSqr(poi.pos)
                if d < bestD then best, bestKey, bestD = poi.pos, poi.key, d end
            end
        end
        chosen, chosenKey = best, bestKey
    end

    if not chosen then
        for _ = 1, 6 do
            local cand = CAI.Nav.RandomPointNear(origin, RADIUS, true)
            local key = cand and CAI.Battlefield.PosKey(cand)
            if accept(cand, key) then
                chosen, chosenKey = cand, key
                break
            end
        end
    end

    if not chosen then
        for _, yaw in ipairs({ 0, 45, -45, 90, -90, 135, -135, 180 }) do
            local dir = Angle(0, yaw, 0):Forward()
            local cand = CAI.Nav.SafeGround(origin + dir * 400)
            if cand and accept(cand, CAI.Battlefield.PosKey(cand)) then
                chosen, chosenKey = cand, CAI.Battlefield.PosKey(cand)
                break
            end
        end
    end

    if chosen then
        data.patrolTarget = chosen
        data.lastPatrolPoint = chosen
        hist[#hist + 1] = chosen
        while #hist > 5 do table.remove(hist, 1) end
        if squad then CAI.Battlefield.MarkPatrolVisited(squad, chosenKey) end
        CAI.Nav.MoveTo(data, chosen, "walk")
    end
    CAI.Nav.CheckStuck(data)
    if math.random() < 0.15 then CAI.Voice.Speak(data, "idle") end
end

