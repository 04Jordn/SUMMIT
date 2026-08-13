--=====================================================================================
--  SUMMITX  —  UI LIBRARY
--
--    1. Config & constants        6.  Input & drag          11. Widgets
--    2. Services & platform       7.  Notify & errors       12. Window
--    3. Lifetime                  8.  Icons                 13. Key gate, log, Init
--    4. Animation                 9.  Loops                 14. Keybind dispatch
--    5. Instances                 10. Persistence           15. Exports
--                                 10b. Premium gating       16. Built-in tabs
--
--  Returns Library and builds nothing until a game script calls Init. Copy example.lua
--  to start a new game; everything below is defaults it can override.
--=====================================================================================

-- getgenv() is the one table that survives a re-inject; `_G` inside an executor thread is not
-- the game's `_G`, so cleanup stashed there can never find the previous copy of itself.
local genv = (getgenv and getgenv()) or (getfenv and getfenv(0)) or _G

if genv.SummitCleanup then genv.SummitCleanup() end
genv.SummitGen = (genv.SummitGen or 0) + 1

-- SHAPE AND SAFE DEFAULTS ONLY — the real name, links, keys and webhook live in the game script
-- and arrive through Library:Configure{...} before Init. Nothing here is a secret, so this file
-- is safe to publish. Every empty value below is inert: no key gate, no whitelist, no logging.
local CONFIG = {
    HUB_NAME = "",                  -- e.g. "SummitX" — topbar title, notification and key-card title
    VERSION = "",                   -- e.g. "v1.0" — the chip beside the game name
    DISCORD = "",                   -- e.g. "https://discord.gg/abcdef" — copied by the Get Key button
    STORE = "",                     -- e.g. "https://summitx.mysellauth.com" — where Premium is bought

    -- On-disk home for configs, icons and the key file. A real name, not a placeholder: every
    -- path below is built from it, and "" would write to the executor's workspace root.
    FOLDER = "SummitX",
    CONFIG_FILE = "SummitX/configs/" .. tostring(game.PlaceId) .. ".json",

    LOG_WEBHOOK = "",               -- e.g. "https://discord.com/api/webhooks/..." — empty = no logging
    -- Relay for the webhook POST: Discord refuses some executor User-Agents outright. Accepts a
    -- bare host or one already ending in /api/webhooks. Empty = post straight to Discord.
    LOG_PROXY = "",                 -- e.g. "https://webhook.lewisakura.moe"

    -- Executors the hub refuses to run on: each entry is matched as a case-insensitive SUBSTRING
    -- of identifyexecutor(), so "wave" catches "Wave 2.4". Empty list = every executor allowed.
    UNSUPPORTED = {},               -- e.g. { "Solara", "JJSploit" }
    UNSUPPORTED_NOTE = "",          -- e.g. "Use Potassium or Xeno instead."

    -- Enabled = false boots straight in, and an empty Keys list counts as disabled rather than
    -- locking everyone out. Saved keys are re-checked against Keys every launch, so rotating
    -- this list re-prompts everyone.
    KEY = {
        Enabled = false,
        Keys = {},                  -- e.g. { "SummitX", "SummitX2" } — matched case-insensitively
        Note = "",                  -- e.g. "Join the Discord to grab your key, then paste it below."
        SaveFile = "SummitX/key.txt",
        SaveForPremiumOnly = true,  -- free users retype the key each launch
    },

    -- Base is the raw Gist URL including the trailing slash. Both files are flat
    -- {"userid": true} maps; a failed fetch leaves the user on the free tier.
    WHITELIST = {
        Base = "",                  -- e.g. "https://gist.githubusercontent.com/<user>/<id>/raw/"
        Whitelist = "whitelist.json",
        Blacklist = "blacklist.json",
        Attempts = 2,               -- one silent retry so a transient 502 can't downgrade a payer
        KickBlacklisted = false,    -- true = unload entirely instead of dropping to free tier
    },
}

-- fade + lift the page on tab switch
local ENABLE_TAB_TRANSITION = false


-- RailGap is the spacing between controls sharing one row's rail.
local L = {
    RowMin = 45, PadX = 15, PadY = 15, LabelGap = 3, RailGap = 10,
    TitleSize = 14, DescSize = 11,
    TabH = 38, TabGap = 6, TopbarH = 52, PageTop = 50,
    Corner16 = UDim.new(0, 16), Corner12 = UDim.new(0, 12), Corner8 = UDim.new(0, 8), Corner6 = UDim.new(0, 6), Pill = UDim.new(1, 0),
}

local COLOR_WHITE, COLOR_BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
-- launcher plate: stacked copies of the shadow sprite make a radial black falloff (see the fab)
-- Launcher face: 49% black. FAB_CORNER is shared by the button and the fill so they are one shape.
local FAB_CORNER, FAB_PLATE_ALPHA = UDim.new(0, 14), 0.51
local MAX_BLUR, DEFAULT_TWEEN_TIME = 24, 0.35
-- The checkmark crossfade, the one animation not on Tween(): a spring is asymmetric, which reads
-- wrong for a symmetric fade in and out.
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

-- Library calls stay on their globals. Luau resolves math.*/table.* through GETIMPORT and
-- compiles the hot ones to fastcalls; aliasing them into locals defeats both.

local CloneRef = clonereference or cloneref or function(o) return o end
local function Service(n) return CloneRef(game:GetService(n)) end

local Players, UIS, TweenService = Service("Players"), Service("UserInputService"), Service("TweenService")
local RunService, TeleportService, HttpService = Service("RunService"), Service("TeleportService"), Service("HttpService")
local GuiService, TextService = Service("GuiService"), Service("TextService")
local MarketplaceService = Service("MarketplaceService")

local HttpRequest = (type(syn) == "table" and syn.request) or (type(http) == "table" and http.request) or request or http_request
local LocalPlayer = Players.LocalPlayer
local Workspace = CloneRef(workspace)
local Camera = Workspace.CurrentCamera

-- Executors expose this under several names, none guaranteed; reparenting into gethui() is the
-- fallback when no protector exists.
local function Protect(g)
    if typeof(g) ~= "Instance" then return g end
    local hiders = {
        syn and syn.protect_gui,
        protectgui, protect_gui,
        (getgenv and getgenv().protect_gui),
        secure_gui,
    }
    for i = 1, #hiders do
        local fn = hiders[i]
        if type(fn) == "function" and pcall(fn, g) then return g end
    end
    -- no protector: park it in the hidden container, which hides it from a naive CoreGui sweep
    local ok, hidden = pcall(function() return (gethui or get_hidden_ui or gethiddenui)() end)
    if ok and typeof(hidden) == "Instance" then pcall(function() g.Parent = hidden end) end
    return g
end

-- gethui() then CoreGui. NO PlayerGui fallback: it is replicated and wiped on respawn.
local TargetGui = (function()
    local ok, res = pcall(function() return (gethui or get_hidden_ui or gethiddenui)() end)
    if ok and typeof(res) == "Instance" then return res end
    ok, res = pcall(function() local c = Service("CoreGui") c:GetFullName() return c end)
    if ok and typeof(res) == "Instance" then return res end
    return Service("CoreGui")
end)()

for _, leftover in { "SummitUI", "SummitKeyUI", "SummitToasts" } do
    local stale = TargetGui:FindFirstChild(leftover)
    while stale do
        pcall(function() stale:Destroy() end)
        stale = TargetGui:FindFirstChild(leftover)
    end
end

local IsConsole = (function() local ok, v = pcall(GuiService.IsTenFootInterface, GuiService) return ok and v end)()
local IsMobile = not IsConsole and UIS.TouchEnabled and not UIS.KeyboardEnabled

-- runs before anything touches disk
if isfolder and makefolder then
    for _, path in { CONFIG.FOLDER, CONFIG.FOLDER .. "/configs" } do
        if not isfolder(path) then pcall(makefolder, path) end
    end
end

-- Populated by CreateWindow, exported as Library.UI.
local UI = {}

--=====================================================================================
--  3. Lifetime
--=====================================================================================

local function Scope()
    local tasks = {}
    return {
        Add = function(item) tasks[#tasks + 1] = item return item end,
        Clean = function()
            for i = #tasks, 1, -1 do
                local item = tasks[i]
                if typeof(item) == "RBXScriptConnection" then item:Disconnect()
                elseif typeof(item) == "Instance" then item:Destroy()
                elseif type(item) == "function" then item() end
            end
            table.clear(tasks)
        end,
    }
end

local Root = Scope()
function genv.SummitCleanup() Root.Clean() genv.SummitCleanup = nil end

-- forward declarations; the bodies live with the animation and instance helpers below
local FadeOut, FadeVisible, ResetInteractives, Snapshot, ApplySnapshot, PrimeFade, FadeWindowOut, FadeWindowIn

local cursorForced, savedMouseIcon, iconGuard
local function SetCursor(show)
    if show and not cursorForced then
        cursorForced, savedMouseIcon = true, UIS.MouseIconEnabled
        UIS.MouseIconEnabled = true
        -- MouseIconEnabled has no working changed signal, so reassert per frame while open
        iconGuard = RunService.Heartbeat:Connect(function()
            if not UIS.MouseIconEnabled then UIS.MouseIconEnabled = true end
        end)
    elseif not show and cursorForced then
        cursorForced = false
        if iconGuard then iconGuard:Disconnect() iconGuard = nil end
        UIS.MouseIconEnabled = savedMouseIcon
    end
end
Root.Add(function() SetCursor(false) end)

--=====================================================================================
--  4. Animation
--=====================================================================================

local KeybindRegistry, PendingBinds = {}, {}
local SliderDragging = false
local SPRING_EPS, V_THRESH, P_THRESH = 0.0001, 0.001, 0.001

-- Every branch of the spring reduces to the same pair of linear maps:
--     p1 = offset*A + v0*B + g
--     v1 = offset*C + v0*D
-- and A..D depend only on freq, damping and dt -- never on the component being driven. Solving
-- them ONCE per property instead of once per component is what keeps a UDim2 (4 components) from
-- paying four math.exp calls a frame. The per-component path below is two multiply-adds.
local function SpringCoeffs(freq, damp, dt)
    local f = freq * 6.283185307179586
    local decay = math.exp(-damp * f * dt)
    if damp == 1 then
        local fdt = f * dt
        return (1 + fdt) * decay, dt * decay, -(f * f * dt) * decay, (1 - fdt) * decay
    elseif damp < 1 then
        local c = math.sqrt(1 - damp * damp)
        local i, j = math.cos(f * c * dt), math.sin(f * c * dt)
        local z
        if c > SPRING_EPS then z = j / c else
            local a = dt * f
            z = a + ((a * a) * (c * c) * (c * c) / 20 - c * c) * (a * a * a) / 6
        end
        local y
        if f * c > SPRING_EPS then y = j / (f * c) else
            local b = f * c
            y = dt + ((dt * dt) * (b * b) * (b * b) / 20 - b * b) * (dt * dt * dt) / 6
        end
        return (i + damp * z) * decay, y * decay, -(z * f) * decay, (i - z * damp) * decay
    end
    local c = math.sqrt(damp * damp - 1)
    local r1, r2 = -f * (damp - c), -f * (damp + c)
    local k = 1 / (2 * f * c)
    local e1, e2 = math.exp(r1 * dt), math.exp(r2 * dt)
    local w = 1 + r1 * k
    return w * e1 - r1 * k * e2, k * (e2 - e1),
           w * r1 * e1 - r1 * r2 * k * e2, k * (r2 * e2 - r1 * e1)
end

-- Writes into a caller-owned buffer and returns the component count, so decomposing a value
-- allocates nothing. The two buffers below are consumed inside Tween before it can yield.
local DEC_GOAL, DEC_CUR = table.create(4), table.create(4)
local function Decompose(v, into)
    local t = typeof(v)
    if t == "number" then into[1] = v return 1, "number" end
    if t == "Color3" then into[1], into[2], into[3] = v.R, v.G, v.B return 3, "Color3" end
    if t == "UDim2" then
        into[1], into[2], into[3], into[4] = v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset
        return 4, "UDim2"
    end
    if t == "UDim" then into[1], into[2] = v.Scale, v.Offset return 2, "UDim" end
    if t == "Vector2" then into[1], into[2] = v.X, v.Y return 2, "Vector2" end
    return nil
end

local function Compose(kind, c)
    if kind == "number" then return c[1] end
    if kind == "Color3" then return Color3.new(math.clamp(c[1], 0, 1), math.clamp(c[2], 0, 1), math.clamp(c[3], 0, 1)) end
    if kind == "UDim2" then return UDim2.new(c[1], c[2], c[3], c[4]) end
    if kind == "UDim" then return UDim.new(c[1], c[2]) end
    return Vector2.new(c[1], c[2])
end

local Motors, MotorConn = {}, nil
local SCRATCH = table.create(4)     -- reused every step: Compose only reads the indices its kind needs
local function RunDone(g)
    local fns = g.f
    if not fns then return end
    g.f = nil
    for i = 1, #fns do task.spawn(fns[i]) end
end
local MAX_STEP = 0.05
local function StepMotors(dt)
    debug.profilebegin("SummitX/Motors")
    -- A frame hitch hands RenderStepped a dt of whole seconds. The underdamped branch would swing
    -- sin/cos through several periods in one step and the element visibly snaps past its goal, so
    -- a long frame is treated as one slow frame instead.
    if dt > MAX_STEP then dt = MAX_STEP end
    local active = false
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
            obj[prop] = Compose(m.k, SCRATCH)
            if settled then
                props[prop] = nil
                local g = m.g
                if g then
                    g.n -= 1
                    if g.n <= 0 then RunDone(g) end
                end
            else
                active = true
            end
        end
        if next(props) == nil then Motors[obj] = nil end
    end
    if not active and MotorConn then MotorConn:Disconnect() MotorConn = nil end
    debug.profileend()
end

local function CancelMotors(obj) Motors[obj] = nil end
Root.Add(function()
    if MotorConn then MotorConn:Disconnect() MotorConn = nil end
    table.clear(Motors)
end)

local Library = {
    Theme = {
        -- Deep indigo ground with a dusty periwinkle accent -- desaturated so it reads mulled
        -- rather than neon. Text is a soft lavender-white, not COLOR_WHITE, which goes clinical
        -- against these surfaces; COLOR_WHITE stays reserved for gradient carriers. Bad is left
        -- warm on purpose: rose opposite violet is what makes an error read as one.
        Background = Color3.fromRGB(15, 14, 24), Sidebar = Color3.fromRGB(9, 9, 16), Section = Color3.fromRGB(27, 25, 40),
        Text = Color3.fromRGB(226, 223, 236), SubText = Color3.fromRGB(162, 158, 187), TabText = Color3.fromRGB(193, 189, 213), Placeholder = Color3.fromRGB(96, 92, 118),
        Accent = Color3.fromRGB(128, 120, 184), Active = Color3.fromRGB(156, 147, 210), Close = Color3.fromRGB(154, 150, 179),
        Stroke = Color3.fromRGB(42, 39, 60), WindowStroke = Color3.fromRGB(60, 55, 86), ToggleActive = Color3.fromRGB(28, 25, 43),
        Chip = Color3.fromRGB(32, 29, 47), ToggleBorder = Color3.fromRGB(82, 75, 122), InputFocus = Color3.fromRGB(30, 27, 44), DropdownOption = Color3.fromRGB(28, 26, 42), BindBackground = Color3.fromRGB(8, 8, 14), SliderTrack = Color3.fromRGB(13, 12, 21),
        Bad = Color3.fromRGB(188, 98, 105),
    },
    TabOrder = {}, BlurEffect = nil, CurrentBlurVal = 0,
}
local Theme = table.freeze(Library.Theme)

-- Widget registry, tab list, loop lists and popup ownership. Deliberately NOT fields on Library:
-- a game script or another injected script assigning over Library.Flags would strand every
-- widget's saved value, and clearing Library.OpenPopup would leave the click-catcher stuck on
-- with two lists open. Reach them through GetFlag/SetFlag/RegisterLoop instead.
local Private = {
    Flags = {}, Tabs = {}, Popup = nil, Gen = genv.SummitGen,
    Loops = { RenderStepped = {}, Heartbeat = {}, Stepped = {} },
}

-- onDone is optional; when nil, no completion bookkeeping is allocated at all
local function Tween(obj, props, time, damping, onDone)
    local freq = math.clamp(1 / math.max(time or DEFAULT_TWEEN_TIME, 0.05), 2, 14)
    local damp = damping or 1
    local reg = Motors[obj]
    if not reg then reg = {} Motors[obj] = reg end
    local grp = onDone and { n = 0, f = { onDone } } or nil
    for prop, goal in props do
        local cur = obj[prop]
        if cur == goal then
            reg[prop] = nil     -- already there: don't spin up a motor just to sit still
        else
            local gn, kind = Decompose(goal, DEC_GOAL)
            local sn = Decompose(cur, DEC_CUR)
            if gn and sn and gn == sn then
                -- one flat array of position/velocity/goal triples rather than a table per
                -- component: a UDim2 tween used to cost five tables, and hover fires two a row
                local prev = reg[prop]
                local pc = prev and prev.c
                local comps = table.create(gn * 3)
                for i = 1, gn do
                    local b = (i - 1) * 3
                    comps[b + 1] = DEC_CUR[i]
                    comps[b + 2] = (pc and pc[b + 2]) or 0
                    comps[b + 3] = DEC_GOAL[i]
                end
                if grp then grp.n += 1 end
                reg[prop] = { c = comps, n = gn, f = freq, d = damp, k = kind, g = grp }
            else
                obj[prop] = goal
            end
        end
    end
    if grp and grp.n == 0 then task.defer(RunDone, grp) end
    if next(reg) == nil then
        Motors[obj] = nil
    elseif not MotorConn then
        MotorConn = RunService.RenderStepped:Connect(StepMotors)
    end
end

-- Never use a CanvasGroup: it renders to an offscreen buffer and softens text. Elements rest at
-- different values (a row at 0.15, its stroke at 0.55), so each interpolates from its own toward 1.
local FADE_TIME = 0.22
local FADE_INFO = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function ReadRest(v)
    if v:IsA("UIStroke") then
        return { Transparency = v.Transparency }
    elseif v:IsA("GuiObject") then
        local rest = { BackgroundTransparency = v.BackgroundTransparency }
        if v:IsA("TextLabel") or v:IsA("TextButton") or v:IsA("TextBox") then rest.TextTransparency = v.TextTransparency end
        if v:IsA("ImageLabel") or v:IsA("ImageButton") then rest.ImageTransparency = v.ImageTransparency end
        if v:IsA("ScrollingFrame") then rest.ScrollBarImageTransparency = v.ScrollBarImageTransparency end
        return rest
    end
    return nil
end

-- The caller must hold the returned array for the life of the animation; an Instance-keyed cache
-- loses entries mid-fade. `skip` leaves a subtree alone (the drag plate lives inside the window).
function Snapshot(root, skip)
    if not skip then
        -- one array from the engine, sized once. The recursive form below allocates a fresh
        -- GetChildren table at every node -- hundreds of them for a window-sized tree.
        local kids = root:GetDescendants()
        local snap = table.create(#kids + 1)
        local rest = ReadRest(root)
        if rest then snap[#snap + 1] = { root, rest } end
        for i = 1, #kids do
            rest = ReadRest(kids[i])
            if rest then snap[#snap + 1] = { kids[i], rest } end
        end
        return snap
    end
    local snap = table.create(64)
    local function walk(inst)
        if skip[inst] then return end
        local rest = ReadRest(inst)
        if rest then snap[#snap + 1] = { inst, rest } end
        local kids = inst:GetChildren()
        for i = 1, #kids do walk(kids[i]) end
    end
    walk(root)
    return snap
end

-- Two snapshots off one walk: the pane (background, border, shadow) and everything inside it.
-- They fade in stages -- see FadeVisible -- so only one layer is ever in motion.
local function SplitSnapshot(root, shellSet, skip)
    local shell, body = table.create(16), table.create(#root:GetDescendants())
    local function walk(inst)
        if skip and skip[inst] then return end
        local rest = ReadRest(inst)
        if rest then
            local into = shellSet[inst] and shell or body
            into[#into + 1] = { inst, rest }
        end
        local kids = inst:GetChildren()
        for i = 1, #kids do walk(kids[i]) end
    end
    walk(root)
    return shell, body
end

-- alpha 0 = resting, 1 = invisible. `time` omitted writes instantly.
function ApplySnapshot(snap, alpha, time)
    -- built once for the whole snapshot, not per instance
    local info = time and (time == FADE_TIME and FADE_INFO
        or TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)) or nil
    for i = 1, #snap do
        local inst, rest = snap[i][1], snap[i][2]
        if inst.Parent then
            local goal
            for prop, base in rest do
                goal = goal or {}
                goal[prop] = base + (1 - base) * alpha
            end
            if goal then
                if info then
                    -- no pcall: inst.Parent above already covers the only failure this can hit,
                    -- and wrapping it both allocated a closure per instance per fade and hid
                    -- real property errors behind a silent no-op
                    TweenService:Create(inst, info, goal):Play()
                else
                    for prop, v in goal do inst[prop] = v end
                end
            end
        end
    end
end

function FadeOut(inst)
    if typeof(inst) ~= "Instance" or not inst.Parent then return end
    ApplySnapshot(Snapshot(inst), 1, FADE_TIME)
    task.delay(FADE_TIME + 0.02, function() pcall(function() inst:Destroy() end) end)
end

-- Contents dissolve first while the pane is still solid, then the pane follows. Closing runs
-- inside-out, opening runs outside-in, so the window always has a surface to appear on.
local BODY_FADE, SHELL_FADE, FADE_STAGGER = 0.13, 0.18, 0.09
local FADE_TOTAL = FADE_STAGGER + SHELL_FADE
local ShellSnap, BodySnap, MenuGen, FadeBusy, FadePlan = nil, nil, 0, false, nil

-- Records WHAT to snapshot; the snapshot is deferred. Tabs are built after the window, so an eager
-- capture would hold the chrome only and the contents would never fade.
function PrimeFade(root, shellSet, skip) FadePlan = { root, shellSet, skip } end

-- ONLY on a transition that STARTS from the resting look -- a hide, or a drag grab. On the way
-- back in the window sits fully transparent, and re-reading records that as rest.
local function RefreshFade()
    if not FadePlan then return false end
    if not FadeBusy then
        ResetInteractives()     -- a button still under the cursor must not be captured hovered
        ShellSnap, BodySnap = SplitSnapshot(FadePlan[1], FadePlan[2], FadePlan[3])
    end
    return ShellSnap ~= nil
end

function FadeVisible(inst, show)
    MenuGen += 1
    local gen = MenuGen
    if show then
        -- reuses whatever the matching hide captured; nothing to read while it is invisible
        if not ShellSnap then inst.Visible = true return end
        FadeBusy = true
        inst.Visible = true
        ApplySnapshot(ShellSnap, 1) ApplySnapshot(BodySnap, 1)
        ApplySnapshot(ShellSnap, 0, SHELL_FADE)
        task.delay(FADE_STAGGER, function()
            if gen == MenuGen then ApplySnapshot(BodySnap, 0, BODY_FADE) end
        end)
    else
        if not RefreshFade() then return end
        FadeBusy = true
        ApplySnapshot(BodySnap, 1, BODY_FADE)
        task.delay(FADE_STAGGER, function()
            if gen == MenuGen then ApplySnapshot(ShellSnap, 1, SHELL_FADE) end
        end)
    end
    task.delay(FADE_TOTAL + 0.05, function()
        if gen ~= MenuGen then return end
        FadeBusy = false
        if show then
            ApplySnapshot(ShellSnap, 0) ApplySnapshot(BodySnap, 0)   -- land exactly on rest
        else
            inst.Visible = false
        end
    end)
end

-- The drag plate's pair, staged like the menu fade: the plate is translucent, so the window must
-- be gone before it appears. Out HOLDS the snapshot until the matching In -- a drag outlasts any
-- fade, and letting FadeBusy lapse lets the release read fully-faded values as the resting state.
function FadeWindowOut(bodyTime, shellTime, stagger)
    MenuGen += 1
    local gen = MenuGen
    if not RefreshFade() then return end
    FadeBusy = true
    ApplySnapshot(BodySnap, 1, bodyTime)
    task.delay(stagger, function()
        if gen == MenuGen then ApplySnapshot(ShellSnap, 1, shellTime) end
    end)
end

function FadeWindowIn(bodyTime, shellTime, stagger)
    MenuGen += 1
    local gen = MenuGen
    if not ShellSnap then return end
    -- reverse order: the pane comes back first so the contents never appear over a see-through one
    ApplySnapshot(ShellSnap, 0, shellTime)
    task.delay(stagger, function()
        if gen == MenuGen then ApplySnapshot(BodySnap, 0, bodyTime) end
    end)
    task.delay(stagger + bodyTime + 0.05, function()
        if gen ~= MenuGen then return end
        ApplySnapshot(ShellSnap, 0) ApplySnapshot(BodySnap, 0)
        FadeBusy = false
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

-- props wins, so a default it overrides is skipped rather than written and immediately replaced:
-- every one of those is a round trip across the Lua/C++ boundary, and this runs ~500 times a build.
local function Create(class, parent, props)
    local obj = Instance.new(class)
    local def = CLASS_DEFAULTS[class]
    if def then
        for k, v in def do
            if props[k] == nil then obj[k] = v end
        end
    end
    for k, v in props do obj[k] = v end
    if parent then obj.Parent = parent end     -- parented last: no reparent cost per property
    return obj
end

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

-- Stops are written directly onto a white carrier, not multiplied against a tinted one: a
-- UIGradient multiplies, which can only darken, and on near-black surfaces that flattens the ramp.
-- Writing them lets the top sit ABOVE the base colour, which is what reads as depth.
-- The floor is a deep indigo, not black: lerping to black drags saturation out as it darkens,
-- so a tall surface greys off at the bottom and the falloff reads as a smudge instead of depth.
local GLASS_LIFT, GLASS_FALL = Color3.fromRGB(64, 57, 101), Color3.fromRGB(5, 5, 10)

-- lift = how far the top rises above the base, fall = how far the bottom sinks.
local function Glass(obj, lift, fall)
    -- LINEAR, and it has to be. UIGradient interpolates in 8-bit, so a band is however many
    -- pixels the ramp spends inside one integer step, and a band edge is only visible when it is
    -- WIDE -- tightly packed edges blur into a smooth ramp. An eased curve spends its travel at
    -- the top and crawls across the bottom, which is what put 38px stripes down the lower half.
    -- Straight-line travel with the deepest floor the palette allows packs the same drop into
    -- 22px bands. Roblox cannot dither a gradient, so edge spacing is the only lever there is.
    lift, fall = lift or 0.13, fall or 1.00
    local base = obj.BackgroundColor3
    obj.BackgroundColor3 = COLOR_WHITE
    -- Two stops: linear interpolation between them is exactly what the sampled curve produced,
    -- so the extra keypoints only cost build time.
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
local Interactives = {}
function ResetInteractives()
    for target, entry in Interactives do
        if not target.Parent then
            Interactives[target] = nil
        elseif not entry.gate or entry.gate() then
            -- gated ones opt out: a selected tab's background is not its hover state
            CancelMotors(target)
            for prop, v in entry.Rest() do target[prop] = v end
        end
    end
end

local function Interactive(btn, spec)
    local target = spec.Target or btn
    local over, out, down, t = spec.Over, spec.Out, spec.Down, spec.Time or 0.14
    local gate = spec.Enabled
    local function Resolve(v) return type(v) == "function" and v() or v end
    local function Allowed() return not gate or gate() end

    if out then
        Interactives[target] = { Rest = function() return Resolve(out) end, gate = gate }
        -- strong key: without this a destroyed widget pins its Instance until the next minimise
        btn.Destroying:Connect(function() Interactives[target] = nil end)
    end
    if over then btn.MouseEnter:Connect(function() if Allowed() then Tween(target, Resolve(over), t) end end) end
    if out then btn.MouseLeave:Connect(function() if Allowed() then Tween(target, Resolve(out), t) end end) end
    if down then
        btn.MouseButton1Down:Connect(function() if Allowed() then Tween(target, Resolve(down), t * 0.5) end end)
        btn.MouseButton1Up:Connect(function() if Allowed() then Tween(target, Resolve(over or out), t) end end)
    end
    return btn
end

--=====================================================================================
--  6. Input & drag
--=====================================================================================

local function IsPress(t) return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch end
local function IsMove(t) return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch end

-- keeps the caret inside a fixed-width field by sliding the TextBox behind a clipping window
local function CaretFollow(box, clip)
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
-- coalesces InputChanged into ONE apply per RenderStepped; every drag in the library routes here
local function BeginDrag(onMove)
    dragScope.Clean()
    local latest
    dragScope.Add(UIS.InputChanged:Connect(function(i)
        if IsMove(i.UserInputType) then latest = i end
    end))
    dragScope.Add(RunService.RenderStepped:Connect(function()
        if latest then local i = latest latest = nil onMove(i) end
    end))
    dragScope.Add(UIS.InputEnded:Connect(function(i)
        if IsPress(i.UserInputType) then dragScope.Clean() end
    end))
    dragScope.Add(function() if latest then onMove(latest) latest = nil end end)
end

-- onMoving(true/false) brackets the part of the gesture that actually moves something, so a
-- plain click on the handle never fires it -- only a real drag past the 5px threshold does.
local function MakeDraggable(handle, target, onStart, onMoving)
    target = target or handle
    local dragStart, startTL, host, active
    handle.InputBegan:Connect(function(input)
        if not IsPress(input.UserInputType) then return end
        if onStart then onStart() end
        host = target.Parent
        dragStart, active = input.Position, false
        startTL = target.AbsolutePosition - (host and host.AbsolutePosition or Vector2.new(0, 0))
        BeginDrag(function(i)
            local delta = i.Position - dragStart
            if not active and delta.Magnitude < 5 then return end
            if not active and onMoving then onMoving(true) end
            active = true
            local vp = host and host.AbsoluteSize or Vector2.new(1280, 720)
            local size, ap, pos = target.AbsoluteSize, target.AnchorPoint, target.Position
            local tlx = math.clamp(startTL.X + delta.X, 100 - size.X, vp.X - 100)
            local tly = math.clamp(startTL.Y + delta.Y, 0, vp.Y - 44)
            target.Position = UDim2.new(pos.X.Scale, tlx + size.X * ap.X - vp.X * pos.X.Scale,
                                        pos.Y.Scale, tly + size.Y * ap.Y - vp.Y * pos.Y.Scale)
        end)
        -- Registered AFTER BeginDrag, which opens with dragScope.Clean() and would wipe it. Cleanups run
        -- in reverse, so this fires before BeginDrag's trailing move.
        if onMoving then
            dragScope.Add(function()
                if active then onMoving(false) end
                active = false
            end)
        end
    end)
end

--=====================================================================================
--  7. Notifications, errors, observers
--=====================================================================================

local NOTIFY_MAX, NotifyGui, NotifyHolder, NotifyOrder, NotifyLive = 6, nil, nil, 0, {}
local function EnsureNotify()
    if NotifyGui and NotifyGui.Parent then return end
    NotifyGui = Create("ScreenGui", TargetGui, { Name = "SummitToasts", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 10000 })
    Protect(NotifyGui)
    Root.Add(function() FadeOut(NotifyGui) end)
    NotifyHolder = Create("Frame", NotifyGui, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.new(0, 318, 1, -40), BackgroundTransparency = 1 })
    Create("UIListLayout", NotifyHolder, { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 10) })
end

-- tall enough for L.Corner8 to resolve its full curve (needs >= 2x the radius); only the top 2px
-- is ever on screen
local BAR_BODY = 40

-- Layout-stable typewriter: the final string goes to .Text up front and only MaxVisibleGraphemes
-- animates, so TextBounds and every AutomaticSize ancestor settle on frame one. Counts against
-- ContentText, so RichText markup survives. Returns a stop function.
local function Graphemes(s)
    local n = 0
    for _ in utf8.graphemes(s) do n += 1 end
    return n
end
-- Seconds per grapheme, floored and capped: never a crawl on a paragraph, never a blink on
-- three words.
local function RevealTime(n) return math.clamp(n * 0.024, 0.18, 2.2) end

local function RevealText(label, time, onDone)
    local total = Graphemes(label.ContentText)
    if total == 0 then
        if onDone then onDone() end
        return function() end
    end
    time = time or RevealTime(total)
    label.MaxVisibleGraphemes = 0
    local conn, t0, dead = nil, os.clock(), false
    local function stop(finish)
        if dead then return end
        dead = true
        if conn then conn:Disconnect() conn = nil end
        -- -1 is "no limit". Leaving a COUNT behind would silently clip the next text this
        -- label is given.
        if finish then label.MaxVisibleGraphemes = -1 end
    end
    conn = RunService.Heartbeat:Connect(function()
        if not label.Parent then stop(false) return end
        local a = (os.clock() - t0) / time
        if a >= 1 then
            stop(true)
            if onDone then onDone() end
            return
        end
        label.MaxVisibleGraphemes = math.floor(total * a)
    end)
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
        sub = Create("TextLabel", body, { Text = cfg.SubContent, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = Theme.Placeholder, TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3 })
    end
    -- Blanked at creation: the sub-line types second and would sit readable under the body otherwise.
    -- Zero graphemes still reserves the label's full height, so the card does not move.
    if typing and sub and content then sub.MaxVisibleGraphemes = 0 end

    local closed = false
    local cardSnap                      -- taken below, once the card is fully built
    local stopReveal                    -- set only when Typewrite is on
    local entry = { Card = card, Instance = holder }
    function entry.Close()
        if closed then return end
        closed = true
        if stopReveal then stopReveal(true) stopReveal = nil end
        NotifyLive[entry] = nil
        holder.Size = UDim2.new(1, 0, 0, holder.AbsoluteSize.Y)
        holder.AutomaticSize = Enum.AutomaticSize.None
        ApplySnapshot(cardSnap, 1, 0.22)
        Tween(card, { Position = UDim2.new(1, 24, 0, 0) }, 0.22)
        -- destroy when the collapse actually lands, not on a guessed delay
        local gone = false
        local function Reap()
            if gone then return end
            gone = true
            if holder.Parent then holder:Destroy() end
        end
        Tween(holder, { Size = UDim2.new(1, 0, 0, 0) }, 0.3, 1, Reap)
        task.delay(1, Reap)     -- safety net if the motor is cancelled mid-flight
    end
    -- cancel first: a reveal still in flight is holding a grapheme COUNT on this label, and writing
    -- new text under it would show only the first few characters of the new string
    function entry.SetContent(txt)
        if not content then return end
        if stopReveal then stopReveal(true) stopReveal = nil end
        content.Text = txt
    end

    local close = Create("TextButton", card, { Text = "×", Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12), TextColor3 = Theme.Placeholder, Font = Enum.Font.GothamMedium, TextSize = 18 })
    Interactive(close, { Over = { TextColor3 = COLOR_WHITE }, Out = { TextColor3 = Theme.Placeholder } })
    close.MouseButton1Click:Connect(entry.Close)

    NotifyLive[entry] = true
    local live = 0
    for _ in NotifyLive do live += 1 end
    if live > NOTIFY_MAX then
        local oldest
        for e in NotifyLive do
            if e ~= entry and (not oldest or e.Instance.LayoutOrder < oldest.Instance.LayoutOrder) then oldest = e end
        end
        if oldest then oldest.Close() end
    end

    cardSnap = Snapshot(card)           -- resting values, then arm it hidden and animate in
    ApplySnapshot(cardSnap, 1)
    ApplySnapshot(cardSnap, 0, 0.34)
    Tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.34, 0.78)
    local dur = cfg.Duration
    if dur == nil then dur = 5 end
    -- Body types first, then the sub-line off its onDone, sharing one budget capped against the
    -- toast's lifetime so nothing is still typing as the card slides out. The title is never typed.
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
        TweenService:Create(bar, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, BAR_BODY) }):Play()
        task.delay(dur, entry.Close)
    else
        bar.Visible = false
    end
    return entry
end

-- xpcall so the stack is captured at the throw site: full traceback to console, first line to toast
local ErrLast, ErrAt = nil, 0
local function Traceback(err) return debug.traceback(tostring(err), 2) end
local function ReportErr(err)
    local msg = tostring(err)
    local first = msg:match("^[^\n]*") or msg
    local now = os.clock()
    if first == ErrLast and now - ErrAt < 5 then return end
    ErrLast, ErrAt = first, now
    task.defer(warn, "[" .. CONFIG.HUB_NAME .. "] " .. msg)
    pcall(function()
        Library:Notify({ Title = "Callback error", Content = (first:gsub("^.-:%d+:%s*", ""):gsub("<", "&lt;")), Duration = 6, Type = "error" })
    end)
end
local function Guard(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = xpcall(fn, Traceback, ...)
    if not ok then ReportErr(err) end
end
local function RunGuarded(fn, ...)      -- one shared body: no closure per invocation
    local ok, err = xpcall(fn, Traceback, ...)
    if not ok then ReportErr(err) end
end
local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return end
    task.spawn(RunGuarded, fn, ...)
end

local Observers = setmetatable({}, { __mode = "k" })
-- Every table leaving the library is copied first, so a consumer cannot edit widget state or
-- another consumer's copy. Shallow is right -- widget values are flat arrays of strings.
local function CloneValue(v)
    return type(v) == "table" and table.clone(v) or v
end

local function AddObserver(handle, fn)
    if type(fn) ~= "function" then return function() end end
    local list = Observers[handle]
    if not list then list = {} Observers[handle] = list end
    list[fn] = true
    return function() list[fn] = nil end
end
-- one copy per listener, not one for the whole fan-out: two observers sharing a table means the
-- second sees whatever the first did to it
local function FireObservers(handle, value)
    local list = Observers[handle]
    if not list then return end
    for fn in list do SafeCall(fn, CloneValue(value)) end
end

--=====================================================================================
--  8. Icons
--=====================================================================================

local TAB_ICONS = { Player = "user", Visuals = "eye", Teleport = "map-pin", Combat = "swords", Settings = "settings", Misc = "layout-grid" }
local IconSets, PendingIcons = nil, {}
local function ApplyIcon(img, iconName, setName)
    if not IconSets then PendingIcons[#PendingIcons + 1] = { img, iconName, setName } return end
    local set = IconSets[setName or "Lucide"]
    local id = set and set[iconName]
    img.Image = id and ("rbxassetid://" .. id) or ""
end

-- The endpoint is a stub that loadstrings a second, larger payload (~1s). The resolved table is
-- cached to disk (~4ms to decode, works offline). Two things invalidate it: the stub pointing
-- somewhere new, and ICON_SCHEMA -- bump that and every client re-fetches, which is the only way
-- to retire a cache whose shape this file no longer reads the same way.
local ICON_URL, ICON_SCHEMA = "https://raw.nebulasoftworks.xyz/nebula-icon-library-loader", 1
local function ValidSets(sets)
    if type(sets) ~= "table" or type(sets.Lucide) ~= "table" or next(sets.Lucide) == nil then return nil end
    return sets
end
local function FlushIcons(sets)
    IconSets = sets
    for _, p in PendingIcons do pcall(ApplyIcon, p[1], p[2], p[3]) end
    table.clear(PendingIcons)
end
task.spawn(function()
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
    if ok then
        local ok2, fn = pcall(loadstring, stub)
        if ok2 and type(fn) == "function" then
            local ok3, result = pcall(fn)
            sets = ok3 and ValidSets(result) or nil
        end
    end
    if sets then
        if writefile then
            local packs = {}
            for packName, tbl in sets do
                if type(tbl) == "table" then packs[packName] = tbl end -- helper functions can't be encoded
            end
            pcall(function()
                writefile(cacheFile, HttpService:JSONEncode({ __v = ICON_SCHEMA, __src = innerUrl or ICON_URL, sets = packs }))
            end)
        end
        if not IconSets then FlushIcons(sets) end
    elseif not IconSets then
        FlushIcons({})
    end
end)

--=====================================================================================
--  9. Loops
--=====================================================================================

local LoopSignals = { RenderStepped = RunService.RenderStepped, Heartbeat = RunService.Heartbeat, Stepped = RunService.Stepped }
local LoopConnections = {}
local function DispatchLoops(loops, ...)
    if #loops == 0 then return end
    debug.profilebegin("SummitX/Loops")
    local now, dead = os.clock(), nil
    for i = 1, #loops do
        local loop = loops[i]
        local run = loop.Active
        if loop.ShouldRun then run = loop.ShouldRun() end
        if loop.Dead then run = false end
        if run and loop.Interval then
            if now - (loop._last or 0) < loop.Interval then run = false else loop._last = now end
        end
        if loop.Removed then
            dead = dead or {}       -- swept after the pass so visit order stays registration order
            dead[#dead + 1] = i
            run = false
        end
        if run then
            -- a throwing loop would otherwise starve every loop after it, every single frame
            local ok, err = xpcall(loop.Func, Traceback, ...)
            if ok then
                loop.Errors = nil
            else
                loop.Errors = (loop.Errors or 0) + 1
                if loop.Errors >= 5 then loop.Dead = true ReportErr("loop stopped after 5 errors: " .. tostring(err))
                else ReportErr(err) end
            end
        end
    end
    if dead then
        for i = #dead, 1, -1 do table.remove(loops, dead[i]) end
    end
    debug.profileend()
end

function Library:RegisterLoop(loopType, func, shouldRun, interval)
    local entry = { Func = func, Active = true, ShouldRun = shouldRun, Interval = interval }
    table.insert(Private.Loops[loopType], entry)
    if not LoopConnections[loopType] then
        LoopConnections[loopType] = true
        Root.Add(LoopSignals[loopType]:Connect(function(...) DispatchLoops(Private.Loops[loopType], ...) end))
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

-- SavedConfig stays live as a mirror of the file, so a widget built after LoadConfig still restores.
local function RegisterFlag(flag, handle)
    if not flag then return end
    if Private.Flags[flag] then
        warn(("[%s] duplicate flag %q — the later widget wins and the earlier one stops saving. Pass a unique Flag."):format(CONFIG.HUB_NAME, flag))
    end
    Private.Flags[flag] = handle
    if SavedConfig ~= nil and SavedConfig[flag] ~= nil and not loading then
        loading = true
        Guard(handle.Set, SavedConfig[flag])
        loading = false
    end
end
local function UnregisterFlag(flag) if flag then Private.Flags[flag] = nil end end

-- Merges over the file: saving only the flags that exist right now would wipe settings whose
-- widget wasn't created this session.
function Library:SaveConfig()
    if not canFile then return end
    local data = SavedConfig or {}
    for flag, h in Private.Flags do
        local ok, v = pcall(h.Get)
        if ok then data[flag] = v end
    end
    SavedConfig = data
    pcall(writefile, CONFIG.CONFIG_FILE, HttpService:JSONEncode(data))
end
-- One timer per burst of edits. A Heartbeat entry would wake 60 times a second forever just to
-- ask whether 2s had passed on a config nobody is touching.
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
    if not ok or type(data) ~= "table" then writefile(CONFIG.CONFIG_FILE, "{}") return end
    SavedConfig = data
    loading = true
    for flag, v in data do
        local h = Private.Flags[flag]
        if h then Guard(h.Set, v) end
    end
    loading = false
end

function Library:GetFlag(flag)
    local h = Private.Flags[flag]
    if not h then return nil end
    -- not `ok and v or nil` — that would turn a false toggle into nil
    local ok, v = pcall(h.Get)
    -- copied on the way out, so a caller sorting or clearing the result can't reach back into
    -- the widget that produced it
    if ok then return CloneValue(v) end
    return nil
end
function Library:SetFlag(flag, value)
    local h = Private.Flags[flag]
    if not h then return false end
    Guard(h.Set, value)
    return true
end

--=====================================================================================
--  10b. Premium gating
--=====================================================================================
--
--  Widgets are built before the whitelist answers, so locking is reactive: gated widgets register
--  and re-evaluate when it lands. An overlay absorbs input and Bind suppresses the callback.

Library.IsPremium = false
Library.PremiumState = "checking"        -- checking | free | premium | blocked

local PremiumGates = setmetatable({}, { __mode = "k" })
local PremiumHooks = {}
local AcceptedKey = nil

-- Each state copies a different link, and "checking" copies none: putting a purchase link on the
-- clipboard while access is still resolving tells someone to buy what they may already own.
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
            pcall(writefile, K.SaveFile, AcceptedKey)
        elseif not value and delfile and isfile(K.SaveFile) then
            pcall(delfile, K.SaveFile)
        end
    end
    if changed then
        for i = 1, #PremiumHooks do SafeCall(PremiumHooks[i], value) end
    end
end
function Library:OnPremiumChanged(fn)
    if type(fn) == "function" then PremiumHooks[#PremiumHooks + 1] = fn end
end

local function Gate(host, props, corner)
    if not props.Premium then return end
    -- cancel out any UIPadding on the host, or the overlay insets and leaves the edges clickable
    local pad = host:FindFirstChildOfClass("UIPadding")
    local pl = pad and pad.PaddingLeft.Offset or 0
    local pr = pad and pad.PaddingRight.Offset or 0
    local pt = pad and pad.PaddingTop.Offset or 0
    local pb = pad and pad.PaddingBottom.Offset or 0
    local overlay = Create("TextButton", host, { Size = UDim2.new(1, pl + pr, 1, pt + pb),
        Position = UDim2.fromOffset(-pl, -pt), BackgroundColor3 = COLOR_BLACK,
        BackgroundTransparency = 0.55, ZIndex = 60, Text = "" })
    Decorate(overlay, corner or L.Corner8)
    -- centred on rows, but a button's own label is centred too, so shift the lock aside there
    local ownText = host:IsA("TextButton") and host.Text ~= "" and host.TextXAlignment == Enum.TextXAlignment.Center
    local lock = Create("ImageLabel", overlay, { Size = UDim2.new(0, 16, 0, 16),
        AnchorPoint = ownText and Vector2.new(1, 0.5) or Vector2.new(0.5, 0.5),
        Position = ownText and UDim2.new(1, -(L.PadX + pr), 0.5, 0) or UDim2.fromScale(0.5, 0.5),
        ImageColor3 = COLOR_WHITE, ImageTransparency = 0.25, ZIndex = 61 })
    ApplyIcon(lock, "lock")
    overlay.MouseButton1Click:Connect(PremiumNag)
    PremiumGates[overlay] = true
    overlay.Visible = not Library.IsPremium
    overlay.Active = not Library.IsPremium
    return overlay
end

-- Blocking; call inside a spawn. `attempts` overrides the configured retry count, so the boot check
-- can run single-attempt and never stall the key gate behind two backoffs.
local function RunPremiumCheck(attempts)
    local uid = tostring(LocalPlayer.UserId)
    local W = CONFIG.WHITELIST
    attempts = math.max(1, attempts or W.Attempts)
    -- unconfigured: everyone is free rather than everyone hitting a dead URL
    if not W.Base or W.Base == "" or W.Base:find("PASTE_") then
        Library:SetPremium(false, "free")
        return
    end

    local function fetch(file)
        for attempt = 1, attempts do
            -- cache-buster: GitHub's CDN otherwise serves a stale table for minutes after a publish
            local url = W.Base .. file .. "?_=" .. tostring(os.time()) .. tostring(attempt)
            local ok, body = pcall(game.HttpGet, game, url)
            if ok and type(body) == "string" and #body > 0 then
                local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
                if decoded and type(data) == "table" then return data end
            end
            if attempt < attempts then task.wait(1.5 * attempt) end
        end
        return nil
    end

    local blacklist = fetch(W.Blacklist)
    if blacklist and blacklist[uid] then
        Library:SetPremium(false, "blocked")
        if W.KickBlacklisted and genv.SummitCleanup then
            Library:Notify({ Title = "Access revoked", Content = "This account is blocked.", Type = "error", Duration = 6 })
            task.delay(3, function() if genv.SummitCleanup then genv.SummitCleanup() end end)
        end
        return
    end

    local whitelist = fetch(W.Whitelist)
    if whitelist == nil then
        Library:SetPremium(false, "free")   -- unreachable: degrade, don't lock out
        return
    end
    Library:SetPremium(whitelist[uid] == true, whitelist[uid] and "premium" or "free")
end

local function StartPremiumCheck()
    task.spawn(RunPremiumCheck)
end

function Library:RegisterTab(name, builderFunc, subtitle, icon)
    table.insert(Private.Tabs, { Name = name, Build = builderFunc, Subtitle = subtitle, Icon = icon or TAB_ICONS[name] or "circle" })
end
function Library:BuildTabs(windowObj) for _, t in Private.Tabs do t.Build(windowObj:MakeTab(t.Name, t.Subtitle, t.Icon), windowObj) end end

--=====================================================================================
--  11. Rows, bindings, widget registry
--=====================================================================================

--------------------------------------------------------------------------- popup ownership
--
--  One overlay at a time, so ownership is a single slot: claiming evicts whoever held it. An owner
--  is any table with a Close(); the engine never reaches into its instances.

local function ReleasePopup(owner)
    -- a stale release from a popup that was already evicted must not clear the new owner
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
    if prev then SafeCall(prev.Close) end
    if UI.Catcher then UI.Catcher.Visible = true end
end

local function CloseActivePopup()
    local cur = Private.Popup
    if cur then SafeCall(cur.Close) end
end

--------------------------------------------------------------------------- widget factory

local KEY_SHORT = {
    LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
    LeftAlt = "LAlt", RightAlt = "RAlt", LeftSuper = "LWin", RightSuper = "RWin",
    Backspace = "Bksp", CapsLock = "Caps", PageUp = "PgUp", PageDown = "PgDn", Delete = "Del",
    Insert = "Ins", Escape = "Esc", Return = "Enter", KeypadEnter = "NumEnter", PrintScreen = "PrtSc",
}
local function KeyLabel(k) return KEY_SHORT[k] or k end

-- A row is a HOST, not a widget: a label block on the left, a rail on the right that controls
-- attach into. Several controls share one rail, so nothing declares how much width to reserve --
-- the rail measures itself and the label block flex-fills the rest. The rail is built on first use.
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
    -- L.RowMin falls out of this: a 15px title between two 15px pads is exactly 45, so the row
    -- holds its minimum height without a UISizeConstraint.
    Create("UIPadding", content, { PaddingTop = UDim.new(0, L.PadY), PaddingBottom = UDim.new(0, L.PadY) })

    local desc = props.Description or props.Content
    local hasDesc = desc ~= nil and desc ~= ""
    -- with nothing to stack beneath it the title needs no wrapper, and is its own label block
    local holder = hasDesc and Create("Frame", content, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }) or nil
    if holder then List(holder, L.LabelGap) end
    local nameLbl = Create("TextLabel", holder or content, { Text = props.Name or "", TextColor3 = Theme.SubText, Font = Enum.Font.GothamSemibold,
        TextSize = L.TitleSize, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 15), LayoutOrder = 1 })
    -- Fill takes whatever the rail leaves over, which is what removes the per-widget reserve table
    Create("UIFlexItem", holder or nameLbl, { FlexMode = Enum.UIFlexMode.Fill })
    local descLbl
    if hasDesc then
        descLbl = Create("TextLabel", holder, { Text = desc, TextColor3 = Theme.Placeholder, Font = Enum.Font.Gotham, TextSize = L.DescSize,
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
    return frame, stroke, nameLbl, descLbl, Rail
end

-- Flag naming, config registration, dirty marking, callback dispatch, observers, teardown.
-- The widget owns its value; Bind returns the handle plus a Changed(value) to fan it out.
local function FlagFor(ctx, props) return props.Flag or (ctx.TabName .. "::" .. tostring(props.Name)) end

local function Bind(ctx, props, flag, getter, setter, extraFlags, loopEntry)
    local h = { Flag = flag, Get = getter, Set = setter, OnChanged = AddObserver }
    RegisterFlag(flag, { Get = getter, Set = setter })

    local flags = { flag }
    if extraFlags then for _, f in extraFlags do flags[#flags + 1] = f end end
    -- idempotent, and separate from Destroy so DefineWidget can also run it off Destroying
    local torn = false
    function h.Teardown()
        if torn then return end
        torn = true
        for _, f in flags do UnregisterFlag(f) end
        if loopEntry then Library:RemoveLoop(loopEntry) end
    end
    function h.Destroy()
        h.Teardown()
        -- a standalone widget owns the row it was given, so it takes the label with it; a control
        -- sharing a row only ever removes itself
        local inst = h.Row or h.Instance
        if inst and inst.Parent then inst:Destroy() end
    end

    return h, function(value)       -- Changed(value)
        MarkDirty(flag)
        -- a premium widget still remembers its value, it just can't act on it while locked
        if not (props.Premium and not Library.IsPremium) then
            SafeCall(props.Callback, CloneValue(value))
        end
        FireObservers(h, value)
    end
end

local function Expect(props, field, kind)
    assert(props[field] ~= nil, ("[%s] %s is required"):format(CONFIG.HUB_NAME, field))
    if kind then
        assert(typeof(props[field]) == kind, ("[%s] %s must be a %s, got %s"):format(CONFIG.HUB_NAME, field, kind, typeof(props[field])))
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

--------------------------------------------------------------------------- host rows
--
--  A host owns one row and lends out its rail. The standalone `tab:AddToggle{...}` is the same
--  thing with the row made for you, so the two shapes cannot drift.
--
--  Exclusive marks that made-for-you case: the whole row is the click target and lights up with
--  the state. On a shared row a row-wide target would swallow clicks meant for its neighbours.

local Host = {}
Host.__index = Host

function Container:AddRow(props, exclusive)
    props = props or {}
    local frame, stroke, nameLbl, descLbl, Rail = Row(self.Parent, props, props.Active)
    local host = setmetatable({
        Ctx = self, Instance = frame, Stroke = stroke, NameLabel = nameLbl, DescLabel = descLbl,
        Rail = Rail, Exclusive = exclusive or false,
    }, Host)
    host.Gated = Gate(frame, props) ~= nil
    return host
end

function Host:SetTitle(t) self.NameLabel.Text = t end
function Host:SetDescription(t) if self.DescLabel then self.DescLabel.Text = t end end
function Host:Destroy() self.Instance:Destroy() end

local function DefineControl(kind, build)
    Host["Add" .. kind] = function(self, props)
        props = props or {}
        local h = WireTeardown(build(self.Ctx, props, self))
        -- a premium row already wears the lock; a premium control on a shared row wears its own
        if type(h) == "table" and props.Premium and not self.Gated and h.Instance then
            Gate(h.Instance, props, L.Corner6)
        end
        return h
    end
    Container["Add" .. kind] = function(self, props)
        props = props or {}
        local host = self:AddRow(props, true)
        local h = host["Add" .. kind](host, props)
        if type(h) == "table" then
            h.Row = host.Instance
        elseif h == nil then
            -- a control that declined to build -- a keybind on mobile -- leaves no orphan label
            host.Instance:Destroy()
        end
        return h
    end
end

--------------------------------------------------------------------------- keybind pill

-- laid out by the rail, so it carries no position of its own -- that is what lets it share a row
-- with another control without either knowing about the other
local function BindPill(parent, props, action, saveId, canHold)
    if IsMobile then return nil end
    local pill = Create("TextButton", parent, { Text = KeyLabel(props.Keybind), RichText = false, AutomaticSize = Enum.AutomaticSize.X,
        -- 5, ahead of the toggle ring's 10: the bind reads to the LEFT of the checkmark
        Size = UDim2.new(0, 0, 0, 22), LayoutOrder = 5,
        BackgroundColor3 = Theme.BindBackground, BackgroundTransparency = 0.5, TextColor3 = Theme.SubText, Font = Enum.Font.GothamBold, TextSize = 10 })
    Decorate(pill, L.Corner6, {Theme.Stroke, 0.7, 1}, {nil, nil, 10, 10})
    Create("UISizeConstraint", pill, { MinSize = Vector2.new(44, 22) })
    Interactive(pill, { Over = {BackgroundTransparency = 0.2}, Out = {BackgroundTransparency = 0.5}, Time = 0.15 })

    local entry = { Key = props.Keybind, Action = action, Mode = "Toggle", CanHold = canHold }
    function entry.Render() pill.Text = KeyLabel(entry.Key) .. (entry.Mode == "Hold" and "  HOLD" or "") end
    KeybindRegistry[pill] = entry
    -- the flag goes with it: a pill can be destroyed on its own, and one left pointing at a dead
    -- pill answers config saves with a stale "NONE"
    pill.Destroying:Connect(function()
        KeybindRegistry[pill], PendingBinds[pill] = nil, nil
        UnregisterFlag(saveId)
    end)
    pill.MouseButton1Click:Connect(function()
        pill.Text = "..."
        Tween(pill, {TextColor3 = Theme.Accent, BackgroundColor3 = Theme.Section})
        PendingBinds[pill] = true
    end)
    if canHold then
        pill.MouseButton2Click:Connect(function()
            entry.Mode = entry.Mode == "Hold" and "Toggle" or "Hold"
            entry.Render()
            MarkDirty("keybind")
        end)
    end
    RegisterFlag(saveId, {
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
    })
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

DefineWidget("Label", function(ctx, props)
    local text = type(props) == "string" and props or props.Name or props.Text or ""
    local lbl = Create("TextLabel", ctx.Parent, { Text = text, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextColor3 = Theme.SubText, Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
    Decorate(lbl, nil, nil, {2, 2, L.PadX, L.PadX})
    return lbl
end)

DefineWidget("Paragraph", function(ctx, props)
    -- never asks for a rail, so it costs a row's chrome and nothing else
    local frame, stroke, titleLbl, bodyLbl = Row(ctx.Parent, {
        Name = props.Name or props.Title or "",
        Description = props.Content or props.Text or " ",
    })
    frame.BackgroundTransparency = 0.4
    stroke.Transparency = 0.7
    titleLbl.TextColor3 = Theme.Text
    if bodyLbl then bodyLbl.TextSize = 12 bodyLbl.TextColor3 = Theme.SubText end
    return {
        Instance = frame,
        SetTitle = function(t) titleLbl.Text = t end,
        SetContent = function(t) if bodyLbl then bodyLbl.Text = t end end,
    }
end)

DefineWidget("Watermark", function(ctx, props)
    local text = type(props) == "string" and props or props.Name or props.Text or ""
    local link = type(props) == "table" and props.Link or text
    local wm = Create("TextButton", ctx.Parent, { Text = text, RichText = false, Size = UDim2.new(1, 0, 0, 42), TextColor3 = Theme.SubText,
        Font = Enum.Font.GothamBold, TextSize = 22, TextTransparency = 0.1 })
    wm.MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(link) end
        wm.Text = "Copied to clipboard"
        task.delay(1.5, function() if wm.Parent then wm.Text = text end end)
    end)
    return wm
end)

--------------------------------------------------------------------------- buttons

local function BuildButton(parent, props, size)
    local btn = Create("TextButton", parent, { Text = props.Name, RichText = false, Size = size, BackgroundColor3 = props.Color or Theme.Section,
        BackgroundTransparency = 0.1, TextColor3 = Theme.SubText, Font = Enum.Font.GothamBold, TextSize = L.TitleSize, TextTruncate = Enum.TextTruncate.AtEnd })
    Create("UIPadding", btn, { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) })
    Decorate(btn, L.Corner8, {Theme.Stroke, 0.55, 1})
    -- no UIScale press effect: scaling a button inside a UIListLayout shoves its siblings around
    Interactive(btn, {
        Over = { BackgroundTransparency = 0, TextColor3 = Theme.Text },
        Out = { BackgroundTransparency = 0.1, TextColor3 = Theme.SubText },
        Down = { BackgroundTransparency = 0.3 },
        Time = 0.15,
    })
    btn.MouseButton1Click:Connect(function() SafeCall(props.Callback) end)
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

DefineControl("Toggle", function(ctx, props, host)
    Expect(props, "Name")
    local flag = FlagFor(ctx, props)
    local state = not not props.Default
    local frame, stroke, nameLbl = host.Instance, host.Stroke, host.NameLabel
    local rowWide = host.Exclusive
    if rowWide and state then
        frame.BackgroundColor3, stroke.Color, stroke.Transparency = Theme.ToggleActive, Theme.Active, 0.2
    end
    -- when the toggle owns the row the whole row is the button; when it shares one the ring is,
    -- or a stray click meant for a neighbouring control would flip the toggle instead
    -- ZIndex 0, BELOW the row's content. Row() builds `content` first, so a full-row target added
    -- afterwards at the same ZIndex draws over it -- later sibling wins on a tie -- and swallows
    -- clicks meant for anything else on the rail.
    local hit = rowWide and Create("TextButton", frame, { Size = UDim2.fromScale(1, 1), ZIndex = 0 }) or nil

    local ring = Create(rowWide and "Frame" or "TextButton", host.Rail(), { Size = UDim2.new(0, 16, 0, 16),
        BackgroundTransparency = 1, LayoutOrder = 10,
        -- inert only in the row-wide case: as a button it would sink the press and the row's hit
        -- target would never see the middle of its own checkbox
        Active = rowWide and false or nil, Selectable = rowWide and false or nil })
    -- The box never fills: a dark rim stays put through every state change and the glyph crossfades
    -- over it. The ring stays 16x16 -- it is the layout footprint on the rail, and carries no
    -- corner of its own: it is fully transparent, so rounding it rounds nothing.
    -- Coincident with the ring -- no inset, no centred position. Size and a centred position round
    -- to whole pixels independently, which makes the fill wander inside the border as UI Scale moves.
    --
    -- 16px box + 2.5px Border stroke = 21px outer, deliberately just under the keybind pill's 22:
    -- the solid rim reads taller than the pill's 1px border, so matching 22 looks BIGGER.
    local outline = Create("Frame", ring, { Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Active = false, Selectable = false })
    Decorate(outline, UDim.new(0.2, 0), {Theme.ToggleBorder, 0.05, 2.5})
    -- Glyph is the RING's size (16), the same rect as the rim's box, so the check reads edge to
    -- edge inside the 21px outer. To make it bolder, grow the glyph, never the 16x16 footprint.
    -- Pure scale, no offset: mixing the two restarts the rounding fight above.
    local tick = Create("ImageLabel", ring, { Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), ScaleType = Enum.ScaleType.Fit,
        ImageColor3 = Theme.Active, ImageTransparency = state and 0 or 1,
        Active = false, Selectable = false })
    ApplyIcon(tick, "check", "Symbols-Filled")

    local loopEntry
    if props.Loop then
        -- ShouldRun overrides Active in the dispatcher, so a premium loop can never tick while
        -- locked even if config restored the toggle to on
        local gated = props.Premium and function() return state and Library.IsPremium end or nil
        loopEntry = Library:RegisterLoop(props.Loop.Type or "RenderStepped", props.Loop.Func, gated, props.Loop.Interval)
        loopEntry.Active = state
    end

    -- the row's own colours only follow the state when the toggle owns the row; on a shared row
    -- one control repainting the whole row would speak for its neighbours too
    local tickFade
    local function ApplyVisual(animated)
        -- Only the glyph moves; the rim reads the same on and off. Cancel first so a fast
        -- double-toggle lands on the right value instead of wherever the losing tween stopped.
        if tickFade then tickFade:Cancel() end
        if animated then
            tickFade = TweenService:Create(tick, TICK_FADE, {ImageTransparency = state and 0 or 1})
            tickFade:Play()
        else
            tickFade = nil
            tick.ImageTransparency = state and 0 or 1
        end
        if not rowWide then return end
        local fc = state and Theme.ToggleActive or Theme.Section
        local sc = state and Theme.Active or Theme.Stroke
        local tc = state and Theme.Text or Theme.SubText
        if animated then
            Tween(frame, {BackgroundColor3 = fc})
            Tween(stroke, {Color = sc, Transparency = state and 0.2 or 0.7})
            Tween(nameLbl, {TextColor3 = tc}, 0.2)
        else
            frame.BackgroundColor3, stroke.Color, nameLbl.TextColor3 = fc, sc, tc
        end
    end

    local Changed
    local function SetState(v)
        v = not not v
        if state == v then return end
        state = v
        if loopEntry then
            loopEntry.Active = state
            if state then loopEntry.Dead, loopEntry.Errors = nil, nil end
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
    if state and not (props.Premium and not Library.IsPremium) then SafeCall(props.Callback, state) end
    -- granted mid-session: hand the feature its restored state so it starts without a re-click
    if props.Premium then
        Library:OnPremiumChanged(function(on)
            if on and state then SafeCall(props.Callback, state) end
        end)
    end
    local tap = hit or ring
    tap.MouseButton1Click:Connect(function() SetState(not state) end)
    if rowWide then
        Interactive(tap, { Target = frame, Over = {BackgroundTransparency = 0.02}, Out = {BackgroundTransparency = 0.15}, Time = 0.12 })
    else
        Interactive(tap, { Over = {BackgroundTransparency = 0.85}, Out = {BackgroundTransparency = 1}, Time = 0.12 })
    end
    if props.Keybind then
        BindPill(host.Rail(), props, function(down)
            if down == nil then SetState(not state) else SetState(down) end
        end, flag .. "_bind", true)
    end
    return h
end)

--------------------------------------------------------------------------- keybind

DefineControl("Keybind", function(ctx, props, host)
    if IsMobile then return nil end
    Expect(props, "Name")
    local flag = FlagFor(ctx, props)
    local pill = BindPill(host.Rail(), props, function(...) SafeCall(props.Callback, ...) end, flag .. "_bind")
    return { Instance = pill, Flag = flag .. "_bind" }
end)

--------------------------------------------------------------------------- input

DefineControl("Input", function(ctx, props, host)
    Expect(props, "Name")
    local frame, stroke = host.Instance, host.Stroke
    local field = Create("Frame", host.Rail(), { Size = UDim2.new(0, 160, 0, 26), LayoutOrder = 30,
        BackgroundColor3 = Theme.BindBackground, BackgroundTransparency = 0.5 })
    Decorate(field, L.Corner6, {Theme.Stroke, 0.7, 1})
    local box = ClippedBox(field, { Text = tostring(props.Default or ""), PlaceholderText = props.Placeholder or "...",
        TextColor3 = Theme.Text, PlaceholderColor3 = Theme.Placeholder })

    local Changed
    local function Get() return box.Text end
    local function SetText(t)
        box.Text = tostring(t)
        Changed(box.Text)
    end
    local h
    h, Changed = Bind(ctx, props, FlagFor(ctx, props), Get, SetText)
    h.Instance = field

    -- focus tints the row it sits on, but only when the input is the only thing on that row
    local lit = host.Exclusive
    box.Focused:Connect(function()
        Tween(stroke, {Color = Theme.Accent, Transparency = 0.2})
        if lit then Tween(frame, {BackgroundColor3 = Theme.InputFocus}) end
    end)
    box.FocusLost:Connect(function()
        Tween(stroke, {Color = Theme.Stroke, Transparency = 0.7})
        if lit then Tween(frame, {BackgroundColor3 = Theme.Section}) end
        Changed(box.Text)
    end)
    return h
end)

--------------------------------------------------------------------------- slider

DefineControl("Slider", function(ctx, props, host)
    Expect(props, "Name")
    local min, max = props.Min or 0, props.Max or 100
    local span = max - min
    if span == 0 then span = 1 end

    -- Step quantises to real increments (5, 0.25, ...). Precision is inferred by counting the
    -- digits the step needs, so Step = 0.25 formats to 2dp.
    local step = tonumber(props.Step or props.Increment)
    if step and step <= 0 then step = nil end
    local function DigitsFor(v)
        for d = 0, 6 do
            local m = 10 ^ d
            if math.abs(v * m - math.round(v * m)) < 1e-9 then return d end
        end
        return 6
    end
    -- integer by default; pass Decimals = 2 for .00, or a Step to infer it
    local decimals = props.Int and 0 or props.Decimals or (step and DigitsFor(step)) or 0
    local fmtStr, mult = "%." .. decimals .. "f", 10 ^ decimals
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
    local function GrabPos(frac) return UDim2.new(frac, (0.5 - frac) * GRAB, 0.5, 0) end
    -- inert on purpose: the knob must never hit-test, or it eats the press it is sitting on top of
    local grab = Create("Frame", track, { Size = UDim2.new(0, GRAB, 0, GRAB), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = GrabPos((default - min) / span), BackgroundColor3 = COLOR_WHITE, ZIndex = 2,
        Active = false, Selectable = false })
    Decorate(grab, L.Pill, {Theme.Accent, 0.4, 1.5})

    local current, Changed = default, nil
    local function Get() return current end
    local function Apply(v, fire, instant)
        v = Round(v)
        if instant and v == current then return v end
        current = v
        valText.Text = string.format(fmtStr, v)
        local frac = (v - min) / span
        local sz, gp = UDim2.new(frac, 0, 1, 0), GrabPos(frac)
        if instant then
            CancelMotors(fill) CancelMotors(grab)
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

    -- only the track listens: the knob is inert and passes the press straight through, so one
    -- click can never open two drags
    local function StartDrag(input)
        if not IsPress(input.UserInputType) then return end
        local originX, width = track.AbsolutePosition.X, math.max(track.AbsoluteSize.X, 1)
        local fine, refX, refVal = false, 0, current
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
--  Only one popup is ever on screen, so every dropdown in the hub shares ONE list panel. It is
--  built the first time any dropdown opens -- a hub whose dropdowns are never touched pays
--  nothing for them -- and re-bound to whichever dropdown claims it.
--
--  The list is VIRTUALISED: a fixed window of rows, re-stamped as it scrolls, so a 500-entry list
--  costs the same as a 3-entry one. Rows are absolutely positioned -- a UIListLayout would have to
--  measure every child -- and CanvasSize is set from the row count.
--
--  Drop.Map holds slot -> option index, read at call time, so a slot's handlers are allocated once
--  and still act on whatever it currently shows.

local DROP_MAX, SEARCH_H = 224, 36
local DROP_ROW, DROP_GAP = 32, 4
local DROP_STEP = DROP_ROW + DROP_GAP
local DROP_LIST_H = DROP_MAX - SEARCH_H - 12
local DROP_SLOTS = math.ceil(DROP_LIST_H / DROP_STEP) + 2
local Drop

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

-- paints the visible window; cheap enough to call on every scroll frame
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
    -- a cleanup takes the ScreenGui with it, so a surface left over from a previous load is dead
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
             Slots = {}, Bars = {}, Map = {}, Filtered = {} }
    -- one connection each for the whole pool, guarded by whoever owns it now
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local o = Drop.Owner
        if o then o.Filter() o.Reflow() end
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
    -- ZIndex 0 for the same reason as the toggle's row-wide target: it must sit under the rail
    local header = host.Exclusive and Create("TextButton", row, { Size = UDim2.fromScale(1, 1), ZIndex = 0 }) or nil
    local valLbl = Create("TextLabel", opener, { Text = "", RichText = false, Size = UDim2.new(1, -20, 1, 0),
        TextColor3 = Theme.SubText, Font = Enum.Font.Gotham, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
    local chev = Create("ImageLabel", opener, { Size = UDim2.new(0, 14, 0, 14), AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), ImageColor3 = Theme.SubText })
    ApplyIcon(chev, "chevron-down")

    local me, Changed = {}, nil
    local function IsOwner() return Drop ~= nil and Drop.Owner == me end

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
        if openConn then openConn:Disconnect() openConn = nil end
        Tween(chev, {Rotation = 0}, 0.18)
        ReleasePopup(me)
    end

    -- list order first, then selections not in the current list, so a Populate refresh can't
    -- silently drop a saved value
    local function Values()
        local out, seen = {}, {}
        for _, opt in built do
            if chosen[opt] then out[#out + 1] = opt seen[opt] = true end
        end
        for k in chosen do if not seen[k] then out[#out + 1] = k end end
        return out
    end
    local function Display()
        local vals = Values()
        valLbl.Text = #vals > 0 and table.concat(vals, ", ") or "None"
        return vals
    end
    -- rebuilds the filtered index list, then repaints the window
    local function ApplyFilter()
        if not IsOwner() then return end
        local S = Drop
        local q = S.Search.Text:lower()
        table.clear(S.Filtered)
        for i = 1, #built do
            if q == "" or built[i]:lower():find(q, 1, true) then S.Filtered[#S.Filtered + 1] = i end
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
        if IsOwner() then ApplyFilter() Reflow() end
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

    -- the surface talks to whoever owns it through these; all take an OPTION index, never a slot
    function me.IsSel(i) return chosen[built[i]] == true end
    function me.TextAt(i) return built[i] or "" end
    function me.Pick(i) if built[i] then Select(built[i], true) end end
    function me.Filter() ApplyFilter() end
    function me.Reflow() Reflow() end
    me.Close = Close

    local function Open()
        if IsOwner() then Close() return end
        local S = DropSurface()
        -- claim first: this evicts whoever held the surface, and their Close() clears Owner
        ClaimPopup(me)
        S.Owner = me
        S.Search.Text = ""
        Refresh()
        ApplyFilter()
        Reflow()
        S.Portal.Visible = true
        -- only tracked while the list is up; an idle dropdown costs no connections
        openConn = row:GetPropertyChangedSignal("AbsolutePosition"):Connect(Reflow)
        Tween(chev, {Rotation = 180}, 0.18)
    end

    local h
    h, Changed = Bind(ctx, props, FlagFor(ctx, props), Get, SetValue)
    h.Instance, h.Refresh, h.Close = opener, Refresh, Close

    row.Destroying:Connect(Close)
    opener.MouseButton1Click:Connect(Open)
    if header then
        header.MouseButton1Click:Connect(Open)
        Interactive(header, { Target = row, Over = {BackgroundTransparency = 0.02}, Out = {BackgroundTransparency = 0.15}, Time = 0.12 })
    else
        -- the text lives on the label, so the hover has to be aimed there and not at the button
        Interactive(opener, { Target = valLbl, Over = {TextColor3 = Theme.Text}, Out = {TextColor3 = Theme.SubText}, Time = 0.12 })
    end
    return h
end)

--------------------------------------------------------------------------- section

function Container:AddSection(title, startClosed)
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
        open = v
        body.Visible = v
        if not v then CloseActivePopup() end
        Tween(chev, { Rotation = v and 0 or -90 }, 0.15)
    end
    head.MouseButton1Click:Connect(function() SetOpen(not open) end)
    Interactive(head, { Target = lbl, Over = {TextColor3 = Theme.Text}, Out = {TextColor3 = Theme.SubText}, Time = 0.12 })

    local sub = NewContainer(body, self.TabName, self.Page, self.Window)
    sub.Instance, sub.SetOpen, sub.IsOpen = box, SetOpen, function() return open end
    return sub
end

--=====================================================================================
--  12. Window
--=====================================================================================

function Library:CreateWindow(titleText)
    local old = TargetGui:FindFirstChild("SummitUI")
    if old then old:Destroy() end
    local gui = Create("ScreenGui", TargetGui, {Name = "SummitUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 9999})
    Protect(gui)
    Root.Add(function() FadeOut(gui) end)

    local baseW, baseH = IsMobile and 560 or 880, IsMobile and 330 or 520
    local SIDEBAR_W = IsMobile and 150 or 170

    -- root wraps main so the shadow can sit behind it; a child always draws over its parent's fill
    local root = Create("Frame", gui, { Size = UDim2.new(0, baseW, 0, baseH), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, Active = true, ZIndex = 1 })
    local uiScale = Create("UIScale", root, {Scale = DEFAULT_SCALE * SCALE_BASE})
    local shadow = Shadow(root, 120, 0.62, 0)
    local main = Create("Frame", root, { Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background, BackgroundTransparency = 0, Active = true, ZIndex = 1 })
    Glass(main, 0.13, 1.00)
    local _, mainStroke = Decorate(main, L.Corner12, {Theme.WindowStroke, 0.3, 1.6})
    EdgeGradient(mainStroke)

    -- opt-in from Settings and OFF by default, so nothing appears on screen unless it is asked for
    local fab, fabEnabled = nil, false
    local ToggleHooks = {}
    -- tracked explicitly: root.Visible now lags the toggle by the fade duration
    local menuOpen = true
    -- must stay below menuOpen: declared above it, the body binds a nil GLOBAL instead of the
    -- upvalue, `not menuOpen` is always true, and the badge shows through an open menu
    local function RefreshFab() if fab then fab.Visible = fabEnabled and not menuOpen end end
    local function SetMenuOpen(open)
        open = not not open
        if open == menuOpen then return end
        menuOpen = open
        if not open then CloseActivePopup() end
        SetCursor(open)
        FadeVisible(root, open)
        RefreshFab()
        if open then Library:SetBlur(Library.CurrentBlurVal) elseif Library.BlurEffect then Library.BlurEffect.Size = 0 end
        for i = 1, #ToggleHooks do SafeCall(ToggleHooks[i], open) end
    end

    -- one shared click-catcher: anything outside an open dropdown closes it, no screen-space math
    local catcher = Create("TextButton", gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 198 })
    catcher.MouseButton1Click:Connect(CloseActivePopup)

    UI.Gui, UI.Scale, UI.Catcher = gui, uiScale, catcher

    -- Topbar and sidebar are one flat fill; a gradient on either makes the seam between them visible.
    local topbar = Create("Frame", main, { Size = UDim2.new(1, 0, 0, L.TopbarH), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, Active = true, ZIndex = 5 })
    Decorate(topbar, L.Corner12)
    Create("Frame", topbar, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, ZIndex = 5 })
    Create("Frame", topbar, { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.35, ZIndex = 6 })

    local sidebar = Create("Frame", main, { Size = UDim2.new(0, SIDEBAR_W, 1, -L.TopbarH), Position = UDim2.new(0, 0, 0, L.TopbarH), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, Active = true, ZIndex = 2 })
    Decorate(sidebar, L.Corner12)
    -- UICorner rounds all four, and the top two butt against the topbar, so they cut a notch
    -- where the surfaces meet. Same filler the topbar uses to square off its own bottom.
    Create("Frame", sidebar, { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0, ZIndex = 2 })
    Create("Frame", main, { Size = UDim2.new(0, 1, 1, -(L.TopbarH + 14)), Position = UDim2.new(0, SIDEBAR_W, 0, L.TopbarH), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.5, ZIndex = 3 })

    -- centred over the sidebar column, nudged left
    local TOPBAR_NUDGE = 12
    Create("TextLabel", topbar, { Text = titleText, Size = UDim2.new(0, SIDEBAR_W, 1, 0), Position = UDim2.new(0, -TOPBAR_NUDGE, 0, 0), TextColor3 = Theme.Accent,
        Font = Enum.Font.GothamBlack, TextSize = 23, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })

    local btnContainer = Create("ScrollingFrame", sidebar, { Size = UDim2.new(1, 0, 1, -94), Position = UDim2.new(0, 0, 0, 12), BackgroundTransparency = 1, ZIndex = 3, ScrollBarThickness = 0 })
    local tabList = Create("Frame", btnContainer, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3 })
    List(tabList, L.TabGap, false, Enum.HorizontalAlignment.Center)
    -- a single rail marker that travels between tabs and stretches with the distance it covers
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
    Create("TextLabel", nameBlock, { Text = "@" .. LocalPlayer.Name, Size = UDim2.new(1, 0, 0, 15), TextColor3 = Theme.Placeholder, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2, ZIndex = 3 })

    local glow = Create("Frame", main, { Size = UDim2.new(1, -SIDEBAR_W, 0, 200), Position = UDim2.new(0, SIDEBAR_W, 0, L.TopbarH), BackgroundColor3 = Theme.Accent, ZIndex = 0 })
    Create("UIGradient", glow, { Rotation = 90, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.35, 0.9), NumberSequenceKeypoint.new(1, 1) }) })

    local container = Create("Frame", main, { Size = UDim2.new(1, -(SIDEBAR_W + 20), 1, -(L.TopbarH + 18)), Position = UDim2.new(0, SIDEBAR_W + 10, 0, L.TopbarH + 8), BackgroundTransparency = 1 })
    local headTitle = Create("TextLabel", container, { Text = "", Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 12, 0, 2), TextColor3 = Theme.Text, Font = Enum.Font.GothamBold, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
    local headSub = Create("TextLabel", container, { Text = "", Size = UDim2.new(1, -12, 0, 14), Position = UDim2.new(0, 12, 0, 27), TextColor3 = Theme.SubText, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
    -- must stay a plain Frame: a CanvasGroup here would soften the text of every widget on every tab
    local pageHost = Create("Frame", container, { Size = UDim2.new(1, 0, 1, -L.PageTop), Position = UDim2.new(0, 0, 0, L.PageTop),
        BackgroundTransparency = 1, ClipsDescendants = true })

    -- starts past the sidebar; ends clear of the window buttons
    local CHIP_X, CHIP_RIGHT = SIDEBAR_W + 22 - TOPBAR_NUDGE, 108
    local chipRow = Create("Frame", topbar, { Size = UDim2.new(1, -(CHIP_X + CHIP_RIGHT), 1, 0), Position = UDim2.new(0, CHIP_X, 0, 0), BackgroundTransparency = 1, ZIndex = 6 })
    List(chipRow, 8, true)
    local function Chip(text, accent, order)
        local c = Create("TextLabel", chipRow, { Text = text, RichText = false, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 22),
            -- a dark tag with accent lettering, not a filled pill: a solid accent block is the
            -- brightest thing on screen and fights the palette
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
    local WindowObj = { MainUI = root, Gui = gui, FirstTab = true, SetMenuOpen = SetMenuOpen, Profile = profile, ProfileDivider = profileDivider }
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

    -- the size the user actually chose, kept separate from root.Size so clamping to fit a smaller
    -- viewport (or a bigger scale) is non-destructive: scale back down and the window returns
    local desiredSize = UDim2.fromOffset(baseW, baseH)
    local maximized, savedPos, maxIcon, movedWhileMax = false, nil, nil, false
    local function ClampSize(sz, vp, sc)
        return UDim2.fromOffset(
            math.clamp(sz.X.Offset, MIN_W, math.max(MIN_W, vp.X / sc)),
            math.clamp(sz.Y.Offset, MIN_H, math.max(MIN_H, vp.Y / sc)))
    end
    local function SetMaximized(v)
        if v == maximized then return end
        maximized = v
        local vp, sc = gui.AbsoluteSize, math.max(uiScale.Scale, 0.01)
        if v then
            savedPos = root.Position
            Tween(root, { Size = UDim2.fromOffset((vp.X - 20) / sc, (vp.Y - 20) / sc), Position = UDim2.fromScale(0.5, 0.5) }, 0.3)
        else
            -- if it was dragged while maximized, shrink in place rather than teleporting back
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

    -- While the window is being moved it is swapped for a flat plate: the contents are unreadable
    -- in motion, and this leaves one rectangle to draw per frame instead of the whole tree.
    local GHOST_BG, GHOST_EDGE, GHOST_TEXT = 0.45, 0.7, 0.1
    -- the plate crosses with the PANE, never with the contents: it waits out DRAG_BODY while they
    -- dissolve, then trades places with the bare pane over DRAG_SHELL
    local DRAG_BODY, DRAG_SHELL = 0.10, 0.15
    local GHOST_IN, GHOST_OUT = DRAG_SHELL, DRAG_SHELL
    -- Always exactly the window's footprint. A smaller plate sits inside the window's still-fading
    -- border and a ring appears to float around it, so never animate its size.
    local ghost = Create("Frame", root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = COLOR_BLACK,
        BackgroundTransparency = 1, Visible = false, ZIndex = 2 })
    local _, ghostStroke = Decorate(ghost, L.Corner12, {COLOR_WHITE, 1, 1.5})
    local ghostText = Create("TextLabel", ghost, { Text = (CONFIG.DISCORD:gsub("^%w+://", "")):upper(), RichText = false,
        Rotation = -20, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.88, 0.26), TextColor3 = COLOR_WHITE, TextTransparency = 1,
        Font = Enum.Font.GothamBlack, TextScaled = true })

    -- Cross-fade, not a Visible flip. Generation-guarded so grab/release/grab cannot strand a layer.
    local skipGhost = { [ghost] = true }
    local dragGen = 0
    local function DragGhost(moving)
        dragGen += 1
        local gen = dragGen
        if moving then
            FadeWindowOut(DRAG_BODY, DRAG_SHELL, DRAG_BODY)
            -- held back until the contents are gone, so it never shows through a half-faded window
            task.delay(DRAG_BODY, function()
                if gen ~= dragGen then return end
                ghost.Visible = true
                Tween(ghost, { BackgroundTransparency = GHOST_BG }, GHOST_IN)
                Tween(ghostStroke, { Transparency = GHOST_EDGE }, GHOST_IN)
                Tween(ghostText, { TextTransparency = GHOST_TEXT }, GHOST_IN)
            end)
            -- dropped from the draw only once it is actually invisible
            task.delay(DRAG_BODY + DRAG_SHELL + 0.02, function()
                if gen == dragGen then main.Visible = false end
            end)
        else
            main.Visible = true
            -- the pane returns while the plate leaves; the contents wait for a solid pane
            FadeWindowIn(DRAG_BODY, DRAG_SHELL, DRAG_SHELL)
            Tween(ghostStroke, { Transparency = 1 }, GHOST_OUT)
            Tween(ghostText, { TextTransparency = 1 }, GHOST_OUT)
            Tween(ghost, { BackgroundTransparency = 1 }, GHOST_OUT, nil, function()
                if gen == dragGen then ghost.Visible = false end
            end)
        end
    end

    MakeDraggable(topbar, root, NoteDrag, DragGhost)
    MakeDraggable(sidebar, root, NoteDrag, DragGhost)
    -- everything is at rest right here; see the note on PrimeFade. The pane is root + its shadow +
    -- main's fill and border -- everything else is contents and dissolves ahead of it.
    PrimeFade(root, { [root] = true, [shadow] = true, [main] = true, [mainStroke] = true }, skipGhost)

    function RefitWindow()
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
        if want ~= root.Size then CancelMotors(root) root.Size = want end
        local size, ap, pos = root.AbsoluteSize, root.AnchorPoint, root.Position
        local tl = root.AbsolutePosition - gui.AbsolutePosition
        local nx = math.clamp(tl.X, 100 - size.X, math.max(100 - size.X, vp.X - 100))
        local ny = math.clamp(tl.Y, 0, math.max(0, vp.Y - 44))
        if nx ~= tl.X or ny ~= tl.Y then
            root.Position = UDim2.new(pos.X.Scale, nx + size.X * ap.X - vp.X * pos.X.Scale,
                                      pos.Y.Scale, ny + size.Y * ap.Y - vp.Y * pos.Y.Scale)
        end
    end
    -- AbsoluteSize lags its own changed signal by several frames, so poll for a short settle window
    -- instead of reading it inside the signal. The watcher only exists during that window.
    local refitUntil, refitConn, lastVp = 0, nil, gui.AbsoluteSize
    local function QueueRefit()
        refitUntil = os.clock() + 0.5
        if refitConn then return end
        refitConn = RunService.Heartbeat:Connect(function()
            if not gui.Parent then refitConn:Disconnect() refitConn = nil return end
            local vp = gui.AbsoluteSize
            if vp ~= lastVp then
                lastVp = vp
                RefitWindow()
            end
            if os.clock() > refitUntil then refitConn:Disconnect() refitConn = nil end
        end)
    end
    Root.Add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(QueueRefit))
    if Camera then Root.Add(Camera:GetPropertyChangedSignal("ViewportSize"):Connect(QueueRefit)) end
    Root.Add(function() if refitConn then refitConn:Disconnect() refitConn = nil end end)

    local function WindowBtn(iconName, xOffset, tintColor, callback)
        local btn = Create("TextButton", topbar, { Size = UDim2.new(0, 28, 0, 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, xOffset, 0.5, 0), BackgroundColor3 = tintColor, BackgroundTransparency = 1, ZIndex = 7 })
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
            local vp = gui.AbsoluteSize
            local w = math.clamp(size0.X.Offset + dx, MIN_W, math.max(MIN_W, vp.X / scale))
            local h = math.clamp(size0.Y.Offset + dy, MIN_H, math.max(MIN_H, vp.Y / scale))
            root.Size = UDim2.new(0, w, 0, h)
            desiredSize = root.Size
            root.Position = UDim2.new(pos0.X.Scale, pos0.X.Offset + (w - size0.X.Offset) * scale / 2, pos0.Y.Scale, pos0.Y.Offset + (h - size0.Y.Offset) * scale / 2)
        end)
    end)

    -- Built on every platform, not just touch: it is the only way back in if the toggle key is
    -- forgotten, and it costs nothing while hidden. Shows whenever the menu is closed.
    do
        -- No Shadow() parented here: under ZIndexBehavior.Sibling a descendant always draws above
        -- its ancestor regardless of ZIndex, so it renders as a blur across the face, not behind it.
        fab = Create("TextButton", gui, { Size = UDim2.new(0, 46, 0, 46),
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16),
            BackgroundColor3 = Theme.Active, BackgroundTransparency = 0, ZIndex = 100, Visible = false })
        Decorate(fab, FAB_CORNER, {Theme.ToggleBorder, 0.05, 2})
        -- Shares the button's exact rect and corner radius, so the black cannot cross the rim.
        -- A radial cannot do edge-to-edge here: covering the face needs ~2.5x oversize and the tail
        -- then hangs outside with nothing to clip it (ClipsDescendants clips to a RECTANGLE).
        local plate = Create("Frame", fab, { BackgroundColor3 = COLOR_BLACK, BackgroundTransparency = FAB_PLATE_ALPHA,
            Size = UDim2.fromScale(1, 1), Active = false, Selectable = false, ZIndex = 101 })
        Decorate(plate, FAB_CORNER)
        -- the stroke is ApplyStrokeMode.Border so it draws outside the frame and no child can
        -- cover it. Two-tone: the second letter is black so it reads against the plate.
        Create("TextLabel", fab, { Text = '<font color="#FFFFFF">S</font><font color="#000000">X</font>',
            RichText = true, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 102 })
        Interactive(fab, { Over = { BackgroundColor3 = Theme.Accent }, Out = { BackgroundColor3 = Theme.Active }, Time = 0.14 })
        local fabStart, fabOrigin, fabMoved
        fab.InputBegan:Connect(function(input)
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
        fab.InputEnded:Connect(function(input)
            if IsPress(input.UserInputType) and not fabMoved then SetMenuOpen(true) end
        end)
    end

    local tabSetters, tabHandles = {}, {}

    function WindowObj:MakeTab(name, subtitle, icon)
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

        local function SetActive(on)
            page.Visible = on
            Tween(btn, { BackgroundTransparency = on and 0.85 or 1 }, 0.18)
            Tween(tabLbl, { TextColor3 = on and Theme.Text or Theme.TabText }, 0.18)
            Tween(tabIcon, { ImageColor3 = on and Theme.Accent or Theme.TabText }, 0.18)
        end
        tabSetters[tabIndex] = SetActive

        local function Select()
            if page.Visible then return end
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
            if ENABLE_TAB_TRANSITION then
                pageHost.Position = UDim2.new(0, 0, 0, L.PageTop + 12)
                Tween(pageHost, { Position = UDim2.new(0, 0, 0, L.PageTop) }, 0.28, 0.85)
            end
        end

        btn.MouseButton1Click:Connect(Select)
        Interactive(btn, { Over = {BackgroundTransparency = 0.93}, Out = {BackgroundTransparency = 1},
                           Time = 0.15, Enabled = function() return not page.Visible end })

        local tab = NewContainer(page, name, page, WindowObj)
        tab.Page, tab.Button, tab.Select, tab.Index = page, btn, Select, tabIndex
        tabHandles[tabIndex], tabHandles[name] = tab, tab
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

    SetCursor(true)
    return WindowObj
end

--=====================================================================================
--  13. Key gate
--=====================================================================================

local function ShowKeyGate(K, Matches, onPass)
    if genv.SummitGen ~= Private.Gen then return end
    local previous = TargetGui:FindFirstChild("SummitKeyUI")
    while previous do
        pcall(function() previous:Destroy() end)
        previous = TargetGui:FindFirstChild("SummitKeyUI")
    end
    local kgui = Create("ScreenGui", TargetGui, { Name = "SummitKeyUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 9999 })
    Protect(kgui)
    Root.Add(function() FadeOut(kgui) end)
    SetCursor(true)

    local shell = Create("Frame", kgui, { Size = UDim2.new(0, 360, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, Active = true })
    -- Opens at its FINAL scale; the fade carries the entrance. Scaling up reads as a mis-sized card.
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
    -- pulled left of the close button so the two never collide
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

    -- on the shell, not the card: the card's UIListLayout would treat it as a list item
    local close = Create("TextButton", shell, { Text = "×", Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8), TextColor3 = Theme.Close, Font = Enum.Font.GothamMedium, TextSize = 20, ZIndex = 6 })
    Interactive(close, { Over = { TextColor3 = COLOR_WHITE }, Out = { TextColor3 = Theme.Close } })
    close.MouseButton1Click:Connect(function() if genv.SummitCleanup then genv.SummitCleanup() end end)

    local granted, tries = false, 0
    local function Submit()
        if granted then return end
        if genv.SummitGen ~= Private.Gen then kgui:Destroy() return end
        if Matches(box.Text) then
            granted = true
            -- held, not written: SetPremium decides whether this account gets to skip the gate
            AcceptedKey = (box.Text:gsub("%s", ""))
            if canFile and not K.SaveForPremiumOnly then pcall(writefile, K.SaveFile, AcceptedKey) end
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

-- Resolved once and memoised: RejectUnsupported needs it on the boot path and the log needs it
-- again a few hundred ms later, and identifyexecutor() is a foreign call, not a table read.
function Library:ExecutorName()
    local cached = Private.Executor
    if cached then return cached end
    cached = "unknown"
    -- type-checked, not pcall'd around a nil call: on a stripped environment both globals are nil
    local probe = (type(identifyexecutor) == "function" and identifyexecutor)
        or (type(getexecutorname) == "function" and getexecutorname)
    if probe then
        local ok, found = pcall(probe)
        if ok and found ~= nil and found ~= "" then cached = tostring(found) end
    end
    Private.Executor = cached
    return cached
end

-- Fire and forget: one webhook POST per execution, on its own thread, and any failure is
-- swallowed. Runs before the key gate, so it logs everyone who ran the script.
function Library:LogExecution()
    if not (HttpRequest and CONFIG.LOG_WEBHOOK and CONFIG.LOG_WEBHOOK ~= "") then return end
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

        -- 32-bit multiply split in halves: a straight h * k passes 2^53 and silently loses bits
        local function Mul32(h, k)
            local lo, hi = h % 65536, math.floor(h / 65536)
            return (lo * k + ((hi * k) % 65536) * 65536) % 4294967296
        end
        -- FNV-1a with an avalanche finish. The address itself is never sent; the digest only has
        -- to tell two accounts on one connection apart. Run over the address forwards and then
        -- BACKWARDS, not just from a second seed: FNV's low byte lane ignores the seed, so two
        -- seeded passes over the same string produce two halves ending in identical bits.
        local function Fnv(s, seed)
            local h = seed
            for i = 1, #s do
                h = Mul32(bit32.bxor(h, s:byte(i)), 16777619)
            end
            h = Mul32(bit32.bxor(h, bit32.rshift(h, 15)), 2246822507)
            return bit32.bxor(h, bit32.rshift(h, 13))
        end

        local function Json(url)
            local ok, body = pcall(game.HttpGet, game, url)
            if not ok then return nil end
            local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
            return decoded and type(data) == "table" and data or nil
        end

        -- Discord 403s some executor User-Agents. LOG_PROXY relays the POST; the id/token are
        -- pulled out of the webhook by pattern rather than by slicing the string, so a proxy
        -- base given with or without a trailing /api/webhooks lands on the same URL. A webhook
        -- that does not match the shape falls through to Discord directly.
        local endpoint = CONFIG.LOG_WEBHOOK
        local base = CONFIG.LOG_PROXY
        if base and base ~= "" then
            local id, token = endpoint:match("/api/webhooks/(%d+)/([%w%-_]+)")
            if id then
                base = base:gsub("/+$", ""):gsub("/api/webhooks$", "")
                endpoint = base .. "/api/webhooks/" .. id .. "/" .. token
            end
        end

        -- Two independent lookups, so both run at once and whichever finishes last sends. No
        -- yielding, no polling: the counter is the join. `sent` keeps the timeout from posting
        -- a second copy if a slow worker lands after it.
        local ip, country, gameName = "", "unknown", "unknown"
        local pending, sent = 2, false
        local function Send(force)
            if not force then pending -= 1 end
            if sent or (pending > 0 and not force) then return end
            sent = true

            local hashIp = ip ~= "" and ("%08x%08x"):format(Fnv(ip, 2166136261), Fnv(ip:reverse(), 40389)) or "unknown"
            local uid = LocalPlayer.UserId
            pcall(HttpRequest, {
            Url = endpoint,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            },
            Body = HttpService:JSONEncode({ embeds = { {
                -- A heading, so it goes in `description`: embed TITLES render markdown headings
                -- literally, as the characters "## ". Discord has no way to centre text anywhere.
                description = "## " .. CONFIG.HUB_NAME .. " | Execution Log",
                -- Discord always draws the left strip; it can only be blended, not removed.
                -- #2B2D31 is the dark-theme embed background, so it disappears there.
                color = 2829617,
                -- three inline fields per row: Player/User ID/Executor, then Game/Country/Hashed IP
                fields = {
                    { name = "Player", value = ("[%s (@%s)](https://www.roblox.com/users/%d/profile)")
                        :format(LocalPlayer.DisplayName, LocalPlayer.Name, uid), inline = true },
                    { name = "User ID", value = "`" .. uid .. "`", inline = true },
                    { name = "Executor", value = "`" .. Library:ExecutorName() .. "`", inline = true },
                    { name = "Game", value = ("[%s](https://www.roblox.com/games/%d)"):format(gameName, game.PlaceId), inline = true },
                    { name = "Country", value = "`" .. country .. "`", inline = true },
                    { name = "Hashed IP", value = "`" .. hashIp .. "`", inline = true },
                    { name = "HWID", value = "```\n" .. First(gethwid, get_hwid, syn and syn.get_hwid,
                        function() return Service("RbxAnalyticsService"):GetClientId() end) .. "\n```", inline = true },
                },
            } } }),
            })
        end

        task.spawn(function()
            local geo = Json("https://ipwho.is/")
            if geo and geo.success then
                ip, country = geo.ip or "", geo.country or "unknown"
            else
                local okIp, plain = pcall(game.HttpGet, game, "https://api.ipify.org")
                if okIp and type(plain) == "string" then ip = plain end
            end
            Send()
        end)
        task.spawn(function()
            local okInfo, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
            if okInfo and info and info.Name then gameName = info.Name end
            Send()
        end)
        task.delay(10, function() Send(true) end)
    end)
end

-- True when this executor is on CONFIG.UNSUPPORTED, after telling the user and scheduling the
-- unload. Substring match on identifyexecutor(), case-insensitive, so "wave" catches "Wave 2.4".
-- The delay is what makes the toast readable: the unload takes the notification with it.
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

--=====================================================================================
--  13c. Init
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

    self:LogExecution()                 -- logged before the check, so refusals show up too
    if self:RejectUnsupported() then return end
    -- registered here rather than at load so Settings sorts last, behind the game's tabs
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
    -- On demand, destroyed at zero. The BlurEffect in the Camera is the only instance this library
    -- puts anywhere a game script can enumerate.
    function Library:SetBlur(alpha)
        Library.CurrentBlurVal = alpha
        local want = alpha * MAX_BLUR
        if want <= 0 then
            if Library.BlurEffect then
                Library.BlurEffect:Destroy()
                Library.BlurEffect = nil
            end
            return
        end
        if not Library.BlurEffect or not Library.BlurEffect.Parent then
            Library.BlurEffect = Create("BlurEffect", Camera, { Name = "SummitBlur", Size = 0 })
        end
        Library.BlurEffect.Size = want
    end
    Root.Add(function()
        local b = Library.BlurEffect
        if not b then return end
        Library.BlurEffect = nil
        if b.Parent then TweenService:Create(b, FADE_INFO, { Size = 0 }):Play() end
        task.delay(FADE_TIME + 0.02, function() if b.Parent then b:Destroy() end end)
    end)
    Root.Add(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local cam = Workspace.CurrentCamera
        if cam then Camera = cam if Library.BlurEffect then Library.BlurEffect.Parent = Camera end end
    end))

    local function Build()
        if genv.SummitGen ~= Private.Gen then return end
        self:BuildTabs(self:CreateWindow(CONFIG.HUB_NAME))
        self:LoadConfig()
        Root.Add(function() if configDirty then Library:SaveConfig() end end)
    end

    -- An empty Keys list counts as disabled: a gate no key can open locks out every user,
    -- and forgetting to configure one should not be the way that happens.
    local K = CONFIG.KEY
    if not K.Enabled or not K.Keys or #K.Keys == 0 then Build() StartPremiumCheck() return end

    -- case-insensitive, and paste-tolerant of stray whitespace
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

    -- Premium accounts never see the gate, so the whitelist resolves first. Single attempt keeps that
    -- quick; the full retry runs after, so a blip can still unlock premium widgets later.
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
    if next(PendingBinds) and not UIS:GetFocusedTextBox()
       and (io.UserInputType == Enum.UserInputType.Keyboard or not gp) then
        if io.KeyCode == Enum.KeyCode.Backspace or io.KeyCode == Enum.KeyCode.Escape then nm = "NONE" end
        for btn in PendingBinds do
            local b = KeybindRegistry[btn]
            if b then
                b.Key = nm
                b.Render()
                Tween(btn, {TextColor3 = Theme.SubText, BackgroundColor3 = Theme.BindBackground})
            end
        end
        MarkDirty("keybind")
        table.clear(PendingBinds)
        return
    end
    if gp or SliderDragging then return end
    for _, bind in KeybindRegistry do
        if bind.Key ~= "NONE" and bind.Key == nm then
            if bind.Mode == "Hold" then Guard(bind.Action, true) else Guard(bind.Action) end
        end
    end
end))

Root.Add(UIS.InputEnded:Connect(function(io)
    local nm = BindName(io)
    if not nm then return end
    for _, bind in KeybindRegistry do
        if bind.Mode == "Hold" and bind.Key == nm then Guard(bind.Action, false) end
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

Library.Config = CONFIG          -- live config table; write through Configure
Library.UI = UI                  -- .Gui .Scale .Catcher .Window — populated by Init
Library.TabIcons = TAB_ICONS     -- default Lucide icon per tab name; RegisterTab's 4th arg wins
Library.HttpRequest = HttpRequest
Library.IsMobile, Library.IsConsole = IsMobile, IsConsole
Library.Root = Root              -- .Add(conn | instance | fn) — torn down on re-inject

-- Call before Init. Nested tables (KEY, WHITELIST) merge field by field, so passing
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
    if opts.FOLDER and not opts.CONFIG_FILE then
        CONFIG.CONFIG_FILE = CONFIG.FOLDER .. "/configs/" .. tostring(game.PlaceId) .. ".json"
        if isfolder and makefolder then
            for _, path in { CONFIG.FOLDER, CONFIG.FOLDER .. "/configs" } do
                if not isfolder(path) then pcall(makefolder, path) end
            end
        end
    end
    return self
end

--=====================================================================================
--  16. Built-in tabs
--=====================================================================================
--
--  Settings is the one tab every game inherits. Registered by Init AFTER the game's tabs,
--  so it always lands last in the sidebar; name it in Library.TabOrder to move it, or set
--  Library.Builtins.Settings = false to drop it — you then own the menu keybind, the blur,
--  the launcher and UI Scale yourself.

Library.Builtins = { Settings = true }

function Library:RegisterBuiltins()
    if not (self.Builtins and self.Builtins.Settings) then return end

    self:RegisterTab("Settings", function(tab, windowObj)
        tab:AddHeader("GUI")
        tab:AddKeybind({ Name = "Toggle Menu Bind", Description = "Key that shows/hides the menu", Keybind = "RightShift", Callback = function()
            windowObj.SetMenuOpen(not windowObj.IsOpen())
        end})
        tab:AddToggle({ Name = "Launcher Button", Description = "Floating badge to reopen the menu, drag to move it",
            Flag = "launcher_button", Default = false, Callback = function(v) windowObj.SetLauncher(v) end })
        tab:AddSlider({ Name = "Background Blur", Description = "Blurs the game behind the menu", Min = 0, Max = 100, Default = 0, Callback = function(val)
            Library.CurrentBlurVal = val / 100
            if windowObj.IsOpen() then Library:SetBlur(Library.CurrentBlurVal) end
        end})
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
                local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
                local response = HttpRequest and HttpRequest({ Url = url, Method = "GET" })
                local res = response and (response.Body or response.body)
                if not res or res == "" then res = game:HttpGet(url) end
                local open = {}
                for _, srv in HttpService:JSONDecode(res).data do
                    if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then open[#open + 1] = srv.id end
                end
                if #open > 0 then TeleportService:TeleportToPlaceInstance(placeId, open[math.random(#open)], LocalPlayer)
                else TeleportService:Teleport(placeId, LocalPlayer) end
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
