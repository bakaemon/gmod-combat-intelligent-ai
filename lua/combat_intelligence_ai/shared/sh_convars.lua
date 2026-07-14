local SV = { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }

local function SVar(name, default, help)
    CreateConVar(name, default, SV, help)
end

SVar("cai_enabled", "1", "Master switch for Combat Intelligence AI.")
SVar("cai_cover", "1", "Enable the smart cover system.")
SVar("cai_morale", "1", "Enable the morale system.")
SVar("cai_suppression", "1", "Enable the suppression system.")
SVar("cai_memory", "1", "Enable the memory system.")
SVar("cai_flanking", "1", "Enable flanking maneuvers.")
SVar("cai_move_shoot", "1", "Enable NPCs to fire while moving (run-and-gun).")
SVar("cai_search", "1", "Enable last-known-position searching.")
SVar("cai_comms", "1", "Enable squad communication & shared knowledge.")
SVar("cai_voice", "1", "Enable the modular voice line system.")
SVar("cai_formations", "1", "Enable squad formations.")
SVar("cai_friendlyfire_avoid", "1", "Enable friendly-fire avoidance / spacing.")
SVar("cai_weaponintel", "1", "Enable player weapon recognition.")
SVar("cai_soundintel", "1", "Enable NPC sound reactions.")
SVar("cai_flashlight", "1", "Player flashlights visually reveal them to NPCs with line of sight.")
SVar("cai_meleepanic", "1", "Cornered, broken NPCs with empty weapons take a desperate melee swing.")
SVar("cai_vj_enabled", "0", "EXPERIMENTAL: allow CAI to manage opted-in VJ Base SNPCs.")
SVar("cai_aggression", "0.5", "0 = cautious and tactical, 1 = everyone engages at once.")
SVar("cai_darkness", "1", "NPCs struggle to spot players standing in darkness.")
SVar("cai_simfire", "1", "Remove the engine's 2-shooters-per-squad fire limit so everyone can engage.")
SVar("cai_accuracy", "0.5", "Global NPC accuracy, 0 stormtrooper to 1 deadeye.")
SVar("cai_npc_regen", "0", "NPCs slowly regenerate health when out of combat.")
SVar("cai_wallbang", "0", "Suppressing NPCs fire at last known position even through walls, for servers with bullet penetration mods.")
SVar("cai_npc_flashlights", "1", "NPCs switch on flashlights in darkness. Their beam gives their position away too.")
SVar("cai_patrol", "1", "NPCs wander on patrol. Set 0 to keep them stationary at their posts until something happens.")
SVar("cai_danger_avoid", "1", "NPCs avoid repositioning into known kill zones (where allies died or were suppressed) and hold safe cover until it clears.")
SVar("cai_hold_unknown", "1", "NPCs hold angles and fire from cover instead of curiously advancing into the unknown when they have no eyes-on target.")
SVar("cai_cornerpush", "1", "Squads run a realistic corner-push: suppress, survive the corner, push through, follower overwatches, rest released from caution.")

SVar("cai_difficulty", "1", "Global difficulty scale 0.5 (easy) - 2 (brutal). Scales reaction speed & accuracy.")
SVar("cai_performance_mode", "0", "1 = aggressive LOD & reduced scan rates for huge battles.")
SVar("cai_max_managed", "150", "Maximum NPCs managed simultaneously.")

SVar("cai_voice_volume", "1", "Voice line volume 0-1.")
SVar("cai_voice_chance", "0.75","Chance (0-1) an eligible event actually speaks.")
SVar("cai_voice_cooldown", "4", "Per-NPC seconds between voice lines.")
SVar("cai_voice_interrupt","0", "1 = new lines may cut off a currently playing line.")
SVar("cai_voice_maxdist", "2000","Max distance (units) voice lines are audible.")

SVar("cai_debug", "0", "Enable the full debug overlay (admins).")
SVar("cai_debug_rays", "1", "Draw vision/decision rays in debug mode.")

if CLIENT then
end

function CAI.CVBool(name) local c = GetConVar(name) return c and c:GetBool() or false end
function CAI.CVNum(name) local c = GetConVar(name) return c and c:GetFloat() or 0 end
function CAI.Enabled() return CAI.CVBool("cai_enabled") end
function CAI.Difficulty() return math.Clamp(CAI.CVNum("cai_difficulty"), 0.25, 3) end
