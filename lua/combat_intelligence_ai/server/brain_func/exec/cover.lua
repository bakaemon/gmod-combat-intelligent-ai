local BR = CAI.Brain

-- COVER: find and hold a scored cover spot, reload from safety, and run a
-- duck/pop cycle (peek to shoot, duck when suppressed) to survive fire.
BR.Exec[3] = function(data)
    local npc = data.ent
    local dangerAvoid = CAI.CVBool("cai_danger_avoid")
    local enemy, rec = BR.CombatTarget(data)
    local enemyPos = rec and rec.pos or (IsValid(enemy) and enemy:GetPos())

    -- Refresh which cover spot currently shields us from the enemy.
    CAI.Cover.UpdateCoverStatus(data, enemy)

    -- Hurt-response: when recently shot, flinch / relocate to break line of sight,
    -- scaled by aggression (brave & reckless hold, cowards & defensive relocate often).
    if CAI.CVBool("cai_hurt_react") and not CAI.CVBool("cai_performance_mode")
       and CurTime() < (data.hurtReactUntil or 0) then
        local now = CurTime()
        local inCover = data.cover ~= nil
        local aggro = CAI.WeaponIntel.EffectiveAggression(data)
        local cd = inCover and Lerp(aggro, CAI.Config.Suppression.HurtCoverCdMin,
                                            CAI.Config.Suppression.HurtCoverCdMax)
                            or CAI.Config.Suppression.HurtExposeCd
        if now - (data.evadeAt or 0) > cd then
            local src = (IsValid(data.lastAttacker) and data.lastAttacker) or enemy
            if IsValid(src) then
                local away = npc:GetPos() - src:GetPos()
                away.z = 0
                away:Normalize()
                local dist = inCover and CAI.Config.Suppression.HurtEvadeDist * 0.4
                                    or CAI.Config.Suppression.HurtEvadeDist
                local dest = CAI.Nav.SafeOffset(data, away, dist)
                if dest and not CAI.Util.CanSeePos(src, dest + Vector(0, 0, 40)) then
                    data.evadeAt = now
                    data.cover = nil
                    CAI.Nav.MoveTo(data, dest, "run")
                    return
                end
            end
        end
    end

    if not data.cover then
        local pos = CAI.Cover.FindBest(data, enemy, enemyPos)
        if not pos and CurTime() - (data.nodeCoverAt or 0) > 3 then
            data.nodeCoverAt = CurTime()
            npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
        end
        if pos then
            if dangerAvoid and CAI.Memory.AvoidPos(data, pos, CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius) then
                pos = nil
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
                BR.SetState(data, CAI.STATE.ENGAGE, "no_cover_available")
                return
            end
            if CurTime() - (data.engCoverAt or 0) > 3 then
                data.engCoverAt = CurTime()
                npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
            end
            return
        end
    end

    if data.cover and not CAI.Nav.Arrived(data, 80) then
        local inGo = npc.IsCurrentSchedule and (npc:IsCurrentSchedule(SCHED_FORCED_GO)
            or npc:IsCurrentSchedule(SCHED_FORCED_GO_RUN))
        if not inGo and CurTime() - (data.moveIssuedAt or 0) > 1.0 then
            CAI.Nav.MoveTo(data, data.cover.pos, "run")
        end
    end

    if data.lastDecision == "reloading_cover" then
        local wep = npc:GetActiveWeapon()
        if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 then
            local reloading = npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_RELOAD)
            if not reloading and CurTime() - (data.forceReloadAt or 0) > 3.5 then
                data.forceReloadAt = CurTime()
                data.coverPhase = nil
                data.moveTarget = nil
                npc:SetSchedule(SCHED_RELOAD)
            end
            return
        end
        if IsValid(wep) and wep.Clip1 and wep:Clip1() > 0 then
            data.forceReloadAt = nil
            local engaged = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
                and npc:GetPos():Distance(enemy:GetPos()) <= CAI.WeaponIntel.OwnRange(npc)
            if not engaged and data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
               and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 900 * 900 then
                data.cover = nil
                CAI.Brain.SetState(data, CAI.STATE.REGROUP, "reloaded_regroup")
                return
            end
        end
    end

    if CAI.Nav.Arrived(data, 80) then
        local aggro = CAI.CVNum("cai_aggression")
        local now = CurTime()
        if CAI.Suppression.IsPinned(data) and aggro < 0.95 then
            if data.coverPhase ~= "duck" then
                data.coverPhase = "duck"
                data.coverPhaseEnd = now + 2 * (1.3 - aggro)
                npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
            end
            if now > (data.coverPhaseEnd or 0) then data.coverPhase = nil end
        -- Duck/pop cycle: when suppressed, duck (take cover), otherwise pop up to
    -- shoot, then duck again on a timer. Prefires at remembered positions.
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
                        npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
                    end
                end
            end
        end
    end
    CAI.FriendlyFire.Update(data)
end

