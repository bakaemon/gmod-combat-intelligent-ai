local BR = CAI.Brain

table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    if ctx.data.wantFlank then
        ctx.data.wantFlank = nil
        return CAI.PHASE.MANEUVER, "flank", 4, "squad_flank_order"
    end
end)
