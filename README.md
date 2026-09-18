# RSDW Random Events

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod that brings OSRS-style
*random events* into *RuneScape: Dragonwilds* - short, unscripted
interruptions that occasionally fire while you play, the way Old School
RuneScape's Mysterious Old Man, Drunken Dwarf, and friends do.

**Status: confirmed working in-game across dozens of trigger cycles, no
crashes.** For each event: spawn a real Dragonwilds NPC, rename it, show a
"Press F for Random Event" prompt while you're nearby, and on `F` play a
line, give a gift, and despawn. This took a lot of debugging to get right -
several rounds of crash fixes, spawn-placement fixes (NPCs landing
half-buried/floating, a placeholder box at their feet, not facing the
player), and more - the full history is in `CHANGELOG.md` if you're curious;
this README just describes the current, working state.

## The current events

| Event | OSRS inspiration | What it does here |
|---|---|---|
| Mysterious Old Man | [Mysterious Old Man](https://oldschool.runescape.wiki/w/Mysterious_Old_Man) | Spawns Dragonwilds' own Wise Old Man NPC nearby. Gives one random Tier1 skill tome or an Antipoison Potion. |
| Drunken Dwarf | [Drunken Dwarf](https://oldschool.runescape.wiki/w/Drunken_Dwarf) | Spawns Dragonwilds' Doric NPC (a dwarf, per OSRS lore). Gives Umbral Kebab and Strong Tea. |
| Vannaka | [Vannaka](https://oldschool.runescape.wiki/w/Vannaka) | Spawns Dragonwilds' own Vannaka NPC. Gives "mob loot" (two random rolls of common monster-drop materials) rather than food/potions/tomes, since he's a slayer master. |
| Zanik | [Zanik](https://oldschool.runescape.wiki/w/Zanik) | Spawns Dragonwilds' own Zanik NPC. Gives 100x of one random rune, since Zanik's a runecrafting NPC here. |
| Cathan | thematic original (a ghost) | Spawns Dragonwilds' own Cathan NPC. Gives 2x each of 3 random farming/tree seeds. |
| Postie Pete | thematic original (a delivery NPC) | Spawns Dragonwilds' own Postie Pete NPC. Gives a fixed set of "undelivered" building materials (Ash Logs, Ash Planks, Oak Logs). |

All six are defined in `Scripts/events.lua` as `{ id, weight, cooldownMs, run }`
tables. `weight` sets relative pick frequency; `cooldownMs` is a per-event
cooldown on top of the global one in `config.lua`.

## Design decisions

Dragonwilds isn't OSRS, so a few calls had to be made about how to adapt the
concept rather than port it literally:

- **Trigger: time/world-based, not tied to skilling actions.** OSRS rolls a
  random-event chance on skilling actions (chop, mine, fish, ...).
  Dragonwilds is a survival game where "skilling" is one part of a much
  broader moment-to-moment loop, so events here instead fire off a simple
  periodic timer (`Config.CheckIntervalMs` + `Config.TriggerChance` in
  `Scripts/config.lua`) whenever you're in an active gameplay world. Mean
  gap between events is roughly `CheckIntervalMs / TriggerChance` (~8 min
  by default).
- **NPCs: reuse existing Dragonwilds actors, not custom art.** OSRS's random
  events each have a bespoke NPC. Building new 3D models/animations for
  Dragonwilds needs a whole separate asset pipeline outside what a Lua mod
  can do (and possibly outside what's feasible at all without an official
  SDK). So every event here spawns a real, existing Dragonwilds NPC instead
  (`Config.EnableExperimentalSpawns`, on by default and confirmed working).
- **Scope: six events for now**, not the full ~30-event OSRS roster. Adding
  more is just appending to `Scripts/events.lua` - see "Filling in a spawn
  target" below for how to find a new NPC to use.

## Project layout

```text
Scripts/
  main.lua        - entry point: trigger loop, weighted event picker, F hotkey
  config.lua       - all tunables (timing, hotkeys, colors, gift tables)
  events.lua        - the event registry (add new events here)
  encounter.lua      - scripted NPC encounters: rename, show the "Press F"
                        prompt while nearby, say a line, give item(s), say
                        a line, despawn
  notify.lua         - toast notification UI (custom UMG panel)
  prompt.lua         - persistent "Press F for Random Event" UI prompt
  discovery.lua       - dev tool: logs nearby actor class paths (not wired
                        to a hotkey - see "Filling in a spawn target")
install.ps1     - dev install: junctions this repo into the game's ue4ss\Mods
package.ps1     - builds a release zip (CurseForge, Nexus Mods, etc.)
tools/
  Install-UE4SS.ps1 - downloads + installs UE4SS itself into the game (one-time)
VERSION         - current mod version
CHANGELOG.md    - full release/development history
```

## One-time setup

1. **Install UE4SS into the game** (if not already present):
   ```powershell
   .\tools\Install-UE4SS.ps1
   ```
   This downloads the UE4SS *experimental* build line into
   `RSDragonwilds\Binaries\Win64`. Experimental, not stable 3.0.1, because
   the reference `DragonwildsHUD` mod's README documents stable builds
   crashing this game on certain UMG calls (`SetText` on a `TextBlock`) -
   the same UMG APIs this mod's toast UI uses.
2. Launch RSDragonwilds once, reach the main menu, then close it - this
   lets UE4SS create `Binaries\Win64\ue4ss\Mods`. Confirm that folder exists.
3. Install this mod:
   ```powershell
   .\install.ps1
   ```
   This junctions `ue4ss\Mods\RSDWRandomEvents` to this repo (so edits here
   take effect immediately) and adds `RSDWRandomEvents : 1` to `mods.txt`.
   (If you're installing from a release zip instead of this repo, just
   extract the `RSDWRandomEvents` folder straight into `ue4ss\Mods\`.)

## Testing

1. Launch the game and check `Binaries\Win64\ue4ss\UE4SS.log` for
   `[RSDWRandomEvents] Loaded v0.2.0. F = trigger a nearby event NPC's
   encounter.` - confirms the mod loaded without a script error.
2. Get into an active gameplay world (past any menu) and just play. Events
   fire on their own passive timer - there's no manual trigger hotkey (it
   was a dev-only debug tool, removed for public testing) - so expect a
   random event roughly every ~8 minutes on default settings, not on a
   predictable schedule. If you want to test faster, temporarily lower
   `Config.CheckIntervalMs` and/or raise `Config.TriggerChance` in
   `Scripts/config.lua`.
3. When a "A Random Event Has Spawned!" toast appears, walk toward the
   spawned NPC - you'll see a "Press F for Random Event" prompt once
   you're close enough. Press `F` to play it out.
4. Report back what's broken (a Lua error in `UE4SS.log`, a toast/prompt
   that doesn't show/hide right, a gift that doesn't land, positioning off
   at your resolution, pacing feeling too frequent/rare, etc.).

## Filling in a spawn target

`events.lua`'s six events each spawn an actor of a configured class near
the player, via a shared `trySpawnNearPlayer` helper in `events.lua`. All
six class paths are already filled in - see `Scripts/config.lua`'s
`Config.*ClassPath` entries.

If you want to add a new event using a different NPC, `Scripts/discovery.lua`
is a dev tool for finding one: stand near the NPC you want and call
`Discovery.Run()` (not wired to a hotkey by default - wire a temporary
`RegisterKeyBind` in `main.lua`, the same way the F hotkey is registered, to
call it). It logs every nearby Actor's class path + distance + display name
to `Scripts/discovery_log.txt` (gitignored - local scratch output). Use one
of the logged class paths as a new `Config.<Event>ClassPath`.

## Custom dialogue and item-giving

Each spawned NPC gets a name and chat distinct from the real NPC it's
copied from, and gives the player items then despawns. Implemented in
`Scripts/encounter.lua` and `Scripts/prompt.lua`. The full debugging
history - several rounds of crashes and dead ends before landing here - is
in `CHANGELOG.md`; this section just describes the current design.

- **Renaming**: `AWorldActor.DisplayName` (an `FText` property every
  world actor has) is set to the event's name, e.g. "The Mysterious Old
  Man".
- **The native "Press E to interact" prompt is disabled** on the spawned
  copy (`InteractionComponent:SetActive(false, false)`, in
  `Encounter.Run`) - it only opened the stock tutorial dialogue, which
  does nothing useful here now that `F` is the real interaction. Never
  touches the real NPC, only the actor we just spawned.
- **Triggering on `F`, a dedicated key, not the game's own interact
  button**: reliably intercepting the real interact button turned out
  not to be possible (`RegisterHook` doesn't support delegate functions,
  and three native functions that looked like plausible alternatives all
  confirmed to never fire for these NPCs - see CHANGELOG). A "Press F for
  Random Event" prompt (`Scripts/prompt.lua`, a persistent toggleable UMG
  panel) shows automatically while the player is within
  `Config.EncounterRadius` of a spawned, tracked NPC, via a proximity
  poll in `encounter.lua` (which also keeps the NPC turned to face the
  player). Pressing `F` (`Config.HotkeyEncounterInteract`) calls
  `Encounter.TryTriggerNearby()`, which plays the line/gift/despawn
  sequence directly.
- **Giving items**: items are `UItemData` objects (data-only Blueprints,
  not distinct actor classes), given via
  `PlayerController:GetInventory():AddItemByData(itemData, count,
  durabilityPercentage, gameplayTags)`, guarded by a `CanAddItemByData`
  check first. A gift is either a plain asset-path string (gives 1) or a
  `{ path = "...", count = N }` table (gives N, as N separate `Count=1`
  calls). The `GameplayTagContainer` argument is `nil`, not `{}`, and the
  whole call runs wrapped in `ExecuteInGameThread` - both were real causes
  of crashes during development (see CHANGELOG for the full story; the
  `ExecuteInGameThread` one was the actual root cause behind most of it).
- **Placement**: spawned NPCs are ground-snapped (a trace under both the
  player and the spawn point, so it works on slopes/ledges, not just flat
  ground) and have their placeholder "box" meshes hidden - see CHANGELOG
  for the mesh-hiding details if a future NPC shows a visible box.
- **If nobody presses F**: each spawned NPC despawns quietly after
  `Config.EncounterMaxWaitMs` (2 min default) rather than lingering forever.

## Hot reloading

UE4SS's hot-reload (`Ctrl+R` by default) should pick up edits to these
scripts without a full restart, if `EnableHotReloadSystem = 1` is set in
`UE4SS-settings.ini` (takes effect after a restart). The `DragonwildsHUD`
mod's README notes at least one UE4SS build where `Ctrl+R` crashes the game
outright - if that happens here too, just restart fully after edits instead.

## Configuration

See `Scripts/config.lua` - trigger timing, the F hotkey, toast/prompt
appearance, and every event's line(s) and gift table are all there with
inline comments. `Config.Debug = true` by default turns on verbose logging
to `UE4SS.log`, which is helpful if you're reporting a bug.

## Releases

See `CHANGELOG.md`. To build a release zip: `.\package.ps1`, which reads
`VERSION` and produces `dist\RSDWRandomEvents-vX.Y.Z.zip`.
