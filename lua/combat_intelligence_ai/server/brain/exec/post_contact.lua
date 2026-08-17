local BR = CAI.Brain

BR.RegisterHook("brain/exec", "post_contact", function(data)
    local npc = data.ent
    if not data._pcSince then
        data._pcSince = CurTime()
        return
    end
    if CurTime() - data._pcSince > math.Rand(2, 4) then
        data._pcSince = nil
        data.planPending = "post_contact_done"
    end
end)
