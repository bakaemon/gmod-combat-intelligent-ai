local BR = CAI.Brain

BR.RegisterHook("brain/exec", "cover", function(data)
    local npc = data.ent
    local dangerAvoid = CAI.CVBool("cai_danger_avoid")
    local enemy, rec = BR.CombatTarget(data)
    local enemyPos = rec and rec.pos or (IsValid(enemy) and enemy:GetPos())

    CAI.Cover.UpdateCoverStatus(data, enemy)

    if not data.cover then
        local pos = CAI.Cover.FindBest(data, enemy, enemyPos)
        if not pos and CurTime() - (data.nodeCoverAt or 0) > 3 then
            data.nodeCoverAt = CurTime()
            CAI.Schedule(data, SCHED_TAKE_COVER_FROM_ENEMY)
        end
        if pos then
            if dangerAvoid and CAI.Memory.AvoidPos(data, pos, CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius) then
                pos = nil
            end
        end
        if pos and data.squad then
            for _, m in ipairs(data.squad.members) do
                if IsValid(m) and m ~= npc and npc:GetPos():DistToSqr(m:GetPos()) < 150 * 150 then
                    pos = nil
                    break
                end
            end
            if pos and #data.squad.members > 1 then
                local closest = math.huge
                local center = CAI.SquadFunc.SquadCenterOfMass(data.squad, npc)
                for _, m in ipairs(data.squad.members) do
                    if IsValid(m) and m ~= npc then
                        local d = pos:DistToSqr(m:GetPos())
                        if d < closest then closest = d end
                    end
                end
                if closest > 600 * 600 and center then
                    local dir = (center - pos):GetNormalized()
                    dir.z = 0
                    local nudged = CAI.Nav.SafeOffset(pos, dir, 300)
                    if nudged then pos = nudged end
                end
            end
        end
        if pos then
            data.cover = { pos = pos, since = CurTime() }
            data.coverBounces = (data.coverBounces or 0) + 1
            data.coverSearchFailures = 0
            CAI.Nav.MoveTo(data, pos, "run")
            if math.random() < 0.25 then CAI.Voice.Speak(data, "cover_me") end
        else
            data.coverSearchFailures = (data.coverSearchFailures or 0) + 1
            if data.coverSearchFailures >= 4 then
                data.coverSearchFailures = 0
                data.planPending = "no_cover_available"
                return
            end
            if CurTime() - (data.engCoverAt or 0) > 3 then
                data.engCoverAt = CurTime()
                CAI.Schedule(data, SCHED_TAKE_COVER_FROM_ENEMY)
            end
            return
        end
    end

    if data.cover and npc:GetPos():DistToSqr(data.cover.pos) > 80 * 80 then
        local inGo = npc.IsCurrentSchedule and (npc:IsCurrentSchedule(SCHED_FORCED_GO)
            or npc:IsCurrentSchedule(SCHED_FORCED_GO_RUN))
        if not inGo and CurTime() - (data.moveIssuedAt or 0) > 1.0 then
            CAI.Nav.MoveTo(data, data.cover.pos, "run")
        end
    end

    if npc:GetPos():DistToSqr(data.cover.pos) < 80 * 80 then
        local aggro = CAI.CVNum("cai_aggression")
        local now = CurTime()
        if CAI.Suppression.IsPinned(data) and aggro < 0.95 then
            if data.coverPhase ~= "duck" then
                data.coverPhase = "duck"
                data.coverPhaseEnd = now + 2 * (1.3 - aggro)
                npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
            end
            if now > (data.coverPhaseEnd or 0) then data.coverPhase = nil end
        elseif now > (data.coverPhaseEnd or 0) then
            if data.coverPhase == "pop" then
                data.coverPhase = "duck"
                data.coverPhaseEnd = now + math.Rand(1.0, 1.8) * (1.3 - aggro)
                npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
            else
                if dangerAvoid and CAI.Memory.AvoidPos(data, npc:GetPos(), CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius)
                   and not (IsValid(enemy) and CAI.Util.Sees(npc, enemy)) then
                    data.coverPhase = "duck"
                    data.coverPhaseEnd = now + math.Rand(1.0, 1.8) * (1.3 - aggro)
                    npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
                else
                    data.coverPhase = "pop"
                    data.coverPhaseEnd = now + math.Rand(2.2, 3.4)
                    data.coverBounces = 0
                    data.lastEngageAt = now
                    local _, prec = BR.CombatTarget(data)
                    if prec and not CAI.Util.CanSeePos(npc, prec.pos + Vector(0, 0, 40))
                       and CurTime() - (prec.t or 0) < 4 then
                        CAI.Brain.Prefire(data, prec.pos)
                    else
                        CAI.Brain.FireSchedule(data)
                    end
                end
            end
        end
    end
    do
        local wep = npc:GetActiveWeapon()
        if IsValid(wep) and wep.Clip1 and wep:Clip1() > 0 and wep:Clip1() < (wep.GetMaxClip1 and wep:GetMaxClip1() or wep:Clip1()) * 0.3 then
            local reloading = npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_RELOAD)
            if not reloading and CurTime() > (data._tacticalReloadAt or 0) then
                data._tacticalReloadAt = CurTime() + 2.0
                data._reloadingAt = CurTime()
                npc:SetSchedule(SCHED_RELOAD)
            end
        end
    end
    CAI.FriendlyFire.Update(data)
end)
