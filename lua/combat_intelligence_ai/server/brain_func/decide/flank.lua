local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action (visible): continue an in-progress flank. The lost-target
-- variant lives in lost_target.lua.
table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    if ctx.data.flank then
        -- Keep the flank alive until the executor ends it on its own terms
        -- (contact < FireDist, arrival, or timeout). Dropping it at a fixed
        -- distance here just handed the NPC to ENGAGE the moment it closed in.
        return CAI.STATE.FLANK, "flank_in_progress"
    end
end)
