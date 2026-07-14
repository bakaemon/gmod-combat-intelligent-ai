CAI.Sound = CAI.Sound or {}
local SND = CAI.Sound

function SND.Classify(name, level)
    name = string.lower(name or "")
    for _, p in ipairs(CAI.Config.SoundPatterns) do
        if name:find(p.pattern, 1, true) then
            local radius = p.radius

            if p.type == "gunshot" and (name:find("silenc") or name:find("suppress") or (level or 75) < 70) then
                radius = radius * CAI.Config.SuppressedGunshotMult
            end
            return p.type, radius
        end
    end
    return nil
end

function SND.Emit(pos, stype, radius, source)

    if IsValid(source) and source:IsPlayer() and not CAI.Util.IsTargetable(source) then return end
    for npc, data in pairs(CAI.Manager.All()) do
        if IsValid(npc) and npc:GetPos():DistToSqr(pos) < radius * radius then
            local dominated = IsValid(source) and npc:Disposition(source) ~= D_HT and stype ~= "explosion"
            if dominated and IsValid(source) and source:IsNPC()
               and npc:Disposition(source) == D_LI
               and (stype == "gunshot" or stype == "explosion") then
                dominated = false
            end
            if not dominated then
                CAI.Memory.AddSound(data, pos, stype)
                if IsValid(source) and source:IsPlayer() then
                    if stype ~= "footstep" or npc:GetPos():DistToSqr(pos) < 250 * 250 then
                        CAI.Memory.HearEnemy(data, source, pos)
                    end
                end

                if IsValid(source) and source:IsNPC()
                   and npc:Disposition(source) == D_LI
                   and (stype == "gunshot" or stype == "explosion") then
                    CAI.Memory.AddSound(data, pos, "battle")
                end

                if data.state == CAI.STATE.IDLE or data.state == CAI.STATE.PATROL then
                    local urgent = stype == "gunshot" or stype == "explosion" or stype == "glass"
                        or (stype == "footstep" and npc:GetPos():DistToSqr(pos) < 300 * 300)
                    local recent = data.lastInvestigate
                    if urgent or not (recent and CurTime() - recent.t < 30
                            and pos:DistToSqr(recent.pos) < 150 * 150) then
                        data.investigatePos = pos
                        data.investigateUntil = CurTime() + 12
                        CAI.Brain.SetState(data, CAI.STATE.INVESTIGATE, "heard_" .. stype)
                    end
                end
            end
        end
    end
end

CAI.SafeHook("EntityEmitSound", "CAI_SoundIntel", function(t)
    if not CAI.Enabled() or not CAI.CVBool("cai_soundintel") then return end
    local src = t.Entity

    if not IsValid(src) then return end
    local class = src:GetClass()
    local isNPCWeapon = src:IsNPC() and CAI.Manager.Get(src) ~= nil
    if not (src:IsPlayer() or class:find("door") or class:find("prop_") or class:find("func_break") or isNPCWeapon) then
        return
    end
    if isNPCWeapon then
        local preType = SND.Classify(t.SoundName, t.SoundLevel)
        if preType ~= "gunshot" and preType ~= "explosion" then return end
    end

    if class == "prop_ragdoll" then
        local phys = src:GetPhysicsObject()
        if not IsValid(phys) or phys:GetVelocity():LengthSqr() < 150 * 150 then return end
    end
    local stype, radius = SND.Classify(t.SoundName, t.SoundLevel)
    if not stype then return end
    if stype == "footstep" and src:IsPlayer() and src.Crouching and src:Crouching() then return end

    local now = CurTime()
    src.CAI_LastSoundEvent = src.CAI_LastSoundEvent or 0
    if now - src.CAI_LastSoundEvent < 0.4 then return end
    src.CAI_LastSoundEvent = now
    SND.Emit(t.Pos or src:GetPos(), stype, radius, src:IsPlayer() and src or nil)
end)

CAI.SafeHook("PlayerFootstep", "CAI_Footsteps", function(ply, pos)
    if not CAI.Enabled() or not CAI.CVBool("cai_soundintel") then return end
    if ply:Crouching() then return end
    local now = CurTime()
    ply.CAI_LastFootEvent = ply.CAI_LastFootEvent or 0
    if now - ply.CAI_LastFootEvent < 0.6 then return end
    ply.CAI_LastFootEvent = now
    local radius = ply:IsSprinting() and 650 or 300
    SND.Emit(pos, "footstep", radius, ply)
end)

CAI.SafeHook("PlayerSwitchFlashlight", "CAI_Flashlight", function(ply, enabled)
    if not enabled then return end
    if not CAI.Enabled() or not CAI.CVBool("cai_flashlight") then return end
    if not CAI.Util.IsTargetable(ply) then return end
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        local pos = ply:GetPos()
        for npc, data in pairs(CAI.Manager.All()) do
            if IsValid(npc) and npc:Disposition(ply) == D_HT
               and npc:GetPos():DistToSqr(pos) < 1400 * 1400
               and CAI.Util.CanSee(npc, ply) then
                CAI.Memory.SeeEnemy(data, ply, pos)
                if data.squad then
                    CAI.Battlefield.ReportEnemy(data.squad, ply, pos, npc)
                end
            end
        end
    end)
end)

CAI.Prof.WrapFn(SND, "Emit", "sound_emit")
