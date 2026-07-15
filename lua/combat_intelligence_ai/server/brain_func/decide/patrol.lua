local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: nothing else applies; fall back to patrolling. (decide.lua
-- also keeps a hard PATROL fallback as a safety net.)
table.insert(BR.COA.Target, function(ctx)
    return CAI.STATE.PATROL, "all_quiet"
end)
