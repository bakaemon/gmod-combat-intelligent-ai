local BR = CAI.Brain
local C = CAI.Config

function BR.IsCommitted(data)
    local npc = data.ent
    if not (npc.IsCurrentSchedule) then return false end
    -- Committed weapon wind-ups (basic fire, secondary attacks, melee swings)
    -- are uninterruptible so the flinch layer never resets a live shot or a
    -- grenade wind-up mid-sequence.
    return npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1)
        or npc:IsCurrentSchedule(SCHED_RANGE_ATTACK2)
        or npc:IsCurrentSchedule(SCHED_MELEE_ATTACK1)
end

function BR.UnderFire(data)
    return (data.suppression or 0) > C.Flinch.UnderFireAt
end