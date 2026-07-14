CAI.Voice = CAI.Voice or {}
local V = CAI.Voice

V.Library = V.Library or {}

function V.BuildLibrary()
    V.Library = {}
    local base = "sound/" .. CAI.Config.Voice.BasePath
    local _, dirs = file.Find(base .. "*", "GAME")
    for _, dir in ipairs(dirs or {}) do
        local files = file.Find(base .. dir .. "/*", "GAME") or {}
        local list = {}
        for _, f in ipairs(files) do
            local ext = string.lower(string.GetExtensionFromFilename(f) or "")
            if ext == "wav" or ext == "mp3" or ext == "ogg" then
                list[#list + 1] = CAI.Config.Voice.BasePath .. dir .. "/" .. f
            end
        end
        if #list > 0 then
            V.Library[dir] = list
        end
    end
    local cats = table.Count(V.Library)
    print(CAI.PrintPrefix .. "Loaded voice lines for " .. cats .. " categories.")
end

local function AddResources()
    local base = "sound/" .. CAI.Config.Voice.BasePath
    for cat, list in pairs(V.Library) do
        for _, path in ipairs(list) do
            resource.AddSingleFile("sound/" .. path)
        end
    end
end

V.Defaults = V.Defaults or {}

local function ValidateList(list)
    local out = {}
    for _, path in ipairs(list or {}) do
        if file.Exists("sound/" .. path, "GAME") then out[#out + 1] = path end
    end
    return out
end

function V.BuildDefaults()
    local cfg = CAI.Config.Voice.Defaults
    V.Defaults = {}

    V.Defaults.combine = {}
    for cat, list in pairs(cfg.combine or {}) do
        V.Defaults.combine[cat] = ValidateList(list)
    end

    V.Defaults.resistance_male, V.Defaults.resistance_female = {}, {}
    for cat, list in pairs(cfg.resistance or {}) do
        V.Defaults.resistance_male[cat] = ValidateList(list)
        local fem = {}
        for _, path in ipairs(list) do
            fem[#fem + 1] = path:gsub("/male01/", "/female01/")
        end
        V.Defaults.resistance_female[cat] = ValidateList(fem)
    end
end

hook.Add("InitPostEntity", "CAI_VoiceLibrary", function()
    V.BuildDefaults()
    V.BuildLibrary()
    AddResources()
end)

concommand.Add("cai_voice_reload", function(ply)
    V.BuildDefaults()
    if IsValid(ply) and not ply:IsAdmin() then return end
    V.BuildLibrary()
end, nil, "Rescan voice line folders.")

function V.Speak(data, event, force)
    if not CAI.CVBool("cai_voice") then return false end
    local npc = data.ent
    if not IsValid(npc) then return false end

    local ci = CAI.Config.NPCClasses[npc:GetClass()]
    if ci and (ci.noVoice or ci.lightTouch) then return false end

    local category = CAI.Config.Voice.Events[event] or event

    local isDefault = false
    local list = V.Library[data.faction .. "_" .. category]
    if not list or #list == 0 then list = V.Library[category] end

    if data.role == CAI.ROLE.LEADER then
        local ll = V.Library["leader_" .. category]
        if ll and #ll > 0 then list = ll end
    end

    if category == "idle" then
        local traits = data.personality and data.personality.traits or {}
        local flavor
        if table.HasValue(traits, "Aggressive") or table.HasValue(traits, "Reckless") then
            flavor = "idle_alert"
        elseif table.HasValue(traits, "Patient") or table.HasValue(traits, "Defensive") then
            flavor = "idle_bored"
        else
            flavor = math.random() < 0.5 and "idle_joking" or "idle_bored"
        end
        local fl = V.Library[flavor]
        if fl and #fl > 0 then list = fl end
    end
    if not list or #list == 0 then
        local defs
        if data.faction == "resistance" then
            defs = data.voiceGender == "female" and V.Defaults.resistance_female
                                                 or V.Defaults.resistance_male

            if defs and (not defs[category] or #defs[category] == 0) then
                defs = V.Defaults.resistance_male
            end
        else
            defs = V.Defaults[data.faction]
        end
        if not defs then return false end
        list = defs[category]
        isDefault = true
    end
    if not list or #list == 0 then return false end

    local now = CurTime()

    local chatter = CAI.Config.Voice.Chatter[category]
    if chatter and not force then
        if now - (data.lastChatterAt or 0) < chatter.npcGap then return false end
        if data.squad and now - (data.squad.lastChatterAt or 0) < chatter.squadGap then
            return false
        end
    end

    local cooldown = CAI.CVNum("cai_voice_cooldown")
    if not force then
        if now - (data.lastVoiceAt or 0) < cooldown then
            if not CAI.CVBool("cai_voice_interrupt") then return false end
        end
        if math.Rand(0, 1) > CAI.CVNum("cai_voice_chance") then return false end
    end

    if data.squad then
        if now - (data.squad.lastVoiceAt or 0) < CAI.Config.Voice.SquadCooldown and not force then
            return false
        end
        data.squad.lastVoiceAt = now
    end

    local maxDist = CAI.CVNum("cai_voice_maxdist")
    local _, distSqr = CAI.Util.NearestPlayer(npc:GetPos())
    if distSqr > maxDist * maxDist then return false end

    if CAI.CVBool("cai_voice_interrupt") and data.lastVoiceSound then
        npc:StopSound(data.lastVoiceSound)
    end

    local sound = list[math.random(#list)]
    local vol = math.Clamp(CAI.CVNum("cai_voice_volume"), 0, 1)

    local pitch
    if isDefault and data.faction == "combine" then pitch = 100
    elseif isDefault then pitch = math.random(94, 106)
    else pitch = math.random(96, 104) end
    npc:EmitSound(sound, 75, pitch, vol, CHAN_VOICE)

    if isDefault and data.faction == "combine" and string.find(sound, "/vo/", 1, true) then
        local dur = SoundDuration(sound)
        if dur and dur > 0 and dur < 10 then
            timer.Simple(dur, function()
                if not IsValid(npc) then return end
                local clicks = CAI.Config.Voice.RadioOffClicks
                npc:EmitSound(clicks[math.random(#clicks)], 75, 100, vol, CHAN_VOICE)
            end)
        end
    end

    data.lastVoiceAt = now
    data.lastVoiceSound = sound
    if chatter then
        data.lastChatterAt = now
        if data.squad then data.squad.lastChatterAt = now end
    end
    return true
end

CAI.Prof.WrapFn(V, "Speak", "voice_speak")
