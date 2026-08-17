local BR = CAI.Brain

local function retreatDirection(data, npc)
    local push = Vector()
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and CAI.Util.Alive(ent) and rec.pos then
            local v = npc:GetPos() - rec.pos
            v.z = 0
            local len = v:Length()
            if len > 1 then push = push + v * (1 / len) end
        end
    end
    push.z = 0
    local pull = Vector()
    local center = data.squad and CAI.SquadFunc.SquadCenterOfMass(data.squad, npc, 2000)
    if center then
        pull = center - npc:GetPos()
        pull.z = 0
    end
    local combined
    if push:LengthSqr() > 1 then
        push:Normalize()
        if pull:LengthSqr() > 1 then
            pull:Normalize()
            combined = push * 0.7 + pull * 0.3
        else
            combined = push
        end
    elseif pull:LengthSqr() > 1 then
        combined = pull
    else
        return nil
    end
    combined.z = 0
    return combined:GetNormalized()
end

local function nearestEnemy(data, npc)
    local bestPos, bestD = nil, math.huge
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and rec.pos then
            local d = npc:GetPos():Distance(rec.pos)
            if d < bestD then bestPos, bestD = rec.pos, d end
        end
    end
    return bestPos, bestD
end

local function exposedToEnemies(data, p)
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and rec.pos and CAI.Util.CanSeePos(ent, p) then return true end
    end
    return false
end

local function safeRetreat(data, p, nearPos, curD)
    if not p then return false end
    if not IsValid(navmesh.GetNearestNavArea(p)) then return false end
    if CAI.CVBool("cai_danger_avoid") and CAI.Memory.AvoidPos(data, p,
            CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius) then
        return false
    end
    if nearPos and curD and p:Distance(nearPos) < curD - 50 then return false end
    return true
end

BR.RegisterHook("brain/exec", "withdraw", function(data)
    local npc = data.ent
    local nearPos, curD = nearestEnemy(data, npc)

    if data.phaseIntent == "flee" or data.phaseIntent == "tactical" then
        if data.reflex then data.reflex.bias = nil end
        if data.lastDecision == "escape_encirclement" then
            local ecfg = CAI.Config.Escape
            local now = CurTime()
            local count, nearest, nearDist, centroid = BR.MeleeThreatScan(data)

            if nearDist > ecfg.ClearDist and count < ecfg.SurroundCount
               and now - (data.lastMeleeHurtAt or 0) > ecfg.MeleeHitGrace then
                data.saidRetreat = false
                local wep = npc:GetActiveWeapon()
                if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 then
                    data.planPending = "reloading_cover"
                else
                    data.planPending = "engage_target"
                end
                return
            end

            local ref = centroid or (IsValid(nearest) and nearest:GetPos()) or data.escapeCentroid
            if IsValid(nearest) and CurTime() - (data.shoveAt or 0) > 1.5
               and npc.CapabilitiesGet
               and bit.band(npc:CapabilitiesGet(), CAP_INNATE_MELEE_ATTACK1) ~= 0
               and npc:GetPos():DistToSqr(nearest:GetPos()) < ecfg.ShoveRange * ecfg.ShoveRange then
                data.shoveAt = now
                if npc.SetEnemy then npc:SetEnemy(nearest) end
                npc:SetSchedule(SCHED_MELEE_ATTACK1)
                return
            end

            if now - (data.escapeMoveAt or 0) > 1.0 then
                data.escapeMoveAt = now
                local away = ref and (npc:GetPos() - ref) or retreatDirection(data, npc)
                away = away or Vector(1, 0, 0)
                away.z = 0
                if away:LengthSqr() < 1 then away = retreatDirection(data, npc) or Vector(1, 0, 0) end
                away:Normalize()
                local yaw = away:Angle().y
                local dest
                for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                    local dir = Angle(0, yaw + off, 0):Forward()
                    local p = CAI.Nav.SafeOffset(npc:GetPos(), dir, ecfg.Step)
                    if p and safeRetreat(data, p, nearPos, curD) then dest = p break end
                end
                if dest and IsValid(navmesh.GetNearestNavArea(dest)) and not BR.IsCommitted(data) then
                    CAI.Nav.MoveTo(data, dest, "run", "escape")
                end
                if not data.saidRetreat then
                    data.saidRetreat = true
                    CAI.Voice.Speak(data, "retreat")
                end
            end
            return
        end

        if data.scatterFrom and data.scatterUntil and CurTime() < data.scatterUntil then
            local away = npc:GetPos() - data.scatterFrom
            away.z = 0
            if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
            away:Normalize()
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 280)
            if dest and IsValid(navmesh.GetNearestNavArea(dest)) and not BR.IsCommitted(data) then
                CAI.Nav.MoveTo(data, dest, "run", "scatter")
            end
            return
        end

        local unarmed = data.lastDecision == "unarmed_flee"
        if unarmed and CurTime() - (data.hideAt or 0) > 2 then
            data.hideAt = CurTime()
            local ent, rec = CAI.Memory.FreshestEnemy(data)
            local threat = rec and rec.pos
            local dest
            if threat then
                local spot = CAI.Cover.FindBest(data, ent, threat)
                if spot and safeRetreat(data, spot, nearPos, curD) and not exposedToEnemies(data, spot) then
                    dest = spot
                end
                if not dest then
                    local away = retreatDirection(data, npc) or (npc:GetPos() - threat)
                    away.z = 0
                    if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
                    away:Normalize()
                    local yaw = away:Angle().y
                    for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                        local dir = Angle(0, yaw + off, 0):Forward()
                        local p = CAI.Nav.SafeOffset(npc:GetPos(), dir, 700)
                        if p and safeRetreat(data, p, nearPos, curD) then dest = p break end
                    end
                end
            end
            if not dest then
                local away = retreatDirection(data, npc) or Vector(1, 0, 0)
                away.z = 0
                if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
                away:Normalize()
                dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 700)
            end
            if dest and IsValid(navmesh.GetNearestNavArea(dest)) and not BR.IsCommitted(data) then
                CAI.Nav.MoveTo(data, dest, "run", "hide")
            end
            if not data.saidRetreat then
                data.saidRetreat = true
                CAI.Voice.Speak(data, "panic")
            end
            return
        end

        local cacheBad = data.retreatDest and CAI.CVBool("cai_danger_avoid")
            and CAI.Memory.AvoidPos(data, data.retreatDest,
                CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius)
        if not data.retreatDest or not CAI.Nav.HasGoal(data) or CAI.Nav.Arrived(data, 100)
           or CurTime() - (data.retreatAt or 0) > 5 or cacheBad then
            data.retreatAt = CurTime()
            local ent, rec = CAI.Memory.FreshestEnemy(data)
            if rec then
                local threat = rec.pos
                local spot = CAI.Cover.FindBest(data, ent, threat)
                local unseen, fallback
                if spot and safeRetreat(data, spot, nearPos, curD) then
                    if not exposedToEnemies(data, spot) then unseen = spot
                    else fallback = fallback or spot end
                end
                if not unseen then
                    local away = retreatDirection(data, npc) or (npc:GetPos() - threat)
                    away.z = 0
                    if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
                    away:Normalize()
                    local yaw = away:Angle().y
                    local heatCfg = CAI.Config.Heatmap
                    local bestUnseenScore, bestFallbackScore = -math.huge, -math.huge
                    for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                        local dir = Angle(0, yaw + off, 0):Forward()
                        local p = CAI.Nav.RandomPointNear(npc:GetPos() + dir * 800, 400)
                        if not p then p = CAI.Nav.SafeOffset(npc:GetPos(), dir, 600) end
                        if p and safeRetreat(data, p, nearPos, curD) then
                            local temp = CAI.SpatialMap.QueryTemp(data.squad, p)
                            local coldness = heatCfg.Baseline - temp
                            if not exposedToEnemies(data, p) then
                                if coldness >= bestUnseenScore then
                                    bestUnseenScore = coldness
                                    unseen = p
                                end
                            elseif coldness >= bestFallbackScore then
                                bestFallbackScore = coldness
                                fallback = p
                            end
                        end
                    end
                end
                local dest = unseen or fallback
                if dest then
                    data.retreatDest = dest
                    data.retreatMoveAt = CurTime()
                    if not BR.IsCommitted(data) then
                        CAI.Nav.MoveTo(data, dest, "run", "retreat")
                    end
                else
                    data.retreatDest = nil
                end
            end
            if not data.saidRetreat then
                data.saidRetreat = true
                CAI.Voice.Speak(data, "retreat")
                if data.squad then CAI.Squad.Broadcast(data.squad, "retreating", npc) end
            end
        end
        if data.retreatDest and CurTime() - (data.retreatMoveAt or 0) > 1 then
            data.retreatMoveAt = CurTime()
            if not BR.IsCommitted(data) then
                CAI.Nav.MoveTo(data, data.retreatDest, "run", "retreat")
            end
        elseif nearPos then
            local away = (npc:GetPos() - nearPos):GetNormalized() * 600
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 600)
            if dest and IsValid(navmesh.GetNearestNavArea(dest)) then
                data.retreatDest = dest
                data.retreatMoveAt = CurTime()
                if not BR.IsCommitted(data) then
                    CAI.Nav.MoveTo(data, dest, "run", "retreat")
                end
            end
        end
        return
    end

    if data.phaseIntent == "regroup" then
        local squad = data.squad
        if not squad or not IsValid(squad.leader) or squad.leader == npc then
            data.planPending = "no_squad_to_regroup"
            return
        end

        local visEnemy, visRec = CAI.Memory.FreshestEnemy(data)
        if IsValid(visEnemy) and CAI.Util.CanSee(npc, visEnemy) then
            data.reinforceTarget = nil
            data.planPending = "spotted_during_regroup"
            return
        end

        if data.reinforceTarget then
            if npc:GetPos():DistToSqr(data.reinforceTarget) < 90 * 90 then
                data.reinforceTarget = nil
                data.planPending = "reinforced"
                return
            end
            CAI.Nav.MoveTo(data, data.reinforceTarget, "run", "regroup")
            return
        end

        local idx = 0
        for _, m in ipairs(squad.members) do
            if m ~= squad.leader then
                idx = idx + 1
                if m == data.ent then break end
            end
        end
        local slot = CAI.Squad.FormationSlot(squad, idx)
        if slot and (CurTime() - (data.regroupAt or 0) > 1.5 or not CAI.Nav.HasGoal(data)) then
            data.regroupAt = CurTime()
            CAI.Nav.MoveTo(data, slot, "run", "regroup")
        end
        if CAI.Nav.HasGoal(data) and CAI.Nav.Arrived(data, 90) then
            data.planPending = "in_formation"
        end
        return
    end
end)