local BR = CAI.Brain

local function shotgunPush(ctx)
    local data, npc, now = ctx.data, ctx.npc, ctx.now
    if ctx.dist <= ctx.ideal then return false end
    if now - (data.pressAt or 0) <= 3 then return false end
    data.pressAt = now
    data.combatMoveAt = now
    if ctx.tryMoveShoot() then return true, true end
    local dir = ctx.enemy:GetPos() - npc:GetPos()
    dir.z = 0 dir:Normalize()
    dir = CAI.SpatialMap.BiasedDir(data.squad, npc:GetPos(), dir)
    local dest = CAI.Nav.SafeGround(ctx.enemy:GetPos() - dir * ctx.ideal * 0.6)
    if dest and ctx.safeDest(dest) then CAI.Nav.MoveTo(data, dest, "run") end
    return true
end

BR.Exec.Engage.Ranged.Override("push", shotgunPush)

BR.RegisterHook("brain/exec/engage", "shotgun", function(data)
    BR.Exec.Engage.Ranged.Run(data)
end)