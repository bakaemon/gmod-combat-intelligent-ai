local BR = CAI.Brain
local C = CAI.Config

table.insert(BR.ReflexHandlers, function(data, dt)
    local npc = data.ent
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
            if not BR.IsCommitted(data) then
                local dest = src + away:GetNormalized() * 200
                biasVec = CAI.Nav.ReflexMove(data, dest)
            else
                biasVec = away:GetNormalized() * 200
            end
        end
    end

    return biasVec, urgency
end)