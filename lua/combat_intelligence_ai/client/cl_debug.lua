local rows, rowsAt = {}, 0

net.Receive(CAI.Net.Debug, function()
    rows = {}
    local n = net.ReadUInt(6)
    for i = 1, n do
        local r = {}
        r.idx    = net.ReadUInt(14)
        r.phase  = net.ReadUInt(3)
        r.intent = net.ReadString()
        r.role   = net.ReadUInt(4)
        r.morale = net.ReadUInt(7)
        r.supp   = net.ReadUInt(7)
        r.squad  = net.ReadUInt(8)
        r.plan   = net.ReadString()
        r.why    = net.ReadString()
        if net.ReadBool() then r.cover = net.ReadVector() end
        if net.ReadBool() then r.move  = net.ReadVector() end
        r.target = net.ReadUInt(14)
        r.memE   = net.ReadUInt(4)
        r.memD   = net.ReadUInt(4)
        r.lod    = net.ReadFloat()
        r.traits = net.ReadString()
        rows[#rows + 1] = r
    end
    rowsAt = CurTime()
end)

surface.CreateFont("CAI_Debug", { font = "Tahoma", size = 15, weight = 700, outline = true })

-- Phase colour: drives only the phase/intent header now
local PHASE_COLORS = {
    [0] = Color(160, 200, 160),  -- PRE_CONTACT  green
    [1] = Color(255, 200, 100),  -- ASSESS       amber
    [2] = Color(255, 80,  80 ),  -- ENGAGE       red
    [3] = Color(255, 160, 40 ),  -- MANEUVER     orange
    [4] = Color(80,  160, 255),  -- COVER        blue
    [5] = Color(255, 60,  200),  -- WITHDRAW     pink
    [6] = Color(180, 180, 180),  -- POST_CONTACT grey
}

-- Fixed colours for every other row
local COL_HEADER  = Color(100, 180, 255)   -- bright blue  (entity id / role line)
local COL_STATS   = color_white
local COL_SQUAD   = Color(180, 255, 180)
local COL_WHY     = Color(200, 200, 200)
local COL_MEM     = Color(160, 160, 160)
local COL_TRAITS  = Color(255, 200, 120)

local LINE_H = 17   -- pixel step between lines (15px font + 2px gap, outline-safe)

local function phaseColor(r)
    return PHASE_COLORS[r.phase] or color_white
end

local function phaseName(r)
    local T = CAI.Config and CAI.Config.Text
    if not T then return "?" end
    return T.Phases[r.phase] or ("phase" .. r.phase)
end

local function roleName(r)
    local T = CAI.Config and CAI.Config.Text
    if not T then return "-" end
    -- role 0 = no squad role assigned yet
    if r.role == 0 then return "-" end
    return (T.Roles and T.Roles[r.role]) or (CAI.ROLE_NAMES and CAI.ROLE_NAMES[r.role]) or tostring(r.role)
end

local function whyName(r)
    local T = CAI.Config and CAI.Config.Text
    local reasons = T and T.Reasons
    if reasons and reasons[r.why] then return reasons[r.why] end
    return (r.why ~= "" and r.why) or "-"
end

cvars.AddChangeCallback("cai_debug", function(_, _, new)
    if new == "0" then rows = {} end
end, "CAI_DebugClear")

hook.Add("HUDPaint", "CAI_DebugDraw", function()
    local cv = GetConVar("cai_debug")
    if not cv or not cv:GetBool() then return end
    if CurTime() - rowsAt > 1 then return end
    if #rows == 0 then return end

    local drawRays = GetConVar("cai_debug_rays"):GetBool()
    local T = CAI.Config and CAI.Config.Text
    local L = T and T.Labels or {}

    for _, r in ipairs(rows) do
        local npc = Entity(r.idx)
        if IsValid(npc) then
            local head = npc:GetPos() + Vector(0, 0, npc:OBBMaxs().z + 14)
            local sp = head:ToScreen()
            if sp.visible then
                local phaseCol = phaseColor(r)

                -- Line 1: blue header — entity index + role
                local line1 = "#" .. r.idx .. "  [" .. roleName(r) .. "]"

                -- Line 2: phase : intent  (coloured by phase)
                local intent = (r.intent ~= "" and r.intent) or "-"
                local line2 = phaseName(r) .. ":  " .. intent

                -- Line 3: morale / suppression
                local line3 = (L.morale or "morale") .. " " .. r.morale
                           .. "   " .. (L.supp or "supp") .. " " .. r.supp

                -- Line 4: squad / plan
                local line4 = (L.squad or "squad") .. " " .. r.squad
                           .. "  " .. (L.plan or "plan:") .. " " .. (r.plan ~= "" and r.plan or "-")

                -- Line 5: why
                local line5 = (L.why or "why:") .. " " .. whyName(r)

                -- Line 6: memory / lod
                local line6 = (L.memE or "mem E:") .. r.memE
                           .. (L.memD or " D:") .. r.memD
                           .. "  " .. (L.lod or "lod ") .. string.format("%.2fs", r.lod)

                -- Line 7: traits
                local line7 = "Traits: " .. (r.traits ~= "" and r.traits or "-")

                local lines = {
                    { line1, COL_HEADER  },
                    { line2, phaseCol    },
                    { line3, COL_STATS   },
                    { line4, COL_SQUAD   },
                    { line5, COL_WHY     },
                    { line6, COL_MEM     },
                    { line7, COL_TRAITS  },
                }

                for i, l in ipairs(lines) do
                    draw.SimpleText(l[1], "CAI_Debug",
                        sp.x, sp.y + (i - 1) * LINE_H,
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
                    if r.move  then line(r.move,  Color(120, 255, 120)) end
                    local tgt = Entity(r.target)
                    if IsValid(tgt) then
                        line(tgt:GetPos() + Vector(0, 0, 40), Color(255, 80, 80))
                    end
                end
            end
        end
    end
end)