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

    local _tr = CAI.Prof.active and SysTime() or 0
    BR.Reflex(data, dt)
    if _tr ~= 0 then CAI.Prof.Record("brain_reflex", SysTime() - _tr) end

    local urgency = data.reflex and data.reflex.urgency
    local planExpired = data.plan and CurTime() >= data.plan.expiresAt
    if planExpired or urgency or data.planPending then
        local _to = CAI.Prof.active and SysTime() or 0
        BR.OODA(data)
        if _to ~= 0 then CAI.Prof.Record("brain_ooda", SysTime() - _to) end
    end

    CAI.FireAim.Tick(data)

    local exec = BR.ExecPhase[data.phase]
    if exec then
        local label = "exec_" .. (CAI.PHASE_NAMES[data.phase] or tostring(data.phase))
        local _te = CAI.Prof.active and SysTime() or 0
        exec(data)
        if _te ~= 0 then CAI.Prof.Record(label, SysTime() - _te) end
    end

    -- Retaliate: brief fire-back at whoever just hit us
    BR.Retaliate(data)

    if CAI.CVBool("cai_npc_regen") and npc:Health() < npc:GetMaxHealth()
       and CurTime() - (data.lastHurtAt or 0) > 6 then
        npc:SetHealth(math.min(npc:GetMaxHealth(), npc:Health() + 9 * dt))
    end
end
