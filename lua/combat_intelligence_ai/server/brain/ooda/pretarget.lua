local ROOT = "combat_intelligence_ai/server/brain/ooda/pretarget/"
include(ROOT .. "all/flank_protect.lua")
include(ROOT .. "all/melee_threat.lua")
include(ROOT .. "all/panic.lua")
include(ROOT .. "all/room_clear_coa.lua")
include(ROOT .. "ranged/morale_break.lua")
include(ROOT .. "melee/morale_break.lua")

local function loader(ctx)
    BR.CallScopes("brain/ooda/pretarget", ctx)
end
BR.RegisterHook("brain/ooda/pretarget", BR.HOOK_LOADER, loader)