local BR = CAI.Brain
local C = CAI.Config

--[[
    react.lua: the Flinch layer.

    Evade is modelled here as a LOW-LEVEL DEFENSIVE RULE, not a brain state.
    It runs every tick AFTER the state machine (see think.lua) and only ever
    biases MOVEMENT — it never calls SetState, so it cannot interrupt
    COVER / RETREAT / ENGAGE / FLANK / SUPPRESS.

    Design rules:
      * It follows the plan's intent; it never changes the state or the plan's
        high-level destination.
      * If the plan is already in effective cover, SUPPRESS, or already returning
        fire from a hold, Flinch yields entirely.
      * While repositioning under fire it runs-and-guns: with move-shoot available
        it issues SCHED_CHASE_ENEMY so the NPC fires while moving. The defensive
        journey (lean toward cover / lateral dodge) is preserved; only the
        schedule changes.
      * Committed weapon wind-ups (energy ball / melee swing) are never
        interrupted.
--]]

function BR.IsCommitted(data)
    local npc = data.ent
    if not (npc.IsCurrentSchedule) then return false end
    -- Committed weapon wind-ups (basic fire, secondary attacks, melee swings)
    -- are uninterruptible so the flinch layer never resets a live shot or a
    -- grenade wind-up mid-sequence.
    return npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1)
        or npc:IsCurrentSchedule(SCHED_RANGE_ATTACK2)
        or npc:IsCurrentSchedule(SCHED_MELEE_ATTACK1)
end

function BR.UnderFire(data)
    return (data.suppression or 0) > C.Flinch.UnderFireAt
end

local function clearFlinch(data)
    data.flinchActive = nil
    data.flinchPhase = nil
    data.flinchPhaseEnd = nil
    data.flinchNextPlan = nil
    data.flinchTarget = nil
    data.flinchCover = nil
end

local function applyLateral(dir, maxDeg)
    local ang = math.rad(math.Rand(-maxDeg, maxDeg))
    local c, s = math.cos(ang), math.sin(ang)
    return Vector(dir.x * c - dir.y * s, dir.x * s + dir.y * c, 0)
end

local function resolveDest(src, dir, dist)
    local dest = CAI.Nav.SafeOffset(src, dir, dist)
    if not dest then dest = CAI.Nav.RandomPointNear(src, dist, false) end
    return dest
end

local function computeFlinchDest(data)
    local npc = data.ent
    local src = npc:GetPos()
    local enemy = npc:GetEnemy()
    local enemyPos = IsValid(enemy) and enemy:GetPos() or nil

    -- Throttle the (costly) cover search to the replan cadence.
    if not data.flinchCover then
        data.flinchCover = CAI.Cover.FindBest(data, enemy, enemyPos)
    end

    if data.moveTarget then
        -- Plan is already moving: bias its direction, keep destination dominant.
        local base = data.moveTarget - src
        base.z = 0
        if base:LengthSqr() < 1 then base = Vector(1, 0, 0) end
        base:Normalize()

        if data.flinchCover then
            local toCov = data.flinchCover - data.moveTarget
            toCov.z = 0
            if toCov:LengthSqr() < (C.Cover.SearchRadius * 0.4) ^ 2 then
                base = (base + toCov:GetNormalized() * C.Flinch.CoverLean):GetNormalized()
            end
        end

        base = applyLateral(base, C.Flinch.JinkAngleMax)
        return resolveDest(src, base, math.Rand(C.Flinch.JinkDistMin, C.Flinch.JinkDistMax))
    end

    -- Plan is holding: inject a purposeful reposition.
    if data.flinchCover then
        local dir = data.flinchCover - src
        dir.z = 0
        if dir:LengthSqr() > 1 then
            dir = dir:GetNormalized()
            local step = math.min(src:Distance(data.flinchCover),
                                  math.Rand(C.Flinch.JinkDistMin, C.Flinch.JinkDistMax))
            return resolveDest(src, dir, step)
        end
    end

    -- No cover: break the firing line with a bounded lateral displacement.
    local ref = enemyPos
    if not ref then
        local atk = data.lastAttacker
        ref = IsValid(atk) and atk:GetPos() or src
    end
    local away = src - ref
    away.z = 0
    if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
    away:Normalize()
    local right = Vector(-away.y, away.x, 0)
    local dir = (away * 0.3 + right * math.Rand(-1, 1)):GetNormalized()
    return resolveDest(src, dir, math.Rand(C.Flinch.JinkDistMin, C.Flinch.JinkDistMax))
end

function BR.Flinch(data)
    if not CAI.CVBool("cai_hurt_react") or CAI.CVBool("cai_performance_mode") then
        return
    end
    local npc = data.ent
    local now = CurTime()

    -- Gate: recently hit + under fire + not mid committed wind-up.
    if BR.IsCommitted(data) or (now - (data.lastHurtAt or 0)) <= 0
       or (now - (data.lastHurtAt or 0)) > C.Suppression.HurtGraceMax
       or not BR.UnderFire(data) then
        clearFlinch(data)
        return
    end

    -- Branch 1: SUPPRESS -> moving would cancel the bullseye proxy.
    -- Branch 2: genuinely sheltered (enemy cannot see the NPC) -> the COVER /
    -- hold logic owns defense. A mere "near data.cover.pos" no longer suppresses
    -- the jink, because that spot may be exposed (enemy can see the NPC) and the
    -- NPC would otherwise reload/die in the open.
    if data.state == CAI.STATE.SUPPRESS then
        clearFlinch(data)
        return
    end
    local enemy = npc:GetEnemy()
    local genuinelySheltered = IsValid(enemy) and not CAI.Util.CanSee(enemy, npc)
    if genuinelySheltered then
        clearFlinch(data)
        return
    end

    -- Don't walk into a teammate's line of fire.
    if CAI.FriendlyFire.Update(data) then
        return
    end

    -- Re-pick the jink destination on a cadence (anti-thrash + cheap cover search).
    if now >= (data.flinchNextPlan or 0) then
        data.flinchNextPlan = now + math.Rand(C.Flinch.JinkReplanMin, C.Flinch.JinkReplanMax)
        if not data.flinchActive then
            data.flinchActive = true
            data.flinchPhase = "burst"
            data.flinchPhaseEnd = now + math.Rand(C.Flinch.BurstMin, C.Flinch.BurstMax)
        end
        data.flinchTarget = computeFlinchDest(data)
    end

    if not data.flinchTarget then
        clearFlinch(data)
        return
    end

    local moveShoot = CAI.CVBool("cai_move_shoot") and not CAI.CVBool("cai_performance_mode")
    enemy = npc:GetEnemy()
    local firing = npc.IsCurrentSchedule and (npc:IsCurrentSchedule(SCHED_RANGE_ATTACK1)
        or npc:IsCurrentSchedule(SCHED_RANGE_ATTACK2)
        or npc:IsCurrentSchedule(SCHED_MELEE_ATTACK1))
    local canRunGun = moveShoot and IsValid(enemy) and CAI.Util.Sees(npc, enemy)
        and not firing

    if firing then
        -- The plan is already returning fire from a hold; let it continue.
        clearFlinch(data)
        return
    end

    if canRunGun and data.state == CAI.STATE.ENGAGE then
        -- Already moving this way: avoid restarting the schedule every tick.
        if npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_CHASE_ENEMY) then
            return
        end
        -- Run-and-gun: keep the NPC moving while it fires at the enemy.
        -- SCHED_CHASE_ENEMY is the engine's move-and-fire schedule, so the
        -- defensive reposition still returns fire. Scoped to ENGAGE so it never
        -- overrides another state's destination.
        data.moveTarget = nil
        npc:SetSchedule(SCHED_CHASE_ENEMY)
        return
    end

    -- Fallback when move-shoot is off, the enemy isn't visible, or the plan is
    -- holding its own destination: the defensive dodge journey only.
    local mode
    if data.moveTarget then
        mode = data.moveMode or "run"
    else
        if now >= (data.flinchPhaseEnd or 0) then
            if data.flinchPhase == "burst" then
                data.flinchPhase = "run"
                data.flinchPhaseEnd = now + math.Rand(C.Flinch.RunMin, C.Flinch.RunMax)
            else
                data.flinchPhase = "burst"
                data.flinchPhaseEnd = now + math.Rand(C.Flinch.BurstMin, C.Flinch.BurstMax)
            end
        end
        if data.flinchPhase == "burst" then
            local resp = data.enemyWeaponResponse
            if resp and resp.stayHidden then
                mode = "run"
            elseif not moveShoot then
                mode = "run"
            else
                mode = "walk"
            end
        else
            mode = "run"
        end
    end

    CAI.Nav.MoveTo(data, data.flinchTarget, mode)
end
