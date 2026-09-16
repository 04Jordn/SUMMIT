--=====================================================================================
--  SUMMITX LOADER
--
--  One URL, two jobs, chosen by the argument it is called with.
--
--  NO ARGUMENT -- returns the Library, exactly like loading SummitX.lua directly:
--
--      local Library = loadstring(game:HttpGet(LOADER))()
--
--  Every game script calls it this way, which is why they can point at a URL that never
--  moves: rename the library file, restructure the repo, change host, and you edit SOURCE
--  below instead of every script you have ever shipped. Those scripts ship obfuscated, so
--  the no-argument call has to keep meaning "give me the Library" -- that is why picking a
--  game is a separate argument rather than the default.
--
--  AN ARGUMENT -- runs the script for the game you are in, picked by GameId:
--
--      loadstring(game:HttpGet(LOADER))("auto")
--
--  Pass a name instead to force one: ("mafia"), ("cold war"), ("fut"), ("last stop").
--  A name GAMES does not have is fetched as a repo file of that name, so a script still in
--  development loads by file name without this file naming it. Shipping one is its GAMES line:
--  that line is the switch that makes it load by itself for everyone standing in that game.
--=====================================================================================

local BASE   = "https://raw.githubusercontent.com/04Jordn/SUMMIT/refs/heads/main/"
local SOURCE = BASE .. "SummitX.lua"

-- GameId, never PlaceId: a universe moves players between places -- Mafia rounds run in a
-- separate round place, FUT hops pitches -- and the match has to survive the teleport. Ids is
-- a list because one script can cover several universes: FUT's clones are separate universes
-- running the same build, which is why FUT is the one script with no GAME_IDS guard of its own.
local GAMES = {
    { Name = "Cold War",  File = "ColdWarGame",  Ids = { 4750561026 } },
    { Name = "FUT",       File = "FutGame",      Ids = { 9517627739, 10629189132 } },
    { Name = "MAFIA",     File = "MafiaGame",    Ids = { 7497471789 } },
    { Name = "Last Stop", File = "LastStopGame", Ids = { 10759337137 } },
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

-- Cache-buster: raw.githubusercontent sends Cache-Control: max-age=300, so without it a
-- fresh upload keeps serving the previous copy for five minutes -- which looks exactly
-- like "my update didn't apply".
local function Run(target, name)
    local url = target .. (target:find("?") and "&" or "?") .. "_=" .. tostring(os.time())

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
            if Normalise(entry.Name) == want or Normalise(entry.File) == want then return entry end
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
if mode == nil or mode == false then return Run(SOURCE, "SummitX") end

local raw  = (type(mode) == "string") and mode or ""
local want = Normalise(raw)
if want == "auto" or want == "game" or want == "true" or want == "" then want = nil end

local entry, why = Pick(want)
if entry then return Run(BASE .. entry.File, entry.File) end

-- A name GAMES does not have is still allowed to be a file on the repo. That is how a script
-- that has not shipped yet loads -- ("FootballFusion3") -- without this public file naming it,
-- which a GAMES line would, to everyone, along with handing a copy to anyone standing in that
-- game. Spelled exactly: raw.githubusercontent is case-sensitive, and a plain file name only.
if want and raw:match("^[%w_%-]+$") then return Run(BASE .. raw, raw) end

warn("[SummitX] " .. why)
