local D = CAI.DebugUI

local PAD_L = 12
local PAD_R = 12
local PAD_T = 6
local PAD_B = 8
local BAR_GAP = 8
local BAR_H = 4
local MIN_W = 118
local CHIP_W = 210
local CHIP_H = 15
local CHIP_GAP = 4
local CHIP_PAD = 6
local DOT = 4

local function Bar(x, y, w, h, frac, col, a)
    draw.RoundedBox(2, x, y, w, h, ColorAlpha(D.Col.barbg, 215 * a))
    local fw = math.Round(w * math.Clamp(frac, 0, 1))
    if fw > 1 then
        draw.RoundedBox(2, x, y, fw, h, ColorAlpha(col, 255 * a))
    end
end

local function LayoutChips(traits)
    surface.SetFont("CAI_DbgChip")

    local rows = {}
    local cur = {}
    local curW = 0

    for _, name in ipairs(traits) do
        local info = D.TraitInfo(name)
        local tw = surface.GetTextSize(info.tag)
        local cw = CHIP_PAD + DOT + 5 + tw + CHIP_PAD

        if #cur > 0 and curW + CHIP_GAP + cw > CHIP_W then
            rows[#rows + 1] = { items = cur, w = curW }
            cur, curW = {}, 0
        end

        curW = curW + (#cur > 0 and CHIP_GAP or 0) + cw
        cur[#cur + 1] = { info = info, w = cw }
    end

    if #cur > 0 then
        rows[#rows + 1] = { items = cur, w = curW }
    end

    local widest = 0
    for _, row in ipairs(rows) do
        widest = math.max(widest, row.w)
    end
    return rows, widest
end

local function DrawChips(rows, x, y, innerW, a)
    for _, row in ipairs(rows) do
        local cx = x + math.floor((innerW - row.w) * 0.5)
        for _, chip in ipairs(row.items) do
            local col = chip.info.col
            draw.RoundedBox(4, cx, y, chip.w, CHIP_H, ColorAlpha(col, 46 * a))
            draw.RoundedBox(4, cx, y, 2, CHIP_H, ColorAlpha(col, 200 * a))
            draw.RoundedBox(2, cx + CHIP_PAD, y + math.floor((CHIP_H - DOT) * 0.5), DOT, DOT,
                ColorAlpha(col, 255 * a))
            draw.SimpleText(chip.info.tag, "CAI_DbgChip", cx + CHIP_PAD + DOT + 5, y + CHIP_H * 0.5 - 1,
                ColorAlpha(col, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            cx = cx + chip.w + CHIP_GAP
        end
        y = y + CHIP_H + 3
    end
end

local function DrawBadge(r, sp, a, showTraits)
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

    local chipRows, chipW = nil, 0
    local traits = r.traitList or {}
    if showTraits and #traits > 0 then
        chipRows, chipW = LayoutChips(traits)
    end

    local topH = math.max(idH, roleH)
    local topW = idW + 14 + roleW
    local innerW = math.max(topW, phaseW, chipW, MIN_W)

    local w = innerW + PAD_L + PAD_R
    local h = PAD_T + topH + 3 + phaseH + 6 + BAR_H + PAD_B

    if chipRows then
        h = h + 5 + #chipRows * (CHIP_H + 3) - 3 + 2
    end

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

    cy = cy + BAR_H

    if chipRows then
        surface.SetDrawColor(ColorAlpha(D.Col.line, 130 * a))
        surface.DrawRect(cx, cy + 4, innerW, 1)
        DrawChips(chipRows, cx, cy + 9, innerW, a)
    end
end

hook.Add("HUDPaint", "CAI_DebugBadges", function()
    if not D.Fresh() then return end
    if D.Opt.cinema then return end
    if not D.Opt.badges then return end

    local list, hidden = D.Sorted(D.Opt.maxdraw)
    D.Hidden = hidden

    local showTraits = D.Opt.traits

    for _, r in ipairs(list) do
        local npc = r.ent
        if IsValid(npc) then
            local head = npc:GetPos() + Vector(0, 0, npc:OBBMaxs().z + 16)
            local sp = head:ToScreen()
            if sp.visible then
                local a = D.Alpha(r.dist)
                if D.Occluded(head) then a = a * 0.32 end
                if a > 0.02 then
                    DrawBadge(r, sp, a, showTraits)
                end
            end
        end
    end
end)