--!nocheck
--!nolint CommentDirective
--!nolint SameLineStatement
--!nolint UnknownGlobal
-- nocheck: the type checker has no definitions for executor globals. UnknownGlobal is the
-- `gethui or get_hidden_ui or gethiddenui` chain and its kin, built on globals that may be nil.

--=====================================================================================
--  SUMMITX  —  UI LIBRARY
--
--    1. Config & constants        6.  Input & drag          11. Widgets
--    2. Services & platform       7.  Notify & observers    12. Window
--    3. Lifetime                  8.  Icons                 13. Key gate, log, Init
--    4. Animation                 9.  Loops                 14. Keybind dispatch
--    5. Instances                 10. Persistence           15. Exports
--                                 10b. Premium gating       16. Built-in tabs
--
--  Returns Library and builds nothing until a game script calls Init. Copy example.lua
--  to start a new game; everything below is defaults it can override.
--
--  SHIPS AS SOURCE. Anyone can read this file, so every name it leaves lying around is a
--  signature somebody can match on: the ScreenGui names are generated fresh each run. Do not
--  hard-code any of them back. Nothing is parented inside the game at all.
--=====================================================================================

-- getgenv() is the one table that survives a re-inject; `_G` inside an executor thread is not
-- the game's `_G`, so cleanup stashed there can never find the previous copy of itself.
local genv = type(getgenv) == "function" and getgenv() or nil
if type(genv) ~= "table" then
    error("SummitX needs getgenv(); this executor does not expose it. There is no _G fallback -- on "
        .. "most executors _G is not the table the game sees, so cleanup could never find its own "
        .. "previous copy, and on the ones where it IS shared the hub's keys would land in reach "
        .. "of the game.", 0)
end

genv.SummitGen = (genv.SummitGen or 0) + 1

-- Handed to the NEXT injection through genv so a re-inject can sweep the copy before it when
-- SummitCleanup did not run. Only the genv KEYS stay fixed -- they have to, or a re-inject cannot
-- find its predecessor at all.
local function RandName()
    local n, out = math.random(9, 15), {}
    for i = 1, n do
        local c = math.random(52)
        out[i] = string.char(c <= 26 and 64 + c or 70 + c)      -- A-Z then a-z
    end
    return table.concat(out)
end

local PrevNames = genv.SummitNames
local Names = { Ui = RandName(), Toast = RandName(), Key = RandName() }
genv.SummitNames = Names

-- SHAPE AND SAFE DEFAULTS ONLY — the real name, links, keys and webhook live in the game script
-- and arrive through Library:Configure{...} before Init. Nothing here is a secret, so this file
-- is safe to publish. Every empty value below is inert: no key gate, no logging.
local CONFIG = {
    HUB_NAME = "",                  -- e.g. "SummitX" — topbar title, notification and key-card title
    VERSION = "",                   -- e.g. "v1.0" — the chip beside the game name
    DISCORD = "",                   -- e.g. "https://discord.gg/abcdef" — copied by the Get Key button
    STORE = "",                     -- e.g. "https://summitx.mysellauth.com" — where Premium is bought

    -- On-disk home for configs, icons and the key file. A real name, not a placeholder: every
    -- path below is built from it, and "" would write to the executor's workspace root.
    FOLDER = "SummitX",
    CONFIG_FILE = "SummitX/configs/" .. tostring(game.PlaceId) .. ".json",

    -- Your bot's HTTPS endpoint, no trailing slash. Serves BOTH the premium check and the
    -- execution log. Not a secret: the webhook stays in the bot's environment and the whitelist
    -- never leaves it.
    --
    -- SET HERE, ON PURPOSE. Premium is one list of Roblox ids for ALL games, so a whitelisted
    -- account is premium in every script that loads this library. Empty or unset = everyone free.
    API = "https://vk57znx9vk.apps.bot-hosting.cloud",
    API_ATTEMPTS = 2,               -- one silent retry so a transient blip can't downgrade a payer

    -- Executors the hub refuses to run on: each entry is matched as a case-insensitive SUBSTRING
    -- of identifyexecutor(), so "wave" catches "Wave 2.4". Empty list = every executor allowed.
    UNSUPPORTED = {},               -- e.g. { "Solara", "JJSploit" }
    UNSUPPORTED_NOTE = "",          -- e.g. "Use Potassium or Xeno instead."

    -- The game this script is FOR, as UNIVERSE ids. Empty (the default) = it runs anywhere, which
    -- is the right setting for a general hub. Fill it and it becomes all-or-nothing: on a matching
    -- game the whole hub builds as normal, and on anything else NOTHING builds: one notification
    -- and an unload, with no middle state where the tabs are missing and Settings is left standing.
    --
    -- GameId, never PlaceId. An experience spans several places -- a lobby and a round server carry
    -- different PlaceIds under one GameId -- so a place-pinned script goes dead the moment the game
    -- teleports the player, which is the failure this exists to prevent rather than cause.
    GAME_IDS = {},                  -- e.g. { 7024694308 } — covers every place in the experience
    GAME_NAME = "",                 -- e.g. "Main Game" — named in the wrong-game notification
    GAME_NOTE = "",                 -- e.g. "Grab the FUT script for that one instead."

    KEY = {
        Enabled = false,
        Keys = {},                  -- e.g. { "SummitX", "SummitX2" } — matched case-insensitively
        Note = "",                  -- e.g. "Join the Discord to grab your key, then paste it below."
        SaveFile = "SummitX/key.txt",
        SaveForPremiumOnly = true,  -- free users retype the key each launch
    },
}

local L = {
    PadX = 15, PadY = 15, LabelGap = 5, RailGap = 10,
    TitleSize = 14, DescSize = 12,
    TabH = 38, TabGap = 6, TopbarH = 52, PageTop = 50,
    Corner12 = UDim.new(0, 12), Corner8 = UDim.new(0, 8), Corner6 = UDim.new(0, 6), Pill = UDim.new(1, 0),
}

local COLOR_WHITE, COLOR_BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
-- 18 on a 46px face is the 0.4 radius ratio the badge artwork is drawn to.
local FAB_CORNER, FAB_FACE_ALPHA = UDim.new(0, 18), 0.42
-- Bump FAB_SCHEMA to force every client to re-fetch the badge after replacing the artwork; the
-- version is in the filename, so a stale cache can never be picked up by name.
local FAB_ICON, FAB_SCHEMA = "https://raw.githubusercontent.com/04Jordn/SUMMIT/main/SX%20Icon.png", 1
local DEFAULT_TWEEN_TIME = 0.35
local TICK_FADE = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
-- The UI Scale slider is a multiple of the design size: 1.00 renders at SCALE_BASE. Geometry maths
-- keeps reading uiScale.Scale, which is the real number.
local SCALE_BASE = 1.15
local DEFAULT_SCALE = 1.00      -- also the UI Scale slider's default, so the window never snaps on boot
local SHADOW_IMG, SHADOW_SLICE = "rbxassetid://8992230677", Rect.new(99, 99, 99, 99)
local BAR_TOP, BAR_MID, BAR_BOT = "rbxassetid://6276641225", "rbxassetid://6889812721", "rbxassetid://6889812791"

--=====================================================================================
--  2. Services & platform
--=====================================================================================

-- Do NOT alias math.*/table.* into locals: Luau resolves them through GETIMPORT and compiles the
-- hot ones to fastcalls, and a local defeats both.

-- First CALLABLE of the candidates, skipping non-functions. Variadic with select("#") rather than
-- a table: a nil global in the middle leaves a hole an array walk would stop dead on.
--!mv:omit
local function FirstFn(...)
    for i = 1, select("#", ...) do
        local fn = select(i, ...)
        if type(fn) == "function" then return fn end
    end
    return nil
end

local CloneRef = FirstFn(clonereference, cloneref)
if not (CloneRef and pcall(CloneRef, game)) then CloneRef = function(o) return o end end
--!mv:omit
local function Service(n)
    local s = game:GetService(n)
    if not s then error(('SummitX: game:GetService("%s") returned nil -- the executor thread lost its capability. Re-run the script.'):format(n), 0) end
    return CloneRef(s)
end

local Players, UIS, TweenService = Service("Players"), Service("UserInputService"), Service("TweenService")
local RunService, TeleportService, HttpService = Service("RunService"), Service("TeleportService"), Service("HttpService")
local GuiService, TextService = Service("GuiService"), Service("TextService")
local MarketplaceService = Service("MarketplaceService")

local HttpRequest = FirstFn(type(syn) == "table" and syn.request, type(fluxus) == "table" and fluxus.request,
    type(http) == "table" and http.request, request, http_request, genv.request)
local LocalPlayer = Players.LocalPlayer
local Workspace = CloneRef(workspace)
local Camera = Workspace.CurrentCamera

local HideGui = FirstFn(
    type(syn) == "table" and syn.protect_gui,
    protectgui, protect_gui,
    genv.protect_gui,
    secure_gui)
local HiddenUi = (function()
    local get = FirstFn(gethui, get_hidden_ui, gethiddenui)
    if not get then return nil end
    local ok, res = pcall(get)
    return (ok and typeof(res) == "Instance") and res or nil
end)()

-- gethui() then CoreGui. NO PlayerGui fallback: it is replicated and wiped on respawn.
local TargetGui = HiddenUi or (function()
    local c = Service("CoreGui")
    -- GetFullName throws at identity 2 without the capability, and there is nothing to fall back
    -- TO: returning CoreGui anyway only moves the error into the first Create(), where it names
    -- neither the cause nor the fix.
    local ok, err = pcall(c.GetFullName, c)
    if not ok then
        error("SummitX: no gethui() and CoreGui is not reachable from this thread (" .. tostring(err)
            .. "). Re-run the script; if it keeps happening the executor is injecting without enough capability.", 0)
    end
    return c
end)()

local function Warn(fmt, ...)
    local who = CONFIG.HUB_NAME
    warn(("[%s] "):format(who ~= "" and who or "SummitX") .. string.format(fmt, ...))
end

-- Tear the previous copy down only now. This yields (cleanup fades its GUIs out), and a yielded
-- executor thread can come back without the capability GetService needs -- so everything above
-- has to be resolved before we get here. The stale-name sweep below is the backstop if it fails.
if genv.SummitCleanup then pcall(genv.SummitCleanup) end

-- BOUNDED. When Destroy is refused the pcall swallows the failure and FindFirstChild hands back
-- the same instance, so an uncapped retry never ends and the client hangs on load saying nothing.
--!mv:omit
local function SweepStale(name)
    for _ = 1, 8 do
        local stale = TargetGui:FindFirstChild(name)
        if not stale then return end
        pcall(function() stale:Destroy() end)
    end
    Warn("a leftover %q from a previous run would not destroy", name)
end
-- Only the PREVIOUS run's names can be swept; this run's are new and nothing else answers to them.
if PrevNames then
    for _, leftover in PrevNames do SweepStale(leftover) end
end

local IsConsole = (function() local ok, v = pcall(GuiService.IsTenFootInterface, GuiService); return ok and v end)()
local IsMobile = not IsConsole and UIS.TouchEnabled and not UIS.KeyboardEnabled

--!mv:omit
local function EnsureFolders()
    if not (isfolder and makefolder) then return end
    local want = {}
    for _, path in { CONFIG.FOLDER, CONFIG.CONFIG_FILE, CONFIG.KEY and CONFIG.KEY.SaveFile } do
        local dir = path and (path:match("^(.*)/[^/]*$") or path)
        if dir and dir ~= "" then want[dir] = true end
    end
    for path in want do
        -- Every level, not just the leaf: makefolder("A/B") fails on some executors unless A
        -- already exists, and a hub pointing CONFIG_FILE at "MyHub/saves/x.json" needs both.
        local acc
        for seg in path:gmatch("[^/]+") do
            acc = acc and (acc .. "/" .. seg) or seg
            if not isfolder(acc) then
                local ok, err = pcall(makefolder, acc)
                if not ok then Warn("could not create folder %q: %s", acc, tostring(err)) end
            end
        end
    end
end
EnsureFolders()

local UI: { [string]: any } = {}

--=====================================================================================
--  3. Lifetime
--=====================================================================================

local function Scope()
    local tasks = {}
    return {
        Add = function(item) tasks[#tasks + 1] = item; return item end,
        -- Swaps the list out and repeats while it refills, so a cleanup that queues another task
        -- still runs it. Capped, like SweepStale, so a task that re-adds itself cannot spin.
        Clean = function()
            for _ = 1, 8 do
                if #tasks == 0 then return end
                local list = tasks
                tasks = {}
                for i = #list, 1, -1 do
                    local item = list[i]
                    if typeof(item) == "RBXScriptConnection" then item:Disconnect()
                    elseif typeof(item) == "Instance" then item:Destroy()
                    elseif type(item) == "function" then item() end
                end
            end
        end,
    }
end

local Root = Scope()
function genv.SummitCleanup() Root.Clean(); genv.SummitCleanup = nil end

local FadeOut, FadeVisible, ResetInteractives, Snapshot, ApplySnapshot, PrimeFade, FadeWindowOut, FadeWindowIn

local cursorForced, savedMouseIcon, iconGuard
-- ⚠ THE ONLY THING A GAME CAN SEE. The library parents nothing inside the DataModel, so this is
-- the whole surface: a game that locks the cursor sets MouseIconEnabled false and finds it true
-- again, which is a real tell. Do not add a second one. Kept as narrow as it goes -- the WRITE
-- only happens when something else turned it off, and only while the menu is open. Do not widen
-- it to run while the menu is closed.
--
-- MouseIconEnabled has no working changed signal, so this reasserts per frame while the menu is open.
--!mv:omit
local function GuardCursor()
    if not UIS.MouseIconEnabled then UIS.MouseIconEnabled = true end
end
--!mv:omit
local function SetCursor(show)
    if show and not cursorForced then
        cursorForced, savedMouseIcon = true, UIS.MouseIconEnabled
        UIS.MouseIconEnabled = true
        iconGuard = RunService.Heartbeat:Connect(GuardCursor)
    elseif not show and cursorForced then
        cursorForced = false
        if iconGuard then iconGuard:Disconnect(); iconGuard = nil end
        UIS.MouseIconEnabled = savedMouseIcon
    end
end
Root.Add(function() SetCursor(false) end)

--=====================================================================================
--  4. Animation
--=====================================================================================

-- ONE pill listens at a time -- the same single-slot rule the popup engine follows. A set would
-- leave two armed at once and bind both to the next key press.
-- ⚠ NOT weak-keyed, and none of these registries may be. Everything the hub builds lives under
-- gethui(), which is OUTSIDE the DataModel, so a parented-and-visible instance is not GC-rooted:
-- weak entries disappear on the next collection while the widget is still on screen. Every table
-- holding one of our Instances is strong and pruned on Destroying instead.
local KeybindRegistry, PendingBind = {}, nil
local SliderDragging = false
local V_THRESH, P_THRESH = 0.001, 0.001

local Motors = {}
local WakeTick
-- The `do` blocks in this file are not style: they keep SPRING_EPS and the fade walker out of the
-- enclosing scope, and the file runs close enough to Luau's 200-locals-per-function cap that
-- flattening one is a COMPILE error, not a slowdown.
--
-- Do NOT put a coefficient cache in front of this. Luau compiles math.exp to a fastcall, so a
-- critically damped solve is ~85ns and a lookup costs about what it saves.
local SpringCoeffs
do
local SPRING_EPS = 0.0001
-- Every branch reduces to the same pair of linear maps:
--     p1 = offset*A + v0*B + g   /   v1 = offset*C + v0*D
-- A..D depend only on freq, damping and dt, never on the component, so they are solved ONCE per
-- property -- a UDim2 would otherwise pay four math.exp calls a frame.
--
-- Damping is clamped to (0, 1] by Tween, so there is NO overdamped branch: every call site passes
-- nil, 1, 0.85, 0.78 or 0.62, and Tween is not exported.
--!mv:omit
function SpringCoeffs(freq, damp, dt)
    local f = freq * 6.283185307179586
    local decay = math.exp(-damp * f * dt)
    if damp == 1 then
        local fdt = f * dt
        return (1 + fdt) * decay, dt * decay, -(f * f * dt) * decay, (1 - fdt) * decay
    end
    -- Underdamped. y and z are the SAME quantity: z = sin(w*dt)/c, y = sin(w*dt)/w, w = f*c, so
    -- z = y*f exactly and one division does both. The guard is the sinc limit sin(x)/x -> 1.
    local c = math.sqrt(1 - damp * damp)
    local w = f * c
    local i = math.cos(w * dt)
    local y = w > SPRING_EPS and math.sin(w * dt) / w or dt
    local z = y * f
    return (i + damp * z) * decay, y * decay, -(z * f) * decay, (i - z * damp) * decay
end
end

local StepMotors
do
local SCRATCH = table.create(4)
-- Same rule StepFades follows: a done callback may start a NEW Tween, and adding a key to a table
-- being walked by next() is undefined. Collected here, fired after the walk. Reused buffer.
local MotorDone = {}
local MAX_STEP = 0.05
--!mv:omit
function StepMotors(dt)
    -- A frame hitch hands RenderStepped a dt of whole seconds. The underdamped branch would swing
    -- sin/cos through several periods in one step and the element visibly snaps past its goal, so
    -- a long frame is treated as one slow frame instead.
    if dt > MAX_STEP then dt = MAX_STEP end
    local fired = 0
    for obj, props in Motors do
        for prop, m in props do
            local settled, c = true, m.c
            local A, B, C, D = SpringCoeffs(m.f, m.d, dt)
            for i = 1, m.n do
                local b = (i - 1) * 3
                local g = c[b + 3]
                local offset, v0 = c[b + 1] - g, c[b + 2]
                local p, v = offset * A + v0 * B + g, offset * C + v0 * D
                if math.abs(v) < V_THRESH and math.abs(p - g) < P_THRESH then
                    p, v = g, 0
                else
                    settled = false
                end
                c[b + 1], c[b + 2] = p, v
                SCRATCH[i] = p
            end
            obj[prop] = m.k(SCRATCH)
            if settled then
                props[prop] = nil
                if m.done then fired += 1; MotorDone[fired] = m.done end
            end
        end
        if next(props) == nil then Motors[obj] = nil end
    end
    for i = 1, fired do
        local fn = MotorDone[i]
        MotorDone[i] = nil
        task.spawn(fn)
    end
end
end

--!mv:omit
local function CancelMotors(obj) Motors[obj] = nil end
-- Clears the motors and deliberately leaves the DRIVER running. Cleanups are reverse-ordered, so
-- the window's closing fade has already been started by the time this runs, and that fade now owns
-- the Destroy that lands when it finishes -- cutting the tick here would leave the window painted
-- on screen for good. It lets go on its own once the last fade drains.
Root.Add(function() table.clear(Motors) end)

local Library = {
    Theme = {
        Background = Color3.fromRGB(15, 14, 24), Sidebar = Color3.fromRGB(9, 9, 16), Section = Color3.fromRGB(27, 25, 40),
        Text = Color3.fromRGB(226, 223, 236), SubText = Color3.fromRGB(186, 182, 208), TabText = Color3.fromRGB(193, 189, 213), Placeholder = Color3.fromRGB(96, 92, 118),
        Desc = Color3.fromRGB(150, 145, 176),
        Accent = Color3.fromRGB(128, 120, 184), Active = Color3.fromRGB(156, 147, 210), Close = Color3.fromRGB(154, 150, 179),
        Stroke = Color3.fromRGB(42, 39, 60), WindowStroke = Color3.fromRGB(60, 55, 86), ToggleActive = Color3.fromRGB(28, 25, 43),
        Chip = Color3.fromRGB(32, 29, 47), ToggleBorder = Color3.fromRGB(82, 75, 122), InputFocus = Color3.fromRGB(30, 27, 44), DropdownOption = Color3.fromRGB(28, 26, 42), BindBackground = Color3.fromRGB(8, 8, 14), SliderTrack = Color3.fromRGB(13, 12, 21),
        Bad = Color3.fromRGB(188, 98, 105),
    },
    TabOrder = {},
}
local Theme = table.freeze(Library.Theme)

-- Widget registry, tab list, loop lists and popup ownership. Deliberately NOT fields on Library:
-- a game script or another injected script assigning over Library.Flags would strand every
-- widget's saved value, and clearing Library.OpenPopup would leave the click-catcher stuck on
-- with two lists open. Reach them through GetFlag/SetFlag/RegisterLoop instead.
local Private: { [string]: any } = {
    Flags = {}, Tabs = {}, Popup = nil, Gen = genv.SummitGen,
    Loops = { RenderStepped = {}, Heartbeat = {}, Stepped = {} },
}

local Tween
do
local DEC_GOAL, DEC_CUR = table.create(4), table.create(4)
local DECOMPOSE
do
-- Column 0 INSIDE the block on purpose: an indented --!mv:omit is not confirmed to attach, and Lua
-- does not care about the whitespace. Every one of these runs per Tween call, so all ten are named
-- rather than anonymous table fields -- a directive has nothing to attach to otherwise.
--!mv:omit
local function cNumber(c) return c[1] end
--!mv:omit
local function cColor3(c) return Color3.new(math.clamp(c[1], 0, 1), math.clamp(c[2], 0, 1), math.clamp(c[3], 0, 1)) end
--!mv:omit
local function cUDim2(c) return UDim2.new(c[1], c[2], c[3], c[4]) end
--!mv:omit
local function cUDim(c) return UDim.new(c[1], c[2]) end
--!mv:omit
local function cVector2(c) return Vector2.new(c[1], c[2]) end
--!mv:omit
local function dNumber(v, into) into[1] = v; return 1, cNumber end
--!mv:omit
local function dColor3(v, into) into[1], into[2], into[3] = v.R, v.G, v.B; return 3, cColor3 end
--!mv:omit
local function dUDim2(v, into)
    into[1], into[2], into[3], into[4] = v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset
    return 4, cUDim2
end
--!mv:omit
local function dUDim(v, into) into[1], into[2] = v.Scale, v.Offset; return 2, cUDim end
--!mv:omit
local function dVector2(v, into) into[1], into[2] = v.X, v.Y; return 2, cVector2 end
DECOMPOSE = { number = dNumber, Color3 = dColor3, UDim2 = dUDim2, UDim = dUDim, Vector2 = dVector2 }
end
--!mv:omit
local function Decompose(v, into)
    local fn = DECOMPOSE[typeof(v)]
    if not fn then return nil end
    return fn(v, into)
end

--!mv:omit
function Tween(obj, props, time, damping, onDone)
    local freq = math.clamp(1 / math.max(time or DEFAULT_TWEEN_TIME, 0.05), 2, 14)
    -- Clamped to (0, 1]. SpringCoeffs has no overdamped arm -- nothing has ever asked for one --
    -- and a damping of 0 is an undamped oscillator that never meets the settle threshold, so its
    -- motor would hold the driver on RenderStepped for the rest of the session.
    local damp = math.clamp(damping or 1, 0.05, 1)
    local reg = Motors[obj]
    if not reg then reg = {}; Motors[obj] = reg end
    -- onDone rides ONE motor. Every property in a call shares freq and damping, so they land on
    -- the same frame, and a retarget replaces the motor and drops the callback with it -- which is
    -- what every caller wants (a re-shown launcher must not run the hide's `Visible = false`).
    local pending = onDone
    for prop, goal in props do
        local cur = obj[prop]
        if cur == goal then
            reg[prop] = nil
        else
            local gn, kind = Decompose(goal, DEC_GOAL)
            local sn = Decompose(cur, DEC_CUR)
            if gn and sn and gn == sn then
                -- Both tables are REUSED when this property already has a motor, which is what a
                -- hover or a drag frame does every time. Velocity is read out of the slot before
                -- that slot is overwritten, so carrying it over survives the reuse.
                local m = reg[prop]
                local c = m and m.c
                if not c or #c ~= gn * 3 then c = table.create(gn * 3) end
                for i = 1, gn do
                    local b = (i - 1) * 3
                    local v0 = c[b + 2] or 0
                    c[b + 1], c[b + 2], c[b + 3] = DEC_CUR[i], v0, DEC_GOAL[i]
                end
                if m then
                    m.c, m.n, m.f, m.d, m.k, m.done = c, gn, freq, damp, kind, pending
                else
                    reg[prop] = { c = c, n = gn, f = freq, d = damp, k = kind, done = pending }
                end
                pending = nil
            else
                obj[prop] = goal
            end
        end
    end
    if pending then task.defer(pending) end
    if next(reg) == nil then
        Motors[obj] = nil
    else
        WakeTick()
    end
end
end

-- ⚠ A CanvasGroup would be the obvious way to fade the window as one image, and it DOES NOT WORK
-- HERE. GroupTransparency is applied by an offscreen pass that never runs under gethui() OR
-- CoreGui -- measured: the property reads back correctly and the group renders fully opaque. It
-- only composites under PlayerGui, which this library refuses (replicated, wiped on respawn).
-- Everything below is how the same look is reached without one.
local FADE_TIME = 0.22

-- How far ahead of the pane the CONTENTS run. Every element starts fading on the same frame, but
-- the interior clears first, so what you see is one object dissolving rather than a stack of
-- translucent sheets with the layout showing through it. Reversed automatically on the way back
-- in: the pane arrives first and the contents land on a solid surface.
local INNER_LEAD = 1.9

-- A snapshot is ONE FLAT array of (instance, property, resting value) triples plus `a`, the alpha
-- it currently sits at, so a fade always resumes where the last one left off. Scoped against the
-- 200-per-scope cap: the class table, the kind codes and the walker are used nowhere else.
do
local K_NONE, K_GUI, K_TEXT, K_IMAGE, K_SCROLL, K_STROKE = 0, 1, 2, 3, 4, 5
local KIND = {
    Frame = K_GUI, CanvasGroup = K_GUI, ViewportFrame = K_GUI, VideoFrame = K_GUI,
    TextLabel = K_TEXT, TextButton = K_TEXT, TextBox = K_TEXT,
    ImageLabel = K_IMAGE, ImageButton = K_IMAGE,
    ScrollingFrame = K_SCROLL, UIStroke = K_STROKE,
    UICorner = K_NONE, UIPadding = K_NONE, UIListLayout = K_NONE, UIGradient = K_NONE,
    UIScale = K_NONE, UISizeConstraint = K_NONE, UIFlexItem = K_NONE,
}
--!mv:omit
local function KindOf(inst)
    local cls = inst.ClassName
    local k = KIND[cls]
    if k == nil then
        if inst:IsA("UIStroke") then k = K_STROKE
        elseif not inst:IsA("GuiObject") then k = K_NONE
        elseif inst:IsA("ScrollingFrame") then k = K_SCROLL
        elseif inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then k = K_TEXT
        elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then k = K_IMAGE
        else k = K_GUI end
        KIND[cls] = k
    end
    return k
end

-- ⚠ A MOTOR STILL DRIVING ONE OF THESE PROPERTIES BREAKS THE FADE TWICE OVER, so take it off the
-- property here. Hover a row and move away, then hide the menu inside the 0.14s the Out tween
-- runs: the snapshot records that mid-tween value as the row's RESTING look, and the motor goes on
-- writing over the fade for the rest of its travel -- the widget that "fades away slightly later".
--
--
--!mv:omit
local function RestOf(v, prop, live)
    local reg = Motors[v]
    local m = reg and reg[prop]
    if not m then return live end
    reg[prop] = nil
    if next(reg) == nil then Motors[v] = nil end
    local goal = m.c[3]
    v[prop] = goal
    return goal
end

--!mv:omit
local function Capture(snap, n, v, kind)
    if kind == K_STROKE then
        local t = RestOf(v, "Transparency", v.Transparency)
        if t < 1 then snap[n + 1], snap[n + 2], snap[n + 3] = v, "Transparency", t; n += 3 end
        return n
    end
    local bg = RestOf(v, "BackgroundTransparency", v.BackgroundTransparency)
    if bg < 1 then snap[n + 1], snap[n + 2], snap[n + 3] = v, "BackgroundTransparency", bg; n += 3 end
    local prop, t
    if kind == K_TEXT then prop, t = "TextTransparency", v.TextTransparency
    elseif kind == K_IMAGE then prop, t = "ImageTransparency", v.ImageTransparency
    elseif kind == K_SCROLL then prop, t = "ScrollBarImageTransparency", v.ScrollBarImageTransparency
    else return n end
    t = RestOf(v, prop, t)
    if t < 1 then snap[n + 1], snap[n + 2], snap[n + 3] = v, prop, t; n += 3 end
    return n
end

--!mv:omit
local function Walk(inst, snap, n, skip)
    if skip and skip[inst] then return n end
    local kind = KindOf(inst)
    if kind ~= K_NONE then
        -- a UIStroke has no Visible of its own; it goes with whatever it is drawn on
        if kind ~= K_STROKE and not inst.Visible then return n end
        n = Capture(snap, n, inst, kind)
    end
    local kids = inst:GetChildren()
    for i = 1, #kids do n = Walk(kids[i], snap, n, skip) end
    return n
end

-- The caller MUST hold the returned array for the life of the animation; an Instance-keyed cache
-- loses entries mid-fade. `skip` leaves a subtree alone (the drag plate lives inside the window).
--!mv:omit
function Snapshot(root, skip, pane)
    local snap = table.create(1024)
    Walk(root, snap, 0, skip)
    snap.pane = pane            -- the handful of instances that fade at the base rate
    return snap
end
end

-- ONE RenderStepped driver for every fade in flight. Do NOT go back to a Tween per property: a
-- menu toggle allocates ~1800 of them on one frame and leaves all of them stepping.
local Fades = {}

--!mv:omit
local function WriteSnap(snap, alpha)
    if snap.a == alpha then return end
    snap.a = alpha
    -- No pane set (a toast, an unload) means the whole snapshot IS the object: everything runs at
    -- the base rate. Only a snapshot that named its pane splits into pane and contents, or a
    -- single-element fade would finish at 53% of its duration and sit invisible for the rest.
    local pane, inner = snap.pane, math.min(1, alpha * INNER_LEAD)
    for i = 1, #snap, 3 do
        local base = snap[i + 2]
        local a = (not pane or pane[snap[i]]) and alpha or inner
        snap[i][snap[i + 1]] = base + (1 - base) * a
    end
end

-- Completed callbacks run AFTER the traversal: one of them may start a new fade, and adding a key
-- to a table being walked by next() is undefined. Reused buffer, so a settling fade allocates nothing.
local FadeDone = {}

--!mv:omit
local function StepFades()
    local now, fired = os.clock(), 0
    for snap, f in Fades do
        local a = (now - f.t) / f.d
        if a >= 1 then
            a = 1
            Fades[snap] = nil
            if f.done then fired += 1; FadeDone[fired] = f.done end
        end
        a = 1 - (1 - a) * (1 - a)       -- Quad Out, matching the TweenInfo this replaced
        WriteSnap(snap, f.from + (f.to - f.from) * a)
    end
    for i = 1, fired do
        local fn = FadeDone[i]
        FadeDone[i] = nil
        fn()
    end
end

-- Liveness is read AFTER both steps: a completion callback that starts new work would otherwise
-- call WakeTick while this connection was still up, see nothing to do, and be cut by the
-- disconnect it had just raced. Deliberately NOT registered for cleanup -- every fade is finite so
-- this lets go within one, and cutting it would strand the closing fade that owns the final
-- Destroy.
do
local TickConn = nil
--!mv:omit
local function Tick(dt)
    StepMotors(dt)
    StepFades()
    if next(Motors) == nil and next(Fades) == nil then
        TickConn:Disconnect()
        TickConn = nil
    end
end
--!mv:omit
function WakeTick()
    if not TickConn then TickConn = RunService.RenderStepped:Connect(Tick) end
end
end

-- alpha 0 = resting, 1 = invisible. `time` omitted writes instantly. No Parent guard on the write:
-- a property write to a destroyed instance is a legal no-op, and the check cost a read per element.
--
--!mv:omit
function ApplySnapshot(snap, alpha, time, onDone)
    if not time or time <= 0 then
        Fades[snap] = nil
        WriteSnap(snap, alpha)
        if onDone then onDone() end
        return
    end
    Fades[snap] = { from = snap.a or 0, to = alpha, d = time, done = onDone, t = os.clock() }
    WakeTick()
end

--!mv:omit
function FadeOut(inst)
    if typeof(inst) ~= "Instance" or not inst.Parent then return end
    ApplySnapshot(Snapshot(inst), 1, FADE_TIME, function() pcall(function() inst:Destroy() end) end)
end

local MenuSnap, MenuGen, FadeBusy, FadePlan = nil, 0, false, nil

--!mv:omit
function PrimeFade(root, skip, pane) FadePlan = { root, skip, pane } end

-- ONLY on a transition that STARTS from the resting look -- a hide, or a drag grab. On the way
-- back in the window sits fully transparent, and re-reading records that as rest.
--!mv:omit
local function RefreshFade()
    if not FadePlan then return false end
    if not FadeBusy then
        ResetInteractives()     -- a button still under the cursor must not be captured hovered
        MenuSnap = Snapshot(FadePlan[1], FadePlan[2], FadePlan[3])
    end
    return MenuSnap ~= nil
end

--!mv:omit
function FadeVisible(inst, show)
    MenuGen += 1
    local gen = MenuGen
    if show then
        if not MenuSnap then inst.Visible = true; return end
        FadeBusy = true
        inst.Visible = true
        ApplySnapshot(MenuSnap, 1)
        ApplySnapshot(MenuSnap, 0, FADE_TIME, function()
            if gen == MenuGen then FadeBusy = false end
        end)
    else
        if not RefreshFade() then return end
        FadeBusy = true
        ApplySnapshot(MenuSnap, 1, FADE_TIME, function()
            if gen ~= MenuGen then return end
            FadeBusy = false
            inst.Visible = false
        end)
    end
end

--!mv:omit
function FadeWindowOut(time)
    MenuGen += 1
    if not RefreshFade() then return end
    FadeBusy = true
    ApplySnapshot(MenuSnap, 1, time)
end

--!mv:omit
function FadeWindowIn(time)
    MenuGen += 1
    local gen = MenuGen
    if not MenuSnap then return end
    ApplySnapshot(MenuSnap, 0, time, function()
        if gen == MenuGen then FadeBusy = false end
    end)
end

--=====================================================================================
--  5. Instance construction
--=====================================================================================

local CLASS_DEFAULTS = {
    Frame = { BorderSizePixel = 0 },
    ScrollingFrame = { BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent, ScrollBarImageTransparency = 0.5,
        TopImage = BAR_TOP, MidImage = BAR_MID, BottomImage = BAR_BOT, CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.Y },
    TextLabel = { BorderSizePixel = 0, BackgroundTransparency = 1, RichText = true, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Theme.Text },
    TextButton = { BorderSizePixel = 0, BackgroundTransparency = 1, RichText = true, AutoButtonColor = false, Text = "", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Theme.Text },
    TextBox = { BorderSizePixel = 0, BackgroundTransparency = 1, ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Theme.Text },
    ImageLabel = { BorderSizePixel = 0, BackgroundTransparency = 1 },
    ImageButton = { BorderSizePixel = 0, BackgroundTransparency = 1, AutoButtonColor = false },
}

--!mv:omit
local function Create(class, parent, props)
    local obj = Instance.new(class)
    local def = CLASS_DEFAULTS[class]
    if def then
        for k, v in def do
            if props[k] == nil then obj[k] = v end
        end
    end
    for k, v in props do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end

-- The one way a ScreenGui gets on screen: the toast layer, the window and the key gate all come
-- through here. Protect BEFORE parenting, the order every protector documents -- parent first and
-- a hider that reparents into its own container is undoing a write already made.
--!mv:omit
local function MountGui(name, displayOrder)
    local g = Create("ScreenGui", nil, { Name = name, ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = displayOrder })
    if HideGui then pcall(HideGui, g) end
    if not g.Parent then g.Parent = TargetGui end
    return g
end

--!mv:omit
local function Decorate(obj, corner, stroke, pad)
    if corner then Create("UICorner", obj, {CornerRadius = corner}) end
    local strokeObj
    -- Border mode: on a TextLabel/TextButton the default (Contextual) outlines the *glyphs*, not the frame
    if stroke then strokeObj = Create("UIStroke", obj, {Color = stroke[1], Transparency = stroke[2], Thickness = stroke[3] or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}) end
    if pad then
        Create("UIPadding", obj, { PaddingTop = UDim.new(0, pad[1] or 0), PaddingBottom = UDim.new(0, pad[2] or 0), PaddingLeft = UDim.new(0, pad[3] or 0), PaddingRight = UDim.new(0, pad[4] or 0) })
    end
    return obj, strokeObj
end

--!mv:omit
local function List(parent, padding, horizontal, align)
    return Create("UIListLayout", parent, {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, padding or 0),
        FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
        VerticalAlignment = horizontal and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top,
    })
end

local function Shadow(parent, spread, transparency, zindex)
    return Create("ImageLabel", parent, { Image = SHADOW_IMG, ScaleType = Enum.ScaleType.Slice, SliceCenter = SHADOW_SLICE,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, spread, 1, spread - 4),
        ImageColor3 = COLOR_BLACK, ImageTransparency = transparency, ZIndex = zindex or 0 })
end

local GLASS_LIFT, GLASS_FALL = Color3.fromRGB(64, 57, 101), Color3.fromRGB(5, 5, 10)

local function Glass(obj, lift, fall)
    -- LINEAR, and it has to be. UIGradient interpolates in 8-bit, so a band is however many
    -- pixels the ramp spends inside one integer step, and a band edge is only visible when it is
    -- WIDE. An eased curve spends its travel at the top and crawls across the bottom, which stripes
    -- the lower half; straight-line travel packs the same drop into tight bands. Roblox cannot
    -- dither a gradient, so edge spacing is the only lever there is.
    lift, fall = lift or 0.13, fall or 1.00
    local base = obj.BackgroundColor3
    obj.BackgroundColor3 = COLOR_WHITE
    Create("UIGradient", obj, { Rotation = 90, Color = ColorSequence.new(
        base:Lerp(GLASS_LIFT, lift), base:Lerp(GLASS_FALL, fall)) })
    return obj
end

local function EdgeGradient(stroke)
    local base = stroke.Color
    stroke.Color = COLOR_WHITE
    Create("UIGradient", stroke, { Rotation = 90, Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, base:Lerp(Theme.Active, 0.60)),
        ColorSequenceKeypoint.new(0.32, base:Lerp(Theme.Accent, 0.30)),
        ColorSequenceKeypoint.new(0.70, base),
        ColorSequenceKeypoint.new(1.00, base:Lerp(COLOR_BLACK, 0.55)),
    }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.00, 0.08),
            NumberSequenceKeypoint.new(0.45, 0.34),
            NumberSequenceKeypoint.new(1.00, 0.72),
        }) })
    return stroke
end

-- spec = { Over = {props}, Out = {props}, Down = {props}, Target = obj, Time = n, Enabled = fn }
-- Target is tweened instead of the button when given. Over/Out may be functions when the resting
-- look depends on state. Every hover pair MUST come through here: hiding the window means
-- MouseLeave never fires, and a hand-rolled pair leaves the hover stuck and snapshotted as rest.
-- Strong, for the reason on KeybindRegistry. ResetInteractives empties it on every pass, so it
-- cannot grow: an entry survives only between MouseEnter and the next leave or reset.
local HotTargets = {}
-- Over/Out may be functions when the resting look depends on state, so both go through here.
--!mv:omit
local function ResolveSpec(v) return type(v) == "function" and v() or v end
--!mv:omit
function ResetInteractives()
    for target, entry in HotTargets do
        HotTargets[target] = nil
        if target.Parent and (not entry.gate or entry.gate()) then
            CancelMotors(target)
            for prop, v in ResolveSpec(entry.out) do target[prop] = v end
        end
    end
end

--!mv:omit
local function Interactive(btn, spec)
    local target = spec.Target or btn
    local over, out, down, t = spec.Over, spec.Out, spec.Down, spec.Time or 0.14
    local gate = spec.Enabled
    --!mv:omit
    local function Allowed() return not gate or gate() end
    -- Plain fields, no closure: every interactive element in the hub built one otherwise, and the
    -- only reader is ResetInteractives, which can resolve `out` itself.
    local entry = out and { out = out, gate = gate } or nil

    if over then btn.MouseEnter:Connect(function()
        if not Allowed() then return end
        if entry then HotTargets[target] = entry end
        Tween(target, ResolveSpec(over), t)
    end) end
    if out then btn.MouseLeave:Connect(function()
        if not Allowed() then return end
        HotTargets[target] = nil
        Tween(target, ResolveSpec(out), t)
    end) end
    if down then
        btn.MouseButton1Down:Connect(function()
            if not Allowed() then return end
            if entry then HotTargets[target] = entry end
            Tween(target, ResolveSpec(down), t * 0.5)
        end)
        -- a spec with Down but neither Over nor Out has nothing to return to; Tween would be
        -- handed a nil property table and throw on release
        btn.MouseButton1Up:Connect(function()
            if not Allowed() then return end
            local back = ResolveSpec(over or out)
            if back then Tween(target, back, t) end
        end)
    end
    return btn
end

--=====================================================================================
--  6. Input & drag
--=====================================================================================

local function IsPress(t) return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch end
local function IsMove(t) return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch end

--!mv:omit
local function CaretFollow(box, clip)
    --!mv:omit
    local function Update()
        local pad, reveal = 2, clip.AbsoluteSize.X
        if not box:IsFocused() or box.TextBounds.X <= reveal - 2 * pad then
            box.Position = UDim2.fromOffset(pad, 0)
            return
        end
        local cur = box.CursorPosition
        if cur == -1 then return end
        local w = TextService:GetTextSize(box.Text:sub(1, cur - 1), box.TextSize, box.Font, Vector2.new(9e9, 9e9)).X
        local at = box.Position.X.Offset + w
        if at < pad then box.Position = UDim2.fromOffset(pad - w, 0)
        elseif at > reveal - pad - 1 then box.Position = UDim2.fromOffset(reveal - w - pad - 1, 0) end
    end
    box:GetPropertyChangedSignal("Text"):Connect(Update)
    box:GetPropertyChangedSignal("CursorPosition"):Connect(Update)
    box.Focused:Connect(Update)
    box.FocusLost:Connect(Update)
    Update()
end

local function ClippedBox(field, props)
    local clip = Create("Frame", field, { BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(1, -16, 1, 0) })
    props.Size, props.Position = UDim2.fromScale(1, 1), UDim2.fromOffset(2, 0)
    props.TextXAlignment = Enum.TextXAlignment.Left
    local box = Create("TextBox", clip, props)
    CaretFollow(box, clip)
    return box
end

local dragScope = Scope()
Root.Add(dragScope.Clean)
--!mv:omit
local function BeginDrag(onMove)
    dragScope.Clean()
    local latest
    --!mv:omit
    local function Note(i)
        if IsMove(i.UserInputType) then latest = i end
    end
    --!mv:omit
    local function Apply()
        if latest then local i = latest; latest = nil; onMove(i) end
    end
    dragScope.Add(UIS.InputChanged:Connect(Note))
    dragScope.Add(RunService.RenderStepped:Connect(Apply))
    dragScope.Add(UIS.InputEnded:Connect(function(i)
        if IsPress(i.UserInputType) then dragScope.Clean() end
    end))
    dragScope.Add(function() if latest then onMove(latest); latest = nil end end)
end

--!mv:omit
local function SetTopLeft(target, vp, x, y)
    local size, ap, pos = target.AbsoluteSize, target.AnchorPoint, target.Position
    target.Position = UDim2.new(pos.X.Scale, x + size.X * ap.X - vp.X * pos.X.Scale,
                                pos.Y.Scale, y + size.Y * ap.Y - vp.Y * pos.Y.Scale)
end

--!mv:omit
local function MakeDraggable(handle, target, onStart, onMoving)
    target = target or handle
    local dragStart, startTL, host, active, done
    handle.InputBegan:Connect(function(input)
        if not IsPress(input.UserInputType) then return end
        if onStart then onStart() end
        host = target.Parent
        startTL = target.AbsolutePosition - (host and host.AbsolutePosition or Vector2.new(0, 0))
        BeginDrag(function(i)
            -- Teardown already ran. Cleanups fire in reverse, so BeginDrag's trailing apply lands
            -- AFTER the release below has cleared `active` -- without this guard that last frame
            -- walks straight back into the start-of-drag branch and re-arms onMoving(true) with
            -- nothing left to pair it. On touch a move is always pending at lift.
            if done then return end
            local delta = i.Position - dragStart
            if not active and delta.Magnitude < 5 then return end
            if not active and onMoving then onMoving(true) end
            active = true
            local vp = host and host.AbsoluteSize or Vector2.new(1280, 720)
            local size = target.AbsoluteSize
            local x = math.clamp(startTL.X + delta.X, 100 - size.X, vp.X - 100)
            local y = math.clamp(startTL.Y + delta.Y, 0, vp.Y - 44)
            SetTopLeft(target, vp, x, y)
        end)
        -- AFTER BeginDrag, never before: it opens with dragScope.Clean(), which runs the previous
        -- gesture's teardown. Resetting `active` above that point clears the flag that teardown
        -- reads, so its onMoving(false) is skipped and the drag plate is left up with no gesture
        -- left to take it down. A second InputBegan mid-drag is routine on touch.
        dragStart, active, done = input.Position, false, false
        dragScope.Add(function()
            done = true
            if active and onMoving then onMoving(false) end
            active = false
        end)
    end)
end

--=====================================================================================
--  7. Notifications and observers
--=====================================================================================

local NotifyLive = {}
local NOTIFY_MAX, NotifyGui, NotifyHolder, NotifyOrder = 6, nil, nil, 0
local function EnsureNotify()
    if NotifyGui and NotifyGui.Parent then return end
    -- The cleanup closes over THIS gui, not the upvalue: a rebuild would otherwise leave the old
    -- entry pointing at the new layer, and every rebuild stacks another one on Root.
    local g = MountGui(Names.Toast, 10000)
    NotifyGui = g
    Root.Add(function() FadeOut(g) end)
    NotifyHolder = Create("Frame", NotifyGui, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.new(0, 318, 1, -40), BackgroundTransparency = 1 })
    Create("UIListLayout", NotifyHolder, { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 10) })
end

-- tall enough for L.Corner8 to resolve its full curve (needs >= 2x the radius); only the top 2px
-- is ever on screen
local BAR_BODY = 40

--!mv:omit
local function Graphemes(s)
    local n = 0
    for _ in utf8.graphemes(s) do n += 1 end
    return n
end
-- Seconds per grapheme, floored and capped: never a crawl on a paragraph, never a blink on
-- three words.
--!mv:omit
local function RevealTime(n) return math.clamp(n * 0.024, 0.18, 2.2) end

--!mv:omit
local function RevealText(label, time, onDone)
    local total = Graphemes(label.ContentText)
    if total == 0 then
        if onDone then onDone() end
        return function() end
    end
    time = time or RevealTime(total)
    -- TypewriteTime = 0 means "don't reveal", not a 0/0 divide: without this the first Step gets
    -- nan for its alpha and writes math.floor(nan) into an integer property.
    if time <= 0 then
        if onDone then onDone() end
        return function() end
    end
    label.MaxVisibleGraphemes = 0
    local conn, t0, dead = nil, os.clock(), false
    --!mv:omit
    local function stop(finish)
        if dead then return end
        dead = true
        if conn then conn:Disconnect(); conn = nil end
        -- -1 is "no limit". Leaving a COUNT behind would silently clip the next text this
        -- label is given.
        if finish then label.MaxVisibleGraphemes = -1 end
    end
    --!mv:omit
    local function Step()
        if not label.Parent then stop(false); return end
        local a = (os.clock() - t0) / time
        if a >= 1 then
            stop(true)
            if onDone then onDone() end
            return
        end
        label.MaxVisibleGraphemes = math.floor(total * a)
    end
    conn = RunService.Heartbeat:Connect(Step)
    return stop
end

function Library:Notify(cfg)
    EnsureNotify()
    local tint = cfg.Type == "error" and Theme.Bad or Theme.Accent
    NotifyOrder += 1
    local holder = Create("Frame", NotifyHolder, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = NotifyOrder })
    local card = Create("Frame", holder, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(1, 24, 0, 0),
        BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0.05, ClipsDescendants = true })
    Decorate(card, L.Corner8, {Theme.WindowStroke, 0.4, 1.2})
    Create("Frame", card, { Size = UDim2.new(0, 3, 1, -18), Position = UDim2.new(0, 9, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = tint })
    -- A 2px window onto a tall bar carrying the card's own corner radius, so the sliver follows the
    -- curve. ClipsDescendants clips to a RECTANGLE, so a plain full-width bar keeps square ends.
    local barClip = Create("Frame", card, { Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 1, ClipsDescendants = true })
    local bar = Create("Frame", barClip, { Size = UDim2.new(1, 0, 0, BAR_BODY), BackgroundColor3 = tint, BackgroundTransparency = 0.35 })
    Decorate(bar, L.Corner8)

    local body = Create("Frame", card, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -54, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
    List(body, 3)
    Create("UIPadding", body, { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) })
    Create("TextLabel", body, { Text = cfg.Title or CONFIG.HUB_NAME, Size = UDim2.new(1, 0, 0, 15), TextColor3 = Theme.Text, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 })
    local typing = cfg.Typewrite ~= false
    local content, sub
    if cfg.Content and cfg.Content ~= "" then
        content = Create("TextLabel", body, { Text = cfg.Content, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = Theme.SubText, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2 })
    end
    if cfg.SubContent and cfg.SubContent ~= "" then
        sub = Create("TextLabel", body, { Text = cfg.SubContent, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = Theme.Desc, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3 })
    end
    if typing and sub and content then sub.MaxVisibleGraphemes = 0 end

    local closed = false
    local cardSnap, stopReveal, barTween
    local entry = { Instance = holder }
    function entry.Close()
        if closed then return end
        closed = true
        if stopReveal then stopReveal(true); stopReveal = nil end
        -- Cancelled, not left to expire: a TweenService tween holds its instance alive for the
        -- rest of its duration, so a dismissed 60s toast would pin the card for 59 more.
        if barTween then barTween:Cancel(); barTween = nil end
        NotifyLive[entry] = nil
        holder.Size = UDim2.new(1, 0, 0, holder.AbsoluteSize.Y)
        holder.AutomaticSize = Enum.AutomaticSize.None
        ApplySnapshot(cardSnap, 1, 0.22)
        Tween(card, { Position = UDim2.new(1, 24, 0, 0) }, 0.22)
        local function Reap()
            if holder.Parent then holder:Destroy() end
        end
        Tween(holder, { Size = UDim2.new(1, 0, 0, 0) }, 0.3, 1, Reap)
    end
    -- cancel first: a reveal still in flight is holding a grapheme COUNT on this label, and writing
    -- new text under it would show only the first few characters of the new string
    function entry.SetContent(txt)
        if not content then return end
        if stopReveal then stopReveal(true); stopReveal = nil end
        -- The sub-line sits at 0 graphemes until the BODY's reveal finishes and hands over to it.
        -- Cancelling that reveal here kills the hand-over, so without this the SubContent stays
        -- invisible for the rest of the toast's life.
        if sub then sub.MaxVisibleGraphemes = -1 end
        content.Text = txt
    end

    local close = Create("TextButton", card, { Text = "×", Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12), TextColor3 = Theme.Placeholder, Font = Enum.Font.GothamMedium, TextSize = 18 })
    Interactive(close, { Over = { TextColor3 = COLOR_WHITE }, Out = { TextColor3 = Theme.Placeholder } })
    close.MouseButton1Click:Connect(entry.Close)

    NotifyLive[entry] = true
    holder.Destroying:Connect(function() NotifyLive[entry] = nil end)
    local live = 0
    for _ in NotifyLive do live += 1 end
    if live > NOTIFY_MAX then
        local oldest
        for e in NotifyLive do
            if e ~= entry and (not oldest or e.Instance.LayoutOrder < oldest.Instance.LayoutOrder) then oldest = e end
        end
        if oldest then oldest.Close() end
    end

    cardSnap = Snapshot(card)
    ApplySnapshot(cardSnap, 1)
    ApplySnapshot(cardSnap, 0, 0.34)
    Tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.34, 0.78)
    local dur = cfg.Duration
    if dur == nil then dur = 5 end
    if typing and (content or sub) then
        local tc = content and RevealTime(Graphemes(content.ContentText)) or 0
        local ts = sub and RevealTime(Graphemes(sub.ContentText)) or 0
        local total = tc + ts
        if total > 0 then
            local budget = cfg.TypewriteTime or (dur > 0 and math.min(total, dur * 0.7) or total)
            local k = budget / total
            tc, ts = tc * k, ts * k
        end
        local function typeSub() if sub then stopReveal = RevealText(sub, ts) end end
        if content then stopReveal = RevealText(content, tc, typeSub) else typeSub() end
    end
    if dur and dur > 0 then
        barTween = TweenService:Create(bar, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, BAR_BODY) })
        barTween:Play()
        task.delay(dur, entry.Close)
    else
        bar.Visible = false
    end
    return entry
end

-- NOTHING HERE CATCHES. A callback that throws goes red in F9 with the traceback rooted at the
-- throw site and stops the thread it was on: no toast, no warning, no retirement, no switch to
-- flip. task.spawn is NOT a net -- it means a callback that yields cannot hold the input handler
-- that fired it, and it starts inline, so ordering is the same as a direct call would give.
--
local function Spawn(fn, ...)
    if fn ~= nil then task.spawn(fn, ...) end
end

-- The ONE registry that may stay weak: it is keyed by the widget HANDLE, a plain Lua table, and
-- those are rooted normally. The gethui() problem applies to Instances only.
local Observers = setmetatable({}, { __mode = "k" })
local function CloneValue(v)
    return type(v) == "table" and table.clone(v) or v
end

local function AddObserver(handle, fn)
    local list = Observers[handle]
    if not list then list = {}; Observers[handle] = list end
    list[fn] = true
    return function() list[fn] = nil end
end
local function FireObservers(handle, value)
    local list = Observers[handle]
    if not list then return end
    for fn in list do task.spawn(fn, CloneValue(value)) end
end

--=====================================================================================
--  8. Icons
--=====================================================================================

local TAB_ICONS = { Player = "user", Visuals = "eye", Teleport = "map-pin", Combat = "swords", Settings = "settings", Misc = "layout-grid" }
local IconSets, PendingIcons = nil, {}
local IconMisses = {}
local function ApplyIcon(img, iconName, setName)
    if not IconSets then PendingIcons[#PendingIcons + 1] = { img, iconName, setName }; return end
    local set = IconSets[setName or "Lucide"]
    local id = set and set[iconName]
    img.Image = id and ("rbxassetid://" .. id) or ""
    if not id and next(IconSets) ~= nil and not IconMisses[iconName] then
        IconMisses[iconName] = true
        if not set then Warn("icon set %q does not exist", tostring(setName or "Lucide"))
        else Warn("icon %q is not in the %s set — names are lowercase and hyphenated",
                  tostring(iconName), tostring(setName or "Lucide")) end
    end
end

local ICON_URL, ICON_SCHEMA = "https://raw.nebulasoftworks.xyz/nebula-icon-library-loader", 1
local function ValidSets(sets)
    if type(sets) ~= "table" or type(sets.Lucide) ~= "table" or next(sets.Lucide) == nil then return nil end
    return sets
end
local function FlushIcons(sets)
    IconSets = sets
    for _, p in PendingIcons do
        local ok, err = pcall(ApplyIcon, p[1], p[2], p[3])
        if not ok then Warn("applying icon %q failed: %s", tostring(p[2]), tostring(err)) end
    end
    table.clear(PendingIcons)
end
task.spawn(function()
    task.wait()
    local cachedUrl
    local cacheFile = CONFIG.FOLDER .. "/icons.json"
    if isfile and readfile and isfile(cacheFile) then
        local ok, raw = pcall(readfile, cacheFile)
        if ok then
            local ok2, blob = pcall(HttpService.JSONDecode, HttpService, raw)
            if ok2 and type(blob) == "table" and blob.__v == ICON_SCHEMA then
                cachedUrl = blob.__src
                local sets = ValidSets(blob.sets)
                if sets then FlushIcons(sets) end
            end
        end
    end

    local ok, stub = pcall(game.HttpGet, game, ICON_URL)
    local innerUrl = ok and type(stub) == "string" and stub:match('HttpGet%(%s*["\']([^"\']+)["\']') or nil
    if IconSets and innerUrl and innerUrl == cachedUrl then return end

    local sets
    if not ok then
        Warn("icon library unreachable at %s: %s", ICON_URL, tostring(stub))
    else
        local ok2, fn = pcall(function() return loadstring(stub) end)
        if not ok2 or type(fn) ~= "function" then
            Warn("icon loader stub would not compile: %s", tostring(fn))
        else
            local ok3, result = pcall(fn)
            if not ok3 then Warn("icon loader threw: %s", tostring(result))
            else
                sets = ValidSets(result)
                if not sets then Warn("icon payload has no usable Lucide set") end
            end
        end
    end
    if sets then
        if writefile then
            local packs = {}
            for packName, tbl in sets do
                if type(tbl) == "table" then packs[packName] = tbl end -- helper functions can't be encoded
            end
            local okW, errW = pcall(function()
                writefile(cacheFile, HttpService:JSONEncode({ __v = ICON_SCHEMA, __src = innerUrl or ICON_URL, sets = packs }))
            end)
            if not okW then Warn("could not cache icons to %q: %s", cacheFile, tostring(errW)) end
        end
        if not IconSets then FlushIcons(sets) end
    elseif not IconSets then
        Warn("no icons available — every icon in the hub will be blank")
        FlushIcons({})
    end
end)

--=====================================================================================
--  9. Loops
--=====================================================================================

local LoopSignals = { RenderStepped = RunService.RenderStepped, Heartbeat = RunService.Heartbeat, Stepped = RunService.Stepped }
local LoopConnections = {}
-- loop.Func is called flat. A loop that throws goes red at the throw site and ends that frame's
-- pass where it stood; the loops behind it tick again next frame and the broken one keeps throwing
-- until it is fixed, which is the entire point of running without a net.
--!mv:omit
local function DispatchLoops(loops, ...)
    local n = #loops
    if n == 0 then return end
    local now, dead = os.clock(), nil
    for i = 1, n do
        local loop = loops[i]
        if loop.Removed then
            dead = dead or {}       -- swept after the pass so visit order stays registration order
            dead[#dead + 1] = i
        else
            local run, should, interval = loop.Active, loop.ShouldRun, loop.Interval
            if should then run = should() end
            if run and interval then
                if now - loop.Last < interval then run = false else loop.Last = now end
            end
            if run then loop.Func(...) end
        end
    end
    if dead then
        for i = #dead, 1, -1 do table.remove(loops, dead[i]) end
    end
end

function Library:RegisterLoop(loopType, func, shouldRun, interval)
    local list = Private.Loops[loopType]
    -- Named here rather than as "attempt to index nil" three frames deep. A widget's Loop.Type is
    -- a hand-typed string, so a wrong case is the usual way this arrives.
    if not list then
        error(("[%s] RegisterLoop: %q is not a loop type -- use RenderStepped, Heartbeat or Stepped")
            :format(CONFIG.HUB_NAME, tostring(loopType)), 0)
    end
    local entry = { Func = func, Active = true, ShouldRun = shouldRun, Interval = interval, Last = 0 }
    list[#list + 1] = entry
    if not LoopConnections[loopType] then
        LoopConnections[loopType] = true
        --!mv:omit
        local function Pump(...) DispatchLoops(list, ...) end
        Root.Add(LoopSignals[loopType]:Connect(Pump))
    end
    return entry
end
function Library:RemoveLoop(entry) if entry then entry.Removed = true end end
function Library:OnCleanup(fn) return Root.Add(fn) end

--=====================================================================================
--  10. Persistence
--=====================================================================================

local canFile = writefile and readfile and isfile
local configDirty, saverOn, loading = false, false, false
local SavedConfig = nil

-- `loading` suppresses dirty-marking while saved values are being pushed into widgets, and a
-- setter that throws on a corrupt saved value is now allowed to throw. Both restore paths below
-- therefore queue this before they call one: the throw is the report, but it must not leave the
-- hub silently unable to save for the rest of the session. Setters do not yield, so a deferred
-- release always lands after the span it is releasing.
local function EndLoading() loading = false end

local function RegisterFlag(flag, handle)
    if not flag then return end
    if Private.Flags[flag] then
        warn(("[%s] duplicate flag %q — the later widget wins and the earlier one stops saving. Pass a unique Flag."):format(CONFIG.HUB_NAME, flag))
    end
    Private.Flags[flag] = handle
    if SavedConfig ~= nil and SavedConfig[flag] ~= nil and not loading then
        -- One resumption later, NOT inline. Bind registers the flag before it returns, and a
        -- widget's Changed fan-out is whatever Bind hands back -- so a Set dispatched from here
        -- lands while `Changed` is still nil and the slider and dropdown throw on it. The value is
        -- captured now so a save landing in between cannot rewrite what gets restored.
        local value = SavedConfig[flag]
        task.defer(function()
            if Private.Flags[flag] ~= handle then return end
            loading = true
            task.defer(EndLoading)
            handle.Set(value)
            loading = false
        end)
    end
end
-- Only clears the slot if it is still OURS. Two widgets can end up sharing a flag (it warns, and
-- the later one wins); without this check destroying the FIRST unregisters the SECOND, which is
-- alive and now silently stops saving. Passing no handle clears unconditionally, for callers that
-- never held one.
local function UnregisterFlag(flag, handle)
    if not flag then return end
    if handle == nil or Private.Flags[flag] == handle then Private.Flags[flag] = nil end
end

function Library:SaveConfig()
    if not canFile then return end
    local data = SavedConfig or {}
    -- a getter that throws takes the save down with it rather than dropping one setting quietly
    for flag, h in Private.Flags do
        data[flag] = h.Get()
    end
    SavedConfig = data
    local ok, err = pcall(function()
        writefile(CONFIG.CONFIG_FILE, HttpService:JSONEncode(data))
    end)
    if not ok then Warn("could not save config to %q: %s", CONFIG.CONFIG_FILE, tostring(err)) end
end
local function MarkDirty(flag)
    if loading or not flag or not canFile then return end
    configDirty = true
    if saverOn then return end
    saverOn = true
    task.delay(2, function()
        saverOn = false
        if configDirty and Private.Gen == genv.SummitGen then
            configDirty = false
            Library:SaveConfig()
        end
    end)
end
function Library:LoadConfig()
    if not (canFile and isfile(CONFIG.CONFIG_FILE)) then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG.CONFIG_FILE)) end)
    if not ok or type(data) ~= "table" then
        -- Left on disk, not reset. The first SaveConfig overwrites it anyway (SavedConfig is still
        -- nil, so the merge starts from {}), and a writefile here is one more thing that can throw
        -- straight out of Init -- killing the whole hub over a recoverable bad file. Say what
        -- happened, or this reads as "the hub just stopped remembering anything".
        Warn("config at %q is unreadable — every saved setting is lost, and the next save replaces it: %s",
            CONFIG.CONFIG_FILE, tostring(data))
        return
    end
    SavedConfig = data
    loading = true
    task.defer(EndLoading)
    for flag, v in data do
        local h = Private.Flags[flag]
        if h then h.Set(v) end
    end
    loading = false
end

function Library:GetFlag(flag)
    local h = Private.Flags[flag]
    if not h then Warn("GetFlag(%q): no widget owns that flag", tostring(flag)); return nil end
    return CloneValue(h.Get())
end
function Library:SetFlag(flag, value)
    local h = Private.Flags[flag]
    if not h then Warn("SetFlag(%q): no widget owns that flag", tostring(flag)); return false end
    h.Set(value)
    return true
end

--=====================================================================================
--  10b. Premium gating
--=====================================================================================
--
--

Library.IsPremium = false
Library.PremiumState = "checking"        -- checking | free | premium | blocked

-- Strong and pruned on Destroying. Weak-keyed, these overlays were collected out from under
-- SyncGates, and buying premium mid-session leaves every widget still showing its lock.
local PremiumGates = {}
local PremiumHooks = {}
local AcceptedKey = nil

local function PremiumNag()
    if Library.PremiumState == "blocked" then
        if setclipboard then pcall(setclipboard, CONFIG.DISCORD) end
        Library:Notify({ Title = "Access revoked", Content = "This account is blocked from Premium.",
            SubContent = "Open a ticket if you think that's wrong — Discord copied to your clipboard.", Type = "error", Duration = 6 })
    elseif Library.PremiumState == "checking" then
        Library:Notify({ Title = "Premium only", Content = "Still checking your access — give it a second.",
            Type = "error", Duration = 6 })
    else
        if setclipboard then pcall(setclipboard, CONFIG.STORE) end
        Library:Notify({ Title = "Premium only", Content = "You have to be Premium to use this feature.",
            SubContent = "Get it at " .. (CONFIG.STORE:gsub("^%w+://", "")) .. " — link copied to your clipboard.",
            Type = "error", Duration = 6 })
    end
end

local function SyncGates()
    local unlocked = Library.IsPremium
    for overlay in PremiumGates do
        if overlay.Parent then
            overlay.Visible = not unlocked
            overlay.Active = not unlocked
        end
    end
end

function Library:SetPremium(value, state)
    value = not not value
    local changed = value ~= self.IsPremium
    self.IsPremium = value
    self.PremiumState = state or (value and "premium" or "free")
    SyncGates()
    local K = CONFIG.KEY
    if canFile and K.Enabled and K.SaveForPremiumOnly then
        if value and AcceptedKey then
            local ok, err = pcall(writefile, K.SaveFile, AcceptedKey)
            if not ok then Warn("could not save key to %q: %s", K.SaveFile, tostring(err)) end
        elseif not value and delfile and isfile(K.SaveFile) then
            local ok, err = pcall(delfile, K.SaveFile)
            if not ok then Warn("could not delete key file %q: %s", K.SaveFile, tostring(err)) end
        end
    end
    if changed then
        for fn in PremiumHooks do task.spawn(fn, value) end
    end
end
function Library:OnPremiumChanged(fn)
    if type(fn) ~= "function" then return function() end end
    PremiumHooks[fn] = true
    return function() PremiumHooks[fn] = nil end
end

local function Gate(host, props, corner)
    if not props.Premium then return end
    local pad = host:FindFirstChildOfClass("UIPadding")
    local pl = pad and pad.PaddingLeft.Offset or 0
    local pr = pad and pad.PaddingRight.Offset or 0
    local pt = pad and pad.PaddingTop.Offset or 0
    local pb = pad and pad.PaddingBottom.Offset or 0
    local overlay = Create("TextButton", host, { Size = UDim2.new(1, pl + pr, 1, pt + pb),
        Position = UDim2.fromOffset(-pl, -pt), BackgroundColor3 = COLOR_BLACK,
        BackgroundTransparency = 0.55, ZIndex = 60, Text = "" })
    Decorate(overlay, corner or L.Corner8)
    local ownText = host:IsA("TextButton") and host.Text ~= "" and host.TextXAlignment == Enum.TextXAlignment.Center
    local lock = Create("ImageLabel", overlay, { Size = UDim2.new(0, 16, 0, 16),
        AnchorPoint = ownText and Vector2.new(1, 0.5) or Vector2.new(0.5, 0.5),
        Position = ownText and UDim2.new(1, -(L.PadX + pr), 0.5, 0) or UDim2.fromScale(0.5, 0.5),
        ImageColor3 = COLOR_WHITE, ImageTransparency = 0.25, ZIndex = 61 })
    ApplyIcon(lock, "lock")
    overlay.MouseButton1Click:Connect(PremiumNag)
    PremiumGates[overlay] = true
    overlay.Destroying:Connect(function() PremiumGates[overlay] = nil end)
    overlay.Visible = not Library.IsPremium
    overlay.Active = not Library.IsPremium
    return overlay
end

--
local function RunPremiumCheck(attempts)
    local base = CONFIG.API
    attempts = math.max(1, attempts or CONFIG.API_ATTEMPTS or 2)

    if not base or base == "" or base:find("PASTE_") or base:find("CHANGE%-ME") then
        Library:SetPremium(false, "free")
        return
    end

    local url = base:gsub("/+$", "") .. "/premium?uid=" .. tostring(LocalPlayer.UserId)

    local why
    for attempt = 1, attempts do
        local ok, body = pcall(game.HttpGet, game, url)
        if not ok then why = tostring(body)
        elseif type(body) ~= "string" or #body == 0 then why = "empty response"
        else
            local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
            if decoded and type(data) == "table" then
                if data.blocked then
                    Library:SetPremium(false, "blocked")
                else
                    -- one boolean drives BOTH, or a truthy-but-not-true `premium` leaves the
                    -- state saying "premium" while IsPremium is false, and the nag copies nothing
                    local paid = data.premium == true
                    Library:SetPremium(paid, paid and "premium" or "free")
                end
                return
            end
            why = "not valid JSON: " .. tostring(data)
        end
        if attempt < attempts then task.wait(1.5 * attempt) end
    end

    Warn("premium check failed after %d attempt(s): %s", attempts, tostring(why))
    Library:SetPremium(false, "free")
end

local function StartPremiumCheck()
    task.spawn(RunPremiumCheck)
end

function Library:RegisterTab(name, builderFunc, subtitle, icon)
    table.insert(Private.Tabs, { Name = name, Build = builderFunc, Subtitle = subtitle, Icon = icon or TAB_ICONS[name] or "circle" })
end
function Library:BuildTabs(windowObj)
    for _, t in Private.Tabs do windowObj:MakeTab(t.Name, t.Subtitle, t.Icon, t.Build) end
end

--=====================================================================================
--  11. Rows, bindings, widget registry
--=====================================================================================

--------------------------------------------------------------------------- popup ownership
--
--  One overlay at a time, so ownership is a single slot: claiming evicts whoever held it. An owner
--  is any table with a Close(); the engine never reaches into its instances.

local function ReleasePopup(owner)
    if Private.Popup ~= owner then return end
    Private.Popup = nil
    if UI.Catcher then UI.Catcher.Visible = false end
end

local function ClaimPopup(owner)
    local prev = Private.Popup
    if prev == owner then return end
    -- installed before the eviction, not after: the outgoing Close() calls ReleasePopup, and if
    -- it still saw itself as owner it would hide the catcher the incoming popup needs
    Private.Popup = owner
    if prev then prev.Close() end
    if UI.Catcher then UI.Catcher.Visible = true end
end

local function CloseActivePopup()
    local cur = Private.Popup
    if cur then cur.Close() end
end

--------------------------------------------------------------------------- widget factory

local KEY_SHORT = {
    LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
    LeftAlt = "LAlt", RightAlt = "RAlt", LeftSuper = "LWin", RightSuper = "RWin",
    Backspace = "Bksp", CapsLock = "Caps", PageUp = "PgUp", PageDown = "PgDn", Delete = "Del",
    Insert = "Ins", Escape = "Esc", Return = "Enter", KeypadEnter = "NumEnter", PrintScreen = "PrtSc",
}
local function KeyLabel(k) return KEY_SHORT[k] or k end

--!mv:omit
local function Row(parent, props, activeState)
    local frame = Create("Frame", parent, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = activeState and Theme.ToggleActive or Theme.Section, BackgroundTransparency = 0.15 })
    local _, stroke = Decorate(frame, L.Corner8, {activeState and Theme.Active or Theme.Stroke, activeState and 0.2 or 0.55, 1})

    -- The content wrapper is required: full-row hit targets and the premium lock must be siblings of
    -- the layout, or the lock overlay becomes another flex column.
    local content = Create("Frame", frame, { BackgroundTransparency = 1, Position = UDim2.new(0, L.PadX, 0, 0),
        Size = UDim2.new(1, -L.PadX * 2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    Create("UIListLayout", content, { SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, L.RailGap) })
    -- A 15px title between two 15px pads is exactly the 45px minimum row, so the row holds its
    -- height without a UISizeConstraint.
    Create("UIPadding", content, { PaddingTop = UDim.new(0, L.PadY), PaddingBottom = UDim.new(0, L.PadY) })

    local desc = props.Description or props.Content
    local hasDesc = desc ~= nil and desc ~= ""
    local holder = hasDesc and Create("Frame", content, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }) or nil
    if holder then List(holder, L.LabelGap) end
    local nameLbl = Create("TextLabel", holder or content, { Text = props.Name or "", TextColor3 = Theme.SubText, Font = Enum.Font.GothamSemibold,
        TextSize = L.TitleSize, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 15), LayoutOrder = 1 })
    Create("UIFlexItem", holder or nameLbl, { FlexMode = Enum.UIFlexMode.Fill })
    if hasDesc then
        Create("TextLabel", holder, { Text = desc, TextColor3 = Theme.Desc, Font = Enum.Font.Gotham, TextSize = L.DescSize,
            TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
    end

    local rail
    local function Rail()
        if not rail then
            rail = Create("Frame", content, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2 })
            List(rail, L.RailGap, true, Enum.HorizontalAlignment.Right)
        end
        return rail
    end
    return frame, stroke, nameLbl, Rail
end

local function FlagFor(ctx, props) return props.Flag or (ctx.TabName .. "::" .. tostring(props.Name)) end

-- One definition of "premium widget the user has not paid for". Three copies of this expression
-- drifted apart once already -- the keybind's keyboard path was missing it entirely.
local function Locked(props) return props.Premium and not Library.IsPremium end

local function Bind(ctx, props, flag, getter, setter, extraFlags, loopEntry)
    local h: { [string]: any } = { Flag = flag, Get = getter, Set = setter, OnChanged = AddObserver }
    local slot = { Get = getter, Set = setter }
    RegisterFlag(flag, slot)

    local flags = { flag }
    if extraFlags then for _, f in extraFlags do flags[#flags + 1] = f end end
    local torn, extras = false, nil
    function h.AddTeardown(fn)
        extras = extras or {}
        extras[#extras + 1] = fn
    end
    function h.Teardown()
        if torn then return end
        torn = true
        for _, f in flags do UnregisterFlag(f, f == flag and slot or nil) end
        if loopEntry then Library:RemoveLoop(loopEntry) end
        if extras then
            for i = 1, #extras do extras[i]() end
            extras = nil
        end
    end
    function h.Destroy()
        h.Teardown()
        local inst = h.Row or h.Instance
        if inst and inst.Parent then inst:Destroy() end
    end

    return h, function(value)       -- Changed(value)
        MarkDirty(flag)
        local cb = props.Callback
        if cb and not Locked(props) then
            task.spawn(cb, CloneValue(value))
        end
        FireObservers(h, value)
    end
end

local function Expect(props, field, kind)
    local v = props[field]
    if v == nil then
        error(("[%s] %s is required"):format(CONFIG.HUB_NAME, field), 0)
    end
    if kind and typeof(v) ~= kind then
        error(("[%s] %s must be a %s, got %s"):format(CONFIG.HUB_NAME, field, kind, typeof(v)), 0)
    end
end

local Container = {}
Container.__index = Container

local function NewContainer(parent, tabName, page, window)
    return setmetatable({ Parent = parent, TabName = tabName, Page = page, Window = window }, Container)
end

-- Destroying a widget by any route must release its flag and stop its loop. Some widgets return a
-- bare Instance rather than a handle, and indexing one throws.
local function WireTeardown(h)
    if type(h) == "table" and h.Teardown and h.Instance then
        h.Instance.Destroying:Connect(h.Teardown)
    end
    return h
end

local function DefineWidget(kind, build)
    Container["Add" .. kind] = function(self, props)
        return WireTeardown(build(self, props or {}))
    end
end

--------------------------------------------------------------------------- control rows
--
--  ONE control per row, and the row is made for it: a label block on the left, a rail on the
--  right the control attaches into. The whole row is therefore the click target and is free to
--  light up with the control's state. `host` is built here rather than by each widget so every
--  control gets the same chrome.
--
--  The rail still takes more than one child -- a toggle's keybind pill sits beside its checkmark
--  -- but that pairing belongs to a single widget. There is no way to hang two independent
--  controls off one row, by design.

local function DefineControl(kind, build)
    Container["Add" .. kind] = function(self, props)
        props = props or {}
        local frame, stroke, nameLbl, Rail = Row(self.Parent, props, props.Active)
        Gate(frame, props)
        local h = WireTeardown(build(self, props, {
            Instance = frame, Stroke = stroke, NameLabel = nameLbl, Rail = Rail,
        }))
        if type(h) == "table" then
            h.Row = frame
        elseif h == nil then
            frame:Destroy()
        end
        return h
    end
end

--------------------------------------------------------------------------- keybind pill

-- Claiming the slot evicts whoever held it and puts their label back, so an abandoned pill can
-- never be left reading "..." with nothing listening on its behalf.
local function ArmBind(pill)
    local prev = PendingBind
    if prev and prev ~= pill then
        local b = KeybindRegistry[prev]
        if b then b.Render() end
        Tween(prev, {TextColor3 = Theme.SubText, BackgroundColor3 = Theme.BindBackground})
    end
    PendingBind = pill
    pill.Text = "..."
    Tween(pill, {TextColor3 = Theme.Accent, BackgroundColor3 = Theme.Section})
end

-- DESKTOP ONLY. Both call sites skip it on touch: a Toggle's pill would be a second way to hit a
-- row that is already tappable, and a standalone Keybind becomes a toggle plus a draggable button.
-- Because it never runs on a phone, `flag_bind` is never registered there and a phone session
-- cannot save "NONE" over the key the user set on PC.
--!mv:omit
local function BindPill(parent, props, action, saveId, canHold)
    local pill = Create("TextButton", parent, { Text = "", RichText = false, AutomaticSize = Enum.AutomaticSize.X,
        -- 5, ahead of the toggle ring's 10: the bind reads to the LEFT of the checkmark
        Size = UDim2.new(0, 0, 0, 22), LayoutOrder = 5,
        BackgroundColor3 = Theme.BindBackground, BackgroundTransparency = 0.5, TextColor3 = Theme.SubText, Font = Enum.Font.GothamBold, TextSize = 10 })
    Decorate(pill, L.Corner6, {Theme.Stroke, 0.7, 1}, {nil, nil, 10, 10})
    Create("UISizeConstraint", pill, { MinSize = Vector2.new(44, 22) })
    Interactive(pill, { Over = {BackgroundTransparency = 0.2}, Out = {BackgroundTransparency = 0.5}, Time = 0.15 })

    -- "NONE", never nil -- the same sentinel the clear path and Get() already use. An AddKeybind
    -- written without a Keybind prop otherwise concatenates nil in Render (taking the whole tab
    -- build down) and again in Get (taking every config save down with it).
    local entry = { Key = props.Keybind or "NONE", Action = action, Mode = "Toggle", CanHold = canHold }
    function entry.Render()
        pill.Text = KeyLabel(entry.Key) .. (entry.Mode == "Hold" and "  HOLD" or "")
    end
    entry.Render()
    KeybindRegistry[pill] = entry

    -- ⚠ DECLARED ABOVE THE HANDLER THAT READS IT. Below it, `slot` in the Destroying closure is a
    -- nil GLOBAL, not this local -- and UnregisterFlag(saveId, nil) then takes the unconditional
    -- path, evicting whichever widget owns the flag NOW. That is the exact case the handle
    -- argument exists to prevent.
    local slot

    -- the flag goes with it: a pill can be destroyed on its own, and one left pointing at a dead
    -- pill answers config saves with a stale "NONE"
    pill.Destroying:Connect(function()
        KeybindRegistry[pill] = nil
        if PendingBind == pill then PendingBind = nil end
        UnregisterFlag(saveId, slot)
    end)
    pill.MouseButton1Click:Connect(function() ArmBind(pill) end)
    if canHold then
        pill.MouseButton2Click:Connect(function()
            entry.Mode = entry.Mode == "Hold" and "Toggle" or "Hold"
            entry.Render()
            MarkDirty("keybind")
        end)
    end
    slot = {
        Get = function()
            local b = KeybindRegistry[pill]
            if not b then return "NONE" end
            return b.Mode == "Hold" and (b.Key .. "|hold") or b.Key
        end,
        Set = function(v)
            local b = KeybindRegistry[pill]
            if not b then return end
            v = tostring(v)
            local key, mode = v:match("^(.-)|(.+)$")
            b.Key = key or v
            b.Mode = (mode == "hold" and b.CanHold) and "Hold" or "Toggle"
            b.Render()
        end,
    }
    RegisterFlag(saveId, slot)
    return pill
end

--------------------------------------------------------------------------- static widgets

DefineWidget("Header", function(ctx, props)
    local text = type(props) == "string" and props or props.Name or props.Text or ""
    local header = Create("TextLabel", ctx.Parent, { Text = text, Size = UDim2.new(1, 0, 0, 24), TextColor3 = Theme.Accent,
        Font = Enum.Font.GothamBlack, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left })
    Decorate(header, nil, nil, {10, nil, L.PadX, nil})
    return header
end)

DefineWidget("Divider", function(ctx)
    local wrap = Create("Frame", ctx.Parent, { Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1 })
    Create("Frame", wrap, { Size = UDim2.new(1, -30, 0, 1), Position = UDim2.new(0, L.PadX, 0.5, 0), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.45 })
    return wrap
end)

--------------------------------------------------------------------------- buttons

local function BuildButton(parent, props, size)
    local btn = Create("TextButton", parent, { Text = props.Name, RichText = false, Size = size, BackgroundColor3 = props.Color or Theme.Section,
        BackgroundTransparency = 0.1, TextColor3 = Theme.SubText, Font = Enum.Font.GothamBold, TextSize = L.TitleSize, TextTruncate = Enum.TextTruncate.AtEnd })
    Create("UIPadding", btn, { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) })
    Decorate(btn, L.Corner8, {Theme.Stroke, 0.55, 1})
    Interactive(btn, {
        Over = { BackgroundTransparency = 0, TextColor3 = Theme.Text },
        Out = { BackgroundTransparency = 0.1, TextColor3 = Theme.SubText },
        Down = { BackgroundTransparency = 0.3 },
        Time = 0.15,
    })
    btn.MouseButton1Click:Connect(function() Spawn(props.Callback) end)
    Gate(btn, props)
    return btn
end

DefineWidget("Button", function(ctx, props)
    Expect(props, "Name")
    return BuildButton(ctx.Parent, props, UDim2.new(1, 0, 0, 40))
end)

DefineWidget("Buttons", function(ctx, list)
    local n, gap = #list, 8
    local row = Create("Frame", ctx.Parent, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 })
    List(row, gap, true)
    local made = {}
    for i, props in ipairs(list) do
        made[i] = BuildButton(row, props, UDim2.new(1 / n, -gap * (n - 1) / n, 1, 0))
        made[i].LayoutOrder = i
    end
    return made
end)

--------------------------------------------------------------------------- toggle

-- The 16px ring, its rim and the check glyph. Shared, so a mobile Keybind draws the same control
-- a Toggle does instead of a second copy that drifts away from it.
--
-- Coincident with the ring -- no inset, no centred position: size and a centred position round to
-- whole pixels independently, and the fill then wanders inside the border as UI Scale moves.
-- 16px box + 2.5px Border = 21px outer, deliberately under the keybind pill's 22: the solid rim
-- reads taller than the pill's 1px border, so matching 22 looks BIGGER. To make the check bolder,
-- grow the glyph, never the 16x16 footprint.
--!mv:omit
local function Checkbox(parent, on)
    local ring = Create("Frame", parent, { Size = UDim2.new(0, 16, 0, 16),
        BackgroundTransparency = 1, LayoutOrder = 10, Active = false, Selectable = false })
    local outline = Create("Frame", ring, { Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Active = false, Selectable = false })
    Decorate(outline, UDim.new(0.2, 0), {Theme.ToggleBorder, 0.05, 2.5})
    local tick = Create("ImageLabel", ring, { Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), ScaleType = Enum.ScaleType.Fit,
        ImageColor3 = Theme.Active, ImageTransparency = on and 0 or 1,
        Active = false, Selectable = false })
    ApplyIcon(tick, "check", "Symbols-Filled")
    return ring, tick
end

DefineControl("Toggle", function(ctx, props, host)
    Expect(props, "Name")
    local flag = FlagFor(ctx, props)
    local state = not not props.Default
    local frame, stroke, nameLbl = host.Instance, host.Stroke, host.NameLabel
    -- The whole row is the button. ZIndex 0, BELOW the row's content: Row() builds `content` first,
    -- so a full-row target added afterwards at the same ZIndex draws over it -- later sibling wins
    -- on a tie -- and swallows clicks meant for the keybind pill sharing the rail.
    local hit = Create("TextButton", frame, { Size = UDim2.fromScale(1, 1), ZIndex = 0 })

    local ring, tick = Checkbox(host.Rail(), state)

    local loopEntry
    if props.Loop then
        -- ShouldRun overrides Active in the dispatcher, so a premium loop can never tick while
        -- locked even if config restored the toggle to on
        local gated = props.Premium and function() return state and Library.IsPremium end or nil
        loopEntry = Library:RegisterLoop(props.Loop.Type or "RenderStepped", props.Loop.Func, gated, props.Loop.Interval)
        loopEntry.Active = state
    end

    local tickFade
    -- What the row DRAWS, which is not always what it stores. A locked premium toggle reads OFF
    -- however it was left: its callback is suppressed anyway, so showing it lit is a row claiming
    -- to do something it is not. `state` keeps the real value, so the setting still saves and comes
    -- straight back the moment premium lands.
    local function Shown() return state and not Locked(props) end

    local function ApplyVisual(animated)
        local on = Shown()
        if tickFade then tickFade:Cancel() end
        if animated then
            tickFade = TweenService:Create(tick, TICK_FADE, {ImageTransparency = on and 0 or 1})
            tickFade:Play()
        else
            tickFade = nil
            tick.ImageTransparency = on and 0 or 1
        end
        local fc = on and Theme.ToggleActive or Theme.Section
        local sc = on and Theme.Active or Theme.Stroke
        local tc = on and Theme.Text or Theme.SubText
        -- 0.55 off, matching what Row() gives every other inactive row. Both branches write it:
        -- when only the animated one did, a toggle built OFF sat at Row's 0.55 and dropped to 0.7
        -- the first time it was clicked, so its resting border changed after one interaction.
        local st = on and 0.2 or 0.55
        if animated then
            Tween(frame, {BackgroundColor3 = fc})
            Tween(stroke, {Color = sc, Transparency = st})
            Tween(nameLbl, {TextColor3 = tc}, 0.2)
        else
            frame.BackgroundColor3, nameLbl.TextColor3 = fc, tc
            stroke.Color, stroke.Transparency = sc, st
        end
    end

    local Changed
    local function SetState(v)
        v = not not v
        if state == v then return end
        state = v
        if loopEntry then
            loopEntry.Active = state
        end
        ApplyVisual(true)
        Changed(state)
    end

    local h
    h, Changed = Bind(ctx, props, flag, function() return state end, SetState,
        props.Keybind and { flag .. "_bind" } or nil, loopEntry)
    h.Instance, h.SetState, h.Loop = ring, SetState, loopEntry
    function h.SetTitle(t) nameLbl.Text = t end

    ApplyVisual(false)
    if Shown() then Spawn(props.Callback, state) end
    if props.Premium then
        h.AddTeardown(Library:OnPremiumChanged(function(on)
            ApplyVisual(true)
            if on and state then Spawn(props.Callback, state) end
        end))
    end
    hit.MouseButton1Click:Connect(function() SetState(not state) end)
    Interactive(hit, { Target = frame, Over = {BackgroundTransparency = 0.02}, Out = {BackgroundTransparency = 0.15}, Time = 0.12 })
    if props.Keybind and not IsMobile then
        BindPill(host.Rail(), props, function(down)
            if down == nil then SetState(not state) else SetState(down) end
        end, flag .. "_bind", true)
    end
    return h
end)

--------------------------------------------------------------------------- keybind

-- MOBILE ONLY. The TAP pills are extra buttons on a small screen and not everyone wants them, so
-- Settings can switch them off. The whole ROW goes, not just the pill: a keybind row is nothing but
-- its pill, and hiding one leaves a labelled row with no control, which reads as broken.
-- UIListLayout skips invisible children, so the rows around it close up.
--
-- MOBILE ONLY. A draggable button parked on the ScreenGui, OUTSIDE the window, so it stays on
-- screen while the menu is closed -- which is the whole point of it. Tapping fires; dragging moves
-- it and must NOT fire, so the move threshold is the same one the launcher badge uses.
local ActionButtons = 0
--!mv:omit
local function ActionButton(text, onFire)
    local gui = UI.Gui
    if not gui then return nil end
    ActionButtons += 1
    local holder = Create("Frame", gui, { Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X,
        Position = UDim2.new(0, 18, 0.34, (ActionButtons - 1) * 48), BackgroundTransparency = 1, ZIndex = 150 })
    local face = Create("TextButton", holder, { Text = text, RichText = false, Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Theme.Section, BackgroundTransparency = 0.08,
        TextColor3 = Theme.Text, Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 150 })
    Create("UIPadding", face, { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) })
    Decorate(face, L.Corner8, {Theme.Accent, 0.35, 1.4})
    Interactive(face, { Over = { BackgroundTransparency = 0 }, Out = { BackgroundTransparency = 0.08 },
                        Down = { BackgroundTransparency = 0.25 }, Time = 0.12 })

    local start, origin, moved
    face.InputBegan:Connect(function(input)
        if not IsPress(input.UserInputType) then return end
        start, moved = input.Position, false
        origin = holder.AbsolutePosition - gui.AbsolutePosition
        holder.Position = UDim2.fromOffset(origin.X, origin.Y)
        BeginDrag(function(i)
            local delta = i.Position - start
            if delta.Magnitude > 6 then moved = true end
            local vp = gui.AbsoluteSize
            holder.Position = UDim2.fromOffset(
                math.clamp(origin.X + delta.X, 4, math.max(4, vp.X - holder.AbsoluteSize.X - 4)),
                math.clamp(origin.Y + delta.Y, 4, math.max(4, vp.Y - holder.AbsoluteSize.Y - 4)))
        end)
    end)
    face.InputEnded:Connect(function(input)
        if IsPress(input.UserInputType) and not moved then onFire() end
    end)
    return holder
end

DefineControl("Keybind", function(ctx, props, host)
    Expect(props, "Name")
    local flag = FlagFor(ctx, props)
    -- ⚠ The premium check HAS to be in here. The lock overlay only stops clicks, and a keybind
    -- fires from the keyboard (and from the mobile button), neither of which touches it. Every
    -- other control gets this free from Bind's Changed; a Keybind has no value to bind.
    local function Fire(...)
        if Locked(props) then return end
        Spawn(props.Callback, ...)
    end

    if not IsMobile then
        local pill = BindPill(host.Rail(), props, Fire, flag .. "_bind", false)
        return { Instance = pill, Flag = flag .. "_bind" }
    end

    -- MOBILE: there is no key to bind, so the row is a plain toggle. On, it parks a draggable
    -- button on screen; off, that button goes away. The desktop key lives under `flag_bind` and is
    -- never registered here, so a phone session cannot save "NONE" over the key set on PC.
    local frame, stroke, nameLbl = host.Instance, host.Stroke, host.NameLabel
    local hit = Create("TextButton", frame, { Size = UDim2.fromScale(1, 1), ZIndex = 0 })
    local ring, tick = Checkbox(host.Rail(), false)
    local btn, state, Changed = nil, false, nil

    local function ApplyVisual(animated)
        local on = state and not Locked(props)
        if animated then Tween(tick, { ImageTransparency = on and 0 or 1 }, 0.15)
        else tick.ImageTransparency = on and 0 or 1 end
        local fc = on and Theme.ToggleActive or Theme.Section
        local sc = on and Theme.Active or Theme.Stroke
        local st = on and 0.2 or 0.55
        if animated then
            Tween(frame, { BackgroundColor3 = fc })
            Tween(stroke, { Color = sc, Transparency = st })
            Tween(nameLbl, { TextColor3 = on and Theme.Text or Theme.SubText }, 0.2)
        else
            frame.BackgroundColor3, nameLbl.TextColor3 = fc, on and Theme.Text or Theme.SubText
            stroke.Color, stroke.Transparency = sc, st
        end
        if on and not btn then btn = ActionButton(props.Name, Fire)
        elseif not on and btn then btn:Destroy(); btn = nil end
    end

    local function SetState(v)
        v = not not v
        if state == v then return end
        state = v
        ApplyVisual(true)
        Changed(state)
    end

    local h
    h, Changed = Bind(ctx, props, flag, function() return state end, SetState)
    h.Instance, h.SetState = ring, SetState
    h.AddTeardown(function() if btn then btn:Destroy(); btn = nil end end)
    if props.Premium then
        h.AddTeardown(Library:OnPremiumChanged(function() ApplyVisual(true) end))
    end
    state = not not props.Default
    ApplyVisual(false)
    hit.MouseButton1Click:Connect(function() SetState(not state) end)
    Interactive(hit, { Target = frame, Over = {BackgroundTransparency = 0.02}, Out = {BackgroundTransparency = 0.15}, Time = 0.12 })
    return h
end)

--------------------------------------------------------------------------- slider

DefineControl("Slider", function(ctx, props, host)
    Expect(props, "Name")
    local min, max = props.Min or 0, props.Max or 100
    -- math.clamp THROWS when min > max, from inside Round, naming neither the widget nor the cause
    if max < min then
        error(("[%s] %s: Max (%s) is below Min (%s)"):format(CONFIG.HUB_NAME, tostring(props.Name), tostring(max), tostring(min)), 0)
    end
    local span = max - min
    if span == 0 then span = 1 end

    -- Step quantises to real increments (5, 0.25, ...). Precision is inferred by counting the
    -- digits the step needs, so Step = 0.25 formats to 2dp.
    local step = tonumber(props.Step)
    if step and step <= 0 then step = nil end
    local function DigitsFor(v)
        for d = 0, 6 do
            local m = 10 ^ d
            if math.abs(v * m - math.round(v * m)) < 1e-9 then return d end
        end
        return 6
    end
    local decimals = math.clamp(props.Int and 0 or props.Decimals or (step and DigitsFor(step)) or 0, 0, 6)
    local fmtStr, mult = "%." .. decimals .. "f", 10 ^ decimals
    --!mv:omit
    local function Round(v)
        v = math.clamp(v, min, max)
        if step then v = math.clamp(min + math.round((v - min) / step) * step, min, max) end
        return math.round(v * mult) / mult
    end

    local default = Round(props.Default or min)
    local rail = host.Rail()

    local valText = Create("TextBox", rail, { Text = string.format(fmtStr, default), Size = UDim2.new(0, 58, 0, 18), LayoutOrder = 39,
        TextColor3 = Theme.Accent, Font = Enum.Font.GothamBold, TextSize = L.TitleSize,
        TextXAlignment = Enum.TextXAlignment.Right, ClearTextOnFocus = true })
    local track = Create("Frame", rail, { Size = UDim2.new(0, 150, 0, 6), LayoutOrder = 40, BackgroundColor3 = Theme.SliderTrack })
    Decorate(track, L.Corner6)
    local fill = Create("Frame", track, { Size = UDim2.new((default - min) / span, 0, 1, 0), BackgroundColor3 = Theme.Accent })
    Decorate(fill, L.Corner6)
    local GRAB = 12
    --!mv:omit
    local function GrabPos(frac) return UDim2.new(frac, (0.5 - frac) * GRAB, 0.5, 0) end
    -- inert on purpose: the knob must never hit-test, or it eats the press it is sitting on top of
    local grab = Create("Frame", track, { Size = UDim2.new(0, GRAB, 0, GRAB), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = GrabPos((default - min) / span), BackgroundColor3 = COLOR_WHITE, ZIndex = 2,
        Active = false, Selectable = false })
    Decorate(grab, L.Pill, {Theme.Accent, 0.4, 1.5})

    local current, Changed = default, nil
    local function Get() return current end
    --!mv:omit
    local function Apply(v, fire, instant)
        v = Round(v)
        if instant and v == current then return v end
        current = v
        valText.Text = string.format(fmtStr, v)
        local frac = (v - min) / span
        local sz, gp = UDim2.new(frac, 0, 1, 0), GrabPos(frac)
        if instant then
            CancelMotors(fill); CancelMotors(grab)
            fill.Size, grab.Position = sz, gp
        else
            Tween(fill, {Size = sz}, 0.1)
            Tween(grab, {Position = gp}, 0.1)
        end
        if fire then Changed(v) end
        return v
    end
    local function Set(v) return Apply(v, true) end

    local h
    h, Changed = Bind(ctx, props, FlagFor(ctx, props), Get, Set)
    h.Instance = track

    valText.Focused:Connect(function() Tween(valText, {TextColor3 = Theme.Text}, 0.15) end)
    valText.FocusLost:Connect(function()
        Tween(valText, {TextColor3 = Theme.Accent}, 0.15)
        local num = tonumber((valText.Text:gsub(",", ".")))
        if num then Apply(num, true) else valText.Text = string.format(fmtStr, current) end
    end)

    --!mv:omit
    local function StartDrag(input)
        if not IsPress(input.UserInputType) then return end
        local originX, width = track.AbsolutePosition.X, math.max(track.AbsoluteSize.X, 1)
        local fine, refX, refVal = false, 0, current
        --!mv:omit
        local function fromInput(i)
            local held = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
            if held ~= fine then fine, refX, refVal = held, i.Position.X, current end
            local v
            if fine then
                v = refVal + ((i.Position.X - refX) / width) * span * 0.15
            else
                v = min + math.clamp((i.Position.X - originX) / width, 0, 1) * span
            end
            Apply(v, true, true)
        end
        fromInput(input)
        BeginDrag(fromInput)
        SliderDragging = true
        -- on touch the page would otherwise scroll out from under the finger mid-drag
        local page = ctx.Page
        if page then page.ScrollingEnabled = false end
        dragScope.Add(function()
            SliderDragging = false
            if page then page.ScrollingEnabled = true end
        end)
    end
    track.InputBegan:Connect(StartDrag)
    return h
end)

--------------------------------------------------------------------------- dropdown
--
--  Every dropdown shares ONE list panel, built on the first open and re-bound to whoever claims it.
--  The list is VIRTUALISED: a fixed window of absolutely-positioned rows re-stamped as it scrolls,
--  with CanvasSize set from the row count. Drop.Map holds slot -> option index and is read at call
--  time, so a slot's handlers are allocated once and still act on whatever it currently shows.

-- Ranked match: a literal hit always outscores a scattered one, and typing initials still finds
-- the row. Both halves reward a hit at a word start, because that is what someone is usually
-- aiming at. Scores only have to be comparable within one list -- never store or compare them
-- across lists.
--!mv:omit
local function FuzzyScore(text, q)
    if q == "" then return true, 0 end
    local at = text:find(q, 1, true)
    if at then
        local boundary = at == 1 or text:sub(at - 1, at - 1):match("[%s%p_]") ~= nil
        return true, 1e5 - at + (boundary and 500 or 0) + #q * 5
    end
    local tn, qn = #text, #q
    if qn > tn then return false, 0 end
    local qi, score, run, last = 1, 0, 0, 0
    for ti = 1, tn do
        if qi > qn then break end
        if text:sub(ti, ti) == q:sub(qi, qi) then
            local boundary = ti == 1 or text:sub(ti - 1, ti - 1):match("[%s%p_]") ~= nil
            run = (last == ti - 1) and run + 1 or 1
            score += 1 + (boundary and 6 or 0) + math.min(run - 1, 5) * 3
            last, qi = ti, qi + 1
        end
    end
    if qi <= qn then return false, 0 end            -- a query character was never reached, in order
    return true, score - (last - qn) * 0.05         -- tighter matches edge out sprawling ones
end

local DROP_MAX, SEARCH_H = 224, 36
local DROP_ROW, DROP_GAP = 32, 4
local DROP_STEP = DROP_ROW + DROP_GAP
local DROP_LIST_H = DROP_MAX - SEARCH_H - 12
local DROP_SLOTS = math.ceil(DROP_LIST_H / DROP_STEP) + 2
local Drop

--!mv:omit
local function DropSlot(si)
    local S = Drop
    local b = Create("TextButton", S.List, { Text = "", RichText = false, Size = UDim2.new(1, 0, 0, DROP_ROW),
        BackgroundColor3 = Theme.DropdownOption, BackgroundTransparency = 0.15, Font = Enum.Font.Gotham, TextSize = 13,
        TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 202 })
    Decorate(b, L.Corner6, nil, {nil, nil, 14, 8})
    local bar = Create("Frame", b, { Size = UDim2.new(0, 3, 0, 0), Position = UDim2.new(0, -9, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.Accent, ZIndex = 203 })
    Decorate(bar, L.Pill)
    -- resting look depends on selection, so Out is a function; going through Interactive is what
    -- keeps the hover from sticking when the window hides out from under the cursor
    Interactive(b, {
        Over = { BackgroundTransparency = 0, TextColor3 = Theme.Text },
        Out = function()
            local o, idx = S.Owner, S.Map[si]
            local sel = o ~= nil and idx ~= nil and o.IsSel(idx)
            return { BackgroundTransparency = sel and 0 or 0.15, TextColor3 = sel and Theme.Active or Theme.SubText }
        end,
        Time = 0.15,
    })
    b.MouseButton1Click:Connect(function()
        local o, idx = S.Owner, S.Map[si]
        if o and idx then o.Pick(idx) end
    end)
    S.Slots[si], S.Bars[si] = b, bar
    return b
end

--!mv:omit
local function DropRender()
    local S = Drop
    local o = S.Owner
    if not o then return end
    local list, view = S.Filtered, S.List
    local n = #list
    -- Clamped to the last full window: CanvasPosition can sit past it, and an unclamped index renders
    -- the list empty at the bottom of a long scroll.
    local maxFirst = math.max(1, n - DROP_SLOTS + 1)
    local first = math.clamp(math.floor(view.CanvasPosition.Y / DROP_STEP) + 1, 1, maxFirst)
    for si = 1, DROP_SLOTS do
        local idx = first + si - 1
        local b = S.Slots[si]
        if idx <= n then
            b = b or DropSlot(si)
            local opt = list[idx]
            S.Map[si] = opt
            b.Text = o.TextAt(opt)
            b.Position = UDim2.fromOffset(0, (idx - 1) * DROP_STEP)
            local sel = o.IsSel(opt)
            b.BackgroundTransparency = sel and 0 or 0.15
            b.TextColor3 = sel and Theme.Active or Theme.SubText
            S.Bars[si].Size = UDim2.new(0, 3, 0, sel and 15 or 0)
            b.Visible = true
        elseif b then
            b.Visible = false
            S.Map[si] = nil
        end
    end
    view.CanvasSize = UDim2.new(0, 0, 0, n * DROP_STEP)
end

local function DropSurface()
    if Drop and Drop.Portal.Parent then return Drop end
    local portal = Create("Frame", UI.Gui, { BackgroundTransparency = 1, Visible = false, ZIndex = 200, Size = UDim2.fromOffset(160, 100) })
    local pScale = Create("UIScale", portal, { Scale = 1 })
    Shadow(portal, 56, 0.5, 199)
    local panel = Create("Frame", portal, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0.02, ZIndex = 200 })
    Decorate(panel, L.Corner8, {Theme.WindowStroke, 0.35, 1.2})
    local searchBox = Create("TextBox", panel, { Text = "", PlaceholderText = "Search...", Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 6),
        BackgroundColor3 = Theme.BindBackground, BackgroundTransparency = 0.35, TextColor3 = Theme.Text, PlaceholderColor3 = Theme.Placeholder, TextSize = 12, ZIndex = 201 })
    Decorate(searchBox, L.Corner6, {Theme.Stroke, 0.7, 1}, {nil, nil, 10, 10})
    -- AutomaticCanvasSize off: the rows are absolutely positioned, so the canvas is ours to set
    local optionFrame = Create("ScrollingFrame", panel, { Size = UDim2.new(1, -8, 1, -(12 + SEARCH_H)),
        Position = UDim2.fromOffset(4, 6 + SEARCH_H), BackgroundTransparency = 1, ZIndex = 201,
        AutomaticCanvasSize = Enum.AutomaticSize.None })
    Create("UIPadding", optionFrame, { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6) })

    Drop = { Portal = portal, Scale = pScale, Search = searchBox, List = optionFrame,
             Slots = {}, Bars = {}, Map = {}, Filtered = {}, Score = {} }
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local o = Drop.Owner
        if o then o.Filter(); o.Reflow() end
    end)
    optionFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(DropRender)
    return Drop
end

DefineControl("Dropdown", function(ctx, props, host)
    Expect(props, "Name")
    local multi = props.Multi
    local chosen, built = {}, {}
    do
        local d = props.Default
        if d == nil and not multi and props.Options then d = props.Options[1] end
        if type(d) == "table" then for _, v in ipairs(d) do chosen[tostring(v)] = true end
        elseif d ~= nil then chosen[tostring(d)] = true end
    end

    local row, rail = host.Instance, host.Rail()
    local opener = Create("TextButton", rail, { Size = UDim2.new(0, 164, 0, 22), LayoutOrder = 50 })
    local header = Create("TextButton", row, { Size = UDim2.fromScale(1, 1), ZIndex = 0 })
    local valLbl = Create("TextLabel", opener, { Text = "", RichText = false, Size = UDim2.new(1, -20, 1, 0),
        TextColor3 = Theme.SubText, Font = Enum.Font.Gotham, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
    local chev = Create("ImageLabel", opener, { Size = UDim2.new(0, 14, 0, 14), AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), ImageColor3 = Theme.SubText })
    ApplyIcon(chev, "chevron-down")

    local me, Changed = {}, nil
    --!mv:omit
    local function IsOwner() return Drop ~= nil and Drop.Owner == me end

    -- wired to the row's AbsolutePosition while the list is open, so it fires per frame for as
    -- long as the window is moving underneath it
    --!mv:omit
    local function Reflow()
        if not IsOwner() then return end
        local S = Drop
        local sc = math.max(UI.Scale.Scale, 0.01)
        S.Scale.Scale = sc
        local rows = #S.Filtered
        local h = math.clamp(rows * DROP_STEP + 14 + SEARCH_H, 44 + SEARCH_H, DROP_MAX)
        local gui = UI.Gui
        local origin, abs, size = gui.AbsolutePosition, row.AbsolutePosition, row.AbsoluteSize
        local lx, ly, vpY = abs.X - origin.X, abs.Y - origin.Y, gui.AbsoluteSize.Y
        S.Portal.Size = UDim2.fromOffset(size.X / sc, h)
        local below, scaled = ly + size.Y + 6, h * sc
        if below + scaled > vpY - 10 and ly - scaled - 6 > 10 then
            S.Portal.Position = UDim2.fromOffset(lx, ly - scaled - 6)
        else
            S.Portal.Position = UDim2.fromOffset(lx, math.min(below, math.max(10, vpY - scaled - 10)))
        end
    end

    local openConn
    local function Close()
        if not IsOwner() then return end
        Drop.Portal.Visible = false
        Drop.Owner = nil
        if openConn then openConn:Disconnect(); openConn = nil end
        Tween(chev, {Rotation = 0}, 0.18)
        ReleasePopup(me)
    end

    local function Values()
        local out, seen = {}, {}
        for _, opt in built do
            if chosen[opt] then out[#out + 1] = opt; seen[opt] = true end
        end
        -- The tail is a HASH walk with no stable order, so it is sorted: unsorted, the label reads
        -- "B, A" one run and "A, B" the next, and the saved config churns for no reason.
        local tail = {}
        for k in chosen do if not seen[k] then tail[#tail + 1] = k end end
        table.sort(tail)
        table.move(tail, 1, #tail, #out + 1, out)
        return out
    end
    local function Display()
        local vals = Values()
        valLbl.Text = #vals > 0 and table.concat(vals, ", ") or "None"
        return vals
    end
    --!mv:omit
    local function ApplyFilter()
        if not IsOwner() then return end
        local S = Drop
        -- Spaces come out of the QUERY only, never the option text: "live pl" and "livepl" should
        -- reach the same row, and the subsequence pass is what closes the gap.
        local q = S.Search.Text:lower():gsub("%s+", "")
        table.clear(S.Filtered)
        if q == "" then
            for i = 1, #built do S.Filtered[i] = i end
        else
            local score = S.Score
            table.clear(score)
            for i = 1, #built do
                local hit, sc = FuzzyScore(built[i]:lower(), q)
                if hit then S.Filtered[#S.Filtered + 1] = i; score[i] = sc end
            end
            table.sort(S.Filtered, function(a, b)
                if score[a] ~= score[b] then return score[a] > score[b] end
                return a < b
            end)
        end
        S.List.CanvasPosition = Vector2.new(0, 0)
        DropRender()
    end
    local function Get()
        local vals = Values()
        return multi and vals or (vals[1] or "")
    end
    local function Select(opt, fire)
        local k = tostring(opt)
        if multi then
            chosen[k] = (not chosen[k]) or nil
        else
            table.clear(chosen)
            chosen[k] = true
        end
        local vals = Display()
        if IsOwner() then DropRender() end
        if not multi then Close() end
        if fire then Changed(multi and vals or (vals[1] or "")) end
    end

    local function Refresh()
        local src = props.Populate and props.Populate() or props.Options or {}
        -- copied on ingest: a caller keeping its Options array and mutating it later must not be
        -- able to reshape a list this widget has already committed to
        local n = #src
        for i = 1, n do built[i] = tostring(src[i]) end
        for i = #built, n + 1, -1 do built[i] = nil end
        Display()
        if IsOwner() then ApplyFilter(); Reflow() end
    end
    Refresh()

    local function SetValue(v)
        table.clear(chosen)
        if type(v) == "table" then for _, x in ipairs(v) do chosen[tostring(x)] = true end
        elseif v ~= nil then chosen[tostring(v)] = true end
        Display()
        if IsOwner() then DropRender() end
        Changed(Get())
    end

    function me.IsSel(i) return chosen[built[i]] == true end
    function me.TextAt(i) return built[i] or "" end
    function me.Pick(i) if built[i] then Select(built[i], true) end end
    function me.Filter() ApplyFilter() end
    --!mv:omit
    function me.Reflow() Reflow() end
    me.Close = Close

    local function Open()
        if IsOwner() then Close(); return end
        local S = DropSurface()
        ClaimPopup(me)
        S.Owner = me
        S.Search.Text = ""
        Refresh()   -- Owner is set by now, so Refresh itself filters and reflows
        S.Portal.Visible = true
        openConn = row:GetPropertyChangedSignal("AbsolutePosition"):Connect(Reflow)
        Tween(chev, {Rotation = 180}, 0.18)
    end

    local h
    h, Changed = Bind(ctx, props, FlagFor(ctx, props), Get, SetValue)
    h.Instance, h.Refresh, h.Close = opener, Refresh, Close

    row.Destroying:Connect(Close)
    opener.MouseButton1Click:Connect(Open)
    header.MouseButton1Click:Connect(Open)
    Interactive(header, { Target = row, Over = {BackgroundTransparency = 0.02}, Out = {BackgroundTransparency = 0.15}, Time = 0.12 })
    return h
end)

--------------------------------------------------------------------------- section

function Container:AddSection(title, startClosed)
    -- Sections do not nest. One level is the whole grouping model: a tab holds sections, a section
    -- holds widgets. Said out loud rather than silently building a second level nobody styled for.
    if self.IsSection then
        error(("[%s] sections do not nest -- put these widgets on the tab, or in one section")
            :format(CONFIG.HUB_NAME), 0)
    end
    local open = not startClosed
    local box = Create("Frame", self.Parent, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0.45 })
    Decorate(box, L.Corner8, {Theme.Stroke, 0.6, 1}, {12, 14, 12, 12})
    List(box, 12)
    local head = Create("TextButton", box, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0 })
    local chev = Create("ImageLabel", head, { Size = UDim2.new(0, 13, 0, 13), Position = UDim2.new(0, 4, 0.5, -6), ImageColor3 = Theme.SubText, Rotation = open and 0 or -90 })
    ApplyIcon(chev, "chevron-down")
    local lbl = Create("TextLabel", head, { Text = tostring(title):upper(), Size = UDim2.new(1, -30, 1, 0), Position = UDim2.new(0, 24, 0, 0),
        TextColor3 = Theme.SubText, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
    local body = Create("Frame", box, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = open, LayoutOrder = 1 })
    List(body, 8)

    local function SetOpen(v)
        v = not not v
        open = v
        body.Visible = v
        if not v then CloseActivePopup() end
        Tween(chev, { Rotation = v and 0 or -90 }, 0.15)
    end
    head.MouseButton1Click:Connect(function() SetOpen(not open) end)
    Interactive(head, { Target = lbl, Over = {TextColor3 = Theme.Text}, Out = {TextColor3 = Theme.SubText}, Time = 0.12 })

    local sub = NewContainer(body, self.TabName, self.Page, self.Window)
    sub.Instance, sub.SetOpen, sub.IsOpen, sub.IsSection = box, SetOpen, function() return open end, true
    return sub
end

--=====================================================================================
--  12. Window
--=====================================================================================

function Library:CreateWindow(titleText)
    local old = TargetGui:FindFirstChild(Names.Ui)
    if old then old:Destroy() end
    local gui = MountGui(Names.Ui, 9999)
    Root.Add(function() FadeOut(gui) end)

    local baseW, baseH = IsMobile and 560 or 880, IsMobile and 330 or 520
    local SIDEBAR_W = IsMobile and 150 or 170

    local root = Create("Frame", nil, { Size = UDim2.new(0, baseW, 0, baseH), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, Active = true, ZIndex = 1 })
    local uiScale = Create("UIScale", root, {Scale = DEFAULT_SCALE * SCALE_BASE})
    local shadow = Shadow(root, 120, 0.62, 0)
    local main = Create("Frame", root, { Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background, BackgroundTransparency = 0, Active = true, ZIndex = 1 })
    Glass(main, 0.13, 1.00)
    local _, mainStroke = Decorate(main, L.Corner12, {Theme.WindowStroke, 0.3, 1.6})
    EdgeGradient(mainStroke)

    local fab, fabScale, fabEnabled = nil, nil, false
    local ToggleHooks = {}
    local menuOpen = true
    -- must stay below menuOpen: declared above it, the body binds a nil GLOBAL instead of the
    -- upvalue, `not menuOpen` is always true, and the badge shows through an open menu
    -- Forced on touch, not merely defaulted: there is no keybind row on mobile, so the badge is
    -- the only way back into a closed menu and a saved `false` would strand the user.
    --
    -- ONE predicate, read twice. The collapse's completion used to re-check `fabEnabled and not
    -- menuOpen`, dropping the `or IsMobile` -- so on a phone the two halves disagreed about
    -- whether the badge should be up.
    local function FabWanted() return (fabEnabled or IsMobile) and not menuOpen end
    local function RefreshFab()
        if not fab then return end
        if FabWanted() then
            fab.Visible = true
            Tween(fabScale, { Scale = 1 }, 0.32, 0.62)
        else
            Tween(fabScale, { Scale = 0 }, 0.18, 1, function()
                if not FabWanted() then fab.Visible = false end
            end)
        end
    end
    local function SetMenuOpen(open)
        open = not not open
        if open == menuOpen then return end
        menuOpen = open
        if not open then CloseActivePopup() end
        SetCursor(open)
        FadeVisible(root, open)
        RefreshFab()
        for i = 1, #ToggleHooks do task.spawn(ToggleHooks[i], open) end
    end

    local catcher = Create("TextButton", gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 198 })
    catcher.MouseButton1Click:Connect(CloseActivePopup)

    UI.Gui, UI.Scale, UI.Catcher = gui, uiScale, catcher

    local topbar = Create("Frame", main, { Size = UDim2.new(1, 0, 0, L.TopbarH), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, Active = true, ZIndex = 5 })
    Decorate(topbar, L.Corner12)
    Create("Frame", topbar, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, ZIndex = 5 })
    Create("Frame", topbar, { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.35, ZIndex = 6 })

    local sidebar = Create("Frame", main, { Size = UDim2.new(0, SIDEBAR_W, 1, -L.TopbarH), Position = UDim2.new(0, 0, 0, L.TopbarH), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, Active = true, ZIndex = 2 })
    Decorate(sidebar, L.Corner12)
    Create("Frame", sidebar, { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, ZIndex = 2 })
    Create("Frame", main, { Size = UDim2.new(0, 1, 1, -(L.TopbarH + 14)), Position = UDim2.new(0, SIDEBAR_W, 0, L.TopbarH), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.5, ZIndex = 3 })

    local TOPBAR_NUDGE = 12
    Create("TextLabel", topbar, { Text = titleText, Size = UDim2.new(0, SIDEBAR_W, 1, 0), Position = UDim2.new(0, -TOPBAR_NUDGE, 0, 0), TextColor3 = Theme.Accent,
        Font = Enum.Font.GothamBlack, TextSize = 23, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })

    local btnContainer = Create("ScrollingFrame", sidebar, { Size = UDim2.new(1, 0, 1, -94), Position = UDim2.new(0, 0, 0, 12), BackgroundTransparency = 1, ZIndex = 3, ScrollBarThickness = 0 })
    local tabList = Create("Frame", btnContainer, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3 })
    List(tabList, L.TabGap, false, Enum.HorizontalAlignment.Center)
    local selector = Create("Frame", btnContainer, { Size = UDim2.new(0, 3, 0, 0), Position = UDim2.new(0, 5, 0, 19), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.Accent, ZIndex = 4 })
    Decorate(selector, L.Pill)

    local profileDivider = Create("Frame", sidebar, { Size = UDim2.new(1, -32, 0, 1), Position = UDim2.new(0, 16, 1, -76), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.25, ZIndex = 3 })
    local profile = Create("Frame", sidebar, { Size = UDim2.new(1, -28, 0, 48), Position = UDim2.new(0, 14, 1, -62), BackgroundTransparency = 1, ZIndex = 3 })
    local avatar = Create("ImageLabel", profile, { Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 0, 0.5, -22), BackgroundColor3 = Theme.Section, BackgroundTransparency = 0.2, ZIndex = 3 })
    Decorate(avatar, L.Pill, {Theme.Accent, 0.3, 1})
    task.spawn(function()
        local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
        if ok and avatar.Parent then avatar.Image = img end
    end)
    local nameBlock = Create("Frame", profile, { Size = UDim2.new(1, -56, 1, 0), Position = UDim2.new(0, 56, 0, 0), BackgroundTransparency = 1, ZIndex = 3 })
    List(nameBlock, 2)
    Create("UIPadding", nameBlock, { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) })
    Create("TextLabel", nameBlock, { Text = LocalPlayer.DisplayName ~= "" and LocalPlayer.DisplayName or LocalPlayer.Name, Size = UDim2.new(1, 0, 0, 18), TextColor3 = Theme.Text, Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1, ZIndex = 3 })
    Create("TextLabel", nameBlock, { Text = "@" .. LocalPlayer.Name, Size = UDim2.new(1, 0, 0, 15), TextColor3 = Theme.Desc, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2, ZIndex = 3 })

    local glow = Create("Frame", main, { Size = UDim2.new(1, -SIDEBAR_W, 0, 200), Position = UDim2.new(0, SIDEBAR_W, 0, L.TopbarH), BackgroundColor3 = Theme.Accent, ZIndex = 0 })
    Create("UIGradient", glow, { Rotation = 90, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.35, 0.9), NumberSequenceKeypoint.new(1, 1) }) })

    local container = Create("Frame", main, { Size = UDim2.new(1, -(SIDEBAR_W + 20), 1, -(L.TopbarH + 18)), Position = UDim2.new(0, SIDEBAR_W + 10, 0, L.TopbarH + 8), BackgroundTransparency = 1 })
    local headTitle = Create("TextLabel", container, { Text = "", Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 12, 0, 2), TextColor3 = Theme.Text, Font = Enum.Font.GothamBold, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
    local headSub = Create("TextLabel", container, { Text = "", Size = UDim2.new(1, -12, 0, 14), Position = UDim2.new(0, 12, 0, 27), TextColor3 = Theme.SubText, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
    -- must stay a plain Frame: a CanvasGroup here would soften the text of every widget on every tab
    local pageHost = Create("Frame", container, { Size = UDim2.new(1, 0, 1, -L.PageTop), Position = UDim2.new(0, 0, 0, L.PageTop),
        BackgroundTransparency = 1, ClipsDescendants = true })

    local CHIP_X, CHIP_RIGHT = SIDEBAR_W + 22 - TOPBAR_NUDGE, 108
    local chipRow = Create("Frame", topbar, { Size = UDim2.new(1, -(CHIP_X + CHIP_RIGHT), 1, 0), Position = UDim2.new(0, CHIP_X, 0, 0), BackgroundTransparency = 1, ZIndex = 6 })
    List(chipRow, 8, true)
    local function Chip(text, accent, order)
        local c = Create("TextLabel", chipRow, { Text = text, RichText = false, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 22),
            BackgroundColor3 = accent and Theme.Chip or Theme.Section, BackgroundTransparency = accent and 0.15 or 0.3,
            TextColor3 = accent and Theme.Active or Theme.SubText, Font = Enum.Font.GothamBold, TextSize = 11, LayoutOrder = order, ZIndex = 6 })
        Decorate(c, L.Corner6, {accent and Theme.Accent or Theme.Stroke, accent and 0.45 or 0.6, 1}, {nil, nil, 10, 10})
        return c
    end
    local gameChip = Chip("...", true, 1)
    task.spawn(function()
        local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
        if gameChip.Parent then gameChip.Text = (ok and info and info.Name or "ROBLOX"):upper() end
    end)
    Chip(CONFIG.VERSION, false, 2)

    local MIN_W, MIN_H = 620, 340
    local RefitWindow    -- defined below; SetScale needs it
    local WindowObj = { Gui = gui, FirstTab = true, SetMenuOpen = SetMenuOpen, Profile = profile, ProfileDivider = profileDivider }
    UI.Window = WindowObj

    -- root.Size is PRE-UIScale, so a scale change alters how big the window renders without
    -- changing what is stored. Every scale change has to re-fit or it runs off screen.
    function WindowObj.SetLauncher(v)
        fabEnabled = not not v
        RefreshFab()
    end

    function WindowObj.SetScale(v)
        uiScale.Scale = v * SCALE_BASE
        if RefitWindow then RefitWindow() end
    end

    local desiredSize = UDim2.fromOffset(baseW, baseH)
    local maximized, savedPos, maxIcon, movedWhileMax = false, nil, nil, false
    -- The viewport is the hard ceiling and MIN_W/MIN_H only apply when they fit inside it. Flooring
    -- at MIN unconditionally makes the window wider than a phone screen, which pushes the topbar
    -- buttons off the right edge -- minimize and close become unreachable rather than merely small.
    --!mv:omit
    local function ClampSize(sz, vp, sc)
        local maxW, maxH = math.max(160, vp.X / sc), math.max(160, vp.Y / sc)
        return UDim2.fromOffset(
            math.clamp(sz.X.Offset, math.min(MIN_W, maxW), maxW),
            math.clamp(sz.Y.Offset, math.min(MIN_H, maxH), maxH))
    end
    local function SetMaximized(v)
        if v == maximized then return end
        maximized = v
        local vp, sc = gui.AbsoluteSize, math.max(uiScale.Scale, 0.01)
        if v then
            savedPos = root.Position
            Tween(root, { Size = UDim2.fromOffset((vp.X - 20) / sc, (vp.Y - 20) / sc), Position = UDim2.fromScale(0.5, 0.5) }, 0.3)
        else
            Tween(root, { Size = ClampSize(desiredSize, vp, sc),
                          Position = movedWhileMax and root.Position or savedPos or UDim2.fromScale(0.5, 0.5) }, 0.3)
        end
        movedWhileMax = false
        if maxIcon then ApplyIcon(maxIcon, maximized and "minimize-2" or "maximize-2") end
    end
    -- only a manual RESIZE drops the maximized state; moving the window must not, or the button has
    -- nothing to restore to and looks dead after any drag
    local function ResizeClearsMaximized()
        maximized, savedPos, movedWhileMax = false, nil, false
        if maxIcon then ApplyIcon(maxIcon, "maximize-2") end
    end
    local function NoteDrag() if maximized then movedWhileMax = true end end

    local GHOST_BG, GHOST_EDGE, GHOST_TEXT = 0.45, 0.7, 0.1
    local DRAG_FADE = 0.15
    -- Always exactly the window's footprint. A smaller plate sits inside the window's still-fading
    -- border and a ring appears to float around it, so never animate its size.
    local ghost = Create("Frame", root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = COLOR_BLACK,
        BackgroundTransparency = 1, Visible = false, ZIndex = 2 })
    local _, ghostStroke = Decorate(ghost, L.Corner12, {COLOR_WHITE, 1, 1.5})
    local ghostText = Create("TextLabel", ghost, { Text = (CONFIG.DISCORD:gsub("^%w+://", "")):upper(), RichText = false,
        Rotation = -20, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.88, 0.26), TextColor3 = COLOR_WHITE, TextTransparency = 1,
        Font = Enum.Font.GothamBlack, TextScaled = true })

    local skipGhost = { [ghost] = true }
    local dragGen = 0
    local function DragGhost(moving)
        dragGen += 1
        local gen = dragGen
        if moving then
            FadeWindowOut(DRAG_FADE)
            ghost.Visible = true
            Tween(ghost, { BackgroundTransparency = GHOST_BG }, DRAG_FADE)
            Tween(ghostStroke, { Transparency = GHOST_EDGE }, DRAG_FADE)
            Tween(ghostText, { TextTransparency = GHOST_TEXT }, DRAG_FADE)
            task.delay(DRAG_FADE + 0.02, function()
                if gen == dragGen then main.Visible = false end
            end)
        else
            main.Visible = true
            FadeWindowIn(DRAG_FADE)
            Tween(ghostStroke, { Transparency = 1 }, DRAG_FADE)
            Tween(ghostText, { TextTransparency = 1 }, DRAG_FADE)
            Tween(ghost, { BackgroundTransparency = 1 }, DRAG_FADE, nil, function()
                if gen == dragGen then ghost.Visible = false end
            end)
        end
    end

    MakeDraggable(topbar, root, NoteDrag, DragGhost)
    MakeDraggable(sidebar, root, NoteDrag, DragGhost)
    -- The second set is the PANE -- root, its shadow, and main's fill and border. Those four fade
    -- at the base rate and everything else runs ahead of them, which is what makes the window
    -- leave as one piece instead of a stack of translucent sheets.
    PrimeFade(root, skipGhost, { [root] = true, [shadow] = true, [main] = true, [mainStroke] = true })

    --!mv:omit
    function RefitWindow()
        -- A detached root measures 0 on every axis, and the clamp below would read that as a
        -- zero-width window and shove it to x = 100. The attach re-queues, so nothing is lost.
        if not root.Parent then return end
        local vp, sc = gui.AbsoluteSize, math.max(uiScale.Scale, 0.01)
        if vp.X < 1 or vp.Y < 1 then vp = Camera and Camera.ViewportSize or vp end
        if vp.X < 1 or vp.Y < 1 then return end
        CloseActivePopup()
        if maximized then
            CancelMotors(root)
            root.Size = UDim2.fromOffset((vp.X - 20) / sc, (vp.Y - 20) / sc)
            root.Position = UDim2.fromScale(0.5, 0.5)
            return
        end
        local want = ClampSize(desiredSize, vp, sc)
        if want ~= root.Size then CancelMotors(root); root.Size = want end
        local w = root.AbsoluteSize.X
        local tl = root.AbsolutePosition - gui.AbsolutePosition
        local nx = math.clamp(tl.X, 100 - w, math.max(100 - w, vp.X - 100))
        local ny = math.clamp(tl.Y, 0, math.max(0, vp.Y - 44))
        if nx ~= tl.X or ny ~= tl.Y then SetTopLeft(root, vp, nx, ny) end
    end
    -- AbsoluteSize lags its own changed signal by several frames, so poll for a short settle window
    -- instead of reading it inside the signal. The watcher only exists during that window.
    local refitUntil, refitConn, lastVp = 0, nil, gui.AbsoluteSize
    --!mv:omit
    local function WatchViewport()
        if not gui.Parent then refitConn:Disconnect(); refitConn = nil; return end
        local vp = gui.AbsoluteSize
        if vp ~= lastVp then
            lastVp = vp
            RefitWindow()
        end
        if os.clock() > refitUntil then refitConn:Disconnect(); refitConn = nil end
    end
    --!mv:omit
    local function QueueRefit()
        refitUntil = os.clock() + 0.5
        if refitConn then return end
        refitConn = RunService.Heartbeat:Connect(WatchViewport)
    end
    Root.Add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(QueueRefit))
    if Camera then Root.Add(Camera:GetPropertyChangedSignal("ViewportSize"):Connect(QueueRefit)) end
    Root.Add(function() if refitConn then refitConn:Disconnect(); refitConn = nil end end)
    QueueRefit()

    local function WindowBtn(iconName, xOffset, tintColor, callback)
        -- a 28px target is a comfortable mouse hit and a poor finger one
        local btn = Create("TextButton", topbar, { Size = UDim2.new(0, IsMobile and 36 or 28, 0, IsMobile and 36 or 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, xOffset, 0.5, 0), BackgroundColor3 = tintColor, BackgroundTransparency = 1, ZIndex = 7 })
        Decorate(btn, L.Corner6)
        local ic = Create("ImageLabel", btn, { Size = UDim2.new(0, 15, 0, 15), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ImageColor3 = Theme.TabText, ZIndex = 8 })
        ApplyIcon(ic, iconName)
        Interactive(btn, { Over = {BackgroundTransparency = 0.78}, Out = {BackgroundTransparency = 1} })
        Interactive(btn, { Target = ic, Over = {ImageColor3 = COLOR_WHITE}, Out = {ImageColor3 = Theme.TabText} })
        btn.MouseButton1Click:Connect(callback)
        return btn, ic
    end
    WindowBtn("x", -10, Color3.fromRGB(192, 102, 110), function() if genv.SummitCleanup then genv.SummitCleanup() end end)
    local _
    _, maxIcon = WindowBtn("maximize-2", -44, Theme.Close, function() SetMaximized(not maximized) end)
    WindowBtn("minus", -78, Theme.Close, function() SetMenuOpen(false) end)

    local grip = Create("TextButton", main, { BackgroundTransparency = 1, Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(1, -18, 1, -18), ZIndex = 7 })
    for _, d in { {10, 2}, {6, 6}, {10, 6}, {2, 10}, {6, 10}, {10, 10} } do
        Create("Frame", grip, { Size = UDim2.new(0, 2, 0, 2), Position = UDim2.new(0, d[1], 0, d[2]), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.2, ZIndex = 7 })
    end
    grip.InputBegan:Connect(function(input)
        if not IsPress(input.UserInputType) then return end
        ResizeClearsMaximized()
        CloseActivePopup()
        local start, size0, pos0 = input.Position, root.Size, root.Position
        BeginDrag(function(i)
            local scale = math.max(uiScale.Scale, 0.01)
            local dx, dy = (i.Position.X - start.X) / scale, (i.Position.Y - start.Y) / scale
            -- ClampSize, not a second copy of the clamp: flooring at MIN_W unconditionally makes
            -- the window WIDER than a phone screen and pushes the topbar buttons off the edge,
            -- which is the case ClampSize is written to avoid.
            local want = ClampSize(UDim2.fromOffset(size0.X.Offset + dx, size0.Y.Offset + dy),
                                   gui.AbsoluteSize, scale)
            local w, h = want.X.Offset, want.Y.Offset
            root.Size = want
            desiredSize = want
            root.Position = UDim2.new(pos0.X.Scale, pos0.X.Offset + (w - size0.X.Offset) * scale / 2, pos0.Y.Scale, pos0.Y.Offset + (h - size0.Y.Offset) * scale / 2)
        end)
    end)

    -- Built on every platform, not just touch: it is the only way back in if the toggle key is
    -- forgotten, and it costs nothing while hidden. Shows whenever the menu is closed.
    do
        -- fab is the carrier, `face` is the button. A Shadow() parented INSIDE the button draws
        -- over it -- under ZIndexBehavior.Sibling a descendant always beats its ancestor -- so the
        -- shadow has to be the button's sibling, which is what the carrier exists for.
        fab = Create("Frame", gui, { Size = UDim2.new(0, 46, 0, 46),
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16),
            BackgroundTransparency = 1, Active = true, ZIndex = 100, Visible = false })
        fabScale = Create("UIScale", fab, { Scale = 0 })
        Shadow(fab, 26, 0.72, 99)
        local face = Create("TextButton", fab, { Size = UDim2.fromScale(1, 1),
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BackgroundColor3 = Theme.Active, BackgroundTransparency = FAB_FACE_ALPHA, ZIndex = 100 })
        -- Hover scales the FACE, show/hide scales the carrier. One UIScale driving both would be
        -- clobbered by ResetInteractives, which force-writes every hover target to its rest value
        -- when the window hides -- the exact moment the launcher animates in.
        local hoverScale = Create("UIScale", face, { Scale = 1 })
        Decorate(face, FAB_CORNER, {Theme.ToggleBorder, 0.35, 2})
        local mark = Create("ImageLabel", face, { Size = UDim2.fromScale(0.62, 0.62),
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            ScaleType = Enum.ScaleType.Fit, ZIndex = 102 })
        Interactive(face, { Over = { BackgroundTransparency = FAB_FACE_ALPHA - 0.22, BackgroundColor3 = Theme.Accent },
            Out = { BackgroundTransparency = FAB_FACE_ALPHA, BackgroundColor3 = Theme.Active }, Time = 0.14 })
        -- Scale is barred on in-layout widgets because it shoves their neighbours around. The
        -- launcher is absolutely positioned in the ScreenGui with no siblings, so there is no
        -- layout to thrash and the grow is free.
        Interactive(face, { Target = hoverScale, Over = { Scale = 1.09 }, Out = { Scale = 1 }, Time = 0.16 })

        task.spawn(function()
            local asset = (type(getcustomasset) == "function" and getcustomasset)
                or (type(getsynasset) == "function" and getsynasset)
            local id
            if asset and writefile and isfile then
                local file = ("%s/launcher_v%d.png"):format(CONFIG.FOLDER, FAB_SCHEMA)
                local ready = isfile(file)
                if not ready then
                    -- game:HttpGet, not the executor's request(): Roblox's own stack sends the
                    -- User-Agent raw.githubusercontent wants, and it needs no executor capability.
                    local ok, data = pcall(game.HttpGet, game, FAB_ICON)
                    if not ok then
                        Warn("launcher badge fetch failed: %s", tostring(data))
                    elseif type(data) ~= "string" or data:sub(2, 4) ~= "PNG" then
                        -- An error page or a truncated body writes as happily as a PNG, and a bad
                        -- cache file is PERMANENT: isfile() answers ready forever after, so the
                        -- launcher would wear a broken image id for good. Check the magic bytes.
                        Warn("launcher badge from %s was not a PNG", FAB_ICON)
                    else
                        local okW, errW = pcall(writefile, file, data)
                        ready = okW
                        if not okW then Warn("could not write launcher badge to %q: %s", file, tostring(errW)) end
                    end
                end
                if ready then
                    local ok, res = pcall(asset, file)
                    id = ok and res or nil
                    if not ok then Warn("getcustomasset rejected %q: %s", file, tostring(res)) end
                end
            end
            if not mark.Parent then return end
            if id then
                mark.Image = id
            else
                Create("TextLabel", face, { Text = "SX", Size = UDim2.fromScale(1, 1),
                    Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = COLOR_WHITE, ZIndex = 102 })
            end
        end)

        local fabStart, fabOrigin, fabMoved
        face.InputBegan:Connect(function(input)
            if not IsPress(input.UserInputType) then return end
            fabStart, fabMoved = input.Position, false
            fabOrigin = fab.AbsolutePosition - gui.AbsolutePosition
            -- it starts anchored top-centre; normalise to plain top-left offsets before dragging,
            -- or the anchor would shift it half its width on the first move
            fab.AnchorPoint = Vector2.new(0, 0)
            fab.Position = UDim2.fromOffset(fabOrigin.X, fabOrigin.Y)
            BeginDrag(function(i)
                local delta = i.Position - fabStart
                if delta.Magnitude > 6 then fabMoved = true end
                local vp = gui.AbsoluteSize
                local nx = math.clamp(fabOrigin.X + delta.X, 4, math.max(4, vp.X - fab.AbsoluteSize.X - 4))
                local ny = math.clamp(fabOrigin.Y + delta.Y, 4, math.max(4, vp.Y - fab.AbsoluteSize.Y - 4))
                fab.Position = UDim2.fromOffset(nx, ny)
            end)
        end)
        face.InputEnded:Connect(function(input)
            if IsPress(input.UserInputType) and not fabMoved then SetMenuOpen(true) end
        end)
    end

    local tabSetters, tabHandles = {}, {}

    -- Tab BODIES build one per frame; every tab's SHELL is built inline so the sidebar is complete
    -- and correctly ordered on frame one. The queue always drains on its own, so a Default-on
    -- toggle on the last tab still fires its callback and registers its flag -- a few frames late.
    local warmQueue, warmAt, warmConn = {}, 1, nil
    -- Called flat. The first tab builds inline, so a throwing builder there unwinds Init and lands
    -- red in the game script that called it -- which is where a broken tab belongs. From the warm
    -- driver it costs only its own tab: warmAt has already advanced past this one before the body
    -- runs, so the next Heartbeat picks up at the tab after it rather than retrying this one.
    --!mv:omit
    local function BuildBody(tab)
        local body = tab.Body
        if not body then return false end
        tab.Body = nil
        body(tab, WindowObj)
        return true
    end
    --!mv:omit
    local function WarmStep()
        while warmAt <= #warmQueue do
            local tab = warmQueue[warmAt]
            warmAt += 1
            if BuildBody(tab) then return true end
        end
        return false
    end
    --!mv:omit
    local function WarmTick()
        -- guarded: a tab builder that unloads the hub runs Root's cleanup, which already cut this
        -- connection and nilled it out from under the frame still executing here
        if not WarmStep() and warmConn then warmConn:Disconnect(); warmConn = nil end
    end
    local function StartWarm()
        if warmConn then return end
        warmConn = RunService.Heartbeat:Connect(WarmTick)
    end
    Root.Add(function() if warmConn then warmConn:Disconnect(); warmConn = nil end end)

    function WindowObj:MakeTab(name, subtitle, icon, body)
        local isActiveTab = self.FirstTab
        self.FirstTab = false
        local tabIndex = #tabSetters + 1
        if isActiveTab then headTitle.Text, headSub.Text = name, subtitle or "" end

        local btn = Create("TextButton", tabList, { Size = UDim2.new(1, -24, 0, L.TabH), BackgroundColor3 = Theme.Accent, BackgroundTransparency = isActiveTab and 0.85 or 1, ZIndex = 3, LayoutOrder = tabIndex })
        Decorate(btn, L.Corner8)
        local tabIcon = Create("ImageLabel", btn, { Size = UDim2.new(0, 17, 0, 17), Position = UDim2.new(0, 16, 0.5, -8), ImageColor3 = isActiveTab and Theme.Accent or Theme.TabText, ZIndex = 4 })
        ApplyIcon(tabIcon, icon or "circle")
        local tabLbl = Create("TextLabel", btn, { Text = name, Size = UDim2.new(1, -48, 1, 0), Position = UDim2.new(0, 40, 0, 0), TextColor3 = isActiveTab and Theme.Text or Theme.TabText, Font = Enum.Font.GothamBold, TextSize = L.TitleSize, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
        local page = Create("ScrollingFrame", pageHost, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = isActiveTab })
        List(page, 12, false, Enum.HorizontalAlignment.Center)
        Decorate(page, nil, nil, {4, 8, 12, 12})

        local selY = (tabIndex - 1) * (L.TabH + L.TabGap) + L.TabH / 2
        if isActiveTab then
            selector.Position = UDim2.new(0, 5, 0, selY)
            selector.Size = UDim2.new(0, 3, 0, 16)
        end

        local tab      -- built below; Select needs it to force a still-queued body

        local function SetActive(on)
            page.Visible = on
            Tween(btn, { BackgroundTransparency = on and 0.85 or 1 }, 0.18)
            Tween(tabLbl, { TextColor3 = on and Theme.Text or Theme.TabText }, 0.18)
            Tween(tabIcon, { ImageColor3 = on and Theme.Accent or Theme.TabText }, 0.18)
        end
        tabSetters[tabIndex] = SetActive

        local function Select()
            if page.Visible then return end
            -- ahead of the switch, not after: the page has to be populated before it is shown, or
            -- clicking a tab the warm-up has not reached yet lands on an empty panel
            BuildBody(tab)
            CloseActivePopup()
            for _, f in tabSetters do f(false) end
            SetActive(true)
            headTitle.Text, headSub.Text = name, subtitle or ""
            -- Position only, critically damped. The rail keeps a fixed height: with AnchorPoint.Y
            -- at 0.5 an animated height moves both edges on their own curve, and against a
            -- non-integer UIScale those edges land on different sub-pixels every frame, which is
            -- what read as jitter. No CancelMotors either -- retargeting an in-flight motor
            -- carries its velocity over, so a fast second click bends the travel instead of
            -- restarting it.
            Tween(selector, { Position = UDim2.new(0, 5, 0, selY) }, 0.28)
        end

        btn.MouseButton1Click:Connect(Select)
        Interactive(btn, { Over = {BackgroundTransparency = 0.93}, Out = {BackgroundTransparency = 1},
                           Time = 0.15, Enabled = function() return not page.Visible end })

        tab = NewContainer(page, name, page, WindowObj)
        tab.Page, tab.Button, tab.Select, tab.Index = page, btn, Select, tabIndex
        tab.Body = body
        tabHandles[tabIndex], tabHandles[name] = tab, tab
        if isActiveTab then BuildBody(tab) else warmQueue[#warmQueue + 1] = tab; StartWarm() end
        return tab
    end

    function WindowObj:SelectTab(which)
        local t = tabHandles[which]
        if t then t.Select() end
        return t
    end
    function WindowObj:GetTab(which) return tabHandles[which] end
    function WindowObj.IsOpen() return menuOpen end
    function WindowObj:Notify(cfg) return Library:Notify(cfg) end
    function WindowObj:OnToggle(fn) if type(fn) == "function" then ToggleHooks[#ToggleHooks + 1] = fn end end

    -- The tree goes live HERE, not at creation: task.defer resumes after Init's BuildTabs and
    -- LoadConfig, so the whole boot tree is assembled detached and lands in one parent write.
    task.defer(function()
        if root.Parent or not gui.Parent then return end
        root.Parent = gui
        QueueRefit()
    end)

    SetCursor(true)
    return WindowObj
end

--=====================================================================================
--  13. Key gate
--=====================================================================================

local function ShowKeyGate(K, Matches, onPass)
    if genv.SummitGen ~= Private.Gen then return end
    SweepStale(Names.Key)
    local kgui = MountGui(Names.Key, 9999)
    Root.Add(function() FadeOut(kgui) end)
    SetCursor(true)

    local shell = Create("Frame", kgui, { Size = UDim2.new(0, 360, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, Active = true })
    local shellScale = Create("UIScale", shell, { Scale = 1 })
    Shadow(shell, 110, 0.6, 0)
    local card = Create("Frame", shell, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background, BackgroundTransparency = 0, Active = true, ZIndex = 1 })
    Glass(card)
    local _, cardStroke = Decorate(card, L.Corner12, {Theme.WindowStroke, 0.3, 1.6})
    EdgeGradient(cardStroke)
    MakeDraggable(card, shell)
    List(card, 12)
    Create("UIPadding", card, { PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 20), PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) })

    local head = Create("Frame", card, { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1 })
    Create("TextLabel", head, { Text = CONFIG.HUB_NAME, Size = UDim2.new(1, -70, 1, 0), TextColor3 = Theme.Accent,
        Font = Enum.Font.GothamBlack, TextSize = 23, TextXAlignment = Enum.TextXAlignment.Left })
    Create("TextLabel", head, { Text = "KEY SYSTEM", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -30, 0.5, 0),
        Size = UDim2.new(0, 90, 0, 16), TextColor3 = Theme.Placeholder, Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right })

    Create("TextLabel", card, { Text = K.Note or "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextColor3 = Theme.SubText, Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2 })

    local field = Create("Frame", card, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Section, BackgroundTransparency = 0.15, LayoutOrder = 3 })
    local _, fieldStroke = Decorate(field, L.Corner8, {Theme.Stroke, 0.55, 1})
    local box = ClippedBox(field, { Text = "", PlaceholderText = "Paste your key", TextColor3 = Theme.Text,
        PlaceholderColor3 = Theme.Placeholder, Font = Enum.Font.GothamMedium, TextSize = L.TitleSize })
    box.Focused:Connect(function() Tween(fieldStroke, { Color = Theme.Accent, Transparency = 0.2 }, 0.15) end)
    box.FocusLost:Connect(function() Tween(fieldStroke, { Color = Theme.Stroke, Transparency = 0.55 }, 0.15) end)

    local row = Create("Frame", card, { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 4 })
    List(row, 8, true)
    local function CardBtn(text, accent, order)
        local b = Create("TextButton", row, { Text = text, RichText = false, Size = UDim2.new(0.5, -4, 1, 0),
            BackgroundColor3 = accent and Theme.Accent or Theme.Section, BackgroundTransparency = accent and 0.1 or 0.15,
            TextColor3 = accent and COLOR_WHITE or Theme.SubText, Font = Enum.Font.GothamBold, TextSize = 13, LayoutOrder = order })
        Decorate(b, L.Corner8, {accent and Theme.Active or Theme.Stroke, 0.5, 1})
        Interactive(b, { Over = { BackgroundTransparency = 0 }, Out = { BackgroundTransparency = accent and 0.1 or 0.15 },
                         Down = { BackgroundTransparency = 0.28 } })
        return b
    end
    local copyBtn = CardBtn("Get Key", false, 1)
    local submitBtn = CardBtn("Submit", true, 2)

    local close = Create("TextButton", shell, { Text = "×", Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8), TextColor3 = Theme.Close, Font = Enum.Font.GothamMedium, TextSize = 20, ZIndex = 6 })
    Interactive(close, { Over = { TextColor3 = COLOR_WHITE }, Out = { TextColor3 = Theme.Close } })
    close.MouseButton1Click:Connect(function() if genv.SummitCleanup then genv.SummitCleanup() end end)

    local granted, tries = false, 0
    local function Submit()
        if granted then return end
        if genv.SummitGen ~= Private.Gen then kgui:Destroy(); return end
        if Matches(box.Text) then
            granted = true
            AcceptedKey = (box.Text:gsub("%s", ""))
            if canFile and not K.SaveForPremiumOnly then
                local okW, errW = pcall(writefile, K.SaveFile, AcceptedKey)
                if not okW then Warn("could not save key to %q: %s", K.SaveFile, tostring(errW)) end
            end
            Tween(shellScale, { Scale = 0.82 }, 0.2)
            ApplySnapshot(Snapshot(card), 1, 0.2)
            task.delay(0.28, function()
                kgui:Destroy()
                if genv.SummitGen ~= Private.Gen then return end
                onPass()
                Library:Notify({ Title = CONFIG.HUB_NAME .. " " .. CONFIG.VERSION, Content = "Key accepted.", Duration = 4 })
            end)
            return
        end
        tries += 1
        box.Text = ""
        box.PlaceholderText = tries >= 3 and "Still wrong — copy the whole key" or "Invalid key"
        TweenService:Create(shell, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 4, true), { Rotation = 3 }):Play()
        TweenService:Create(cardStroke, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { Color = Theme.Bad, Transparency = 0.1 }):Play()
        Library:Notify({ Title = "Invalid key", Content = "That key wasn't recognised.",
            SubContent = tries >= 2 and "Grab a fresh one from the Discord." or nil, Type = "error", Duration = 5 })
    end
    submitBtn.MouseButton1Click:Connect(Submit)
    box.FocusLost:Connect(function(enterPressed) if enterPressed then Submit() end end)
    copyBtn.MouseButton1Click:Connect(function()
        if setclipboard then pcall(setclipboard, CONFIG.DISCORD) end
        copyBtn.Text = "Link copied!"
        Library:Notify({ Title = "Discord copied", Content = "Invite copied — grab your key in there.",
            SubContent = CONFIG.DISCORD, Duration = 4 })
        task.delay(1.4, function() if copyBtn.Parent then copyBtn.Text = "Get Key" end end)
    end)

    local cardSnap = Snapshot(card)
    ApplySnapshot(cardSnap, 1)
    ApplySnapshot(cardSnap, 0, 0.28)
end

--=====================================================================================
--  13b. Execution log
--=====================================================================================

-- Memoised: identifyexecutor() is a foreign call, and both the boot path and the log ask for it.
function Library:ExecutorName()
    local cached = Private.Executor
    if cached then return cached end
    cached = "unknown"
    local probe = (type(identifyexecutor) == "function" and identifyexecutor)
        or (type(getexecutorname) == "function" and getexecutorname)
    if probe then
        local ok, found = pcall(probe)
        if ok and found ~= nil and found ~= "" then cached = tostring(found) end
    end
    Private.Executor = cached
    return cached
end

function Library:LogExecution()
    if not (HttpRequest and CONFIG.API and CONFIG.API ~= "") then return end
    task.spawn(function()
        -- select("#") rather than ipairs: a nil global would leave a hole and stop the scan dead
        local function First(...)
            for i = 1, select("#", ...) do
                local fn = select(i, ...)
                if type(fn) == "function" then
                    local ok, v = pcall(fn)
                    if ok and v and v ~= "" then return tostring(v) end
                end
            end
            return "unknown"
        end

        local endpoint = CONFIG.API:gsub("/+$", "") .. "/log"

        -- One lookup, so there is no join to run. `sent` guards the timeout, which is the only
        -- thing that could post a second copy if GetProductInfo hangs rather than failing.
        local sent = false
        local function Send(gameName)
            if sent then return end
            sent = true
            pcall(HttpRequest, {
                Url = endpoint,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({
                    hub       = CONFIG.HUB_NAME,
                    player    = ("%s (@%s)"):format(LocalPlayer.DisplayName, LocalPlayer.Name),
                    game_name = gameName,
                    executor  = Library:ExecutorName(),
                    place_id  = tostring(game.PlaceId),
                    hwid      = First(gethwid, get_hwid, type(syn) == "table" and syn.get_hwid,
                        function() return Service("RbxAnalyticsService"):GetClientId() end),
                }),
            })
        end

        task.spawn(function()
            local okInfo, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
            Send(okInfo and info and info.Name or "unknown")
        end)
        task.delay(10, function() Send("unknown") end)
    end)
end

function Library:RejectUnsupported()
    local list = CONFIG.UNSUPPORTED
    if type(list) ~= "table" or #list == 0 then return false end

    local name = self:ExecutorName()
    local lowered = name:lower()

    for _, entry in ipairs(list) do
        if type(entry) == "string" and entry ~= "" and lowered:find(entry:lower(), 1, true) then
            Library:Notify({
                Title = "Unsupported executor",
                Content = name .. " cannot run " .. CONFIG.HUB_NAME .. ".",
                SubContent = CONFIG.UNSUPPORTED_NOTE ~= "" and CONFIG.UNSUPPORTED_NOTE or nil,
                Type = "error", Duration = 8,
            })
            task.delay(6, function() if genv.SummitCleanup then genv.SummitCleanup() end end)
            return true
        end
    end
    return false
end

--
function Library:IsSupportedGame()
    local ids = CONFIG.GAME_IDS
    if type(ids) ~= "table" or #ids == 0 then return true end
    for _, id in ipairs(ids) do
        if tonumber(id) == game.GameId then return true end
    end
    return false
end

-- True when this is the wrong game, after telling the user and scheduling the unload. Same shape as
-- RejectUnsupported above, and deliberately so: Init returns before CreateWindow, so NOTHING is
-- built. There is no middle state where the game script's tabs are missing and Settings is left
-- standing on its own -- that reads as a broken hub rather than a hub in the wrong place.
function Library:RejectWrongGame()
    if self:IsSupportedGame() then return false end

    local hub = CONFIG.HUB_NAME ~= "" and CONFIG.HUB_NAME or "This script"
    local want = CONFIG.GAME_NAME ~= "" and CONFIG.GAME_NAME or "a different game"
    Library:Notify({
        Title = "Wrong game",
        Content = ("%s only works in %s."):format(hub, want),
        SubContent = CONFIG.GAME_NOTE ~= "" and CONFIG.GAME_NOTE or nil,
        Type = "error", Duration = 8,
    })
    task.delay(6, function() if genv.SummitCleanup then genv.SummitCleanup() end end)
    return true
end

--=====================================================================================
--=====================================================================================

function Library:Init()
    if self.Started then return end     -- a second Init would stack a whole second window
    self.Started = true

    -- Configure runs before Init, so nothing legitimate writes CONFIG past this point. Frozen
    -- deeply, an injected script cannot repoint the key list or the webhook mid-session, and a
    -- game script that configures too late throws instead of silently doing nothing.
    local function Seal(t)
        for _, v in t do
            if type(v) == "table" and not table.isfrozen(v) then Seal(v) end
        end
        return table.freeze(t)
    end
    Seal(CONFIG)

    self:LogExecution()                 -- logged before the checks, so refusals show up too
    if self:RejectUnsupported() then return end
    if self:RejectWrongGame() then return end
    self:RegisterBuiltins()

    -- table.sort is NOT stable, and every tab missing from TabOrder ties. Registration index
    -- breaks the tie, or the sidebar order changes between runs.
    local rank = {}
    for i, name in ipairs(self.TabOrder or {}) do rank[name] = i end
    for i, t in Private.Tabs do t.Seq = i end
    table.sort(Private.Tabs, function(a, b)
        local ra, rb = rank[a.Name] or math.huge, rank[b.Name] or math.huge
        if ra ~= rb then return ra < rb end
        return a.Seq < b.Seq
    end)
    Camera = Workspace.CurrentCamera or Camera

    local function Build()
        if genv.SummitGen ~= Private.Gen then return end
        self:BuildTabs(self:CreateWindow(CONFIG.HUB_NAME))
        self:LoadConfig()
        Root.Add(function() if configDirty then Library:SaveConfig() end end)
    end

    -- An empty Keys list counts as disabled: a gate no key can open locks out every user,
    -- and forgetting to configure one should not be the way that happens.
    local K = CONFIG.KEY
    if not K.Enabled or not K.Keys or #K.Keys == 0 then Build(); StartPremiumCheck(); return end

    local function Normalise(s)
        return tostring(s):gsub("%s", ""):gsub("%c", ""):lower()
    end
    local function Matches(entered)
        entered = Normalise(entered)
        if entered == "" then return false end
        for _, k in ipairs(K.Keys) do
            if entered == Normalise(k) then return true end
        end
        return false
    end

    if canFile and isfile(K.SaveFile) then
        local ok, saved = pcall(readfile, K.SaveFile)
        if ok and Matches(saved) then
            AcceptedKey = (tostring(saved):gsub("%s", ""))
            Build()
            StartPremiumCheck()
            return
        end
        if delfile then pcall(delfile, K.SaveFile) end     -- rotated out of Keys; drop it
    end

    task.spawn(function()
        RunPremiumCheck(1)
        if genv.SummitGen ~= Private.Gen then return end
        if Library.IsPremium then
            Build()
        else
            ShowKeyGate(K, Matches, function()
                Build()
                StartPremiumCheck()
            end)
        end
    end)
end

--=====================================================================================
--  14. Global keybind dispatch
--=====================================================================================

local MOUSE_BIND = {
    [Enum.UserInputType.MouseButton1] = "M1",
    [Enum.UserInputType.MouseButton2] = "M2",
    [Enum.UserInputType.MouseButton3] = "M3",
}
local function BindName(io)
    if io.UserInputType == Enum.UserInputType.Keyboard then return io.KeyCode.Name end
    return MOUSE_BIND[io.UserInputType]
end

Root.Add(UIS.InputBegan:Connect(function(io, gp)
    local nm = BindName(io)
    if not nm then return end
    local pending = PendingBind
    if pending and not UIS:GetFocusedTextBox()
       and (io.UserInputType == Enum.UserInputType.Keyboard or not gp) then
        if io.KeyCode == Enum.KeyCode.Backspace or io.KeyCode == Enum.KeyCode.Escape then nm = "NONE" end
        PendingBind = nil
        local b = KeybindRegistry[pending]
        if b then
            b.Key = nm
            b.Render()
            Tween(pending, {TextColor3 = Theme.SubText, BackgroundColor3 = Theme.BindBackground})
        end
        MarkDirty("keybind")
        return
    end
    -- Escape backs out one layer and NEVER toggles the menu. The focused box goes first, so one
    -- press leaves the dropdown's search field and the next closes the list. Arming a keybind is
    -- handled above, where Escape means "clear this bind" instead.
    if io.KeyCode == Enum.KeyCode.Escape then
        local box = UIS:GetFocusedTextBox()
        if box then box:ReleaseFocus(); return end
        if Private.Popup then CloseActivePopup(); return end
    end
    if gp or SliderDragging then return end
    for _, bind in KeybindRegistry do
        if bind.Key ~= "NONE" and bind.Key == nm then
            if bind.Mode == "Hold" then bind.Action(true) else bind.Action() end
        end
    end
end))

Root.Add(UIS.InputEnded:Connect(function(io)
    local nm = BindName(io)
    if not nm then return end
    for _, bind in KeybindRegistry do
        if bind.Mode == "Hold" and bind.Key == nm then bind.Action(false) end
    end
end))

--=====================================================================================
--  15. Exports
--=====================================================================================
--
--      local Library = loadstring(game:HttpGet(SUMMITX_URL))()
--      Library:Configure({ ... })
--      Library:RegisterTab("Player", function(tab, window) ... end, "Subtitle", "user")
--      Library:Init()
--
--=====================================================================================

Root.Add(function()
    table.clear(UI)
    MenuSnap, FadePlan, Drop = nil, nil, nil
    table.clear(Private.Flags)
    table.clear(PremiumHooks)
end)

Library.Config = CONFIG          -- live config table; write through Configure
Library.UI = UI                  -- .Gui .Scale .Catcher .Window — populated by Init
Library.TabIcons = TAB_ICONS     -- default Lucide icon per tab name; RegisterTab's 4th arg wins
Library.HttpRequest = HttpRequest
Library.IsMobile, Library.IsConsole = IsMobile, IsConsole
Library.Root = Root              -- .Add(conn | instance | fn) — torn down on re-inject

-- Call before Init. Nested tables (KEY) merge field by field, so passing
-- KEY = { Keys = {...} } swaps the key list without clearing Note or SaveFile. LISTS replace
-- outright: merging UNSUPPORTED by index would leave entries from a longer previous list behind.
function Library:Configure(opts)
    for k, v in opts do
        if type(v) == "table" and type(CONFIG[k]) == "table" and v[1] == nil then
            for field, value in v do CONFIG[k][field] = value end
        else
            CONFIG[k] = v
        end
    end
    if opts.FOLDER then
        if not opts.CONFIG_FILE then
            CONFIG.CONFIG_FILE = CONFIG.FOLDER .. "/configs/" .. tostring(game.PlaceId) .. ".json"
        end
        -- The key file lives in the same folder and has to move with it. Left alone it keeps
        -- writing to the DEFAULT folder, which nothing has created, so the key silently fails to
        -- save and the gate reappears next launch for someone who already entered it.
        if not (opts.KEY and opts.KEY.SaveFile) then
            CONFIG.KEY.SaveFile = CONFIG.FOLDER .. "/key.txt"
        end
    end
    -- Unconditional: a hub that repoints CONFIG_FILE without touching FOLDER still needs its
    -- directory made, and a silent pcall here would hide every failure that followed.
    EnsureFolders()
    return self
end

--=====================================================================================
--  16. Built-in tabs
--=====================================================================================
--
--  Settings is the one tab every game inherits. Registered by Init AFTER the game's tabs,
--  so it always lands last in the sidebar; name it in Library.TabOrder to move it, or set
--  Library.Builtins.Settings = false to drop it — you then own the menu keybind,
--  the launcher and UI Scale yourself.

Library.Builtins = { Settings = true }

function Library:RegisterBuiltins()
    if not (self.Builtins and self.Builtins.Settings) then return end

    self:RegisterTab("Settings", function(tab, windowObj)
        tab:AddHeader("GUI")
        tab:AddKeybind({ Name = "Toggle Menu Bind", Description = "Key that shows/hides the menu", Keybind = "RightShift", Callback = function()
            windowObj.SetMenuOpen(not windowObj.IsOpen())
        end})
        if not IsMobile then
            tab:AddToggle({ Name = "Launcher Button", Description = "Floating badge to reopen the menu, drag to move it",
                Flag = "launcher_button", Default = false, Callback = function(v) windowObj.SetLauncher(v) end })
        end
        -- The mirror of the row above: only on touch, because only there does a keybind draw a
        -- button. ON by default -- a TAP pill is the only way to fire a keybind on a phone, so it
        -- has to be there unless somebody asks for it not to be.
        tab:AddToggle({ Name = "Show Profile", Description = "Your avatar and name in the sidebar", Default = true, Callback = function(state)
            windowObj.Profile.Visible = state
            windowObj.ProfileDivider.Visible = state
        end})
        -- pinned flag: this slider is a multiple of SCALE_BASE, not a raw UIScale value, and the
        -- saved config is keyed on it. Don't rename it.
        tab:AddSlider({ Name = "UI Scale", Description = "Size of the whole menu, 1.00 being the default", Flag = "ui_scale_rel",
            Min = 0.7, Max = 1.4, Default = DEFAULT_SCALE, Decimals = 2, Callback = function(val) windowObj.SetScale(val) end})

        tab:AddHeader("SERVER")
        tab:AddButtons({
            { Name = "Server Hop", Callback = function()
                local placeId = game.PlaceId
                -- game:HttpGet only. Roblox's own stack is what this endpoint answers to, and it
                -- needs no executor capability, so there is nothing to fall back to.
                local ok, res = pcall(game.HttpGet, game, string.format(
                    "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId))
                local list
                if ok then
                    local okJ, body = pcall(HttpService.JSONDecode, HttpService, res)
                    list = okJ and type(body) == "table" and body.data or nil
                end
                -- Rate-limited, the body is {"errors":[...]} with no .data at all. Iterating that
                -- is a hard error with nothing on screen to explain it, and this endpoint gets
                -- rate-limited exactly when someone is hopping repeatedly.
                if not list then
                    Library:Notify({ Title = "Server Hop", Duration = 4,
                        Content = "Roblox wouldn't hand over the server list. Try again in a moment." })
                    return
                end
                local open = {}
                for _, srv in list do
                    if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then open[#open + 1] = srv.id end
                end
                -- Never plain Teleport as a consolation: it can land you back in THIS server, which
                -- looks like the hop silently did nothing.
                if #open == 0 then
                    Library:Notify({ Title = "Server Hop", Duration = 4,
                        Content = "No other server has a free slot right now." })
                    return
                end
                TeleportService:TeleportToPlaceInstance(placeId, open[math.random(#open)], LocalPlayer)
            end },
            { Name = "Quick Rejoin", Callback = function()
                local placeId = game.PlaceId
                if #Players:GetPlayers() <= 1 then TeleportService:Teleport(placeId, LocalPlayer)
                else TeleportService:TeleportToPlaceInstance(placeId, game.JobId, LocalPlayer) end
            end },
        })
    end, "Menu, keybinds and server tools")
end

return Library
