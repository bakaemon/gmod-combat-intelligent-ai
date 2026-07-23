local BR = CAI.Brain

BR.Exec = BR.Exec or {}

-- Execution handlers, one file per brain state (see CAI.STATE in sh_config.lua).
-- Each file assigns BR.Exec[<state>] = function(data) ... end.
local DIR = "combat_intelligence_ai/server/brain_func/exec/"

include(DIR .. "idle.lua")        -- 0  IDLE
include(DIR .. "patrol.lua")      -- 1  PATROL
include(DIR .. "engage.lua")      -- 2  ENGAGE
include(DIR .. "cover.lua")       -- 3  COVER
include(DIR .. "flank.lua")       -- 4  FLANK
include(DIR .. "suppress.lua")    -- 5  SUPPRESS
include(DIR .. "search.lua")      -- 6  SEARCH
include(DIR .. "retreat.lua")     -- 7  RETREAT
include(DIR .. "investigate.lua") -- 8  INVESTIGATE
include(DIR .. "regroup.lua")     -- 9  REGROUP
include(DIR .. "room_clear.lua")  -- 10 ROOM_CLEAR
include(DIR .. "bounded.lua")      -- 11 BOUNDED
