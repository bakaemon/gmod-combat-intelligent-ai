local BR = CAI.Brain

-- SetState: transition helper. Only acts when the state actually changes, and
-- clears transient per-state fields so stale state never leaks across states.
function BR.SetState(data, newState, reason)
    if data.state == newState then
        if reason then data.lastDecision = reason end
        return
    end
    if CAI.CVBool("cai_debug_transitions") then
        local role = CAI.ROLE_NAMES[data.role] or "?"
        local want = CAI.CVStr("cai_debug_role")
        if want == "" or want == role then
            local npc = data.ent
            local dur = CurTime() - (data.stateSince or 0)
            local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
            local clip = (IsValid(wep) and wep.Clip1) and wep:Clip1() or -1
            local tdist = -1
            local fenemy = npc.GetEnemy and npc:GetEnemy()
            if IsValid(fenemy) then
                tdist = math.Round(npc:GetPos():Distance(fenemy:GetPos()))
            else
                local fe = CAI.Memory.FreshestEnemy(data)
                if IsValid(fe) then tdist = math.Round(npc:GetPos():Distance(fe:GetPos())) end
            end
            print(CAI.PrintPrefix .. ("[trans] %s idx=%d  %s(%.1fs) -> %s  reason=%s  td=%d | mor=%d sup=%d flank=%s brk=%s scat=%s clip=%d")
                :format(role, npc:EntIndex(),
                    CAI.STATE_NAMES[data.state] or data.state, dur,
                    CAI.STATE_NAMES[newState] or newState,
                    reason or "?", tdist,
                    math.Round(data.morale or 0), math.Round(data.suppression or 0),
                    data.flank and "Y" or "n", tostring(data.flankBreak),
                    data.scatterUntil and CurTime() < data.scatterUntil and "Y" or "n",
                    clip))
        end
    end
    data.prevState = data.state
    data.state = newState
    data.fighting = nil
    data.coverPhase = nil
    data.coverPhaseEnd = nil
    data.suppFaced = nil
    data.fleeSched = nil
    data.investFaced = nil
    data.retreatDest = nil
    data.ambush = nil
    data.meleePhase = nil
    data.stateSince = CurTime()
    if reason then data.lastDecision = reason end
    data.moveTarget = nil
    data.moveIssuedAt = nil
    data.patrolTarget = nil
    -- Drop a stale cover spot when leaving COVER so the Flinch layer can't read
    -- a far-away cover and wrongly decide we're already sheltered.
    if newState ~= CAI.STATE.COVER then
        data.cover = nil
    end
    if newState ~= CAI.STATE.PATROL then
        data.patrolAt = CurTime()
    end
end

BR.StopSuppressing = function(data)
    if IsValid(data.suppBullseye) then data.suppBullseye:Remove() end
    data.suppBullseye = nil
end

function BR.FireSchedule(data)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(npc) then
        local e = npc.GetEnemy and npc:GetEnemy()
        if IsValid(e) and npc.HasCondition and npc:HasCondition(COND_CAN_MELEE_ATTACK1) then
            npc:SetSchedule(SCHED_MELEE_ATTACK1)
        elseif IsValid(e) then
            npc:SetSchedule(SCHED_CHASE_ENEMY)
        else
            npc:SetSchedule(SCHED_IDLE_STAND)
        end
        return
    end
    npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
end

function BR.Prefire(data, pos)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(npc) then
        BR.FireSchedule(data)
        return
    end
    if not CAI.CVBool("cai_suppression") then
        npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        return
    end
    local aim = pos + Vector(0, 0, 40)
    local bull = data.suppBullseye
    if not IsValid(bull) then
        bull = ents.Create("npc_bullseye")
        if not IsValid(bull) then return end
        bull:SetPos(aim)
        bull:SetKeyValue("spawnflags", "196608")
        bull:Spawn()
        bull:SetNoDraw(true)
        bull:SetSolid(SOLID_NONE)
        bull:SetHealth(999999)
        data.suppBullseye = bull
        npc:AddEntityRelationship(bull, D_HT, 99)
    else
        bull:SetPos(aim)
    end
    if npc.SetEnemy then
        npc:SetEnemy(bull)
        if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(bull, aim) end
    end
    data.prefireUntil = CurTime() + 1.2
end

-- Think: one brain tick for a single NPC. Tick order:
--   perceive -> fade memory -> decay suppression -> regen morale/proficiency
--   -> decide (state) -> execute (Exec[state]) -> prefire/bullseye cleanup.
-- Light-touch NPCs (e.g. hunters) only perceive + fade, skipping decisions.