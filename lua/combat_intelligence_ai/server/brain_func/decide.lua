local BR = CAI.Brain

BR.COA = BR.COA or {}
BR.COA.OODA = BR.COA.OODA or { PreTarget = {}, Target = {} }

local DIR = "combat_intelligence_ai/server/brain_func/decide/"

BR.COA.PreTarget = BR.COA.OODA.PreTarget
BR.COA.Target = BR.COA.OODA.Target

include(DIR .. "flank_protect.lua")
include(DIR .. "melee_threat.lua")
include(DIR .. "morale_break.lua")
include(DIR .. "panic.lua")
include(DIR .. "room_clear_coa.lua")
include(DIR .. "pinned.lua")
include(DIR .. "engage_target.lua")
include(DIR .. "lost_target_coa.lua")
include(DIR .. "suppress_order.lua")
include(DIR .. "flank_order.lua")
include(DIR .. "bound_order.lua")
include(DIR .. "separated.lua")
include(DIR .. "squad_aware.lua")
include(DIR .. "pre_contact.lua")
