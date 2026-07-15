CAI.Config = CAI.Config or {}
local C = CAI.Config

CAI.STATE = {
    IDLE = 0,
    PATROL = 1,
    ENGAGE = 2,
    COVER = 3,
    FLANK = 4,
    SUPPRESS = 5,
    SEARCH = 6,
    RETREAT = 7,
    INVESTIGATE = 8,
    REGROUP = 9,
    ROOM_CLEAR = 10,
    BOUNDED = 11,
}

CAI.STATE_NAMES = {}
for k, v in pairs(CAI.STATE) do CAI.STATE_NAMES[v] = k end

CAI.ROLE = {
    LEADER = 1,
    SUPPRESSOR = 2,
    FLANKER = 3,
    SUPPORT = 4,
    BREACHER = 5,
    REAR = 6,
    GRENADIER = 7,
}
CAI.ROLE_NAMES = {}
for k, v in pairs(CAI.ROLE) do CAI.ROLE_NAMES[v] = k end

C.NPCClasses = {
    ["npc_combine_s"] = { faction = "combine" },
    ["npc_metropolice"] = { faction = "combine" },
    ["npc_citizen"] = { faction = "resistance" },
    ["npc_alyx"] = { faction = "resistance", noVoice = true, traits = { "Brave", "Accurate" } },
    ["npc_barney"] = { faction = "resistance", noVoice = true, traits = { "Brave", "Accurate" } },
    ["npc_monk"] = { faction = "resistance", noVoice = true, traits = { "Brave", "Accurate" } },
    ["npc_eli"] = { faction = "resistance" },
    ["npc_kleiner"] = { faction = "resistance" },
    ["npc_magnusson"] = { faction = "resistance" },
    ["npc_mossman"] = { faction = "resistance" },
    ["npc_fisherman"] = { faction = "resistance" },
    ["npc_odessa"] = { faction = "resistance" },
    ["npc_breen"] = { faction = "resistance" },
    ["npc_gman"] = { faction = "resistance" },
    ["npc_hunter"] = { faction = "combine", noCover = true, lightTouch = true },
}

function CAI.RegisterNPCClass(class, tbl)
    C.NPCClasses[class] = tbl or { faction = "custom" }
end

C.LOD = {

    { dist = 1500, interval = 0.15 },
    { dist = 3500, interval = 0.40 },
    { dist = 6000, interval = 1.00 },
    { dist = math.huge, interval = 3.0 },
}
C.MaxBrainThinksPerTick = 12
C.ManagerTickRate = 0.05

C.Engage = {
    -- Distance (u) under which a NPC with no line of sight backs off to regain
    -- a sightline. With line of sight it simply holds and fires instead.
    PointBlank = 120,
    -- Minimum seconds between re-issuing the fire schedule (no schedule thrash).
    RetryGap = 0.4,
}

C.Flank = {
    -- cai_aggression at or above this lets any squad member peel off to flank a
    -- hidden enemy. Below it, only a designated FLANKER flanks.
    AggressiveAt = 0.7,
    -- Distance (u) to the enemy (or any other enemy) at which a flank opens
    -- fire and runs-and-guns instead of finishing the silent maneuver.
    FireDist = 500,
}

C.Perceive = {
    -- Distance (u) for the hard point-blank target-acquisition fallback: a
    -- hostile player this close with line of sight is always noticed.
    PointBlankAcquire = 250,
    -- Throttle (s) for that scan so it is not run every think.
    PointBlankScan = 0.5,
}

C.Cover = {
    SearchRadius = 1200,
    MinEnemyDist = 250,
    IdealEnemyDist = 900,
    AllyCrowdDist = 110,
    CacheLifetime = 8,
    CompromiseTime = 1.6,
    Weights = {
        distSelf = 1.0,
        distEnemy = 1.2,
        losBlocked = 3.0,
        crowding = 1.5,
        danger = 2.5,
        flankRisk = 1.2,
        history = 1.0,
        escapeRoute = 1.5,
        highGround = 0.8,
        nearChokepoint = 0.6,
    },
}

C.Memory = {
    EnemyTTL = 45,
    SoundTTL = 20,
    DangerTTL = 30,
    FadeTick = 2,
}

C.Morale = {
    Start = 75,
    Min = 0,
    Max = 100,
    AllyDeathNear = -18, AllyDeathRadius = 700,
    LowHealth = -15,
    OutOfAmmoClip = -6,
    KillConfirm = 12,
    Outnumbered = -10,
    Reinforced = 8,
    Explosion = -12, ExplosionRadius = 500,
    RegenPerTick = 1.5,
    BreakThreshold = 25,
    ShakenThreshold = 45,
}

C.Suppression = {
    Radius = 140,
    PerBullet = 14,
    Explosion = 45,
    Decay = 9,
    Max = 100,
    PinnedAt = 55,
    PanicAt = 85,
    FFMaxAllies = 4,
    HurtGraceMin = 1.0,
    HurtGraceMax = 3.0,
    HurtEvadeDist = 300,
    HurtCoverCdMin = 1.5,
    HurtCoverCdMax = 8.0,
    HurtExposeCd = 0.6,
    AccuracyPenaltySteps = { [30] = 1, [60] = 2, [85] = 3 },
}

C.WeaponPatterns = {
    { pattern = "shotgun", archetype = "shotgun" },
    { pattern = "sniper", archetype = "sniper" }, { pattern = "awp", archetype = "sniper" },
    { pattern = "crossbow", archetype = "sniper" },
    { pattern = "m249", archetype = "lmg" }, { pattern = "lmg", archetype = "lmg" },
    { pattern = "mg42", archetype = "lmg" }, { pattern = "minigun", archetype = "lmg" },
    { pattern = "rpg", archetype = "rocket" }, { pattern = "rocket", archetype = "rocket" },
    { pattern = "launcher", archetype = "rocket" }, { pattern = "grenade", archetype = "rocket" },
    { pattern = "smg", archetype = "smg" }, { pattern = "mp5", archetype = "smg" },
    { pattern = "mac10", archetype = "smg" }, { pattern = "uzi", archetype = "smg" },
    { pattern = "pistol", archetype = "pistol" }, { pattern = "357", archetype = "pistol" },
    { pattern = "deagle", archetype = "pistol" }, { pattern = "revolver", archetype = "pistol" },
}

C.WeaponResponses = {
    shotgun = { idealDist = 1100, aggression = -0.3, keepDistance = true },
    sniper = { idealDist = 500, aggression = -0.2, stayHidden = true },
    lmg = { idealDist = 900, aggression = -0.25, avoidExposure = true },
    rocket = { idealDist = 1200, aggression = -0.4, scatter = true },
    melee = { idealDist = 430, aggression = 0.15, keepDistance = true },
    smg = { idealDist = 350, aggression = 0.35 },
    pistol = { idealDist = 400, aggression = 0.45 },
    rifle = { idealDist = 700, aggression = 0.0 },
}

C.SoundPatterns = {
    { pattern = "footstep", type = "footstep", radius = 450 },
    { pattern = "doors/", type = "door", radius = 900 },
    { pattern = "glass", type = "glass", radius = 1100 },
    { pattern = "reload", type = "reload", radius = 600 },
    { pattern = "clipin", type = "reload", radius = 600 },
    { pattern = "explode", type = "explosion", radius = 2500 },
    { pattern = "explosion", type = "explosion", radius = 2500 },
    { pattern = "physics", type = "physics", radius = 550 },
    { pattern = "weapons/", type = "gunshot", radius = 2000 },
    { pattern = "npc/", type = "battle", radius = 1800 },
}
C.SuppressedGunshotMult = 0.35

C.Search = {
    MaxPoints = 6,
    PointRadius = 900,
    DwellTime = 2.2,
    GiveUpAfter = 55,
    VerticalBonus = 1.4,
}

C.Formations = {
    LINE = { {0,-90}, {0,90}, {0,-180}, {0,180}, {0,-270}, {0,270} },
    WEDGE = { {-80,-80}, {-80,80}, {-160,-160}, {-160,160}, {-240,0} },
    DIAMOND = { {-100,-100}, {-100,100}, {-200,0}, {100,0}, {-300,0} },
    FILE = { {-90,0}, {-180,0}, {-270,0}, {-360,0}, {-450,0} },
    STACK = { {-45,35}, {-90,-35}, {-135,35}, {-180,-35}, {-225,35} },
    CIRCLE = { {120,0}, {-120,0}, {0,120}, {0,-120}, {85,85} },
}

C.Voice = {
    BasePath = "combat_intelligence_ai/",

    Events = {
        enemy_spotted = "enemy_spotted",
        taking_fire = "taking_fire",
        reload = "reload",
        grenade = "grenade",
        retreat = "retreat",
        cover_me = "cover_me",
        flanking = "flanking",
        breach = "breach",
        clear = "clear",
        idle = "idle",
        panic = "panic",
        victory = "victory",
        death = "death",
        hurt = "hurt",
        suppressing = "suppressing",
        moving = "moving",
        searching = "searching",
        enemy_lost = "enemy_lost",
        need_backup = "need_backup",
        need_help = "need_help",
    },
    SquadCooldown = 1.2,

    Defaults = {
    combine = {
        enemy_spotted = {
            "npc/combine_soldier/vo/contact.wav",
            "npc/combine_soldier/vo/contactconfim.wav",
            "npc/combine_soldier/vo/contactconfirmprosecuting.wav",
            "npc/combine_soldier/vo/callcontacttarget1.wav",
            "npc/combine_soldier/vo/targetone.wav",
            "npc/combine_soldier/vo/viscon.wav",
            "npc/combine_soldier/vo/goactiveintercept.wav",
        },
        taking_fire = {
            "npc/combine_soldier/vo/cover.wav",
            "npc/combine_soldier/vo/coverhurt.wav",
            "npc/combine_soldier/vo/heavyresistance.wav",
            "npc/combine_soldier/vo/hardenthatposition.wav",
        },
        reload = {
            "npc/combine_soldier/vo/coverme.wav",
            "npc/combine_soldier/vo/displace.wav",
        },
        grenade = {
            "npc/combine_soldier/vo/bouncerbouncer.wav",
            "npc/combine_soldier/vo/ripcordripcord.wav",
        },
        retreat = {
            "npc/combine_soldier/vo/displace.wav",
            "npc/combine_soldier/vo/displace2.wav",
            "npc/combine_soldier/vo/prison_soldier_fallback_b4.wav",
        },
        cover_me = {
            "npc/combine_soldier/vo/coverme.wav",
        },
        flanking = {
            "npc/combine_soldier/vo/closing.wav",
            "npc/combine_soldier/vo/closing2.wav",
            "npc/combine_soldier/vo/unitismovingin.wav",
            "npc/combine_soldier/vo/fixsightlinesmovein.wav",
            "npc/combine_soldier/vo/sweepingin.wav",
        },
        breach = {
            "npc/combine_soldier/vo/gosharp.wav",
            "npc/combine_soldier/vo/gosharpgosharp.wav",
            "npc/combine_soldier/vo/movein.wav",
        },
        clear = {
            "npc/combine_soldier/vo/reportingclear.wav",
            "npc/combine_soldier/vo/reportallpositionsclear.wav",
            "npc/combine_soldier/vo/sightlineisclear.wav",
            "npc/combine_soldier/vo/sectorissecurenovison.wav",
            "npc/combine_soldier/vo/cleaned.wav",
        },
        idle = {
            "npc/combine_soldier/vo/stayalert.wav",
            "npc/combine_soldier/vo/stayalertreportsightlines.wav",
            "npc/combine_soldier/vo/reportallradialsfree.wav",
            "npc/combine_soldier/vo/teamdeployedandscanning.wav",
        },
        panic = {
            "npc/combine_soldier/vo/overwatchsectoroverrun.wav",
            "npc/combine_soldier/vo/overwatchteamisdown.wav",
            "npc/combine_soldier/vo/isfinalteamunitbackup.wav",
            "npc/combine_soldier/vo/heavyresistance.wav",
        },
        victory = {
            "npc/combine_soldier/vo/onedown.wav",
            "npc/combine_soldier/vo/flatline.wav",
            "npc/combine_soldier/vo/affirmativewegothimnow.wav",
            "npc/combine_soldier/vo/overwatchtarget1sterilized.wav",
            "npc/combine_soldier/vo/thatsitwrapitup.wav",
        },
        death = {
            "npc/combine_soldier/die1.wav",
            "npc/combine_soldier/die2.wav",
            "npc/combine_soldier/die3.wav",
        },
        hurt = {
            "npc/combine_soldier/pain1.wav",
            "npc/combine_soldier/pain2.wav",
            "npc/combine_soldier/pain3.wav",
            "npc/combine_soldier/vo/requestmedical.wav",
            "npc/combine_soldier/vo/requeststimdose.wav",
        },
        suppressing = {
            "npc/combine_soldier/vo/suppressing.wav",
            "npc/combine_soldier/vo/hardenthatposition.wav",
        },
        moving = {
            "npc/combine_soldier/vo/movein.wav",
            "npc/combine_soldier/vo/unitismovingin.wav",
            "npc/combine_soldier/vo/unitisclosing.wav",
            "npc/combine_soldier/vo/inbound.wav",
        },
        searching = {
            "npc/combine_soldier/vo/motioncheckallradials.wav",
            "npc/combine_soldier/vo/sweepingin.wav",
            "npc/combine_soldier/vo/teamdeployedandscanning.wav",
            "npc/combine_soldier/vo/noviscon.wav",
        },
        enemy_lost = {
            "npc/combine_soldier/vo/lostcontact.wav",
            "npc/combine_soldier/vo/noviscon.wav",
            "npc/combine_soldier/vo/hasnegativemovement.wav",
            "npc/combine_soldier/vo/targetblackout.wav",
        },
        need_backup = {
            "npc/combine_soldier/vo/overwatchrequestreinforcement.wav",
            "npc/combine_soldier/vo/overwatchrequestreserveactivation.wav",
            "npc/combine_soldier/vo/isfinalteamunitbackup.wav",
        },
    },

    resistance = {
        enemy_spotted = {
            "vo/npc/male01/combine01.wav",
            "vo/npc/male01/combine02.wav",
            "vo/npc/male01/heretheycome01.wav",
            "vo/npc/male01/overthere01.wav",
            "vo/npc/male01/overthere02.wav",
            "vo/npc/male01/behindyou01.wav",
            "vo/npc/male01/upthere01.wav",
            "vo/npc/male01/headsup01.wav",
        },
        taking_fire = {
            "vo/npc/male01/takecover02.wav",
            "vo/npc/male01/getdown02.wav",
            "vo/npc/male01/incoming02.wav",
            "vo/npc/male01/watchout.wav",
        },
        reload = {
            "vo/npc/male01/gottareload01.wav",
            "vo/npc/male01/coverwhilereload01.wav",
            "vo/npc/male01/coverwhilereload02.wav",
        },
        grenade = {
            "vo/npc/male01/incoming02.wav",
            "vo/npc/male01/getdown02.wav",
            "vo/npc/male01/headsup02.wav",
        },
        retreat = {
            "vo/npc/male01/runforyourlife01.wav",
            "vo/npc/male01/runforyourlife02.wav",
            "vo/npc/male01/runforyourlife03.wav",
            "vo/npc/male01/gethellout.wav",
            "vo/npc/male01/strider_run.wav",
        },
        cover_me = {
            "vo/npc/male01/coverwhilereload01.wav",
            "vo/npc/male01/coverwhilereload02.wav",
        },
        flanking = {
            "vo/npc/male01/squad_away01.wav",
            "vo/npc/male01/squad_away02.wav",
            "vo/npc/male01/squad_away03.wav",
            "vo/npc/male01/letsgo01.wav",
        },
        breach = {
            "vo/npc/male01/letsgo01.wav",
            "vo/npc/male01/letsgo02.wav",
            "vo/npc/male01/squad_follow03.wav",
            "vo/npc/male01/okimready01.wav",
        },
        clear = {
            "vo/npc/male01/yeah02.wav",
            "vo/npc/male01/nice.wav",
            "vo/npc/male01/fantastic01.wav",
            "vo/npc/male01/finally.wav",
        },
        idle = {
            "vo/npc/male01/question01.wav",
            "vo/npc/male01/question03.wav",
            "vo/npc/male01/question05.wav",
            "vo/npc/male01/question07.wav",
            "vo/npc/male01/question11.wav",
            "vo/npc/male01/question12.wav",
            "vo/npc/male01/question20.wav",
            "vo/npc/male01/question21.wav",
            "vo/npc/male01/question23.wav",
            "vo/npc/male01/question26.wav",
            "vo/npc/male01/question28.wav",
            "vo/npc/male01/waitingsomebody.wav",
            "vo/npc/male01/doingsomething.wav",
        },
        panic = {
            "vo/npc/male01/ohno.wav",
            "vo/npc/male01/goodgod.wav",
            "vo/npc/male01/uhoh.wav",
            "vo/npc/male01/no01.wav",
            "vo/npc/male01/help01.wav",
        },
        victory = {
            "vo/npc/male01/gotone01.wav",
            "vo/npc/male01/gotone02.wav",
            "vo/npc/male01/nice.wav",
            "vo/npc/male01/yeah02.wav",
            "vo/npc/male01/likethat.wav",
        },
        death = {
            "vo/npc/male01/pain07.wav",
            "vo/npc/male01/pain08.wav",
            "vo/npc/male01/pain09.wav",
        },
        hurt = {
            "vo/npc/male01/imhurt01.wav",
            "vo/npc/male01/imhurt02.wav",
            "vo/npc/male01/ow01.wav",
            "vo/npc/male01/ow02.wav",
            "vo/npc/male01/pain01.wav",
            "vo/npc/male01/pain03.wav",
            "vo/npc/male01/pain05.wav",
            "vo/npc/male01/myarm01.wav",
            "vo/npc/male01/myleg01.wav",
            "vo/npc/male01/hitingut01.wav",
        },
        suppressing = {
            "vo/npc/male01/evenodds.wav",
            "vo/npc/male01/likethat.wav",
        },
        moving = {
            "vo/npc/male01/letsgo01.wav",
            "vo/npc/male01/letsgo02.wav",
            "vo/npc/male01/squad_approach02.wav",
            "vo/npc/male01/squad_approach03.wav",
            "vo/npc/male01/squad_approach04.wav",
        },
        searching = {
            "vo/npc/male01/overhere01.wav",
            "vo/npc/male01/upthere01.wav",
            "vo/npc/male01/upthere02.wav",
            "vo/npc/male01/uhoh.wav",
        },
        enemy_lost = {
            "vo/npc/male01/uhoh.wav",
            "vo/npc/male01/whoops01.wav",
        },
        need_backup = {
            "vo/npc/male01/help01.wav",
            "vo/npc/male01/overhere01.wav",
        },
    },
    },

    Chatter = {
        idle = { npcGap = 20, squadGap = 8 },
        cover_me = { npcGap = 14, squadGap = 6 },
        moving = { npcGap = 12, squadGap = 5 },
        searching = { npcGap = 10, squadGap = 5 },
        suppressing = { npcGap = 10, squadGap = 5 },
    },

    RadioOffClicks = {
        "npc/combine_soldier/vo/off1.wav",
        "npc/combine_soldier/vo/off2.wav",
        "npc/combine_soldier/vo/off3.wav",
    },
}

C.Plan = {
    Interval = 3.5,
    FlankMinMembers = 3,
    RetreatMoraleAvg = 30,
    PushAdvantage = 1.6,
}

C.LastVisGrace = 1.0

C.SpatialMap = {
    ScanInterval = 5.0,
    ScanBudget = 40,
    ChokepointWidth = 80,
    HighGroundThreshold = 48,
    RoomMinAreas = 3,
    DoorwayMaxConnections = 2,
    ChokepointTTL = 60,
    RouteTTL = 45,
    MaxChokepoints = 20,
    MaxHighGround = 15,
    MaxFlankRoutes = 10,
    MaxRooms = 12,
    MaxDoorways = 16,
}

C.SquadTactics = {
    BoundInterval = 10,
    BoundMoveDistance = 400,
    BoundFireDuration = 2.5,
    ClearSliceAngle = 15,
    ClearSliceMax = 90,
    ClearEntryDwell = 1.5,
    StaggerOffset = 0.4,
    StaggerFireWindow = 0.3,
    MoveShootFraction = 0.5,
    BattleAwarenessRadius = 1200,
    BattleAwarenessDuration = 8,
}

C.Push = {
    CreepMult     = 1.2,
    StopMult      = 0.45,
    BoundStep     = 350,
    BoundInterval = 1.8,
    BurstDuration = 1.2,
    CreepStep     = 100,
    CreepInterval = 4,
}

C.Nav = {
    StuckHardTimeout = 8,
}

C.Escape = {
    PointBlank     = 150,
    SurroundRadius = 320,
    SurroundCount  = 2,
    ClearDist      = 450,
    Step           = 400,
    ShoveRange     = 80,
    MeleeHitGrace  = 1.5,
    MeleeWindow    = 4,
    OverwhelmHits  = 3,
    WithdrawDist   = 350,
}

C.SelfPreserve = {
    DangerAvoid = {
        DeferCap         = 9,
        HoldTTL          = 30,
        AllyDeathRadius  = 250,
        AdvanceIntoRadius = 300,
    },
    HoldUnknown = {
        PatienceMult = 1.5,
    },
    CornerPush = {
        ConfidenceTime = 2.5,
    },
}
