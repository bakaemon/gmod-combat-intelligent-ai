CAI.Brain = CAI.Brain or {}
local BR = CAI.Brain
local STATE = nil

function BR.SetState(data, newState, reason)
    if data.state == newState then return end
    data.prevState = data.state
    data.state = newState
    data.fighting = nil
    data.coverPhase = nil
    data.coverPhaseEnd = nil
    data.suppFaced = nil
    data.fleeSched = nil
    data.investFaced = nil
    data.stateSince = CurTime()
    if reason then data.lastDecision = reason end
    data.moveTarget = nil
    data.moveIssuedAt = nil
    data.patrolTarget = nil
    if newState ~= CAI.STATE.PATROL then
        data.patrolAt = CurTime()
    end
end

local function Perceive(data)
    local npc = data.ent

    if CurTime() - (data.darkAt or 0) > 1.0 then
        data.darkAt = CurTime()
        CAI.ApplyDarknessVision(data)
    end

    if CurTime() - (data.aimCheckAt or 0) > 0.4 then
        data.aimCheckAt = CurTime()
        local ply = CAI.Util.NearestPlayer(npc:GetPos())
        if IsValid(ply) and CAI.Util.IsTargetable(ply)
           and npc:Disposition(ply) == D_HT
           and npc:GetPos():DistToSqr(ply:GetPos()) < 1500 * 1500 then
            local toNPC = (npc:WorldSpaceCenter() - ply:EyePos())
            toNPC:Normalize()
            if ply:GetAimVector():Dot(toNPC) > 0.995 and CAI.Util.CanSee(npc, ply) then
                data.aimedSince = data.aimedSince or CurTime()
                if CurTime() - data.aimedSince > 0.35 then
                    CAI.Memory.SeeEnemy(data, ply, ply:GetPos())
                    if data.state == CAI.STATE.COVER and not data.forceRecover
                       and math.random() < 0.35 then
                        data.forceRecover = true
                    end
                end
            else
                data.aimedSince = nil
            end
        else
            data.aimedSince = nil
        end
    end

    local engineEnemy = npc.GetEnemy and npc:GetEnemy()
    if IsValid(engineEnemy) and CAI.Util.IsTargetable(engineEnemy) then
        if CAI.Util.Sees(npc, engineEnemy) then
            local firstContact = data.memory.enemies[engineEnemy] == nil
            CAI.Memory.SeeEnemy(data, engineEnemy, engineEnemy:GetPos())
            CAI.WeaponIntel.Update(data, engineEnemy)
            if data.squad then
                CAI.Battlefield.ReportEnemy(data.squad, engineEnemy, engineEnemy:GetPos(), npc)
                if firstContact then
                    CAI.Voice.Speak(data, "enemy_spotted")
                    CAI.Squad.Broadcast(data.squad, "enemy_spotted", npc,
                        { enemy = engineEnemy, pos = engineEnemy:GetPos() })
                    CAI.Squad.Broadcast(data.squad, "need_help", npc,
                        { pos = engineEnemy:GetPos() })
                end
            end
        else
            local rec = data.memory.enemies[engineEnemy]
            if not rec or (rec.heardOnly and CurTime() - rec.t > 1.0) then
                CAI.Memory.HearEnemy(data, engineEnemy, engineEnemy:GetPos())
            end
        end
    end

    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 and not data.saidReload then
        data.saidReload = true
        CAI.Voice.Speak(data, "reload")
        if data.squad then CAI.Squad.Broadcast(data.squad, "reloading", npc) end
        CAI.Morale.Add(data, CAI.Config.Morale.OutOfAmmoClip, "empty_clip")
    elseif IsValid(wep) and wep.Clip1 and wep:Clip1() > 0 then
        data.saidReload = false
    end

    CAI.Morale.CheckHealth(data)
end

function BR.CombatTarget(data)
    local npc = data.ent

    local ee = npc.GetEnemy and npc:GetEnemy()
    if IsValid(ee) and CAI.Util.IsTargetable(ee) and ee:GetClass() ~= "npc_bullseye" then
        local vis = CAI.Util.CanSee(npc, ee)
        if not vis and data.lastVisEnemy == ee
           and CurTime() - (data.lastVisAt or 0) < CAI.Config.LastVisGrace then
            vis = true
        end
        if vis then
            local rec = data.memory.enemies[ee]
                or { pos = ee:GetPos(), t = CurTime(), heardOnly = false }
            return ee, rec
        end
    end

    local ct = data.combatTarget
    if IsValid(ct) and CAI.Util.Alive(ct) and CAI.Util.IsTargetable(ct)
       and data.combatRec then
        return ct, data.combatRec
    end

    return CAI.Memory.FreshestEnemy(data)
end

local function MeleeThreatScan(data)
    local npc = data.ent
    local cfg = CAI.Config.Escape
    local origin = npc:GetPos()
    local radSqr = cfg.SurroundRadius * cfg.SurroundRadius
    local count, nearest, nearestSqr = 0, nil, math.huge
    local sum, contrib = Vector(0, 0, 0), 0
    for ent, _ in pairs(data.memory.enemies) do
        if IsValid(ent) and CAI.Util.Alive(ent) and CAI.Util.IsTargetable(ent)
           and CAI.WeaponIntel.IsMeleeThreat(ent) then
            local dSqr = origin:DistToSqr(ent:GetPos())
            if dSqr < radSqr then
                count = count + 1
                sum = sum + ent:GetPos()
                contrib = contrib + 1
                if dSqr < nearestSqr then nearest, nearestSqr = ent, dSqr end
            end
        end
    end
    local centroid = contrib > 0 and (sum / contrib) or nil
    return count, nearest, math.sqrt(nearestSqr), centroid
end
BR.MeleeThreatScan = MeleeThreatScan

local function Decide(data)
    local S = CAI.STATE
    local npc = data.ent

    data.combatTarget = nil
    data.combatRec = nil

    if data.forceRecover then
        data.forceRecover = nil
        return S.COVER, "emergency_relocate"
    end

    if data.scatterUntil then
        if CurTime() < data.scatterUntil then
            return S.RETREAT, "grenade_scatter"
        end
        data.scatterFrom, data.scatterUntil = nil, nil
    end

    do
        local ownWep = npc.GetActiveWeapon and npc:GetActiveWeapon()
        if IsValid(ownWep) and not CAI.WeaponIntel.IsMelee(npc) then
            local ecfg = CAI.Config.Escape
            local count, nearest, nearDist, centroid = MeleeThreatScan(data)
            local recentHit = CurTime() - (data.lastMeleeHurtAt or 0) < ecfg.MeleeHitGrace
            if nearDist < ecfg.PointBlank or count >= ecfg.SurroundCount or recentHit then
                data.escapeCentroid = centroid or (IsValid(nearest) and nearest:GetPos())
                data.pbEnemy = nearest
                local clipEmpty = ownWep.Clip1 and ownWep:Clip1() == 0
                if clipEmpty or CAI.Morale.RecentMeleeHits(data) >= ecfg.OverwhelmHits then
                    return S.RETREAT, "escape_encirclement"
                end
                return S.ENGAGE, "point_blank_fight"
            end
        end
    end

    if CAI.Morale.IsBroken(data) then
        if CAI.CVBool("cai_meleepanic") then
            local ee = npc.GetEnemy and npc:GetEnemy()
            if IsValid(ee) and CAI.Util.IsTargetable(ee)
               and npc:GetPos():DistToSqr(ee:GetPos()) < 110 * 110 then
                local wep = npc:GetActiveWeapon()
                if not IsValid(wep) or (wep.Clip1 and wep:Clip1() == 0) then
                    return S.ENGAGE, "cornered_melee"
                end
            end
        end
        return S.RETREAT, "morale_broken"
    end

    if CAI.Suppression.IsPanicked(data) and (data.personality.stats.courage or 0) < 0.2 then
        return S.RETREAT, "suppression_panic"
    end

    do
        local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
        if not IsValid(wep) then
            local _, rec = CAI.Memory.FreshestEnemy(data)
            if (rec and CurTime() - rec.t < 8) or data.suppression > 10
               or CurTime() - (data.lastHurtAt or 0) < 6 then
                return S.RETREAT, "unarmed_flee"
            end
        end
    end

    if CAI.WeaponIntel.IsMelee(npc) then
        local me, mrec = CAI.Memory.FreshestEnemy(data)
        if IsValid(me) and not CAI.Util.IsTargetable(me) then
            data.memory.enemies[me] = nil
            mrec = nil
        end
        if mrec and CurTime() - mrec.t < 5 then
            if CAI.Morale.IsBroken(data) then return S.RETREAT, "morale_broken" end
            return S.ENGAGE, "melee_chase"
        end
    end

    if data.squad and data.squad.clearingDoor and not data.squad.clearingDoor.done then
        return S.ROOM_CLEAR, "clearing_doorway"
    end

    local enemy, rec = CAI.Target.Evaluate(data)
    if IsValid(enemy) then
        data.combatTarget, data.combatRec = enemy, rec
    end
    local visible = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
    if visible then
        data.lastVisEnemy, data.lastVisAt = enemy, CurTime()
    elseif IsValid(enemy) and data.lastVisEnemy == enemy
       and CurTime() - (data.lastVisAt or 0) < CAI.Config.LastVisGrace then
        visible = true
    end

    local holdUnknown = CAI.CVBool("cai_hold_unknown")
    local dangerAvoid = CAI.CVBool("cai_danger_avoid")
    local function squadCovering()
        return data.squad and (CAI.Squad.AnyoneEngaging(data.squad, npc)
            or CAI.Squad.Suppressing(data.squad, npc)) or false
    end

    if IsValid(enemy) then
        if visible then

            data.search = nil

            if data.flank then
                if npc:GetPos():DistToSqr(enemy:GetPos()) < 600 * 600 then
                    data.flank = nil
                else
                    return S.FLANK, "flank_in_progress"
                end
            end

            if CAI.Suppression.IsPinned(data) then
                return S.COVER, "pinned_by_fire"
            end

            local ownWep = npc:GetActiveWeapon()
            if IsValid(ownWep) and ownWep.Clip1 and ownWep:Clip1() == 0 then
                return S.COVER, "reloading_cover"
            end
            if data.wantFlank then
                data.wantFlank = nil
                return S.FLANK, "squad_flank_order"
            end
            if data.suppressUntil and CurTime() < data.suppressUntil then
                return S.SUPPRESS, "squad_suppress_order"
            end

            if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
               and data.role ~= CAI.ROLE.FLANKER
               and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700
               and npc:GetPos():Distance(enemy:GetPos()) > CAI.WeaponIntel.OwnRange(npc) then
                return S.REGROUP, "separated_from_squad"
            end

            if data.wantBound and data.boundTarget then
                data.wantBound = nil
                return S.BOUNDED, "squad_bound_order"
            end

            local resp = data.enemyWeaponResponse
            local agg = CAI.WeaponIntel.EffectiveAggression(data)
            local dist = npc:GetPos():Distance(enemy:GetPos())

            if dist < 500 then
                return S.ENGAGE, "close_range_engage"
            end

            data.coverBounces = data.coverBounces or 0
            if data.state ~= CAI.STATE.COVER then data.lastEngageAt = CurTime() end
            local coverStuck = data.state == CAI.STATE.COVER and (data.coverSearchFailures or 0) >= 2
            local starved = CurTime() - (data.lastEngageAt or CurTime()) > 6
                         or data.coverBounces >= 3
                         or coverStuck

            if resp and resp.scatter then
                return S.COVER, "rocket_threat"
            end
            if resp and resp.keepDistance and dist < resp.idealDist * 0.6 then
                return S.COVER, "shotgun_too_close"
            end
            if starved and dist < 2000 then
                data.coverBounces = 0
                data.lastEngageAt = CurTime()
                return S.ENGAGE, "hold_and_fight"
            end
            if data.squadPlan == "push" or agg > 0.72 or dist < 600 then
                return S.ENGAGE, "aggressive_push"
            end
            if data.squadPlan == "retreat" then
                return S.RETREAT, "squad_retreat"
            end

            data.coverBounces = 0
            data.lastEngageAt = CurTime()
            return S.ENGAGE, "engage_target"
        else
            if data.suppressUntil and CurTime() < data.suppressUntil then
                return S.SUPPRESS, "squad_suppress_order"
            end
            if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
               and data.role ~= CAI.ROLE.FLANKER
               and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700 then
                BR.StopSuppressing(data)
                return S.REGROUP, "separated_from_squad"
            end
            if data.flank then
                return S.FLANK, "flank_in_progress"
            end
            local patience = 1.5 + (data.personality.stats.patience or 0) * 3
            local staleFor = rec and (CurTime() - rec.t) or math.huge
            if staleFor < patience then
                if rec and npc:GetPos():DistToSqr(rec.pos) < 350 * 350 then
                    if dangerAvoid and CAI.Memory.AvoidPos(data, rec.pos,
                        CAI.Config.SelfPreserve.DangerAvoid.AllyDeathRadius) then
                        return S.COVER, "await_reacquire"
                    end
                    if holdUnknown and squadCovering()
                       and not (data.squadPlan == "push" or data.squadPlan == "flank") then
                        return S.COVER, "await_reacquire"
                    end
                    data.investigatePos = rec.pos
                    data.investigateUntil = CurTime() + 6
                    return S.INVESTIGATE, "heard_close"
                end
                return S.COVER, "await_reacquire"
            end
            if data.search then return S.SEARCH, "search_in_progress" end
            if CAI.CVBool("cai_search") then
                return S.SEARCH, "enemy_vanished"
            end
            return S.COVER, "await_reacquire"
        end
    end

    if not IsValid(enemy) and data.squad
       and (data.squad.plan == "push" or data.squad.plan == "flank") then
        local helpScore = 0
        local battlePos = nil
        local cfg = CAI.Config.SquadTactics
        for _, snd in ipairs(data.memory.sounds) do
            if snd.type == "battle" and CurTime() - snd.t < cfg.BattleAwarenessDuration then
                local dist = npc:GetPos():Distance(snd.pos)
                if dist < cfg.BattleAwarenessRadius then
                    local distScore = math.Clamp(40 * (1 - dist / cfg.BattleAwarenessRadius), 0, 40)
                    local freshScore = math.Clamp(20 * (1 - (CurTime() - snd.t) / cfg.BattleAwarenessDuration), 0, 20)
                    local total = distScore + freshScore
                    if total > helpScore then
                        helpScore = total
                        battlePos = snd.pos
                    end
                end
            end
        end
        if helpScore > 0 and battlePos then
            local commitment = 0
            if data.state == CAI.STATE.PATROL then
                commitment = 10
            elseif data.state == CAI.STATE.IDLE then
                commitment = 5
            elseif data.state == CAI.STATE.COVER then
                if data.suppression > CAI.Config.Suppression.PinnedAt then
                    commitment = 80
                elseif data.suppression > 30 then
                    commitment = 50
                else
                    commitment = 20
                end
            elseif data.state == CAI.STATE.INVESTIGATE then
                commitment = 15
            elseif data.state == CAI.STATE.SEARCH then
                commitment = 25
            else
                commitment = 60
            end
            local courage = data.personality.stats.courage or 0
            local aggression = data.personality.stats.aggression or 0
            helpScore = helpScore + (courage * 10) + (aggression * 8)
            if data.morale > 70 then helpScore = helpScore + 10 end
            if data.morale < 25 then helpScore = helpScore - 20 end
            if helpScore > commitment then
                if holdUnknown and not (data.wantBound and data.boundTarget)
                   and not (data.squadPlan == "push" or data.squadPlan == "flank") then
                    return S.COVER, "await_reacquire"
                end
                data.investigatePos = battlePos
                data.investigateUntil = CurTime() + 15
                return S.INVESTIGATE, "nearby_battle"
            end
        end
    end

    if data.reinforceTarget then
        return S.REGROUP, "reinforcing"
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 1100 * 1100 then
        return S.REGROUP, "rejoin_squad"
    end
    if data.investigatePos and CurTime() < (data.investigateUntil or 0) then
        return S.INVESTIGATE, "heard_something"
    end
    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
       and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 700 * 700 then
        return S.REGROUP, "rejoin_squad"
    end
    return S.PATROL, "all_quiet"
end

local Exec = {}

Exec[0] = function(data) end

Exec[1] = function(data)
    local npc = data.ent
    if not CAI.CVBool("cai_patrol") then
        if math.random() < 0.03 then CAI.Voice.Speak(data, "idle") end
        return
    end
    if data.moveTarget then
        if CAI.Nav.Arrived(data, 80) then
        elseif npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_IDLE_STAND) then
            data.moveTarget = nil
        else
            return
        end
    end
    local pat = data.personality.stats.patience or 0
    local dwellEnd = data.patrolAt or 0
    if CurTime() < dwellEnd then return end
    data.patrolAt = CurTime() + math.Rand(1, 2) * (1 + pat * 0.8)

    local RADIUS, DEDUP, DECLUMP, TTL = 1500, 400, 500, 30
    local origin = npc:GetPos()
    local squad = data.squad
    if squad then CAI.Battlefield.PrunePatrolVisited(squad, TTL) end

    local reach = CAI.Nav.ReachableAreas(origin)
    local function reachable(p)
        if not p then return false end
        if reach == nil then return true end
        local a = navmesh.GetNearestNavArea(p)
        return IsValid(a) and reach[a] == true
    end

    data.patrolHistory = data.patrolHistory or {}
    local hist = data.patrolHistory

    local function accept(p, key)
        if not p then return false end
        if not reachable(p) then return false end
        if p:DistToSqr(origin) < 300 * 300 then return false end
        if CAI.Memory.NearAllyDeath(data, p, CAI.Config.SelfPreserve.DangerAvoid.AllyDeathRadius) then return false end
        for _, h in ipairs(hist) do
            if p:DistToSqr(h) < DEDUP * DEDUP then return false end
        end
        if squad then
            for _, m in ipairs(squad.members) do
                if IsValid(m) and m ~= npc then
                    local md = CAI.Manager.Get(m)
                    if md and md.patrolTarget and p:DistToSqr(md.patrolTarget) < DECLUMP * DECLUMP then
                        return false
                    end
                end
            end
            if key and CAI.Battlefield.PatrolVisitedAt(squad, key) > 0 then return false end
        end
        return true
    end

    local chosen, chosenKey

    if squad and math.random() > 0.7 then
        local best, bestKey, bestD = nil, nil, math.huge
        for _, poi in ipairs(CAI.Battlefield.GetPatrolPoints(squad, origin, RADIUS)) do
            if accept(poi.pos, poi.key) then
                local d = origin:DistToSqr(poi.pos)
                if d < bestD then best, bestKey, bestD = poi.pos, poi.key, d end
            end
        end
        chosen, chosenKey = best, bestKey
    end

    if not chosen then
        for _ = 1, 6 do
            local cand = CAI.Nav.RandomPointNear(origin, RADIUS, true)
            local key = cand and CAI.Battlefield.PosKey(cand)
            if accept(cand, key) then
                chosen, chosenKey = cand, key
                break
            end
        end
    end

    if not chosen then
        for _, yaw in ipairs({ 0, 45, -45, 90, -90, 135, -135, 180 }) do
            local dir = Angle(0, yaw, 0):Forward()
            local cand = CAI.Nav.SafeGround(origin + dir * 400)
            if cand and accept(cand, CAI.Battlefield.PosKey(cand)) then
                chosen, chosenKey = cand, CAI.Battlefield.PosKey(cand)
                break
            end
        end
    end

    if chosen then
        data.patrolTarget = chosen
        data.lastPatrolPoint = chosen
        hist[#hist + 1] = chosen
        while #hist > 5 do table.remove(hist, 1) end
        if squad then CAI.Battlefield.MarkPatrolVisited(squad, chosenKey) end
        CAI.Nav.MoveTo(data, chosen, "walk")
    end
    CAI.Nav.CheckStuck(data)
    if math.random() < 0.15 then CAI.Voice.Speak(data, "idle") end
end

Exec[2] = function(data)
    local npc = data.ent
    local dangerAvoid = CAI.CVBool("cai_danger_avoid")
    local function safeDest(p)
        if not dangerAvoid or not p then return true end
        if CAI.Util.Sees(npc, enemy) then return true end
        return not CAI.Memory.AvoidPos(data, p, CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius)
    end

    if data.lastDecision == "melee_chase" then
        local me, mrec = BR.CombatTarget(data)
        if IsValid(me) and npc:GetPos():DistToSqr(me:GetPos()) < 90 * 90 then
            if CurTime() - (data.meleeAt or 0) > 0.9 then
                data.meleeAt = CurTime()
                if npc.SetEnemy then npc:SetEnemy(me) end
                data.moveTarget = nil
                npc:SetSchedule(SCHED_MELEE_ATTACK1)
            end
            return
        end
        if mrec and CurTime() - (data.chaseAt or 0) > 0.8 then
            data.chaseAt = CurTime()
            if IsValid(me) and me.GetPos then
                if npc.SetEnemy then npc:SetEnemy(me) end
                CAI.Nav.MoveTo(data, me:GetPos(), "run")
            else
                CAI.Nav.MoveTo(data, mrec.pos, "run")
            end
        end
        return
    end

    if data.lastDecision == "point_blank_fight" then
        local pcfg = CAI.Config.Escape
        local foe = data.pbEnemy
        if not IsValid(foe) then foe = BR.CombatTarget(data) end
        if not IsValid(foe) then return end
        if npc.SetEnemy and npc:GetEnemy() ~= foe then npc:SetEnemy(foe) end
        local now = CurTime()
        local dist = npc:GetPos():Distance(foe:GetPos())
        if now < (data.pbPhaseEnd or 0) then
            CAI.FriendlyFire.Update(data)
            return
        end
        if data.pbPhase == "fire" and dist < pcfg.WithdrawDist then
            data.pbPhase = "move"
            data.pbPhaseEnd = now + 0.8
            data.combatMoveAt = now
            local ref = data.escapeCentroid or foe:GetPos()
            local away = npc:GetPos() - ref
            away.z = 0
            if away:LengthSqr() < 1 then away = npc:GetPos() - foe:GetPos() away.z = 0 end
            away:Normalize()
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, pcfg.Step)
            if dest then CAI.Nav.MoveTo(data, dest, "run") end
        else
            data.pbPhase = "fire"
            data.pbPhaseEnd = now + 1.0
            data.moveTarget = nil
            npc:SetSchedule(SCHED_RANGE_ATTACK1)
        end
        CAI.FriendlyFire.Update(data)
        return
    end

    local enemy = npc:GetEnemy()
    if not IsValid(enemy) then return end
    if data.lastDecision == "cornered_melee" then
        if CurTime() - (data.meleeAt or 0) > 1.2 then
            data.meleeAt = CurTime()
            npc:SetSchedule(SCHED_MELEE_ATTACK1)
            CAI.Voice.Speak(data, "panic")
        end
        return
    end
    local now = CurTime()
    if data.fireUntil and now < data.fireUntil then
        if CAI.FriendlyFire.Update(data) then
            data.fireUntil = nil
        end
        return
    end
    local moving = data.moveTarget ~= nil and not CAI.Nav.Arrived(data, 70)
    if moving then
        if now - (data.combatMoveAt or 0) > 2.2 then
            data.moveTarget = nil
            data.fireUntil = now + 1.6
            npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        end
        CAI.FriendlyFire.Update(data)
        return
    end

    local ideal = CAI.WeaponIntel.OwnIdeal(npc)
    local ownArch = CAI.WeaponIntel.OwnArch(npc)
    local maxRange = CAI.WeaponIntel.OwnRange(npc)
    local resp = data.enemyWeaponResponse
    if resp and resp.keepDistance then ideal = math.max(ideal, resp.idealDist or ideal) end
    local dist = npc:GetPos():Distance(enemy:GetPos())

    if data.lastDecision == "aggressive_push" then
        local pcfg = CAI.Config.Push
        local creepRange = ideal * pcfg.CreepMult
        local stopRange = ideal * pcfg.StopMult

        if dist > creepRange then
            if dist <= maxRange and CAI.Util.Sees(npc, enemy)
               and now >= (data.fireUntil or 0)
               and now - (data.pushBurstAt or 0) > pcfg.BoundInterval + pcfg.BurstDuration then
                data.pushBurstAt = now
                data.fireUntil = now + pcfg.BurstDuration
                data.moveTarget = nil
                data.fighting = nil
                npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
                CAI.FriendlyFire.Update(data)
                return
            end
            if now >= (data.fireUntil or 0) and now - (data.pushAt or 0) > pcfg.BoundInterval then
                data.pushAt = now
                data.combatMoveAt = now
                data.fighting = nil
                local dir = enemy:GetPos() - npc:GetPos()
                dir.z = 0 dir:Normalize()
                local step = math.min(dist - creepRange, pcfg.BoundStep)
                local dest = CAI.Nav.SafeGround(npc:GetPos() + dir * step)
                          or CAI.Nav.SafeOffset(npc:GetPos(), dir, step)
                if dest and safeDest(dest) then
                    CAI.Nav.MoveTo(data, dest, "run")
                    if math.random() < 0.25 then CAI.Voice.Speak(data, "moving") end
                end
            end
            CAI.FriendlyFire.Update(data)
            return
        end

        local ecfg = CAI.Config.Escape
        local _, _, meleeNear = BR.MeleeThreatScan(data)
        if dist > stopRange and CAI.Util.Sees(npc, enemy)
           and meleeNear > ecfg.PointBlank * 1.5
           and now - (data.creepAt or 0) > pcfg.CreepInterval then
            data.creepAt = now
            data.combatMoveAt = now
            local dir = enemy:GetPos() - npc:GetPos()
            dir.z = 0 dir:Normalize()
            local dest = CAI.Nav.SafeGround(npc:GetPos() + dir * pcfg.CreepStep)
                      or CAI.Nav.SafeOffset(npc:GetPos(), dir, pcfg.CreepStep)
            if dest and safeDest(dest) then CAI.Nav.MoveTo(data, dest, "walk") end
            CAI.FriendlyFire.Update(data)
            return
        end
    end

    if resp == CAI.Config.WeaponResponses.melee then
        if dist < ideal * 0.95 then
            if now - (data.kiteAt or 0) > 1.2 then
                data.kiteAt = now
                data.combatMoveAt = now
                local away = npc:GetPos() - enemy:GetPos()
                away.z = 0 away:Normalize()
                local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 260)
                if dest then CAI.Nav.MoveTo(data, dest, "run") end
            end
        end
        CAI.FriendlyFire.Update(data)
    end

    if dist >= ideal * 0.45 and dist <= maxRange and CAI.Util.Sees(npc, enemy) then
        data.moveTarget = nil
        local firing = false
        if npc.IsCurrentSchedule then
            firing = npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1)
                or npc:IsCurrentSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        end
        if data.squad and data.squadPlan == "hold" and data.staggerOffset and data.squad._staggerPhase then
            local cycleLen = #data.squad.members * CAI.Config.SquadTactics.StaggerOffset
            local phase = (CurTime() - data.squad._staggerPhase) % cycleLen
            local myWindow = CAI.Config.SquadTactics.StaggerFireWindow
            if math.abs(phase - data.staggerOffset) > myWindow then
                if not data.staggerCovering then
                    data.staggerCovering = true
                    data.fighting = nil
                    npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
                end
                CAI.FriendlyFire.Update(data)
                return
            end
            data.staggerCovering = nil
        end
        if CAI.FriendlyFire.Update(data) then
            return
        end
        if data.fireAngleOffset and data.fireAngleOffset ~= 0 then
            local toEnemy = (enemy:GetPos() - npc:GetPos()):GetNormalized()
            local right = Vector(-toEnemy.y, toEnemy.x, 0)
            local offset = right * data.fireAngleOffset * 5
            local dest = CAI.Nav.SafeGround(npc:GetPos() + offset)
            if dest then CAI.Nav.MoveTo(data, dest, "walk") end
            data.fireAngleOffset = data.fireAngleOffset * 0.5
            if math.abs(data.fireAngleOffset) < 1 then data.fireAngleOffset = nil end
        end
        if not data.fighting or (not firing and CurTime() - (data.fightSchedAt or 0) > 1.5) then
            data.fighting = true
            data.fightSchedAt = CurTime()
            npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        end
        return
    end

    if dist < ideal * 0.45 then
        if now - (data.backoffAt or 0) > 3 then
            data.backoffAt = now
            data.combatMoveAt = now
            local away = npc:GetPos() - enemy:GetPos()
            away.z = 0 away:Normalize()
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 200)
            if dest then CAI.Nav.MoveTo(data, dest, "run") end
        end
    elseif ownArch == "shotgun" and dist > ideal and now - (data.pressAt or 0) > 3 then
        data.pressAt = now
        data.combatMoveAt = now
        local dir = enemy:GetPos() - npc:GetPos()
        dir.z = 0 dir:Normalize()
        local dest = CAI.Nav.SafeGround(enemy:GetPos() - dir * ideal * 0.6)
        if dest and safeDest(dest) then CAI.Nav.MoveTo(data, dest, "run") end
    elseif dist > maxRange then
        if now - (data.advanceAt or 0) > 1.8 then
            data.advanceAt = now
            data.combatMoveAt = now
            data.fighting = nil
            local dir = enemy:GetPos() - npc:GetPos()
            dir.z = 0 dir:Normalize()
            local step = math.min(dist - ideal, 400)
            local dest = CAI.Nav.SafeGround(npc:GetPos() + dir * step)
                      or CAI.Nav.SafeOffset(npc:GetPos(), dir, step)
            if dest and safeDest(dest) then
                CAI.Nav.MoveTo(data, dest, "run")
                if math.random() < 0.3 then CAI.Voice.Speak(data, "moving") end
            end
        end
    else
        if now - (data.advanceAt or 0) > 2 then
            data.advanceAt = now
            npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        end
    end
    CAI.FriendlyFire.Update(data)
end

Exec[3] = function(data)
    local npc = data.ent
    local dangerAvoid = CAI.CVBool("cai_danger_avoid")
    local enemy, rec = BR.CombatTarget(data)
    local enemyPos = rec and rec.pos or (IsValid(enemy) and enemy:GetPos())

    CAI.Cover.UpdateCoverStatus(data, enemy)

    if not data.cover then
        local pos = CAI.Cover.FindBest(data, enemy, enemyPos)
        if not pos and CurTime() - (data.nodeCoverAt or 0) > 3 then
            data.nodeCoverAt = CurTime()
            npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
        end
        if pos then
            if dangerAvoid and CAI.Memory.AvoidPos(data, pos, CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius) then
                pos = nil
            end
        end
        if pos then
            data.cover = { pos = pos, since = CurTime() }
            data.coverBounces = (data.coverBounces or 0) + 1
            data.coverSearchFailures = 0
            CAI.Nav.MoveTo(data, pos, "run")
            if math.random() < 0.25 then CAI.Voice.Speak(data, "cover_me") end
        else
            data.coverSearchFailures = (data.coverSearchFailures or 0) + 1
            if data.coverSearchFailures >= 4 then
                data.coverSearchFailures = 0
                BR.SetState(data, CAI.STATE.ENGAGE, "no_cover_available")
                return
            end
            if CurTime() - (data.engCoverAt or 0) > 3 then
                data.engCoverAt = CurTime()
                npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
            end
            return
        end
    end

    if data.cover and not CAI.Nav.Arrived(data, 80) then
        local inGo = npc.IsCurrentSchedule and (npc:IsCurrentSchedule(SCHED_FORCED_GO)
            or npc:IsCurrentSchedule(SCHED_FORCED_GO_RUN))
        if not inGo and CurTime() - (data.moveIssuedAt or 0) > 1.0 then
            CAI.Nav.MoveTo(data, data.cover.pos, "run")
        end
    end

    if data.lastDecision == "reloading_cover" then
        local wep = npc:GetActiveWeapon()
        if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 then
            if CurTime() - (data.forceReloadAt or 0) > 2 then
                data.forceReloadAt = CurTime()
                data.coverPhase = nil
                data.moveTarget = nil
                npc:SetSchedule(SCHED_RELOAD)
            end
            return
        end
        if IsValid(wep) and wep.Clip1 and wep:Clip1() > 0 then
            data.forceReloadAt = nil
            local engaged = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
                and npc:GetPos():Distance(enemy:GetPos()) <= CAI.WeaponIntel.OwnRange(npc)
            if not engaged and data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc
               and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 900 * 900 then
                data.cover = nil
                CAI.Brain.SetState(data, CAI.STATE.REGROUP, "reloaded_regroup")
                return
            end
        end
    end

    if CAI.Nav.Arrived(data, 80) then
        local aggro = CAI.CVNum("cai_aggression")
        local now = CurTime()
        if CAI.Suppression.IsPinned(data) and aggro < 0.95 then
            if data.coverPhase ~= "duck" then
                data.coverPhase = "duck"
                data.coverPhaseEnd = now + 2 * (1.3 - aggro)
                npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
            end
            if now > (data.coverPhaseEnd or 0) then data.coverPhase = nil end
        elseif now > (data.coverPhaseEnd or 0) then
            if data.coverPhase == "pop" then
                data.coverPhase = "duck"
                data.coverPhaseEnd = now + math.Rand(1.0, 1.8) * (1.3 - aggro)
                npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
            else
                if dangerAvoid and CAI.Memory.AvoidPos(data, npc:GetPos(), CAI.Config.SelfPreserve.DangerAvoid.AdvanceIntoRadius)
                   and not (IsValid(enemy) and CAI.Util.Sees(npc, enemy)) then
                    data.coverPhase = "duck"
                    data.coverPhaseEnd = now + math.Rand(1.0, 1.8) * (1.3 - aggro)
                    npc:SetSchedule(SCHED_TAKE_COVER_FROM_ENEMY)
                else
                    data.coverPhase = "pop"
                    data.coverPhaseEnd = now + math.Rand(2.2, 3.4)
                    data.coverBounces = 0
                    data.lastEngageAt = now
                    local _, prec = BR.CombatTarget(data)
                    if prec and not CAI.Util.CanSeePos(npc, prec.pos + Vector(0, 0, 40))
                       and CurTime() - (prec.t or 0) < 4 then
                        CAI.Brain.Prefire(data, prec.pos)
                    else
                        npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
                    end
                end
            end
        end
    end
    CAI.FriendlyFire.Update(data)
end

Exec[4] = function(data)
    local npc = data.ent
    if not data.flank then
        local _, rec = CAI.Memory.FreshestEnemy(data)
        if not rec or not CAI.Flank.Begin(data, rec.pos) then
            BR.SetState(data, CAI.STATE.COVER, "flank_unavailable")
            return
        end
    end
    if not CAI.Flank.Update(data) then
        local enemy, rec = CAI.Memory.FreshestEnemy(data)
        if IsValid(enemy) and npc.SetEnemy then npc:SetEnemy(enemy) end
        data.lastFlankAt = CurTime()
        BR.SetState(data, CAI.STATE.ENGAGE, "flank_complete")
    end
end

local function StopSuppressing(data)
    if IsValid(data.suppBullseye) then data.suppBullseye:Remove() end
    data.suppBullseye = nil
end
BR.StopSuppressing = StopSuppressing

Exec[5] = function(data)
    local npc = data.ent
    local enemy, rec = BR.CombatTarget(data)
    if not rec then
        StopSuppressing(data)
        data.suppNoLosAt = nil
        BR.SetState(data, CAI.STATE.COVER, "nothing_to_suppress")
        return
    end

    if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < 200 * 200 then
        StopSuppressing(data)
        data.suppNoLosAt = nil
        if npc.SetEnemy then npc:SetEnemy(enemy) end
        BR.SetState(data, CAI.STATE.ENGAGE, "too_close_suppress")
        return
    end

    if data.squad and IsValid(data.squad.leader) and data.squad.leader ~= npc then
        local canFight = IsValid(enemy) and CAI.Util.Sees(npc, enemy)
        if not canFight and npc:GetPos():DistToSqr(data.squad.leader:GetPos()) > 900 * 900 then
            StopSuppressing(data)
            data.suppNoLosAt = nil
            if npc.SetEnemy then npc:SetEnemy(NULL) end
            CAI.Nav.MoveTo(data, data.squad.leader:GetPos(), "run")
            return
        end
        data.moveTarget = nil
        data.moveIssuedAt = nil
    end

    local now = CurTime()
    if IsValid(enemy) and CAI.Util.Sees(npc, enemy) then
        StopSuppressing(data)
        data.suppNoLosAt = now
        if npc.SetEnemy then npc:SetEnemy(enemy) end
        if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(enemy, rec.pos) end
    else
        if not data.suppNoLosAt then data.suppNoLosAt = now end
        if now - data.suppNoLosAt > 8 then
            StopSuppressing(data)
            data.suppNoLosAt = nil
            CAI.Memory.SeeEnemy(data, enemy, rec.pos)
            BR.SetState(data, CAI.STATE.SEARCH, "suppress_no_los")
            return
        end
        local aim
        for _, b in ipairs(CAI.Cover.Barrels()) do
            if IsValid(b) and b:GetPos():DistToSqr(rec.pos) < 170 * 170
               and CAI.Util.CanSeePos(npc, b:GetPos() + Vector(0, 0, 10)) then
                aim = b:GetPos() + Vector(0, 0, 10)
                break
            end
        end
        for _, h in ipairs({ 55, 90 }) do
            if aim then break end
            local p = rec.pos + Vector(0, 0, h)
            if CAI.Util.CanSeePos(npc, p) then aim = p break end
        end
        if not aim and CAI.CVBool("cai_wallbang") then
            aim = rec.pos + Vector(0, 0, 55)
        end
        if not aim then
            aim = rec.pos + Vector(0, 0, 40)
        end
        if aim then
            local bull = data.suppBullseye
            if not IsValid(bull) then
                bull = ents.Create("npc_bullseye")
                if IsValid(bull) then
                    bull:SetPos(aim)
                    bull:SetKeyValue("spawnflags", "196608")
                    bull:Spawn()
                    bull:SetNoDraw(true)
                    bull:SetSolid(SOLID_NONE)
                    bull:SetHealth(999999)
                    data.suppBullseye = bull
                    npc:AddEntityRelationship(bull, D_HT, 99)
                end
            else
                bull:SetPos(aim)
            end
            if IsValid(bull) and npc.SetEnemy then
                npc:SetEnemy(bull)
                if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(bull, aim) end
            end
        else
            if IsValid(enemy) and npc:GetPos():DistToSqr(enemy:GetPos()) < 400 * 400 then
                StopSuppressing(data)
                if npc.SetEnemy then npc:SetEnemy(enemy) end
                BR.SetState(data, CAI.STATE.ENGAGE, "suppressed_no_target")
                return
            end
        end
    end

    if not data.suppFaced then
        data.suppFaced = true
        npc:SetSchedule(SCHED_COMBAT_FACE)
    end
    if not data.saidSuppress then
        data.saidSuppress = true
        CAI.Voice.Speak(data, "suppressing")
        if data.squad then
            local sa = data.squad.blackboard.suppressedAt
            sa[#sa + 1] = { pos = rec.pos, t = CurTime() }
            if #sa > 6 then table.remove(sa, 1) end
            CAI.Squad.Broadcast(data.squad, "suppression_active", data.ent, { pos = rec.pos })
        end
    end
    if not data.suppressUntil or CurTime() > data.suppressUntil then
        data.saidSuppress = false
        data.suppNoLosAt = nil
        BR.SetState(data, CAI.STATE.COVER, "suppress_done")
    end
end

Exec[6] = function(data)
    if not data.search then
        local enemy, rec = CAI.Memory.FreshestEnemy(data)
        if not rec or not CAI.Search.Begin(data, enemy, rec.pos) then
            BR.SetState(data, CAI.STATE.PATROL, "nothing_to_search")
            return
        end
    end
    if not CAI.Search.Update(data) then
        BR.SetState(data, CAI.STATE.PATROL, "search_over")
    end
end

Exec[7] = function(data)
    local npc = data.ent

    if data.lastDecision == "escape_encirclement" then
        local ecfg = CAI.Config.Escape
        local now = CurTime()
        local count, nearest, nearDist, centroid = BR.MeleeThreatScan(data)

        if nearDist > ecfg.ClearDist and count < ecfg.SurroundCount
           and now - (data.lastMeleeHurtAt or 0) > ecfg.MeleeHitGrace then
            data.saidRetreat = false
            local wep = npc:GetActiveWeapon()
            if IsValid(wep) and wep.Clip1 and wep:Clip1() == 0 then
                BR.SetState(data, CAI.STATE.COVER, "reloading_cover")
            else
                BR.SetState(data, CAI.STATE.ENGAGE, "engage_target")
            end
            return
        end

        local ref = centroid or (IsValid(nearest) and nearest:GetPos()) or data.escapeCentroid
        if IsValid(nearest) and CurTime() - (data.shoveAt or 0) > 1.5
           and npc.CapabilitiesGet
           and bit.band(npc:CapabilitiesGet(), CAP_INNATE_MELEE_ATTACK1) ~= 0
           and npc:GetPos():DistToSqr(nearest:GetPos()) < ecfg.ShoveRange * ecfg.ShoveRange then
            data.shoveAt = now
            if npc.SetEnemy then npc:SetEnemy(nearest) end
            npc:SetSchedule(SCHED_MELEE_ATTACK1)
            return
        end

        if now - (data.escapeMoveAt or 0) > 1.0 then
            data.escapeMoveAt = now
            local away = ref and (npc:GetPos() - ref) or Vector(1, 0, 0)
            away.z = 0
            if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
            away:Normalize()
            local yaw = away:Angle().y
            local dest
            for _, off in ipairs({ 0, 45, -45, 90, -90 }) do
                local dir = Angle(0, yaw + off, 0):Forward()
                dest = CAI.Nav.SafeOffset(npc:GetPos(), dir, ecfg.Step)
                if dest then break end
            end
            if dest then CAI.Nav.MoveTo(data, dest, "run") end
            if not data.saidRetreat then
                data.saidRetreat = true
                CAI.Voice.Speak(data, "retreat")
            end
        end
        return
    end

    if data.scatterFrom and data.scatterUntil and CurTime() < data.scatterUntil then
        local away = npc:GetPos() - data.scatterFrom
        away.z = 0
        if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
        away:Normalize()
        local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 280)
        if dest then CAI.Nav.MoveTo(data, dest, "run") end
        return
    end
    local unarmed = data.lastDecision == "unarmed_flee"
    if unarmed and CurTime() - (data.hideAt or 0) > 2 then
        data.hideAt = CurTime()
        local _, rec = CAI.Memory.FreshestEnemy(data)
        local threat = rec and rec.pos
        local spot = threat and CAI.Cover.FindBest(data, nil, threat)
        if spot then
            CAI.Nav.MoveTo(data, spot, "run")
        elseif threat then
            local away = (npc:GetPos() - threat); away.z = 0; away:Normalize()
            local dest = CAI.Nav.SafeOffset(npc:GetPos(), away, 700) or npc:GetPos()
            CAI.Nav.MoveTo(data, dest, "run")
        end
        if not data.saidRetreat then
            data.saidRetreat = true
            CAI.Voice.Speak(data, "panic")
        end
        return
    end

    if CurTime() - (data.retreatAt or 0) > 3 then
        data.retreatAt = CurTime()
        local _, rec = CAI.Memory.FreshestEnemy(data)
        if rec then
            local away = (npc:GetPos() - rec.pos); away.z = 0; away:Normalize()
            local yaw = away:Angle().y
            local dest
            for _, off in ipairs({ 0, 60, -60, 120 }) do
                local dir = Angle(0, yaw + off, 0):Forward()
                dest = CAI.Nav.RandomPointNear(npc:GetPos() + dir * 800, 400)
                if dest then break end
            end
            dest = dest or CAI.Nav.SafeOffset(npc:GetPos(), away, 600) or npc:GetPos()
            CAI.Nav.MoveTo(data, dest, "run")
        elseif not data.fleeSched then
            data.fleeSched = true
            npc:SetSchedule(SCHED_RUN_FROM_ENEMY)
        end
        if not data.saidRetreat then
            data.saidRetreat = true
            CAI.Voice.Speak(data, "retreat")
            if data.squad then CAI.Squad.Broadcast(data.squad, "retreating", npc) end
        end
    end

    if data.morale > CAI.Config.Morale.ShakenThreshold + 10 then
        data.saidRetreat = false
        BR.SetState(data, CAI.STATE.COVER, "morale_recovered")
    end
end

Exec[8] = function(data)
    local npc = data.ent
    local visEnemy, visRec = CAI.Memory.FreshestEnemy(data)
    if IsValid(visEnemy) and CAI.Util.CanSee(npc, visEnemy) then
        BR.SetState(data, CAI.STATE.ENGAGE, "spotted_during_investigate")
        return
    end
    if not data.investigatePos or CurTime() > (data.investigateUntil or 0) then

        if data.investigatePos then
            data.lastInvestigate = { pos = data.investigatePos, t = CurTime() }
        end
        data.investigatePos = nil
        BR.SetState(data, CAI.STATE.PATROL, "investigation_over")
        return
    end
    if data.moveTarget and CAI.Nav.Arrived(data, 100) then
        if not data.investFaced then
            data.investFaced = true
            data.moveTarget = nil
            npc:SetSchedule(SCHED_COMBAT_FACE)
            data.investigateUntil = math.min(data.investigateUntil, CurTime() + 3)
        end
    else
        data.investFaced = nil
        CAI.Nav.MoveTo(data, data.investigatePos, "walk")
    end
end

Exec[9] = function(data)
    local npc = data.ent
    local squad = data.squad
    if not squad or not IsValid(squad.leader) or squad.leader == npc then
        BR.SetState(data, CAI.STATE.PATROL, "no_squad_to_regroup")
        return
    end

    local visEnemy, visRec = CAI.Memory.FreshestEnemy(data)
    if IsValid(visEnemy) and CAI.Util.CanSee(npc, visEnemy) then
        data.reinforceTarget = nil
        BR.SetState(data, CAI.STATE.ENGAGE, "spotted_during_regroup")
        return
    end

    if data.reinforceTarget then
        if npc:GetPos():DistToSqr(data.reinforceTarget) < 90 * 90 then
            data.reinforceTarget = nil
            BR.SetState(data, CAI.STATE.PATROL, "reinforced")
            return
        end
        CAI.Nav.MoveTo(data, data.reinforceTarget, "run")
        return
    end

    local idx = 0
    for _, m in ipairs(squad.members) do
        if m ~= squad.leader then
            idx = idx + 1
            if m == data.ent then break end
        end
    end
    local slot = CAI.Squad.FormationSlot(squad, idx)
    if slot and CurTime() - (data.regroupAt or 0) > 1.5 then
        data.regroupAt = CurTime()
        CAI.Nav.MoveTo(data, slot, "run")
    end
    if data.moveTarget and CAI.Nav.Arrived(data, 90) then
        BR.SetState(data, CAI.STATE.PATROL, "in_formation")
    end
end

Exec[10] = function(data)
    local npc = data.ent
    local squad = data.squad
    if not squad or not squad.clearingDoor then
        BR.SetState(data, CAI.STATE.PATROL, "no_door_to_clear")
        return
    end
    local door = squad.clearingDoor
    if not data.clearPhase then
        data.clearPhase = "approach"
        data.clearAngle = 0
        data.clearSliceStart = nil
        local doorDir = (door.pos - npc:GetPos()):GetNormalized()
        doorDir.z = 0
        local approachPos = door.pos - door.normal * 60
        local safeApproach = CAI.Nav.SafeGround(approachPos) or approachPos
        CAI.Nav.MoveTo(data, safeApproach, "run")
    end
    if data.clearPhase == "approach" then
        if CAI.Nav.Arrived(data, 80) then
            data.clearPhase = "slice"
            data.clearSliceStart = CurTime()
            data.clearAngle = -CAI.Config.SquadTactics.ClearSliceMax
            data.moveTarget = nil
            npc:SetSchedule(SCHED_COMBAT_FACE)
        end
        return
    end
    if data.clearPhase == "slice" then
        local cfg = CAI.Config.SquadTactics
        local sliceAngle = data.clearAngle or 0
        local lookDir = door.normal:Angle()
        lookDir.y = lookDir.y + sliceAngle
        local lookFwd = lookDir:Forward()
        npc:SetAngles(lookDir)
        local checkPos = door.pos + lookFwd * 200 + Vector(0, 0, 40)
        local enemyDetected = false
        for e, _ in pairs(data.memory.enemies) do
            if IsValid(e) and CAI.Util.CanSeePos(npc, e:GetPos() + Vector(0, 0, 40)) then
                enemyDetected = true
                break
            end
        end
        if not enemyDetected then
            local tr = util.TraceLine({
                start = npc:EyePos(),
                endpos = checkPos,
                filter = npc,
                mask = MASK_BLOCKLOS,
            })
            if not tr.Hit then
                local _, rec = CAI.Memory.FreshestEnemy(data)
                if rec and checkPos:DistToSqr(rec.pos) < 300 * 300 then
                    enemyDetected = true
                end
            end
        end
        if enemyDetected then
            data.clearPhase = nil
            door.done = true
            BR.SetState(data, CAI.STATE.ENGAGE, "enemy_in_room")
            return
        end
        data.clearAngle = sliceAngle + cfg.ClearSliceAngle
        if data.clearAngle > cfg.ClearSliceMax then
            data.clearPhase = "entry"
            local entryDest = door.pos + door.normal * 150
            local farCorner = entryDest + Vector(-door.normal.y, door.normal.x, 0) * 100
            local safeEntry = CAI.Nav.SafeGround(farCorner) or CAI.Nav.SafeGround(entryDest) or entryDest
            CAI.Nav.MoveTo(data, safeEntry, "run")
        end
        if CurTime() - (data.clearSliceStart or 0) > 8 then
            data.clearPhase = nil
            door.done = true
            BR.SetState(data, CAI.STATE.PATROL, "clear_timeout")
        end
        return
    end
    if data.clearPhase == "entry" then
        if CAI.Nav.Arrived(data, 80) then
            data.clearPhase = nil
            door.done = true
            CAI.Voice.Speak(data, "clear")
            if data.squad then
                CAI.Squad.Broadcast(data.squad, "clear", data.ent)
            end
            BR.SetState(data, CAI.STATE.PATROL, "room_cleared")
        end
        return
    end
    data.clearPhase = nil
    door.done = true
    BR.SetState(data, CAI.STATE.PATROL, "clear_error")
end

Exec[11] = function(data)
    local npc = data.ent
    if not data.boundTarget then
        BR.SetState(data, CAI.STATE.COVER, "no_bound_target")
        return
    end
    local moving = data.moveTarget ~= nil and not CAI.Nav.Arrived(data, 70)
    if moving then
        CAI.FriendlyFire.Update(data)
        return
    end
    if not data.boundArrived then
        data.boundArrived = CurTime()
        data.fighting = nil
        npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
    end
    local fireDuration = CAI.Config.SquadTactics.BoundFireDuration
    local cornerpush = CAI.CVBool("cai_cornerpush")
    if CurTime() - data.boundArrived > fireDuration then
        local confident = true
        if cornerpush then
            local ct = CAI.Config.SelfPreserve.CornerPush.ConfidenceTime
            confident = (CurTime() - data.boundArrived > ct)
                and (CurTime() - (data.lastHurtAt or 0) > ct)
        end
        if confident then
            data.boundTarget = nil
            data.boundArrived = nil
            data.staggerOffset = nil
            if data.squad and data.squad.leader and data.squad.leader ~= npc then
                BR.SetState(data, CAI.STATE.REGROUP, "bound_complete_regroup")
            else
                BR.SetState(data, CAI.STATE.ENGAGE, "aggressive_push")
            end
        else
            data.boundArrived = CurTime()
            data.fighting = nil
            npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        end
    else
        if cornerpush and (CurTime() - (data.lastHurtAt or 0) < 0.5) then
            data.boundArrived = CurTime()
        end
        CAI.FriendlyFire.Update(data)
    end
end

function BR.Prefire(data, pos)
    local npc = data.ent
    if not CAI.CVBool("cai_suppression") then
        npc:SetSchedule(SCHED_ESTABLISH_LINE_OF_FIRE)
        return
    end
    local aim = pos + Vector(0, 0, 40)
    local bull = data.suppBullseye
    if not IsValid(bull) then
        bull = ents.Create("npc_bullseye")
        if not IsValid(bull) then return end
        bull:SetPos(aim)
        bull:SetKeyValue("spawnflags", "196608")
        bull:Spawn()
        bull:SetNoDraw(true)
        bull:SetSolid(SOLID_NONE)
        bull:SetHealth(999999)
        data.suppBullseye = bull
        npc:AddEntityRelationship(bull, D_HT, 99)
    else
        bull:SetPos(aim)
    end
    if npc.SetEnemy then
        npc:SetEnemy(bull)
        if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(bull, aim) end
    end
    data.prefireUntil = CurTime() + 1.2
end

function BR.Think(data, dt)
    local npc = data.ent
    if not CAI.Util.Alive(npc) then return end

    local classInfo = CAI.Config.NPCClasses[npc:GetClass()]
    if classInfo and classInfo.lightTouch then
        local _tp = CAI.Prof.active and SysTime() or 0
        Perceive(data)
        if _tp ~= 0 then CAI.Prof.Record("brain_perceive", SysTime() - _tp) end
        CAI.Memory.Fade(data)
        CAI.Suppression.Decay(data, dt)
        CAI.Morale.Regen(data, dt)
        return
    end

    do
        local _tp = CAI.Prof.active and SysTime() or 0
        Perceive(data)
        if _tp ~= 0 then CAI.Prof.Record("brain_perceive", SysTime() - _tp) end
    end
    CAI.Memory.Fade(data)
    CAI.Suppression.Decay(data, dt)
    CAI.Morale.Regen(data, dt)
    CAI.Personality.ApplyProficiency(data)
    CAI.Nav.CheckStuck(data)

    local newState, reason
    do
        local _td = CAI.Prof.active and SysTime() or 0
        newState, reason = Decide(data)
        if _td ~= 0 then CAI.Prof.Record("brain_decide", SysTime() - _td) end
    end
    BR.SetState(data, newState, reason)

    local exec = Exec[data.state]
    if exec then
        local label = "exec_" .. (CAI.STATE_NAMES[data.state] or tostring(data.state))
        local _te = CAI.Prof.active and SysTime() or 0
        exec(data)
        if _te ~= 0 then CAI.Prof.Record(label, SysTime() - _te) end
    end

    if data.prefireUntil then
        local e = npc.GetEnemy and npc:GetEnemy()
        if CurTime() > data.prefireUntil or (IsValid(e) and e:GetClass() ~= "npc_bullseye") then
            data.prefireUntil = nil
            if data.state ~= CAI.STATE.SUPPRESS then BR.StopSuppressing(data) end
        end
    end
    if data.state ~= CAI.STATE.SUPPRESS and not data.prefireUntil and IsValid(data.suppBullseye) then
        BR.StopSuppressing(data)
    end

    if CAI.CVBool("cai_npc_regen") and npc:Health() < npc:GetMaxHealth()
       and CurTime() - (data.lastHurtAt or 0) > 6 then
        npc:SetHealth(math.min(npc:GetMaxHealth(), npc.Health() + 9 * dt))
    end
end

CAI.Prof.WrapFn(BR, "Prefire", "brain_prefire")
