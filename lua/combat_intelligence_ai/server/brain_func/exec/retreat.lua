local BR = CAI.Brain

-- RETREAT: fall back from danger, escape melee encirclement, scatter from
-- grenades, hide when unarmed, or retreat to a safe spot (caching the dest).
BR.Exec[7] = function(data)
    local npc = data.ent

    if data.lastDecision == "escape_encirclement" then
        local ecfg = CAI.Config.Escape
        local now = CurTime()
        local count, nearest, nearDist, centroid = BR.MeleeThreatScan(data)

        if nearDist > ecfg.ClearDist and count < ecfg.SurroundCount
           and now - (data.lastMeleeHurtAt or 0) > ecfg.MeleeHitGrace then
            data.saidRetreat = false
            local wep = npc:GetActiveWeapon()
            if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 then
                BR.SetState(data, CAI.STATE.COVER, "reloading_cover")
            else
                BR.SetState(data, CAI.STATE.ENGAGE, "engage_target")
            end
            return
        end

        local ref = centroid or (IsValid(nearest) and nearest:GetPos()) or data.escapeCentroid
        if IsValid(nearest) and CurTime() - (data.shoveAt or 0) > 1.5
           and npc.CapabilitiesGet
           and bit.band(npc:CapabilitiesGet(), CAP_INNATE_MELEE_ATTACK1) ~= 0
           and npc:GetPos():DistToSqr(nearest:GetPos()) < ecfg.ShoveRange * ecfg.ShoveRange then
            data.shoveAt = now
            if npc.SetEnemy then npc:SetEnemy(nearest) end
            npc:SetSchedule(SCHED_MELEE_ATTACK1)
            return
        end

        if now - (data.escapeMoveAt or 0) > 1.0 then
            data.escapeMoveAt = now
            local away = ref and (npc:GetPos() - ref) or Vector(1, 0, 0)
            away.z = 0
            if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
            away:Normalize()
            local yaw = away:Angle().y
            local dest
            for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                local dir = Angle(0, yaw + off, 0):Forward()
                dest = CAI.Nav.SafeOffset(npc:GetPos(), dir, ecfg.Step)
                if dest then break end
            end
            if dest then CAI.Nav.MoveTo(data, dest, "run") end
            if not data.saidRetreat then
                data.saidRetreat = true
                CAI.Voice.Speak(data, "retreat")
            end
        end
        return
    end

    if data.scatterFrom and data.scatterUntil and CurTime() < data.scatterUntil then
        local away = npc:GetPos() - data.scatterFrom
        away.z = 0
        if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
        away:Normalize()
        local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 280)
        if dest then CAI.Nav.MoveTo(data, dest, "run") end
        return
    end
    local unarmed = data.lastDecision == "unarmed_flee"
    if unarmed and CurTime() - (data.hideAt or 0) > 2 then
        data.hideAt = CurTime()
        local _, rec = CAI.Memory.FreshestEnemy(data)
        local threat = rec and rec.pos
        local spot = threat and CAI.Cover.FindBest(data, nil, threat)
        if spot then
            CAI.Nav.MoveTo(data, spot, "run")
        elseif threat then
            local away = (npc:GetPos() - threat); away.z = 0; away:Normalize()
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 700) or npc:GetPos()
            CAI.Nav.MoveTo(data, dest, "run")
        end
        if not data.saidRetreat then
            data.saidRetreat = true
            CAI.Voice.Speak(data, "panic")
        end
        return
    end

    -- Pick / refresh a retreat destination (prefer real cover >300u from the
    -- threat, else a random offset away). Cached in data.retreatDest so we
    -- don't thrash destinations every tick.
    if not data.retreatDest or CAI.Nav.Arrived(data, 100) or CurTime() - (data.retreatAt or 0) > 5 then
        data.retreatAt = CurTime()
        local _, rec = CAI.Memory.FreshestEnemy(data)
        if rec then
            local threat = rec.pos
            local spot = CAI.Cover.FindBest(data, nil, threat)
            local dest
            if spot and spot:DistToSqr(threat) > 300 * 300 then
                dest = spot
            else
                local away = (npc:GetPos() - threat); away.z = 0; away:Normalize()
                local yaw = away:Angle().y
                for _, off in ipairs({0,60,-60,120}) do
                    local dir = Angle(0,yaw+off,0):Forward()
                    dest = CAI.Nav.RandomPointNear(npc:GetPos() + dir * 800, 400)
                    if dest then break end
                end
                dest = dest or CAI.Nav.SafeOffset(npc:GetPos(), away, 600) or npc:GetPos()
            end
            data.retreatDest = dest
            CAI.Nav.MoveTo(data, dest, "run")
        elseif not data.fleeSched then
            data.fleeSched = true
            npc:SetSchedule(SCHED_RUN_FROM_ENEMY)
        end
        if not data.saidRetreat then
            data.saidRetreat = true
            CAI.Voice.Speak(data, "retreat")
            if data.squad then CAI.Squad.Broadcast(data.squad, "retreating", npc) end
        end
    end

    if data.morale > CAI.Config.Morale.ShakenThreshold + 10 then
        data.saidRetreat = false
        BR.SetState(data, CAI.STATE.COVER, "morale_recovered")
    end
end

