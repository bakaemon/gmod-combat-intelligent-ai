local BR = CAI.Brain

BR.RegisterHook("brain/exec", "pre_contact", function(data)
    local intent = data.phaseIntent
    if intent == "patrol" then
        local npc = data.ent
        if not CAI.CVBool("cai_patrol") then
            if math.random() < 0.03 then CAI.Voice.Speak(data, "idle") end
            return
        end
        local squad = data.squad
        if squad and CAI.CVBool("cai_formations") and squad.patrolPos and #squad.members > 1 then
            if npc == squad.leader then
                if data.moveTarget and not CAI.Nav.Arrived(data, 80) then return end
                CAI.Nav.MoveTo(data, squad.patrolPos, "walk")
            else
                local idx = CAI.SquadFunc.SquadIndex(squad, npc)
                local slot = idx and CAI.SquadFunc.FormationSlot(squad, idx)
                if slot then
                    if data.moveTarget and not CAI.Nav.Arrived(data, 80) then return end
                    local safe = CAI.Nav.SafeGround(slot)
                    if safe and IsValid(navmesh.GetNearestNavArea(safe)) then
                        CAI.Nav.MoveTo(data, safe, "walk")
                    else
                        local dir = squad.leader:GetPos() - npc:GetPos()
                        dir.z = 0
                        if dir:LengthSqr() > 1 then
                            local toward = CAI.Nav.SafeGround(npc:GetPos() + dir:GetNormalized() * 100)
                            if toward then
                                CAI.Nav.MoveTo(data, toward, "walk")
                            end
                        end
                    end
                end
            end
            CAI.Nav.CheckStuck(data)
            local heatCfg = CAI.Config.Heatmap
            local src = npc:GetPos()
            CAI.SpatialMap.RecordTemp(squad, src, -heatCfg.AuraCoolRate, heatCfg.AuraRadiateRadius)
            local fwd = npc:GetForward(); fwd.z = 0; fwd:Normalize()
            local right = npc:GetRight(); right.z = 0; right:Normalize()
            local halfFov = math.rad(heatCfg.ConeFOV * 0.5)
            local step = heatCfg.ConeRays > 1 and (heatCfg.ConeFOV * math.pi / 180) / (heatCfg.ConeRays - 1) or 0
            for i = 0, heatCfg.ConeRays - 1 do
                local angle = -halfFov + i * step
                local dir = fwd * math.cos(angle) + right * math.sin(angle)
                local endPos = src + dir * heatCfg.ConeRange
                CAI.SpatialMap.RecordTemp(squad, endPos, -heatCfg.ConeCoolRate)
            end
            if math.random() < 0.1 then CAI.Voice.Speak(data, "idle") end
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
        if squad then
            local heatCfg = CAI.Config.Heatmap
            local src = npc:GetPos()
            CAI.SpatialMap.RecordTemp(squad, src, -heatCfg.AuraCoolRate, heatCfg.AuraRadiateRadius)
            local fwd = npc:GetForward(); fwd.z = 0; fwd:Normalize()
            local right = npc:GetRight(); right.z = 0; right:Normalize()
            local halfFov = math.rad(heatCfg.ConeFOV * 0.5)
            local step = heatCfg.ConeRays > 1 and (heatCfg.ConeFOV * math.pi / 180) / (heatCfg.ConeRays - 1) or 0
            for i = 0, heatCfg.ConeRays - 1 do
                local angle = -halfFov + i * step
                local dir = fwd * math.cos(angle) + right * math.sin(angle)
                local endPos = src + dir * heatCfg.ConeRange
                CAI.SpatialMap.RecordTemp(squad, endPos, -heatCfg.ConeCoolRate)
            end
        end
        if math.random() < 0.15 then CAI.Voice.Speak(data, "idle") end
    elseif intent == "search" then
        if not data.search then
            local enemy, rec = CAI.Memory.FreshestEnemy(data)
            if not rec or not CAI.Search.Begin(data, enemy, rec.pos) then
                data.planPending = "nothing_to_search"
                return
            end
        end
        if not CAI.Search.Update(data) then
            data.planPending = "search_over"
        end
    elseif intent == "investigate" then
        local npc = data.ent
        local visEnemy, visRec = CAI.Memory.FreshestEnemy(data)
        if IsValid(visEnemy) and CAI.Util.CanSee(npc, visEnemy) then
            data.planPending = "spotted_during_investigate"
            return
        end
        if not data.investigatePos or CurTime() > (data.investigateUntil or 0) then
            if data.investigatePos then
                data.lastInvestigate = { pos = data.investigatePos, t = CurTime() }
            end
            data.investigatePos = nil
            data.planPending = "investigation_over"
            return
        end
        if data.moveTarget and CAI.Nav.Arrived(data, 100) then
            if not data.investFaced then
                data.investFaced = true
                data.moveTarget = nil
                npc:SetSchedule(SCHED_COMBAT_FACE)
                data.investigateUntil = math.min(data.investigateUntil, CurTime() + 3)
            end
        else
            data.investFaced = nil
            CAI.Nav.MoveTo(data, data.investigatePos, "walk")
        end
    end
end)
