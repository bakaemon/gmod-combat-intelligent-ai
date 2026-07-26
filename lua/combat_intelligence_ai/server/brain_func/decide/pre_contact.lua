local BR = CAI.Brain

table.insert(BR.COA.Target, function(ctx)
    return CAI.PHASE.PRE_CONTACT, "patrol", 5, "all_quiet"
end)
