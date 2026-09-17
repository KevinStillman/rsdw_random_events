-- Runs a scripted "encounter" on an already-spawned NPC actor: renames
-- it, disables its native "Press E to interact" prompt (dead weight now -
-- it only opens the stock tutorial dialogue, which does nothing useful
-- here), shows a "Press F for Random Event" prompt while the player is
-- nearby, and on that keypress plays out a line, gives item(s), an
-- optional second line, and despawns.
--
-- F is a dedicated key rather than the real interact button because
-- intercepting the latter turned out not to be reliably possible:
-- UE4SS's RegisterHook doesn't support delegate functions (which is what
-- the NPC's own OnInteraction handling is), and three different native
-- functions that looked like plausible "a conversation is starting" hook
-- points (PlayerConversationComponent:Server_StartConversation,
-- AsyncAction_DomStartConversation:AsyncDomStartConversation,
-- PlayerConversationComponent:SetupEnterConversationOnMapClosed) were all
-- confirmed in-game to never fire for these FTUE tutorial NPCs at all.
-- See README "Custom dialogue and item-giving".
local UEHelpers = require("UEHelpers")
local Prompt = require("prompt")

local Encounter = {}

local function log(msg)
    print("[RSDWRandomEvents] " .. msg .. "\n")
end

local function isValid(o)
    return o and o.IsValid and o:IsValid()
end

local function distance(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Defers registering a delayed LoopAsync by one tick before doing so.
-- Registering two LoopAsync callbacks back-to-back in the same call stack
-- has been observed elsewhere in this UE4SS build family to crash with a
-- heap-corruption fault (see DragonwildsHUD's README) - this is cheap
-- insurance against that whenever we schedule a new timer from inside an
-- existing LoopAsync/ExecuteInGameThread/hotkey callback.
local function scheduleAfter(delayMs, fn)
    LoopAsync(1, function()
        LoopAsync(delayMs, function()
            fn()
            return true
        end)
        return true
    end)
end

-- LoadAsset forces the package to load before StaticFindObject can find
-- it (see trySpawnNearPlayer in events.lua for the full explanation).
local function resolveAsset(path)
    pcall(LoadAsset, path)
    local obj = StaticFindObject(path)
    if isValid(obj) then return obj end
    return nil
end

-- `gift` is either a plain asset-path string (gives 1) or a
-- { path = "...", count = N } table (gives N) - see
-- Config.MysteriousOldManGiftPool for examples of both forms. N is given
-- as N separate Count=1 calls rather than one Count=N call: the game
-- crashed outright (no catchable Lua error at all - an engine-level
-- crash) the one time a Count=2 call was attempted, while plain Count=1
-- calls had already worked reliably several times before that, so this
-- sidesteps whatever that was rather than risk it again. Logs the gift
-- being attempted *before* calling AddItemByData, so if it crashes again
-- the log at least says which item was responsible (a crash like this
-- doesn't leave anything else to go on).
local function giveItem(pc, gift)
    local itemPath = type(gift) == "table" and gift.path or gift
    local count = (type(gift) == "table" and gift.count) or 1
    log("encounter.giveItem: resolving " .. tostring(itemPath) .. " (count " .. count .. ")")

    local itemData = resolveAsset(itemPath)
    if not itemData then
        log("encounter.giveItem: could not resolve item asset: " .. tostring(itemPath))
        return false
    end
    local ok_inv, inv = pcall(function() return pc:GetInventory() end)
    if not ok_inv or not isValid(inv) then
        log("encounter.giveItem: GetInventory failed")
        return false
    end

    local allOk = true
    for i = 1, count do
        -- Checked once before: giving Strong Tea crashed the game (same
        -- signature as the tome crash - no catchable error, right as
        -- AddItemByData was called) after it had already succeeded twice
        -- earlier in the same session, so it isn't a fundamentally bad
        -- item like the tomes were. Most likely explanation: the
        -- inventory was full/near-full by that point in testing, and
        -- AddItemByData doesn't handle "no space" gracefully.
        -- CanAddItemByData is a real check for exactly this - skip
        -- (log, don't crash) rather than call AddItemByData blind.
        local ok_can, canAdd = pcall(function() return inv:CanAddItemByData(itemData, 1) end)
        if not ok_can then
            log("encounter.giveItem: CanAddItemByData failed for " .. itemPath .. ": " .. tostring(canAdd))
            allOk = false
        elseif not canAdd then
            log("encounter.giveItem: CanAddItemByData(" .. itemPath .. ") says no room [" .. i .. "/" .. count .. "] - skipping, not risking a crash")
            allOk = false
        else
            log("encounter.giveItem: attempting AddItemByData(" .. itemPath .. ") [" .. i .. "/" .. count .. "]")
            -- (ItemData, Count, DurabilityPercentage, GameplayTagContainer).
            -- Previously passed {} for the tag container, which crashed
            -- unpredictably (including once on Umbral Kebab, a
            -- previously 100%-reliable item on the exact same path) -
            -- FGameplayTagContainer has two TArray fields (GameplayTags,
            -- ParentTags) that a bare {} may not reliably zero-init
            -- through UE4SS's Lua-to-struct marshaling. Passing nil
            -- instead fixed that - confirmed in-game, clean first-try
            -- success. Separately, giving an item can still crash if the
            -- real NPC's own tutorial questline is still active for this
            -- player (its Blueprint's quest-tracking logic likely isn't
            -- expecting a duplicate NPC to be the one involved) - a known
            -- limitation, not something this function can detect safely;
            -- see README "Custom dialogue and item-giving".
            local ok_add, result = pcall(function() return inv:AddItemByData(itemData, 1, 1.0, nil) end)
            if not ok_add then
                log("encounter.giveItem: AddItemByData failed for " .. itemPath .. ": " .. tostring(result))
                allOk = false
            else
                log("encounter.giveItem: AddItemByData(" .. itemPath .. ") returned " .. tostring(result))
            end
        end
    end
    return allOk
end

-- EXPERIMENTAL alternative to giveItem - see config.lua's
-- Config.GiveItemsAsWorldDrops comment for why this exists. Spawns the item
-- as a physical world pickup at the NPC's feet via
-- ItemHelperLibrary:SpawnAndLaunchItem_Sync instead of injecting it into the
-- player's inventory via AddItemByData, on the theory that the drop path is
-- the same one ordinary loot/resource drops use and is therefore far more
-- exercised/trustworthy than shoving an item into inventory data directly.
--
-- Known unknowns, since this hasn't been run in-game yet:
--   - ItemSpawnParameters.Transform is a real FTransform (Rotation is an
--     FQuat), but the only proven-safe transform-table shape in this
--     codebase is the {Translation, Rotation = {Yaw,Pitch,Roll}, Scale3D}
--     one events.lua's trySpawnNearPlayer uses for
--     BeginDeferredActorSpawnFromClass (a different function - confirmed
--     in-game there). Reused verbatim here since it's the only pattern with
--     a track record; whether UE4SS's struct marshaling actually converts
--     that rotator-shaped table into the FQuat AddItemByData... er,
--     SpawnAndLaunchItem_Sync expects is unconfirmed for this specific call.
--   - LaunchDirection/Count/etc. are given as plain field values (no nested
--     TArray-bearing structs like the GameplayTagContainer that caused the
--     {} vs nil bug elsewhere in this file), so that particular crash mode
--     shouldn't apply here - but that's inference from the property list in
--     the SDK dump, not an in-game confirmation.
--   - WorldContextObject is passed as `actor` (the spawned NPC) since it's
--     a live, valid, world-resident UObject at the point this is called -
--     any such object should do for a WorldContextObject, but pc or
--     UEHelpers.GetWorld() are equally plausible if this one doesn't work.
--   - bAddToWorldItemRuntimeCache is set true to match how a "real" dropped
--     item would persist/behave, but that's a guess at intended usage, not
--     something read from a comment or confirmed behavior.
local function dropItem(ctx, actor, gift)
    local itemPath = type(gift) == "table" and gift.path or gift
    local count = (type(gift) == "table" and gift.count) or 1
    ctx.log("encounter.dropItem: resolving " .. tostring(itemPath) .. " (count " .. count .. ")")

    local itemData = resolveAsset(itemPath)
    if not itemData then
        ctx.log("encounter.dropItem: could not resolve item asset: " .. tostring(itemPath))
        return false
    end

    local dropClass = resolveAsset(ctx.config.WorldItemDropClassPath)
    if not isValid(dropClass) then
        ctx.log("encounter.dropItem: could not resolve WorldItemDropClassPath: " .. tostring(ctx.config.WorldItemDropClassPath))
        return false
    end

    local ok_helper, helper = pcall(function()
        return StaticFindObject("/Script/Dominion.Default__ItemHelperLibrary")
    end)
    if not ok_helper or not isValid(helper) then
        ctx.log("encounter.dropItem: ItemHelperLibrary CDO not found")
        return false
    end

    local ok_loc, loc = pcall(function() return actor:K2_GetActorLocation() end)
    if not ok_loc or not loc then
        ctx.log("encounter.dropItem: could not get actor location to drop at")
        return false
    end

    -- Every field is given explicitly, not left to omission-defaults - the
    -- {} vs nil GameplayTagContainer bug (see giveItem above) is exactly
    -- the failure mode of assuming a partially/un-specified struct
    -- zero-inits the way you'd want.
    local params = {
        ItemClass = dropClass,
        bCreateItem = true,
        bMagnetize = false, -- literal ground drop, not auto-pulled to the player
        SpawnedItemData = itemData,
        CopiedItem = nil,
        Count = count,
        Transform = {
            Translation = loc,
            Rotation = { Yaw = 0, Pitch = 0, Roll = 0 },
            Scale3D = { X = 1, Y = 1, Z = 1 },
        },
        LaunchDirection = { X = 0, Y = 0, Z = 1 },
        LaunchSpeed = ctx.config.ItemDropLaunchSpeed or 0.0,
        LaunchAngleVariance = ctx.config.ItemDropLaunchAngleVariance or 0.0,
        bSkipFloorSafetyCheck = false,
        OwnerController = nil,
        bSpawnOnlyForController = false,
        PlayerControllerThatDroppedItem = nil,
        bAddToWorldItemRuntimeCache = true,
        bMagnetizeToInstigatorOnSpawn = false,
    }

    ctx.log("encounter.dropItem: attempting SpawnAndLaunchItem_Sync(" .. itemPath .. ")")
    local ok_spawn, spawned, failureReason = pcall(function()
        return helper:SpawnAndLaunchItem_Sync(actor, params)
    end)
    if not ok_spawn then
        ctx.log("encounter.dropItem: SpawnAndLaunchItem_Sync failed for " .. itemPath .. ": " .. tostring(spawned))
        return false
    end
    ctx.log("encounter.dropItem: SpawnAndLaunchItem_Sync(" .. itemPath .. ") returned " ..
        tostring(isValid(spawned)) .. (failureReason and failureReason ~= "" and (", reason: " .. tostring(failureReason)) or ""))
    return isValid(spawned)
end

local function actorAddress(actor)
    local ok, addr = pcall(function() return actor:GetAddress() end)
    if ok then return addr end
    return nil
end

-- Registry of spawned actors currently awaiting the player's keypress,
-- keyed by actor address: { actor, ctx, opts }. Populated by
-- Encounter.Run, consumed by Encounter.TryTriggerNearby (the hotkey
-- handler in main.lua) and polled by the proximity loop that drives the
-- on-screen prompt.
local tracked = {}
local promptCurrentlyOn = false
local pollActive = false

-- Returns (addr, entry, pc) for whichever tracked actor is closest to the
-- player and within its own radius, or nil if none qualify.
local function findNearbyTrackedActor()
    local ok_pc, pc = pcall(UEHelpers.GetPlayerController)
    if not ok_pc or not isValid(pc) then return nil end
    local ok_pawn, pawn = pcall(function() return pc.Pawn end)
    if not ok_pawn or not isValid(pawn) then return nil end
    local ok_ploc, ploc = pcall(function() return pawn:K2_GetActorLocation() end)
    if not ok_ploc or not ploc then return nil end

    local bestAddr, bestEntry, bestDist = nil, nil, math.huge
    for addr, entry in pairs(tracked) do
        if isValid(entry.actor) then
            local ok_aloc, aloc = pcall(function() return entry.actor:K2_GetActorLocation() end)
            if ok_aloc and aloc then
                local d = distance(ploc, aloc)
                local radius = entry.opts.radius or entry.ctx.config.EncounterRadius
                if d <= radius and d < bestDist then
                    bestAddr, bestEntry, bestDist = addr, entry, d
                end
            end
        end
    end
    if not bestAddr then return nil end
    return bestAddr, bestEntry, pc
end

-- line1 -> (delay) -> give items -> line2 (optional) -> (delay) -> despawn.
local function playSequence(ctx, pc, actor, opts)
    ctx.notify(opts.displayName, opts.line1)

    scheduleAfter(opts.giveDelayMs or ctx.config.EncounterGiveDelayMs, function()
        ctx.log("Encounter '" .. opts.displayName .. "': giving " .. tostring(#(opts.gifts or {})) .. " item(s)")
        for _, gift in ipairs(opts.gifts or {}) do
            if ctx.config.GiveItemsAsWorldDrops then
                dropItem(ctx, actor, gift)
            else
                giveItem(pc, gift)
            end
        end
        if opts.line2 then
            ctx.notify(opts.displayName, opts.line2)
        end
        scheduleAfter(opts.despawnDelayMs or ctx.config.EncounterDespawnDelayMs, function()
            ctx.log("Encounter '" .. opts.displayName .. "': despawning")
            pcall(function() actor:K2_DestroyActor() end)
        end)
    end)
end

-- Starts the proximity poll that drives the "Press F for Random Event"
-- prompt's visibility. Idempotent - only one poll loop ever runs,
-- regardless of how many events have spawned NPCs.
local function ensurePollRunning()
    if pollActive or not LoopAsync then return end
    pollActive = true
    LoopAsync(300, function()
        local addr = findNearbyTrackedActor()
        local shouldShow = addr ~= nil
        if shouldShow ~= promptCurrentlyOn then
            promptCurrentlyOn = shouldShow
            Prompt.SetVisible(shouldShow, "Press F for Random Event")
        end
        return false -- keep looping for the lifetime of the process
    end)
end

-- opts:
--   displayName (string, required) - renames the NPC and is the toast title
--   line1 (string, required) - shown once the player presses F in range
--   gifts (array, optional) - every entry is given; each is either a
--     plain asset-path string (gives 1) or a { path = "...", count = N }
--     table (gives N)
--   line2 (string, optional) - shown after giving items, before despawning
--   radius, maxWaitMs, giveDelayMs, despawnDelayMs (numbers, optional -
--     fall back to ctx.config.Encounter* defaults)
function Encounter.Run(ctx, actor, opts)
    if not isValid(actor) then return end

    local ok_name, err_name = pcall(function() actor.DisplayName = FText(opts.displayName) end)
    ctx.log("Encounter: rename to '" .. opts.displayName .. "' " .. (ok_name and "succeeded" or ("failed: " .. tostring(err_name))))

    -- F is the real interaction now, so the native "Press E to interact"
    -- prompt (which just opens the stock tutorial dialogue) is dead
    -- weight - disable it on this spawned copy only. Never touches the
    -- real NPC, since `actor` here is always the one we just spawned.
    local ok_inter, inter = pcall(function() return actor.InteractionComponent end)
    if ok_inter and isValid(inter) then
        local ok_deactivate, err_deactivate = pcall(function() inter:SetActive(false, false) end)
        ctx.log("Encounter: InteractionComponent:SetActive(false) " ..
            (ok_deactivate and "succeeded" or ("failed: " .. tostring(err_deactivate))))
    else
        ctx.log("Encounter: no InteractionComponent found on spawned actor")
    end

    local addr = actorAddress(actor)
    if not addr then
        ctx.log("Encounter: could not get actor address, cannot track it")
        return
    end
    tracked[addr] = { actor = actor, ctx = ctx, opts = opts }
    ensurePollRunning()

    local maxWaitMs = opts.maxWaitMs or ctx.config.EncounterMaxWaitMs
    scheduleAfter(maxWaitMs, function()
        if tracked[addr] then
            tracked[addr] = nil
            ctx.log("Encounter '" .. opts.displayName .. "': nobody pressed F in time, despawning quietly")
            pcall(function() actor:K2_DestroyActor() end)
        end
    end)

    ctx.log("Encounter '" .. opts.displayName .. "': waiting for the player to get close and press F")
end

-- Called by the F hotkey handler in main.lua. Returns true if a nearby
-- tracked NPC's sequence was triggered, false if nothing was in range.
function Encounter.TryTriggerNearby()
    local addr, entry, pc = findNearbyTrackedActor()
    if not addr then return false end
    tracked[addr] = nil
    entry.ctx.log("Encounter '" .. entry.opts.displayName .. "': F pressed in range, playing sequence")
    playSequence(entry.ctx, pc, entry.actor, entry.opts)
    return true
end

-- Dev tool: destroys every currently-loaded instance of `shortClassName`
-- (e.g. "BP_NPC_WiseOldMan_FTUE_C", a UE4SS FindAllOf-style short class
-- name) whose DisplayName matches `expectedName` exactly - i.e. only our
-- own renamed spawns, never the real NPC (which keeps its original name).
-- For cleaning up copies orphaned by a hot-reload/restart that wiped the
-- Lua-side `tracked` registry before the player could press F (or the
-- safety despawn timer could fire) - the spawned actor persists in the
-- game world independently of the Lua VM state referencing it.
function Encounter.CleanupNamed(ctx, shortClassName, expectedName)
    local ok_actors, actors = pcall(FindAllOf, shortClassName)
    if not ok_actors or not actors then
        ctx.log("Encounter.CleanupNamed: FindAllOf('" .. shortClassName .. "') failed")
        return 0
    end

    local destroyed = 0
    for _, actor in ipairs(actors) do
        if isValid(actor) then
            local ok_name, name = pcall(function()
                return actor.DisplayName and actor.DisplayName:ToString()
            end)
            if ok_name and name == expectedName then
                local ok_destroy = pcall(function() actor:K2_DestroyActor() end)
                if ok_destroy then
                    destroyed = destroyed + 1
                end
            end
        end
    end
    ctx.log("Encounter.CleanupNamed('" .. shortClassName .. "', '" .. expectedName .. "'): destroyed " .. destroyed)
    return destroyed
end

-- Dev tool: destroys whichever instance of `shortClassName` is closest to
-- the player, but only if it's within `maxRadius` units (default 200,
-- i.e. "you're standing right next to it") AND more than one instance of
-- that class exists in total - so it can never touch the sole real NPC
-- when no duplicate is around. For cleaning up duplicates that predate
-- the rename in Encounter.Run (so CleanupNamed has nothing to match on) -
-- stand right next to the one you want gone, away from any other
-- instance of the same NPC, and press the cleanup hotkey.
--
-- Caveat: if the real NPC and a stray duplicate both happen to be within
-- maxRadius of you at the same time, whichever is literally closer gets
-- destroyed - there's no way to tell them apart once neither is renamed.
-- Move away from the real one first if that's a risk.
function Encounter.CleanupNearest(ctx, shortClassName, maxRadius)
    maxRadius = maxRadius or 200.0

    local ok_actors, actors = pcall(FindAllOf, shortClassName)
    if not ok_actors or not actors or #actors <= 1 then
        ctx.log("Encounter.CleanupNearest('" .. shortClassName .. "'): only " ..
            tostring(actors and #actors or 0) .. " instance(s) exist, nothing to clean up")
        return false
    end

    local ok_pc, pc = pcall(UEHelpers.GetPlayerController)
    if not ok_pc or not isValid(pc) then return false end
    local ok_pawn, pawn = pcall(function() return pc.Pawn end)
    if not ok_pawn or not isValid(pawn) then return false end
    local ok_ploc, ploc = pcall(function() return pawn:K2_GetActorLocation() end)
    if not ok_ploc or not ploc then return false end

    local closest, closestDist = nil, math.huge
    for _, actor in ipairs(actors) do
        if isValid(actor) then
            local ok_loc, loc = pcall(function() return actor:K2_GetActorLocation() end)
            if ok_loc and loc then
                local d = distance(ploc, loc)
                if d < closestDist then
                    closest, closestDist = actor, d
                end
            end
        end
    end

    if not closest or closestDist > maxRadius then
        ctx.log("Encounter.CleanupNearest('" .. shortClassName .. "'): nearest of " .. #actors ..
            " instance(s) is " .. tostring(closestDist) .. " units away, outside " .. maxRadius .. " - not touching it")
        return false
    end

    ctx.log("Encounter.CleanupNearest('" .. shortClassName .. "'): destroying nearest instance (" ..
        tostring(closestDist) .. " units away, " .. #actors .. " total instances found)")
    pcall(function() closest:K2_DestroyActor() end)
    return true
end

return Encounter
