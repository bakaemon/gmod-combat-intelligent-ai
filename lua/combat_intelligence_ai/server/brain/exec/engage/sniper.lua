local BR = CAI.Brain

local function handler(data)
    -- Sniper-specific engage overrides (empty stub — falls through to ranged generic)
end

BR.RegisterHook("brain/exec/engage", "sniper", handler)