local BR = CAI.Brain

function BR.SetPhase(data, newPhase, intent, reason, overrideCommitment)
    if data.phase == newPhase and data.phaseIntent == intent then
        if reason then data.lastDecision = reason end
        return
    end

    local committedUntil = data.plan and data.plan.committedUntil or 0
    local urgency = data.reflex and data.reflex.urgency
    local urgent = urgency == "urgent"
    local attention = urgency == "attention"
    local planPending = data.planPending
    local planPendingStuck = planPending and (CurTime() - data.phaseSince > 0.5)

    if not urgent and not attention and not planPendingStuck and not overrideCommitment then
        if CurTime() < committedUntil then
            return
        end
    end

    if attention and not urgent and not planPendingStuck and not overrideCommitment then
        local elapsed = CurTime() - data.phaseSince
        local total = committedUntil - data.phaseSince
        if total > 0 and elapsed < total * 0.5 then
            return
        end
    end

    local oldPhaseSince = data.phaseSince or CurTime()
    data.prevPhase = data.phase

    data.phase = newPhase
    data.phaseIntent = intent
    data.phaseSince = CurTime()
    if reason then data.lastDecision = reason end

    local defDuration = CAI.Config.Plan.PhaseDuration[newPhase] or 1.5
    local sunkCost = math.floor(CurTime() - oldPhaseSince) * 0.3
    data.plan.committedUntil = CurTime() + defDuration + sunkCost
    data.plan.expiresAt = data.plan.committedUntil
    data.plan.reason = reason

    data.fighting = nil
    data.coverPhase = nil
    data.coverPhaseEnd = nil
    data.suppFaced = nil
    data.fleeSched = nil
    data.investFaced = nil
    data.retreatDest = nil
    data.ambush = nil
    data.meleePhase = nil
    data.moveTarget = nil
    data.moveIssuedAt = nil
    data.patrolTarget = nil
    if newPhase ~= CAI.PHASE.COVER then
        data.cover = nil
    end

    data.planPending = nil

    if data.reflex then data.reflex.urgency = nil end
end

BR.StopSuppressing = function(data)
    if IsValid(data.suppBullseye) then
        local npc = data.ent
        if IsValid(npc) and npc.GetEnemy and npc:GetEnemy() == data.suppBullseye then
            npc:SetEnemy(NULL)
        end
        data.suppBullseye:Remove()
    end
    data.suppBullseye = nil
end

function BR.FireSchedule(data)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(npc) then
        local e = npc.GetEnemy and npc:GetEnemy()
        if IsValid(e) and npc.HasCondition and COND_CAN_MELEE_ATTACK1 and npc:HasCondition(COND_CAN_MELEE_ATTACK1) then
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
--   -> reflex -> OODA (decide) -> exec (ExecPhase[phase]) -> prefire/bullseye cleanup.
-- Light-touch NPCs (e.g. hunters) only perceive + fade, skipping decisions.