CAI.Manager = CAI.Manager or {}
local MG = CAI.Manager

MG.NPCs = MG.NPCs or {}
MG.List = MG.List or {}
MG.ListIdx = MG.ListIdx or {}
MG.Count = MG.Count or table.Count(MG.NPCs)
if #MG.List == 0 and MG.Count > 0 then
    for npc in pairs(MG.NPCs) do
        MG.List[#MG.List + 1] = npc
        MG.ListIdx[npc] = #MG.List
    end
end

function MG.Get(npc) return MG.NPCs[npc] end
function MG.All() return MG.NPCs end

function MG.Register(npc)
    if not IsValid(npc) or MG.NPCs[npc] then return end
    if (MG.Count or 0) >= CAI.CVNum("cai_max_managed") then return end
    if not CAI.Config.NPCClasses[npc:GetClass()] then return end

    local classInfo = CAI.Config.NPCClasses[npc:GetClass()]
    local faction = classInfo and classInfo.faction or "custom"
    if classInfo and classInfo.vj then
        local c = istable(npc.VJ_NPC_Class) and npc.VJ_NPC_Class[1]
        if isstring(c) then
            faction = ({ CLASS_COMBINE = "combine", CLASS_PLAYER_ALLY = "resistance" })[c]
                      or string.lower((string.gsub(c, "^CLASS_", "")))
        else
            faction = "vj"
        end
    end
    local mdl = string.lower(npc:GetModel() or "")
    local data = {
        ent = npc,
        faction = faction,
        voiceGender = (mdl:find("female", 1, true) or mdl:find("alyx", 1, true)
                       or mdl:find("mossman", 1, true)) and "female" or "male",
        personality = CAI.Personality.Generate(classInfo and classInfo.traits),
        memory = CAI.Memory.New(),
        morale = CAI.Config.Morale.Start + math.random(-10, 10),
        suppression = 0,
        state = CAI.STATE.IDLE,
        stateSince = CurTime(),
        nextThink = CurTime() + math.Rand(0, 0.3),
        lastThink = CurTime(),
        lastDecision = "registered",
        clearingDoor = nil,
        boundTarget = nil,
        wantBound = nil,
        boundArrived = nil,
        reinforceTarget = nil,
        staggerOffset = nil,
        staggerCovering = nil,
        combatTarget = nil,
        combatRec = nil,
        patrolHistory = nil,
        patrolTarget = nil,
        clearPhase = nil,
        clearAngle = nil,
        clearSliceStart = nil,
    }
    if data.faction == "combine" then
        pcall(function() npc:SetSaveValue("m_iNumGrenades", 2) end)
    end
    if CAI.CVBool("cai_simfire") then
        pcall(function() npc:SetKeyValue("squadname", "cai_solo_" .. npc:EntIndex()) end)
    end
    MG.NPCs[npc] = data
    MG.Count = (MG.Count or 0) + 1
    MG.List[#MG.List + 1] = npc
    MG.ListIdx[npc] = #MG.List

    CAI.Nav.EnableDoorUse(npc)
    CAI.Squad.Place(npc)

    npc:CallOnRemove("CAI_Unregister", function() MG.Unregister(npc) end)
end

function MG.Unregister(npc)
    local idx = MG.ListIdx[npc]
    if idx then
        local lastN = #MG.List
        local lastEnt = MG.List[lastN]
        MG.List[idx] = lastEnt
        MG.List[lastN] = nil
        if lastEnt ~= nil then MG.ListIdx[lastEnt] = idx end
        MG.ListIdx[npc] = nil
    end
    local data = MG.NPCs[npc]
    if not data then return end
    MG.Count = math.max(0, (MG.Count or 1) - 1)
    if IsValid(data.suppBullseye) then data.suppBullseye:Remove() end
    if IsValid(data.flashlight) then data.flashlight:Remove() end
    if IsValid(data.flashglow) then data.flashglow:Remove() end
    if data.squad then CAI.Squad.RemoveMember(data.squad, npc) end
    MG.NPCs[npc] = nil
end

CAI.SafeHook("OnEntityCreated", "CAI_Register", function(ent)
    timer.Simple(0.1, function()
        if IsValid(ent) and ent:IsNPC() and CAI.Enabled() then
            MG.Register(ent)
        end
    end)
end)

CAI.SafeHook("OnNPCKilled", "CAI_UnregisterDead", function(npc)
    MG.Unregister(npc)
end)

hook.Add("InitPostEntity", "CAI_NavCheck", function()
    timer.Simple(3, function()
        if navmesh.GetNavAreaCount() == 0 then
            print(CAI.PrintPrefix .. "This map has no navmesh so the AI will be a bit more basic. Type nav_generate in console (with sv_cheats 1) to fix that.")
        end
    end)
end)

hook.Add("InitPostEntity", "CAI_AdoptExisting", function()
    timer.Simple(1, function()
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent:IsNPC() then MG.Register(ent) end
        end
    end)
end)

local cvAIDisabled
timer.Create("CAI_Scheduler", CAI.Config.ManagerTickRate, 0, function()
    if not CAI.Enabled() then return end

    cvAIDisabled = cvAIDisabled or GetConVar("ai_disabled")
    if cvAIDisabled and cvAIDisabled:GetBool() then return end

    local now = CurTime()
    local _ts = CAI.Prof.active and SysTime() or 0
    local budget = CAI.Config.MaxBrainThinksPerTick
    if CAI.CVBool("cai_performance_mode") then budget = math.max(6, budget - 4) end

    local list = MG.List
    local count = 0
    local steps = #list
    MG.rr = MG.rr or 0
    for _ = 1, steps do
        if #list == 0 then break end
        MG.rr = MG.rr % #list + 1
        local npc = list[MG.rr]
        local data = npc ~= nil and MG.NPCs[npc] or nil
        if not IsValid(npc) or not data then
            if npc ~= nil then MG.Unregister(npc) end
        elseif now >= data.nextThink then
            local t0 = SysTime()
            local dt = now - data.lastThink
            data.lastThink = now

            local ok, err = pcall(CAI.Brain.Think, data, dt)
            if not ok then
                ErrorNoHaltWithStack(CAI.PrintPrefix .. "brain error: " .. tostring(err))
            end

            local interval = CAI.Perf.GetThinkInterval(npc)

            local diffSpeed = math.Clamp(CAI.Difficulty(), 0.5, 1.35)
            interval = interval / diffSpeed
            data.nextThink = now + interval
            data.lodInterval = interval

            CAI.Perf.RecordThink((SysTime() - t0) * 1000)
            count = count + 1
            if count >= budget then break end
        end
    end
    CAI.Perf.Stats.managed = MG.Count or 0
    if _ts ~= 0 then CAI.Prof.Record("manager_scheduler", SysTime() - _ts) end
end)

cvars.AddChangeCallback("cai_enabled", function(_, _, new)
    if new == "0" then
        for npc, data in pairs(MG.NPCs) do
            if IsValid(npc) then npc:SetSchedule(SCHED_IDLE_STAND) end
        end
        print(CAI.PrintPrefix .. "Turned off. NPCs are back to normal now.")
    end
end, "CAI_Toggle")