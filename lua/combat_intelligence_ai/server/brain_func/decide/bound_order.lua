local BR = CAI.Brain

table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    if ctx.data.wantBound and ctx.data.boundTarget then
        ctx.data.wantBound = nil
        return CAI.PHASE.MANEUVER, "bound", 3, "squad_bound_order"
    end
end)
