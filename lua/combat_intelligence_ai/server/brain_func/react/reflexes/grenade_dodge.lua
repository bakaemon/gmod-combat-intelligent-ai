local BR = CAI.Brain

table.insert(BR.ReflexHandlers, function(data, dt)
    local npc = data.ent
    local now = CurTime()
    local gPos = data.reflex and data.reflex.grenadePos
    local gUntil = data.reflex and data.reflex.grenadeUntil
    if not (gPos and gUntil and now < gUntil) then return end

    local src = npc:GetPos()
    local away = src - gPos
    away.z = 0
    if away:LengthSqr() <= 1 then return end

    local biasVec = away:GetNormalized() * 300
    local urgency = (gUntil - now < 1) and "urgent" or "attention"
    return biasVec, urgency
end)

CAI.SafeHook("OnEntityCreated", "CAI_GrenadeWatch", function(ent)
    timer.Simple(0, function()
        if not IsValid(ent) or not CAI.Enabled() then return end
        local cls = ent:GetClass()
        if cls == "npc_grenade_frag" or cls == "grenade_hand" or cls:find("grenade") then
            for npc, data in pairs(CAI.Manager.All()) do
                if IsValid(npc) and npc:GetPos():DistToSqr(ent:GetPos()) < 600 * 600 then
                    CAI.Memory.AddDanger(data, ent:GetPos(), 400, "grenade")
                    data.scatterFrom = ent:GetPos()
                    data.scatterUntil = CurTime() + 2.5
                    if not data.reflex then data.reflex = {} end
                    data.reflex.grenadePos = ent:GetPos()
                    data.reflex.grenadeUntil = CurTime() + 2.5
                    if data.squad then
                        CAI.Battlefield.ReportDanger(data.squad, ent:GetPos(), 400, "grenade")
                        CAI.Squad.Broadcast(data.squad, "grenade", npc)
                    end
                    CAI.Voice.Speak(data, "grenade")
                end
            end
        end
    end)
end)
