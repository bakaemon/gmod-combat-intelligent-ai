# AGENT.md: Combat Intelligence AI (CIA-gmod)

Guidance for AI agents navigating and modifying this Garry's Mod addon.

## What this project is

A Garry's Mod Lua addon ("Combat Intelligence AI") that replaces default NPC
behavior with a smart combat brain: cover scoring, memory of last-seen
positions, squads with roles, morale, suppression, flanking, sound/weapon
recognition, voice lines, spatial mapping, and room clearing.

## Single source of truth: the `CAI` global

Everything hangs off one global table, `CAI`, defined in
`lua/autorun/cai_init.lua`. Subsystems namespace themselves as `CAI.<Name>`
using the idiom:

```lua
CAI.X = CAI.X or {}
local X = CAI.X
```

Common namespaces you will touch: `CAI.Manager`, `CAI.Brain`, `CAI.Memory`,
`CAI.Squad`, `CAI.Cover`, `CAI.Suppression`, `CAI.Morale`, `CAI.Voice`,
`CAI.Nav`, `CAI.Util`, `CAI.Config`, `CAI.Net`, `CAI.Perf`, `CAI.Prof`.

## Directory layout

```
lua/autorun/cai_init.lua          Load order + CAI table/version. EDIT HERE to add/remove modules.
lua/combat_intelligence_ai/
  shared/                        Runs on both client & server.
    sh_config.lua                ALL tuning constants + CAI.STATE / CAI.ROLE enums (539 lines).
    sh_convars.lua               All cai_* console vars + CAI.CVBool/CVNum/Enabled/Difficulty.
    sh_util.lua                  CAI.Util math/trace helpers + CAI.SafeHook.
    sh_net.lua                   Netmessage name registry (CAI.Net).
    sh_text.lua                  Localized strings.
  server/                        AI logic (server-only).
    sv_manager.lua               NPC registration + the per-tick scheduler.
    sv_brain.lua                 Thin LOADER for the brain, includes brain_func/* in order.
    brain_func/                  The decision core, split into focused modules (all on CAI.Brain):
      state.lua                   BR.SetState, BR.StopSuppressing, BR.Prefire
      perceive.lua                BR.Perceive (senses / memory refresh)
      sense.lua                   BR.CombatTarget, BR.MeleeThreatScan
      decide.lua                  BR.Decide (priority cascade -> state + reason)
      exec.lua                    BR.Exec[0..11] (per-state movement / firing handlers)
      think.lua                   BR.Think (per-tick perceive -> decide -> execute loop)
    sv_*.lua                     One file per subsystem (memory, squad, cover, flank, ...).
  client/                        Debug overlay (cl_debug) + settings UI.
build/                           GENERATED. Do NOT hand-edit.
  src/                           Mirror of lua/ (written by sync_addon.sh).
  output/combat_intelligence_ai.gma   Workshop package (written by gma_tool).
addon.json                       Workshop metadata. `ignore` list governs what ships.
sync_addon.sh                    Build: luac check -> repack GMA -> rsync lua/ into build/src.
publish.sh                       Upload build/src to the Steam Workshop (item 3760260083).
```

## Core architecture

- **Per-NPC state record.** `CAI.Manager.NPCs[npc]` is the table holding all
  runtime state for one NPC (faction, personality, memory, morale, suppression,
  `state`, `nextThink`, squad ref, etc.). It is created in
  `sv_manager.lua` (`MG.Register`) and fetched everywhere via `MG.Get(npc)`.
  Treat this table as the NPC's "agent record", almost every subsystem reads
  and writes fields on it.
- **Scheduler.** `sv_manager.lua` creates timer `"CAI_Scheduler"` firing every
  `CAI.Config.ManagerTickRate` (0.05s). Each tick it iterates managed NPCs and,
  when `data.nextThink` is due, calls `CAI.Brain.Think(data, dt)` under a
  per-tick budget (`CAI.Config.MaxBrainThinksPerTick`). Brain errors are
  caught with `pcall` and printed via `ErrorNoHaltWithStack`.
- **Think cadence / LOD.** Actual interval per NPC comes from
  `CAI.Perf.GetThinkInterval(npc)` (distance-based LOD tiers in
  `CAI.Config.LOD`), divided by difficulty speed. Don't assume every NPC
  thinks every 0.05s.
- **State machine.** The brain decision core lives in `server/brain_func/`,
  loaded by `sv_brain.lua`. Each module populates `CAI.Brain` (aliased `BR`):
  `Decide` (`decide.lua`) is a priority cascade returning `(state, reason)`,
  `Exec[state]` (`exec.lua`) runs the matching per-state handler, and `Think`
  (`think.lua`) orchestrates the per-tick perceive -> decide -> execute loop.
  States come from the `CAI.STATE` enum (IDLE, PATROL, ENGAGE, COVER, FLANK,
  SUPPRESS, SEARCH, RETREAT, INVESTIGATE, REGROUP, ROOM_CLEAR, BOUNDED).
  `CAI.Brain.SetState` transitions states, clearing transient per-state fields.
  Subsystem modules are invoked from within the brain.
- **Module loading.** `cai_init.lua` defines `Shared()`, `Server()`, `Client()`
  helpers and lists every file in load order. Shared files load first (config,
  convar, util, net, text), then server, then client.

## Conventions to follow when editing

- **New console vars** go in `sh_convars.lua` via `SVar(...)`. Read them with
  `CAI.CVBool(name)`, `CAI.CVNum(name)`, `CAI.Enabled()`, `CAI.Difficulty()`:
  never call `GetConVar` directly in subsystem code.
- **Add a module:** create the file, then register it in `cai_init.lua` with
  `Server(...)`, `Client(...)`, or `Shared(...)` in the correct phase.
- **Brain logic** lives in `server/brain_func/`; each file populates the
  `CAI.Brain` table (aliased `BR`, e.g. `BR.X = function(data) ...` or
  `BR.Exec[N] = function(data) ...`). `sv_brain.lua` only loads those files in
  order, do not put decision logic directly in it. Cross-file brain calls must
  go through `BR.*` (never a `local` function), since each sub-file is a
  separate `include`.
- **Hooks:** use `CAI.SafeHook(event, name, fn)` (defined in `sh_util.lua`),
  not raw `hook.Add`, so failures are caught and rate-limited.
- **Tuning constants** belong in `sh_config.lua` under `CAI.Config.*`, do not
  hardcode magic numbers in logic.
- **Enums:** NPC states live in `CAI.STATE`, squad roles in `CAI.ROLE` (both in
  `sh_config.lua`). Use them, don't compare against raw integers.
- **Profiling:** `CAI.Prof.Record(name, t)` and `CAI.Perf.*` guard on
  `CAI.Prof.active`, wrap expensive sections with `SysTime()` only when
  profiling is on.
- **Trace/visibility:** prefer `CAI.Util.CanSee` / `CAI.Util.Sees` /
  `CAI.Util.CanSeePos` over ad-hoc `util.TraceLine` (they cache results).
- **NPC validity:** use `CAI.Util.Alive(ent)` / `CAI.Util.IsTargetable(ent)`
  before acting on entities.

## Build & release workflow

These scripts have **machine-specific hardcoded paths** (notably
`GMOD_ROOT=/mnt/big/SteamLibrary/steamapps/common/GarrysMod` in `sync_addon.sh`
and the Workshop item id `3760260083` in both scripts).

- `./sync_addon.sh`: (1) `luac -p` syntax-checks every file under `lua/`;
  (2) repacks `build/src/` into `build/output/combat_intelligence_ai.gma` via
  `gma_tool`, (3) rsyncs `lua/` into `build/src/lua/` so a running/extracted
  copy picks up changes. Requires `gma_tool` and optional `luac5.1`.
- `./publish.sh "[changelog]"`: runs `sync_addon.sh` then `gmpublish update`
  to the Workshop. Requires Steam running and logged in.
- **Version bump:** edit `CAI.Version` and `CAI.Build` in `cai_init.lua` (both
  scripts grep the version string). Repack ships the new version automatically.

## In-game testing & debugging

- `cai_debug 1`: full debug overlay (admins), `cai_debug_rays 1` draws
  vision/decision rays.
- `cai_difficulty 0.5 to 2`: reaction speed & accuracy, `cai_dump`: stats.
- `!cai` chat command or the Options menu opens settings.
- A **navmesh is required** for full behavior, on navmesh-less maps the AI is
  "more basic" (see `sv_manager.lua` nav check). Generate one with
  `nav_generate` (needs `sv_cheats 1`).


