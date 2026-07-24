local BR = CAI.Brain

table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    if ctx.data.squad and IsValid(ctx.data.squad.leader) and ctx.data.squad.leader ~= ctx.npc
       and ctx.data.role ~= CAI.ROLE.FLANKER
       and ctx.npc:GetPos():DistToSqr(ctx.data.squad.leader:GetPos()) > 700 * 700
       and ctx.npc:GetPos():Distance(ctx.enemy:GetPos()) > CAI.WeaponIntel.OwnRange(ctx.npc) then
        return CAI.PHASE.WITHDRAW, "regroup", 4, "separated_from_squad"
    end
end)
