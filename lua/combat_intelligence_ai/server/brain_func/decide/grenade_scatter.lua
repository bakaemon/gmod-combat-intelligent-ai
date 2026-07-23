local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: run away from a thrown grenade for a short window.
table.insert(BR.COA.PreTarget, function(data, npc)
    if data.scatterUntil then
        if CurTime() < data.scatterUntil then
            return CAI.STATE.RETREAT, "grenade_scatter"
        end
        data.scatterFrom, data.scatterUntil = nil, nil
    end
end)
