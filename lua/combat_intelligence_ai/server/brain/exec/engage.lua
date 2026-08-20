local ROOT = "combat_intelligence_ai/server/brain/exec/engage/"
include(ROOT .. "engage_core.lua")
include(ROOT .. "ranged_core.lua")
include(ROOT .. "melee_core.lua")
include(ROOT .. "ranged.lua")
include(ROOT .. "melee.lua")
include(ROOT .. "shotgun.lua")
include(ROOT .. "sniper.lua")
include(ROOT .. "lmg.lua")

local function loader(data)
    if BR.IsCommitted(data) then return end
    local isMelee = CAI.WeaponIntel.IsMelee(data.ent)
    local cat = isMelee and "melee" or "ranged"
    local arch = not isMelee and CAI.WeaponIntel.OwnArch(data.ent)
    if arch and BR.Call("brain/exec/engage", arch, data) then return end
    BR.Call("brain/exec/engage", cat, data)
end
BR.RegisterHook("brain/exec/engage", BR.HOOK_LOADER, loader)