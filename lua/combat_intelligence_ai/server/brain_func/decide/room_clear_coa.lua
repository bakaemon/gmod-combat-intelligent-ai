local BR = CAI.Brain

table.insert(BR.COA.PreTarget, function(ctx)
    local data = ctx.data
    if data.squad and data.squad.clearingDoor and not data.squad.clearingDoor.done then
        return CAI.PHASE.MANEUVER, "room_clear", 4, "clearing_doorway"
    end
end)
