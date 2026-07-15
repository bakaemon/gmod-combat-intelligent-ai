CAI = CAI or {}
CAI.Version = "0.1.4"
CAI.Build = "2026-07-13"
CAI.PrintPrefix = "[Combat Intelligence AI] "

local BASE = "combat_intelligence_ai/"

local function Shared(f)
    if SERVER then AddCSLuaFile(BASE .. f) end
    include(BASE .. f)
end

local function Server(f)
    if SERVER then include(BASE .. f) end
end

local function Client(f)
    if SERVER then AddCSLuaFile(BASE .. f) else include(BASE .. f) end
end

Shared("shared/sh_config.lua")
Shared("shared/sh_convars.lua")
Shared("shared/sh_util.lua")
Shared("shared/sh_net.lua")
Shared("shared/sh_text.lua")

Server("server/sv_performance.lua")
Server("server/sv_personality.lua")
Server("server/sv_memory.lua")
Server("server/sv_battlefield.lua")
Server("server/sv_navigation.lua")
Server("server/sv_cover.lua")
Server("server/sv_suppression.lua")
Server("server/sv_sound.lua")
Server("server/sv_weaponintel.lua")
Server("server/sv_target.lua")
Server("server/sv_morale.lua")
Server("server/sv_voice.lua")
Server("server/sv_squad.lua")
Server("server/sv_spatialmap.lua")
Server("server/sv_search.lua")
Server("server/sv_friendlyfire.lua")
Server("server/sv_brain.lua")
Server("server/sv_manager.lua")
Server("server/sv_debug.lua")
Server("server/sv_settings.lua")
Server("server/sv_vjsupport.lua")
Server("server/sv_darkness.lua")

Client("client/cl_debug.lua")
Client("client/cl_settings.lua")
Client("client/cl_vjsettings.lua")
Client("client/cl_light.lua")

if SERVER then
    print(CAI.PrintPrefix .. "v" .. CAI.Version .. " loaded (server).")

    hook.Add("InitPostEntity", "CAI_StartupMessage", function()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:IsAdmin() then
                ply:ChatPrint(CAI.PrintPrefix .. "v" .. CAI.Version .. " active. Type !cai in chat or use cai_settings in the Options menu.")
            end
        end
    end)
else
    print(CAI.PrintPrefix .. "v" .. CAI.Version .. " loaded (client).")
end
