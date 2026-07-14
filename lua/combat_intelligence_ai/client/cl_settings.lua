local function Send(cvar, val)
    net.Start(CAI.Net.Settings)
    net.WriteString(cvar)
    net.WriteString(tostring(val))
    net.SendToServer()
end

local function AddCheck(panel, label, cvar)
    local cb = panel:CheckBox(label)
    local cv = GetConVar(cvar)
    if cv then cb:SetChecked(cv:GetBool()) end
    function cb:OnChange(checked)
        Send(cvar, checked and "1" or "0")
    end
    cb:SetTooltip(cvar)
    return cb
end

local function AddSlider(panel, label, cvar, minV, maxV, decimals)
    local sl = panel:NumSlider(label, nil, minV, maxV, decimals)
    local cv = GetConVar(cvar)
    if cv then sl:SetValue(cv:GetFloat()) end
    local pending
    function sl:OnValueChanged(v)

        if pending then timer.Remove(pending) end
        pending = "CAI_Set_" .. cvar
        timer.Create(pending, 0.25, 1, function()
            Send(cvar, decimals == 0 and math.Round(v) or math.Round(v, decimals))
        end)
    end
    sl:SetTooltip(cvar)
    return sl
end

local function BuildPanel(panel)
    panel:ClearControls()

    if not LocalPlayer():IsAdmin() then
        panel:Help("You need admin to change these settings.")
        panel:Help("(Current values are shown read-only below.)")
    end

    panel:Help("Master")
    AddCheck(panel, "Enable Combat Intelligence AI", "cai_enabled")
    do
        local opts = {
            { "Easy", 0.6 },
            { "Normal", 1.0 },
            { "Hard", 1.4 },
            { "Very Hard", 1.7 },
            { "Nightmare", 2.0 },
        }
        local combo = panel:ComboBox("Difficulty")
        local cv = GetConVar("cai_difficulty")
        local cur = cv and cv:GetFloat() or 1
        local best, bestDiff = 2, math.huge
        for i, o in ipairs(opts) do
            combo:AddChoice(o[1], o[2])
            local d = math.abs(o[2] - cur)
            if d < bestDiff then best, bestDiff = i, d end
        end
        combo:ChooseOptionID(best)
        combo:SetTooltip("cai_difficulty")
        function combo:OnSelect(_, _, value)
            Send("cai_difficulty", value)
        end
    end
    AddSlider(panel, "Accuracy", "cai_accuracy", 0, 1, 2)
    AddSlider(panel, "Aggression", "cai_aggression", 0, 1, 2)

    panel:Help("Combat features")
    AddCheck(panel, "Smart cover", "cai_cover")
    AddCheck(panel, "Flanking", "cai_flanking")
    AddCheck(panel, "Searching (last known position)", "cai_search")
    AddCheck(panel, "Morale", "cai_morale")
    AddCheck(panel, "Suppression", "cai_suppression")
    AddCheck(panel, "Memory", "cai_memory")
    AddCheck(panel, "Weapon recognition", "cai_weaponintel")
    AddCheck(panel, "Sound intelligence", "cai_soundintel")
    AddCheck(panel, "Flashlights reveal players", "cai_flashlight")
    AddCheck(panel, "Darkness hides players", "cai_darkness")
    AddCheck(panel, "NPC flashlights in darkness", "cai_npc_flashlights")
    AddCheck(panel, "NPCs patrol (off = stay at post)", "cai_patrol")
    AddCheck(panel, "Simultaneous fire (no 2-shooter limit)", "cai_simfire")
    AddCheck(panel, "NPC health regen", "cai_npc_regen")
    AddCheck(panel, "Wallbang suppression (needs penetration mod)", "cai_wallbang")
    AddCheck(panel, "Cornered melee panic", "cai_meleepanic")

    panel:Help("Squads")
    AddCheck(panel, "Squad comms & shared knowledge", "cai_comms")
    AddCheck(panel, "Formations", "cai_formations")
    AddCheck(panel, "Friendly fire avoidance", "cai_friendlyfire_avoid")

    panel:Help("Voice")
    AddCheck(panel, "Voice lines", "cai_voice")
    AddSlider(panel, "Volume", "cai_voice_volume", 0, 1, 2)
    AddSlider(panel, "Chance to speak", "cai_voice_chance", 0, 1, 2)
    AddSlider(panel, "Per-NPC cooldown (s)", "cai_voice_cooldown", 0, 20, 1)
    AddSlider(panel, "Max audible distance", "cai_voice_maxdist", 500, 4000, 0)

    panel:Help("Performance")
    AddCheck(panel, "Performance mode (huge battles)", "cai_performance_mode")
    AddSlider(panel, "Max managed NPCs", "cai_max_managed", 10, 300, 0)

    panel:Help("Debug (admins)")
    AddCheck(panel, "Debug overlay", "cai_debug")
    AddCheck(panel, "Debug rays", "cai_debug_rays")

    local btn = panel:Button("Print AI stats to console (cai_dump)")
    function btn:DoClick() RunConsoleCommand("cai_dump") end
end

hook.Add("PopulateToolMenu", "CAI_SettingsMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Combat Intelligence AI", "cai_settings",
        "Settings", "", "", BuildPanel)
end)
