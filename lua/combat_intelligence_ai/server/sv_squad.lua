CAI.Squad = CAI.Squad or {}
local SQ = CAI.Squad

SQ.Squads = SQ.Squads or {}
local nextID = 1

local function planPending(data, reason)
    data.planPending = reason
    data.plan.expiresAt = CurTime()
end

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
        if CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "idle") or CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "patrol") then
            planPending(data, "squad_cover")
        end
    elseif event == "taking_fire" or event == "need_backup" then

        if IsValid(sender) and (CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "idle") or CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "patrol")) then
            CAI.Nav.MoveTo(data, sender:GetPos(), "run")
            planPending(data, "squad_regroup")
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
        local canAnswer = CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "idle")
            or CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "patrol")
            or CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "search")
            or CAI.PhaseIs(data, CAI.PHASE.WITHDRAW, "regroup")
        if canAnswer and not data.flank
           and CurTime() - (data.helpRespondAt or 0) > 8 then
            data.helpRespondAt = CurTime()
            data.reinforceTarget = payload.pos
            planPending(data, "squad_help")
        end
    elseif event == "suppression_active" and payload then
        if data.role == CAI.ROLE.SUPPRESSOR and CAI.PhaseIs(data, CAI.PHASE.ENGAGE, "suppress") then
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
            if CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "patrol") or CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT, "idle") then
                local side = math.random() < 0.5 and 1 or -1
                local dest = CAI.Nav.SafeOffset(npc:GetPos(), perp * side, 120)
                if dest then CAI.Nav.MoveTo(data, dest, "walk") end
            elseif CAI.PhaseIs(data, CAI.PHASE.ENGAGE) or CAI.PhaseIs(data, CAI.PHASE.ENGAGE, "suppress") then
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
            if d and (CAI.PhaseIs(d, CAI.PHASE.ENGAGE) or CAI.PhaseIs(d, CAI.PHASE.ENGAGE, "suppress") or CAI.PhaseIs(d, CAI.PHASE.MANEUVER, "bound")) then
                if CAI.PhaseIs(d, CAI.PHASE.MANEUVER, "bound") then return true end
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
            if d and CAI.PhaseIs(d, CAI.PHASE.ENGAGE, "suppress")
               and (d.suppressUntil or 0) > CurTime() then
                return true
            end
        end
    end
    return false
end

function SQ.FormationSlot(squad, index)
    return CAI.SquadFunc.FormationSlot(squad, index)
end

function SQ.UpdateFormation(squad, inCombat, indoors)
    CAI.SquadFunc.UpdateFormation(squad, inCombat, indoors)
end

timer.Create("CAI_SquadPlans", 0.5, 0, function()
    if not CAI.Enabled() then return end
    for _, squad in pairs(SQ.Squads) do
        CAI.SquadFunc.Plan(squad)
    end
end)

timer.Create("CAI_SquadPatrol", 0.5, 0, function()
    if not CAI.Enabled() then return end
    for _, squad in pairs(SQ.Squads) do
        if IsValid(squad.leader) and #squad.members > 1 then
            CAI.SquadFunc.PlanPatrol(squad)
        end
    end
end)

CAI.Prof.WrapFn(SQ, "Broadcast", "squad_broadcast")
CAI.Prof.WrapFn(SQ, "OnComm", "squad_oncomm")