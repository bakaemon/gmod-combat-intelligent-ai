local BR = CAI.Brain

BR.ExecPhase[CAI.PHASE.ENGAGE] = function(data)
    local npc = data.ent

    if data.phaseIntent == "suppress" then
        local enemy, rec = BR.CombatTarget(data)
        if not rec then
            BR.StopSuppressing(data)
            data.suppNoLosAt = nil
            data.planPending = "nothing_to_suppress"
            return
        end

        if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < 200 * 200 then
            BR.StopSuppressing(data)
            data.suppNoLosAt = nil
            if npc.SetEnemy then npc:SetEnemy(enemy) end
            data.planPending = "too_close_suppress"
            return
        end

        if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc then
            local canFight = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
            if not canFight and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 900 * 900 then
                BR.StopSuppressing(data)
                data.suppNoLosAt = nil
                if npc.SetEnemy then npc:SetEnemy(NULL) end
                CAI.Nav.MoveTo(data, data.squad.leader:GetPos(), "run")
                return
            end
            data.moveTarget = nil
            data.moveIssuedAt = nil
        end

        local now = CurTime()
        if IsValid(enemy) and CAI.Util.Sees(npc, enemy) then
            BR.StopSuppressing(data)
            data.suppNoLosAt = now
            if npc.SetEnemy then npc:SetEnemy(enemy) end
            if npc.UpdateEnemyMemory and npc:GetEnemy() == enemy then npc:UpdateEnemyMemory(enemy, rec.pos) end
        else
            if not data.suppNoLosAt then data.suppNoLosAt = now end
            if now - data.suppNoLosAt > 8 then
                BR.StopSuppressing(data)
                data.suppressUntil = nil
                data.suppNoLosAt = nil
                CAI.Memory.SeeEnemy(data, enemy, rec.pos)
                data.planPending = "suppress_no_los"
                return
            end
            local aim
            for _, b in ipairs(CAI.Cover.Barrels()) do
                if IsValid(b) and b:GetPos():DistToSqr(rec.pos) < 170 * 170
                   and CAI.Util.CanSeePos(npc, b:GetPos() + Vector(0, 0, 10)) then
                    aim = b:GetPos() + Vector(0, 0, 10)
                    break
                end
            end
            for _, h in ipairs({ 55, 90 }) do
                if aim then break end
                local p = rec.pos + Vector(0, 0, h)
                if CAI.Util.CanSeePos(npc, p) then aim = p break end
            end
            if not aim and CAI.CVBool("cai_wallbang") then
                aim = rec.pos + Vector(0, 0, 55)
            end
            if not aim then
                aim = rec.pos + Vector(0, 0, 40)
            end
            if aim then
                CAI.FireAim.Aim(data, aim)
            else
                if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < 400 * 400 then
                    BR.StopSuppressing(data)
                    if npc.SetEnemy then npc:SetEnemy(enemy) end
                    data.planPending = "suppressed_no_target"
                    return
                end
            end
        end

        if not data.suppFaced then
            data.suppFaced = true
            npc:SetSchedule(SCHED_COMBAT_FACE)
        end
        if not data.saidSuppress then
            data.saidSuppress = true
            CAI.Voice.Speak(data, "suppressing")
            if data.squad then
                local sa = data.squad.blackboard.suppressedAt
                sa[#sa + 1] = { pos = rec.pos, t = CurTime() }
                if #sa > 6 then table.remove(sa, 1) end
                CAI.Squad.Broadcast(data.squad, "suppression_active", data.ent, { pos = rec.pos })
            end
        end
        if not data.suppressUntil or CurTime() > data.suppressUntil then
            data.saidSuppress = false
            data.suppNoLosAt = nil
            data.suppressUntil = nil
            data.planPending = "suppress_done"
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
        return
    end

    local decision = data.lastDecision
    if CAI.WeaponIntel.IsMelee(npc)
       and decision ~= "melee_chase"
       and decision ~= "melee_ambush"
       and decision ~= "cornered_melee" then
        decision = "melee_chase"
    end

    local moveShoot = CAI.CVBool("cai_move_shoot") and not CAI.CVBool("cai_performance_mode")
    local function tryMoveShoot()
        if not moveShoot then return false end
        if data.squad then
            local idx = 0
            for i, m in ipairs(data.squad.members) do
                if m == npc then idx = i break end
            end
            local maxMS = math.max(1, math.floor(#data.squad.members * (CAI.Config.SquadTactics.MoveShootFraction or 0.5)))
            if idx == 0 or idx > maxMS then return false end
        end
        data.fighting = nil
        data.moveTarget = nil
        npc:SetSchedule(SCHED_CHASE_ENEMY)
        return true
    end
    local dangerAvoid = CAI.CVBool("cai_danger_avoid")
    local function safeDest(p)
        if not dangerAvoid or not p then return true end
        local e = npc:GetEnemy()
        if IsValid(e) and CAI.Util.Sees(npc, e) then return true end
        return not CAI.Memory.AvoidPos(data, p, CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius)
    end

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

    if decision == "point_blank_fight" then
        local pcfg = CAI.Config.Escape
        local foe = data.pbEnemy
        if not IsValid(foe) then foe = BR.CombatTarget(data) end
        if not IsValid(foe) then return end
        if npc.SetEnemy and npc:GetEnemy() ~= foe then npc:SetEnemy(foe) end
        local now = CurTime()
        local dist = npc:GetPos():Distance(foe:GetPos())
        if now < (data.pbPhaseEnd or 0) then
            CAI.FriendlyFire.Update(data)
            return
        end
        if data.pbPhase == "fire" and dist < pcfg.WithdrawDist then
            data.pbPhase = "move"
            data.pbPhaseEnd = now + 0.8
            data.combatMoveAt = now
            local ref = data.escapeCentroid or foe:GetPos()
            local away = npc:GetPos() - ref
            away.z = 0
            if away:LengthSqr() < 1 then away = npc:GetPos() - foe:GetPos() away.z = 0 end
            away:Normalize()
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, pcfg.Step)
            if dest then CAI.Nav.MoveTo(data, dest, "run") end
        else
            data.pbPhase = "fire"
            data.pbPhaseEnd = now + 1.0
            data.moveTarget = nil
            npc:SetSchedule(SCHED_RANGE_ATTACK1)
        end
        CAI.FriendlyFire.Update(data)
        return
    end

    local enemy = npc:GetEnemy()
    if not IsValid(enemy) then
        local ct, cr = BR.CombatTarget(data)
        if not IsValid(ct) then
            data.planPending = "target_lost"
            data.plan.expiresAt = CurTime()
            return
        end
        if npc.SetEnemy then npc:SetEnemy(ct) end
        enemy = ct
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
    local now = CurTime()
    if data.fireUntil and now < data.fireUntil then
        if CAI.FriendlyFire.Update(data) then
            data.fireUntil = nil
        end
        return
    end
    local moving = data.moveTarget ~= nil and not CAI.Nav.Arrived(data, 70)
    if moving then
        if now - (data.combatMoveAt or 0) > 2.2 then
            data.moveTarget = nil
            data.fireUntil = now + 1.6
            CAI.Schedule(data, SCHED_ESTABLISH_LINE_OF_FIRE)
        end
        CAI.FriendlyFire.Update(data)
        return
    end

    if npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_CHASE_ENEMY) then
        CAI.FriendlyFire.Update(data)
        return
    end

    local ideal = CAI.WeaponIntel.OwnIdeal(npc)
    local ownArch = CAI.WeaponIntel.OwnArch(npc)
    local maxRange = CAI.WeaponIntel.OwnRange(npc)
    local resp = data.enemyWeaponResponse
    if resp and resp.keepDistance then ideal = math.max(ideal, resp.idealDist or ideal) end
    local dist = npc:GetPos():Distance(enemy:GetPos())

    if decision == "aggressive_push" then
        local pcfg = CAI.Config.Push
        local creepRange = ideal * pcfg.CreepMult
        local stopRange = ideal * pcfg.StopMult

        if dist > creepRange then
            if dist <= maxRange and CAI.Util.Sees(npc, enemy)
               and now >= (data.fireUntil or 0)
               and now - (data.pushBurstAt or 0) > pcfg.BoundInterval + pcfg.BurstDuration then
                data.pushBurstAt = now
                data.fireUntil = now + pcfg.BurstDuration
                data.moveTarget = nil
                data.fighting = nil
                CAI.Schedule(data, SCHED_ESTABLISH_LINE_OF_FIRE)
                CAI.FriendlyFire.Update(data)
                return
            end
            if now >= (data.fireUntil or 0) and now - (data.pushAt or 0) > pcfg.BoundInterval then
                data.pushAt = now
                data.combatMoveAt = now
                data.fighting = nil
                if tryMoveShoot() then return end
                local dir = enemy:GetPos() - npc:GetPos()
                dir.z = 0 dir:Normalize()
                local step = math.min(dist - creepRange, pcfg.BoundStep)
                local dest = CAI.Nav.SafeGround(npc:GetPos() + dir * step)
                          or CAI.Nav.SafeOffset(npc:GetPos(), dir, step)
                if dest and safeDest(dest) then
                    CAI.Nav.MoveTo(data, dest, "run")
                    if math.random() < 0.25 then CAI.Voice.Speak(data, "moving") end
                end
            end
            CAI.FriendlyFire.Update(data)
            return
        end

        local ecfg = CAI.Config.Escape
        local _, _, meleeNear = BR.MeleeThreatScan(data)
        if dist > stopRange and CAI.Util.Sees(npc, enemy)
           and meleeNear > ecfg.PointBlank * 1.5
           and now - (data.creepAt or 0) > pcfg.CreepInterval then
            data.creepAt = now
            data.combatMoveAt = now
            local dir = enemy:GetPos() - npc:GetPos()
            dir.z = 0 dir:Normalize()
            local dest = CAI.Nav.SafeGround(npc:GetPos() + dir * pcfg.CreepStep)
                      or CAI.Nav.SafeOffset(npc:GetPos(), dir, pcfg.CreepStep)
            if dest and safeDest(dest) then CAI.Nav.MoveTo(data, dest, "walk") end
            CAI.FriendlyFire.Update(data)
            return
        end
    end

    if resp == CAI.Config.WeaponResponses.melee then
        if dist < ideal * 0.95 then
            if now - (data.kiteAt or 0) > 1.2 then
                data.kiteAt = now
                data.combatMoveAt = now
                local away = npc:GetPos() - enemy:GetPos()
                away.z = 0 away:Normalize()
                local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 260)
                if dest then CAI.Nav.MoveTo(data, dest, "run") end
            end
        end
        CAI.FriendlyFire.Update(data)
    end

    if dist <= maxRange and CAI.Util.Sees(npc, enemy) then
        data.moveTarget = nil
        local firing = false
        if npc.IsCurrentSchedule then
            firing = npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1)
                or npc:IsCurrentSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        end
        if data.squad and data.squadPlan == "hold" and data.staggerOffset and data.squad._staggerPhase then
            local cycleLen = #data.squad.members * CAI.Config.SquadTactics.StaggerOffset
            local phase = (CurTime() - data.squad._staggerPhase) % cycleLen
            local myWindow = CAI.Config.SquadTactics.StaggerFireWindow
            if math.abs(phase - data.staggerOffset) > myWindow then
                if not data.staggerCovering then
                    data.staggerCovering = true
                    data.fighting = nil
                    npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
                end
                CAI.FriendlyFire.Update(data)
                return
            end
            data.staggerCovering = nil
        end
        if CAI.FriendlyFire.Update(data) then
            return
        end
        if data.fireAngleOffset and data.fireAngleOffset ~= 0 then
            local toEnemy = (enemy:GetPos() - npc:GetPos()):GetNormalized()
            local right = Vector(-toEnemy.y, toEnemy.x, 0)
            local offset = right * data.fireAngleOffset * 5
            local dest = CAI.Nav.SafeGround(npc:GetPos() + offset)
            if dest then CAI.Nav.MoveTo(data, dest, "walk") end
            data.fireAngleOffset = data.fireAngleOffset * 0.5
            if math.abs(data.fireAngleOffset) < 1 then data.fireAngleOffset = nil end
        end
        if not data.fighting or (not firing and CurTime() - (data.fightSchedAt or 0) > CAI.Config.Engage.RetryGap) then
            data.fighting = true
            data.fightSchedAt = CurTime()
            CAI.Schedule(data, SCHED_ESTABLISH_LINE_OF_FIRE)
        end
        return
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

    -- Close-range backoff even when visible: prevents face-off stand-and-deliver.
    if dist < CAI.Config.Engage.PointBlank * 2 and CAI.Util.Sees(npc, enemy)
        and now - (data.backoffAt or 0) > 2 then
        data.backoffAt = now
        data.combatMoveAt = now
        local away = npc:GetPos() - enemy:GetPos()
        away.z = 0 away:Normalize()
        local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 200)
        if dest then CAI.Nav.MoveTo(data, dest, "run") end
    end

    if dist < CAI.Config.Engage.PointBlank and not CAI.Util.Sees(npc, enemy) then
        if now - (data.backoffAt or 0) > 3 then
            data.backoffAt = now
            data.combatMoveAt = now
            local away = npc:GetPos() - enemy:GetPos()
            away.z = 0 away:Normalize()
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 200)
            if dest then CAI.Nav.MoveTo(data, dest, "run") end
        end
    elseif ownArch == "shotgun" and dist > ideal and now - (data.pressAt or 0) > 3 then
        data.pressAt = now
        data.combatMoveAt = now
        if tryMoveShoot() then return end
        local dir = enemy:GetPos() - npc:GetPos()
        dir.z = 0 dir:Normalize()
        local dest = CAI.Nav.SafeGround(enemy:GetPos() - dir * ideal * 0.6)
        if dest and safeDest(dest) then CAI.Nav.MoveTo(data, dest, "run") end
    elseif dist > maxRange then
        if now - (data.advanceAt or 0) > 1.8 then
            data.advanceAt = now
            data.combatMoveAt = now
            data.fighting = nil
            if tryMoveShoot() then return end
            local dir = enemy:GetPos() - npc:GetPos()
            dir.z = 0 dir:Normalize()
            local step = math.min(dist - ideal, 400)
            local dest = CAI.Nav.SafeGround(npc:GetPos() + dir * step)
                      or CAI.Nav.SafeOffset(npc:GetPos(), dir, step)
            if dest and safeDest(dest) then
                CAI.Nav.MoveTo(data, dest, "run")
                if math.random() < 0.3 then CAI.Voice.Speak(data, "moving") end
            end
        end
    else
        if now - (data.advanceAt or 0) > 2 then
            data.advanceAt = now
            if tryMoveShoot() then return end
            CAI.Schedule(data, SCHED_ESTABLISH_LINE_OF_FIRE)
        end
    end
    if data.squad and #data.squad.members > 1 then
        local minDist = CAI.Config.SquadTactics.MinSpacing or 150
        for _, m in ipairs(data.squad.members) do
            if IsValid(m) and m ~= npc then
                local dSq = npc:GetPos():DistToSqr(m:GetPos())
                if dSq < minDist * minDist then
                    local away = (npc:GetPos() - m:GetPos()):GetNormalized()
                    local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, minDist)
                    if dest then CAI.Nav.MoveTo(data, dest, "run") end
                    break
                end
            end
        end
        if not CAI.SquadFunc.FormationCheck(data) then
            data.planPending = "formation_broken"
            return
        end
    end
    CAI.FriendlyFire.Update(data)
end
