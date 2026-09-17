# RSDW Random Events

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod that brings OSRS-style
*random events* into *RuneScape: Dragonwilds* - short, unscripted
interruptions that occasionally fire while you play, the way Old School
RuneScape's Mysterious Old Man, Drunken Dwarf, and friends do.

Status: **confirmed working end to end, on a tutorial-complete
character**. For each event: spawn, rename, disable the now-redundant
native "Press E to interact" prompt, show a "Press F for Random Event"
prompt near the spawned NPC, and on `F` play the scripted line, give the
full gift list, and despawn. Full history of what it took to get here -
several rounds of crash debugging (a `RegisterHook`-based approach to
the real interact button that turned out to be a dead end, a
`GameplayTagContainer` argument bug that caused intermittent
`AddItemByData` crashes, a toast-wrapping bug, a menu-crash) - is in
`CHANGELOG.md`.

**Known limitation**: these events require the player's character to
have completed the early tutorial content involving Doric/Vannaka/the
Wise Old Man - giving an item on a pre-tutorial character crashes the
game, most likely because that NPC's own quest-tracking Blueprint logic
doesn't expect a duplicate to be the one whose inventory changes. See
"Custom dialogue and item-giving" below.

Currently pared down to the four events being actively worked on
(Mysterious Old Man, Drunken Dwarf, Vannaka, Zanik); Bird's Nest, Freaky
Forester, and Sandwich Lady were removed from `events.lua` for now, not
lost design work - they're simple toast-only events and can be re-added
once these are done.

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
  SDK). So the default here is flavor-text toast notifications, with two
  events (Mysterious Old Man, Drunken Dwarf) also able to spawn a real
  Dragonwilds NPC found via the discovery tool - see "Filling in a spawn
  target" below. Spawning is still opt-in (`Config.EnableExperimentalSpawns`),
  because the two candidates found are both tutorial-bound "_FTUE" NPCs
  normally treated as singletons, so spawning a duplicate is unproven.
- **Scope: a couple of events at a time as a proof of concept**, not the
  full ~30-event OSRS roster. The point of this pass is to prove the
  framework (trigger loop, weighted registry, cooldowns, toast UI, NPC
  spawning) end-to-end on a couple of events before scaling out. Adding
  more events once these are confirmed working is just appending to
  `Scripts/events.lua`.

## The current events

| Event | OSRS inspiration | What it does here |
|---|---|---|
| Mysterious Old Man | [Mysterious Old Man](https://oldschool.runescape.wiki/w/Mysterious_Old_Man) | "A Random Event Has Spawned!" toast, then spawns Dragonwilds' own Wise Old Man NPC nearby (`Config.EnableExperimentalSpawns`). |
| Drunken Dwarf | [Drunken Dwarf](https://oldschool.runescape.wiki/w/Drunken_Dwarf) | Same toast, then spawns Dragonwilds' Doric NPC nearby (a dwarf, per OSRS lore; same flag). |
| Vannaka | [Vannaka](https://oldschool.runescape.wiki/w/Vannaka) | Same toast, then spawns Dragonwilds' own Vannaka NPC nearby (same flag). Gives "mob loot" (2 rolls on `Config.VannakaLootTable`) rather than food/potions/tomes, since he's a slayer master. |
| Zanik | [Zanik](https://oldschool.runescape.wiki/w/Zanik) | Same toast, then spawns Dragonwilds' own Zanik NPC nearby (same flag). Gives 100x of one random rune (Air/Fire/Earth/Water/Law/Cosmic/Astral, from `Config.ZanikRuneTable`), since Zanik's a runecrafting NPC here. |

All four are defined in `Scripts/events.lua` as `{ id, weight, cooldownMs, run }`
tables. `weight` sets relative pick frequency; `cooldownMs` is a per-event
cooldown on top of the global one in `config.lua`. Bird's Nest, Freaky
Forester, and Sandwich Lady are removed from the registry for now (not
lost - just simple toast-only events, easy to re-add once these are done).

## Project layout

```text
Scripts/
  main.lua        - entry point: trigger loop, weighted event picker, hotkeys
  config.lua       - all tunables (timing, hotkeys, colors, experimental flags)
  events.lua        - the event registry (add new events here)
  encounter.lua      - scripted NPC encounters: rename, show the "Press F"
                        prompt while nearby, say a line, give item(s), say
                        a line, despawn - plus the stray-spawn cleanup dev
                        tools
  notify.lua         - toast notification UI (custom UMG panel)
  prompt.lua         - persistent "Press F for Random Event" UI prompt
  discovery.lua       - dev tool: logs nearby actor class paths (.)
install.ps1     - dev install: junctions this repo into the game's ue4ss\Mods
package.ps1     - builds a release zip for Nexus Mods
tools/
  Install-UE4SS.ps1 - downloads + installs UE4SS itself into the game (one-time)
VERSION         - current mod version
CHANGELOG.md    - release history
```

## One-time setup

1. **Install UE4SS into the game** (not yet present on this machine as of
   writing - only the VR mod's UEVR injector was installed):
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

## Testing

I can't launch and play the game myself, so this hasn't been run in-game
yet - that part is on you, the same way it was for the VR controller mod in
the sibling `Dragonwilds-VR` project ("I can't put a headset on, so testing
is on you"). Concretely:

1. Launch the game and check `Binaries\Win64\ue4ss\UE4SS.log` for
   `[RSDWRandomEvents] Loaded v0.1.0. F = trigger a nearby event NPC's
   encounter, , = force-trigger a random event, . = log nearby actor
   class paths, / = dump SDK headers + object properties, [ = destroy
   orphaned renamed spawns.` - confirms the mod loaded without a script
   error.
2. Get into an active gameplay world (past any menu), then press **,**
   repeatedly - each press should force-fire a random event immediately
   (bypassing cooldowns), and a toast should appear near the top-center of
   the screen for ~7 seconds. This is the fastest way to check both
   events' toasts render correctly without waiting on the timer.
3. Leave the game running for ~10-15 minutes without pressing **,**, to
   confirm the passive timer (`Config.CheckIntervalMs`/`TriggerChance`)
   fires naturally at a reasonable pace.
4. Report back what's broken (a Lua error in `UE4SS.log`, a toast that
   doesn't show/hide right, positioning off-screen at your resolution,
   pacing feeling too frequent/rare, etc.) and I'll adjust from there.

## Filling in a spawn target

`events.lua`'s `mysterious_old_man`, `drunken_dwarf`, `vannaka`, and
`zanik` events will, if enabled, spawn an actor of a configured class
near the player, via a shared `trySpawnNearPlayer` helper. All four
class paths are already filled in, found with the discovery tool (.)
near actual in-game NPCs:

- `Config.MysteriousOldManClassPath` -> Dragonwilds' Wise Old Man
  (`BP_NPC_WiseOldMan_FTUE`) - a strong thematic match.
- `Config.DrunkenDwarfClassPath` -> Dragonwilds' Doric (`BP_NPC_Doric_FTUE`)
  - Doric is a dwarf in OSRS lore.
- `Config.VannakaClassPath` -> Dragonwilds' own Vannaka (`BP_NPC_Vannaka_FTUE`)
  - same name as the OSRS slayer master.
- `Config.ZanikClassPath` -> Dragonwilds' own Zanik (`BP_NPC_Zanik_FTUE`)
  - same name as the OSRS runecrafting NPC.

All four are `_FTUE` NPCs - normally singleton tutorial characters - so
spawning a duplicate elsewhere in the world was unproven going in, but
`Config.EnableExperimentalSpawns = true` is confirmed working for the
first three, with custom name/dialogue/item-giving fully working too -
see "Custom dialogue and item-giving" below (including a known
limitation around tutorial-incomplete characters). Zanik is wired up the
same way but not yet tested in-game.

If you find a better (non-singleton) candidate for any of these events
later, get near it and press **.** - the discovery tool logs to
`Scripts/discovery_log.txt` (gitignored - local scratch output) every
`Actor` within `Config.DiscoveryRadius` units, sorted by distance, with
each one's Blueprint class path and location.

## Custom dialogue and item-giving

Each spawned NPC gets a name and chat distinct from the real Wise Old
Man/Doric/Vannaka, and gives the player items then despawns. Implemented
in `Scripts/encounter.lua` and `Scripts/prompt.lua`. **Confirmed working
end to end in-game** (on a tutorial-complete character - see the known
limitation below). The full debugging history - several rounds of
crashes and dead ends before landing here - is in `CHANGELOG.md`;
this section just describes the current design.

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
  poll in `encounter.lua`. Pressing `F` (`Config.HotkeyEncounterInteract`)
  calls `Encounter.TryTriggerNearby()`, which plays the line/gift/despawn
  sequence directly.
- **Giving items**: items are `UItemData` objects (data-only Blueprints,
  not distinct actor classes), given via
  `PlayerController:GetInventory():AddItemByData(itemData, count,
  durabilityPercentage, gameplayTags)`, guarded by a `CanAddItemByData`
  check first. A gift is either a plain asset-path string (gives 1) or a
  `{ path = "...", count = N }` table (gives N, as N separate `Count=1`
  calls). The `GameplayTagContainer` argument is `nil`, not `{}` - that
  was the real cause of several crashes during testing (see CHANGELOG).
- **If nobody presses F**: each spawned NPC despawns quietly after
  `Config.EncounterMaxWaitMs` (2 min default) rather than lingering forever.

**EXPERIMENTAL - world drops instead of inventory**: a 2026-09-17 Mining
tome crash showed the "tome crash" (see CHANGELOG) isn't tied to a specific
skill's tome or a broken icon reference - two other tomes were given
successfully in the same play session with the identical warning signature,
and the player's Mining skill wasn't untrained. With no reproducible
per-item cause found, `Config.GiveItemsAsWorldDrops` (default `false`) routes
gifts through `Encounter.dropItem` instead of `Encounter.giveItem`: it spawns
the item as a physical pickup on the ground via
`ItemHelperLibrary:SpawnAndLaunchItem_Sync` rather than injecting it into
inventory via `AddItemByData`, on the theory that the drop path is the same
one ordinary loot/resource drops already use in the base game, and is
therefore more battle-tested than handing a class instance to a generic
inventory-mutation call it may never have been designed for. See
`encounter.lua`'s `dropItem` for the specific unknowns - this hasn't been
run in-game yet.

**Known limitation**: these events require the player's character to
have completed the early tutorial content involving Doric/Vannaka/the
Wise Old Man. Each of these NPCs carries its own `QuestData` and
quest-tracking Blueprint logic (`OnQuestStateChanged`,
`UpdateQuestIndicator`) tied to its tutorial questline; giving an item
through the generic `AddItemByData` path crashes the game on a
pre-tutorial character, most likely because that logic doesn't expect a
duplicate NPC to be the one whose inventory changes. Confirming this
precisely would mean reading quest state via `GetLocalPlayerQuestState`
before spawning/giving, but that takes an out-parameter whose UE4SS Lua
calling convention is unverified - not worth the crash risk to test
blind, so this is documented as a limitation instead of coded around.

## Hot reloading

UE4SS's hot-reload (`Ctrl+R` by default) should pick up edits to these
scripts without a full restart, if `EnableHotReloadSystem = 1` is set in
`UE4SS-settings.ini` (takes effect after a restart). The `DragonwildsHUD`
mod's README notes at least one UE4SS build where `Ctrl+R` crashes the game
outright - if that happens here too, just restart fully after edits instead.

## Configuration

See `Scripts/config.lua` - trigger timing, hotkeys, toast appearance,
discovery radius, and the experimental-spawn flags are all there with
inline comments.

## Releases

See `CHANGELOG.md`. To build a release zip: `.\package.ps1`, which reads
`VERSION` and produces `dist\RSDWRandomEvents-vX.Y.Z.zip`.
