local BR = CAI.Brain
local C = CAI.Config

table.insert(BR.ReflexHandlers, function(data, dt)
    local npc = data.ent
    local sup = data.suppression or 0
    if sup <= C.Flinch.UnderFireAt then return end

    local src = npc:GetPos()
    local squad = data.squad
    local biasVec = nil
    local urgency = sup >= C.Suppression.PinnedAt and "attention" or nil

    local coverPos = squad and CAI.Cover.QueryNearby(data, src, C.Cover.NearbyRadius or 500)
    if coverPos then
        biasVec = CAI.Nav.ReflexMove(data, coverPos)
    else
        local enemy = npc:GetEnemy()
        local enemyPos = IsValid(enemy) and enemy:GetPos()
        if enemyPos then
            local away = src - enemyPos
            away.z = 0
            if away:LengthSqr() > 1 then
                biasVec = away:GetNormalized() * 150
            end
        end
    end

    return biasVec, urgency
end)