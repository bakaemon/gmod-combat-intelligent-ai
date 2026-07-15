local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action (visible): a squad bounding-overwatch order.
table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    if ctx.data.wantBound and ctx.data.boundTarget then
        ctx.data.wantBound = nil
        return CAI.STATE.BOUNDED, "squad_bound_order"
    end
end)
