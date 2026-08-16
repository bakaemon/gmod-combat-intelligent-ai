local BR = CAI.Brain

BR.RegisterHook("brain/ooda/target", "all_pinned", function(ctx)
    if ctx.phase then return end
    if not ctx.visible then return end
    if ctx.data.flank then return end
    local data = ctx.data

    if CAI.Suppression.IsPinned(data) then
        local coverPos = CAI.Cover.FindBest(data, ctx.enemy,
            (ctx.rec and ctx.rec.pos) or (IsValid(ctx.enemy) and ctx.enemy:GetPos()))
        if coverPos then
            local passive = CAI.PhaseIs(data, CAI.PHASE.PRE_CONTACT)
                or CAI.PhaseIs(data, CAI.PHASE.COVER)
            if passive then
                ctx.phase = CAI.PHASE.COVER
                ctx.intent = "hold"
                ctx.duration = 2.5
                ctx.reason = "pinned_by_fire"
                return
            end
            local now = CurTime()
            if not data.pinnedCoverUntil or now > data.pinnedCoverUntil then
                local agg = CAI.WeaponIntel.EffectiveAggression(data)
                local center = CAI.Config.Suppression.FightOpenAggro or 0.5
                local spread = CAI.Config.Suppression.FightOpenSpread or 0.25
                local pCover = 1 / (1 + math.exp((agg - center) / spread))
                data.pinnedCover = math.random() < pCover
                data.pinnedCoverUntil = now + math.Rand(4, 7)
            end
            if data.pinnedCover then
                ctx.phase = CAI.PHASE.COVER
                ctx.intent = "hold"
                ctx.duration = 2.5
                ctx.reason = "pinned_by_fire"
                return
            end
        else
            local now = CurTime()
            if not data.pinnedFleeUntil or now > data.pinnedFleeUntil then
                local agg = CAI.WeaponIntel.EffectiveAggression(data)
                local center = CAI.Config.Suppression.FightOpenAggro or 0.5
                local spread = CAI.Config.Suppression.FightOpenSpread or 0.25
                local pRetreat = 1 / (1 + math.exp((agg - center) / spread))
                data.pinnedFlee = math.random() < pRetreat
                data.pinnedFleeUntil = now + math.Rand(4, 7)
            end
            if data.pinnedFlee then
                ctx.phase = CAI.PHASE.WITHDRAW
                ctx.intent = "tactical"
                ctx.duration = 3
                ctx.reason = "pinned_no_cover"
            end
        end
    end
end)