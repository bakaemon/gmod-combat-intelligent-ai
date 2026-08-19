local BR = CAI.Brain

BR.RegisterHook("brain/react", "ranged_melee_dodge", function(data, dt)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(data.ent) then return end
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
    if biasVec then data.reflex.bias = data.reflex.bias + biasVec; data.reflex.urgency = "urgent" end
end)