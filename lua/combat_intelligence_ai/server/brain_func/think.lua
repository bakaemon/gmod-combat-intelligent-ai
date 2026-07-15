local BR = CAI.Brain

function BR.Think(data, dt)
    local npc = data.ent
    if not CAI.Util.Alive(npc) then return end

    local classInfo = CAI.Config.NPCClasses[npc:GetClass()]
    if classInfo and classInfo.lightTouch then
        local _tp = CAI.Prof.active and SysTime() or 0
        BR.Perceive(data)
        if _tp ~= 0 then CAI.Prof.Record("brain_perceive", SysTime() - _tp) end
        CAI.Memory.Fade(data)
        CAI.Suppression.Decay(data, dt)
        CAI.Morale.Regen(data, dt)
        return
    end

    do
        local _tp = CAI.Prof.active and SysTime() or 0
        BR.Perceive(data)
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
        newState, reason = BR.Decide(data)
        if _td ~= 0 then CAI.Prof.Record("brain_decide", SysTime() - _td) end
    end
    BR.SetState(data, newState, reason)

    -- Reactive interrupt dispatch: an Exec handler may call SetState to switch
    -- state mid-think. Re-dispatch the new state in the SAME tick, guarded
    -- against A<->B oscillation by a visited set + hard cap. This removes the
    -- "telephone game" latency between an environment-forced reaction and the
    -- NPC actually performing it.
    local MAX_REDISPATCH = 2
    local seen = {}
    local redispatch = 0
    repeat
        seen[data.state] = true
        local s = data.state
        local exec = BR.Exec[s]
        if exec then
            local label = "exec_" .. (CAI.STATE_NAMES[s] or tostring(s))
            local _te = CAI.Prof.active and SysTime() or 0
            exec(data)
            if _te ~= 0 then CAI.Prof.Record(label, SysTime() - _te) end
        end
         redispatch = redispatch + 1
     until seen[data.state] or redispatch > MAX_REDISPATCH

     -- Reactive flinch layer: a low-level defensive movement RULE that runs under
     -- the state machine. It may bias movement (run-and-gun jink) but never
     -- changes state, so it cannot interrupt the active plan. Deferred during a
     -- committed weapon wind-up. See brain_func/react.lua.
    BR.Flinch(data)

    if data.prefireUntil then
        local e = npc.GetEnemy and npc:GetEnemy()
        if CurTime() > data.prefireUntil or (IsValid(e) and e:GetClass() ~= "npc_bullseye") then
            data.prefireUntil = nil
            if data.state ~= CAI.STATE.SUPPRESS then BR.StopSuppressing(data) end
        end
    end
    -- Tidy up: drop the bullseye proxy once we're neither suppressing nor
    -- prefiring, so it can't linger and confuse the NPC's real target.
    if data.state ~= CAI.STATE.SUPPRESS and not data.prefireUntil and IsValid(data.suppBullseye) then
        BR.StopSuppressing(data)
    end

    if CAI.CVBool("cai_npc_regen") and npc:Health() < npc:GetMaxHealth()
       and CurTime() - (data.lastHurtAt or 0) > 6 then
        npc:SetHealth(math.min(npc:GetMaxHealth(), npc:Health() + 9 * dt))
    end
end
