local BR = CAI.Brain

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

local function FlankBegin(data, enemyPos)
    local waypoint, attackPos = ComputeRoute(data, enemyPos)
    if not waypoint then return false end
    data.flank = { waypoint = waypoint, attackPos = attackPos, stage = 1, started = CurTime() }
    CAI.Nav.MoveTo(data, waypoint, "run", "flank")
    CAI.Voice.Speak(data, "flanking")
    if data.squad then CAI.Squad.Broadcast(data.squad, "flanking", data.ent, { pos = enemyPos }) end
    return true
end

local function FlankUpdate(data)
    local fl = data.flank
    if not fl then return false end
    if CurTime() - fl.started > 25 then data.flank = nil return false end
    if fl.stage == 1 then
        if not CAI.Nav.HasGoal(data) then
            CAI.Nav.MoveTo(data, fl.waypoint, "run", "flank")
        elseif CAI.Nav.Arrived(data, 90) then
            fl.stage = 2
            CAI.Nav.MoveTo(data, fl.attackPos, "run", "flank")
        else
            CAI.Nav.Claim(data, "flank")
        end
    elseif fl.stage == 2 then
        if not CAI.Nav.HasGoal(data) then
            CAI.Nav.MoveTo(data, fl.attackPos, "run", "flank")
        elseif CAI.Nav.Arrived(data, 120) then
            data.flank = nil
            return false
        else
            CAI.Nav.Claim(data, "flank")
        end
    end
    return true
end

BR.RegisterHook("brain/exec", "maneuver", function(data)
    local npc = data.ent

    if data.phaseIntent == "flank" then
        local enemy, rec = CAI.Memory.FreshestEnemy(data)
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
                data.planPending = "flank_contact"
                return
            end
        end
        if not data.flank then
            local why = "flank_unavailable"
            if rec and (CurTime() - rec.t) > CAI.Config.Flank.FreshWindow then
                why = "flank_stale"
            end
            if not rec or why == "flank_stale" or not FlankBegin(data, rec.pos) then
                data.planPending = why
                return
            end
        end
        if not FlankUpdate(data) then
            data.lastFlankAt = CurTime()
            if IsValid(enemy) then
                if npc.SetEnemy then npc:SetEnemy(enemy) end
                data.planPending = "flank_complete"
            elseif rec then
                if not CAI.Search.Begin(data, enemy, rec.pos) then
                    data.planPending = "flank_arrived_nosearch"
                else
                    data.planPending = "flank_arrived"
                end
            else
                data.planPending = "flank_arrived_nosearch"
            end
        end
        return
    end

    if data.phaseIntent == "bound" then
        if data.squad and not CAI.SquadFunc.FormationCheck(data) then
            data.boundTarget = nil
            data.boundArrived = nil
            data.planPending = "bound_too_far"
            return
        end
        if not data.boundTarget then
            data.planPending = "no_bound_target"
            return
        end
        if not data.boundArrived and not CAI.Nav.HasGoal(data) then
            CAI.Nav.MoveTo(data, data.boundTarget, "run", "bound")
        end
        local moving = CAI.Nav.HasGoal(data) and not CAI.Nav.Arrived(data, 70)
        if moving then
            CAI.Nav.Claim(data, "bound")
            CAI.FriendlyFire.Update(data)
            return
        end
        if not data.boundArrived then
            data.boundArrived = CurTime()
            data.fighting = nil
            CAI.Brain.FireSchedule(data)
        end
        local fireDuration = CAI.Config.SquadTactics.BoundFireDuration
        local cornerpush = CAI.CVBool("cai_cornerpush")
        if CurTime() - data.boundArrived > fireDuration then
            local confident = true
            if cornerpush then
                local ct = CAI.Config.SelfPreserve.CornerPush.ConfidenceTime
                confident = (CurTime() - data.boundArrived > ct)
                    and (CurTime() - (data.lastHurtAt or 0) > ct)
            end
            if confident then
                data.boundTarget = nil
                data.boundArrived = nil
                data.staggerOffset = nil
                data.planPending = "bound_complete"
            else
                data.boundArrived = CurTime()
                data.fighting = nil
                CAI.Brain.FireSchedule(data)
            end
        else
            if cornerpush and (CurTime() - (data.lastHurtAt or 0) < 0.5) then
                data.boundArrived = CurTime()
            end
            CAI.FriendlyFire.Update(data)
        end
        return
    end

    if data.phaseIntent == "room_clear" then
        local squad = data.squad
        if not squad or not squad.clearingDoor then
            data.planPending = "no_door_to_clear"
            return
        end
        local door = squad.clearingDoor
        if not data.clearPhase then
            data.clearPhase = "approach"
            data.clearAngle = 0
            data.clearSliceStart = nil
            data.clearPhaseAt = CurTime()
            local approachPos = door.pos - door.normal * 60
            local safeApproach = CAI.Nav.SafeGround(approachPos) or approachPos
            data.clearDest = safeApproach
            CAI.Nav.MoveTo(data, safeApproach, "run", "room_clear")
        end
        if data.clearPhase == "approach" then
            if CurTime() - (data.clearPhaseAt or 0) > 15 then
                data.clearPhase = nil
                data.clearDest = nil
                door.done = true
                data.planPending = "approach_timeout"
                return
            end
            if not CAI.Nav.HasGoal(data) and data.clearDest then
                CAI.Nav.MoveTo(data, data.clearDest, "run", "room_clear")
                return
            end
            CAI.Nav.Claim(data, "room_clear")
            if CAI.Nav.Arrived(data, 80) then
                data.clearPhase = "slice"
                data.clearPhaseAt = CurTime()
                data.clearSliceStart = CurTime()
                data.clearAngle = -CAI.Config.SquadTactics.ClearSliceMax
                data.clearDest = nil
                CAI.Nav.ClearGoal(data)
                npc:SetSchedule(SCHED_COMBAT_FACE)
            end
            return
        end
        if data.clearPhase == "slice" then
            local cfg = CAI.Config.SquadTactics
            local sliceAngle = data.clearAngle or 0
            local lookDir = door.normal:Angle()
            lookDir.y = lookDir.y + sliceAngle
            local lookFwd = lookDir:Forward()
            npc:SetAngles(lookDir)
            local checkPos = door.pos + lookFwd * 200 + Vector(0, 0, 40)
            local enemyDetected = false
            for e, _ in pairs(data.memory.enemies) do
                if IsValid(e) and CAI.Util.CanSeePos(npc, e:GetPos() + Vector(0, 0, 40)) then
                    enemyDetected = true
                    break
                end
            end
            if not enemyDetected then
                local tr = util.TraceLine({
                    start = npc:EyePos(),
                    endpos = checkPos,
                    filter = npc,
                    mask = MASK_BLOCKLOS,
                })
                if not tr.Hit then
                    local _, rec = CAI.Memory.FreshestEnemy(data)
                    if rec and checkPos:DistToSqr(rec.pos) < 300 * 300 then
                        enemyDetected = true
                    end
                end
            end
            if enemyDetected then
                data.clearPhase = nil
                data.clearDest = nil
                door.done = true
                data.planPending = "enemy_in_room"
                return
            end
            data.clearAngle = sliceAngle + cfg.ClearSliceAngle
            if data.clearAngle > cfg.ClearSliceMax then
                data.clearPhase = "entry"
                data.clearPhaseAt = CurTime()
                local entryDest = door.pos + door.normal * 150
                local farCorner = entryDest + Vector(-door.normal.y, door.normal.x, 0) * 100
                local safeEntry = CAI.Nav.SafeGround(farCorner) or CAI.Nav.SafeGround(entryDest) or entryDest
                data.clearDest = safeEntry
                CAI.Nav.MoveTo(data, safeEntry, "run", "room_clear")
            end
            if CurTime() - (data.clearSliceStart or 0) > 8 then
                data.clearPhase = nil
                data.clearDest = nil
                door.done = true
                data.planPending = "clear_timeout"
            end
            return
        end
        if data.clearPhase == "entry" then
            if CurTime() - (data.clearPhaseAt or 0) > 15 then
                data.clearPhase = nil
                data.clearDest = nil
                door.done = true
                data.planPending = "entry_timeout"
                return
            end
            if not CAI.Nav.HasGoal(data) and data.clearDest then
                CAI.Nav.MoveTo(data, data.clearDest, "run", "room_clear")
                return
            end
            CAI.Nav.Claim(data, "room_clear")
            if CAI.Nav.Arrived(data, 80) then
                data.clearPhase = nil
                data.clearDest = nil
                door.done = true
                CAI.Voice.Speak(data, "clear")
                if data.squad then
                    CAI.Squad.Broadcast(data.squad, "clear", data.ent)
                end
                data.planPending = "room_cleared"
            end
            return
        end
        data.clearPhase = nil
        data.clearDest = nil
        door.done = true
        data.planPending = "clear_error"
        return
    end

    if data.phaseIntent == "reposition" then
        if not CAI.Nav.HasGoal(data) then
            data.planPending = "reposition_done"
            return
        end
        if CAI.Nav.Arrived(data, 70) then
            data.planPending = "reposition_done"
            return
        end
        CAI.Nav.Claim(data, "reposition")
        CAI.FriendlyFire.Update(data)
    end
end)