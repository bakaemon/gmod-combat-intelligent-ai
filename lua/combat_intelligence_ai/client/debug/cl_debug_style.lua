CAI.DebugUI = CAI.DebugUI or {}
local D = CAI.DebugUI

local function CV(name, default, help)
    return CreateClientConVar(name, default, true, false, help)
end

D.CV = {
    badges  = CV("cai_debug_badges", "1", "Draw the status badge above each NPC"),
    detail  = CV("cai_debug_detail", "0", "Expand every badge into the full text"),
    links   = CV("cai_debug_links", "1", "Draw squad bond links on the ground"),
    deaths  = CV("cai_debug_deaths", "1", "Leave a marker where an NPC died"),
    cinema  = CV("cai_debug_cinematic", "0", "Hide all text and keep ONLY the world markers"),
    xray    = CV("cai_debug_xray", "0", "Draw world markers through walls at max power"),
    maxdraw = CV("cai_debug_maxbadges", "16", "Maximum badges drawn at once, 0 = No limit"),
    fade    = CV("cai_debug_fadedist", "2400", "Distance at which the badges fadeout"),
}

surface.CreateFont("CAI_DbgTag",   { font = "Roboto", size = 13, weight = 800 })
surface.CreateFont("CAI_DbgPhase", { font = "Roboto", size = 15, weight = 800 })
surface.CreateFont("CAI_DbgSmall", { font = "Roboto", size = 11, weight = 500 })
surface.CreateFont("CAI_DbgLine",  { font = "Roboto", size = 12, weight = 600 })

D.Phase = {
    [0] = Color(150, 195, 160),
    [1] = Color(240, 195, 105),
    [2] = Color(235, 85, 85),
    [3] = Color(240, 150, 60),
    [4] = Color(90, 160, 240),
    [5] = Color(225, 90, 190),
    [6] = Color(165, 165, 172),
}

D.RoleTag = {
    [0] = "---",
    [1] = "LDR",
    [2] = "SUP",
    [3] = "FLK",
    [4] = "SPT",
    [5] = "BRC",
    [6] = "REAR",
    [7] = "GRN",
}

D.Col = {
    bg        = Color(16, 16, 20),
    text      = Color(235, 235, 238),
    dim       = Color(150, 150, 158),
    accent    = Color(235, 120, 35),
    barbg     = Color(46, 46, 54),
    morale    = Color(110, 205, 120),
    moraleLow = Color(228, 95, 85),
    supp      = Color(238, 178, 70),
    cover     = Color(85, 165, 245),
    move      = Color(120, 235, 130),
    target    = Color(240, 85, 85),
    death     = Color(235, 80, 80),
    traits    = Color(240, 195, 120),
}

local squadCache = {}

function D.SquadColor(id)
    if not id or id == 0 then return Color(170, 170, 178) end
    local c = squadCache[id]
    if not c then
        c = HSVToColor((id * 67) % 360, 0.42, 1)
        squadCache[id] = c
    end
    return c
end

function D.Approach(cur, target, rate)
    local step = FrameTime() * rate
    if cur < target then return math.min(cur + step, target) end
    return math.max(cur - step, target)
end

function D.PhaseName(phase)
    local T = CAI.Config and CAI.Config.Text
    if T and T.Phases and T.Phases[phase] then return T.Phases[phase] end
    if CAI.PHASE_NAMES and CAI.PHASE_NAMES[phase] then return CAI.PHASE_NAMES[phase] end
    return "PHASE " .. tostring(phase)
end

function D.RoleName(role)
    local T = CAI.Config and CAI.Config.Text
    if role == 0 then return "-" end
    if T and T.Roles and T.Roles[role] then return T.Roles[role] end
    if CAI.ROLE_NAMES and CAI.ROLE_NAMES[role] then return CAI.ROLE_NAMES[role] end
    return tostring(role)
end

function D.WhyName(why)
    local T = CAI.Config and CAI.Config.Text
    if T and T.Reasons and T.Reasons[why] then return T.Reasons[why] end
    return (why and why ~= "" and why) or "-"
end

function D.Active()
    local cv = GetConVar("cai_debug")
    return cv ~= nil and cv:GetBool()
end

function D.WorldEnabled()
    local cv = GetConVar("cai_debug_rays")
    return cv ~= nil and cv:GetBool()
end

function D.Alpha(dist)
    local fade = D.CV.fade:GetFloat()
    if fade <= 0 then return 1 end
    return math.Clamp(1 - (dist / fade), 0, 1)
end

function D.Occluded(pos)
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = pos,
        filter = ply,
        mask = MASK_OPAQUE,
    })
    return tr.Hit
end
