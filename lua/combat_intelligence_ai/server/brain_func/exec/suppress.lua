local BR = CAI.Brain

-- SUPPRESS: lay down fire on the enemy's last-known position to keep their
-- head down, even without line of sight (via an invisible npc_bullseye proxy).
BR.Exec[5] = function(data)
    local npc = data.ent
    local enemy, rec = BR.CombatTarget(data)
    if not rec then
        BR.StopSuppressing(data)
        data.suppNoLosAt = nil
        BR.SetState(data, CAI.STATE.COVER, "nothing_to_suppress")
        return
    end

    if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < 200 * 200 then
        BR.StopSuppressing(data)
        data.suppNoLosAt = nil
        if npc.SetEnemy then npc:SetEnemy(enemy) end
        BR.SetState(data, CAI.STATE.ENGAGE, "too_close_suppress")
        return
    end

    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc then
        local canFight = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
        if not canFight and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 900 * 900 then
            BR.StopSuppressing(data)
            data.suppNoLosAt = nil
            if npc.SetEnemy then npc:SetEnemy(NULL) end
            CAI.Nav.MoveTo(data, data.squad.leader:GetPos(), "run")
            return
        end
        data.moveTarget = nil
        data.moveIssuedAt = nil
    end

    local now = CurTime()
    if IsValid(enemy) and CAI.Util.Sees(npc, enemy) then
        BR.StopSuppressing(data)
        data.suppNoLosAt = now
        if npc.SetEnemy then npc:SetEnemy(enemy) end
        if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(enemy, rec.pos) end
    else
        if not data.suppNoLosAt then data.suppNoLosAt = now end
        if now - data.suppNoLosAt > 8 then
            BR.StopSuppressing(data)
            data.suppressUntil = nil
            data.suppNoLosAt = nil
            CAI.Memory.SeeEnemy(data, enemy, rec.pos)
            BR.SetState(data, CAI.STATE.SEARCH, "suppress_no_los")
            return
        end
        local aim
        for _, b in ipairs(CAI.Cover.Barrels()) do
            if IsValid(b) and b:GetPos():DistToSqr(rec.pos) < 170 * 170
               and CAI.Util.CanSeePos(npc, b:GetPos() + Vector(0, 0, 10)) then
                aim = b:GetPos() + Vector(0, 0, 10)
                break
            end
        end
        for _, h in ipairs({ 55, 90 }) do
            if aim then break end
            local p = rec.pos + Vector(0, 0, h)
            if CAI.Util.CanSeePos(npc, p) then aim = p break end
        end
        if not aim and CAI.CVBool("cai_wallbang") then
            aim = rec.pos + Vector(0, 0, 55)
        end
        if not aim then
            aim = rec.pos + Vector(0, 0, 40)
        end
        -- No line of sight: spawn/aim an invisible npc_bullseye at the
        -- last-known position so the NPC keeps suppressing through it
        -- (and through walls when cai_wallbang is on).
        if aim then
            local bull = data.suppBullseye
            if not IsValid(bull) then
                bull = ents.Create("npc_bullseye")
                if IsValid(bull) then
                    bull:SetPos(aim)
                    bull:SetKeyValue("spawnflags", "196608")
                    bull:Spawn()
                    bull:SetNoDraw(true)
                    bull:SetSolid(SOLID_NONE)
                    bull:SetHealth(999999)
                    data.suppBullseye = bull
                    npc:AddEntityRelationship(bull, D_HT, 99)
                end
            else
                bull:SetPos(aim)
            end
            if IsValid(bull) and npc.SetEnemy then
                npc:SetEnemy(bull)
                if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(bull, aim) end
            end
        else
            if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < 400 * 400 then
                BR.StopSuppressing(data)
                if npc.SetEnemy then npc:SetEnemy(enemy) end
                BR.SetState(data, CAI.STATE.ENGAGE, "suppressed_no_target")
                return
            end
        end
    end

    if not data.suppFaced then
        data.suppFaced = true
        npc:SetSchedule(SCHED_COMBAT_FACE)
    end
    if not data.saidSuppress then
        data.saidSuppress = true
        CAI.Voice.Speak(data, "suppressing")
        if data.squad then
            local sa = data.squad.blackboard.suppressedAt
            sa[#sa + 1] = { pos = rec.pos, t = CurTime() }
            if #sa > 6 then table.remove(sa, 1) end
            CAI.Squad.Broadcast(data.squad, "suppression_active", data.ent, { pos = rec.pos })
        end
    end
    if not data.suppressUntil or CurTime() > data.suppressUntil then
        data.saidSuppress = false
        data.suppNoLosAt = nil
        data.suppressUntil = nil
        BR.SetState(data, CAI.STATE.COVER, "suppress_done")
    end
end

