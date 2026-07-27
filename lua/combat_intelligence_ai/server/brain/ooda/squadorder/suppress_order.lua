local function handler(ctx)
    if ctx.phase then return end
    local data = ctx.data
    if not IsValid(ctx.enemy) then return end
    if ctx.visible then return end
    if data.squad and #data.squad.members > 1 and data.role ~= CAI.ROLE.SUPPRESSOR then return end
    if data.suppressUntil and CurTime() < data.suppressUntil then
        ctx.phase = CAI.PHASE.ENGAGE
        ctx.intent = "suppress"
        ctx.duration = 3
        ctx.reason = "squad_suppress_order"
    end
end
BR.RegisterHook("brain/ooda/squadorder", "all_suppress_order", handler)