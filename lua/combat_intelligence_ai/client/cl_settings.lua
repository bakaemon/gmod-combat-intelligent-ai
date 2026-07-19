local uiModern = CreateClientConVar("cai_ui_modern", "0", true, false, "Use the modern dark UI for the CAI settings panel")

local ACCENT    = Color(235, 120, 35)
local HEADER_BG = Color(38, 38, 43)
local BODY_BG   = Color(50, 50, 56)
local ROW_HOVER = Color(60, 60, 68)
local TEXT      = Color(235, 235, 235)
local SUBTEXT   = Color(165, 165, 172)

surface.CreateFont("CAI_Title",  { font = "Roboto", size = 19, weight = 800 })
surface.CreateFont("CAI_Header", { font = "Roboto", size = 15, weight = 700 })
surface.CreateFont("CAI_Label",  { font = "Roboto", size = 14, weight = 500 })
surface.CreateFont("CAI_Small",  { font = "Roboto", size = 12, weight = 400 })

local function Send(cvar, val)
    net.Start(CAI.Net.Settings)
    net.WriteString(cvar)
    net.WriteString(tostring(val))
    net.SendToServer()
end

local tracked = {}
local function Track(cvar)
    if not table.HasValue(tracked, cvar) then table.insert(tracked, cvar) end
end

local BuildPanel

-- Modern Style!

-- Collapsible category
local function Section(panel, title, expanded)
    local cat = vgui.Create("DCollapsibleCategory")
    cat:SetLabel("")
    cat:SetExpanded(expanded ~= false)
    cat.Header:SetTall(28)
    cat:DockMargin(0, 0, 0, 6)

    cat.Paint = function(_, w, h)
        if cat:GetExpanded() and h > 29 then
            draw.RoundedBoxEx(6, 0, 28, w, h - 28, BODY_BG, false, false, true, true)
        end
    end
    cat.Header.Paint = function(_, w, h)
        local open = cat:GetExpanded()
        draw.RoundedBoxEx(6, 0, 0, w, h, HEADER_BG, true, true, not open, not open)
        surface.SetDrawColor(ACCENT)
        surface.DrawRect(0, 0, 3, h)
        draw.SimpleText(title, "CAI_Header", 12, h / 2, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(open and "–" or "+", "CAI_Header", w - 12, h / 2, SUBTEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DListLayout")
    cat:SetContents(body)

    local pad = vgui.Create("DPanel")
    pad:SetTall(6)
    pad.Paint = nil
    body.FinishUp = function()
        body:Add(pad)
    end

    panel:AddItem(cat)
    return body
end

-- Rows
local function AddCheck(body, label, cvar)
    Track(cvar)
    local row = vgui.Create("DPanel")
    row:SetTall(24)
    row:DockMargin(10, 4, 10, 0)
    row.Paint = function(s, w, h)
        if s:IsHovered() or (s.cb and s.cb:IsHovered()) then
            draw.RoundedBox(4, -4, 0, w + 8, h, ROW_HOVER)
        end
    end

    local cb = vgui.Create("DCheckBoxLabel", row)
    cb:Dock(FILL)
    cb:SetText(label)
    cb:SetFont("CAI_Label")
    cb:SetTextColor(TEXT)
    cb:SetTooltip(cvar)
    row.cb = cb

    local cv = GetConVar(cvar)
    if cv then cb:SetChecked(cv:GetBool()) end
    function cb:OnChange(checked)
        Send(cvar, checked and "1" or "0")
    end

    body:Add(row)
    return cb
end

local function AddSlider(body, label, cvar, minV, maxV, decimals)
    Track(cvar)
    local sl = vgui.Create("DNumSlider")
    sl:SetTall(28)
    sl:DockMargin(10, 2, 10, 0)
    sl:SetText(label)
    sl:SetMin(minV)
    sl:SetMax(maxV)
    sl:SetDecimals(decimals)
    sl:SetTooltip(cvar)
    if IsValid(sl.Label) then
        sl.Label:SetFont("CAI_Label")
        sl.Label:SetTextColor(TEXT)
    end
    if IsValid(sl.TextArea) then
        sl.TextArea:SetFont("CAI_Label")
        sl.TextArea:SetTextColor(TEXT)
    end

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

    body:Add(sl)
    return sl
end

local function AddNote(body, text)
    local lbl = vgui.Create("DLabel")
    lbl:SetText(text)
    lbl:SetFont("CAI_Small")
    lbl:SetTextColor(SUBTEXT)
    lbl:SetWrap(true)
    lbl:SetAutoStretchVertical(true)
    lbl:DockMargin(12, 4, 12, 0)
    body:Add(lbl)
    return lbl
end

-- Difficutly chooser
local DIFFICULTIES = {
    { "Easy",      0.6, Color(95, 180, 95)  },
    { "Normal",    1.0, Color(110, 155, 220) },
    { "Hard",      1.4, Color(230, 175, 60) },
    { "Very Hard", 1.7, Color(232, 120, 60) },
    { "Nightmare", 2.0, Color(220, 75, 75)  },
}

local function AddDifficulty(body)
    Track("cai_difficulty")
    local row = vgui.Create("DPanel")
    row:SetTall(46)
    row:DockMargin(10, 4, 10, 0)
    row.Paint = nil

    local lbl = vgui.Create("DLabel", row)
    lbl:Dock(TOP)
    lbl:SetTall(16)
    lbl:SetText("Difficulty")
    lbl:SetFont("CAI_Label")
    lbl:SetTextColor(TEXT)

    local holder = vgui.Create("DPanel", row)
    holder:Dock(FILL)
    holder:DockMargin(0, 2, 0, 2)
    holder.Paint = nil

    local cv = GetConVar("cai_difficulty")
    local cur = cv and cv:GetFloat() or 1
    local selected, bestDiff = 2, math.huge
    for i, o in ipairs(DIFFICULTIES) do
        local d = math.abs(o[2] - cur)
        if d < bestDiff then selected, bestDiff = i, d end
    end

    local btns = {}
    for i, o in ipairs(DIFFICULTIES) do
        local b = vgui.Create("DButton", holder)
        b:SetText("")
        b:SetTooltip(("cai_difficulty %s"):format(o[2]))
        b.Paint = function(s, w, h)
            local sel = (selected == i)
            local col = sel and o[3] or (s:IsHovered() and ROW_HOVER or HEADER_BG)
            draw.RoundedBoxEx(4, 0, 0, w - 2, h, col, i == 1, i == 1, i == #DIFFICULTIES, i == #DIFFICULTIES)
            draw.SimpleText(o[1], "CAI_Small", (w - 2) / 2, h / 2,
                sel and Color(255, 255, 255) or SUBTEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function()
            selected = i
            Send("cai_difficulty", o[2])
        end
        btns[i] = b
    end
    holder.PerformLayout = function(s, w, h)
        local bw = w / #btns
        for i, b in ipairs(btns) do
            b:SetPos((i - 1) * bw, 0)
            b:SetSize(bw, h)
        end
    end

    body:Add(row)
end

-- Buttons
local function StyledButton(bodyOrPanel, label, isForm, onClick)
    local b = vgui.Create("DButton")
    b:SetText("")
    b:SetTall(26)
    b:DockMargin(10, 6, 10, 2)
    b.Paint = function(s, w, h)
        draw.RoundedBox(5, 0, 0, w, h, s:IsHovered() and ACCENT or HEADER_BG)
        draw.SimpleText(label, "CAI_Label", w / 2, h / 2,
            s:IsHovered() and Color(255, 255, 255) or TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = onClick
    if isForm then bodyOrPanel:AddItem(b) else bodyOrPanel:Add(b) end
    return b
end

-- OG STYLE!!!!!

-- Collapsible OG
local function OGSection(panel, title, expanded)
    local form = vgui.Create("DForm")
    form:SetName(title)
    form:SetExpanded(expanded ~= false)
    form:DockMargin(0, 0, 0, 4)
    panel:AddItem(form)
    return form
end

local function OGAddCheck(panel, label, cvar)
    Track(cvar)
    local cb = panel:CheckBox(label)
    local cv = GetConVar(cvar)
    if cv then cb:SetChecked(cv:GetBool()) end
    function cb:OnChange(checked)
        Send(cvar, checked and "1" or "0")
    end
    cb:SetTooltip(cvar)
    return cb
end

local function OGAddSlider(panel, label, cvar, minV, maxV, decimals)
    Track(cvar)
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

-- Difficutly chooser (OG combo box version)
local function OGAddDifficulty(panel)
    Track("cai_difficulty")
    local combo = panel:ComboBox("Difficulty")
    local cv = GetConVar("cai_difficulty")
    local cur = cv and cv:GetFloat() or 1
    local best, bestDiff = 2, math.huge
    for i, o in ipairs(DIFFICULTIES) do
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

-- Shared portions and such :)

local function AddStyleToggle(panel)
    local cb = panel:CheckBox("Modern UI style")
    cb:SetChecked(uiModern:GetBool())
    cb:SetTooltip("cai_ui_modern (clientside, just for you)")
    function cb:OnChange(checked)
        uiModern:SetBool(checked)
        timer.Simple(0, function()
            if IsValid(panel) then BuildPanel(panel) end
        end)
    end
end

local function DoReset(panel)
    Derma_Query("Reset every Combat Intelligence AI setting to its default value?",
        "Combat Intelligence AI",
        "Reset", function()
            for _, cvar in ipairs(tracked) do
                local cv = GetConVar(cvar)
                if cv and cv.GetDefault then
                    Send(cvar, cv:GetDefault())
                end
            end
            timer.Simple(0.5, function()
                if IsValid(panel) then BuildPanel(panel) end
            end)
        end,
        "Cancel", function() end)
end

-- OG settings panel
local function BuildPanelOG(panel)
    if not LocalPlayer():IsAdmin() then
        panel:Help("You need admin to change these settings.")
        panel:Help("(Current values are shown read-only below.)")
    end

    AddStyleToggle(panel)

    local master = OGSection(panel, "Master", true)
    OGAddCheck(master, "Enable Combat Intelligence AI", "cai_enabled")
    OGAddDifficulty(master)
    OGAddSlider(master, "Accuracy", "cai_accuracy", 0, 1, 2)
    OGAddSlider(master, "Aggression", "cai_aggression", 0, 1, 2)

    -- Combat stuff
    local combat = OGSection(panel, "Combat features", true)
    OGAddCheck(combat, "Smart cover", "cai_cover")
    OGAddCheck(combat, "Flanking", "cai_flanking")
    OGAddCheck(combat, "Searching (last known position)", "cai_search")
    OGAddCheck(combat, "Morale", "cai_morale")
    OGAddCheck(combat, "Suppression", "cai_suppression")
    OGAddCheck(combat, "Memory", "cai_memory")
    OGAddCheck(combat, "Weapon recognition", "cai_weaponintel")
    OGAddCheck(combat, "Sound intelligence", "cai_soundintel")
    OGAddCheck(combat, "Cornered melee panic", "cai_meleepanic")
    OGAddCheck(combat, "Simultaneous fire (no 2-shooter limit)", "cai_simfire")
    OGAddCheck(combat, "NPC health regen", "cai_npc_regen")
    OGAddCheck(combat, "Wallbang suppression (needs penetration mod)", "cai_wallbang")

    -- Stealth And Lighting
    local stealth = OGSection(panel, "Stealth & light", false)
    OGAddCheck(stealth, "Darkness hides players", "cai_darkness")
    OGAddCheck(stealth, "Flashlights reveal players", "cai_flashlight")
    OGAddCheck(stealth, "NPC flashlights in darkness", "cai_npc_flashlights")
    OGAddCheck(stealth, "NPCs patrol (off = stay at post)", "cai_patrol")

    -- Squads
    local squads = OGSection(panel, "Squads", false)
    OGAddCheck(squads, "Squad comms & shared knowledge", "cai_comms")
    OGAddCheck(squads, "Formations", "cai_formations")
    OGAddCheck(squads, "Friendly fire avoidance", "cai_friendlyfire_avoid")

    -- Voice
    local voice = OGSection(panel, "Voice", false)
    OGAddCheck(voice, "Voice lines", "cai_voice")
    OGAddSlider(voice, "Volume", "cai_voice_volume", 0, 1, 2)
    OGAddSlider(voice, "Chance to speak", "cai_voice_chance", 0, 1, 2)
    OGAddSlider(voice, "Per-NPC cooldown (s)", "cai_voice_cooldown", 0, 20, 1)
    OGAddSlider(voice, "Max audible distance", "cai_voice_maxdist", 500, 4000, 0)

    -- Performance
    local perf = OGSection(panel, "Performance", false)
    OGAddCheck(perf, "Performance mode (huge battles)", "cai_performance_mode")
    OGAddSlider(perf, "Max managed NPCs", "cai_max_managed", 10, 300, 0)

    -- Debugs
    local debugS = OGSection(panel, "Debug (admins)", false)
    OGAddCheck(debugS, "Debug overlay", "cai_debug")
    OGAddCheck(debugS, "Debug rays", "cai_debug_rays")

    local btn = debugS:Button("Print AI stats to console (cai_dump)")
    function btn:DoClick() RunConsoleCommand("cai_dump") end

    -- Reset everything back
    local rst = panel:Button("Reset all settings to defaults")
    function rst:DoClick() DoReset(panel) end
end

-- Modern settings panel
local function BuildPanelModern(panel)
    -- Banner
    local banner = vgui.Create("DPanel")
    banner:SetTall(44)
    banner.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, HEADER_BG)
        surface.SetDrawColor(ACCENT)
        surface.DrawRect(0, 0, 3, h)
        draw.SimpleText("Combat Intelligence AI", "CAI_Title", 12, h / 2 - 8, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Server settings" .. (LocalPlayer():IsAdmin() and "" or "  •  admin required to change"),
            "CAI_Small", 12, h / 2 + 9, SUBTEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    panel:AddItem(banner)

    AddStyleToggle(panel)

    -- Master
    local master = Section(panel, "Master", true)
    AddCheck(master, "Enable Combat Intelligence AI", "cai_enabled")
    AddDifficulty(master)
    AddSlider(master, "Accuracy", "cai_accuracy", 0, 1, 2)
    AddSlider(master, "Aggression", "cai_aggression", 0, 1, 2)
    master.FinishUp()

    -- Combat stuff
    local combat = Section(panel, "Combat features", true)
    AddCheck(combat, "Smart cover", "cai_cover")
    AddCheck(combat, "Flanking", "cai_flanking")
    AddCheck(combat, "Searching (last known position)", "cai_search")
    AddCheck(combat, "Morale", "cai_morale")
    AddCheck(combat, "Suppression", "cai_suppression")
    AddCheck(combat, "Memory", "cai_memory")
    AddCheck(combat, "Weapon recognition", "cai_weaponintel")
    AddCheck(combat, "Sound intelligence", "cai_soundintel")
    AddCheck(combat, "Cornered melee panic", "cai_meleepanic")
    AddCheck(combat, "Simultaneous fire (no 2-shooter limit)", "cai_simfire")
    AddCheck(combat, "NPC health regen", "cai_npc_regen")
    AddCheck(combat, "Wallbang suppression (needs penetration mod)", "cai_wallbang")
    combat.FinishUp()

    -- Stealth And Lighting
    local stealth = Section(panel, "Stealth & light", false)
    AddCheck(stealth, "Darkness hides players", "cai_darkness")
    AddCheck(stealth, "Flashlights reveal players", "cai_flashlight")
    AddCheck(stealth, "NPC flashlights in darkness", "cai_npc_flashlights")
    AddCheck(stealth, "NPCs patrol (off = stay at post)", "cai_patrol")
    stealth.FinishUp()

    -- Squads
    local squads = Section(panel, "Squads", false)
    AddCheck(squads, "Squad comms & shared knowledge", "cai_comms")
    AddCheck(squads, "Formations", "cai_formations")
    AddCheck(squads, "Friendly fire avoidance", "cai_friendlyfire_avoid")
    squads.FinishUp()

    -- Voice
    local voice = Section(panel, "Voice", false)
    AddCheck(voice, "Voice lines", "cai_voice")
    AddSlider(voice, "Volume", "cai_voice_volume", 0, 1, 2)
    AddSlider(voice, "Chance to speak", "cai_voice_chance", 0, 1, 2)
    AddSlider(voice, "Per-NPC cooldown (s)", "cai_voice_cooldown", 0, 20, 1)
    AddSlider(voice, "Max audible distance", "cai_voice_maxdist", 500, 4000, 0)
    voice.FinishUp()

    -- Performance
    local perf = Section(panel, "Performance", false)
    AddCheck(perf, "Performance mode (huge battles)", "cai_performance_mode")
    AddSlider(perf, "Max managed NPCs", "cai_max_managed", 10, 300, 0)
    perf.FinishUp()

    -- Debugs
    local debugS = Section(panel, "Debug & tools", false)
    AddCheck(debugS, "Debug overlay", "cai_debug")
    AddCheck(debugS, "Debug rays", "cai_debug_rays")
    StyledButton(debugS, "Print AI stats to console", false, function()
        RunConsoleCommand("cai_dump")
    end)
    AddNote(debugS, "Stats print as cai_dump in the server console.")
    debugS.FinishUp()

    -- Reset everything back
    StyledButton(panel, "Reset all settings to defaults", true, function()
        DoReset(panel)
    end)
end

-- Pick the style
BuildPanel = function(panel)
    panel:ClearControls()
    tracked = {}
    if uiModern:GetBool() then
        BuildPanelModern(panel)
    else
        BuildPanelOG(panel)
    end
end

hook.Add("PopulateToolMenu", "CAI_SettingsMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Combat Intelligence AI", "cai_settings",
        "Settings", "", "", BuildPanel)
end)