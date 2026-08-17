local RELOAD_TIMEOUT_MIN = 1.5
local RELOAD_TIMEOUT_MAX = 8
local RELOAD_TIMEOUT_PAD = 0.5
local RELOAD_FAIL_LIMIT = 3
local RELOAD_BACKOFF = 8

local RELOAD_ACTS = {}
for _, act in ipairs({ ACT_RELOAD, ACT_RELOAD_LOW, ACT_RELOAD_PISTOL, ACT_RELOAD_PISTOL_LOW,
    ACT_RELOAD_SMG1, ACT_RELOAD_SMG1_LOW, ACT_RELOAD_SHOTGUN, ACT_RELOAD_SHOTGUN_LOW }) do
    RELOAD_ACTS[act] = true
end

local FIRE_SCHEDS = {}
for _, sched in ipairs({ SCHED_ESTABLISH_LINE_OF_FIRE, SCHED_RANGE_ATTACK1 }) do
    FIRE_SCHEDS[sched] = true
end

function CAI.IsFireSchedule(sched)
    return FIRE_SCHEDS[sched] == true
end

function CAI.ReloadTime(npc)
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then return RELOAD_TIMEOUT_MIN end

    local cached = wep.caiReloadTime
    if cached then return cached end

    local dur = 0
    if npc.SelectWeightedSequence and npc.SequenceDuration then
        local seq = npc:SelectWeightedSequence(ACT_RELOAD)
        if seq and seq >= 0 then dur = npc:SequenceDuration(seq) or 0 end
    end

    dur = math.Clamp(dur + RELOAD_TIMEOUT_PAD, RELOAD_TIMEOUT_MIN, RELOAD_TIMEOUT_MAX)
    wep.caiReloadTime = dur
    return dur
end

function CAI.ReloadClip(npc)
    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) or not wep.Clip1 then return nil, nil end
    local maxClip = wep.GetMaxClip1 and wep:GetMaxClip1() or -1
    return wep:Clip1(), maxClip
end

function CAI.IsDry(data)
    local npc = data.ent
    if not IsValid(npc) then return false end
    if data._dryAt == CurTime() then return data._dry end

    local dry = false
    if not CAI.WeaponIntel.IsMelee(npc) then
        local clip, maxClip = CAI.ReloadClip(npc)
        dry = clip ~= nil and maxClip ~= nil and maxClip > 0 and clip <= 0
    end

    data._dryAt = CurTime()
    data._dry = dry
    return dry
end

function CAI.Reloading(data)
    local npc = data.ent
    if not IsValid(npc) then return false end

    if data._reloadIssuedAt then
        local clip = CAI.ReloadClip(npc)
        if clip and clip > (data._reloadClip or 0) then
            data._reloadIssuedAt = nil
            data._reloadFails = 0
        elseif CurTime() - data._reloadIssuedAt < CAI.ReloadTime(npc) then
            return true
        end
    end

    if npc.IsCurrentSchedule then
        if npc:IsCurrentSchedule(SCHED_RELOAD) then return true end
        if SCHED_HIDE_AND_RELOAD and npc:IsCurrentSchedule(SCHED_HIDE_AND_RELOAD) then return true end
    end

    local act = npc.GetActivity and npc:GetActivity()
    if act and RELOAD_ACTS[act] then return true end

    return false
end

function CAI.TryReload(data, hide)
    local npc = data.ent
    if not IsValid(npc) then return false end

    local wep = npc.GetActiveWeapon and npc:GetActiveWeapon()
    if not IsValid(wep) then return false end

    if data._reloadWep ~= wep then
        data._reloadWep = wep
        data._reloadIssuedAt = nil
        data._reloadClip = nil
        data._reloadFails = 0
        data._reloadBlockUntil = nil
        data._reloadLastAt = nil
    end

    local clip, maxClip = CAI.ReloadClip(npc)
    if not clip or clip < 0 then return false end
    if not maxClip or maxClip <= 0 then return false end
    if clip >= maxClip then return false end

    if CurTime() < (data._reloadBlockUntil or 0) then return false end

    local gap = CAI.ReloadTime(npc)
    if data._reloadLastAt and CurTime() - data._reloadLastAt < gap then return false end
    if CAI.Reloading(data) then return false end

    if data._reloadIssuedAt and clip <= (data._reloadClip or 0) then
        data._reloadFails = (data._reloadFails or 0) + 1
        if data._reloadFails >= RELOAD_FAIL_LIMIT then
            data._reloadFails = 0
            data._reloadIssuedAt = nil
            data._reloadBlockUntil = CurTime() + RELOAD_BACKOFF
            return false
        end
    end

    data._reloadClip = clip
    data._reloadIssuedAt = CurTime()
    data._reloadLastAt = CurTime()
    data._reloadingAt = CurTime()

    if hide and SCHED_HIDE_AND_RELOAD then
        npc:SetSchedule(SCHED_HIDE_AND_RELOAD)
    else
        npc:SetSchedule(SCHED_RELOAD)
    end
    return true
end
