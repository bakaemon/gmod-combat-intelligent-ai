local BR = CAI.Brain

BR.RegisterHook("brain/ooda/pretarget", "all_flank_protect", function(ctx)
    if ctx.phase then return end
    local data, npc = ctx.data, ctx.npc
    if not data.flank then return end
    local _, rec = CAI.Memory.FreshestEnemy(data)
    if not rec then return end
    if data.scatterUntil and CurTime() < data.scatterUntil then return end

    if not data.flankHoldUntil or CurTime() > data.flankHoldUntil then
        local morale = data.morale or 100
        local supp = data.suppression or 0
        local bt = CAI.Config.Morale.BreakThreshold or 25
        local panicked = supp >= (CAI.Config.Suppression.PanicAt or 85)
        local broken = CAI.CVBool("cai_morale") and morale < bt
        local breakChance = 0
        if panicked then breakChance = breakChance + 0.4 end
        if broken then breakChance = breakChance + 0.5 end
        if data.role == CAI.ROLE.FLANKER then breakChance = breakChance * 0.2 end
        data.flankBreak = math.random() < breakChance
        data.flankHoldUntil = CurTime() + 1.5
    end

    if data.flankBreak then
        data.flank = nil
        return
    end
    ctx.phase = CAI.PHASE.MANEUVER
    ctx.intent = "flank"
    ctx.duration = 1.5
    ctx.reason = "flank_in_progress"
end)