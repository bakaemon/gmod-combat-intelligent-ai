CAI.Squad = CAI.Squad or {}
local SQ = CAI.Squad

SQ.Squads = SQ.Squads or {}
local nextID = 1

local GROUP_RADIUS = 900

function SQ.Create(faction)
    local squad = {
        id = nextID, faction = faction,
        members = {}, leader = nil,
        blackboard = CAI.Battlefield.New(),
        formation = "WEDGE",
        lastPlan = 0, plan = "hold",
        lastVoiceAt = 0,
    }
    nextID = nextID + 1
    SQ.Squads[squad.id] = squad
    return squad
end

function SQ.AddMember(squad, npc)
    local data = CAI.Manager.Get(npc)
    if not data then return end
    if data.squad == squad then return end
    if data.squad then SQ.RemoveMember(data.squad, npc) end

    if npc.AddEntityRelationship then
        for _, m in ipairs(squad.members) do
            if IsValid(m) then
                npc:AddEntityRelationship(m, D_LI, 99)
                if m.AddEntityRelationship then
                    m:AddEntityRelationship(npc, D_LI, 99)
                end
            end
        end
    end

    squad.members[#squad.members + 1] = npc
    data.squad = squad
    SQ.AssignRoles(squad)
end

function SQ.RemoveMember(squad, npc)
    for i, m in ipairs(squad.members) do
        if m == npc then table.remove(squad.members, i) break end
    end
    local data = CAI.Manager.Get(npc)
    if data then data.squad, data.role = nil, nil end
    if squad.leader == npc then
        squad.leader = nil
        SQ.AssignRoles(squad)
    end
    if #squad.members == 0 then SQ.Squads[squad.id] = nil end
end

function SQ.Place(npc)
    local data = CAI.Manager.Get(npc)
    if not data then return end
    local classInfo = CAI.Config.NPCClasses[npc:GetClass()]
    local faction = classInfo and classInfo.faction or "custom"

    local best, bestD = nil, GROUP_RADIUS * GROUP_RADIUS
    for _, squad in pairs(SQ.Squads) do
        if squad.faction == faction and IsValid(squad.leader or squad.members[1]) then
            local anchor = (squad.leader or squad.members[1]):GetPos()
            local d = anchor:DistToSqr(npc:GetPos())
            if d < bestD and #squad.members < 8 then best, bestD = squad, d end
        end
    end
    if not best then best = SQ.Create(faction) end
    SQ.AddMember(best, npc)
end

function SQ.AssignRoles(squad)

    for i = #squad.members, 1, -1 do
        if not CAI.Util.Alive(squad.members[i]) then table.remove(squad.members, i) end
    end
    if #squad.members == 0 then return end

    local bestScore, leader = -math.huge, nil
    for _, m in ipairs(squad.members) do
        local d = CAI.Manager.Get(m)
        if d then
            local s = m:Health() / math.max(m:GetMaxHealth(), 1)
                    + (d.personality.stats.courage or 0)
            if s > bestScore then bestScore, leader = s, m end
        end
    end
    squad.leader = leader
    local ld = CAI.Manager.Get(leader)
    if ld then
        if ld.role ~= CAI.ROLE.LEADER then ld.suppressUntil = nil end
        ld.role = CAI.ROLE.LEADER
    end

    local pool = { CAI.ROLE.SUPPRESSOR, CAI.ROLE.FLANKER, CAI.ROLE.SUPPORT,
                   CAI.ROLE.BREACHER, CAI.ROLE.REAR, CAI.ROLE.GRENADIER }
    local idx = 1
    for _, m in ipairs(squad.members) do
        if m ~= leader then
            local d = CAI.Manager.Get(m)
            if d then
                local st = d.personality.stats
                local prevRole = d.role
                if (st.aggression or 0) > 0.2 and not squad._hasFlanker then
                    d.role, squad._hasFlanker = CAI.ROLE.FLANKER, true
                elseif (st.patience or 0) > 0.2 and not squad._hasSupp then
                    d.role, squad._hasSupp = CAI.ROLE.SUPPRESSOR, true
                else
                    d.role = pool[math.min(idx, #pool)]
                    idx = idx + 1
                end
                if d.role ~= prevRole then d.suppressUntil = nil end
            end
        end
    end
    squad._hasFlanker, squad._hasSupp = nil, nil
end

function SQ.Broadcast(squad, event, sender, payload)
    if not squad or not CAI.CVBool("cai_comms") then return end
    for _, m in ipairs(squad.members) do
        if IsValid(m) and m ~= sender then
            local d = CAI.Manager.Get(m)
            if d then SQ.OnComm(d, event, sender, payload) end
        end
    end
end

function SQ.OnComm(data, event, sender, payload)
    if event == "enemy_spotted" and payload then
        CAI.Memory.HearEnemy(data, payload.enemy, payload.pos)
        if data.state == CAI.STATE.IDLE or data.state == CAI.STATE.PATROL then
            CAI.Brain.SetState(data, CAI.STATE.COVER)
        end
    elseif event == "taking_fire" or event == "need_backup" then

        if IsValid(sender) and (data.state == CAI.STATE.IDLE or data.state == CAI.STATE.PATROL) then
            CAI.Nav.MoveTo(data, sender:GetPos(), "run")
            CAI.Brain.SetState(data, CAI.STATE.REGROUP)
        end
    elseif event == "grenade" or event == "rocket_spotted" then
        data.forceRecover = true
    elseif event == "reloading" then

        if data.role == CAI.ROLE.SUPPRESSOR then
            data.suppressUntil = math.max(data.suppressUntil or 0, CurTime() + 2)
        elseif data.role == CAI.ROLE.SUPPORT or data.role == CAI.ROLE.LEADER then
            data.suppressUntil = math.max(data.suppressUntil or 0, CurTime() + 1)
        end
    elseif event == "enemy_lost" and payload then
        data.investigatePos = payload.pos
    elseif event == "retreating" then
        CAI.Morale.Add(data, -4, "ally_retreating")
    elseif event == "need_help" and payload then
        if data.state ~= CAI.STATE.ENGAGE and data.state ~= CAI.STATE.RETREAT then
            data.reinforceTarget = payload.pos
            -- A live flanker is mid-maneuver; do not yank it to REGROUP or the
            -- flank collapses. Record the request but leave its state alone.
            if not data.flank then
                CAI.Brain.SetState(data, CAI.STATE.REGROUP, "help_request")
            end
        end
    elseif event == "suppression_active" and payload then
        if data.role == CAI.ROLE.SUPPRESSOR and data.state == CAI.STATE.SUPPRESS then
            data.suppressUntil = math.max(data.suppressUntil or 0, CurTime() + 2)
        end
    elseif event == "flanking" and payload then
        if data.role == CAI.ROLE.SUPPRESSOR or data.role == CAI.ROLE.SUPPORT then
            data.suppressUntil = math.max(data.suppressUntil or 0, CurTime() + 3)
        end
    elseif event == "line_of_fire_blocked" and payload then
        if payload.blocker == data.ent and sender ~= data.ent then
            local npc = data.ent
            local dir = payload.direction
            local perp = Vector(-dir.y, dir.x, 0)
            if data.state == CAI.STATE.PATROL or data.state == CAI.STATE.IDLE then
                local side = math.random() < 0.5 and 1 or -1
                local dest = CAI.Nav.SafeOffset(npc:GetPos(), perp * side, 120)
                if dest then CAI.Nav.MoveTo(data, dest, "walk") end
            elseif data.state == CAI.STATE.ENGAGE or data.state == CAI.STATE.SUPPRESS then
                local enemy = payload.enemy
                if IsValid(enemy) and CAI.Util.CanSee(npc, enemy) then
                    local myDir = (enemy:GetPos() - npc:GetPos()):GetNormalized()
                    local dot = myDir:Dot(dir)
                    if dot > 0.8 then
                        data.fireAngleOffset = (data.fireAngleOffset or 0) + 15
                    end
                end
            end
        end
    end
end

function SQ.AnyoneEngaging(squad, self)
    if not squad then return false end
    for _, m in ipairs(squad.members) do
        if IsValid(m) and m ~= self then
            local d = CAI.Manager.Get(m)
            if d and (d.state == CAI.STATE.ENGAGE or d.state == CAI.STATE.SUPPRESS or d.state == CAI.STATE.BOUNDED) then
                if d.state == CAI.STATE.BOUNDED then return true end
                if IsValid(m:GetEnemy()) and CAI.Util.Sees(m, m:GetEnemy()) then return true end
            end
        end
    end
    return false
end

function SQ.Suppressing(squad, self)
    if not squad then return false end
    for _, m in ipairs(squad.members) do
        if IsValid(m) and m ~= self then
            local d = CAI.Manager.Get(m)
            if d and d.state == CAI.STATE.SUPPRESS
               and (d.suppressUntil or 0) > CurTime() then
                return true
            end
        end
    end
    return false
end

function SQ.FormationSlot(squad, index)
    local leader = squad.leader
    if not IsValid(leader) then return nil end
    local offsets = CAI.Config.Formations[squad.formation] or CAI.Config.Formations.WEDGE
    local o = offsets[math.min(index, #offsets)]
    if not o then return nil end
    local fwd = leader:GetForward(); fwd.z = 0; fwd:Normalize()
    local right = leader:GetRight(); right.z = 0; right:Normalize()
    return leader:GetPos() + fwd * o[1] + right * o[2]
end

function SQ.UpdateFormation(squad, inCombat, indoors)
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

function SQ.Plan(squad)
    local now = CurTime()
    if now - squad.lastPlan < CAI.Config.Plan.Interval then return end
    squad.lastPlan = now
    local aggro = CAI.CVNum("cai_aggression")

    CAI.Battlefield.Prune(squad)
    SQ.AssignRoles(squad)
    if #squad.members == 0 then return end

    local enemies, moraleSum, ammoLow, injured, withLOS = 0, 0, 0, 0, 0
    for _ in pairs(squad.blackboard.enemies) do enemies = enemies + 1 end
    for _, m in ipairs(squad.members) do
        local d = CAI.Manager.Get(m)
        if d then
            moraleSum = moraleSum + d.morale
            if m:Health() < m:GetMaxHealth() * 0.4 then injured = injured + 1 end
            local wep = m.GetActiveWeapon and m:GetActiveWeapon()
            if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 then ammoLow = ammoLow + 1 end
            local enemy = m.GetEnemy and m:GetEnemy()
            if IsValid(enemy) and CAI.Util.CanSee(m, enemy) then withLOS = withLOS + 1 end
        end
    end
    local avgMorale = moraleSum / #squad.members
    local inCombat = enemies > 0

    if enemies > 0 and enemies >= #squad.members * 2 then
        for _, m in ipairs(squad.members) do
            local d = CAI.Manager.Get(m)
            if d then CAI.Morale.Add(d, CAI.Config.Morale.Outnumbered, "outnumbered") end
        end
    end

    SQ.UpdateFormation(squad, inCombat, false)

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
        if ld and ld.state == CAI.STATE.ENGAGE
           and ld.lastDecision == "aggressive_push"
           and squad.plan ~= "retreat" then
            squad.plan = "push"
        end
    end

    local maxFlankers = math.max(1, math.floor(#squad.members * 0.5))
    local flankCount = 0
    local function SQ_AwayFromLOS(d)
        local npc = d.ent
        if not IsValid(npc) then return true end
        local pos = npc:GetPos()
        for e in pairs(d.memory.enemies or {}) do
            if IsValid(e) and CAI.Util.CanSeePos(e, pos) then return false end
        end
        return true
    end

    for _, m in ipairs(squad.members) do
        local d = CAI.Manager.Get(m)
        if d then
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
                if SQ_AwayFromLOS(d) then p = p + 0.35 end
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
                    d.suppressUntil = now + CAI.Config.SquadTactics.BoundInterval
                    if cornerpush then d.cornerRole = "overwatch" end
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
end

timer.Create("CAI_SquadPlans", 0.5, 0, function()
    if not CAI.Enabled() then return end
    for _, squad in pairs(SQ.Squads) do
        SQ.Plan(squad)
    end
end)

CAI.Prof.WrapFn(SQ, "Plan", "squad_plan")
CAI.Prof.WrapFn(SQ, "Broadcast", "squad_broadcast")
CAI.Prof.WrapFn(SQ, "OnComm", "squad_oncomm")
