local ROOT = "combat_intelligence_ai/server/brain/react/"
include(ROOT .. "all/grenade_dodge.lua")
include(ROOT .. "ranged/empty_reload.lua")
include(ROOT .. "ranged/suppression_jink.lua")
include(ROOT .. "ranged/melee_dodge.lua")
include(ROOT .. "ranged/retaliate.lua")

local function loader(data, dt)
    data.reflex = { bias = Vector(0, 0, 0), urgency = nil }
    BR.CallScopes("brain/react", data, dt)
end
BR.RegisterHook("brain/react", BR.HOOK_LOADER, loader)