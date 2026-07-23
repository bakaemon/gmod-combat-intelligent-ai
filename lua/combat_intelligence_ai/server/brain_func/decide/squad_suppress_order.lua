local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action (visible): a squad suppress order. The lost-target variant
-- lives in lost_target.lua.
table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    if ctx.data.suppressUntil and CurTime() < ctx.data.suppressUntil then
        return CAI.STATE.SUPPRESS, "squad_suppress_order"
    end
end)
