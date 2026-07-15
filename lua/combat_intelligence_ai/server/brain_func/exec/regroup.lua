local BR = CAI.Brain

-- REGROUP: move back toward the squad, rejoin the leader, take a formation
-- slot, or walk to a reinforce target.
BR.Exec[9] = function(data)
    local npc = data.ent
    local squad = data.squad
    if not squad or not IsValid(squad.leader) or squad.leader == npc then
        BR.SetState(data, CAI.STATE.PATROL, "no_squad_to_regroup")
        return
    end

    local visEnemy, visRec = CAI.Memory.FreshestEnemy(data)
    if IsValid(visEnemy) and CAI.Util.CanSee(npc, visEnemy) then
        data.reinforceTarget = nil
        BR.SetState(data, CAI.STATE.ENGAGE, "spotted_during_regroup")
        return
    end

    if data.reinforceTarget then
        if npc:GetPos():DistToSqr(data.reinforceTarget) < 90 * 90 then
            data.reinforceTarget = nil
            BR.SetState(data, CAI.STATE.PATROL, "reinforced")
            return
        end
        CAI.Nav.MoveTo(data, data.reinforceTarget, "run")
        return
    end

    local idx = 0
    for _, m in ipairs(squad.members) do
        if m ~= squad.leader then
            idx = idx + 1
            if m == data.ent then break end
        end
    end
    local slot = CAI.Squad.FormationSlot(squad, idx)
    if slot and CurTime() - (data.regroupAt or 0) > 1.5 then
        data.regroupAt = CurTime()
        CAI.Nav.MoveTo(data, slot, "run")
    end
    if data.moveTarget and CAI.Nav.Arrived(data, 90) then
        BR.SetState(data, CAI.STATE.PATROL, "in_formation")
    end
end

