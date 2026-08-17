local function handler(ctx)
    if ctx.phase then return end
    local data, npc = ctx.data, ctx.npc
    if not data.squad or not IsValid(data.squad.leader) then return end
    if data.squad.leader == npc or data.role == CAI.ROLE.FLANKER then return end
    local radius = CAI.Config.SquadTactics.FormationBreakRadius or 600
    if npc:GetPos():DistToSqr(data.squad.leader:GetPos()) <= radius * radius then return end
    local enemyRange = ctx.enemy and npc:GetPos():Distance(ctx.enemy:GetPos()) or math.huge
    if enemyRange <= CAI.WeaponIntel.OwnRange(npc) then return end
    ctx.phase = CAI.PHASE.WITHDRAW
    ctx.intent = "regroup"
    ctx.duration = 4
    ctx.reason = "separated_from_squad"
end
BR.RegisterHook("brain/ooda/squadorder", "all_separated", handler)