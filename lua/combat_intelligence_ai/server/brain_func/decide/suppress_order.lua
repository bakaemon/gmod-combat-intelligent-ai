local BR = CAI.Brain

table.insert(BR.COA.SquadOrder, function(ctx)
    if not IsValid(ctx.enemy) then return end
    if ctx.visible then return end
    if ctx.data.squad and #ctx.data.squad.members > 1
       and ctx.data.role ~= CAI.ROLE.SUPPRESSOR then return end
    if ctx.data.suppressUntil and CurTime() < ctx.data.suppressUntil then
        return CAI.PHASE.ENGAGE, "suppress", 3, "squad_suppress_order"
    end
end)
