CAI.Brain = CAI.Brain or {}
BR = CAI.Brain
local ROOT = "combat_intelligence_ai/server/brain/"

include(ROOT .. "hooks.lua")
include(ROOT .. "think.lua")
include(ROOT .. "react.lua")
include(ROOT .. "ooda.lua")
include(ROOT .. "exec.lua")
include("combat_intelligence_ai/server/squad_func/init.lua")

CAI.Prof.WrapFn(BR, "Prefire", "brain_prefire")