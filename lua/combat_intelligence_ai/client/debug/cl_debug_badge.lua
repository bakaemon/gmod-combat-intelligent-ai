local D = CAI.DebugUI

local PAD_L = 12
local PAD_R = 12
local PAD_T = 6
local PAD_B = 8
local BAR_GAP = 8
local BAR_H = 4
local MIN_W = 118
local LINE_H = 15

local function Bar(x, y, w, h, frac, col, a)
    draw.RoundedBox(2, x, y, w, h, ColorAlpha(D.Col.barbg, 215 * a))
    local fw = math.Round(w * math.Clamp(frac, 0, 1))
    if fw > 1 then
        draw.RoundedBox(2, x, y, fw, h, ColorAlpha(col, 255 * a))
    end
end

local function DrawBadge(r, sp, a, detail)
    local disp = D.Disp[r.idx]
    local morale = disp and disp.morale or r.morale
    local supp = disp and disp.supp or r.supp

    local idText = "#" .. r.idx
    local roleText = D.RoleTag[r.role] or "---"
    local intent = (r.intent ~= "" and r.intent) or "-"
    local phaseText = D.PhaseName(r.phase) .. "   " .. intent

    surface.SetFont("CAI_DbgSmall")
    local idW, idH = surface.GetTextSize(idText)

    surface.SetFont("CAI_DbgTag")
    local roleW, roleH = surface.GetTextSize(roleText)

    surface.SetFont("CAI_DbgPhase")
    local phaseW, phaseH = surface.GetTextSize(phaseText)

    local topH = math.max(idH, roleH)
    local topW = idW + 14 + roleW
    local innerW = math.max(topW, phaseW, MIN_W)

    local w = innerW + PAD_L + PAD_R
    local h = PAD_T + topH + 3 + phaseH + 6 + BAR_H + PAD_B

    local x = math.Round(sp.x - w * 0.5)
    local y = math.Round(sp.y)

    local phaseCol = D.Phase[r.phase] or D.Col.text
    local squadCol = D.SquadColor(r.squad)

    draw.RoundedBox(4, x, y, w, h, ColorAlpha(D.Col.bg, 232 * a))
    draw.RoundedBoxEx(4, x, y, 4, h, ColorAlpha(phaseCol, 255 * a), true, false, true, false)

    surface.SetDrawColor(ColorAlpha(squadCol, 80 * a))
    surface.DrawOutlinedRect(x, y, w, h, 1)

    local cx = x + PAD_L
    local cy = y + PAD_T

    draw.SimpleText(idText, "CAI_DbgSmall", cx, cy,
        ColorAlpha(D.Col.dim, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    draw.SimpleText(roleText, "CAI_DbgTag", x + w - PAD_R, cy,
        ColorAlpha(squadCol, 255 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

    cy = cy + topH + 3

    draw.SimpleText(phaseText, "CAI_DbgPhase", cx, cy,
        ColorAlpha(phaseCol, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    cy = cy + phaseH + 6

    local barW = math.floor((innerW - BAR_GAP) * 0.5)
    local moraleCol = morale < 40 and D.Col.moraleLow or D.Col.morale
    Bar(cx, cy, barW, BAR_H, morale / 100, moraleCol, a)
    Bar(cx + barW + BAR_GAP, cy, innerW - barW - BAR_GAP, BAR_H, supp / 100, D.Col.supp, a)

    if not detail then return end

    local lines = {
        { "squad " .. r.squad .. "   " .. ((r.plan ~= "" and r.plan) or "-"), squadCol },
        { D.WhyName(r.why), D.Col.dim },
        { "mem " .. r.memE .. "/" .. r.memD .. "   lod " .. string.format("%.2f", r.lod), D.Col.dim },
        { (r.traits ~= "" and r.traits) or "-", D.Col.traits },
    }

    local dy = y + h + 4
    for i, l in ipairs(lines) do
        draw.SimpleText(l[1], "CAI_DbgLine", sp.x, dy + (i - 1) * LINE_H,
            ColorAlpha(l[2], 235 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end

hook.Add("HUDPaint", "CAI_DebugBadges", function()
    if not D.Fresh() then return end
    if D.CV.cinema:GetBool() then return end
    if not D.CV.badges:GetBool() then return end

    local list, hidden = D.Sorted(D.CV.maxdraw:GetInt())
    D.Hidden = hidden

    local detail = D.CV.detail:GetBool()

    for _, r in ipairs(list) do
        local npc = r.ent
        if IsValid(npc) then
            local head = npc:GetPos() + Vector(0, 0, npc:OBBMaxs().z + 16)
            local sp = head:ToScreen()
            if sp.visible then
                local a = D.Alpha(r.dist)
                if D.Occluded(head) then a = a * 0.32 end
                if a > 0.02 then
                    DrawBadge(r, sp, a, detail)
                end
            end
        end
    end
end)