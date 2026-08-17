CAI.WeaponLight = CAI.WeaponLight or {}
local WL = CAI.WeaponLight

local MOUNT_OFFSET = Vector(-1, 0, -2)
local NOMUZZLE_OFFSET = Vector(12, 0, 0)

local function FindMuzzle(npc)
    local wep = npc:GetActiveWeapon()
    if not IsValid(wep) then return nil, 0 end

    local id = wep:LookupAttachment("muzzle")
    if not id or id <= 0 then id = wep:LookupAttachment("muzzle_flash") end
    if not id or id <= 0 then id = wep:LookupAttachment("1") end

    return wep, (id and id > 0) and id or 0
end

local function Attach(npc, ent, data)
    local wep, id = FindMuzzle(npc)
    if not IsValid(wep) then return false end

    if id > 0 then
        ent:SetParent(wep, id)
        ent:SetLocalPos(MOUNT_OFFSET)
    else
        ent:SetParent(wep)
        ent:SetLocalPos(NOMUZZLE_OFFSET)
    end

    ent:SetLocalAngles(angle_zero)
    data.lightWep = wep
    return true
end

function WL.On(npc, data)
    if not IsValid(npc) then return end
    if IsValid(data.flashlight) then return end
    if not IsValid(npc:GetActiveWeapon()) then return end

    local pt = ents.Create("env_projectedtexture")
    if not IsValid(pt) then return end

    pt:SetKeyValue("enableshadows", CAI.CVBool("cai_npc_light_shadows") and "1" or "0")
    pt:SetKeyValue("lightfov", tostring(math.Clamp(CAI.CVNum("cai_npc_light_fov"), 15, 120)))
    pt:SetKeyValue("texturename", "effects/flashlight001")
    pt:SetKeyValue("lightcolor", "255 244 214 200")
    pt:SetKeyValue("nearz", "6")
    pt:SetKeyValue("farz", "1100")
    pt:SetKeyValue("ambient", "0")
    pt:Spawn()

    if not Attach(npc, pt, data) then
        pt:Remove()
        data.lightToggleAt = CurTime()
        return
    end

    pt:Fire("TurnOn")

    data.flashlight = pt
    data.lightToggleAt = CurTime()

    npc:CallOnRemove("CAI_Flashlight_" .. npc:EntIndex(), function()
        if IsValid(pt) then pt:Remove() end
    end)
end

function WL.Off(data)
    if IsValid(data.flashlight) then data.flashlight:Remove() end
    data.flashlight = nil
    data.lightWep = nil
    data.lightToggleAt = CurTime()
end

function WL.Refresh(npc, data)
    if not IsValid(data.flashlight) then return end
    if not IsValid(npc) then return end

    local wep = npc:GetActiveWeapon()
    if data.lightWep == wep then return end

    if not IsValid(wep) then
        WL.Off(data)
        return
    end

    Attach(npc, data.flashlight, data)
end