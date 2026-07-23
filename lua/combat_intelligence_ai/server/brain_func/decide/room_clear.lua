local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

-- Course of action: squad is clearing a doorway; approach and slice it.
table.insert(BR.COA.PreTarget, function(data, npc)
    if data.squad and data.squad.clearingDoor and not data.squad.clearingDoor.done then
        return CAI.STATE.ROOM_CLEAR, "clearing_doorway"
    end
end)
