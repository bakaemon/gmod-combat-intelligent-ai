CAI.Target = CAI.Target or {}
local T = CAI.Target

local ARCH_THREAT = { rocket = 3, lmg = 2.2, sniper = 2, shotgun = 1.6, smg = 1.3, rifle = 1.2, pistol = 0.8 }

function T.Score(data, enemy, rec)
    local npc = data.ent
    local score = 0

    local dist = npc:GetPos():Distance(rec.pos or enemy:GetPos())
    score = score + (1 - math.Clamp(dist / 2500, 0, 1)) * 2

    if enemy.GetActiveWeapon then
        local arch = CAI.WeaponIntel.Classify(enemy:GetActiveWeapon())
        score = score + (ARCH_THREAT[arch] or 1)
    end

    if CAI.Util.CanSee(npc, enemy) then score = score + 1.5 end
    if enemy:Health() < 40 then score = score + 0.7 end
    if not rec.heardOnly then score = score + 0.5 end

    if dist < 250 and enemy:IsNPC() then
        local ew = enemy.GetActiveWeapon and enemy:GetActiveWeapon()
        if not IsValid(ew) then score = score + 2.5 end
    end
    if npc.GetEnemy and npc:GetEnemy() == enemy then score = score * 1.25 end
    if data.lastAttacker == enemy and CurTime() - (data.lastHurtAt or 0) < 1.5 then
        score = score + 4.0
    end

    return score
end

function T.Evaluate(data)
    local npc = data.ent
    local best, bestScore = nil, -math.huge
    local bestRec

    for enemy, rec in pairs(data.memory.enemies) do

        local allied = IsValid(enemy) and npc:Disposition(enemy) == D_LI
        if not IsValid(enemy) or allied or not CAI.Util.IsTargetable(enemy) then

            data.memory.enemies[enemy] = nil
            if IsValid(enemy) and npc.ClearEnemyMemory then
                npc:ClearEnemyMemory(enemy)
            end
        else
            local s = T.Score(data, enemy, rec)
            if s > bestScore then best, bestScore, bestRec = enemy, s, rec end
        end
    end

    local cur = npc.GetEnemy and npc:GetEnemy()
    if IsValid(cur) and not CAI.Util.IsTargetable(cur) then
        if npc.ClearEnemyMemory then npc:ClearEnemyMemory(cur) end
        npc:SetEnemy(NULL)
    end

    if data.state == CAI.STATE.SUPPRESS and IsValid(data.suppBullseye) then
        return best, bestRec
    end

    if IsValid(best) and npc.SetEnemy then
        if npc:GetEnemy() ~= best then
            npc:SetEnemy(best)
            if npc.UpdateEnemyMemory then
                npc:UpdateEnemyMemory(best, bestRec.pos or best:GetPos())
            end
        end
    end
    return best, bestRec
end

CAI.Prof.WrapFn(T, "Evaluate", "target_evaluate")
CAI.Prof.WrapFn(T, "Score", "target_score")
