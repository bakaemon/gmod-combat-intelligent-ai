net.Receive(CAI.Net.Settings, function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local cvar = net.ReadString()
    local val = net.ReadString()

    if not string.StartsWith(cvar, "cai_") then return end
    if not ConVarExists(cvar) then return end

    if not tonumber(val) then return end

    RunConsoleCommand(cvar, val)
end)
