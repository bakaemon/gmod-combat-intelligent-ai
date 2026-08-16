CAI.DebugUI = CAI.DebugUI or {}
local D = CAI.DebugUI

D.Opt = {
    badges = true,
    traits = true,
    links = true,
    deaths = true,
    cinema = false,
    xray = false,
    maxdraw = 16,
    fade = 2400,
}

surface.CreateFont("CAI_DbgTag",   { font = "Roboto", size = 13, weight = 800 })
surface.CreateFont("CAI_DbgPhase", { font = "Roboto", size = 15, weight = 800 })
surface.CreateFont("CAI_DbgSmall", { font = "Roboto", size = 11, weight = 500 })
surface.CreateFont("CAI_DbgLine",  { font = "Roboto", size = 12, weight = 600 })
surface.CreateFont("CAI_DbgChip",  { font = "Roboto", size = 11, weight = 800 })

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
    line      = Color(64, 64, 74),
}

D.Trait = {
    Aggressive = { tag = "AGGR", col = Color(238, 108, 72) },
    Defensive  = { tag = "DEFN", col = Color(95, 165, 235) },
    Patient    = { tag = "PATN", col = Color(90, 205, 195) },
    Brave      = { tag = "BRVE", col = Color(245, 205, 90) },
    Cowardly   = { tag = "COWD", col = Color(190, 140, 230) },
    Calm       = { tag = "CALM", col = Color(140, 215, 175) },
    Impulsive  = { tag = "IMPL", col = Color(240, 125, 180) },
    Accurate   = { tag = "ACCU", col = Color(110, 200, 240) },
    PoorShot   = { tag = "POOR", col = Color(160, 150, 145) },
    Reckless   = { tag = "RECK", col = Color(250, 90, 60) },
}

local unknownTraits = {}

function D.TraitInfo(name)
    local known = D.Trait[name]
    if known then return known end

    local made = unknownTraits[name]
    if not made then
        local seed = 0
        for i = 1, #name do
            seed = seed + name:byte(i) * i
        end
        made = {
            tag = string.upper(string.sub(name, 1, 4)),
            col = HSVToColor((seed * 37) % 360, 0.45, 1),
        }
        unknownTraits[name] = made
    end
    return made
end

local splitCache = {}

function D.TraitList(str)
    if not str or str == "" then return {} end
    local cached = splitCache[str]
    if not cached then
        cached = string.Explode("/", str)
        splitCache[str] = cached
    end
    return cached
end

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
    local fade = D.Opt.fade
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