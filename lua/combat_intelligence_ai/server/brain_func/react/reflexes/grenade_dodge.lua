local BR = CAI.Brain

table.insert(BR.ReflexHandlers, function(data, dt)
    local npc = data.ent
    local now = CurTime()
    local gPos = data.reflex and data.reflex.grenadePos
    local gUntil = data.reflex and data.reflex.grenadeUntil
    if not (gPos and gUntil and now < gUntil) then return end

    local src = npc:GetPos()
    local away = src - gPos
    away.z = 0
    if away:LengthSqr() <= 1 then return end

    local biasVec = away:GetNormalized() * 300
    local urgency = (gUntil - now < 1) and "urgent" or "attention"
    return biasVec, urgency
end)