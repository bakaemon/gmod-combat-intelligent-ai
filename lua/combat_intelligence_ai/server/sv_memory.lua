CAI.Memory = CAI.Memory or {}
local M = CAI.Memory

function M.New()
    return {
        enemies = {},
        sounds = {},
        dangers = {},
        deadAllies = {},
        lastFade = CurTime(),
    }
end

function M.SeeEnemy(data, enemy, pos)
    if not CAI.CVBool("cai_memory") then return end
    if not CAI.Util.IsTargetable(enemy) then return end
    if enemy:GetClass() == "npc_bullseye" then return end
    local rec = data.memory.enemies[enemy] or {}
    rec.pos, rec.t, rec.heardOnly = pos or enemy:GetPos(), CurTime(), false
    data.memory.enemies[enemy] = rec
end

function M.HearEnemy(data, enemy, pos)
    if not CAI.CVBool("cai_memory") then return end
    if not CAI.Util.IsTargetable(enemy) then return end
    if enemy:GetClass() == "npc_bullseye" then return end
    local d = IsValid(data.ent) and data.ent:GetPos():Distance(pos) or 500
    local fuzz = math.min(150, d * 0.12)
    pos = pos + Vector(math.Rand(-fuzz, fuzz), math.Rand(-fuzz, fuzz), 0)
    local rec = data.memory.enemies[enemy] or {}
    if rec.t and not rec.heardOnly and CurTime() - rec.t < 1 then return end
    rec.pos, rec.t, rec.heardOnly = pos, CurTime(), true
    data.memory.enemies[enemy] = rec
end

function M.AddSound(data, pos, stype)
    local s = data.memory.sounds
    s[#s + 1] = { pos = pos, t = CurTime(), type = stype }
    if #s > 8 then table.remove(s, 1) end
end

function M.AddDanger(data, pos, radius, reason)
    local d = data.memory.dangers
    d[#d + 1] = { pos = pos, t = CurTime(), radius = radius or 250, reason = reason }
    if #d > 12 then table.remove(d, 1) end
end

function M.InDanger(data, pos)
    for _, dz in ipairs(data.memory.dangers) do
        if pos:DistToSqr(dz.pos) < dz.radius * dz.radius then return true, dz end
    end
    return false
end

function M.AvoidPos(data, pos, radius)
    radius = radius or 250
    local ind, dz = M.InDanger(data, pos)
    if ind then return true, dz end
    local r2 = radius * radius
    for _, da in ipairs(data.memory.deadAllies) do
        if pos:DistToSqr(da.pos) < r2 then return true, da end
    end
    if data.squad then
        for _, da in ipairs(data.squad.blackboard.deadAllies) do
            if pos:DistToSqr(da.pos) < r2 then return true, da end
        end
    end
    return false
end

function M.NearAllyDeath(data, pos, radius)
    radius = radius or 250
    local r2 = radius * radius
    for _, da in ipairs(data.memory.deadAllies) do
        if pos:DistToSqr(da.pos) < r2 then return true, da end
    end
    if data.squad then
        for _, da in ipairs(data.squad.blackboard.deadAllies) do
            if pos:DistToSqr(da.pos) < r2 then return true, da end
        end
    end
    return false
end

function M.FreshestEnemy(data)
    local best, bestRec
    for ent, rec in pairs(data.memory.enemies) do
        if IsValid(ent) and CAI.Util.Alive(ent) then
            if not bestRec or rec.t > bestRec.t then best, bestRec = ent, rec end
        end
    end
    return best, bestRec
end

function M.Fade(data)
    local now = CurTime()
    if now - data.memory.lastFade < CAI.Config.Memory.FadeTick then return end
    data.memory.lastFade = now
    local cfg = CAI.Config.Memory

    for ent, rec in pairs(data.memory.enemies) do
        if not IsValid(ent) or not CAI.Util.Alive(ent) or now - rec.t > cfg.EnemyTTL then
            data.memory.enemies[ent] = nil
        end
    end
    for i = #data.memory.sounds, 1, -1 do
        if now - data.memory.sounds[i].t > cfg.SoundTTL then table.remove(data.memory.sounds, i) end
    end
    for i = #data.memory.dangers, 1, -1 do
        if now - data.memory.dangers[i].t > cfg.DangerTTL then table.remove(data.memory.dangers, i) end
    end
    for i = #data.memory.deadAllies, 1, -1 do
        if now - data.memory.deadAllies[i].t > cfg.DangerTTL then table.remove(data.memory.deadAllies, i) end
    end
end

CAI.Prof.WrapFn(M, "FreshestEnemy", "mem_freshest")
CAI.Prof.WrapFn(M, "AvoidPos", "mem_avoid")
CAI.Prof.WrapFn(M, "InDanger", "mem_indanger")
CAI.Prof.WrapFn(M, "Fade", "mem_fade")
