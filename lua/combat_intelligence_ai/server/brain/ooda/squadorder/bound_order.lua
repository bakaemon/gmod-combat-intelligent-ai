local function handler(ctx)
    if ctx.phase then return end
    if ctx.data.wantBound and ctx.data.boundTarget then
        ctx.data.wantBound = nil
        ctx.phase = CAI.PHASE.MANEUVER
        ctx.intent = "bound"
        ctx.duration = 3
        ctx.reason = "squad_bound_order"
    end
end
BR.RegisterHook("brain/ooda/squadorder", "all_bound_order", handler)