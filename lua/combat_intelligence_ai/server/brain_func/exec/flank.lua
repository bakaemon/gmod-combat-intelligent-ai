local BR = CAI.Brain

-- FLANK route: move to the enemy's SIDE (a crossfire angle), not up to its
-- front. This is an in-the-dark maneuver: we only know the enemy's last known
-- position (rec.pos), so routing and all "hiddenness" preferences use rec.pos
-- exclusively -- never the live enemy. Hiddenness is a SOFT preference, not a
-- gate (a flank does not require a hidden approach).

local function ComputeRoute(data, enemyPos)
    local npc = data.ent
    local npcPos = npc:GetPos()
    local toEnemy = enemyPos - npcPos
    toEnemy.z = 0
    local dist = toEnemy:Length()
    if dist < 200 then return nil end
    toEnemy:Normalize()

    local right = Vector(-toEnemy.y, toEnemy.x, 0)

    local cfg = CAI.Config.Flank

    -- Snap a candidate to the nav mesh (or a ground trace), rejecting points that
    -- land further than maxSnap from the intended offset so routing stays in-space
    -- instead of collapsing onto cover next to the NPC.
    local function navPt(off, maxSnap)
        local snapSq = maxSnap * maxSnap
        local area = navmesh.GetNearestNavArea(off, false, 400, false, true)
        if IsValid(area) then
            local p = area:GetClosestPointOnArea(off)
            if p and not CAI.Nav.IsDeepWater(p) and p:DistToSqr(off) <= snapSq then return p end
            return nil
        end
        if navmesh.GetNavAreaCount() == 0 then
            local tr = util.TraceLine({
                start = off + Vector(0, 0, 64),
                endpos = off - Vector(0, 0, 220),
                mask = MASK_SOLID_BRUSHONLY,
            })
            if tr.Hit and not CAI.Nav.IsDeepWater(tr.HitPos) then
                local p = tr.HitPos + Vector(0, 0, 4)
                if p:DistToSqr(off) <= snapSq then return p end
            end
        end
        return nil
    end

    -- In-the-dark occlusion: can the enemy (as last known at rec.pos) see pos?
    -- Used only as a soft score, never to reject a route.
    local function occluded(pos)
        if not pos then return false end
        local tr = util.TraceLine({
            start = enemyPos + Vector(0, 0, 40),
            endpos = pos + Vector(0, 0, 40),
            mask = MASK_BLOCKLOS,
        })
        return tr.Hit
    end
    local function hidden(pos) return not pos or occluded(pos) end

    local function legDry(a, b)
        for t = 0.25, 0.75, 0.25 do
            if CAI.Nav.IsDeepWater(Lerp(t, a, b)) then return false end
        end
        return true
    end

    -- Try one side: the attack point sits FlankOffset to one side of rec.pos, and
    -- the waypoint bows that way too, so the NPC reaches the enemy's flank.
    local function trySide(side)
        local atk = navPt(enemyPos + right * (side * cfg.FlankOffset), cfg.MaxSnap)
        if not atk then return nil end
        local fwd = math.min(dist * cfg.WaypointFrac, cfg.ForwardCap)
        local bow = math.min(cfg.BowOffset, cfg.MaxBow)
        local wp = navPt(npcPos + toEnemy * fwd + right * (side * bow), cfg.MaxSnap)
        if not wp then return nil end
        if wp:DistToSqr(npcPos) > (cfg.WaypointMax * cfg.WaypointMax) then return nil end
        if not legDry(npcPos, wp) or not legDry(wp, atk) then return nil end
        local score = (hidden(atk) and 1 or 0) + (hidden(wp) and 0.5 or 0)
        return { wp = wp, atk = atk, score = score }
    end

    local best, bestScore = nil, -1
    for _, side in ipairs({ 1, -1 }) do
        local r = trySide(side)
        if r and r.score > bestScore then best, bestScore = r, r.score end
    end
    if best then return best.wp, best.atk end
    return nil
end

local function Begin(data, enemyPos)
    local waypoint, attackPos = ComputeRoute(data, enemyPos)
    if not waypoint then return false end
    data.flank = { waypoint = waypoint, attackPos = attackPos, stage = 1, started = CurTime() }
    CAI.Nav.MoveTo(data, waypoint, "run")
    CAI.Voice.Speak(data, "flanking")
    if data.squad then CAI.Squad.Broadcast(data.squad, "flanking", data.ent, { pos = enemyPos }) end
    return true
end

local function Update(data)
    local fl = data.flank
    if not fl then return false end
    if CurTime() - fl.started > 25 then data.flank = nil return false end

    if fl.stage == 1 then
        if CAI.Nav.Arrived(data, 90) then
            fl.stage = 2
            CAI.Nav.MoveTo(data, fl.attackPos, "run")
        end
    elseif fl.stage == 2 then
        if CAI.Nav.Arrived(data, 120) then
            data.flank = nil
            return false
        end
    end
    return true
end

-- FLANK: move along a covered route to attack the enemy from the side, resume
-- ENGAGE when the flank completes.
BR.Exec[4] = function(data)
    local npc = data.ent
    local enemy, rec = CAI.Memory.FreshestEnemy(data)
    -- Contact is inevitable: the enemy (or another one) is close enough that a
    -- silent flank is pointless, so open fire and run-and-gun instead.
    if IsValid(enemy) then
        local contact = npc:GetPos():Distance(enemy:GetPos()) < CAI.Config.Flank.FireDist
        if not contact then
            local fireDistSq = CAI.Config.Flank.FireDist ^ 2
            for e in pairs(data.memory.enemies) do
                if IsValid(e) and e ~= enemy
                   and npc:GetPos():DistToSqr(e:GetPos()) < fireDistSq then
                    contact = true break
                end
            end
        end
        if contact then
            data.flank = nil
            if npc.SetEnemy then npc:SetEnemy(enemy) end
            BR.SetState(data, CAI.STATE.ENGAGE, "flank_contact")
            return
        end
    end
    if not data.flank then
        local why = "flank_unavailable"
        if rec and (CurTime() - rec.t) > CAI.Config.Flank.FreshWindow then
            why = "flank_stale"
        end
        if not rec or why == "flank_stale" or not Begin(data, rec.pos) then
            BR.SetState(data, CAI.STATE.COVER, why)
            return
        end
    end
    if not Update(data) then
        data.lastFlankAt = CurTime()
        if IsValid(enemy) then
            -- Enemy reacquired live on arrival: open fire.
            if npc.SetEnemy then npc:SetEnemy(enemy) end
            BR.SetState(data, CAI.STATE.ENGAGE, "flank_complete")
        else
            -- Arrived at the flank point but the enemy is not here: search the
            -- last known position rather than declaring a bogus "flank_complete".
            if not CAI.Search.Begin(data, enemy, rec and rec.pos) then
                BR.SetState(data, CAI.STATE.COVER, "flank_arrived_nosearch")
            else
                BR.SetState(data, CAI.STATE.SEARCH, "flank_arrived")
            end
        end
    end
end
