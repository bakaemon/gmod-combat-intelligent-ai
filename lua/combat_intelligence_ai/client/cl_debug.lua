local rows, rowsAt = {}, 0

net.Receive(CAI.Net.Debug, function()
    rows = {}
    local n = net.ReadUInt(6)
    for i = 1, n do
        local r = {}
        r.idx = net.ReadUInt(14)
        r.state = net.ReadUInt(5)
        r.role = net.ReadUInt(4)
        r.morale = net.ReadUInt(7)
        r.supp = net.ReadUInt(7)
        r.squad = net.ReadUInt(8)
        r.plan = net.ReadString()
        r.why = net.ReadString()
        if net.ReadBool() then r.cover = net.ReadVector() end
        if net.ReadBool() then r.move = net.ReadVector() end
        r.target = net.ReadUInt(14)
        r.memE = net.ReadUInt(4)
        r.memD = net.ReadUInt(4)
        r.lod = net.ReadFloat()
        rows[#rows + 1] = r
    end
    rowsAt = CurTime()
end)

surface.CreateFont("CAI_Debug", { font = "Tahoma", size = 16, weight = 700, outline = true })

local STATE_COLORS = {
    [2] = Color(255, 80, 80),
    [3] = Color(80, 160, 255),
    [4] = Color(255, 160, 40),
    [5] = Color(255, 220, 60),
    [6] = Color(180, 120, 255),
    [7] = Color(255, 60, 200),
}

cvars.AddChangeCallback("cai_debug", function(_, _, new)
    if new == "0" then rows = {} end
end, "CAI_DebugClear")

hook.Add("HUDPaint", "CAI_DebugDraw", function()
    local cv = GetConVar("cai_debug")
    if not cv or not cv:GetBool() then return end
    if CurTime() - rowsAt > 1 then return end
    if #rows == 0 then return end
    local drawRays = GetConVar("cai_debug_rays"):GetBool()

    for _, r in ipairs(rows) do
        local npc = Entity(r.idx)
        if IsValid(npc) then
            local head = npc:GetPos() + Vector(0, 0, npc:OBBMaxs().z + 14)
            local sp = head:ToScreen()
            if sp.visible then
                local col = STATE_COLORS[r.state] or color_white
                local T = CAI.Config.Text
                local L = T.Labels
                local why = T.Reasons[r.why] or r.why
                local lines = {
                    { (T.States[r.state] or CAI.STATE_NAMES[r.state] or "?")
                        .. "  [" .. (T.Roles[r.role] or CAI.ROLE_NAMES[r.role] or "-") .. "]", col },
                    { L.morale .. " " .. r.morale .. "   " .. L.supp .. " " .. r.supp, color_white },
                    { L.squad .. " " .. r.squad .. "  " .. L.plan .. " " .. r.plan, Color(180, 255, 180) },
                    { L.why .. " " .. why, Color(200, 200, 200) },
                    { L.memE .. r.memE .. L.memD .. r.memD .. "  " .. L.lod .. string.format("%.2fs", r.lod), Color(160, 160, 160) },
                }
                for i, l in ipairs(lines) do
                    draw.SimpleText(l[1], "CAI_Debug", sp.x, sp.y + (i - 1) * 16,
                        l[2], TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                end

                if drawRays then

                    local function line(toPos, col2)
                        local a = (npc:GetPos() + Vector(0, 0, 40)):ToScreen()
                        local b = toPos:ToScreen()
                        if a.visible and b.visible then
                            surface.SetDrawColor(col2)
                            surface.DrawLine(a.x, a.y, b.x, b.y)
                        end
                    end
                    if r.cover then line(r.cover, Color(80, 160, 255)) end
                    if r.move then line(r.move, Color(120, 255, 120)) end
                    local tgt = Entity(r.target)
                    if IsValid(tgt) then line(tgt:GetPos() + Vector(0, 0, 40), Color(255, 80, 80)) end
                end
            end
        end
    end
end)
