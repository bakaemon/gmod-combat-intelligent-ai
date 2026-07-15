local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: a player aimed at us long enough; bail from current cover
-- immediately and pick a fresh one.
table.insert(BR.COA.PreTarget, function(data, npc)
    if data.forceRecover then
        data.forceRecover = nil
        return CAI.STATE.COVER, "emergency_relocate"
    end
end)
