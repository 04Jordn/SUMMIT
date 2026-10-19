--=====================================================================================
--  SUMMITX LOADER
--
--  One URL for every game. Runs the Luarmor script for the game you are in, picked by GameId:
--
--      loadstring(game:HttpGet(LOADER))()
--
--  Premium players put their key on the line above it:  script_key = "KEY"
--  ("auto") still works for anyone running the old line. Pass a name instead to force one:
--  ("mafia"), ("cold war"), ("fut"), ("last stop"), ("asylum life").
--  A name GAMES does not have is fetched as a repo file of that name, so a script still in
--  development loads by file name without this file naming it. Shipping one is its GAMES line:
--  that line is the switch that makes it load by itself for everyone standing in that game.
--=====================================================================================

if _VERSION ~= "Luau" then return end

local BASE    = "https://raw.githubusercontent.com/04Jordn/SUMMIT/refs/heads/main/"
local LUARMOR = "https://api.luarmor.net/files/v3/loaders/%s.lua"

-- GameId, never PlaceId: a universe moves players between places -- Mafia rounds run in a
-- separate round place, FUT hops pitches -- and the match has to survive the teleport. Ids is
-- a list because one script can cover several universes: FUT's clones are separate universes
-- running the same build, which is why FUT is the one script with no GAME_IDS guard of its own.
-- Script is the Luarmor script id, the hex line under each script's name on the dashboard.
local GAMES = {
    { Name = "Cold War",    Script = "84b81eeadcd6ad8ababbf2bbc62e8f4e", Ids = { 4750561026 } },
    { Name = "FUT",         Script = "6c5072e19a2de9d7a797cab2af7aeb5b", Ids = { 9517627739, 10629189132 } },
    { Name = "MAFIA",       Script = "26280e1be424b3b4e94f9db1641705f6", Ids = { 7497471789 } },
    { Name = "Last Stop",   Script = "166746cd428fe86fb1ea18a7d2eb2419", Ids = { 10759337137 } },
    { Name = "Asylum Life", Script = "dc9226fec2420baccff4fbbe794517e1", Ids = { 6749060816 } },
}

-- Two transports, same reasoning as the library's own HTTP layer: game:HttpGet is
-- executor-injected, not a Roblox API, so it is not a given. Note the member lookup
-- has to be pcall'd SEPARATELY -- `pcall(game.HttpGet, game, url)` evaluates
-- game.HttpGet to pass it as an argument, and indexing a member a DataModel does not
-- have RAISES, outside that pcall. On such an executor the loader died before it
-- could try anything else, which is the whole hub gone rather than one feature.
local function Fetch(target)
    local why = "no transport"

    local okFn, getFn = pcall(function() return game.HttpGet end)
    if okFn and type(getFn) == "function" then
        local ok, body = pcall(getFn, game, target)
        if ok and type(body) == "string" and #body > 0 then return body end
        why = ok and "empty response" or tostring(body)
    end

    local req = (type(syn) == "table" and syn.request)
        or (type(fluxus) == "table" and fluxus.request)
        or (type(http) == "table" and http.request)
        or request or http_request
        or (type(getgenv) == "function" and getgenv().request)
    if type(req) == "function" then
        local ok, res = pcall(req, { Url = target, Method = "GET" })
        if ok and type(res) == "table" then
            local code = res.StatusCode or res.Status or res.status_code
            local body = res.Body or res.body
            if type(body) == "string" and #body > 0 and (code == nil or (code >= 200 and code < 300)) then
                return body
            end
            why = "HTTP " .. tostring(code)
        else
            why = ok and "no response table" or tostring(res)
        end
    end

    return nil, why
end

local function Run(url, name)
    local body, why = Fetch(url)
    if not body then
        warn("[SummitX] download failed for " .. name .. ": " .. tostring(why))
        return
    end

    -- raw.githubusercontent answers a missing file with a 200-shaped body on some
    -- transports, so a rename reads as a compile error unless it is named here.
    if body:sub(1, 4) == "404:" then
        warn("[SummitX] not on the repo: " .. name)
        return
    end

    local chunk, err = loadstring(body, name)
    if not chunk then
        warn("[SummitX] failed to compile " .. name .. ": " .. tostring(err))
        return
    end

    return chunk()
end

local function Normalise(text)
    return (tostring(text):lower():gsub("[^%w]", ""))
end

local function Pick(want)
    if want then
        for _, entry in ipairs(GAMES) do
            if Normalise(entry.Name) == want then return entry end
        end
        return nil, "no script called '" .. want .. "'"
    end

    for _, entry in ipairs(GAMES) do
        for _, id in ipairs(entry.Ids) do
            if id == game.GameId then return entry end
        end
    end
    return nil, "no script for this game (GameId " .. tostring(game.GameId) .. ")"
end

local mode = ...
local raw  = (type(mode) == "string") and mode or ""
local want = Normalise(raw)
if want == "auto" or want == "game" or want == "true" or want == "" then want = nil end

local entry, why = Pick(want)
if entry and entry.Script == "" then
    warn("[SummitX] " .. entry.Name .. " is not out yet")
    return
end
if entry then return Run(LUARMOR:format(entry.Script), entry.Name) end

-- A name GAMES does not have is still allowed to be a file on the repo. That is how a script
-- that has not shipped yet loads -- ("FootballFusion3") -- without this public file naming it,
-- which a GAMES line would, to everyone, along with handing a copy to anyone standing in that
-- game. Spelled exactly: raw.githubusercontent is case-sensitive, and a plain file name only.
-- The ?_= cache-buster is GitHub only: raw.githubusercontent caches for five minutes, and
-- Luarmor answers a loader URL with a query string differently.
if want and raw:match("^[%w_%-]+$") then return Run(BASE .. raw .. "?_=" .. tostring(os.time()), raw) end

warn("[SummitX] " .. why)
