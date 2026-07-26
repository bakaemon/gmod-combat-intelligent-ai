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

Server("server/meta/sv_performance.lua")
Server("server/meta/sv_personality.lua")
Server("server/meta/sv_debug.lua")
Server("server/meta/sv_settings.lua")
Server("server/meta/sv_vjsupport.lua")
Server("server/perception/sv_memory.lua")
Server("server/perception/sv_sound.lua")
Server("server/perception/sv_weaponintel.lua")
Server("server/perception/sv_target.lua")
Server("server/perception/sv_weaponlight.lua")
Server("server/perception/sv_darkness.lua")
Server("server/sv_battlefield.lua")
Server("server/movement/sv_navigation.lua")
Server("server/movement/sv_cover.lua")
Server("server/movement/sv_spatialmap.lua")
Server("server/movement/sv_search.lua")
Server("server/combat/sv_suppression.lua")
Server("server/combat/sv_morale.lua")
Server("server/combat/sv_voice.lua")
Server("server/combat/sv_friendlyfire.lua")
Server("server/sv_squad.lua")
Server("server/sv_brain.lua")
Server("server/sv_fireaim.lua")
Server("server/sv_manager.lua")

Client("client/debug/cl_debug_style.lua")
Client("client/debug/cl_debug_net.lua")
Client("client/debug/cl_debug_badge.lua")
Client("client/debug/cl_debug_world.lua")
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
