-- Event registry: each entry is
--   { id, weight, cooldownMs, run = function(ctx) ... end }
-- `weight` controls relative pick frequency (raw weight / total weight).
-- `cooldownMs` is a per-event cooldown on top of the global one in
-- config.lua, so a single event can't fire twice in a row even on a lucky
-- streak of rolls. `ctx` is built by main.lua and passed to `run`.
local UEHelpers = require("UEHelpers")
local Encounter = require("encounter")

local Events = {}

local function isValid(o)
    return o and o.IsValid and o:IsValid()
end

-- Rolls `lootTable` twice, with replacement (the same entry can come up
-- both times), for Vannaka's "mob loot" gift.
local function rollTwice(lootTable)
    if not lootTable or #lootTable == 0 then return {} end
    return {
        lootTable[math.random(1, #lootTable)],
        lootTable[math.random(1, #lootTable)],
    }
end

-- Picks one random entry from `pool`, for Zanik's "one random rune" gift
-- and Mysterious Old Man's gift pool.
local function pickOne(pool)
    if not pool or #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

-- Traces straight down (from well above `z` to well below it) at (x, y)
-- and returns the hit location's Z, or nil if the trace found no ground.
-- Used by trySpawnNearPlayer to fix spawns landing half-buried or
-- floating: BeginDeferredActorSpawnFromClass's own
-- AdjustIfPossibleButAlwaysSpawn collision handling only nudges a spawn
-- to clear overlapping geometry at the Z it's given - it never adjusts
-- for terrain height, which is why just reusing the player's own Z
-- (previously the entirety of the spawn Z logic) broke down on any slope
-- where the ground height at the offset spawn point differs from the
-- ground height under the player.
--
-- LineTraceSingle takes an FHitResult& out-parameter. Confirmed in-game
-- that passing `nil` for it is wrong - UE4SS's real convention for an
-- `Out` struct parameter is to pass an actual (empty) table, which the
-- call then fills in place; `nil` errored with "Tried storing reference
-- to a Lua table for an 'Out' parameter... but no table was on the
-- stack." Trace channel 0 is still a guess (Visibility, the common
-- default in a fresh UE project).
--
-- `ignoreActor`, if given, is excluded from the trace via ActorsToIgnore.
-- Needed for the player's own trace below: the trace starts 500 units
-- straight above the traced point, which for the player's own (x, y) is
-- directly in line with their own capsule/mesh - without this, the
-- "ground" it finds is most likely the top of the player's own head, not
-- the actual ground beneath them. Confirmed in-game to matter: without
-- it, spawns ended up sunk almost entirely underground (only heads
-- visible), consistent with the learned "height above ground" offset in
-- trySpawnNearPlayer coming out far too small (or negative) because
-- "player ground" was really "top of the player."
local function traceGroundZ(world, ksl, x, y, z, ignoreActor)
    local start = { X = x, Y = y, Z = z + 500.0 }
    local finish = { X = x, Y = y, Z = z - 2000.0 }
    local outHit = {}
    local ignoreList = ignoreActor and { ignoreActor } or {}
    local ok, hit = pcall(function()
        return ksl:LineTraceSingle(world, start, finish, 0, false, ignoreList, 0, outHit, false, {}, {}, 0.0)
    end)
    if not ok then
        return nil, "LineTraceSingle failed: " .. tostring(hit)
    end
    if not hit then
        return nil, "no ground hit"
    end
    local hitLoc = outHit.Location
    if not hitLoc then
        return nil, "hit result had no Location"
    end
    return hitLoc.Z, nil
end

-- Spawns an actor of `classPath` a few meters in front of the player.
-- Shared by every spawn-capable event, gated by the caller on
-- Config.EnableExperimentalSpawns - see README "Filling in a spawn target"
-- for how classPath values are found. `placeholderMeshProp`, if given, is
-- the name of a UStaticMeshComponent variable on the class to hide right
-- after spawning - see config.lua's *PlaceholderMeshProp comment for why
-- (a baked-in placeholder prop, separate from the real skeletal mesh, that
-- otherwise renders as a box wherever the NPC spawns).
local function trySpawnNearPlayer(ctx, classPath, logPrefix, placeholderMeshProp)
    local ok_pc, pc = pcall(UEHelpers.GetPlayerController)
    if not ok_pc or not isValid(pc) then return end
    local ok_pawn, pawn = pcall(function() return pc.Pawn end)
    if not ok_pawn or not isValid(pawn) then return end

    local ok_loc, loc = pcall(function() return pawn:K2_GetActorLocation() end)
    if not ok_loc or not loc then return end

    -- StaticFindObject only finds objects already resident in memory - it
    -- doesn't load anything. The NPC classes here are normally only loaded
    -- while their placed instance's streaming level is nearby, so without
    -- this they resolve fine right next to that NPC (which is how the
    -- discovery tool found them) but fail everywhere else. LoadAsset forces
    -- the package to load first, matching UE4SS's own bundled "summon"
    -- console command (ConsoleCommandsMod/Scripts/summon_unloaded_assets.lua).
    pcall(LoadAsset, classPath)

    local spawnClass = StaticFindObject(classPath)
    if not isValid(spawnClass) then
        ctx.log(logPrefix .. ": class path did not resolve to a class even after LoadAsset: " .. tostring(classPath))
        return
    end

    local world = UEHelpers.GetWorld()
    if not isValid(world) then return end

    -- Offset a few meters from the player in a random direction, rather
    -- than always the same fixed diagonal - multiple events force-triggered
    -- in quick succession (e.g. mashing the test hotkey) would otherwise
    -- all land in the exact same spot on top of each other.
    local angle = math.random() * 2 * math.pi
    local offsetDist = 300.0
    local spawnX, spawnY = loc.X + offsetDist * math.cos(angle), loc.Y + offsetDist * math.sin(angle)

    -- Ground-snap: reusing the player's own Z verbatim (the entire spawn
    -- Z logic before this) only looks right on flat ground, since the
    -- offset point can sit at a different terrain height than the player
    -- on any slope or ledge. Trace the ground under the player and under
    -- the offset point, and apply the same "height above ground" the
    -- player has to the spawn point - this should hold regardless of
    -- whether an actor's own location pivot is at its feet or its
    -- capsule center, since it's learned from the player's own actor
    -- rather than assumed as a fixed number. Falls back to the player's
    -- raw Z (old behavior) if either trace fails.
    local spawnZ = loc.Z
    local ok_ksl, ksl = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    end)
    if ok_ksl and isValid(ksl) then
        local playerGroundZ, playerErr = traceGroundZ(world, ksl, loc.X, loc.Y, loc.Z, pawn)
        local spawnGroundZ, spawnErr = traceGroundZ(world, ksl, spawnX, spawnY, loc.Z)
        if playerGroundZ and spawnGroundZ then
            spawnZ = spawnGroundZ + (loc.Z - playerGroundZ)
            ctx.log(logPrefix .. ": ground-snapped spawn Z (player Z " .. tostring(loc.Z) ..
                ", player ground " .. tostring(playerGroundZ) ..
                ", spawn ground " .. tostring(spawnGroundZ) .. ", final spawn Z " .. tostring(spawnZ) .. ")")
        else
            ctx.log(logPrefix .. ": ground trace incomplete (player: " .. tostring(playerErr) ..
                ", spawn: " .. tostring(spawnErr) .. ") - using player's own Z")
        end
    else
        ctx.log(logPrefix .. ": KismetSystemLibrary CDO not found - using player's own Z")
    end

    local spawnLoc = { X = spawnX, Y = spawnY, Z = spawnZ }
    local spawnRot = { Yaw = 0, Pitch = 0, Roll = 0 }
    local spawnScale = { X = 1, Y = 1, Z = 1 }

    local ok_gsl, gsl = pcall(function()
        return StaticFindObject("/Script/Engine.Default__GameplayStatics")
    end)
    if not ok_gsl or not isValid(gsl) then
        ctx.log(logPrefix .. ": GameplayStatics CDO not found, cannot spawn")
        return
    end

    -- Both UFUNCTIONs take a trailing ESpawnActorScaleMethod on this UE5
    -- version (0 = its default, SelectDefaultAtRuntime) that older
    -- UE4-era signatures didn't have - confirmed against an independent
    -- UE4SS Lua SDK for another UE5 game (Borderlands 4) hitting the same
    -- signatures. Omitting it fails with "UFunction expected 6/3
    -- parameters, received 5/2".
    --
    -- CollisionHandlingOverride (the param right before it) is
    -- ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn (2),
    -- not Undefined (0, "use the class's own default"). These NPC classes
    -- are normally hand-placed by a level designer, never spawned at
    -- runtime, so their own default is most likely AlwaysSpawn with no
    -- adjustment at all - fine for a curated placement, but a random
    -- offset from the player can land inside world geometry (a crate, a
    -- rock), spawning the NPC half-embedded in it. AdjustIfPossibleButAlwaysSpawn
    -- asks the engine to nudge the spawn location clear of collisions
    -- first, still spawning even if it can't fully clear.
    local ok_spawn, actor = pcall(function()
        return gsl:BeginDeferredActorSpawnFromClass(world, spawnClass,
            { Translation = spawnLoc, Rotation = spawnRot, Scale3D = spawnScale }, 2, nil, 0)
    end)
    if not ok_spawn or not isValid(actor) then
        ctx.log(logPrefix .. ": BeginDeferredActorSpawnFromClass failed: " .. tostring(actor))
        return nil
    end
    pcall(function()
        gsl:FinishSpawningActor(actor, { Translation = spawnLoc, Rotation = spawnRot, Scale3D = spawnScale }, 0)
    end)

    -- These NPC classes are normally hand-placed by a level designer and
    -- never moved again, so their RootComponent's Mobility is most likely
    -- Static - confirmed in-game: encounter.lua's continuous face-the-
    -- player rotation was calling K2_SetActorRotation successfully (no
    -- Lua error) every poll tick, but it returned false every time and a
    -- readback showed the rotation never actually changed from spawn -
    -- the classic signature of a Static component silently refusing a
    -- runtime move, by Unreal's own design (only Movable components can
    -- be moved/rotated after BeginPlay). SetMobility(Movable) on our
    -- spawned copy's RootComponent only, right after spawning - never
    -- touches the real, level-placed instance.
    local ok_mobility, err_mobility = pcall(function()
        actor.RootComponent:SetMobility(2) -- EComponentMobility::Movable
    end)
    ctx.log(logPrefix .. ": SetMobility(Movable) on RootComponent " ..
        (ok_mobility and "succeeded" or ("failed: " .. tostring(err_mobility))))

    local function hideComponent(propName)
        local ok_hide, err = pcall(function()
            local comp = actor[propName]
            if isValid(comp) then
                comp:SetVisibility(false, false)
            end
        end)
        if ok_hide then
            ctx.log(logPrefix .. ": hid placeholder mesh component '" .. propName .. "'")
        else
            ctx.log(logPrefix .. ": failed to hide placeholder mesh component '" .. propName .. "': " .. tostring(err))
        end
    end

    -- AInteractableNPC (the native base class every one of these four
    -- spawn targets ultimately derives from, confirmed via
    -- CXXHeaderDump/Dominion.hpp) has its own UStaticMeshComponent*
    -- ReplacementMesh, separate from whatever extra placeholder mesh
    -- property each Blueprint subclass adds on top (StaticMesh_0,
    -- ReplacementMeshComponent1, or plain StaticMesh - see each
    -- CXXHeaderDump/<class>.hpp). Always attempted for every spawn,
    -- regardless of placeholderMeshProp: for Vannaka/Zanik, hiding just
    -- their own subclass-level StaticMesh was confirmed in-game to not
    -- actually stop the box appearing at their legs, so it's most likely
    -- this shared base-class component, not their subclass's, that's the
    -- real box.
    hideComponent("ReplacementMesh")

    if placeholderMeshProp then
        hideComponent(placeholderMeshProp)
    end

    return actor
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- Mysterious Old Man: the one event that (optionally) spawns an existing
-- Dragonwilds NPC rather than just showing a toast. Gated behind
-- Config.EnableExperimentalSpawns + Config.MysteriousOldManClassPath -
-- found via the discovery tool (.) as Dragonwilds' own "Wise Old Man"
-- tutorial NPC (BP_NPC_WiseOldMan_FTUE), a strong thematic match. The
-- _FTUE suffix means it's normally a singleton tutorial character, so
-- spawning a duplicate is unproven - hence still opt-in, not on by
-- default. With spawning disabled/unconfigured this still fires as a
-- toast. See README "Filling in a spawn target".
table.insert(Events, {
    id = "mysterious_old_man",
    weight = 3,
    cooldownMs = 10 * 60000,
    run = function(ctx)
        ctx.notify("A Random Event Has Spawned!", "Press F to interact with them.")

        if ctx.config.EnableExperimentalSpawns and ctx.config.MysteriousOldManClassPath then
            local actor = trySpawnNearPlayer(ctx, ctx.config.MysteriousOldManClassPath, "mysterious_old_man", ctx.config.MysteriousOldManPlaceholderMeshProp)
            if actor then
                local gift = pickOne(ctx.config.MysteriousOldManGiftPool)
                Encounter.Run(ctx, actor, {
                    displayName = "The Mysterious Old Man",
                    line1 = ctx.config.MysteriousOldManLine1,
                    line2 = ctx.config.MysteriousOldManLine2,
                    gifts = gift and { gift } or {},
                })
            end
        end
    end,
})

-- Drunken Dwarf: spawns Dragonwilds' Doric NPC (a dwarf, per OSRS lore),
-- found via the discovery tool (.) as BP_NPC_Doric_FTUE. Same _FTUE caveat
-- as Mysterious Old Man above - normally a singleton tutorial character,
-- so spawning a duplicate is unproven - hence still opt-in. With spawning
-- disabled/unconfigured this still fires as a toast.
table.insert(Events, {
    id = "drunken_dwarf",
    weight = 2,
    cooldownMs = 12 * 60000,
    run = function(ctx)
        ctx.notify("A Random Event Has Spawned!", "Press F to interact with them.")

        if ctx.config.EnableExperimentalSpawns and ctx.config.DrunkenDwarfClassPath then
            local actor = trySpawnNearPlayer(ctx, ctx.config.DrunkenDwarfClassPath, "drunken_dwarf", ctx.config.DrunkenDwarfPlaceholderMeshProp)
            if actor then
                Encounter.Run(ctx, actor, {
                    displayName = "Drunken Dwarf",
                    line1 = ctx.config.DrunkenDwarfLine1,
                    line2 = ctx.config.DrunkenDwarfLine2,
                    gifts = ctx.config.DrunkenDwarfGifts or {},
                })
            end
        end
    end,
})

-- Vannaka: spawns Dragonwilds' own Vannaka NPC, found via the discovery
-- tool (.) as BP_NPC_Vannaka_FTUE. Same _FTUE caveat as the others above -
-- normally a singleton tutorial character, so spawning a duplicate is
-- unproven - hence still opt-in. With spawning disabled/unconfigured this
-- still fires as a toast. Vannaka's a slayer master in OSRS, so his gift
-- is "mob loot" rather than food/potions/tomes - two rolls (with
-- replacement) on Config.VannakaLootTable.
table.insert(Events, {
    id = "vannaka",
    weight = 3,
    cooldownMs = 10 * 60000,
    run = function(ctx)
        ctx.notify("A Random Event Has Spawned!", "Press F to interact with them.")

        if ctx.config.EnableExperimentalSpawns and ctx.config.VannakaClassPath then
            local actor = trySpawnNearPlayer(ctx, ctx.config.VannakaClassPath, "vannaka", ctx.config.VannakaPlaceholderMeshProp)
            if actor then
                Encounter.Run(ctx, actor, {
                    displayName = "Vannaka",
                    line1 = ctx.config.VannakaLine1,
                    line2 = ctx.config.VannakaLine2,
                    gifts = rollTwice(ctx.config.VannakaLootTable),
                })
            end
        end
    end,
})

-- Zanik: spawns Dragonwilds' own Zanik NPC, found via the discovery tool
-- (.) as BP_NPC_Zanik_FTUE. Same _FTUE caveat as the others above -
-- normally a singleton tutorial character, so spawning a duplicate is
-- unproven - hence still opt-in. With spawning disabled/unconfigured this
-- still fires as a toast. Zanik's a runecrafting NPC here, so his gift is
-- 100x of one random rune from Config.ZanikRuneTable.
table.insert(Events, {
    id = "zanik",
    weight = 3,
    cooldownMs = 10 * 60000,
    run = function(ctx)
        ctx.notify("A Random Event Has Spawned!", "Press F to interact with them.")

        if ctx.config.EnableExperimentalSpawns and ctx.config.ZanikClassPath then
            local actor = trySpawnNearPlayer(ctx, ctx.config.ZanikClassPath, "zanik", ctx.config.ZanikPlaceholderMeshProp)
            if actor then
                local rune = pickOne(ctx.config.ZanikRuneTable)
                Encounter.Run(ctx, actor, {
                    displayName = "Zanik",
                    line1 = ctx.config.ZanikLine1,
                    line2 = ctx.config.ZanikLine2,
                    gifts = rune and { rune } or {},
                })
            end
        end
    end,
})

return Events
