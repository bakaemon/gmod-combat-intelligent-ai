local ROOT = "combat_intelligence_ai/server/brain/ooda/target/"
include(ROOT .. "all/pinned.lua")
include(ROOT .. "all/lost_target_coa.lua")
include(ROOT .. "all/squad_aware.lua")
include(ROOT .. "all/pre_contact_coa.lua")
include(ROOT .. "ranged/engage_target.lua")
include(ROOT .. "melee/engage_target.lua")

local function loader(ctx)
    BR.CallScopes("brain/ooda/target", ctx)
end
BR.RegisterHook("brain/ooda/target", BR.HOOK_LOADER, loader)