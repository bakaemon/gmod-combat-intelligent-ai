CAI.Suppression = CAI.Suppression or {}
local S = CAI.Suppression

function S.Add(data, amount)
    if not CAI.CVBool("cai_suppression") then return end
    local resist = 1 - math.Clamp(data.personality.stats.suppResist or 0, 0, 0.6)

    if data.morale > 70 then resist = resist * 0.85 end
    data.suppression = math.min(CAI.Config.Suppression.Max, data.suppression + amount * resist)
    data.lastSuppressedAt = CurTime()

    if data.suppression > CAI.Config.Suppression.PinnedAt and not data.saidTakingFire then
        data.saidTakingFire = true
        CAI.Voice.Speak(data, "taking_fire")
        if data.squad then
            CAI.Squad.Broadcast(data.squad, "taking_fire", data.ent)
            data.squad.lastHelpCallAt = data.squad.lastHelpCallAt or 0
            if CurTime() - data.squad.lastHelpCallAt > 6 then
                data.squad.lastHelpCallAt = CurTime()
                CAI.Squad.Broadcast(data.squad, "need_help", data.ent, { pos = data.ent:GetPos() })
            end
        end
    end
end

function S.Decay(data, dt)
    if data.suppression <= 0 then return end
    data.suppression = math.max(0, data.suppression - CAI.Config.Suppression.Decay * dt)
    if data.suppression < CAI.Config.Suppression.PinnedAt then
        data.saidTakingFire = false
    end
end

function S.IsPinned(data) return data.suppression >= CAI.Config.Suppression.PinnedAt end
function S.IsPanicked(data) return data.suppression >= CAI.Config.Suppression.PanicAt end

local shotQueue = {}
local MAX_QUEUE = 128

CAI.SafeHook("EntityFireBullets", "CAI_Suppression", CAI.Prof.Wrap("supp_fire_block", function(shooter, info)
    if not CAI.Enabled() then return end
    if not IsValid(shooter) then return end
    if shooter:IsNPC() and CAI.Manager.Get(shooter) and info
       and not CAI.CVBool("cai_performance_mode") then
        local src = info.Src
        local dir = info.Dir
        local dist = info.Distance or 8000
        local dst = src + dir * dist
        local ffMax = CAI.Config.Suppression.FFMaxAllies or 4
        local checked = 0
        for fNPC, fData in pairs(CAI.Manager.All()) do
            if checked >= ffMax then break end
            if IsValid(fNPC) and fNPC ~= shooter
               and shooter:Disposition(fNPC) == D_LI
               and fNPC:GetPos():DistToSqr(src) < 2400 * 2400
               and CAI.Util.PointSegmentDist(fNPC:GetPos(), src, dst) <= 220 then
                checked = checked + 1
                local tr = util.TraceHull({
                    start = src, endpos = dst,
                    filter = shooter,
                    mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8),
                })
                if tr.Entity == fNPC then
                    return false
                end
            end
        end
    end
    if not info then return end
    if not CAI.CVBool("cai_suppression") then return end
    if #shotQueue >= MAX_QUEUE then return end
    local now = CurTime()
    if (shooter.CAI_ShotWin or 0) < now then
        shooter.CAI_ShotWin = now + 0.1
        shooter.CAI_ShotN = 0
    end
    shooter.CAI_ShotN = (shooter.CAI_ShotN or 0) + 1
    if shooter.CAI_ShotN > 6 then return end
        shotQueue[#shotQueue + 1] = {
            shooter = shooter,
            src = Vector(info.Src),
            dir = Vector(info.Dir),
            dist = info.Distance or 8000,
        }
    end))

local function ProcessShot(shot)
    local shooter = shot.shooter
    if not IsValid(shooter) then return end
    if shooter:IsPlayer() and not CAI.Util.IsTargetable(shooter) then return end

    local src = shot.src
    local dst = src + shot.dir * shot.dist
    local cfg = CAI.Config.Suppression

    for npc, data in pairs(CAI.Manager.All()) do
        if IsValid(npc) and npc ~= shooter
           and npc:Disposition(shooter) ~= D_LI
           and npc:Disposition(shooter) ~= D_AL then

            if npc:GetPos():DistToSqr(src) < 3000 * 3000 then
                local d = CAI.Util.PointSegmentDist(npc:GetPos() + Vector(0,0,40), src, dst)
                if d < cfg.Radius then
                    S.Add(data, cfg.PerBullet * (1 - d / cfg.Radius))

                    CAI.Memory.HearEnemy(data, shooter, shooter:GetPos())
                end
            end
        end
    end

    if IsValid(shooter) and shooter:IsNPC() and CAI.Manager.Get(shooter) then
        for npc, data in pairs(CAI.Manager.All()) do
            if IsValid(npc) and npc ~= shooter
               and npc:Disposition(shooter) == D_LI
               and npc:GetPos():DistToSqr(src) < 2500 * 2500 then
                CAI.Memory.AddSound(data, src, "battle")
                local _, rec = CAI.Memory.FreshestEnemy(data)
                if not rec or CurTime() - rec.t > 3 then
                    local approxBattle = src + shot.dir * (shot.dist * 0.3)
                CAI.Memory.AddDanger(data, approxBattle, 200, "nearby_friendly_fire")
            end
        end
    end
end
end

ProcessShot = CAI.Prof.Wrap("supp_process", ProcessShot)

timer.Create("CAI_SuppressionQueue", 0.1, 0, function()
    if #shotQueue == 0 then return end
    local batch = shotQueue
    shotQueue = {}
    for i = 1, #batch do
        local ok = pcall(ProcessShot, batch[i])
    end
end)

CAI.SafeHook("OnEntityCreated", "CAI_GrenadeWatch", CAI.Prof.Wrap("supp_grenade", function(ent)
    timer.Simple(0, function()
        if not IsValid(ent) or not CAI.Enabled() then return end
        local cls = ent:GetClass()
        if cls == "npc_grenade_frag" or cls == "grenade_hand" or cls:find("grenade") then

            for npc, data in pairs(CAI.Manager.All()) do
                if IsValid(npc) and npc:GetPos():DistToSqr(ent:GetPos()) < 600 * 600 then
                    CAI.Memory.AddDanger(data, ent:GetPos(), 400, "grenade")
                    data.scatterFrom = ent:GetPos()
                    data.scatterUntil = CurTime() + 2.5
                    if data.squad then
                        CAI.Battlefield.ReportDanger(data.squad, ent:GetPos(), 400, "grenade")
                        CAI.Squad.Broadcast(data.squad, "grenade", npc)
                    end
                CAI.Voice.Speak(data, "grenade")
            end
        end
    end
    end)
end))