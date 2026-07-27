local BR = CAI.Brain

BR.RegisterHook("brain/ooda/pretarget", "all_room_clear_coa", function(ctx)
    if ctx.phase then return end
    local data = ctx.data
    if data.squad and data.squad.clearingDoor and not data.squad.clearingDoor.done then
        ctx.phase = CAI.PHASE.MANEUVER
        ctx.intent = "room_clear"
        ctx.duration = 4
        ctx.reason = "clearing_doorway"
    end
end)