local BR = CAI.Brain

BR.RegisterHook("brain/ooda/pretarget", "all_melee_threat", function(ctx)
    if ctx.phase then return end
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
                ctx.phase = CAI.PHASE.WITHDRAW
                ctx.intent = "flee"
                ctx.duration = 3
                ctx.reason = "escape_encirclement"
                return
            end
            ctx.phase = CAI.PHASE.ENGAGE
            ctx.intent = "point_blank"
            ctx.duration = 2
            ctx.reason = "point_blank_fight"
        end
    end
end)