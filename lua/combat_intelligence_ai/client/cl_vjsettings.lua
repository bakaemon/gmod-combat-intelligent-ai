local function Send(cvar, val)
    net.Start(CAI.Net.Settings)
    net.WriteString(cvar)
    net.WriteString(tostring(val))
    net.SendToServer()
end

local panelRef

local function Rebuild(classes)
    local panel = panelRef
    if not IsValid(panel) then return end
    panel:ClearControls()

    local master = panel:CheckBox("Enable VJ Base SNPC support (EXPERIMENTAL)")
    local cv = GetConVar("cai_vj_enabled")
    if cv then master:SetChecked(cv:GetBool()) end
    function master:OnChange(checked)
        Send("cai_vj_enabled", checked and "1" or "0")
    end

    panel:Help("VJ SNPCs have their own AI. Enabling this will replace their brain with Combat Intelligence AI. The results will be different for all sorts of NPCs.")

    if not LocalPlayer():IsAdmin() then
        panel:Help("You need admin to change these.")
    end

    if not classes or #classes == 0 then
        panel:Help("No VJ Base NPCs detected on this server.")
        return
    end

    local search = panel:TextEntry("Search")
    search:SetUpdateOnType(true)

    local byCat = {}
    for _, c in ipairs(classes) do
        byCat[c.category] = byCat[c.category] or {}
        table.insert(byCat[c.category], c)
    end

    local allChecks = {}
    local cats = {}

    for catName, items in SortedPairs(byCat) do
        table.sort(items, function(a, b) return a.name < b.name end)

        local cat = vgui.Create("DCollapsibleCategory", panel)
        cat:SetLabel(catName .. "  (" .. #items .. ")")
        cat:SetExpanded(false)
        cat:Dock(TOP)
        cat:DockMargin(0, 4, 0, 0)

        local body = vgui.Create("DListLayout", cat)
        cat:SetContents(body)

        for _, c in ipairs(items) do
            local cb = vgui.Create("DCheckBoxLabel", body)
            cb:SetText(c.name)
            cb:SetDark(true)
            cb:SetChecked(c.enabled)
            cb:SetTooltip(c.class)
            cb:DockMargin(8, 3, 0, 3)
            function cb:OnChange(checked)
                net.Start(CAI.Net.VJToggle)
                net.WriteString(c.class)
                net.WriteBool(checked)
                net.SendToServer()
            end
            allChecks[#allChecks + 1] = { cb = cb, name = string.lower(c.name), class = string.lower(c.class), cat = cat }
            body:Add(cb)
        end

        panel:AddItem(cat)
        cats[#cats + 1] = cat
    end

    function search:OnValueChange(txt)
        txt = string.lower(string.Trim(txt or ""))
        for _, e in ipairs(allChecks) do
            local show = txt == "" or e.name:find(txt, 1, true) ~= nil
                         or e.class:find(txt, 1, true) ~= nil
            e.cb:SetVisible(show)
        end
        for _, cat in ipairs(cats) do
            if txt ~= "" then cat:SetExpanded(true) end
            cat:InvalidateLayout(true)
        end
        panel:InvalidateLayout(true)
    end

    local btnAll = panel:Button("Enable everything shown")
    local btnNone = panel:Button("Disable everything shown")
    function btnAll:DoClick()
        for _, e in ipairs(allChecks) do
            if e.cb:IsVisible() then e.cb:SetChecked(true) end
        end
    end
    function btnNone:DoClick()
        for _, e in ipairs(allChecks) do
            if e.cb:IsVisible() then e.cb:SetChecked(false) end
        end
    end
end

net.Receive(CAI.Net.VJList, function()
    local len = net.ReadUInt(32)
    local raw = util.Decompress(net.ReadData(len))
    local classes = util.JSONToTable(raw or "") or {}
    Rebuild(classes)
end)

local function BuildPanel(panel)
    panelRef = panel
    panel:ClearControls()
    panel:Help("Loading detected VJ NPCs...")
    net.Start(CAI.Net.VJList)
    net.SendToServer()
end

hook.Add("PopulateToolMenu", "CAI_VJMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Combat Intelligence AI", "cai_vj",
        "VJ Base Support", "", "", BuildPanel)
end)
