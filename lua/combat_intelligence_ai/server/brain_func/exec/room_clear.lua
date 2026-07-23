local BR = CAI.Brain

-- ROOM_CLEAR: squad doorway clearing, approach, "slice" the doorway by
-- rotating the view across it to scan for targets, then enter from the corner.
BR.Exec[10] = function(data)
    local npc = data.ent
    local squad = data.squad
    if not squad or not squad.clearingDoor then
        BR.SetState(data, CAI.STATE.PATROL, "no_door_to_clear")
        return
    end
    local door = squad.clearingDoor
    if not data.clearPhase then
        data.clearPhase = "approach"
        data.clearAngle = 0
        data.clearSliceStart = nil
        local doorDir = (door.pos - npc:GetPos()):GetNormalized()
        doorDir.z = 0
        local approachPos = door.pos - door.normal * 60
        local safeApproach = CAI.Nav.SafeGround(approachPos) or approachPos
        CAI.Nav.MoveTo(data, safeApproach, "run")
    end
    if data.clearPhase == "approach" then
        if CAI.Nav.Arrived(data, 80) then
            data.clearPhase = "slice"
            data.clearSliceStart = CurTime()
            data.clearAngle = -CAI.Config.SquadTactics.ClearSliceMax
            data.moveTarget = nil
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
            door.done = true
            BR.SetState(data, CAI.STATE.ENGAGE, "enemy_in_room")
            return
        end
        -- Slice: rotate the view across the doorway in fixed increments to
        -- scan for targets before committing to entry.
        data.clearAngle = sliceAngle + cfg.ClearSliceAngle
        if data.clearAngle > cfg.ClearSliceMax then
            data.clearPhase = "entry"
            local entryDest = door.pos + door.normal * 150
            local farCorner = entryDest + Vector(-door.normal.y, door.normal.x, 0) * 100
            local safeEntry = CAI.Nav.SafeGround(farCorner) or CAI.Nav.SafeGround(entryDest) or entryDest
            CAI.Nav.MoveTo(data, safeEntry, "run")
        end
        if CurTime() - (data.clearSliceStart or 0) > 8 then
            data.clearPhase = nil
            door.done = true
            BR.SetState(data, CAI.STATE.PATROL, "clear_timeout")
        end
        return
    end
    if data.clearPhase == "entry" then
        if CAI.Nav.Arrived(data, 80) then
            data.clearPhase = nil
            door.done = true
            CAI.Voice.Speak(data, "clear")
            if data.squad then
                CAI.Squad.Broadcast(data.squad, "clear", data.ent)
            end
            BR.SetState(data, CAI.STATE.PATROL, "room_cleared")
        end
        return
    end
    data.clearPhase = nil
    door.done = true
    BR.SetState(data, CAI.STATE.PATROL, "clear_error")
end

