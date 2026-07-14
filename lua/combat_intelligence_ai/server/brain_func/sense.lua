local BR = CAI.Brain

-- CombatTarget: resolve who this NPC is currently fighting. Priority:
-- engine enemy (with a brief post-visibility grace) > stored combatTarget >
-- freshest remembered enemy. Returns (enemyEnt, rec).
function BR.CombatTarget(data)
    local npc = data.ent

    local ee = npc.GetEnemy and npc:GetEnemy()
    if IsValid(ee) and CAI.Util.IsTargetable(ee) and ee:GetClass() ~= "npc_bullseye" then
        local vis = CAI.Util.CanSee(npc, ee)
        if not vis and data.lastVisEnemy == ee
           and CurTime() - (data.lastVisAt or 0) < CAI.Config.LastVisGrace then
            vis = true
        end
        if vis then
            local rec = data.memory.enemies[ee]
                or { pos = ee:GetPos(), t = CurTime(), heardOnly = false }
            return ee, rec
        end
    end

    local ct = data.combatTarget
    if IsValid(ct) and CAI.Util.Alive(ct) and CAI.Util.IsTargetable(ct)
       and data.combatRec then
        return ct, data.combatRec
    end

    return CAI.Memory.FreshestEnemy(data)
end

-- MeleeThreatScan: count nearby melee/close-combat threats and compute their
-- centroid, used to detect being swarmed / encircled.
BR.MeleeThreatScan = function(data)
    local npc = data.ent
    local cfg = CAI.Config.Escape
    local origin = npc:GetPos()
    local radSqr = cfg.SurroundRadius * cfg.SurroundRadius
    local count, nearest, nearestSqr = 0, nil, math.huge
    local sum, contrib = Vector(0, 0, 0), 0
    for ent, _ in pairs(data.memory.enemies) do
        if IsValid(ent) and CAI.Util.Alive(ent) and CAI.Util.IsTargetable(ent)
           and CAI.WeaponIntel.IsMeleeThreat(ent) then
            local dSqr = origin:DistToSqr(ent:GetPos())
            if dSqr < radSqr then
                count = count + 1
                sum = sum + ent:GetPos()
                contrib = contrib + 1
                if dSqr < nearestSqr then nearest, nearestSqr = ent, dSqr end
            end
        end
    end
    local centroid = contrib > 0 and (sum / contrib) or nil
    return count, nearest, math.sqrt(nearestSqr), centroid
end
