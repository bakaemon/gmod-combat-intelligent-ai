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

    local exec = BR.Exec[data.state]
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

