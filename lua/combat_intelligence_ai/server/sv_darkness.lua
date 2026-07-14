net.Receive(CAI.Net.Light, function(_, ply)
    if not IsValid(ply) then return end
    local now = CurTime()
    if (ply.CAI_LightAt or 0) + 0.4 > now then return end
    ply.CAI_LightAt = now
    ply.CAI_Light = math.Clamp(net.ReadFloat() or 1, 0, 1)
end)

local function PlayerLight(ply)
    if ply.FlashlightIsOn and ply:FlashlightIsOn() then return 1 end
    return ply.CAI_Light or 1
end
CAI.PlayerLight = PlayerLight

function CAI.ApplyDarknessVision(data)
    local npc = data.ent
    if not npc.SetMaxLookDistance then return end
    if not data.baseLookDist then
        local base = npc.GetMaxLookDistance and npc:GetMaxLookDistance()
        if not base or base < 600 then base = 2048 end
        data.baseLookDist = base
    end
    if not CAI.CVBool("cai_darkness") then
        npc:SetMaxLookDistance(data.baseLookDist)
        return
    end
    local ply = CAI.Util.NearestPlayer(npc:GetPos())
    if not IsValid(ply) then return end
    local light = PlayerLight(ply)
    local dist = Lerp(math.Clamp(light * 2.2, 0, 1), 400, data.baseLookDist)
    npc:SetMaxLookDistance(dist)
end

local MAX_LIGHTS = 8

local externalLights
local function HasExternalFlashlights()
    if externalLights == nil then
        externalLights = false
        for _, a in ipairs(engine.GetAddons()) do
            if a.mounted and string.find(string.lower(a.title or ""), "dynamic combine flashlight", 1, true) then
                externalLights = true
                break
            end
        end
    end
    return externalLights
end

local function LightOn(npc, data)
    if IsValid(data.flashlight) then return end
    local l = ents.Create("light_dynamic")
    if not IsValid(l) then return end
    l:SetPos(npc:GetPos() + Vector(0, 0, 58))
    l:SetKeyValue("brightness", "1")
    l:SetKeyValue("distance", "380")
    l:SetKeyValue("_light", "255 245 215 255")
    l:SetKeyValue("style", "0")
    l:Spawn()
    l:SetParent(npc)
    l:SetLocalPos(Vector(14, 0, 58))
    l:Fire("TurnOn")
    data.flashlight = l
    data.lightToggleAt = CurTime()
    npc:CallOnRemove("CAI_Flashlight_" .. npc:EntIndex(), function()
        if IsValid(l) then l:Remove() end
    end)
end

local function LightOff(data)
    if IsValid(data.flashlight) then data.flashlight:Remove() end
    data.flashlight = nil
    data.lightToggleAt = CurTime()
end
CAI.NPCLightOff = LightOff

local function CanToggle(data)
    return CurTime() - (data.lightToggleAt or 0) > 4
end

timer.Create("CAI_NPCFlashlights", 0.5, 0, CAI.Prof.Wrap("darkness_flashlights", function()
    if not CAI.Enabled() or not CAI.CVBool("cai_npc_flashlights") or not CAI.CVBool("cai_darkness") or HasExternalFlashlights() then
        for _, data in pairs(CAI.Manager.All()) do
            if IsValid(data.flashlight) then LightOff(data) end
        end
        return
    end
    local cands = {}
    for npc, data in pairs(CAI.Manager.All()) do
        if IsValid(npc) then
            local ci = CAI.Config.NPCClasses[npc:GetClass()]
            local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
            if ci and not ci.lightTouch and not ci.noCover
               and IsValid(wep) and not CAI.WeaponIntel.IsMelee(npc) then
                local ply = CAI.Util.NearestPlayer(npc:GetPos())
                local want = false
                if IsValid(ply) then
                    local d = npc:GetPos():DistToSqr(ply:GetPos())
                    local light = PlayerLight(ply)
                    local lit = IsValid(data.flashlight)
                    if d < 2200 * 2200 and data.state ~= CAI.STATE.IDLE then
                        if lit then
                            want = light < 0.45
                        else
                            want = light < 0.30
                        end
                    end
                    if want then
                        cands[#cands + 1] = { data = data, d = lit and d * 0.6 or d }
                    end
                end
                if not want and IsValid(data.flashlight) and CanToggle(data) then
                    LightOff(data)
                end
            elseif IsValid(data.flashlight) then
                LightOff(data)
            end
        end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)
    for i, c in ipairs(cands) do
        if i <= MAX_LIGHTS then
            if not IsValid(c.data.flashlight) and CanToggle(c.data) then
                LightOn(c.data.ent, c.data)
            end
        elseif IsValid(c.data.flashlight) and CanToggle(c.data) then
            LightOff(c.data)
        end
    end
end))
