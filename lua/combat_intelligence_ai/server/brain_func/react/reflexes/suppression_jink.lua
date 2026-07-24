local BR = CAI.Brain
local C = CAI.Config

table.insert(BR.ReflexHandlers, function(data, dt)
    local npc = data.ent
    local sup = data.suppression or 0
    if sup <= C.Flinch.UnderFireAt then return end

    local enemy = npc:GetEnemy()
    local enemyPos = IsValid(enemy) and enemy:GetPos() or nil

    if not data._reflexCover then
        data._reflexCover = CAI.Cover.FindBest(data, enemy, enemyPos)
    end
    local coverPos = data._reflexCover
    local src = npc:GetPos()
    local biasVec = Vector(0, 0, 0)

    if coverPos then
        local toCov = coverPos - src
        toCov.z = 0
        if toCov:LengthSqr() > 1 then
            biasVec = biasVec + toCov:GetNormalized() * 200
        end
    elseif enemyPos then
        local away = src - enemyPos
        away.z = 0
        if away:LengthSqr() > 1 then
            biasVec = biasVec + away:GetNormalized() * 150
        end
    end

    local urgency = nil
    if sup >= CAI.Config.Suppression.PinnedAt then
        urgency = "attention"
    end
    return biasVec, urgency
end)