local function handler(ctx)
    if ctx.phase then return end
    if ctx.data.wantFlank then
        ctx.data.wantFlank = nil
        ctx.phase = CAI.PHASE.MANEUVER
        ctx.intent = "flank"
        ctx.duration = 4
        ctx.reason = "squad_flank_order"
    end
end
BR.RegisterHook("brain/ooda/squadorder", "all_flank_order", handler)