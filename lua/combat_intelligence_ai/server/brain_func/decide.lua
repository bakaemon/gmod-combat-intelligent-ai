local BR = CAI.Brain

-- Decide: the brain's "thinking". A priority-ordered cascade of early returns.
-- Order matters: most urgent first:
--   emergency overrides -> melee/swarm -> broken morale -> panic -> unarmed
--   -> visible target handling -> lost-target handling -> squad battle awareness
--   -> regroup -> patrol.
-- Pure: never moves the NPC or sets schedules, just picks a state + reason.
BR.Decide = function(data)
    local S = CAI.STATE
    local npc = data.ent

    data.combatTarget = nil
    data.combatRec = nil

    -- Forced relocation: a player aimed at us long enough, bail from current
    -- cover immediately and pick a fresh one.
    if data.forceRecover then
        data.forceRecover = nil
        return S.COVER, "emergency_relocate"
    end

    -- Grenade scatter: run away from the thrown grenade for a short window.
    if data.scatterUntil then
        if CurTime() < data.scatterUntil then
            return S.RETREAT, "grenade_scatter"
        end
        data.scatterFrom, data.scatterUntil = nil, nil
    end

    -- Swarm / melee-encirclement check: if crowded, point-blank, or recently
    -- melee-hit, fight back (point-blank) or flee rather than standing still.
    do
        local ownWep = npc.GetActiveWeapon and npc:GetActiveWeapon()
        if IsValid(ownWep) and not CAI.WeaponIntel.IsMelee(npc) then
            local ecfg = CAI.Config.Escape
            local count, nearest, nearDist, centroid = BR.MeleeThreatScan(data)
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

    -- Morale broken: flee unless cornered with an empty weapon (desperate
    -- melee swing) when cai_meleepanic is on.
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
                -- Recently seen but not close: advance to the last-known spot
                -- to reacquire, rather than camping in cover (reacquire_advance).
                data.investigatePos = rec.pos
                data.investigateUntil = CurTime() + 6
                return S.INVESTIGATE, "reacquire_advance"
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
                -- Heard nearby friendly battle: commit to investigating it
                -- unless we're holding unknown angles and not pushing/flanking.
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
    -- Nothing to do: fall back to patrolling.
    return S.PATROL, "all_quiet"
end
