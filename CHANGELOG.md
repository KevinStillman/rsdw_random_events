# Changelog

## 0.1.0

- Initial proof of concept: event framework (weighted registry, global +
  per-event cooldowns, time-based trigger loop) with five OSRS-inspired
  random events (Mysterious Old Man, Bird's Nest, Freaky Forester, Sandwich
  Lady, Drunken Dwarf).
- Toast notification UI (custom UMG panel) for event flavor text.
- Discovery dev tool (.) for finding nearby actor class paths to use as
  future spawn targets.
- Manual trigger hotkey (,) for testing without waiting on the random
  timer.
- Fixed `RegisterKeyBind` calls: this UE4SS build requires a numeric virtual-key
  code (the global `Key.*` table, e.g. `Key.OEM_COMMA`), not a string name -
  the string form crashed the whole mod script on load, silently disabling
  both hotkeys. Confirmed in-game: force-trigger (`,`) now shows toasts, and
  the passive timer fires on its own too.
- Fixed the discovery tool: `GetPathName()` isn't exposed to Lua (only
  `GetClass():GetFullName()` is, hence every class path logging as `?`),
  and comparing pawns with `~=` doesn't detect "is this the player" since
  separately-obtained Lua proxies for the same UObject aren't `==` (hence
  the player's own pawn showing up in every scan). Also broadened the scan
  from `Pawn` to `Actor`, since Dragonwilds' dialogue/quest NPCs turned out
  not to be Pawn-derived at all.
- Moved the experimental NPC-spawn capability from Drunken Dwarf onto
  Mysterious Old Man (better thematic fit - Dragonwilds' own "Wise Old Man"
  tutorial NPC), and wired Drunken Dwarf's spawn to Dragonwilds' Doric NPC
  (a dwarf, per OSRS lore), via a shared `trySpawnNearPlayer` helper. Both
  class paths found via the discovery tool. Still opt-in
  (`Config.EnableExperimentalSpawns = false`) since both are `_FTUE`
  (tutorial/singleton) NPCs and duplicating them is unconfirmed-safe.
- Fixed NPC spawning: `StaticFindObject` only finds objects already
  resident in memory, so it correctly found Doric's/Wise Old Man's class
  while standing next to them (that's how the discovery tool worked) but
  failed everywhere else, since their class only stays loaded while their
  placed instance's streaming level is nearby. `trySpawnNearPlayer` now
  calls `LoadAsset` first to force the package to load, matching the
  pattern UE4SS's own bundled "summon" console command uses.
- Fixed NPC spawning again: `BeginDeferredActorSpawnFromClass` and
  `FinishSpawningActor` both errored ("UFunction expected 6/3 parameters,
  received 5/2") - this UE5 version added a trailing `ESpawnActorScaleMethod`
  parameter to both that the UE4-era signature didn't have. Added it
  (`0`, its default), confirmed against an independent UE4SS Lua SDK for
  another UE5 game hitting the identical signatures.
- Confirmed in-game: both Mysterious Old Man and Drunken Dwarf successfully
  spawn their NPC with `Config.EnableExperimentalSpawns = true`.
- Removed Bird's Nest, Freaky Forester, and Sandwich Lady from the event
  registry (not deleted from design, just out of scope for now) to focus
  on Mysterious Old Man and Drunken Dwarf while adding custom
  name/dialogue/item-giving to their spawned NPCs.
- Added a dump dev-tool hotkey (/): this game's engine fork doesn't render
  UE4SS's ImGui debug overlay (pressing `` ` `` only opens its plain text
  console), so rather than depending on that GUI's "Dumpers" tab, `/` calls
  `GenerateSDK()` and `DumpAllObjects()` directly - needed to get ground
  truth on the NPC name/dialogue and item-giving APIs instead of guessing.
- Added `Scripts/encounter.lua`: scripted NPC encounters built from the SDK
  dump - renames the spawned NPC (`AWorldActor.DisplayName`), best-effort
  disables its stock dialogue (`UDomConversationParticipant:SetActive`),
  waits for the player to get close (proximity trigger, since reliably
  intercepting the real "talk" interaction would need unverified delegate
  hooking), then plays a line, gives item(s) via
  `UInventoryComponent:AddItemByData`, an optional second line, and
  despawns (or despawns quietly if nobody approaches in time). Wired into
  both events with the exact requested lines; item paths confirmed
  (Umbral Kebab) or inferred-pending-confirmation (Strong Tea) from the
  object dump.
- Confirmed in-game: renaming and item-giving both work. Items "seem
  bugged" per initial testing (details TBD) and the stock dialogue still
  opened unchanged - `DomConversationParticipant:SetActive(false, false)`
  alone didn't stop it, most likely because the NPC's own interaction
  Blueprint graph calls into the conversation system directly regardless
  of that component's active state. Also added `InteractionComponent:SetActive(false,
  false)` (disables the interact prompt/OnInteraction event entirely,
  which is what actually drives the stock dialogue) and logging on every
  step of `encounter.lua` (previously only logged failures, so a
  successful run left us with zero visibility into what happened).
- Added a cleanup dev-tool hotkey ([): destroys any of our renamed NPC
  spawns still standing around, for copies orphaned when a restart/reload
  killed the Lua-side despawn timer/poll loop that was tracking them
  before it could finish (the spawned actor persists in the game world
  independently of Lua VM state). Only touches actors whose DisplayName
  exactly matches one of our own renamed strings, never the real NPC.
- Added `Encounter.CleanupNearest` to the cleanup hotkey: the two stray
  NPCs from initial testing predate the rename code, so `CleanupNamed` has
  nothing to match on. This variant instead destroys whichever instance of
  the class is closest to the player, gated on being within 200 units
  (i.e. you're standing right next to it) and more than one instance of
  that class existing at all - so it can't touch the sole real NPC when no
  duplicate is around. One real caveat: if the real NPC and a duplicate are
  both that close to you at once, whichever is literally closer gets
  destroyed - move away from the real one first if that's a risk.
- Fixed toast body text wrapping one word per line instead of filling
  lines left to right: `SetAutoWrapText(true)` alone measures the
  container's on-screen width, which isn't settled the first time the
  panel is built in the same frame it's shown, reading as ~0. Added an
  explicit `SetWrapTextAt(Config.ToastWidth - 2*Config.ToastPadding)`,
  which doesn't depend on layout having already happened.
- Reworked NPC interaction entirely: proximity-triggering is out, the real
  interact button/prompt is back to fully enabled and untouched (undid
  disabling `InteractionComponent`/`DomConversationParticipant`).
  `Encounter.Run` now registers each spawned actor in an address-keyed
  table, and a hook on `Server_StartConversation` (a plain native RPC on
  the player's `UPlayerConversationComponent`, called with the NPC as its
  `Target` param whenever any conversation starts - not a delegate, so
  unlike `OnInteraction` it's actually hookable) checks every conversation
  request's target against that table. On a match: destroys the target
  immediately (best-effort attempt to stop the stock dialogue from
  actually opening, betting a multiplayer-safe RPC already handles its
  target vanishing mid-request - genuinely unverified) and plays the
  scripted line/gift/despawn sequence. Installed once at mod load via
  `Encounter.InstallConversationHook`. Confirmed in-game: the interact
  button/prompt works again, and the hook itself installed successfully
  (`/Script/Dominion.PlayerConversationComponent:Server_StartConversation`
  registered without error).
- Found the real reason nothing appeared to happen on interact: not the
  hook at all - the previous toast-wrapping fix broke toast construction
  outright. `SetWrapTextAt(...)` isn't a callable method on this
  `TextBlock`, it errored with "attempt to call a TrivialObject value",
  which aborted `ensurePanel()` before the panel ever finished building -
  so every `Notify.Show` since that fix (including the ambient toast that
  fires before the NPC is even spawned) silently failed, making it look
  like interacting did nothing. `WrapTextAt` is a plain property here,
  not a setter method - fixed via direct assignment
  (`body.WrapTextAt = ...`), matching how other simple properties
  (`Font.Size`, `Visibility`) are already set elsewhere in this file. The
  actual interaction-hook question (does it fire, does it recognize the
  target) is still open pending a retest with toasts working again.
- Fixed a crash: a random event fired while a menu was open. A valid
  `PlayerController`/`Pawn` doesn't rule that out - both can stay valid
  while a menu is open over the still-loaded world - so `isInGameplayWorld`
  now also requires `PlayerController.CurrentInputMode` to exactly match
  `.GameplayInputMode` (the baseline "normal play, nothing open" mode),
  comparing by address since separately-obtained Lua proxies for the same
  UObject aren't `==`. Applies to the passive timer and every hotkey.
- Confirmed in-game (toasts fixed, no crash): interacting with a spawned,
  renamed NPC still shows only the stock dialogue - no `Encounter
  'interaction detected'` line appeared, and the cleanup hotkey later
  found and destroyed the still-alive renamed NPC that should have been
  destroyed by the hook, confirming it never fired for this interaction.
  The hook callback previously swallowed every early-return case with no
  logging, so there was no way to tell *why*. Added unconditional logging
  at the very top of the callback (target name/address, whether it
  matched something tracked) so the next test will show whether this
  hook fires at all for these FTUE tutorial NPCs, or whether they route
  through something else entirely.
- Confirmed with that logging: `Server_StartConversation` really does
  never fire for these NPCs - not even the unconditional log line at the
  top of the callback appeared. Added two more hooks to try
  simultaneously rather than guessing again one at a time:
  `AsyncAction_DomStartConversation:AsyncDomStartConversation` (the
  actual Blueprint-callable entry point for the "Start Conversation"
  async node - the standard UE5 pattern for this kind of latent
  Blueprint action, and a stronger candidate than the RPC) and
  `PlayerConversationComponent:SetupEnterConversationOnMapClosed` (in
  case tutorial conversations defer entry until some map/menu closes
  first). All three now log unconditionally through a shared
  `handlePotentialInteraction` and are registered independently (each in
  its own `pcall`) so one not existing in memory yet can't prevent the
  others from installing. Not yet tested.
- Confirmed in-game: none of the three hooks fired either. Abandoned
  hooking the native interaction/conversation system entirely - removed
  `Encounter.InstallConversationHook` and `handlePotentialInteraction`
  along with all three `RegisterHook` calls.
- Replaced it with a dedicated encounter key instead of continuing to
  guess at native hook points: a new "Press F for Random Event" prompt
  (`Scripts/prompt.lua`, a persistent toggleable UMG panel distinct from
  `notify.lua`'s auto-hiding toast) shows automatically while the player
  is within `Config.EncounterRadius` of a spawned, tracked NPC, driven by
  a proximity poll in `encounter.lua` (`ensurePollRunning`/
  `findNearbyTrackedActor`). Pressing `F` (`Config.HotkeyEncounterInteract`)
  calls `Encounter.TryTriggerNearby()`, which plays the line/gift/despawn
  sequence directly - no need to destroy the actor pre-emptively to block
  a stock dialogue anymore, since `F` is a wholly separate action from the
  game's own interact button (`E`), which keeps working normally and is
  untouched. `Config.EncounterRadius` (removed earlier when proximity was
  dropped in favor of hooking) is back.
- Confirmed in-game: the full flow works end to end - prompt appears,
  `F` gives the item and shows the toast, NPC despawns.
- Fixed the toast-wrapping bug for real this time (screenshot showed it
  still stacking one word per line despite the earlier "fix"): setting
  `WrapTextAt` alone does nothing while `AutoWrapText` is still `true` -
  Slate's internal `GetWrapTextAt()` always uses its own auto-computed
  width in that case and never even reads `WrapTextAt`, regardless of
  its value. Added `SetAutoWrapText(false)` in both `notify.lua` and
  `prompt.lua` (which had the identical bug, just not yet visibly
  triggered by long enough text) so `WrapTextAt` actually takes effect.
- Replaced both events' ambient spawn toast (previously per-event flavor
  text - "An old man watches you from the treeline...",
  "You hear off-key singing nearby...") with the same generic
  "A Random Event Has Spawned! / Press F to interact with them." for
  both, since that's the actual actionable information now that F drives
  the encounter. Removed `getRandomSkill` from `events.lua`, now unused.
- Replaced `Config.MysteriousOldManGiftPool`'s Umbral Kebab placeholder
  with a real gift list: Antipoison Potion (T3, the untiered-named one -
  4 tiers exist: Weak/T1, Lesser/T2, plain/T3, Super/T4) x2, and one
  Tier1 skill tome per skill (12 total: Attack, Magic, Ranged,
  Woodcutting, Mining, Farming, Fishing, Runecrafting, Construction,
  Artisan, Cooking, Agility) - excludes the "Tier0" quest/lore tomes
  (DragonSlayerQuest, DeathQuestMain, and others not currently loaded,
  likely including Undying/Titan), which use a different naming scheme
  and aren't skill-XP items. Added per-gift count support to
  `encounter.lua`'s `giveItem`/`playSequence` (a gift is now either a
  plain path string, giving 1, or a `{ path, count }` table) to support
  the x2 potion; `Encounter.Run`'s `opts.itemPaths` is renamed
  `opts.gifts` to match. `DrunkenDwarfGifts` is unchanged (still Strong
  Tea + Umbral Kebab).
- Fixed a crash: giving Mysterious Old Man's gift crashed the game
  outright (an engine-level crash - no catchable Lua error, the log just
  stopped mid-`giveItem`), most likely from the one call using
  `Count=2` in a single `AddItemByData` (the Antipoison Potion x2 gift) -
  every previous `Count=1` call, including two just before this one for
  Drunken Dwarf's gifts, had worked fine. `giveItem` now gives a count>1
  gift as N separate `Count=1` calls instead, and logs which item/count
  it's about to attempt *before* calling `AddItemByData`, so if this
  wasn't actually the cause and it crashes again, the log will say
  exactly which item was responsible this time.
- Added a third event: Vannaka, spawning Dragonwilds' own Vannaka NPC
  (`Config.VannakaClassPath`, found via the discovery tool). Line: "Finally,
  an adventurer! My inventory is too full, please take these.." - no
  closing line, matching Drunken Dwarf's pattern. Gift is "mob loot"
  rather than food/potions/tomes (he's a slayer master in OSRS): two
  rolls, with replacement, on `Config.VannakaLootTable` (Fleece, Coarse
  Animal Fur, Animal Hide Scraps, Raw Farm Meat, Animal Hide - all x3 per
  roll), via a new `rollTwice` helper in `events.lua`. Added to the
  cleanup hotkey's `CleanupNamed`/`CleanupNearest` passes alongside the
  other two events.
- Fixed a second crash: force-firing events by mashing `,` spawns them all
  at the same fixed offset (always +300,+300 from the player), so several
  triggered in quick succession land on top of each other. Randomized the
  spawn offset direction in `trySpawnNearPlayer` (`events.lua`) instead of
  the fixed diagonal.
- Found the real cause of both `Count`-related crashes so far: not
  `Count=2` after all. Giving `ITEM_Consumable_Tome_Tier1_Artisan` with
  `Count=1` (post-fix) crashed identically - no catchable Lua error,
  right as `AddItemByData` was called. Tomes are a `BP_Consumables_SkillTome_C`
  class with per-instance state (an `XPEventHandle` struct property) that
  `AddItemByData`'s generic item-instantiation path most likely doesn't
  initialize correctly. Removed all 12 tomes from
  `Config.MysteriousOldManGiftPool` rather than keep crash-testing which
  ones are safe - it's just the Antipoison Potion for now. Giving a
  tome probably needs a different API (maybe spawning as a world pickup
  via `UItemHelperLibrary` instead of straight into inventory) - not yet
  investigated.
- Confirmed in-game: Vannaka's loot table works perfectly (two full runs,
  all 5 possible items given successfully across them).
- Fixed a crash giving Drunken Dwarf's Strong Tea, with the identical
  "no catchable error, frozen right after the attempt log line" signature
  as the tome crash - but this exact item had already succeeded twice
  earlier in the same session, so it isn't a fundamentally bad item like
  the tomes. Most likely cause: the inventory was full/near-full by that
  point in testing, and `AddItemByData` doesn't handle "no space"
  gracefully. Added a `CanAddItemByData` check before every
  `AddItemByData` call in `giveItem` - skips (logs) rather than risking
  a crash if there's no room.
- The full-inventory theory was wrong: confirmed in-game with an almost
  empty inventory, Strong Tea crashed again, identically - passed the new
  `CanAddItemByData` check (so it's not a space issue) and froze exactly
  inside `AddItemByData` again. Since every other item has been solid
  across dozens of trials (Umbral Kebab, all 5 Vannaka items, the
  Antipoison Potion), and Strong Tea's path was always the one *inferred*
  guess (never confirmed - its real package wasn't loaded when first
  searched), it's most likely just the wrong path. Removed it from
  `Config.DrunkenDwarfGifts` (now just Umbral Kebab) rather than keep
  crash-testing it. To find the real path: craft or view a Strong Tea
  in-game once (loads its actual asset), dump again (`/`), and search for
  it the same way Umbral Kebab's was originally found.
- The "wrong path" theory for Strong Tea didn't hold up either: giving
  Umbral Kebab (the one item confirmed rock-solid across dozens of prior
  successful trials, on the exact same asset path every time) crashed too,
  identically. That rules out any specific item as the cause. The one
  remaining unverified piece of every `AddItemByData` call is the 4th
  parameter, `GameplayTagContainer` - always passed as a bare `{}`.
  `FGameplayTagContainer` has two `TArray` fields (`GameplayTags`,
  `ParentTags`); UE4SS's Lua-to-struct marshaling may not reliably
  zero-init both from an empty table literal, which would explain
  crashes that aren't deterministic per item - sometimes leftover memory
  happens to look like a valid empty array, sometimes it doesn't. Changed
  to pass `nil` instead, to hit a cleaner default code path. This is a
  real experiment, not a confirmed fix - if it still crashes, `AddItemByData`
  itself may just be unstable via this Lua binding, and giving items
  directly into inventory this way may need to be abandoned in favor of
  a different approach (e.g. spawning a world pickup via
  `UItemHelperLibrary` for the player to loot normally, going through the
  game's own well-tested pickup code instead of a raw reflection call).
- The `nil` fix looks like it actually worked: confirmed in-game, Drunken
  Dwarf's Umbral Kebab gift now succeeds cleanly on the first attempt on
  at least one character, and Vannaka's loot continues to work perfectly
  across repeat trials.
- Corrected the record: initially misread which of two characters crashed
  and which didn't, concluding (backwards) that the *veteran* character
  was corrupted from earlier crashes. It's the opposite - the character
  that still crashes on Drunken Dwarf's gift is the **pre-tutorial** one
  (hasn't yet met the real Doric through normal story progression); the
  one that works has already completed that early content. So the real
  differentiator is active tutorial/quest state on the real NPC, not
  save corruption - giving an item via the generic `AddItemByData` path
  most likely trips something in Doric's Blueprint quest-tracking logic
  (`OnQuestStateChanged`/`UpdateQuestIndicator`) while that questline is
  still active, quite possibly because it's listening for
  inventory-changed events and doesn't expect a duplicate NPC to be the
  one involved. Confirming this precisely would mean reading quest state
  via `GetLocalPlayerQuestState` before spawning/giving, but that takes
  an out-parameter whose UE4SS Lua calling convention is unverified -
  another real crash risk to test blind. Decided to document this as a
  known limitation instead of chasing it further: these three events
  require having completed the early tutorial content involving Doric/
  Vannaka/the Wise Old Man on the character being tested with.
- Re-added the 12 Tier1 skill tomes to `Config.MysteriousOldManGiftPool`
  and Strong Tea to `Config.DrunkenDwarfGifts`. Both were pulled during
  testing on suspicion of being bad items/paths, but the real cause of
  those crashes was the `GameplayTagContainer` argument bug (fixed with
  `nil`), not the items themselves - so there's no longer a reason to
  think they're broken specifically.
- Confirmed everything works end to end (on a tutorial-complete
  character): both events' full gift lists, tomes and Strong Tea
  included.
- Disabled the native "Press E to interact" prompt on spawned NPCs
  (`InteractionComponent:SetActive(false, false)` in `Encounter.Run`,
  the same call tried earlier for a different reason and reverted) -
  now genuinely dead weight since `F` is the real interaction, it just
  opened the stock dialogue with no useful effect. Only touches the
  actor we just spawned, never the real NPC.
- Added a fourth event: Zanik, spawning Dragonwilds' own Zanik NPC
  (`Config.ZanikClassPath`, found via the discovery tool). Line: "Ooh, a
  friendly face! I've got runes falling out of my pockets - here, take
  some, they're no good to me if I can't carry them!" - no closing line,
  matching Drunken Dwarf/Vannaka's pattern. Gift is 100x of one randomly
  picked rune (Air/Fire/Earth/Water/Law/Cosmic/Astral) from
  `Config.ZanikRuneTable`, via a new `pickOne` helper in `events.lua`
  (also used to simplify Mysterious Old Man's existing gift-pool pick).
  Rune paths for Air/Fire/Earth/Water/Law/Astral confirmed from the
  object dump; Cosmic wasn't loaded when searched, so its path is
  inferred from the other six's identical naming pattern (same situation
  Strong Tea was in earlier, which turned out fine). Confirmed via the
  header dump that `UMagicAmmoData` (Air/Water/Fire's class) still
  inherits down to `UItemData`, so it's a valid `AddItemByData` target
  despite not being a plain `UItemData`/`BP_Consumables_*` type. Added to
  the cleanup hotkey's `CleanupNamed`/`CleanupNearest` passes alongside
  the other three events. Not yet tested in-game.
- Attempted a fix for spawned NPCs appearing half-embedded in world
  geometry (reported: Vannaka's lower half stuck inside a crate) by
  changing `BeginDeferredActorSpawnFromClass`'s `CollisionHandlingOverride`
  from `0` (Undefined) to `2` (`AdjustIfPossibleButAlwaysSpawn`), to nudge
  the spawn point clear of nearby props. This was the wrong diagnosis -
  see below - but the change itself is harmless (still a reasonable
  collision-handling default) and was left in.
- Found the real cause: not world geometry at all - the crate/box
  appears "no matter where he spawns" because it's baked into Vannaka's
  own Blueprint. Confirmed via a fresh SDK dump (`/`) taken while the bug
  was visible plus the class's `CXXHeaderDump/BP_NPC_Vannaka_FTUE.hpp`:
  the class has its own `UStaticMeshComponent* StaticMesh` variable,
  entirely separate from the actual skeletal mesh, attached at a fixed
  offset relative to the actor root. Checked the other two working NPCs'
  headers too - both have the identical pattern (Wise Old Man:
  `StaticMesh_0`; Doric: `ReplacementMeshComponent1`, a name that all but
  confirms it's a placeholder/stand-in prop). The level's hand-placed
  instance evidently hides or repositions this somehow that our runtime
  spawn doesn't replicate. Added `Config.<Event>PlaceholderMeshProp`
  entries naming each class's component property, and
  `trySpawnNearPlayer` now hides that component (`SetVisibility(false,
  false)`) right after spawning, for whichever events have a confirmed
  property name. Zanik's is left `nil` (unconfirmed - not yet spawned
  in-game to dump its header). Not yet retested in-game.
