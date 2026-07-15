local BR = CAI.Brain

-- BOUNDED: squad "bounding overwatch", hold a position and fire for a fixed
-- window, then push through once confident (corner-push gate).
BR.Exec[11] = function(data)
    local npc = data.ent
    if not data.boundTarget then
        BR.SetState(data, CAI.STATE.COVER, "no_bound_target")
        return
    end
    local moving = data.moveTarget ~= nil and not CAI.Nav.Arrived(data, 70)
    if moving then
        CAI.FriendlyFire.Update(data)
        return
    end
    if not data.boundArrived then
        data.boundArrived = CurTime()
        data.fighting = nil
        npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
    end
    local fireDuration = CAI.Config.SquadTactics.BoundFireDuration
    local cornerpush = CAI.CVBool("cai_cornerpush")
    -- Hold the bound position and fire for a fixed window, only push through
    -- (or regroup) once confident, i.e. survived long enough without being
    -- hurt (corner-push confidence gate).
    if CurTime() - data.boundArrived > fireDuration then
        local confident = true
        if cornerpush then
            local ct = CAI.Config.SelfPreserve.CornerPush.ConfidenceTime
            confident = (CurTime() - data.boundArrived > ct)
                and (CurTime() - (data.lastHurtAt or 0) > ct)
        end
        if confident then
            data.boundTarget = nil
            data.boundArrived = nil
            data.staggerOffset = nil
            if data.squad and data.squad.leader and data.squad.leader ~= npc then
                BR.SetState(data, CAI.STATE.REGROUP, "bound_complete_regroup")
            else
                BR.SetState(data, CAI.STATE.ENGAGE, "aggressive_push")
            end
        else
            data.boundArrived = CurTime()
            data.fighting = nil
            npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        end
    else
        if cornerpush and (CurTime() - (data.lastHurtAt or 0) < 0.5) then
            data.boundArrived = CurTime()
        end
        CAI.FriendlyFire.Update(data)
    end
end

-- Prefire: pre-aim at a known/expected position via an invisible bullseye so
-- the NPC is already shooting the moment it arrives, rather than acquiring late.
