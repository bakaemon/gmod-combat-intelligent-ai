local BR = CAI.Brain

-- FLANK: delegate to CAI.Flank. Move along a covered route to attack the
-- enemy from the side, resume ENGAGE when the flank completes.
BR.Exec[4] = function(data)
    local npc = data.ent
    local enemy, rec = CAI.Memory.FreshestEnemy(data)
    -- Contact is inevitable: the enemy (or another one) is close enough that a
    -- silent flank is pointless, so open fire and run-and-gun instead.
    if IsValid(enemy) then
        local contact = npc:GetPos():Distance(enemy:GetPos()) < CAI.Config.Flank.FireDist
        if not contact then
            local fireDistSq = CAI.Config.Flank.FireDist ^ 2
            for e in pairs(data.memory.enemies) do
                if IsValid(e) and e ~= enemy
                   and npc:GetPos():DistToSqr(e:GetPos()) < fireDistSq then
                    contact = true break
                end
            end
        end
        if contact then
            data.flank = nil
            if npc.SetEnemy then npc:SetEnemy(enemy) end
            BR.SetState(data, CAI.STATE.ENGAGE, "flank_contact")
            return
        end
    end
    if not data.flank then
        if not rec or not CAI.Flank.Begin(data, rec.pos) then
            BR.SetState(data, CAI.STATE.COVER, "flank_unavailable")
            return
        end
    end
    if not CAI.Flank.Update(data) then
        if IsValid(enemy) and npc.SetEnemy then npc:SetEnemy(enemy) end
        data.lastFlankAt = CurTime()
        BR.SetState(data, CAI.STATE.ENGAGE, "flank_complete")
    end
end


