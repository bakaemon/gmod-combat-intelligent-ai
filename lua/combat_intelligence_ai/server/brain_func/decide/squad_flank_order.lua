local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action (visible): a squad flank order.
table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    if ctx.data.wantFlank then
        ctx.data.wantFlank = nil
        return CAI.STATE.FLANK, "squad_flank_order"
    end
end)
