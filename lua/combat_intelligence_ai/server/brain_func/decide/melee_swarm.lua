local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: swarm / melee-encirclement. If crowded, point-blank, or
-- recently melee-hit, fight back (point-blank) or flee rather than standing still.
table.insert(BR.COA.PreTarget, function(data, npc)
    local ownWep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if IsValid(ownWep) and not CAI.WeaponIntel.IsMelee(npc) then
        local ecfg = CAI.Config.Escape
        local count, nearest, nearDist, centroid = BR.MeleeThreatScan(data)
        local recentHit = CurTime() - (data.lastMeleeHurtAt or 0) < ecfg.MeleeHitGrace
        if nearDist < ecfg.PointBlank or count >= ecfg.SurroundCount or recentHit then
            data.escapeCentroid = centroid or (IsValid(nearest) and nearest:GetPos())
            data.pbEnemy = nearest
            local clipEmpty = ownWep.Clip1 and ownWep:Clip1() == 0
            if clipEmpty or CAI.Morale.RecentMeleeHits(data) >= ecfg.OverwhelmHits then
                return CAI.STATE.RETREAT, "escape_encirclement"
            end
            return CAI.STATE.ENGAGE, "point_blank_fight"
        end
    end
end)
