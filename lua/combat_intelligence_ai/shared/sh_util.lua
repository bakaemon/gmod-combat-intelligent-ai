CAI.Util = CAI.Util or {}
local U = CAI.Util

function U.Alive(ent)
    return IsValid(ent) and ent:Health() > 0
end

local cvIgnorePlayers
function U.IsTargetable(ent)
    if not U.Alive(ent) then return false end
    if ent:IsPlayer() then
        if ent:IsFlagSet(FL_NOTARGET) then return false end
        cvIgnorePlayers = cvIgnorePlayers or GetConVar("ai_ignoreplayers")
        if cvIgnorePlayers and cvIgnorePlayers:GetBool() then return false end
    end
    return true
end

function U.DistSqr(a, b)
    local d = a - b
    return d:LengthSqr()
end

function U.PointSegmentDist(p, a, b)
    local ab = b - a
    local lenSqr = ab:LengthSqr()
    if lenSqr < 1 then return p:Distance(a) end
    local t = math.Clamp((p - a):Dot(ab) / lenSqr, 0, 1)
    return p:Distance(a + ab * t)
end

function U.EyePos(ent)
    if not IsValid(ent) then return vector_origin end
    if ent.EyePos then return ent:EyePos() end
    return ent:GetPos() + Vector(0, 0, 60)
end

local seeVal, seeTime = {}, {}
local seeFilter = { NULL, NULL }
local seeTrace = { start = nil, endpos = nil, filter = seeFilter, mask = MASK_BLOCKLOS }
function U.CanSee(from, to)
    if not (IsValid(from) and IsValid(to)) then return false end

    local now = CurTime()
    local key = from:EntIndex() * 65536 + to:EntIndex()
    local t = seeTime[key]
    if t and now - t < 0.2 then
        return seeVal[key]
    end
    local _t = CAI.Prof.active and SysTime() or 0
    seeFilter[1], seeFilter[2] = from, to
    seeTrace.start = U.EyePos(from)
    seeTrace.endpos = U.EyePos(to)
    local tr = util.TraceLine(seeTrace)
    local result = not tr.Hit
    if _t ~= 0 then CAI.Prof.Record("trace_cansee", SysTime() - _t) end
    seeVal[key], seeTime[key] = result, now
    return result
end

function U.Sees(from, to)
    if not (IsValid(from) and IsValid(to)) then return false end
    if U.CanSee(from, to) then return true end
    return from.Visible and from:Visible(to) or false
end

timer.Create("CAI_TraceCacheFlush", 30, 0, function()
    seeVal, seeTime = {}, {}
end)

function U.CanSeePos(viewer, pos)
    if not IsValid(viewer) then return false end
    local _t = CAI.Prof.active and SysTime() or 0
    local tr = util.TraceLine({
        start = U.EyePos(viewer),
        endpos = pos + Vector(0, 0, 40),
        filter = viewer,
        mask = MASK_BLOCKLOS,
    })
    local r = not tr.Hit
    if _t ~= 0 then CAI.Prof.Record("trace_cansee_pos", SysTime() - _t) end
    return r
end

function U.NearestPlayer(pos)
    local best, bestD = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if U.Alive(ply) then
            local d = U.DistSqr(pos, ply:GetPos())
            if d < bestD then best, bestD = ply, d end
        end
    end
    return best, bestD
end

function U.WeightedRandom(list)
    local total = 0
    for _, e in ipairs(list) do total = total + e.w end
    local r = math.Rand(0, total)
    for _, e in ipairs(list) do
        r = r - e.w
        if r <= 0 then return e.item end
    end
    return list[#list] and list[#list].item
end

function U.Approach(cur, target, rate)
    return math.Approach(cur, target, rate)
end

local lastHookError = {}
function CAI.SafeHook(event, name, fn)
    hook.Add(event, name, function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            local now = CurTime()
            if (lastHookError[name] or 0) + 5 < now then
                lastHookError[name] = now
                ErrorNoHalt("[Combat Intelligence AI] something broke in " .. name .. ": " .. tostring(err) .. "\n")
            end
        end

    end)
end