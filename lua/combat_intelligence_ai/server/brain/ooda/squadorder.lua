local ROOT = "combat_intelligence_ai/server/brain/ooda/squadorder/"
include(ROOT .. "suppress_order.lua")
include(ROOT .. "flank_order.lua")
include(ROOT .. "bound_order.lua")
include(ROOT .. "separated.lua")

local function loader(ctx)
    BR.CallScopes("brain/ooda/squadorder", ctx)
end
BR.RegisterHook("brain/ooda/squadorder", BR.HOOK_LOADER, loader)