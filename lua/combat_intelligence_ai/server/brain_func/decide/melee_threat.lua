local BR = CAI.Brain

table.insert(BR.COA.PreTarget, function(ctx)
    local data, npc = ctx.data, ctx.npc
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
                return CAI.PHASE.WITHDRAW, "flee", 3, "escape_encirclement"
            end
            return CAI.PHASE.ENGAGE, "point_blank", 2, "point_blank_fight"
        end
    end
end)
