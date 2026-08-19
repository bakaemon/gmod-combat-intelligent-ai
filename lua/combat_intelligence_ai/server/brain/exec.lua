local ROOT = "combat_intelligence_ai/server/brain/exec/"
include(ROOT .. "pre_contact.lua")
include(ROOT .. "assess.lua")
include(ROOT .. "engage.lua")
include(ROOT .. "maneuver.lua")
include(ROOT .. "cover.lua")
include(ROOT .. "withdraw.lua")
include(ROOT .. "post_contact.lua")

local function loader(data)
    local pn = (CAI.PHASE_NAMES[data.phase] or ""):lower()
    if pn == "" then return end
    if data.phase == CAI.PHASE.ENGAGE then
        BR.Call("brain/exec/engage", BR.HOOK_LOADER, data)
    else
        BR.Call("brain/exec", pn, data)
    end
end
BR.RegisterHook("brain/exec", BR.HOOK_LOADER, loader)