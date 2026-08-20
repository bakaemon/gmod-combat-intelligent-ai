local BR = CAI.Brain
local C = CAI.Config

BR.RegisterHook("brain/react", "ranged_suppression_jink", function(data, dt)
    local npc = data.ent
    if CAI.WeaponIntel.IsMelee(data.ent) then return end
    local sup = data.suppression or 0
    if sup <= C.Flinch.UnderFireAt then return end

    local src = npc:GetPos()
    local biasVec = nil
    local urgency = sup >= C.Suppression.PinnedAt and "attention" or nil

    local enemy = npc:GetEnemy()
    local enemyPos = IsValid(enemy) and enemy:GetPos()
    if enemyPos then
        local away = src - enemyPos
        away.z = 0
        if away:LengthSqr() > 1 then
            away:Normalize()
            local jinkDir = CAI.SpatialMap.QuerySafeDir(data.squad, src, away)
            if not BR.IsCommitted(data) then
                local dest = src + jinkDir * 200
                biasVec = CAI.Nav.ReflexMove(data, dest)
            else
                biasVec = jinkDir * 200
            end
        end
    end

    if biasVec then data.reflex.bias = data.reflex.bias + biasVec; data.reflex.urgency = urgency end
end)