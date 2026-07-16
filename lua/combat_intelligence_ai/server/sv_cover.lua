CAI.Cover = CAI.Cover or {}
local CV = CAI.Cover

local spotCache = {}
local shadeCache = {}
function CV.SpotShade(pos)
    local key = math.floor(pos.x / 64) .. ":" .. math.floor(pos.y / 64) .. ":" .. math.floor(pos.z / 64)
    local c = shadeCache[key]
    if c and CurTime() - c.t < 20 then return c.v end
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 40),
        endpos = pos + Vector(0, 0, 4000),
        mask = MASK_SOLID_BRUSHONLY,
    })
    local v = (tr.Hit and not tr.HitSky) and 1 or 0
    shadeCache[key] = { v = v, t = CurTime() }
    return v
end

local function GatherSpots(origin, enemy, enemyPos)
    local cfg = CAI.Config.Cover
    local out = {}
    local areas = navmesh.Find(origin, cfg.SearchRadius, 40, 200) or {}

    for _, area in ipairs(areas) do
        if IsValid(area) then
            local id = area:GetID()
            local cached = spotCache[id]
            if not cached or CurTime() - cached.t > cfg.CacheLifetime then
                local spots = area:GetHidingSpots() or {}

                cached = { spots = spots, t = CurTime() }
                spotCache[id] = cached
            end
            for _, s in ipairs(cached.spots) do out[#out + 1] = s end
        end
    end

    for _, prop in ipairs(ents.FindInSphere(origin, cfg.SearchRadius)) do
        if prop:GetClass() == "prop_physics" and IsValid(prop:GetPhysicsObject()) then
            local mins, maxs = prop:OBBMins(), prop:OBBMaxs()
            local size = (maxs - mins):Length()
            if size > 70 then
                local dir
                if enemyPos then
                    dir = prop:GetPos() - enemyPos
                else
                    dir = origin - prop:GetPos()
                end
                dir.z = 0
                if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) end
                dir:Normalize()
                local off = size * 0.5 + 35
                for _, ang in ipairs({ 0, 45, -45, 180 }) do
                    local d = Angle(0, dir:Angle().y + ang, 0):Forward()
                    local cand = CAI.Nav.SafeGround(prop:GetPos() + d * off)
                    if cand and CAI.Nav.IsGroundSpot(cand) then out[#out + 1] = cand end
                end
            end
        end
    end

    if enemyPos then
        local dirToEnemy = enemyPos - origin
        dirToEnemy.z = 0
        if dirToEnemy:LengthSqr() > 1 then
            dirToEnemy:Normalize()
            for _, r in ipairs({ 180, 300, 420 }) do
                for a = -150, 150, 30 do
                    local ang = math.rad(a)
                    local rot = Vector(
                        dirToEnemy.x * math.cos(ang) - dirToEnemy.y * math.sin(ang),
                        dirToEnemy.x * math.sin(ang) + dirToEnemy.y * math.cos(ang), 0)
                    local cand = CAI.Nav.SafeGround(origin + rot * r)
                    if cand and CAI.Nav.IsGroundSpot(cand)
                       and (not IsValid(enemy) or not CAI.Util.CanSeePos(enemy, cand)) then
                        out[#out + 1] = cand
                    end
                end
            end
        end
    end

    return out
end

function CV.ScoreSpot(data, spot, enemy, enemyPos)
    local cfg = CAI.Config.Cover
    local W = cfg.Weights
    local npc = data.ent
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc then
        local d = spot:Distance(data.squad.leader:GetPos())
        if d > 1200 then return -50 end
        if d > 700 then return -3 - (d - 700) / 200 end
    end
    if CAI.Nav.IsDeepWater(spot) then return -50 end
    for _, b in ipairs(CV.Barrels()) do
        if IsValid(b) and spot:DistToSqr(b:GetPos()) < 200 * 200 then
            return -50
        end
    end
    local score = 0

    local dSelf = npc:GetPos():Distance(spot)
    score = score + W.distSelf * (1 - math.Clamp(dSelf / cfg.SearchRadius, 0, 1))

    local dEnemy = enemyPos and spot:Distance(enemyPos) or cfg.IdealEnemyDist
    if dEnemy < cfg.MinEnemyDist then
        score = score - W.distEnemy * 1.5
    else
        local ideal = data.enemyWeaponResponse and data.enemyWeaponResponse.idealDist or cfg.IdealEnemyDist
        score = score + W.distEnemy * (1 - math.Clamp(math.abs(dEnemy - ideal) / ideal, 0, 1))
    end

    if IsValid(enemy) and enemyPos then
        local visible = CAI.Util.CanSeePos(enemy, spot)
        score = score + (visible and -W.losBlocked * 0.5 or W.losBlocked)
    end

    if data.squad then
        for _, member in ipairs(data.squad.members) do
            if IsValid(member) and member ~= npc
               and member:GetPos():DistToSqr(spot) < cfg.AllyCrowdDist * cfg.AllyCrowdDist then
                score = score - W.crowding
            end
        end
    end

    if CAI.Memory.InDanger(data, spot) then
        score = score - W.danger
    end

    local open = 0
    for _, dir in ipairs({ Vector(1,0,0), Vector(-1,0,0), Vector(0,1,0), Vector(0,-1,0) }) do
        local tr = util.TraceLine({
            start = spot + Vector(0,0,48),
            endpos = spot + Vector(0,0,48) + dir * 300,
            mask = MASK_SOLID_BRUSHONLY,
        })
        if not tr.Hit then open = open + 1 end
    end
    score = score - W.flankRisk * (open / 4) * 0.8

    local escapeScore = 0
    local awayFromEnemy = enemyPos and (spot - enemyPos) or Vector(0, 0, 0)
    awayFromEnemy.z = 0
    if awayFromEnemy:LengthSqr() > 1 then
        awayFromEnemy:Normalize()
        local escapeDest = CAI.Nav.SafeOffset(spot, awayFromEnemy, 300)
        if escapeDest then
            escapeScore = 1.0
        else
            local right = Vector(-awayFromEnemy.y, awayFromEnemy.x, 0)
            for _, side in ipairs({ right, -right }) do
                escapeDest = CAI.Nav.SafeOffset(spot, side, 250)
                if escapeDest then escapeScore = 0.6 break end
            end
        end
    else
        escapeScore = 0.5
    end
    score = score + W.escapeRoute * escapeScore

    local heightAdv = (spot.z - (enemyPos and enemyPos.z or spot.z))
    score = score + W.highGround * math.Clamp(heightAdv / 64, -0.5, 1.0)

    if data.squad and data.squad.blackboard and data.squad.blackboard.spatialMap then
        local cp = CAI.Battlefield.GetNearestChokepoint(data.squad, spot, 300)
        if cp then
            score = score + W.nearChokepoint * (1 - spot:Distance(cp.pos) / 300)
        end
    end

    score = score + W.history * CAI.Battlefield.CoverHistory(data.squad, spot)

    local darkW = data.wantDarkCover and 2.5 or (W.dark or 0)
    if darkW > 0 then
        score = score + darkW * CV.SpotShade(spot)
    end

    return score
end

function CV.FindBest(data, enemy, enemyPos)
    if not CAI.CVBool("cai_cover") then return nil end
    local classInfo = CAI.Config.NPCClasses[data.ent:GetClass()]
    if classInfo and classInfo.noCover then return nil end

    local _tg = CAI.Prof.active and SysTime() or 0
    local spots = GatherSpots(data.ent:GetPos(), enemy, enemyPos)
    if _tg ~= 0 then CAI.Prof.Record("cover_gather", SysTime() - _tg) end
    if #spots == 0 then return nil end

    local best, bestScore = nil, -math.huge

    local step = math.max(1, math.floor(#spots / 40))
    for i = 1, #spots, step do
        local s = CV.ScoreSpot(data, spots[i], enemy, enemyPos)
        if s > bestScore then best, bestScore = spots[i], s end
    end
    return best, bestScore
end

function CV.UpdateCoverStatus(data, enemy)
    if not data.cover then return end
    local cfg = CAI.Config.Cover

    local underFire = data.suppression and data.suppression > 15
    if IsValid(enemy) and CAI.Util.CanSee(enemy, data.ent) and underFire then
        data.cover.exposedSince = data.cover.exposedSince or CurTime()
        if CurTime() - data.cover.exposedSince > cfg.CompromiseTime then

            CAI.Battlefield.MarkCover(data.squad, data.cover.pos, false)
            CAI.Memory.AddDanger(data, data.cover.pos, 150, "compromised_cover")
            data.cover = nil
            data.forceRecover = true

            local newPos = CV.FindBest(data, enemy, IsValid(enemy) and enemy:GetPos() or nil)
            if newPos then
                data.cover = { pos = newPos, since = CurTime() }
                data.forceRecover = nil
                CAI.Nav.MoveTo(data, newPos, "run")
                CAI.Brain.SetState(data, CAI.STATE.COVER, "cover_blown_relocate")
            end
        end
    else
        data.cover.exposedSince = nil

        if not data.cover.credited and CurTime() - data.cover.since > 6 then
            CAI.Battlefield.MarkCover(data.squad, data.cover.pos, true)
            data.cover.credited = true
        end
    end
end

local barrels, barrelsAt = {}, 0
function CV.Barrels()
    if CurTime() - barrelsAt > 10 then
        barrelsAt = CurTime()
        barrels = {}
        for _, e in ipairs(ents.FindByClass("prop_physics")) do
            if IsValid(e) and (e:GetModel() or ""):find("explosive", 1, true) then
                barrels[#barrels + 1] = e
            end
        end
    end
    return barrels
end

CAI.Prof.WrapFn(CV, "FindBest", "cover_findbest")
CAI.Prof.WrapFn(CV, "ScoreSpot", "cover_score")
CAI.Prof.WrapFn(CV, "UpdateCoverStatus", "cover_updatestatus")
CAI.Prof.WrapFn(CV, "Barrels", "cover_barrels")
