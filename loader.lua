--=====================================================================================
--  SUMMITX LOADER
--
--  Returns the Library, exactly like loading SummitX.lua directly:
--
--      local Library = loadstring(game:HttpGet(
--          "https://raw.githubusercontent.com/04Jordn/SUMMIT/refs/heads/main/loader.lua"))()
--
--  Knows nothing about any game. It exists so game scripts point at a URL that
--  never moves: rename the library file, restructure the repo, change host, and
--  you edit SOURCE below instead of every script you have ever shipped.
--=====================================================================================

local SOURCE = "https://raw.githubusercontent.com/04Jordn/SUMMIT/refs/heads/main/SummitX.lua"

-- Cache-buster: raw.githubusercontent sends Cache-Control: max-age=300, so without
-- it a fresh upload keeps serving the previous copy for five minutes -- which looks
-- exactly like "my update didn't apply".
local url = SOURCE .. (SOURCE:find("?") and "&" or "?") .. "_=" .. tostring(os.time())

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

local body, why = Fetch(url)
if not body then
    warn("[SummitX] download failed: " .. tostring(why))
    return
end

local chunk, err = loadstring(body, "SummitX")
if not chunk then
    warn("[SummitX] failed to compile: " .. tostring(err))
    return
end

return chunk()
