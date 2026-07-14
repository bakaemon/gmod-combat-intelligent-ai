CAI.FriendlyFire = CAI.FriendlyFire or {}
local FF = CAI.FriendlyFire

local function AllyBlocking(npc, enemy)
    local from = npc.GetShootPos and npc:GetShootPos() or CAI.Util.EyePos(npc)
    local to = CAI.Util.EyePos(enemy)
    local tr = util.TraceHull({
        start = from, endpos = to,
        filter = npc,
        mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8),
    })
    local hit = tr.Entity
    if IsValid(hit) and hit:IsNPC() and npc:Disposition(hit) == D_LI then
        return true, hit
    end
    return false, nil
end

local function Sidestep(data, enemy)
    local npc = data.ent
    local dir = (enemy:GetPos() - npc:GetPos()); dir.z = 0; dir:Normalize()
    local right = Vector(-dir.y, dir.x, 0)
    local side = math.random() < 0.5 and 1 or -1
    for _, mult in ipairs({ side, -side }) do
        local target = npc:GetPos() + right * mult * 120
        local area = navmesh.GetNearestNavArea(target)
        if IsValid(area) then
            data.moveTarget = nil
            CAI.Nav.MoveTo(data, area:GetClosestPointOnArea(target), "run")
            return true
        end
    end
    return false
end

function FF.Update(data)
    if not CAI.CVBool("cai_friendlyfire_avoid") then
        data.ffBlocked = false
        return false
    end
    local npc = data.ent
    local enemy = npc.GetEnemy and npc:GetEnemy()

    if IsValid(enemy) and CAI.Util.Alive(enemy) then
        data.ffCheckAt = data.ffCheckAt or 0
        if CurTime() > data.ffCheckAt then
            data.ffCheckAt = CurTime() + 0.1
            local blocked, blocker = AllyBlocking(npc, enemy)
            if blocked then
                Sidestep(data, enemy)
                if data.squad and IsValid(blocker) then
                    local shootDir = (enemy:GetPos() - npc:GetPos()):GetNormalized()
                    CAI.Squad.Broadcast(data.squad, "line_of_fire_blocked", npc, {
                        blocker = blocker,
                        direction = shootDir,
                        enemy = enemy,
                    })
                end
                data.ffBlocked = true
                return true
            end
        end
    end
    data.ffBlocked = false
    return false
end

CAI.Prof.WrapFn(FF, "Update", "ff_update")
