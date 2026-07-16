local BR = CAI.Brain
BR.COA = BR.COA or { PreTarget = {}, Target = {} }

table.insert(BR.COA.PreTarget, function(data, npc)
    if not CAI.WeaponIntel.IsMelee(npc) then return end
    local me, mrec = CAI.Memory.FreshestEnemy(data)
    if IsValid(me) and not CAI.Util.IsTargetable(me) then
        data.memory.enemies[me] = nil
        mrec = nil
    end
    if not mrec or CurTime() - mrec.t >= 5 then return end
    if CAI.Morale.IsBroken(data) then return CAI.STATE.RETREAT, "morale_broken" end

    local mcfg = CAI.Config.Melee
    local pounceSqr = mcfg.Ambush.PounceDist * mcfg.Ambush.PounceDist
.
    if IsValid(me) and npc:GetPos():DistToSqr(me:GetPos()) < pounceSqr then
        return CAI.STATE.ENGAGE, "melee_chase"
    end

    local arch = "unarmed"
    if IsValid(me) then
        local ew = me.GetActiveWeapon and me:GetActiveWeapon()
        if IsValid(ew) then
            arch = CAI.WeaponIntel.IsMeleeThreat(me) and "melee" or CAI.WeaponIntel.Classify(ew)
        end
    end

    local support = 0
    if data.squad then
        for _, m in ipairs(data.squad.members) do
            if IsValid(m) and m ~= npc and CAI.Util.Alive(m)
               and m:GetPos():DistToSqr(npc:GetPos()) < mcfg.SupportRadius * mcfg.SupportRadius then
                support = support + 1
            end
        end
    end

    local agg = CAI.WeaponIntel.EffectiveAggression(data)
    local courage = data.personality.stats.courage or 0
    local rush = (mcfg.RushBase[arch] or 0)
               + agg * 0.5 + courage * 0.25
               + support * mcfg.SupportBonus
    if arch == "pistol" and support >= mcfg.PistolPackSize then
        rush = rush + 0.4
    end

    if arch == "sniper" and rush < mcfg.RushThreshold + 0.3 then
        if data.flank or CurTime() - (data.lastFlankAt or 0) > 6 then
            return CAI.STATE.FLANK, "sneak_on_sniper"
        end
        return CAI.STATE.ENGAGE, "melee_ambush"
    end

    if arch == "shotgun" and agg < mcfg.ShotgunOverride then
        return CAI.STATE.ENGAGE, "melee_ambush"
    end

    if rush >= mcfg.RushThreshold then
        return CAI.STATE.ENGAGE, "melee_chase"
    end
    return CAI.STATE.ENGAGE, "melee_ambush"
end)