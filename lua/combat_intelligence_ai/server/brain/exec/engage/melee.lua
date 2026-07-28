local BR = CAI.Brain

local cornerCache = {}
local function CornerScore(pos)
    local key = math.floor(pos.x / 64) .. ":" .. math.floor(pos.y / 64)
        .. ":" .. math.floor(pos.z / 64)
    local c = cornerCache[key]
    if c and CurTime() - c.t < 15 then return c.v end
    local eye = pos + Vector(0, 0, 40)
    local hits = 0
    for i = 0, 7 do
        local a = math.rad(i * 45)
        local tr = util.TraceLine({
            start = eye,
            endpos = eye + Vector(math.cos(a), math.sin(a), 0) * 90,
            mask = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then hits = hits + 1 end
    end
    local v = 0
    if hits >= 2 and hits <= 4 then v = 1
    elseif hits == 5 then v = 0.5 end
    if table.Count(cornerCache) > 256 then cornerCache = {} end
    cornerCache[key] = { v = v, t = CurTime() }
    return v
end

local function FindAmbushSpot(data, enemy, threatPos)
    local mcfg = CAI.Config.Melee
    data.wantDarkCover = true
    local best = CAI.Cover.FindBest(data, enemy, threatPos)
    data.wantDarkCover = nil
    if not best then return nil end
    if CAI.CVBool("cai_performance_mode") then return best end

    local bestScore = CornerScore(best) * mcfg.CornerBonus
    for i = 0, 5 do
        local a = math.rad(i * 60)
        local cand = CAI.Nav.SafeOffset(best,
            Vector(math.cos(a), math.sin(a), 0), mcfg.CornerRadius)
        if cand and CAI.Nav.IsGroundSpot(cand)
           and (not IsValid(enemy) or not CAI.Util.CanSeePos(enemy, cand)) then
            local sc = CornerScore(cand) * mcfg.CornerBonus
                     + (CAI.Cover.SpotShade(cand) or 0)
            if sc > bestScore then best, bestScore = cand, sc end
        end
    end
    return best
end

local function handler(data)
    local npc = data.ent
    local decision = data.lastDecision

    if decision == "melee_chase" or decision == "melee_ambush" then
        local mcfg = CAI.Config.Melee
        local now = CurTime()
        if now - (data.meleeThreatCheckAt or 0) > mcfg.ThreatRecheck then
            data.meleeThreatCheckAt = now
            local foe = BR.CombatTarget(data)
            if IsValid(foe) and CAI.Util.CanSee(npc, foe) then
                local tc = CAI.WeaponIntel.ThreatClass(foe)
                local dist = npc:GetPos():Distance(foe:GetPos())
                data.meleeThreatSeen = tc
                if dist >= mcfg.GunPanicDist then
                    if tc == "gun" and decision == "melee_chase" then
                        data.meleePhase = nil
                        data.moveTarget = nil
                        data.lastDecision = "melee_ambush"
                        decision = "melee_ambush"
                    elseif tc ~= "gun" and decision == "melee_ambush" then
                        data.ambush = nil
                        data.lastDecision = "melee_chase"
                        decision = "melee_chase"
                    end
                end
            end
        end
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
        local a = data.ambush

        local pounce = acfg.PounceDist
        if a and a.alerted and now - a.alerted < 3 then
            pounce = pounce * acfg.AlertPounceMult
        end
        local dSqr = IsValid(me) and npc:GetPos():DistToSqr(me:GetPos()) or math.huge
        local spotted = IsValid(me) and CAI.Util.CanSee(me, npc)
        if dSqr < pounce * pounce
           or (spotted and dSqr < (pounce * 1.6) ^ 2) then
            data.ambush, data.ambushRetry = nil, nil
            data.lastDecision = "melee_chase"
            decision = "melee_chase"
            if npc.SetEnemy then npc:SetEnemy(me) end
            CAI.Nav.MoveTo(data, me:GetPos(), "run")
            return
        end

        if a and a.settled and not spotted
           and now - (data.lastHurtAt or 0) < acfg.HurtBreakTime then
            a, data.ambush = nil, nil
        end

        local needSpot = not a
            or threat:DistToSqr(a.threat) > acfg.RepickDist * acfg.RepickDist
        if a and not a.settled then
            if now - a.since > acfg.PathTimeout then needSpot = true end
            local ply, plyDSqr = CAI.Util.NearestPlayer(a.pos)
            if IsValid(ply) and plyDSqr < acfg.SpotTakenDist * acfg.SpotTakenDist then
                needSpot = true
            end
        elseif a and a.settled and now > (a.holdUntil or 0) then
            needSpot = true
        end

        if needSpot then
            data.ambushRetry = (data.ambushRetry or 0) + 1
            local spot = data.ambushRetry <= acfg.MaxRetries
                and FindAmbushSpot(data, me, threat) or nil
            if not spot then
                data.ambush, data.ambushRetry = nil, nil
                data.lastDecision = "melee_chase"
                decision = "melee_chase"
                return
            end
            a = { pos = spot, since = now, threat = threat }
            data.ambush = a
            CAI.Nav.MoveTo(data, spot, "run")
        end

        if not a.settled then
            local range = npc:GetPos():Distance(a.pos)

            if not a.lookedOut and range < acfg.LookOutDist and range > 20 then
                a.lookedOut = true
                local out = npc:GetPos() - a.pos
                out.z = 0
                if out:Length2DSqr() > 1 and npc.SetIdealYawAndUpdate then
                    npc:SetIdealYawAndUpdate(out:Angle().yaw)
                end
            end

            if range < acfg.ArriveDist or CAI.Nav.Arrived(data, acfg.ArriveDist) then
                a.settled = true
                a.settledAt = now
                a.holdUntil = now + math.Rand(acfg.HoldMin, acfg.HoldMax)
                data.ambushRetry = nil
                data.moveTarget = nil

                local watchYaw
                local toThreat = threat - npc:GetPos()
                toThreat.z = 0
                if mrec and now - (mrec.t or 0) < 8 and toThreat:Length2DSqr() > 1 then
                    watchYaw = toThreat:Angle().yaw
                else
                    local eye = npc:EyePos()
                    local bestOpen = -1
                    for i = 0, 7 do
                        local ang = math.rad(i * 45)
                        local dir = Vector(math.cos(ang), math.sin(ang), 0)
                        local tr = util.TraceLine({
                            start = eye, endpos = eye + dir * 1000,
                            filter = npc, mask = MASK_SOLID_BRUSHONLY,
                        })
                        if tr.Fraction > bestOpen then
                            bestOpen, watchYaw = tr.Fraction, dir:Angle().yaw
                        end
                    end
                end
                if watchYaw and npc.SetIdealYawAndUpdate then
                    npc:SetIdealYawAndUpdate(watchYaw)
                end
                CAI.Schedule(data, SCHED_IDLE_STAND)
                return
            end

            if now - (data.moveIssuedAt or 0) > 1.2 then
                CAI.Nav.MoveTo(data, a.pos, "run")
            end
            return
        end

        if now - (a.settledAt or 0) > acfg.SettleGrace then
            local sounds = data.memory.sounds
            local alertSqr = acfg.NoiseAlertDist * acfg.NoiseAlertDist
            for i = #sounds, 1, -1 do
                local snd = sounds[i]
                if now - snd.t > 1.5 then break end
                if npc:GetPos():DistToSqr(snd.pos) < alertSqr then
                    a.alerted = now
                    local toS = snd.pos - npc:GetPos()
                    toS.z = 0
                    if toS:Length2DSqr() > 1 and npc.SetIdealYawAndUpdate then
                        npc:SetIdealYawAndUpdate(toS:Angle().yaw)
                    end
                    break
                end
            end
        end

        if now - (data.ambushHoldAt or 0) > 2 then
            data.ambushHoldAt = now
            data.moveTarget = nil
            CAI.Schedule(data, SCHED_IDLE_STAND)
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