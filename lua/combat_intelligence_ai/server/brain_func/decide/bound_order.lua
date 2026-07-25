local BR = CAI.Brain

table.insert(BR.COA.SquadOrder, function(ctx)
    if ctx.data.wantBound and ctx.data.boundTarget then
        ctx.data.wantBound = nil
        return CAI.PHASE.MANEUVER, "bound", 3, "squad_bound_order"
    end
end)
