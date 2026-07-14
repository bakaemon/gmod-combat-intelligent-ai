local BR = CAI.Brain

-- SetState: transition helper. Only acts when the state actually changes, and
-- clears transient per-state fields so stale state never leaks across states.
function BR.SetState(data, newState, reason)
    if data.state == newState then return end
    data.prevState = data.state
    data.state = newState
    data.fighting = nil
    data.coverPhase = nil
    data.coverPhaseEnd = nil
    data.suppFaced = nil
    data.fleeSched = nil
    data.investFaced = nil
    data.retreatDest = nil
    data.stateSince = CurTime()
    if reason then data.lastDecision = reason end
    data.moveTarget = nil
    data.moveIssuedAt = nil
    data.patrolTarget = nil
    if newState ~= CAI.STATE.PATROL then
        data.patrolAt = CurTime()
    end
end

BR.StopSuppressing = function(data)
    if IsValid(data.suppBullseye) then data.suppBullseye:Remove() end
    data.suppBullseye = nil
end

function BR.Prefire(data, pos)
    local npc = data.ent
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
