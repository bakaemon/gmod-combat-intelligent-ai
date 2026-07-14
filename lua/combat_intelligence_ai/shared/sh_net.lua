CAI.Net = {
    Debug = "CAI_DebugSnapshot",
    Settings = "CAI_Settings",
    VJList = "CAI_VJList",
    VJToggle = "CAI_VJToggle",
    Light = "CAI_Light",
}

if SERVER then
    util.AddNetworkString(CAI.Net.Debug)
    util.AddNetworkString(CAI.Net.Settings)
    util.AddNetworkString(CAI.Net.VJList)
    util.AddNetworkString(CAI.Net.VJToggle)
    util.AddNetworkString(CAI.Net.Light)
end
