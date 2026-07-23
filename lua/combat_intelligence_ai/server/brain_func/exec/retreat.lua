local BR = CAI.Brain

-- RETREAT: fall back from danger, escape melee encirclement, scatter from
-- grenades, hide when unarmed, or retreat to a safe spot (caching the dest).
-- Retreat helpers: pick a destination that actually moves the NPC away from
-- the enemy formation instead of into it.

-- Aggregate repulsion direction from every known enemy (not just melee), so a
-- flee vector accounts for ranged shooters, not only the closest melee threat.
local function awayFromEnemies(data, npc)
    local push = Vector()
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and CAI.Util.Alive(ent) and rec.pos then
            local v = npc:GetPos() - rec.pos
            v.z = 0
            local len = v:Length()
            if len > 1 then push = push + v * (1 / len) end
        end
    end
    push.z = 0
    return push:LengthSqr() > 1 and push:GetNormalized() or nil
end

-- Closest known enemy position + distance, for the "don't get closer" test.
local function nearestEnemy(data, npc)
    local bestPos, bestD = nil, math.huge
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and rec.pos then
            local d = npc:GetPos():Distance(rec.pos)
            if d < bestD then bestPos, bestD = rec.pos, d end
        end
    end
    return bestPos, bestD
end

-- True if any known enemy can see the candidate point.
local function exposedToEnemies(data, p)
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and rec.pos and CAI.Util.CanSeePos(ent, p) then return true end
    end
    return false
end

-- Reject a candidate that lies in a known kill zone or would bring the NPC
-- closer to the nearest enemy than it already is.
local function safeRetreat(data, p, nearPos, curD)
    if not p then return false end
    if CAI.CVBool("cai_danger_avoid") and CAI.Memory.AvoidPos(data, p,
            CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius) then
        return false
    end
    if nearPos and curD and p:Distance(nearPos) < curD - 50 then return false end
    return true
end

BR.Exec[7] = function(data)
    local npc = data.ent
    local nearPos, curD = nearestEnemy(data, npc)

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
            -- Flee away from the melee threat if we have one; otherwise away from
            -- the whole enemy formation. Never collapse to a fixed world axis.
            local away = ref and (npc:GetPos() - ref) or awayFromEnemies(data, npc)
            away = away or Vector(1, 0, 0)
            away.z = 0
            if away:LengthSqr() < 1 then away = awayFromEnemies(data, npc) or Vector(1, 0, 0) end
            away:Normalize()
            local yaw = away:Angle().y
            local dest
            for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                local dir = Angle(0, yaw + off, 0):Forward()
                local p = CAI.Nav.SafeOffset(npc:GetPos(), dir, ecfg.Step)
                if p and safeRetreat(data, p, nearPos, curD) then dest = p break end
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
        local ent, rec = CAI.Memory.FreshestEnemy(data)
        local threat = rec and rec.pos
        local dest
        if threat then
            local spot = CAI.Cover.FindBest(data, ent, threat)
            if spot and safeRetreat(data, spot, nearPos, curD) and not exposedToEnemies(data, spot) then
                dest = spot
            end
            if not dest then
                local away = awayFromEnemies(data, npc) or (npc:GetPos() - threat)
                away.z = 0
                if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
                away:Normalize()
                local yaw = away:Angle().y
                for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                    local dir = Angle(0, yaw + off, 0):Forward()
                    local p = CAI.Nav.SafeOffset(npc:GetPos(), dir, 700)
                    if p and safeRetreat(data, p, nearPos, curD) then dest = p break end
                end
            end
        end
        if not dest then
            local away = awayFromEnemies(data, npc) or Vector(1, 0, 0)
            away.z = 0
            if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
            away:Normalize()
            dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 700)
        end
        if dest then CAI.Nav.MoveTo(data, dest, "run") end
        if not data.saidRetreat then
            data.saidRetreat = true
            CAI.Voice.Speak(data, "panic")
        end
        return
    end

    -- Pick / refresh a retreat destination. Prefer real cover hidden from
    -- enemies and outside known danger zones; otherwise move along a direction
    -- that increases distance from the whole enemy formation. Never commit a
    -- destination that sits in a kill zone or closer to the enemy.
    local cacheBad = data.retreatDest and CAI.CVBool("cai_danger_avoid")
        and CAI.Memory.AvoidPos(data, data.retreatDest,
            CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius)
    if not data.retreatDest or CAI.Nav.Arrived(data, 100)
       or CurTime() - (data.retreatAt or 0) > 5 or cacheBad then
        data.retreatAt = CurTime()
        local ent, rec = CAI.Memory.FreshestEnemy(data)
        if rec then
            local threat = rec.pos
            local spot = CAI.Cover.FindBest(data, ent, threat)
            local unseen, fallback
            if spot and safeRetreat(data, spot, nearPos, curD) then
                if not exposedToEnemies(data, spot) then unseen = spot
                else fallback = fallback or spot end
            end
            if not unseen then
                local away = awayFromEnemies(data, npc) or (npc:GetPos() - threat)
                away.z = 0
                if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
                away:Normalize()
                local yaw = away:Angle().y
                for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                    local dir = Angle(0, yaw + off, 0):Forward()
                    local p = CAI.Nav.RandomPointNear(npc:GetPos() + dir * 800, 400)
                    if not p then p = CAI.Nav.SafeOffset(npc:GetPos(), dir, 600) end
                    if p and safeRetreat(data, p, nearPos, curD) then
                        if not exposedToEnemies(data, p) then unseen = unseen or p break end
                        fallback = fallback or p
                    end
                end
            end
            local dest = unseen or fallback
            if dest then
                data.retreatDest = dest
                CAI.Nav.MoveTo(data, dest, "run")
            end
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

end

