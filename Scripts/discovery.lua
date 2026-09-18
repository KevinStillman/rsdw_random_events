-- Dev tool: call Discovery.Run() near an NPC you want to reuse as a
-- random-event actor, and this logs every nearby Actor's class path +
-- distance + display name to Scripts/discovery_log.txt (gitignored - it's
-- local scratch output, not something to commit). Use one of the logged
-- class paths as Config.DrunkenDwarfClassPath (or a future event's spawn
-- target) in config.lua. Not wired to a hotkey (removed ahead of public
-- testing, along with the other dev-only hotkeys - see CHANGELOG) - wire
-- a temporary RegisterKeyBind in main.lua back up if you need this again.
--
-- Scans "Actor" rather than just "Pawn": Dragonwilds' dialogue/quest NPCs
-- (e.g. the Wise Old Man, Vannaka) turned out not to be Pawn-derived at all
-- - no player-style movement/controller - so a Pawn-only scan missed them
-- entirely. Actor is the engine's base class for anything placed in the
-- world, so this is the broadest net that still works generically. The
-- radius filter keeps the result list manageable even so.
--
-- We can't launch/play the game ourselves to find these paths - see README
-- "Filling in a spawn target" for the workflow this feeds into.
local UEHelpers = require("UEHelpers")
local Config = require("config")

local Discovery = {}

local function isValid(o)
    return o and o.IsValid and o:IsValid()
end

local function getScriptDir()
    local source = debug.getinfo(1, "S").source
    source = source:match("^@(.*)$") or source
    return source:match("^(.*)[/\\]")
end

local LOG_FILE = getScriptDir() and (getScriptDir() .. "\\discovery_log.txt")

local function distance(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Two separately-obtained Lua proxies for the same UObject aren't `==`, so
-- identity has to go through the underlying pointer via GetAddress().
local function sameObject(a, b)
    local ok_a, addrA = pcall(function() return a:GetAddress() end)
    local ok_b, addrB = pcall(function() return b:GetAddress() end)
    return ok_a and ok_b and addrA == addrB
end

-- GetPathName() isn't exposed to Lua (only GetFullName() is, e.g.
-- "BlueprintGeneratedClass /Game/.../BP_X.BP_X_C") - strip the leading
-- type-name token so the result is a bare object path, matching the format
-- StaticFindObject/spawn calls expect.
local function classPathOf(cls)
    local ok, full = pcall(function() return cls:GetFullName() end)
    if not ok or not full then return "?" end
    return full:match("^%S+%s+(.+)$") or full
end

function Discovery.Run()
    local ok_pc, pc = pcall(UEHelpers.GetPlayerController)
    if not ok_pc or not isValid(pc) then
        print("[RSDWRandomEvents] discovery: no PlayerController\n")
        return
    end
    local ok_pawn, playerPawn = pcall(function() return pc.Pawn end)
    if not ok_pawn or not isValid(playerPawn) then
        print("[RSDWRandomEvents] discovery: no player Pawn\n")
        return
    end
    local ok_loc, playerLoc = pcall(function() return playerPawn:K2_GetActorLocation() end)
    if not ok_loc or not playerLoc then
        print("[RSDWRandomEvents] discovery: could not read player location\n")
        return
    end

    local ok_actors, actors = pcall(FindAllOf, "Actor")
    if not ok_actors or not actors then
        print("[RSDWRandomEvents] discovery: FindAllOf('Actor') failed\n")
        return
    end

    local rows = {}
    for _, actor in ipairs(actors) do
        if isValid(actor) and not sameObject(actor, playerPawn) then
            local ok_aloc, aloc = pcall(function() return actor:K2_GetActorLocation() end)
            if ok_aloc and aloc then
                local d = distance(playerLoc, aloc)
                if d <= Config.DiscoveryRadius then
                    local ok_cls, cls = pcall(function() return actor:GetClass() end)
                    local classPath = (ok_cls and isValid(cls)) and classPathOf(cls) or "?"
                    local displayName = "?"
                    pcall(function() displayName = actor:GetFName():ToString() end)
                    table.insert(rows, { distance = d, classPath = classPath, name = displayName, loc = aloc })
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.distance < b.distance end)

    local lines = {}
    table.insert(lines, os.date("%Y-%m-%d %H:%M:%S") ..
        (" - player at (%.0f, %.0f, %.0f), %d Actor(s) within %.0f units"):format(
            playerLoc.X, playerLoc.Y, playerLoc.Z, #rows, Config.DiscoveryRadius))
    for _, row in ipairs(rows) do
        table.insert(lines, ("  [%6.0f] %-30s %s  (%.0f, %.0f, %.0f)"):format(
            row.distance, row.name, row.classPath, row.loc.X, row.loc.Y, row.loc.Z))
    end
    table.insert(lines, "")

    local text = table.concat(lines, "\n")
    print("[RSDWRandomEvents] " .. text .. "\n")

    if LOG_FILE then
        local f = io.open(LOG_FILE, "a")
        if f then
            f:write(text .. "\n")
            f:close()
        end
    end
end

return Discovery
