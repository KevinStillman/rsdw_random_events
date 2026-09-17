local Config = {}

Config.Version = "0.1.0"

-- ---------------------------------------------------------------------------
-- Trigger loop
-- ---------------------------------------------------------------------------
-- Every CheckIntervalMs, roll TriggerChance. On a hit, pick a weighted-random
-- event, provided GlobalCooldownMs has elapsed since the last event fired.
-- Mean gap between events ~= CheckIntervalMs / TriggerChance (default: ~8 min).
Config.CheckIntervalMs = 60000
Config.TriggerChance = 0.12
Config.GlobalCooldownMs = 180000

-- ---------------------------------------------------------------------------
-- Hotkeys
-- ---------------------------------------------------------------------------
-- RegisterKeyBind takes a numeric virtual-key code, not a string - Key is a
-- global table UE4SS injects into every mod's Lua environment (see
-- assets/Mods/shared/Types.lua in the UE4SS repo for the full list).
Config.HotkeyForceTrigger = Key.OEM_COMMA  -- ',' - fire a random event immediately, ignoring cooldowns
Config.HotkeyForceTriggerLabel = ","
Config.HotkeyDiscovery = Key.OEM_PERIOD    -- '.' - log nearby actor class paths + player location
Config.HotkeyDiscoveryLabel = "."
Config.HotkeyDump = Key.OEM_TWO            -- '/' - dump SDK headers + live object properties (dev tool)
Config.HotkeyDumpLabel = "/"
Config.HotkeyCleanup = Key.OEM_FOUR        -- '[' - destroy any orphaned renamed spawns (dev tool)
Config.HotkeyCleanupLabel = "["
Config.HotkeyEncounterInteract = Key.F     -- 'F' - trigger a nearby event NPC's encounter
Config.HotkeyEncounterInteractLabel = "F"

Config.Debug = true -- verbose logging to UE4SS.log

-- ---------------------------------------------------------------------------
-- Toast notification UI
-- ---------------------------------------------------------------------------
Config.ToastDurationMs = 7000
Config.ToastX = 0.5  -- fraction of viewport width, anchored center
Config.ToastY = 0.14 -- fraction of viewport height from the top
Config.ToastWidth = 520
Config.ToastPadding = 14
Config.ToastBackgroundColor = { R = 0.05, G = 0.05, B = 0.08, A = 0.85 }
Config.ToastTitleColor = { R = 1.0, G = 0.82, B = 0.2, A = 1.0 }
Config.ToastBodyColor = { R = 0.92, G = 0.92, B = 0.92, A = 1.0 }
Config.ToastTitleFontSize = 20
Config.ToastBodyFontSize = 16

-- ---------------------------------------------------------------------------
-- "Press F for Random Event" prompt UI (Scripts/prompt.lua)
-- ---------------------------------------------------------------------------
Config.PromptX = 0.5  -- fraction of viewport width, anchored center
Config.PromptY = 0.72 -- fraction of viewport height from the top - above the
                       -- usual crosshair/interact-prompt area, not overlapping it
Config.PromptWidth = 360
Config.PromptPadding = 10
Config.PromptBackgroundColor = { R = 0.05, G = 0.05, B = 0.08, A = 0.85 }
Config.PromptTextColor = { R = 1.0, G = 0.82, B = 0.2, A = 1.0 }
Config.PromptFontSize = 18

-- ---------------------------------------------------------------------------
-- Discovery tool
-- ---------------------------------------------------------------------------
Config.DiscoveryRadius = 2000.0 -- UE units (~20m) around the player to scan

-- ---------------------------------------------------------------------------
-- Experimental: NPC-spawn events
-- ---------------------------------------------------------------------------
-- Off by default even though both class paths below are now real (found
-- via the discovery tool, .) - both are Dragonwilds' own tutorial NPCs
-- (the "_FTUE" suffix), normally singleton story characters, so spawning a
-- duplicate elsewhere in the world is unproven and could trip dialogue or
-- quest-tracking logic that assumes only one exists. Flip this to true to
-- actually test it - see README "Filling in a spawn target".
Config.EnableExperimentalSpawns = true
Config.MysteriousOldManClassPath = "/Game/Gameplay/NPCs/BP_NPC_WiseOldMan_FTUE.BP_NPC_WiseOldMan_FTUE_C"
Config.DrunkenDwarfClassPath = "/Game/Gameplay/NPCs/BP_NPC_Doric_FTUE.BP_NPC_Doric_FTUE_C" -- Doric is a dwarf
Config.VannakaClassPath = "/Game/Gameplay/NPCs/BP_NPC_Vannaka_FTUE.BP_NPC_Vannaka_FTUE_C" -- Vannaka is a slayer master
Config.ZanikClassPath = "/Game/Gameplay/NPCs/BP_NPC_Zanik_FTUE.BP_NPC_Zanik_FTUE_C" -- Zanik is a runecrafting NPC here

-- Each of these _FTUE Blueprints carries its own extra UStaticMeshComponent
-- variable, separate from the actual skeletal mesh - confirmed via the
-- CXXHeaderDump (/): a plain placeholder/stand-in prop (Doric's is even
-- named "ReplacementMeshComponent1") attached at a fixed offset relative to
-- the actor. The level's hand-placed instance evidently hides or
-- repositions it somehow; our runtime spawn doesn't replicate whatever
-- does that, so it renders as a box wherever the NPC is spawned (reported:
-- Vannaka standing on/inside a crate no matter where he appears).
-- trySpawnNearPlayer hides the named component, if any, right after spawn.
-- Property name found per-class from CXXHeaderDump/<class>.hpp - nil means
-- not yet confirmed (class not dumped, e.g. Zanik hasn't been spawned in-game).
Config.MysteriousOldManPlaceholderMeshProp = "StaticMesh_0"
Config.DrunkenDwarfPlaceholderMeshProp = "ReplacementMeshComponent1"
Config.VannakaPlaceholderMeshProp = "StaticMesh"
Config.ZanikPlaceholderMeshProp = nil

-- ---------------------------------------------------------------------------
-- Scripted encounters: custom name/dialogue/item-giving for the spawned
-- NPCs, layered on top of the spawn above. Found via the SDK dump (/):
-- AWorldActor.DisplayName (FText) renames the world nameplate, and
-- UInventoryComponent:AddItemByData gives an item directly to the player's
-- inventory. Triggered by a dedicated hotkey (Config.HotkeyEncounterInteract)
-- while in range, not the game's own interact button - three different
-- native hook points that looked like plausible ways to react to the real
-- "talk" interaction were all confirmed in-game to never fire for these
-- NPCs, so a separate key sidesteps the problem entirely. See README
-- "Custom dialogue and item-giving".
-- ---------------------------------------------------------------------------
Config.EncounterRadius = 250.0        -- UE units (~2.5m) - shows the prompt / lets F trigger the encounter
Config.EncounterMaxWaitMs = 120000    -- despawn quietly if nobody presses F within this long
Config.EncounterGiveDelayMs = 3000    -- delay between line1 and giving the item(s)
Config.EncounterDespawnDelayMs = 2500 -- delay between giving the item(s)/line2 and despawning

-- ---------------------------------------------------------------------------
-- EXPERIMENTAL: world-drop gifts instead of straight-to-inventory
-- ---------------------------------------------------------------------------
-- The tome crash (see encounter.lua's giveItem and CHANGELOG.md) never got a
-- real root cause - it's an engine-level death with no catchable Lua error
-- and no crash dump anywhere, and a 2026-09-17 session ruled out both of the
-- two leading theories (a broken concept-art icon reference; the player's
-- Mining skill being untrained). AddItemByData is a generic
-- straight-into-inventory path; ItemHelperLibrary:SpawnAndLaunchItem_Sync
-- (found via the SDK dump, /Script/Dominion.ItemHelperLibrary) is what
-- actually drops a physical pickup into the world instead - the same
-- mechanism behind ordinary loot/resource drops, so presumably far more
-- battle-tested than shoving an item into inventory data from a class that
-- was probably never meant to be handed out that way. Set true to route
-- Encounter gifts through Encounter.dropItem (spawns the item on the ground
-- at the NPC's feet) instead of Encounter.giveItem (AddItemByData straight
-- to inventory). Untested in-game as of this writing - see dropItem's
-- comments for the specific unknowns (Transform/FVector marshaling,
-- WorldContextObject choice). Default false: this is a branch for exploring
-- the idea, not yet something to ship on by default.
Config.GiveItemsAsWorldDrops = false
-- The base "drop a single ItemData as a physical pickup" class - other
-- variants exist (BP_RuntimeSpawnedWorldItem_NoExpiry/_NoDelayForMagnet/
-- _ProcessingStation) but this is the plain one, matching "drop it on the
-- ground" rather than anything fancier.
Config.WorldItemDropClassPath = "/Game/Gameplay/WorldItems/BP_RuntimeSpawnedWorldItem.BP_RuntimeSpawnedWorldItem_C"
Config.ItemDropLaunchSpeed = 0.0          -- 0 = just place it, no toss/pop away from the spawn point
Config.ItemDropLaunchAngleVariance = 0.0

Config.MysteriousOldManLine1 = "Ah, so you are there. I hoped you would talk to me, I get so lonely. Here, have a present! I must be going now though."
Config.MysteriousOldManLine2 = "Enjoy!"
-- One entry is picked at random as the "present". Each entry is either a
-- plain asset-path string (gives 1) or a { path = "...", count = N }
-- table (gives N) - found by searching ue4ss/UE4SS_ObjectDump.txt (via
-- the / dev-tool dump) for the item's in-game name, same as
-- DrunkenDwarfGifts below.
--
-- Antipoison Potion: 4 tiers exist (Weak/T1, Lesser/T2, plain T3, Super/T4)
-- - T3 is the one with no tier-word in its name, so that's "Antipoison
-- Potion" unqualified.
--
-- Tomes: one per skill, Tier1 only (Tier2 exists too but isn't included
-- here). Excludes the "Tier0" tomes (DragonSlayerQuest, DeathQuestMain,
-- and others not currently loaded, likely including Undying/Titan) -
-- those are quest/lore items, not skill-XP tomes, and use a different
-- naming scheme (Tier0 vs Tier1/Tier2) that's easy to tell apart.
--
-- Re-added after initially being pulled for crashing: the real cause
-- turned out to be the GameplayTagContainer argument passed to
-- AddItemByData (a bare {} instead of nil - see encounter.lua's
-- giveItem), not the tomes themselves, and that's now fixed. If a tome
-- still crashes, note it's more likely the pre-tutorial-character
-- limitation (see README "Custom dialogue and item-giving") than the
-- tome itself, given every other item type has worked fine since the
-- nil fix.
Config.MysteriousOldManGiftPool = {
    { path = "/Game/Gameplay/Items/Consumables/Magic/ITEM_Consumable_Potion_T3_Antipoison.ITEM_Consumable_Potion_T3_Antipoison", count = 2 },
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Attack.ITEM_Consumable_Tome_Tier1_Attack",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Magic.ITEM_Consumable_Tome_Tier1_Magic",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Ranged.ITEM_Consumable_Tome_Tier1_Ranged",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Woodcutting.ITEM_Consumable_Tome_Tier1_Woodcutting",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Mining.ITEM_Consumable_Tome_Tier1_Mining",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Farming.ITEM_Consumable_Tome_Tier1_Farming",
    "/Fishing/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Fishing.ITEM_Consumable_Tome_Tier1_Fishing",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Runecrafting.ITEM_Consumable_Tome_Tier1_Runecrafting",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Construction.ITEM_Consumable_Tome_Tier1_Construction",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Artisan.ITEM_Consumable_Tome_Tier1_Artisan",
    "/Game/Gameplay/Items/Consumables/Tomes/ITEM_Consumable_Tome_Tier1_Cooking.ITEM_Consumable_Tome_Tier1_Cooking",
    "/Agility/Gameplay/Items/Tomes/ITEM_Consumable_Tome_Tier1_Agility.ITEM_Consumable_Tome_Tier1_Agility",
}

Config.DrunkenDwarfLine1 = "I 'new it were you matey! 'Ere, have some ob the good stuff!"
Config.DrunkenDwarfLine2 = nil -- no closing line specified - just gives the items and disappears
-- Umbral Kebab confirmed via the object dump and rock-solid across many
-- in-game trials. Strong Tea's path is inferred from a sibling recipe
-- asset's naming pattern (its own item package wasn't loaded when first
-- searched), not directly confirmed - it was pulled after crashing, but
-- that turned out to be the GameplayTagContainer argument bug (see
-- MysteriousOldManGiftPool's comment above), not this path being wrong,
-- so it's back in. If it still fails, ctx.log will say so, and the fix
-- is to craft/view a Strong Tea in-game once (loads its actual asset),
-- press / to dump again, and search ue4ss/UE4SS_ObjectDump.txt for
-- "Strong" or "Tea" the same way Umbral Kebab's path was found.
Config.DrunkenDwarfGifts = {
    "/UmbralSands/Gameplay/Items/Resources/Consumable/ITEM_Consumable_Tea_Strong.ITEM_Consumable_Tea_Strong",
    "/UmbralSands/Gameplay/Items/Resources/Consumable/ITEM_Consumable_Umbral_Kebab.ITEM_Consumable_Umbral_Kebab",
}

Config.VannakaLine1 = "Finally, an adventurer! My inventory is too full, please take these.."
Config.VannakaLine2 = nil -- no closing line specified - just gives the loot and disappears
-- events.lua rolls this table twice (with replacement - the same entry
-- can come up both times) for Vannaka's "mob loot" gift, each roll giving
-- 3 of whichever item it lands on. "Fleece" and "Animal Hide Scraps" are
-- internally named Skin_Fleece/Skin_Scraps - both live in the same
-- "Materials_Basic" journal category as their requested names, which is
-- what ties the two together despite the differing wording.
Config.VannakaLootTable = {
    { path = "/Game/Gameplay/Items/Resources/Animal/ITEM_Resources_Skin_Fleece.ITEM_Resources_Skin_Fleece", count = 3 },
    { path = "/Game/Gameplay/Items/Resources/Animal/ITEM_Resources_Coarse_Animal_Fur.ITEM_Resources_Coarse_Animal_Fur", count = 3 },
    { path = "/Game/Gameplay/Items/Resources/Animal/ITEM_Resources_Skin_Scraps.ITEM_Resources_Skin_Scraps", count = 3 },
    { path = "/Game/Gameplay/Items/Resources/Animal/ITEM_Resources_Meat_Farm.ITEM_Resources_Meat_Farm", count = 3 },
    { path = "/Game/Gameplay/Items/Resources/Animal/ITEM_Resources_Animal_Hide.ITEM_Resources_Animal_Hide", count = 3 },
}

Config.ZanikLine1 = "Ooh, a friendly face! I've got runes falling out of my pockets - here, take some, they're no good to me if I can't carry them!"
Config.ZanikLine2 = nil -- no closing line specified - just gives the runes and disappears
-- events.lua picks ONE of these at random for Zanik's "100x a random
-- rune" gift. All live under /Game/Gameplay/Items/Resources/Magic/ as
-- ITEM_Rune_<Name> - Air/Water/Fire are class UMagicAmmoData rather than
-- plain UItemData, but UMagicAmmoData -> UAmmoData -> UEquipmentData ->
-- UItemData, so they're still valid AddItemByData targets. Cosmic wasn't
-- currently loaded when searched (same situation Strong Tea was in), so
-- its path is inferred from the other 6's identical naming pattern, not
-- directly confirmed.
Config.ZanikRuneTable = {
    { path = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Air.ITEM_Rune_Air", count = 100 },
    { path = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Fire.ITEM_Rune_Fire", count = 100 },
    { path = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Earth.ITEM_Rune_Earth", count = 100 },
    { path = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Water.ITEM_Rune_Water", count = 100 },
    { path = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Law.ITEM_Rune_Law", count = 100 },
    { path = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Cosmic.ITEM_Rune_Cosmic", count = 100 },
    { path = "/Game/Gameplay/Items/Resources/Magic/ITEM_Rune_Astral.ITEM_Rune_Astral", count = 100 },
}

return Config
