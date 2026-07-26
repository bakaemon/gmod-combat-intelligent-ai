local BR = CAI.Brain

BR.ExecPhase = BR.ExecPhase or {}

local DIR = "combat_intelligence_ai/server/brain_func/exec/"

-- OODA phase-based exec handlers
include(DIR .. "pre_contact.lua")
include(DIR .. "assess.lua")
include(DIR .. "engage.lua")
include(DIR .. "maneuver.lua")
include(DIR .. "cover.lua")
include(DIR .. "withdraw.lua")
include(DIR .. "post_contact.lua")
