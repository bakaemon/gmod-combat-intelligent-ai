local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: keep an in-progress flank alive. A flank is conducted UNDER
-- FIRE by design, so a flanker must not break off just because it is being shot
-- at or its morale dipped a little. It only abandons the maneuver when genuinely
-- broken (morale < BreakThreshold) or panicking (suppression >= PanicAt). The
-- FLANKER role is the maneuver specialist and almost never breaks. The roll is
-- cached for a short window so the NPC does not flap between states every tick.
table.insert(BR.COA.PreTarget, function(data, npc)
    if not data.flank then return end
    -- Keep a flank alive only while we still have a last known enemy position.
    -- With no rec the flanker has nothing to flank toward, so let the cascade
    -- re-evaluate (it will fall to SEARCH/COVER) instead of force-holding FLANK.
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
        -- FLANKER: the maneuver specialist; commit hard.
        if data.role == CAI.ROLE.FLANKER then breakChance = breakChance * 0.2 end
        data.flankBreak = math.random() < breakChance
        if data.flankBreak and CAI.CVBool("cai_debug_transitions") then
            local role = CAI.ROLE_NAMES[data.role] or "?"
            local want = CAI.CVStr("cai_debug_role")
            if want == "" or want == role then
                local npc = data.ent
                local held = data.flank and data.flank.started and (CurTime() - data.flank.started) or 0
                local tdist = -1
                local fenemy = npc.GetEnemy and npc:GetEnemy()
                if IsValid(fenemy) then
                    tdist = math.Round(npc:GetPos():Distance(fenemy:GetPos()))
                else
                    local fe = CAI.Memory.FreshestEnemy(data)
                    if IsValid(fe) then tdist = math.Round(npc:GetPos():Distance(fe:GetPos())) end
                end
                print(CAI.PrintPrefix .. ("[flank] %s idx=%d  BREAK  mor=%d sup=%d chance=%.2f held=%.1fs td=%d")
                    :format(role, npc:EntIndex(),
                        math.Round(data.morale or 0), math.Round(data.suppression or 0),
                        breakChance, held, tdist))
            end
        end
        data.flankHoldUntil = CurTime() + 1.5
    end

    if data.flankBreak then
        data.flank = nil
        return
    end
    return CAI.STATE.FLANK, "flank_in_progress"
end)
