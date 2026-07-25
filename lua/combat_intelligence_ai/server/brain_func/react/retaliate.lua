local BR = CAI.Brain

BR.Retaliate = function(data)
    local npc = data.ent
    if not data.retaliateUntil then return end
    if CurTime() >= data.retaliateUntil then
        data.retaliateUntil = nil
        data.retaliateTarget = nil
        data.retaliatePos = nil
        return
    end
    local atk = IsValid(data.retaliateTarget) and data.retaliateTarget
    local pos = atk and atk:GetPos() or data.retaliatePos
    if not pos then return end
    if atk and CAI.Util.CanSee(npc, atk) then
        if npc.SetEnemy then npc:SetEnemy(atk) end
        CAI.Schedule(data, SCHED_ESTABLISH_LINE_OF_FIRE)
    elseif not CAI.PhaseIs(data, CAI.PHASE.ENGAGE, "suppress") then
        BR.Prefire(data, pos)
    end
end
