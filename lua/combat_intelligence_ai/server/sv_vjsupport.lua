CAI.VJ = CAI.VJ or {}
local VJ = CAI.VJ

VJ.Detected = VJ.Detected or {}
VJ.Enabled = VJ.Enabled or {}

local DATA_DIR = "combat_intelligence_ai"
local DATA_FILE = DATA_DIR .. "/vj_classes.txt"

local function IsVJClass(cls)
    if string.find(cls, "npc_vj_", 1, true) == 1 then return true end
    local seen, cur, depth = {}, scripted_ents.GetStored(cls), 0
    while cur and depth < 12 do
        local t = cur.t
        if t and t.IsVJBaseSNPC then return true end
        local base = t and t.Base
        if not base or seen[base] then break end
        if string.find(tostring(base), "vj_", 1, true) then return true end
        seen[base] = true
        cur = scripted_ents.GetStored(base)
        depth = depth + 1
    end
    return false
end

function VJ.Detect()
    VJ.Detected = {}
    for _, entry in pairs(list.Get("NPC")) do
        local cls = entry.Class
        if isstring(cls) and not CAI.Config.NPCClasses[cls] and IsVJClass(cls) then
            VJ.Detected[cls] = {
                name = entry.Name or cls,
                category = entry.Category or "VJ Base",
            }
        end
    end
end

function VJ.Load()
    if not file.Exists(DATA_FILE, "DATA") then return end
    local tbl = util.JSONToTable(file.Read(DATA_FILE, "DATA") or "")
    if istable(tbl) then VJ.Enabled = tbl end
end

function VJ.Save()
    file.CreateDir(DATA_DIR)
    file.Write(DATA_FILE, util.TableToJSON(VJ.Enabled))
end

local function AdoptClass(cls)
    local n = 0
    for _, e in ipairs(ents.FindByClass(cls)) do
        if IsValid(e) then
            CAI.Manager.Register(e)
            if CAI.Manager.Get(e) then n = n + 1 end
        end
    end
    print(CAI.PrintPrefix .. "Turned on " .. cls .. " - took over " .. n .. " that were already spawned.")
end

local function ReleaseClass(cls)
    for _, e in ipairs(ents.FindByClass(cls)) do
        if IsValid(e) then CAI.Manager.Unregister(e) end
    end
end

function VJ.Apply()
    local on = CAI.CVBool("cai_vj_enabled")
    for cls in pairs(VJ.Detected) do
        local want = on and VJ.Enabled[cls] == true
        local have = CAI.Config.NPCClasses[cls] ~= nil
        if want and not have then
            CAI.Config.NPCClasses[cls] = { vj = true, faction = "vj" }
            AdoptClass(cls)
        elseif have and not want and CAI.Config.NPCClasses[cls]
               and CAI.Config.NPCClasses[cls].vj then
            CAI.Config.NPCClasses[cls] = nil
            ReleaseClass(cls)
        end
    end
end

function VJ.SetClass(cls, enabled)
    if not VJ.Detected[cls] then return end
    VJ.Enabled[cls] = enabled and true or nil
    VJ.Save()
    VJ.Apply()
end

hook.Add("InitPostEntity", "CAI_VJDetect", function()
    timer.Simple(2, function()
        VJ.Load()
        VJ.Detect()
        VJ.Apply()
        local n = table.Count(VJ.Detected)
        if n > 0 then
            print(CAI.PrintPrefix .. "Found " .. n .. " VJ Base NPC types. You can turn them on in the Options menu if you want.")
        end
    end)
end)

cvars.AddChangeCallback("cai_vj_enabled", function()
    VJ.Apply()
end, "CAI_VJMaster")

net.Receive(CAI.Net.VJList, function(_, ply)
    if not IsValid(ply) then return end
    local out = {}
    for cls, info in pairs(VJ.Detected) do
        out[#out + 1] = {
            class = cls,
            name = info.name,
            category = info.category,
            enabled = VJ.Enabled[cls] == true,
        }
    end
    local json = util.Compress(util.TableToJSON(out))
    net.Start(CAI.Net.VJList)
    net.WriteUInt(#json, 32)
    net.WriteData(json, #json)
    net.Send(ply)
end)

net.Receive(CAI.Net.VJToggle, function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local cls = net.ReadString()
    local on = net.ReadBool()
    VJ.SetClass(cls, on)
end)

concommand.Add("cai_vj_list", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    print(CAI.PrintPrefix .. "VJ NPCs found on this server:")
    for cls, info in SortedPairs(VJ.Detected) do
        print(string.format("  [%s] %s  (%s)", VJ.Enabled[cls] and "ON " or "off", cls, info.name))
    end
end)
