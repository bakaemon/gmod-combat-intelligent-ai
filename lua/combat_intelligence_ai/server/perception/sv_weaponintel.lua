CAI.WeaponIntel = CAI.WeaponIntel or {}
local WI = CAI.WeaponIntel

local archetypeCache = {}

function WI.Classify(wep)
    if not IsValid(wep) then return "rifle" end
    local cls = wep:GetClass()
    local cached = archetypeCache[cls]
    if cached then return cached end
    local lower = string.lower(cls)
    for _, p in ipairs(CAI.Config.WeaponPatterns) do
        if lower:find(p.pattern, 1, true) then
            archetypeCache[cls] = p.archetype
            return p.archetype
        end
    end
    archetypeCache[cls] = "rifle"
    return "rifle"
end

function WI.Update(data, enemy)
    if IsValid(enemy) and enemy:IsNPC() then
        local ew = enemy.GetActiveWeapon and enemy:GetActiveWeapon()
        if not IsValid(ew) then
            data.enemyWeaponResponse = CAI.Config.WeaponResponses.melee
            return
        end
    end
    if not CAI.CVBool("cai_weaponintel") then
        data.enemyWeaponResponse = CAI.Config.WeaponResponses.rifle
        return
    end
    if not (IsValid(enemy) and enemy.GetActiveWeapon) then return end
    local archetype = WI.Classify(enemy:GetActiveWeapon())

    if data.enemyWeaponArchetype ~= archetype then
        data.enemyWeaponArchetype = archetype
        data.enemyWeaponResponse = CAI.Config.WeaponResponses[archetype] or CAI.Config.WeaponResponses.rifle

        if archetype == "rocket" and data.squad then
            for _, member in ipairs(data.squad.members) do
                local md = CAI.Manager.Get(member)
                if md then md.forceRecover = true end
            end
            CAI.Squad.Broadcast(data.squad, "rocket_spotted", data.ent)
        end
    end
end

function WI.EffectiveAggression(data)
    local agg = 0.5 + (data.personality.stats.aggression or 0) * 0.5
    agg = agg + (CAI.CVNum("cai_aggression") - 0.5) * 0.9
    if data.enemyWeaponResponse then
        agg = agg + (data.enemyWeaponResponse.aggression or 0)
    end
    if data.morale > 80 then agg = agg + 0.1 end
    if data.morale < CAI.Config.Morale.ShakenThreshold then agg = agg - 0.25 end
    return math.Clamp(agg, 0, 1)
end

local ownIdeal = {
    shotgun = 340, smg = 520, rifle = 650, lmg = 720,
    sniper = 1100, pistol = 500, explosive = 900,
}
function WI.OwnIdeal(npc)
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then return 600 end
    local arch = WI.Classify(wep)
    return ownIdeal[arch] or 600
end

local ownRange = {
    shotgun = 700, smg = 1100, rifle = 1800, lmg = 1600,
    sniper = 4000, pistol = 900, explosive = 1500,
}
function WI.OwnRange(npc)
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then return 1200 end
    local arch = WI.Classify(wep)
    return ownRange[arch] or 1200
end

function WI.IsMelee(npc)
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then return false end
    local c = wep:GetClass()
    return c:find("stunstick", 1, true) ~= nil or c:find("crowbar", 1, true) ~= nil or c:find("melee", 1, true) ~= nil
end

function WI.OwnArch(npc)
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then return nil end
    return WI.Classify(wep)
end

function WI.IsMeleeThreat(ent)
    if not IsValid(ent) then return false end
    local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
    if IsValid(wep) then
        local c = wep:GetClass()
        return c:find("crowbar", 1, true) ~= nil
            or c:find("stunstick", 1, true) ~= nil
            or c:find("melee", 1, true) ~= nil
    end
    if ent.CapabilitiesGet then
        return bit.band(ent:CapabilitiesGet(), CAP_INNATE_MELEE_ATTACK1) ~= 0
    end
    return true
end

CAI.Prof.WrapFn(WI, "Update", "weaponintel_update")
