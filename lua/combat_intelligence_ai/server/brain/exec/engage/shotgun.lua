local BR = CAI.Brain

local function handler(data)
    -- Shotgun-specific engage overrides are handled inline in the ranged handler
    -- (advance-toward-ideal-range logic at lines 541-548 of the original).
    -- This stub exists for arch-specific hooks; currently falls through to ranged.
end

BR.RegisterHook("brain/exec/engage", "shotgun", handler)