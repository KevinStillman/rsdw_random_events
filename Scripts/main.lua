local UEHelpers = require("UEHelpers")
local Config    = require("config")
local Events    = require("events")
local Notify    = require("notify")
local Encounter = require("encounter")

local lastEventAtMs = -math.huge
local lastEventAtByIdMs = {}
local loopActive = false

local function log(msg)
    if Config.Debug then
        print("[RSDWRandomEvents] " .. msg .. "\n")
    end
end

local function isValid(o)
    return o and o.IsValid and o:IsValid()
end

-- A random event firing while a menu was open crashed the game (likely
-- from spawning an actor / touching the world while it's paused/suspended
-- behind a full-screen UI). A valid PlayerController alone doesn't rule
-- that out - it (and its Pawn) can stay valid while a menu is open over
-- the still-loaded world. ADominionPlayerController tracks exactly which
-- UI mode is active via CurrentInputMode, compared against its own
-- GameplayInputMode (the baseline "normal play, nothing open" mode) - so
-- this requires that exact match, not just "some Pawn exists". Two
-- separately-obtained Lua proxies for the same UObject aren't `==`, so
-- the comparison goes through GetAddress() (see discovery.lua for the
-- same pattern hit before).
local function isInGameplayWorld()
    local ok_pc, pc = pcall(UEHelpers.GetPlayerController)
    if not ok_pc or not isValid(pc) then return false end

    local ok_pawn, pawn = pcall(function() return pc.Pawn end)
    if not ok_pawn or not isValid(pawn) then return false end

    local ok_cur, current = pcall(function() return pc.CurrentInputMode end)
    local ok_gp, gameplay = pcall(function() return pc.GameplayInputMode end)
    if not (ok_cur and ok_gp and isValid(current) and isValid(gameplay)) then return false end

    local ok_addr1, addr1 = pcall(function() return current:GetAddress() end)
    local ok_addr2, addr2 = pcall(function() return gameplay:GetAddress() end)
    return ok_addr1 and ok_addr2 and addr1 == addr2
end

-- os.time() (wall-clock seconds), not os.clock() (CPU time) - CPU time
-- drifts well behind wall-clock time in a game process that spends most of
-- each frame waiting, which would make minute-scale cooldowns below fire
-- far less often than configured.
local function nowMs()
    return os.time() * 1000
end

-- Picks a random event from the pool, weighted by `weight`, skipping any
-- still on per-event cooldown. Returns nil if every event is on cooldown.
local function pickEvent()
    local eligible = {}
    local totalWeight = 0
    local t = nowMs()
    for _, ev in ipairs(Events) do
        local lastAt = lastEventAtByIdMs[ev.id] or -math.huge
        if t - lastAt >= ev.cooldownMs then
            totalWeight = totalWeight + ev.weight
            table.insert(eligible, ev)
        end
    end
    if totalWeight <= 0 then return nil end

    local roll = math.random() * totalWeight
    local acc = 0
    for _, ev in ipairs(eligible) do
        acc = acc + ev.weight
        if roll <= acc then return ev end
    end
    return eligible[#eligible] -- float rounding fallback
end

local function runEvent(ev)
    local ctx = {
        config = Config,
        log = log,
        notify = function(title, body, durationMs) Notify.Show(title, body, durationMs) end,
    }
    log("firing event: " .. ev.id)
    local ok, err = pcall(ev.run, ctx)
    if not ok then
        log("event '" .. ev.id .. "' errored: " .. tostring(err))
        return
    end
    local t = nowMs()
    lastEventAtMs = t
    lastEventAtByIdMs[ev.id] = t
end

local function maybeTriggerEvent()
    local t = nowMs()
    if t - lastEventAtMs < Config.GlobalCooldownMs then return end
    if math.random() > Config.TriggerChance then return end

    local ev = pickEvent()
    if not ev then
        log("maybeTriggerEvent: all events on cooldown")
        return
    end
    ExecuteInGameThread(function() runEvent(ev) end)
end

local function startTriggerLoop()
    if loopActive or not LoopAsync then return end
    loopActive = true
    LoopAsync(Config.CheckIntervalMs, function()
        if not isInGameplayWorld() then return false end
        local ok, err = pcall(maybeTriggerEvent)
        if not ok then log("startTriggerLoop: maybeTriggerEvent failed: " .. tostring(err)) end
        return false -- keep looping for the lifetime of the process
    end)
end

startTriggerLoop()

-- ---------------------------------------------------------------------------
-- Hotkey: triggers a nearby spawned NPC's scripted encounter (line, item
-- gift, despawn). Separate from the game's own interact button entirely -
-- see encounter.lua for why (three different native hook points that
-- looked plausible for reacting to the real interact button were all
-- confirmed to never fire for these NPCs). A "Press F for Random Event"
-- prompt (Scripts/prompt.lua) shows automatically while in range, driven
-- by encounter.lua's own proximity poll - this hotkey doesn't need its
-- own range check, Encounter.TryTriggerNearby does that and just returns
-- false if nothing qualifies.
-- ---------------------------------------------------------------------------
if not _G.__RSDWRandomEvents_EncounterInteractRegistered then
    _G.__RSDWRandomEvents_EncounterInteractRegistered = true
    RegisterKeyBind(Config.HotkeyEncounterInteract, function()
        ExecuteInGameThread(function()
            if not isInGameplayWorld() then return end
            Encounter.TryTriggerNearby()
        end)
    end)
else
    log("RegisterKeyBind skipped: encounter-interact hotkey already registered (hot-reload)")
end

log("Loaded v" .. tostring(Config.Version) .. ". " ..
    Config.HotkeyEncounterInteractLabel .. " = trigger a nearby event NPC's encounter.")
