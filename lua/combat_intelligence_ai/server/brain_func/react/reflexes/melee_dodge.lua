local BR = CAI.Brain

table.insert(BR.ReflexHandlers, function(data, dt)
    local npc = data.ent
    local now = CurTime()
    local mt = data.reflex and data.reflex.meleeThreatAt
    if not (mt and now < mt) then return end

    local src = npc:GetPos()
    local enemy = npc:GetEnemy()
    if not IsValid(enemy) then return end

    local dist = src:Distance(enemy:GetPos())
    if dist >= 150 then return end

    local away = src - enemy:GetPos()
    away.z = 0
    if away:LengthSqr() <= 1 then return end

    local awayPos = src + away:GetNormalized() * 350
    local biasVec = CAI.Nav.ReflexMove(data, awayPos)
    return biasVec, "urgent"
end)