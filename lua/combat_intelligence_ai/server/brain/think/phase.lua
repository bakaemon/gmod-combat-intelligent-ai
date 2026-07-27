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
    local planPendingStuck = planPending and (CurTime() - data.phaseSince > CAI.Config.OODA.PhaseCooldown)

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

    if not overrideCommitment and BR.IsCommitted(data) then
        return
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
    data._pushCover = nil
    data._pushCoverPhase = nil
    data._pushCoverAt = nil
    data._pushPeekUntil = nil
    data._pushHops = nil
    if newPhase ~= CAI.PHASE.COVER then
        data.cover = nil
    end

    data.planPending = nil

    if data.reflex then data.reflex.urgency = nil end
    CAI.FireAim.ClearEnemy(data)
end

-- Targeted schedule throttle: only blocks re-issuing the same schedule within
-- SchedCooldown, and protects mid-reload from interruption.
function CAI.Schedule(data, sched)
    local npc = data.ent
    if sched ~= SCHED_RELOAD and data._schedAt and data._lastSched
        and sched == data._lastSched
        and CurTime() - data._schedAt < CAI.Config.Engage.SchedCooldown then
        return
    end
    if sched ~= SCHED_RELOAD and data._reloadingAt
        and CurTime() - data._reloadingAt < 1.5 then
        return
    end
    data._schedAt = CurTime()
    data._lastSched = sched
    npc:SetSchedule(sched)
end

function BR.FireSchedule(data)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(npc) then
        local e = npc.GetEnemy and npc:GetEnemy()
        if IsValid(e) and npc.HasCondition and COND_CAN_MELEE_ATTACK1 and npc:HasCondition(COND_CAN_MELEE_ATTACK1) then
            CAI.Schedule(data, SCHED_MELEE_ATTACK1)
        elseif IsValid(e) then
            CAI.Schedule(data, SCHED_CHASE_ENEMY)
        else
            CAI.Schedule(data, SCHED_IDLE_STAND)
        end
        return
    end
    CAI.Schedule(data, SCHED_ESTABLISH_LINE_OF_FIRE)
end

function BR.Prefire(data, pos)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(npc) then
        BR.FireSchedule(data)
        return
    end
    if not CAI.CVBool("cai_suppression") then
        CAI.Schedule(data, SCHED_ESTABLISH_LINE_OF_FIRE)
        return
    end
    if not pos then return end
    local aim = pos + Vector(0, 0, 40)
    CAI.FireAim.Aim(data, aim, 1.2)
end

-- Think: one brain tick for a single NPC. Tick order:
--   perceive -> fade memory -> decay suppression -> regen morale/proficiency
--   -> reflex -> OODA (decide) -> FireAim.Tick (auto-cleanup) -> exec (ExecPhase[phase]).
-- Light-touch NPCs (e.g. hunters) only perceive + fade, skipping decisions.

local C = CAI.Config

function BR.IsCommitted(data)
    local npc = data.ent
    if not (npc.IsCurrentSchedule) then return false end
    return npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1)
        or npc:IsCurrentSchedule(SCHED_RANGE_ATTACK2)
        or npc:IsCurrentSchedule(SCHED_MELEE_ATTACK1)
end

function BR.UnderFire(data)
    return (data.suppression or 0) > C.Flinch.UnderFireAt
end