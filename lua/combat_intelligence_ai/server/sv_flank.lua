CAI.Flank = CAI.Flank or {}
local F = CAI.Flank

function F.ComputeRoute(data, enemyPos)
    local npc = data.ent
    local toEnemy = enemyPos - npc:GetPos()
    toEnemy.z = 0
    local dist = toEnemy:Length()
    if dist < 200 then return nil end
    toEnemy:Normalize()

    local right = Vector(-toEnemy.y, toEnemy.x, 0)
    local side = math.random() < 0.5 and 1 or -1

    for attempt = 1, 2 do
        local wing = right * side * math.Clamp(dist * 0.8, 400, 1200)
        local mid = npc:GetPos() + toEnemy * (dist * 0.5) + wing

        local waypoint
        local area = navmesh.GetNearestNavArea(mid, false, 400, false, true)
        if IsValid(area) then
            waypoint = area:GetClosestPointOnArea(mid)
        elseif navmesh.GetNavAreaCount() == 0 then
            local tr = util.TraceLine({
                start = mid + Vector(0, 0, 64),
                endpos = mid - Vector(0, 0, 220),
                mask = MASK_SOLID_BRUSHONLY,
            })
            if tr.Hit and not CAI.Nav.IsDeepWater(tr.HitPos) then waypoint = tr.HitPos + Vector(0, 0, 4) end
        end
        if waypoint then

            local hiddenBonus = true
            for enemy in pairs(data.memory.enemies) do
                if IsValid(enemy) and CAI.Util.CanSeePos(enemy, waypoint) then
                    hiddenBonus = false
                    break
                end
            end
            if hiddenBonus or attempt == 2 then

                local atkTry = enemyPos + right * side * 350
                local atkArea = navmesh.GetNearestNavArea(atkTry, false, 400, false, true)
                local attackPos = IsValid(atkArea) and atkArea:GetClosestPointOnArea(atkTry)
                                  or (navmesh.GetNavAreaCount() == 0 and atkTry)
                                  or enemyPos
                local atkExposed = false
                for enemy in pairs(data.memory.enemies) do
                    if IsValid(enemy) and CAI.Util.CanSeePos(enemy, attackPos) then
                        atkExposed = true break
                    end
                end
                if atkExposed then
                    local altTry = enemyPos + right * (-side) * 350
                    local altArea = navmesh.GetNearestNavArea(altTry, false, 400, false, true)
                    local altPos = IsValid(altArea) and altArea:GetClosestPointOnArea(altTry) or altTry
                    local altExposed = false
                    for enemy in pairs(data.memory.enemies) do
                        if IsValid(enemy) and CAI.Util.CanSeePos(enemy, altPos) then
                            altExposed = true break
                        end
                    end
                    if not altExposed then
                        attackPos = altPos
                    else
                        local coverSpot = CAI.Cover.FindBest(data, nil, attackPos)
                        if coverSpot then attackPos = coverSpot end
                    end
                end
                return waypoint, attackPos
            end
        end
        side = -side
    end
    return nil
end

function F.Begin(data, enemyPos)
    local waypoint, attackPos = F.ComputeRoute(data, enemyPos)
    if not waypoint then return false end
    data.flank = { waypoint = waypoint, attackPos = attackPos, stage = 1, started = CurTime() }
    CAI.Nav.MoveTo(data, waypoint, "run")
    CAI.Voice.Speak(data, "flanking")
    if data.squad then CAI.Squad.Broadcast(data.squad, "flanking", data.ent, { pos = enemyPos }) end
    return true
end

function F.Update(data)
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
