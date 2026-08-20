local SF = CAI.SquadFunc

local function awayFromLOS(d)
    local npc = d.ent
    if not IsValid(npc) then return true end
    local pos = npc:GetPos()
    for e in pairs(d.memory.enemies or {}) do
        if IsValid(e) and CAI.Util.CanSeePos(e, pos) then return false end
    end
    return true
end

function SF.Plan(squad)
    local now = CurTime()
    if now - squad.lastPlan < CAI.Config.Plan.Interval then return end
    squad.lastPlan = now
    local aggro = CAI.CVNum("cai_aggression")

    CAI.Battlefield.Prune(squad)
    CAI.Squad.AssignRoles(squad)
    if #squad.members == 0 then return end

    local enemies, moraleSum, ammoLow, injured, withLOS = 0, 0, 0, 0, 0
    for _ in pairs(squad.blackboard.enemies) do enemies = enemies + 1 end
    local lastContact = 0
    for _, m in ipairs(squad.members) do
        local d = CAI.Manager.Get(m)
        if d then
            moraleSum = moraleSum + d.morale
            if m:Health() < m:GetMaxHealth() * 0.4 then injured = injured + 1 end
            local wep = m.GetActiveWeapon and m:GetActiveWeapon()
            if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 then ammoLow = ammoLow + 1 end
            local enemy = m.GetEnemy and m:GetEnemy()
            if IsValid(enemy) and CAI.Util.CanSee(m, enemy) then withLOS = withLOS + 1 end
            local freshest = CAI.Memory.FreshestEnemy(d)
            if freshest then
                local t = freshest.t or 0
                if t > lastContact then lastContact = t end
            end
        end
    end
    local avgMorale = moraleSum / #squad.members
    local inCombat = enemies > 0

    if lastContact > 0 then
        squad.lastContactPos = squad.lastContactPos or {}
        squad.lastContactPos.t = lastContact
    end

    if enemies > 0 and enemies >= #squad.members * 2 then
        for _, m in ipairs(squad.members) do
            local d = CAI.Manager.Get(m)
            if d then CAI.Morale.Add(d, CAI.Config.Morale.Outnumbered, "outnumbered") end
        end
    end

    SF.UpdateFormation(squad, inCombat, false)

    local cfg = CAI.Config.Plan
    if inCombat and avgMorale < cfg.RetreatMoraleAvg then
        squad.plan = "retreat"
    elseif inCombat and injured >= #squad.members * 0.5 then
        squad.plan = "retreat"
    elseif inCombat and ammoLow >= #squad.members * 0.5 then
        squad.plan = "hold"
    elseif inCombat and #squad.members >= enemies * cfg.PushAdvantage and withLOS > 0 then
        squad.plan = "push"
    elseif inCombat and CAI.CVBool("cai_flanking")
           and #squad.members >= (aggro >= CAI.Config.Flank.AggressiveAt and 2 or cfg.FlankMinMembers) then
        squad.plan = "flank"
    elseif inCombat then
        squad.plan = "hold"
    else
        squad.plan = "regroup"
        local leader = squad.leader
        if #squad.members <= 1 then
            squad.plan = "hold"
        elseif IsValid(leader) then
            local far = 0
            for _, m in ipairs(squad.members) do
                if IsValid(m) and m:GetPos():DistToSqr(leader:GetPos()) > 350 * 350 then far = far + 1 end
            end
            if far == 0 then squad.plan = "hold" end
        end
    end

    if IsValid(squad.leader) then
        local ld = CAI.Manager.Get(squad.leader)
        if ld and CAI.PhaseIs(ld, CAI.PHASE.ENGAGE)
           and ld.lastDecision == "aggressive_push"
           and squad.plan ~= "retreat" then
            squad.plan = "push"
        end
    end

    local maxFlankers = math.max(1, math.floor(#squad.members * 0.5))
    local flankCount = 0

    for idx, m in ipairs(squad.members) do
        local d = CAI.Manager.Get(m)
        if d then
            d.squadIndex = idx
            d.squadPlan = squad.plan
            if d.role == CAI.ROLE.SUPPRESSOR and (squad.plan == "push" or squad.plan == "flank" or squad.plan == "hold") then
                if not d.suppressUntil or now > d.suppressUntil then
                    d.suppressStarted = now
                end
                if not d.suppressStarted or now - d.suppressStarted < 12 then
                    d.suppressUntil = math.max(d.suppressUntil or 0, now + cfg.Interval * 2)
                end
            elseif (squad.plan == "flank" or squad.plan == "push") and d.role == CAI.ROLE.FLANKER then
                if not d.lastFlankAt or now - d.lastFlankAt > 15 then
                    d.wantFlank = true
                    flankCount = flankCount + 1
                end
            elseif (squad.plan == "flank" or squad.plan == "push")
                   and d.role ~= CAI.ROLE.FLANKER and d.ent ~= squad.leader
                   and (not d.lastFlankAt or now - d.lastFlankAt > 15)
                   and flankCount < maxFlankers then
                local p = 0.15 + (d.personality.stats.aggression or 0) * 0.3
                if awayFromLOS(d) then p = p + 0.35 end
                if math.random() < p then
                    d.wantFlank = true
                    flankCount = flankCount + 1
                end
            end
            if d.role == CAI.ROLE.GRENADIER or d.role == CAI.ROLE.LEADER then
                pcall(function() d.ent:SetSaveValue("m_iNumGrenades", 3) end)
            end
        end
    end

    local maxSuppressors = math.max(1, math.floor(#squad.members * CAI.Config.SquadTactics.SuppressorRatio))
    local currentSuppressors = 0
    for _, m in ipairs(squad.members) do
        local d = CAI.Manager.Get(m)
        if d and d.role == CAI.ROLE.SUPPRESSOR then
            currentSuppressors = currentSuppressors + 1
        end
    end
    if currentSuppressors < maxSuppressors and inCombat then
        for _, m in ipairs(squad.members) do
            if currentSuppressors >= maxSuppressors then break end
            local d = CAI.Manager.Get(m)
            if d and d.role ~= CAI.ROLE.SUPPRESSOR
               and d.role ~= CAI.ROLE.FLANKER
               and d.role ~= CAI.ROLE.LEADER then
                d.role = CAI.ROLE.SUPPRESSOR
                d.suppressUntil = now + cfg.Interval * 2
                d.suppressStarted = now
                currentSuppressors = currentSuppressors + 1
            end
        end
    end

    if (squad.plan == "push" or squad.plan == "flank") and #squad.members >= 2 then
        if not squad._boundSwitchAt or now - squad._boundSwitchAt > CAI.Config.SquadTactics.BoundInterval then
            squad._boundSwitchAt = now
            local fireTeam = {}
            local maneuverTeam = {}
            for _, m in ipairs(squad.members) do
                local d = CAI.Manager.Get(m)
                if d then
                    local r = d.role
                    if r == CAI.ROLE.FLANKER or r == CAI.ROLE.BREACHER or r == CAI.ROLE.GRENADIER then
                        maneuverTeam[#maneuverTeam + 1] = m
                    else
                        fireTeam[#fireTeam + 1] = m
                    end
                end
            end
            local cornerpush = CAI.CVBool("cai_cornerpush")
            for _, m in ipairs(fireTeam) do
                local d = CAI.Manager.Get(m)
                if d then
                    if d.role == CAI.ROLE.SUPPRESSOR then
                        d.suppressUntil = now + CAI.Config.SquadTactics.BoundInterval
                        if cornerpush then d.cornerRole = "overwatch" end
                    end
                end
            end
            for _, m in ipairs(maneuverTeam) do
                local d = CAI.Manager.Get(m)
                if d then
                    if cornerpush then d.cornerRole = "lead" end
                    if not (d.boundTarget and not CAI.Nav.Arrived(d, 80)) then
                        local enemy, rec = CAI.Memory.FreshestEnemy(d)
                        if rec then
                            local toEnemy = (rec.pos - d.ent:GetPos())
                            toEnemy.z = 0 toEnemy:Normalize()
                            local right = Vector(-toEnemy.y, toEnemy.x, 0)
                            local side = math.random() < 0.5 and 1 or -1
                            local dist = d.ent:GetPos():Distance(rec.pos)
                            local moveDist = math.min(CAI.Config.SquadTactics.BoundMoveDistance, dist * 0.4)
                            local lateralDir = (toEnemy * 0.3 + right * side * 0.7):GetNormalized()
                            lateralDir.z = 0
                            lateralDir = CAI.SpatialMap.BiasedDir(d.squad, d.ent:GetPos(), lateralDir)
                            local dest = d.ent:GetPos() + lateralDir * moveDist
                            local safeDest = CAI.Nav.SafeGround(dest)
                            if not safeDest then
                                local reducedDir = (toEnemy * 0.6 + right * side * 0.4):GetNormalized()
                                reducedDir.z = 0
                                safeDest = CAI.Nav.SafeGround(d.ent:GetPos() + reducedDir * moveDist)
                            end
                            if not safeDest then
                                safeDest = CAI.Nav.SafeOffset(d.ent:GetPos(), toEnemy, moveDist)
                            end
                            if safeDest then
                                d.boundTarget = safeDest
                                d.wantBound = true
                            end
                        end
                    end
                end
            end
        end
    end

    if squad.plan == "hold" and #squad.members >= 2 then
        squad._staggerPhase = squad._staggerPhase or now
        for i, m in ipairs(squad.members) do
            local d = CAI.Manager.Get(m)
            if d then
                d.staggerOffset = (i - 1) * CAI.Config.SquadTactics.StaggerOffset
            end
        end
    end

    -- Set squad-level movement target
    if inCombat then
        local bestRec, bestT = nil, 0
        for _, m in ipairs(squad.members) do
            local d = CAI.Manager.Get(m)
            if d then
                local _, rec = CAI.Memory.FreshestEnemy(d)
                if rec and (rec.t or 0) > bestT then
                    bestRec, bestT = rec, rec.t or 0
                end
            end
        end
        if bestRec then
            squad.objectivePos = bestRec.pos
        end
    end
end

timer.Create("CAI_CoverCacheRefresh", 2.0, 0, function()
    if not CAI.Enabled() then return end
    local cv = CAI.Cover
    local cfg = CAI.Config.Cover
    local seenSquads = {}
    for npc, data in pairs(CAI.Manager.All()) do
        local squad = data.squad
        if squad and not seenSquads[squad] then
            seenSquads[squad] = true
            local sm = squad.blackboard.spatialMap
            local budget = 2
            for _, m in ipairs(squad.members) do
                if budget <= 0 then break end
                local d = CAI.Manager.Get(m)
                if d and IsValid(m) then
                    local closest = cv.QueryNearby(d, m:GetPos(), cfg.SearchRadius)
                    if not closest then
                        local enemy, rec = CAI.Memory.FreshestEnemy(d)
                        local pos = cv.FindBestFallback(d, enemy, rec and rec.pos)
                        if pos then
                            local key = math.floor(pos.x / cfg.CellSize) .. ":" .. math.floor(pos.y / cfg.CellSize)
                            if not sm.cover[key] then sm.cover[key] = {} end
                            if #sm.cover[key] < cfg.MaxPerCell then
                                table.insert(sm.cover[key], { pos = pos, weight = 0, validatedAt = CurTime() })
                            end
                            budget = budget - 1
                        end
                    end
                end
            end
        end
    end
end)
