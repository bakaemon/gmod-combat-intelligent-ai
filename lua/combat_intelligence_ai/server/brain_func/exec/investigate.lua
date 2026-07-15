local BR = CAI.Brain

-- INVESTIGATE: move to a heard/last-known position, face it, and look around;
-- re-engage if the enemy is spotted, else resume patrol when the timer expires.
BR.Exec[8] = function(data)
    local npc = data.ent
    local visEnemy, visRec = CAI.Memory.FreshestEnemy(data)
    if IsValid(visEnemy) and CAI.Util.CanSee(npc, visEnemy) then
        BR.SetState(data, CAI.STATE.ENGAGE, "spotted_during_investigate")
        return
    end
    if not data.investigatePos or CurTime() > (data.investigateUntil or 0) then

        if data.investigatePos then
            data.lastInvestigate = { pos = data.investigatePos, t = CurTime() }
        end
        data.investigatePos = nil
        BR.SetState(data, CAI.STATE.PATROL, "investigation_over")
        return
    end
    if data.moveTarget and CAI.Nav.Arrived(data, 100) then
        if not data.investFaced then
            data.investFaced = true
            data.moveTarget = nil
            npc:SetSchedule(SCHED_COMBAT_FACE)
            data.investigateUntil = math.min(data.investigateUntil, CurTime() + 3)
        end
    else
        data.investFaced = nil
        CAI.Nav.MoveTo(data, data.investigatePos, "walk")
    end
end

