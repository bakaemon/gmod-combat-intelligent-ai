CAI.SquadFunc = CAI.SquadFunc or {}
local SF = CAI.SquadFunc

local DIR = "combat_intelligence_ai/server/squad_func/"
include(DIR .. "plan.lua")
include(DIR .. "patrol.lua")
include(DIR .. "formation.lua")

CAI.Prof.WrapFn(CAI.SquadFunc, "Plan", "squad_func_plan")
