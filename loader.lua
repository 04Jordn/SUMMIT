--=====================================================================================
--  SUMMITX LOADER
--
--  This is the ONLY url anyone ever pastes:
--
--      loadstring(game:HttpGet("https://raw.githubusercontent.com/04Jordn/SUMMIT/main/loader.lua"))()
--
--  It holds no logic and no secrets. Point TARGET at whichever script this loader
--  is for; move it, rename the repo, change host entirely, and every loadstring
--  already in circulation follows, because none of them ever pointed at the script
--  directly.
--
--  For a second game, copy this file under another name (loader-fut.lua) and change
--  TARGET. Nothing here inspects the game -- premium is decided by WHO is running
--  the script, never by where they are running it.
--=====================================================================================

local TARGET = "https://raw.githubusercontent.com/04Jordn/SUMMIT/main/NewUIMafia.lua"

-- Cache-buster: raw.githubusercontent serves through a CDN that will happily hand
-- out a stale file for minutes after a push, which looks exactly like "my update
-- didn't apply".
local url = TARGET .. (TARGET:find("?") and "&" or "?") .. "_=" .. tostring(os.time())

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
