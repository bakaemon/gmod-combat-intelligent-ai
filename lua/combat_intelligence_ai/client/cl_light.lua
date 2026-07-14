local nextSend = 0
hook.Add("Think", "CAI_LightReport", function()
    if CurTime() < nextSend then return end
    nextSend = CurTime() + 0.5
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local c = render.GetLightColor(ply:EyePos())
    local level = math.Clamp((c.x + c.y + c.z) / 3, 0, 1)
    net.Start(CAI.Net.Light)
    net.WriteFloat(level)
    net.SendToServer()
end)
