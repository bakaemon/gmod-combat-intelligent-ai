CAI.Morale = CAI.Morale or {}
local MO = CAI.Morale

function MO.RecentMeleeHits(data)
    local hits = data.meleeHits
    if not hits then return 0 end
    local window = (CAI.Config.Escape and CAI.Config.Escape.MeleeWindow) or 4
    local cutoff = CurTime() - window
    local n = 0
    for i = #hits, 1, -1 do
        if hits[i] >= cutoff then
            n = n + 1
        else
            table.remove(hits, i)
        end
    end
    return n
end

function MO.Add(data, amount, reason)
    if not CAI.CVBool("cai_morale") then return end
    if amount < 0 then
        amount = amount * (1 - math.Clamp(data.personality.stats.courage or 0, -0.5, 0.5))
    end
    local cfg = CAI.Config.Morale
    data.morale = math.Clamp(data.morale + amount, cfg.Min, cfg.Max)
    data.lastMoraleEvent = reason
end

function MO.IsBroken(data) return CAI.CVBool("cai_morale") and data.morale < CAI.Config.Morale.BreakThreshold end
function MO.IsShaken(data) return CAI.CVBool("cai_morale") and data.morale < CAI.Config.Morale.ShakenThreshold end

function MO.Regen(data, dt)
    local base = CAI.Config.Morale.RegenPerTick
    local rate
    if data.state == CAI.STATE.IDLE or data.state == CAI.STATE.PATROL then
        rate = base
    else
        rate = base * 0.35
    end
    if data.squad then
        local allies = 0
        for _, m in ipairs(data.squad.members) do
            if IsValid(m) and m ~= data.ent and m:Health() > 0
               and m:GetPos():DistToSqr(data.ent:GetPos()) < 500 * 500 then
                allies = allies + 1
            end
        end
        rate = rate * (1 + math.min(allies, 4) * 0.3)
    end
    MO.Add(data, rate * dt, "rest")
end

function MO.CheckHealth(data)
    local npc = data.ent
    if not data.lowHealthHit and npc:Health() < npc:GetMaxHealth() * 0.35 then
        data.lowHealthHit = true
        MO.Add(data, CAI.Config.Morale.LowHealth, "low_health")
        CAI.Voice.Speak(data, "hurt")
    end
end

CAI.SafeHook("OnNPCKilled", "CAI_MoraleDeaths", CAI.Prof.Wrap("morale_kill", function(npc, attacker)
    if not CAI.Enabled() then return end
    local cfg = CAI.Config.Morale
    local deadPos = npc:GetPos()
    local victimData = CAI.Manager.Get(npc)

    if victimData then CAI.Voice.Speak(victimData, "death", true) end

    for other, data in pairs(CAI.Manager.All()) do
        if IsValid(other) and other ~= npc then
            local friendly = other:Disposition(npc) == D_LI
            local distOK = other:GetPos():DistToSqr(deadPos) < cfg.AllyDeathRadius * cfg.AllyDeathRadius
            if friendly and distOK then
                MO.Add(data, cfg.AllyDeathNear, "ally_death")
                CAI.Memory.AddDanger(data, deadPos, 200, "ally_died_here")
                local da = data.memory.deadAllies
                da[#da + 1] = { pos = deadPos, t = CurTime() }
                if data.squad then
                    local bda = data.squad.blackboard.deadAllies
                    bda[#bda + 1] = { pos = deadPos, t = CurTime() }
                end
                if IsValid(attacker) and other:Disposition(attacker) == D_HT
                   and CAI.Util.IsTargetable(attacker) then
                    CAI.Memory.HearEnemy(data, attacker, attacker:GetPos())
                end
                if data.state == CAI.STATE.IDLE or data.state == CAI.STATE.PATROL then
                    data.investigatePos = deadPos
                    data.investigateUntil = CurTime() + 10
                    CAI.Brain.SetState(data, CAI.STATE.INVESTIGATE, "squadmate_down")
                    if math.random() < 0.5 then CAI.Voice.Speak(data, "need_backup") end
                end
            elseif other:Disposition(npc) == D_HT and IsValid(attacker) and attacker == other then
            MO.Add(data, cfg.KillConfirm, "kill")
            CAI.Voice.Speak(data, "victory")
        end
    end
end
end))

CAI.SafeHook("EntityTakeDamage", "CAI_MoraleExplosions", CAI.Prof.Wrap("morale_explosion", function(target, dmg)
    if not CAI.Enabled() then return end
    if not dmg:IsExplosionDamage() then return end
    local pos = dmg:GetDamagePosition()
    local cfg = CAI.Config.Morale

    MO._lastBoom = MO._lastBoom or {}
    local key = math.floor(pos.x / 100) .. ":" .. math.floor(pos.y / 100)
    if MO._lastBoom[key] and CurTime() - MO._lastBoom[key] < 0.5 then return end
    MO._lastBoom[key] = CurTime()

    for npc, data in pairs(CAI.Manager.All()) do
        if IsValid(npc) and npc:GetPos():DistToSqr(pos) < cfg.ExplosionRadius * cfg.ExplosionRadius then
            MO.Add(data, cfg.Explosion, "explosion")
            CAI.Suppression.Add(data, CAI.Config.Suppression.Explosion)
            CAI.Memory.AddDanger(data, pos, 300, "explosion")
        end
    end
end))

CAI.SafeHook("EntityTakeDamage", "CAI_DamageReact", CAI.Prof.Wrap("morale_damage", function(victim, dmg)
    if not CAI.Enabled() then return end
    local data = CAI.Manager.Get(victim)
    if not data then return end

    data.lastHurtAt = CurTime()
    data.lastAttacker = dmg:GetAttacker()

    local atk = dmg:GetAttacker()
    local melee = dmg:IsDamageType(DMG_CLUB) or dmg:IsDamageType(DMG_SLASH)
    if not melee and IsValid(atk) and atk.GetPos
       and victim:GetPos():DistToSqr(atk:GetPos()) < 120 * 120 then
        melee = true
    end
    if melee then
        data.lastMeleeHurtAt = CurTime()
        data.meleeHits = data.meleeHits or {}
        data.meleeHits[#data.meleeHits + 1] = CurTime()
    end

    CAI.Suppression.Add(data, 18)
    if CurTime() - (data.lastMoraleHit or 0) > 0.7 then
        data.lastMoraleHit = CurTime()
        MO.Add(data, -4, "took_damage")
    end
    if math.random() < 0.4 then CAI.Voice.Speak(data, "hurt") end

    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and victim:Disposition(attacker) == D_HT
       and CAI.Util.IsTargetable(attacker) then
        CAI.Memory.HearEnemy(data, attacker, attacker:GetPos())
        if data.squad then
            CAI.Battlefield.ReportEnemy(data.squad, attacker, attacker:GetPos(), victim)
            CAI.Squad.Broadcast(data.squad, "taking_fire", victim)
        end
    end
end))

CAI.Prof.WrapFn(MO, "Regen", "morale_regen")
