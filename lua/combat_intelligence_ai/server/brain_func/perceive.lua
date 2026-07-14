local BR = CAI.Brain

-- Perceive: gather senses and refresh memory. Runs first every tick. Crucially
-- it does NOT decide or move, it only feeds data.memory / combat awareness.
BR.Perceive = function(data)
    local npc = data.ent

    if CurTime() - (data.darkAt or 0) > 1.0 then
        data.darkAt = CurTime()
        CAI.ApplyDarknessVision(data)
    end

    if CurTime() - (data.aimCheckAt or 0) > 0.4 then
        data.aimCheckAt = CurTime()
        local ply = CAI.Util.NearestPlayer(npc:GetPos())
        if IsValid(ply) and CAI.Util.IsTargetable(ply)
           and npc:Disposition(ply) == D_HT
           and npc:GetPos():DistToSqr(ply:GetPos()) < 1500 * 1500 then
            local toNPC = (npc:WorldSpaceCenter() - ply:EyePos())
            toNPC:Normalize()
            if ply:GetAimVector():Dot(toNPC) > 0.995 and CAI.Util.CanSee(npc, ply) then
                data.aimedSince = data.aimedSince or CurTime()
                if CurTime() - data.aimedSince > 0.35 then
                    CAI.Memory.SeeEnemy(data, ply, ply:GetPos())
                    if data.state == CAI.STATE.COVER and not data.forceRecover
                       and math.random() < 0.35 then
                        data.forceRecover = true
                    end
                end
            else
                data.aimedSince = nil
            end
        else
            data.aimedSince = nil
        end
    end

    local engineEnemy = npc.GetEnemy and npc:GetEnemy()
    if IsValid(engineEnemy) and CAI.Util.IsTargetable(engineEnemy) then
        if CAI.Util.Sees(npc, engineEnemy) then
            local firstContact = data.memory.enemies[engineEnemy] == nil
            CAI.Memory.SeeEnemy(data, engineEnemy, engineEnemy:GetPos())
            CAI.WeaponIntel.Update(data, engineEnemy)
            if data.squad then
                CAI.Battlefield.ReportEnemy(data.squad, engineEnemy, engineEnemy:GetPos(), npc)
                if firstContact then
                    CAI.Voice.Speak(data, "enemy_spotted")
                    CAI.Squad.Broadcast(data.squad, "enemy_spotted", npc,
                        { enemy = engineEnemy, pos = engineEnemy:GetPos() })
                    CAI.Squad.Broadcast(data.squad, "need_help", npc,
                        { pos = engineEnemy:GetPos() })
                end
            end
        else
            local rec = data.memory.enemies[engineEnemy]
            if not rec or (rec.heardOnly and CurTime() - rec.t > 1.0) then
                CAI.Memory.HearEnemy(data, engineEnemy, engineEnemy:GetPos())
            end
        end
    end

    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 and not data.saidReload then
        data.saidReload = true
        CAI.Voice.Speak(data, "reload")
        if data.squad then CAI.Squad.Broadcast(data.squad, "reloading", npc) end
        CAI.Morale.Add(data, CAI.Config.Morale.OutOfAmmoClip, "empty_clip")
    elseif IsValid(wep) and wep.Clip1 and wep:Clip1() > 0 then
        data.saidReload = false
    end

    CAI.Morale.CheckHealth(data)
end
