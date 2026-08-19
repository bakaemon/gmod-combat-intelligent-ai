local BR = CAI.Brain

BR.RegisterHook("brain/ooda/target", "all_pre_contact_coa", function(ctx)
    if ctx.phase then return end
    if IsValid(ctx.enemy) then return end
    ctx.phase = CAI.PHASE.PRE_CONTACT
    ctx.intent = "patrol"
    ctx.duration = 5
    ctx.reason = "all_quiet"
end)