local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action (visible): hold cover when pinned by fire, or duck to reload.
table.insert(BR.COA.Target, function(ctx)
    if not ctx.visible then return end
    -- A live flank owns the NPC's movement; never pull it into COVER.
    if ctx.data.flank then return end
    -- Pinned by fire: take COVER when one is available; with no cover, let the
    -- NPC's willingness to hold ground decide between breaking contact and
    -- returning fire from the open.
    if CAI.Suppression.IsPinned(ctx.data) then
        local d = ctx.data
        local coverPos = CAI.Cover.FindBest(d, ctx.enemy,
            (ctx.rec and ctx.rec.pos) or (IsValid(ctx.enemy) and ctx.enemy:GetPos()))
        if coverPos then
            -- Has cover: only commit to COVER from a passive state (nothing else
            -- to interrupt), when already ducking, or when disposition favours
            -- it. An active combat plan keeps running and the jink defends it.
            local passive = d.state == CAI.STATE.IDLE or d.state == CAI.STATE.PATROL
                or d.state == CAI.STATE.INVESTIGATE or d.state == CAI.STATE.SEARCH
                or d.state == CAI.STATE.COVER
            if passive then
                return CAI.STATE.COVER, "pinned_by_fire"
            end
            local now = CurTime()
            if not d.pinnedCoverUntil or now > d.pinnedCoverUntil then
                local agg = CAI.WeaponIntel.EffectiveAggression(d)
                local center = CAI.Config.Suppression.FightOpenAggro or 0.5
                local spread = CAI.Config.Suppression.FightOpenSpread or 0.25
                local pCover = 1 / (1 + math.exp((agg - center) / spread))
                d.pinnedCover = math.random() < pCover
                d.pinnedCoverUntil = now + math.Rand(4, 7)
            end
            if d.pinnedCover then
                return CAI.STATE.COVER, "pinned_by_fire"
            end
        else
            -- No cover: bias fight/retreat by how willing the NPC is to hold
            -- ground (EffectiveAggression) and commit to the roll for a few
            -- seconds so the outcome stays stable within an engagement.
            local now = CurTime()
            if not d.pinnedFleeUntil or now > d.pinnedFleeUntil then
                local agg = CAI.WeaponIntel.EffectiveAggression(d)
                local center = CAI.Config.Suppression.FightOpenAggro or 0.5
                local spread = CAI.Config.Suppression.FightOpenSpread or 0.25
                local pRetreat = 1 / (1 + math.exp((agg - center) / spread))
                d.pinnedFlee = math.random() < pRetreat
                d.pinnedFleeUntil = now + math.Rand(4, 7)
            end
            if d.pinnedFlee then
                return CAI.STATE.RETREAT, "pinned_no_cover"
            end
        end
        -- Otherwise continue the current plan (cascade picks flank/suppress/engage).
    end
    local ownWep = ctx.npc:GetActiveWeapon()
    if IsValid(ownWep) and ownWep.Clip1 and ownWep:Clip1() == 0 then
        return CAI.STATE.COVER, "reloading_cover"
    end
end)
