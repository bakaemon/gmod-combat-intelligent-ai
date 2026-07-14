timer.Create("CAI_DebugNet", 0.35, 0, function()
    if not CAI.Enabled() or not CAI.CVBool("cai_debug") then return end

    local admins = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply:IsAdmin() then admins[#admins + 1] = ply end
    end
    if #admins == 0 then return end

    for _, ply in ipairs(admins) do
        local eye = ply:GetPos()
        local near = {}
        for npc, data in pairs(CAI.Manager.All()) do
            if IsValid(npc) then
                local d = eye:DistToSqr(npc:GetPos())
                if d < 2500 * 2500 then
                    near[#near + 1] = { npc = npc, data = data, d = d }
                end
            end
        end
        table.sort(near, function(a, b) return a.d < b.d end)

        local rows = {}
        for i = 1, math.min(#near, 24) do
            local npc, data = near[i].npc, near[i].data
            do
                local enemy = npc.GetEnemy and npc:GetEnemy()
                rows[#rows + 1] = {
                    idx = npc:EntIndex(),
                    state = data.state,
                    role = data.role or 0,
                    morale = math.Round(data.morale),
                    supp = math.Round(data.suppression),
                    squad = data.squad and data.squad.id or 0,
                    plan = data.squadPlan or "",
                    why = data.lastDecision or "",
                    cover = data.cover and data.cover.pos or nil,
                    move = data.moveTarget,
                    target = IsValid(enemy) and enemy:EntIndex() or 0,
                    memE = table.Count(data.memory.enemies),
                    memD = #data.memory.dangers,
                    lod = data.lodInterval or 0,
                    traits = data.personality and table.concat(data.personality.traits, "/") or "",
                }
            end
        end

        net.Start(CAI.Net.Debug)
            net.WriteUInt(#rows, 6)
            for _, r in ipairs(rows) do
                net.WriteUInt(r.idx, 14)
                net.WriteUInt(r.state, 5)
                net.WriteUInt(r.role, 4)
                net.WriteUInt(r.morale, 7)
                net.WriteUInt(r.supp, 7)
                net.WriteUInt(r.squad % 256, 8)
                net.WriteString(r.plan)
                net.WriteString(r.why)
                net.WriteBool(r.cover ~= nil)
                if r.cover then net.WriteVector(r.cover) end
                net.WriteBool(r.move ~= nil)
                if r.move then net.WriteVector(r.move) end
                net.WriteUInt(r.target, 14)
                net.WriteUInt(math.min(r.memE, 15), 4)
                net.WriteUInt(math.min(r.memD, 15), 4)
                net.WriteFloat(r.lod)
                net.WriteString(r.traits)
            end
        net.Send(ply)
    end
end)

concommand.Add("cai_profiler_start", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    CAI.Prof.Start()
end, nil, "Start the CAI performance profiler session.")

concommand.Add("cai_profiler_stop", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    CAI.Prof.Stop()
end, nil, "Stop the CAI performance profiler session.")

concommand.Add("cai_profiler_dump", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    CAI.Prof.Dump()
end, nil, "Print the CAI profiler report to console.")

concommand.Add("cai_dump", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    print(("===== Combat Intelligence AI %s (%s) ====="):format(CAI.Version, CAI.Build or "?"))
    print("Managed NPCs: " .. CAI.Perf.Stats.managed)
    print("Thinks/sec:   " .. CAI.Perf.Stats.thinksPerSecond)
    print("Avg think ms: " .. string.format("%.3f", CAI.Perf.Stats.avgThinkMs))
    local byClass = {}
    for npc in pairs(CAI.Manager.All()) do
        if IsValid(npc) then
            local c = npc:GetClass()
            byClass[c] = (byClass[c] or 0) + 1
        end
    end
    for c, n in SortedPairs(byClass) do
        print(("  %s x%d"):format(c, n))
    end
    for _, ply in ipairs(player.GetAll()) do
        local age = ply.CAI_LightAt and math.Round(CurTime() - ply.CAI_LightAt, 1) or -1
        print(("  light %s = %.2f (age %ss)%s"):format(ply:Nick(), ply.CAI_Light or 1, age,
            age < 0 and " NO REPORTS - client light sensing not arriving" or ""))
    end
    for id, squad in pairs(CAI.Squad.Squads) do
        print(("Squad %d [%s] members=%d plan=%s formation=%s staggerPhase=%s")
            :format(id, squad.faction, #squad.members, squad.plan or "?", squad.formation,
            squad._staggerPhase and string.format("%.1fs ago", CurTime() - squad._staggerPhase) or "nil"))
    end
    print("")
    print("--- Per-NPC details ---")
    for npc, data in pairs(CAI.Manager.All()) do
        if IsValid(npc) then
            local stateName = CAI.STATE_NAMES[data.state] or ("?" .. tostring(data.state))
            local stateAge = math.Round(CurTime() - (data.stateSince or 0), 1)
            print(("-- %s [%s] idx=%d --"):format(npc:GetClass(), npc:GetModel() or "?", npc:EntIndex()))
            print(("  state=%s (%.1fs) lastDecision=%s"):format(stateName, stateAge, data.lastDecision or "?"))
            print(("  morale=%d suppression=%d fighting=%s"):format(
                math.Round(data.morale), math.Round(data.suppression), tostring(data.fighting)))
            print(("  moveTarget=%s patrolAt=%s ago lastPatrol=%s"):format(
                data.moveTarget and string.format("(%.0f,%.0f,%.0f)", data.moveTarget.x, data.moveTarget.y, data.moveTarget.z) or "nil",
                data.patrolAt and string.format("%.1fs", CurTime() - data.patrolAt) or "nil",
                data.lastPatrolPoint and string.format("(%.0f,%.0f,%.0f)", data.lastPatrolPoint.x, data.lastPatrolPoint.y, data.lastPatrolPoint.z) or "nil"))
            print(("  squad=%s plan=%s role=%s leaderDist=%s"):format(
                data.squad and tostring(data.squad.id) or "nil",
                data.squadPlan or "nil",
                CAI.ROLE_NAMES[data.role] or "nil",
                data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
                    and string.format("%.0f", npc:GetPos():Distance(data.squad.leader:GetPos()))
                    or "n/a"))
            local investigateStr = "nil"
            if data.investigatePos then
                local remaining = math.Round((data.investigateUntil or 0) - CurTime(), 1)
                investigateStr = string.format("(%.0f,%.0f,%.0f) %.1fs left",
                    data.investigatePos.x, data.investigatePos.y, data.investigatePos.z, remaining)
            end
            print(("  investigate=%s"):format(investigateStr))
            print(("  clearingDoor=%s clearPhase=%s"):format(
                tostring(data.clearingDoor), tostring(data.clearPhase)))
            print(("  boundTarget=%s wantBound=%s boundArrived=%s"):format(
                data.boundTarget and "yes" or "nil",
                tostring(data.wantBound),
                data.boundArrived and string.format("%.1fs", CurTime() - data.boundArrived) or "nil"))
            print(("  staggerOffset=%s staggerCovering=%s"):format(
                tostring(data.staggerOffset), tostring(data.staggerCovering)))
            print(("  mem: enemies=%d sounds=%s dangers=%d"):format(
                table.Count(data.memory.enemies),
                #data.memory.sounds,
                #data.memory.dangers))
            local freshestEnemy, freshestRec = CAI.Memory.FreshestEnemy(data)
            if freshestRec then
                print(("  freshestEnemy=%s (%.1fs ago, %s)"):format(
                    IsValid(freshestEnemy) and freshestEnemy:EntIndex() or "?",
                    CurTime() - freshestRec.t,
                    freshestRec.seen and "seen" or "heard"))
            else
                print("  freshestEnemy=none")
            end
            local engineEnemy = npc.GetEnemy and npc:GetEnemy()
            local engValid = IsValid(engineEnemy)
            local distStr = "n/a"
            local canSeeStr = "n/a"
            local archStr = "none"
            local idealStr = "n/a"
            if engValid then
                local d = npc:GetPos():Distance(engineEnemy:GetPos())
                distStr = string.format("%.0f", d)
                canSeeStr = tostring(CAI.Util.CanSee(npc, engineEnemy))
            end
            local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
            if IsValid(wep) then
                local cls = wep:GetClass()
                archStr = CAI.WeaponIntel and CAI.WeaponIntel.OwnArch(npc) or cls
                idealStr = CAI.WeaponIntel and tostring(CAI.WeaponIntel.OwnIdeal(npc)) or "n/a"
            end
            print(("  engineEnemy=%s dist=%s canSee=%s weapon=%s ideal=%s"):format(
                engValid and engineEnemy:EntIndex() or "nil",
                distStr, canSeeStr, archStr, idealStr))
            local fireUntilStr = "nil"
            if data.fireUntil then
                local rem = data.fireUntil - CurTime()
                fireUntilStr = rem > 0 and string.format("%.1fs blocking", rem) or "expired"
            end
            print(("  fireUntil=%s suppressUntil=%s"):format(fireUntilStr,
                data.suppressUntil and (data.suppressUntil > CurTime()
                    and string.format("%.1fs", data.suppressUntil - CurTime())
                    or "expired") or "nil"))
            local sched = "unknown"
            if npc.IsCurrentSchedule then
                if npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1) then sched = "RANGE_ATTACK1"
                elseif npc:IsCurrentSchedule(SCHED_ESTABLISH_LINE_OF_FIRE) then sched = "ESTABLISH_LOF"
                elseif npc:IsCurrentSchedule(SCHED_COMBAT_FACE) then sched = "COMBAT_FACE"
                elseif npc:IsCurrentSchedule(SCHED_FORCED_GO) then sched = "FORCED_GO"
                elseif npc:IsCurrentSchedule(SCHED_FORCED_GO_RUN) then sched = "FORCED_GO_RUN"
                elseif npc:IsCurrentSchedule(SCHED_TAKE_COVER_FROM_ENEMY) then sched = "TAKE_COVER"
                elseif npc:IsCurrentSchedule(SCHED_MELEE_ATTACK1) then sched = "MELEE_ATTACK1"
                elseif npc:IsCurrentSchedule(SCHED_RELOAD) then sched = "RELOAD"
                else
                    if npc.GetCurrentSchedule then sched = tostring(npc:GetCurrentSchedule()) end
                end
            end
            print(("  schedule=%s"):format(sched))
        end
    end
end, nil, "Print AI statistics, squad list, and per-NPC diagnostics to console.")
