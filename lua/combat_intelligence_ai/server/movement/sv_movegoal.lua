CAI.MoveGoal = CAI.MoveGoal or {}
local MG = CAI.MoveGoal
local BR = CAI.Brain
local N = CAI.Nav

MG.OrphanGrace = 1.0
MG.ReassertGap = 1.0
MG.DetourTime = 3.0

MG.Stats = MG.Stats or {
    issued = 0,
    arrived = 0,
    reasserted = 0,
    recovered = 0,
    detoured = 0,
    abandoned = 0,
    orphanDropped = 0,
    orphanReclaimed = 0,
}

function MG.ResetStats()
    for k in pairs(MG.Stats) do MG.Stats[k] = 0 end
end

function MG.Bump(key)
    MG.Stats[key] = (MG.Stats[key] or 0) + 1
end

function MG.Describe(data)
    local goal = data.moveGoal
    if not goal then return "none" end
    local npc = data.ent
    local remaining = IsValid(npc) and npc:GetPos():Distance(goal.pos) or -1
    return string.format(
        "owner=%s age=%.1f remaining=%.0f/%.0f recoveries=%d%s%s",
        tostring(goal.owner or "orphan"),
        CurTime() - (goal.startedAt or CurTime()),
        remaining,
        goal.startDist or 0,
        goal.recoveries or 0,
        goal.detour and " detouring" or "",
        goal.timedOut and " timedout" or ""
    )
end

local function tick(data)
    local npc = data.ent
    if not IsValid(npc) then return end

    local goal = data.moveGoal
    if not goal then return end

    if data.moveTarget == nil then
        data.moveGoal = nil
        data.moveIssuedAt = nil
        return
    end

    local now = CurTime()

    if not goal.owner and goal.orphanedAt then
        if data.phaseIntent and now - goal.orphanedAt >= MG.OrphanGrace then
            MG.Bump("orphanDropped")
            N.ClearGoal(data)
            return
        end
    end

    if goal.detour then
        local reached = npc:GetPos():DistToSqr(goal.detour) < 100 * 100
        if reached or now - (goal.detourAt or 0) > MG.DetourTime then
            goal.detour = nil
            goal.detourAt = nil
            goal.issuedAt = 0
        end
    end

    if N.Arrived(data, 70) then
        if not goal.arrivedLogged then
            goal.arrivedLogged = true
            MG.Bump("arrived")
        end
        return
    end

    if data.fireUntil and now < data.fireUntil then return end
    if BR.IsCommitted(data) then return end

    local sched = goal.mode == "walk" and SCHED_FORCED_GO or SCHED_FORCED_GO_RUN
    if npc.IsCurrentSchedule and npc:IsCurrentSchedule(sched) then return end
    if now - (goal.issuedAt or 0) < MG.ReassertGap then return end

    goal.issuedAt = now
    data.moveIssuedAt = now
    MG.Bump("reasserted")
    npc:SetLastPosition(N.EngineDest(goal))
    npc:SetSchedule(sched)
end

BR.RegisterHook("brain/react", "movegoal", tick)

concommand.Add("cai_movegoal_stats", function(ply)
    local out = {}
    for k, v in pairs(MG.Stats) do out[#out + 1] = k .. "=" .. v end
    table.sort(out)
    local line = CAI.PrintPrefix .. "move goals: " .. table.concat(out, "  ")
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end, nil, "Print move goal counters since map load")

concommand.Add("cai_movegoal_reset", function(ply)
    MG.ResetStats()
    local line = CAI.PrintPrefix .. "move goal counters reset"
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end, nil, "Zero the move goal counters")

concommand.Add("cai_movegoal_dump", function(ply)
    local lines = {}
    for npc, data in pairs(CAI.Manager.All()) do
        if IsValid(npc) then
            lines[#lines + 1] = string.format("  %s [%s/%s] %s",
                npc:GetClass(),
                CAI.PHASE_NAMES[data.phase] or "?",
                tostring(data.phaseIntent),
                MG.Describe(data))
        end
    end
    table.sort(lines)
    local text = CAI.PrintPrefix .. "active move goals (" .. #lines .. "):\n" .. table.concat(lines, "\n")
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
end, nil, "List every managed NPCs current move goal")