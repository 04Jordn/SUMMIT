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

local ok, body = pcall(game.HttpGet, game, url)
if not ok or type(body) ~= "string" or #body == 0 then
    warn("[SummitX] download failed: " .. tostring(body))
    return
end

local chunk, err = loadstring(body, "SummitX")
if not chunk then
    warn("[SummitX] failed to compile: " .. tostring(err))
    return
end

return chunk()
