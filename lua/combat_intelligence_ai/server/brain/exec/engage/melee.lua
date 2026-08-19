local BR = CAI.Brain

local function handler(data)
    local npc = data.ent
    local decision = data.lastDecision

    if decision == "melee_chase" then
        local mcfg = CAI.Config.Melee
        local me, mrec = BR.CombatTarget(data)
        local now = CurTime()
        if IsValid(me) and npc:GetPos():DistToSqr(me:GetPos()) < mcfg.SwingRange * mcfg.SwingRange then
            if npc.SetEnemy then npc:SetEnemy(me) end
            if now < (data.meleePhaseEnd or 0) then return end
            if data.meleePhase == "swing" then
                local act = npc.GetActivity and npc:GetActivity()
                if act == ACT_MELEE_ATTACK1 or act == ACT_MELEE_ATTACK2
                   or act == ACT_MELEE_ATTACK_SWING then
                    data.meleePhaseEnd = now + 0.1
                    return
                end
                if CAI.CVBool("cai_performance_mode") then
                    data.meleePhase = nil
                    return
                end
                data.meleePhase = "step"
                data.meleePhaseEnd = now + mcfg.StepTime
                local toMe = me:GetPos() - npc:GetPos()
                toMe.z = 0
                if toMe:LengthSqr() > 1 then
                    toMe:Normalize()
                    local right = Vector(-toMe.y, toMe.x, 0)
                    data.meleeSide = data.meleeSide or (math.random() < 0.5 and 1 or -1)
                    if math.random() < 0.35 then data.meleeSide = -data.meleeSide end
                    local dest = CAI.Nav.SafeOffset(me:GetPos(), right * data.meleeSide, mcfg.StrafeStep)
                              or CAI.Nav.SafeOffset(npc:GetPos(), right * data.meleeSide, mcfg.StrafeStep)
                    if dest then CAI.Nav.MoveTo(data, dest, "run") end
                end
            else
                local lead = mcfg.SwingLead or 0.4
                local reach = mcfg.Reach or 80
                local predicted = me:GetPos() + me:GetVelocity() * lead
                local myPredicted = npc:GetPos() + npc:GetVelocity() * lead
                local canHit = npc.HasCondition and COND_CAN_MELEE_ATTACK1 and npc:HasCondition(COND_CAN_MELEE_ATTACK1)
                local willHit = myPredicted:DistToSqr(predicted) < reach * reach
                data.meleePhase = "swing"
                data.meleePhaseEnd = now + mcfg.ReSwing
                data.moveTarget = nil
                if canHit or willHit then
                    if npc.SetIdealYawAndUpdate then
                        local toP = predicted - npc:GetPos()
                        if toP:Length2DSqr() > 1 then
                            local wantYaw = toP:Angle().yaw
                            local diff = math.abs(math.AngleDifference(wantYaw, npc:GetAngles().yaw))
                            if diff > 20 then
                                npc:SetIdealYawAndUpdate(wantYaw)
                            end
                        end
                    end
                    npc:SetSchedule(SCHED_MELEE_ATTACK1)
                else
                    npc:SetSchedule(SCHED_CHASE_ENEMY)
                end
                if mcfg.PlaybackRate ~= 1 and npc.SetPlaybackRate then
                    npc:SetPlaybackRate(mcfg.PlaybackRate)
                end
            end
            return
        end
        data.meleePhase = nil
        local schedFailed = npc.HasCondition and COND_TASK_FAILED and npc:HasCondition(COND_TASK_FAILED)
        if mrec and (schedFailed or now - (data.chaseAt or 0) > 0.8) then
            data.chaseAt = now
            if IsValid(me) and me.GetPos then
                if npc.SetEnemy then npc:SetEnemy(me) end
                CAI.Nav.MoveTo(data, me:GetPos(), "run")
            else
                CAI.Nav.MoveTo(data, mrec.pos, "run")
            end
        end
        return
    end

    if decision == "melee_ambush" then
        local mcfg = CAI.Config.Melee
        local acfg = mcfg.Ambush
        local now = CurTime()
        local me, mrec = BR.CombatTarget(data)
        local threat = (IsValid(me) and me:GetPos()) or (mrec and mrec.pos)
        if not threat then return end

        local dSqr = IsValid(me) and npc:GetPos():DistToSqr(me:GetPos()) or math.huge
        local spotted = IsValid(me) and CAI.Util.CanSee(me, npc)
        if dSqr < acfg.PounceDist * acfg.PounceDist
           or (spotted and dSqr < (acfg.PounceDist * 1.6) ^ 2) then
            data.ambush = nil
            data.lastDecision = "melee_chase"
            decision = "melee_chase"
            if npc.SetEnemy then npc:SetEnemy(me) end
            CAI.Nav.MoveTo(data, me:GetPos(), "run")
            return
        end

        if not data.ambush
           or now - data.ambush.since > acfg.MaxWait
           or threat:DistToSqr(data.ambush.threat) > acfg.RepickDist * acfg.RepickDist then
            data.wantDarkCover = true
            local spot = CAI.Cover.FindBest(data, me, threat)
            data.wantDarkCover = nil
            if not spot then
                data.lastDecision = "melee_chase"
                decision = "melee_chase"
                return
            end
            data.ambush = { pos = spot, since = now, threat = threat }
            CAI.Nav.MoveTo(data, spot, "run")
        end

        if not CAI.Nav.Arrived(data, 60) then
            if now - (data.moveIssuedAt or 0) > 1.2 then
                CAI.Nav.MoveTo(data, data.ambush.pos, "run")
            end
            return
        end

        if now - (data.ambushHoldAt or 0) > 2 then
            data.ambushHoldAt = now
            data.moveTarget = nil
            npc:SetSchedule(SCHED_IDLE_STAND)
        end
        return
    end

    if decision == "cornered_melee" then
        if CurTime() - (data.meleeAt or 0) > 1.2 then
            data.meleeAt = CurTime()
            if not npc.HasCondition or not COND_CAN_MELEE_ATTACK1 or npc:HasCondition(COND_CAN_MELEE_ATTACK1) then
                npc:SetSchedule(SCHED_MELEE_ATTACK1)
            else
                npc:SetSchedule(SCHED_CHASE_ENEMY)
            end
            CAI.Voice.Speak(data, "panic")
        end
        return
    end
end

BR.RegisterHook("brain/exec/engage", "melee", handler)