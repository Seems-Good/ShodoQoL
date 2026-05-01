-- ShodoQoL/Core.lua
-- Shared init: SavedVariables, one-shot bootstrap, Settings category.
-- Adds a systemd-style debug/journal framework.
-- All existing module APIs (IsEnabled, OnReady, CreateButton, rootCategory) are unchanged.

ShodoQoL = ShodoQoL or {}

ShodoQoL.COLOR      = { r = 0.200, g = 0.576, b = 0.498 }
ShodoQoL.COLOR_HEX  = "|cff33937f"
ShodoQoL.COLOR_LITE = "|cff52c4af"

------------------------------------------------------------------------
-- Master defaults
------------------------------------------------------------------------
ShodoQoL.DEFAULTS = {
    essenceMover = {
        x = nil,
        y = nil,
        scale = 1.5,
    },
    spatialParadox = {
        targetName  = nil,
        targetRealm = nil,
    },
    prescience1 = {
        targetName  = nil,
        targetRealm = nil,
    },
    prescience2 = {
        targetName  = nil,
        targetRealm = nil,
    },
    cauterizingFlame = {
        targetName  = nil,
        targetRealm = nil,
    },
    blisteringScales = {
        targetName  = nil,
        targetRealm = nil,
    },
    hearthStoned = {
        items = {},
        index = 1,
    },
    doNotRelease = {
        posX        = 0,
        posY        = 120,
        colorR      = 1,
        colorG      = 0.1,
        colorB      = 0.1,
        warningText = "PLEASE DO NOT RELEASE",
        fontSize    = 64,
        fontFace    = "Fonts\\FRIZQT__.TTF",
    },
    sourceOfMagic = {
        posX        = 0,
        posY        = 80,
        colorR      = 0.20,
        colorG      = 0.75,
        colorB      = 1.00,
        fontSize    = 52,
        fontFace    = "Fonts\\FRIZQT__.TTF",
        targetName  = nil,
        targetRealm = nil,
    },
    kicksmaxxing = {
        -- Each entry: { name = string, enabled = bool }
        -- Enabled entries have a live KM_SpellName character macro.
        spells = {},
    },
    shoStats = {
        point = "CENTER", relTo = "UIParent", relPt = "CENTER",
        x = 0, y = 200,
        locked = false, scale = 1.0, shown = true, opacity = 1.0,
        show_crit = true, show_haste = true, show_mast = true,
        show_vers = true, show_leech = true, show_speed = true,
        show_main = true,
        statOrder = {"crit","haste","mast","vers","leech","main"},
    },
    hoverTracker = {
        essBleedX   = 8,
        essBleedY   = 8,
        castOpacity = 1.0,
        essOpacity  = 1.0,
    },
    prescienceTracker = {
        point    = "CENTER",
        relPoint = "CENTER",
        posX     = 0,
        posY     = -200,
        locked   = false,
        scale    = 1.0,
        opacity  = 1.0,
    },
    mouseCircle = {
        colorR    = 1.00,
        colorG    = 1.00,
        colorB    = 1.00,
        colorA    = 1.00,
        thickness = 2,
        radius    = 16,
    },
    -- Per-character profiles live here, keyed by "CharName-RealmName".
    -- BackFill adds this key to any existing install automatically.
    profiles = {},
}

-- Default state for a new character profile.
-- Separated from DEFAULTS so BackFill doesn't flatten it into the global DB.
ShodoQoL.PROFILE_DEFAULTS = {
    -- Set true after the one-time class check so it only runs on first login.
    _classCheckDone = false,

    -- Per-module enabled flags for this character.
    enabled = {
        EssenceMover      = true,
        MacroHelpers      = true,
        HearthStoned      = true,
        CInspect          = true,
        DoNotRelease      = true,
        --ShoStats          = true,
        SourceOfMagic     = true,
        HoverTracker      = true,
        PrescienceTracker = true,
        MouseCircle       = false,
        Kicksmaxxing      = true,
    },
}

------------------------------------------------------------------------
-- Deep back-fill
------------------------------------------------------------------------
local function BackFill(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(saved[k]) == "table" then
            if #v == 0 then
                BackFill(saved[k], v)
            end
        end
    end
end

------------------------------------------------------------------------
-- IsEnabled
-- Safe to call at file-load time (before PLAYER_LOGIN): falls back to
-- DEFAULTS when ShodoQoLDB hasn't been initialised yet.
------------------------------------------------------------------------
function ShodoQoL.IsEnabled(key)
    -- Profile is set at PLAYER_LOGIN; until then fall back to compile-time defaults.
    if ShodoQoL._profile then
        return ShodoQoL._profile.enabled[key] ~= false
    end
    return ShodoQoL.PROFILE_DEFAULTS.enabled[key] ~= false
end

------------------------------------------------------------------------
-- Shared clean button
------------------------------------------------------------------------
function ShodoQoL.CreateButton(parent, label, width, height)
    width  = width  or 110
    height = height or 24

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    btn:EnableMouse(true)

    local bgNormal = btn:CreateTexture(nil, "BACKGROUND")
    bgNormal:SetAllPoints()
    bgNormal:SetColorTexture(0.12, 0.12, 0.12, 0.90)

    local bgHover = btn:CreateTexture(nil, "BACKGROUND")
    bgHover:SetAllPoints()
    bgHover:SetColorTexture(0.20, 0.58, 0.50, 0.30)
    bgHover:Hide()

    local bgPush = btn:CreateTexture(nil, "BACKGROUND")
    bgPush:SetAllPoints()
    bgPush:SetColorTexture(0.10, 0.35, 0.30, 0.60)
    bgPush:Hide()

    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.70)
    border:EnableMouse(false)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetText(label)
    fs:SetTextColor(0.90, 0.95, 0.92)

    btn:SetScript("OnEnter", function()
        bgHover:Show()
        border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1.0)
        fs:SetTextColor(1, 1, 1)
    end)
    btn:SetScript("OnLeave", function()
        bgHover:Hide()
        bgPush:Hide()
        border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.70)
        fs:SetTextColor(0.90, 0.95, 0.92)
    end)
    btn:SetScript("OnMouseDown", function() bgPush:Show() end)
    btn:SetScript("OnMouseUp",   function() bgPush:Hide()  end)

    return btn
end

------------------------------------------------------------------------
-- ╔══════════════════════════════════════════════════════╗
-- ║  Debug / Journal framework (systemd-style)           ║
-- ╚══════════════════════════════════════════════════════╝
--
-- Usage from any module:
--   local log = ShodoQoL.Debug.GetLogger("MyModule")
--   log:Info("Something happened")
--   log:Warn("Watch out")
--   log:Error("Something broke: " .. tostring(err))
--   log:Event("UNIT_HEALTH fired")
--   log:Invoke("SomeFunction", "arg1", "arg2")
--
-- Journal entries are stored per-module with timestamps.
-- /sqol status <module>  - prints the journal for that module.
------------------------------------------------------------------------

ShodoQoL.Debug = ShodoQoL.Debug or {}

local Debug = ShodoQoL.Debug

-- Maximum journal entries kept per module (ring buffer)
Debug.MAX_ENTRIES = 64

-- Log levels
Debug.LEVEL = {
    INFO   = "INFO",
    WARN   = "WARN",
    ERROR  = "ERROR",
    EVENT  = "EVENT",
    INVOKE = "INVOKE",
    LOAD   = "LOAD",
}

-- Registry: key = module key, value = { loaded=bool, loadTime=time, entries={...} }
Debug._registry = Debug._registry or {}

-- Colour codes per level for chat output
local LEVEL_COLOR = {
    INFO   = "|cffaaaaaa",
    WARN   = "|cffffff00",
    ERROR  = "|cffff4444",
    EVENT  = "|cff52c4af",
    INVOKE = "|cff88aaff",
    LOAD   = "|cff33937f",
}

local COLOR_RESET = "|r"
local COLOR_TIME  = "|cff666666"
local COLOR_MOD   = "|cff52c4af"
local COLOR_BLUE  = "|cff00ccff"

------------------------------------------------------------------------
-- Internal: push a journal entry for a module
------------------------------------------------------------------------
local function PushEntry(key, level, msg)
    local reg = Debug._registry[key]
    if not reg then return end

    local entry = {
        time  = GetTime(),
        clock = date("%H:%M:%S"),
        level = level,
        msg   = msg,
    }

    local list = reg.entries
    list[#list + 1] = entry

    -- Trim to ring-buffer limit
    if #list > Debug.MAX_ENTRIES then
        table.remove(list, 1)
    end
end

------------------------------------------------------------------------
-- Debug.Register(key)
-- Called automatically by GetLogger. Idempotent.
------------------------------------------------------------------------
function Debug.Register(key)
    if Debug._registry[key] then return end
    Debug._registry[key] = {
        key      = key,
        loaded   = false,
        loadTime = nil,
        entries  = {},
    }
end

------------------------------------------------------------------------
-- Debug.MarkLoaded(key)  /  Debug.MarkUnloaded(key)
-- Called by the bootstrap after OnReady fires for a module.
------------------------------------------------------------------------
function Debug.MarkLoaded(key)
    Debug.Register(key)
    local reg = Debug._registry[key]
    reg.loaded   = true
    reg.loadTime = GetTime()
    PushEntry(key, Debug.LEVEL.LOAD, "Module started (loaded)")
end

function Debug.MarkDisabled(key)
    Debug.Register(key)
    local reg = Debug._registry[key]
    reg.loaded = false
    PushEntry(key, Debug.LEVEL.LOAD, "Module disabled (skipped)")
end

------------------------------------------------------------------------
-- Debug.GetLogger(key)
-- Returns a logger object bound to `key`. Call from module top-level.
-- Safe to call at file-load time (before PLAYER_LOGIN).
------------------------------------------------------------------------
function Debug.GetLogger(key)
    Debug.Register(key)

    local logger = {}

    function logger:_log(level, msg)
        PushEntry(key, level, tostring(msg))
    end

    function logger:Info(msg)   self:_log(Debug.LEVEL.INFO,   msg) end
    function logger:Warn(msg)   self:_log(Debug.LEVEL.WARN,   msg) end
    function logger:Error(msg)  self:_log(Debug.LEVEL.ERROR,  msg) end
    function logger:Event(msg)  self:_log(Debug.LEVEL.EVENT,  msg) end

    -- Invoke: record a function call with optional args as a string.
    function logger:Invoke(funcName, ...)
        local parts = { funcName .. "(" }
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        parts[#parts + 1] = ")"
        self:_log(Debug.LEVEL.INVOKE, table.concat(parts, " "))
    end

    return logger
end

------------------------------------------------------------------------
-- Debug.PrintJournal(key)
-- Prints the journal for a module in systemd journalctl style.
------------------------------------------------------------------------
function Debug.PrintJournal(key)
    -- Normalise key casing: try exact match first, then case-insensitive
    local reg = Debug._registry[key]
    if not reg then
        -- Case-insensitive fallback
        local lower = key:lower()
        for k, v in pairs(Debug._registry) do
            if k:lower() == lower then
                reg = v
                key = k
                break
            end
        end
    end

    local FORMAT_NAME = COLOR_BLUE .. "[ShodoQoL]|r"

    if not reg then
        print(FORMAT_NAME .. " |cffff4444Unknown module:|r " .. key)
        print("  Known modules: " .. table.concat((function()
            local t = {}
            for k in pairs(Debug._registry) do t[#t+1] = k end
            table.sort(t)
            return t
        end)(), ", "))
        return
    end

    local state  = reg.loaded and "|cff33937factive|r" or "|cffff4444inactive|r"
    local uptime = reg.loadTime and string.format("%.1fs", GetTime() - reg.loadTime) or "n/a"

    print(COLOR_MOD .. "● " .. key .. COLOR_RESET
        .. " - " .. FORMAT_NAME .. " module journal")
    print("   Loaded: " .. state
        .. "  |cff666666Uptime:|r " .. uptime
        .. "  |cff666666Entries:|r " .. #reg.entries .. "/" .. Debug.MAX_ENTRIES)
    print("|cff666666" .. string.rep("─", 38) .. "|r")

    if #reg.entries == 0 then
        print("  |cff666666(no journal entries yet)|r")
        return
    end

    for _, e in ipairs(reg.entries) do
        local col = LEVEL_COLOR[e.level] or "|cffaaaaaa"
        local lvl = string.format("%-6s", e.level)
        print(COLOR_TIME .. e.clock .. "|r "
            .. col .. lvl .. COLOR_RESET
            .. " " .. e.msg)
    end
end

------------------------------------------------------------------------
-- Root Settings panel
------------------------------------------------------------------------
local VERSION   = "@project-version@"
local TIMESTAMP = "@project-date-iso@"

-- Modules that only make sense on an Evoker. Auto-disabled on first login
-- for non-Evoker characters. User can re-enable manually at any time.
local EVOKER_ONLY_MODULES = {
    "EssenceMover", "MacroHelpers", "SourceOfMagic",
    "HoverTracker", "PrescienceTracker",
}

local MODULES = {
    { name = "Essence Mover", key = "EssenceMover",
      desc = "Drag your Evoker Essence bar anywhere on screen. "
          .. "Adjust scale with a live slider. Position persists across reloads and spec changes." },
    { name = "Macro Helpers", key = "MacroHelpers",
      desc = "Per-character macros with cross-realm support: |cff52c4afSpatial Paradox|r, "
          .. "|cff52c4afPrescience 1|r, and |cff52c4afPrescience 2|r - each targeting an independent player." },
    { name = "HearthStoned", key = "HearthStoned",
      desc = "Cycles through all owned hearthstone toys with a single per-character macro. "
          .. "Rescan at any time to pick up new toys." },
    { name = "C-Inspect", key = "CInspect", addonKey = "C-Inspect",
      desc = "Hold |cff52c4afCtrl|r and left-click a friendly player to inspect them. "
          .. "Also registers |cff52c4af/rl|r to reload your UI quickly." },
    { name = "DoNotRelease", key = "DoNotRelease", addonKey = "DoNotRelease",
      desc = "Pulsing warning when you die in a group instance. "
          .. "Configurable text, color, font, and position. Use |cff52c4af/dnr test|r to preview." },
    { name = "Source of Magic", key = "SourceOfMagic",
      desc = "Out-of-combat popup when Source of Magic is missing from your configured target. "
          .. "Only active when talented into Source of Magic. Use |cff52c4af/som test|r to preview." },
--    { name = "ShoStats", key = "ShoStats",
--      desc = "Lightweight stat readout frame: Crit, Haste, Mastery, Vers, Leech, Speed, and main stat, "
--          .. "with draggable frame, opacity/scale sliders, and per-stat visibility toggles." },
    { name = "Hover Tracker", key = "HoverTracker",
      desc = "Evoker-only. Glows green/amber/red behind your cast bar based on whether Hover lets you "
          .. "move while casting. Alerts when Hover has no charges. Configurable font, size, and opacity." },
    { name = "Prescience Tracker", key = "PrescienceTracker",
      desc = "Live Prescience buff state tracking 'aura' on your P1 and P2 targets. "
          .. "Color-coded: green o (active), orange ! (expiring), red x (missing), grey - (not in group). "
          .. "Purely event-driven with zero CPU overhead. Augmentation Evoker only." },
    { name = "Mouse Circle", key = "MouseCircle",
      desc = "Draws a thin colored ring around your cursor at all times. "
          .. "Configurable color and thickness. Uses a minimal OnUpdate - "
          .. "just one API call and a SetPoint per frame, no logic or allocations." },
    { name = "Kicksmaxxing", key = "Kicksmaxxing",
      desc = "Dynamic focus-macro generator for interrupts, stuns, and CC. "
          .. "Enter any spell name to create a |cff52c4afKM_SpellName|r character macro that "
          .. "casts on focus when alive/hostile, otherwise focuses-and-casts on the next enemy. "
          .. "Enable up to |cff52c4af5|r spells at once with checkboxes." },
}

-- Build a quick lookup: key -> MODULES entry
local MODULE_BY_KEY = {}
for _, mod in ipairs(MODULES) do
    MODULE_BY_KEY[mod.key] = mod
    -- Register each known module in the debug registry immediately
    Debug.Register(mod.key)
end

local function Divider(parent, anchor, offY)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
    d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY)
    d:SetHeight(1)
    d:SetColorTexture(0.20, 0.58, 0.50, 0.45)
    return d
end

-- Canvas frame registered with Settings - never scrolls itself
local rootPanel = CreateFrame("Frame")
rootPanel.name = "ShodoQoL"
rootPanel:EnableMouse(false)
rootPanel:Hide()

-- ScrollFrame fills the canvas (leave 28px on the right for the scrollbar)
local scrollFrame = CreateFrame("ScrollFrame", nil, rootPanel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     rootPanel, "TOPLEFT",      0,   -4)
scrollFrame:SetPoint("BOTTOMRIGHT", rootPanel, "BOTTOMRIGHT", -28,   4)

-- All content is parented to this child frame
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetWidth(600)   -- fixed width; ScrollFrame clips horizontal overflow
content:SetHeight(1)    -- will be extended after all rows are built
scrollFrame:SetScrollChild(content)

-- ── Header ──────────────────────────────────────────────────────────
local titleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fShodo|r|cff52c4afQoL|r")

local verFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
verFS:SetPoint("LEFT", titleFS, "RIGHT", 8, -1)
verFS:SetText("|cff666666" .. VERSION .. "|r")

local subFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
subFS:SetText("|cff888888Personal quality-of-life tweaks for World of Warcraft|r")

local div0 = Divider(content, subFS, -10)

-- ── Modules section header ───────────────────────────────────────────
local modTitleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
modTitleFS:SetPoint("TOPLEFT", div0, "BOTTOMLEFT", 0, -14)
modTitleFS:SetText("|cff52c4afModules|r")

local reloadNoteFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
reloadNoteFS:SetPoint("LEFT", modTitleFS, "RIGHT", 12, 0)
reloadNoteFS:SetText("")

local prevAnchor   = modTitleFS
local statusBadges = {}
local toggleBtns   = {}

-- ── One row per module ───────────────────────────────────────────────
for _, mod in ipairs(MODULES) do
    local toggleBtn = CreateFrame("Button", nil, content)
    toggleBtn:SetSize(52, 20)
    toggleBtn:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -14)
    toggleBtn:EnableMouse(true)

    local tbBg = toggleBtn:CreateTexture(nil, "BACKGROUND")
    tbBg:SetAllPoints()
    tbBg:SetColorTexture(0.06, 0.06, 0.06, 0.90)

    local tbBorder = CreateFrame("Frame", nil, toggleBtn, "BackdropTemplate")
    tbBorder:SetAllPoints()
    tbBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, insets = {left=1,right=1,top=1,bottom=1} })
    tbBorder:EnableMouse(false)

    local tbLabel = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tbLabel:SetAllPoints()
    tbLabel:SetJustifyH("CENTER")
    tbLabel:SetJustifyV("MIDDLE")

    local nameFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("LEFT", toggleBtn, "RIGHT", 8, 0)
    nameFS:SetText("|cff33937f" .. mod.name .. "|r")

    local statusFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetPoint("LEFT", nameFS, "RIGHT", 10, -1)
    statusFS:SetText("|cff33937f[active]|r")
    if mod.addonKey then statusBadges[mod.addonKey] = statusFS end

    local descFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descFS:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -4)
    descFS:SetWidth(540)
    descFS:SetJustifyH("LEFT")
    descFS:SetTextColor(0.65, 0.65, 0.65)
    descFS:SetText(mod.desc)

    if mod.key then
        toggleBtns[mod.key] = { btn = toggleBtn, label = tbLabel,
                                 border = tbBorder, desc = descFS }
    end

    local modKey = mod.key
    toggleBtn:SetScript("OnClick", function()
        if not modKey then return end
        local cur = ShodoQoL._profile.enabled[modKey]
        local new = (cur == false) and true or false
        ShodoQoL._profile.enabled[modKey] = new
        local entry = toggleBtns[modKey]
        if new then
            entry.label:SetText("|cff33937f[ON]|r")
            entry.border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.80)
        else
            entry.label:SetText("|cffff4444[OFF]|r")
            entry.border:SetBackdropBorderColor(0.60, 0.10, 0.10, 0.80)
        end
        reloadNoteFS:SetText("|cffffd100Reload UI to apply changes (/rl)|r")
    end)
    toggleBtn:SetScript("OnEnter", function()
        tbBg:SetColorTexture(0.20, 0.20, 0.20, 0.90)
    end)
    toggleBtn:SetScript("OnLeave", function()
        tbBg:SetColorTexture(0.06, 0.06, 0.06, 0.90)
    end)

    prevAnchor = descFS
end

ShodoQoL._statusBadges = statusBadges
ShodoQoL._toggleBtns   = toggleBtns

local div1 = Divider(content, prevAnchor, -16)

-- ── Footer ───────────────────────────────────────────────────────────
local footer1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footer1:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -14)
footer1:SetWidth(560)
footer1:SetJustifyH("LEFT")
footer1:SetText(
    "|cff52c4afVersion:|r " .. VERSION .. " " .. TIMESTAMP
    .. " |cff52c4afWebsite:|r https://seemsgood.org"
    .. " |cff52c4afKo-fi:|r https://ko-fi.com/j51b5"
)

local footer2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footer2:SetPoint("TOPLEFT", footer1, "BOTTOMLEFT", 0, -8)
footer2:SetWidth(560)
footer2:SetJustifyH("LEFT")
footer2:SetText("|cff52c4afBugs & Issues:|r https://github.com/Seems-Good/ShodoQoL")

------------------------------------------------------------------------
-- Expand scroll child to fit all content.
-- We use OnShow so that font string heights are realised before measuring.
------------------------------------------------------------------------
content:SetScript("OnShow", function(self)
    local lowest = math.huge

    for i = 1, self:GetNumRegions() do
        local region = select(i, self:GetRegions())
        local b = region:GetBottom()
        if b and b < lowest then lowest = b end
    end

    for i = 1, self:GetNumChildren() do
        local child = select(i, self:GetChildren())
        local b = child:GetBottom()
        if b and b < lowest then lowest = b end
    end

    local top = self:GetTop()
    if top and lowest ~= math.huge then
        self:SetHeight(top - lowest + 24)
    end

    self:SetScript("OnShow", nil)
end)

content:SetHeight(400)

ShodoQoL.rootCategory = Settings.RegisterCanvasLayoutCategory(rootPanel, "ShodoQoL")
Settings.RegisterAddOnCategory(ShodoQoL.rootCategory)

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
local COLOR_YELLOW = "|cffffff00"
local COLOR_GRAY   = "|cff808080"
local COLOR_BLUE   = "|cff00ccff"

local FORMAT_NAME = COLOR_BLUE .. "[ShodoQoL]|r" .. COLOR_GRAY .. "-(" .. VERSION .. ")|r"

local TOTAL_MODULES = #MODULES

-- Status printer - used by both the login message and /sqol status.
local function PrintStatus()
    local enabledCount = 0
    for _, mod in ipairs(MODULES) do
        if ShodoQoL._profile.enabled[mod.key] ~= false then
            enabledCount = enabledCount + 1
        end
    end

    print(FORMAT_NAME .. COLOR_YELLOW .. " [" .. enabledCount .. "/" .. TOTAL_MODULES
        .. "]|r Modules Loaded\n- Type " .. COLOR_YELLOW .. "/sqol status|r to list them.")
end

local function PrintModuleStatus()
    print(FORMAT_NAME .. COLOR_YELLOW .. " Module Status:|r")
    for _, mod in ipairs(MODULES) do
        local on    = ShodoQoL._profile.enabled[mod.key] ~= false
        local badge = on
            and ("|cff33937f[ON] |r")
            or  ("|cffff4444[OFF]|r")
        print("  " .. badge .. " " .. COLOR_BLUE .. mod.name .. "|r")
    end
    print("  Use " .. COLOR_YELLOW .. "/sqol|r to open settings. Changes require |r"
        .. COLOR_YELLOW .. "/rl|r to take effect.")
end

------------------------------------------------------------------------
-- Resolve a module key from user input (case-insensitive, partial match)
-- Returns: canonical key (string) or nil, error message (string)
------------------------------------------------------------------------
local function ResolveModuleKey(input)
    if not input or input == "" then
        return nil, "No module name provided."
    end

    local lower = input:lower()

    -- 1) Exact case-insensitive match
    for _, mod in ipairs(MODULES) do
        if mod.key:lower() == lower then
            return mod.key, nil
        end
    end

    -- 2) Substring match
    local matches = {}
    for _, mod in ipairs(MODULES) do
        if mod.key:lower():find(lower, 1, true)
        or mod.name:lower():find(lower, 1, true) then
            matches[#matches + 1] = mod.key
        end
    end

    if #matches == 1 then
        return matches[1], nil
    elseif #matches > 1 then
        return nil, "Ambiguous module name '" .. input .. "'. Matches: " .. table.concat(matches, ", ")
    end

    return nil, "Unknown module '" .. input .. "'."
end

------------------------------------------------------------------------
-- /sqol enable <module> [--now]
------------------------------------------------------------------------
local function CmdEnable(arg, reload)
    local key, err = ResolveModuleKey(arg)
    if not key then
        print(FORMAT_NAME .. " |cffff4444" .. err .. "|r")
        return
    end

    ShodoQoL._profile.enabled[key] = true

    -- Update settings panel button if visible
    local entry = ShodoQoL._toggleBtns and ShodoQoL._toggleBtns[key]
    if entry then
        entry.label:SetText("|cff33937f[ON]|r")
        entry.border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.80)
    end

    local modName = MODULE_BY_KEY[key] and MODULE_BY_KEY[key].name or key
    print(FORMAT_NAME .. " |cff33937fEnabled:|r " .. modName
        .. (reload and " -- reloading now..." or
            " |cffffd100(reload UI to take effect: /rl)|r"))

    Debug.Register(key)
    PushEntry(key, Debug.LEVEL.LOAD, "enable command issued" .. (reload and " --now" or ""))

    if reload then
        ReloadUI()
    end
end

------------------------------------------------------------------------
-- /sqol disable <module> [--now]
------------------------------------------------------------------------
local function CmdDisable(arg, reload)
    local key, err = ResolveModuleKey(arg)
    if not key then
        print(FORMAT_NAME .. " |cffff4444" .. err .. "|r")
        return
    end

    ShodoQoL._profile.enabled[key] = false

    local entry = ShodoQoL._toggleBtns and ShodoQoL._toggleBtns[key]
    if entry then
        entry.label:SetText("|cffff4444[OFF]|r")
        entry.border:SetBackdropBorderColor(0.60, 0.10, 0.10, 0.80)
    end

    local modName = MODULE_BY_KEY[key] and MODULE_BY_KEY[key].name or key
    print(FORMAT_NAME .. " |cffff4444Disabled:|r " .. modName
        .. (reload and " -- reloading now..." or
            " |cffffd100(reload UI to take effect: /rl)|r"))

    Debug.Register(key)
    PushEntry(key, Debug.LEVEL.LOAD, "disable command issued" .. (reload and " --now" or ""))

    if reload then
        ReloadUI()
    end
end

------------------------------------------------------------------------
-- /sqol status <module>
------------------------------------------------------------------------
local function CmdModuleJournal(arg)
    local key, err = ResolveModuleKey(arg)
    if not key then
        print(FORMAT_NAME .. " |cffff4444" .. err .. "|r")
        -- List available modules as a hint
        local names = {}
        for _, mod in ipairs(MODULES) do names[#names+1] = mod.key end
        print("  Available: " .. table.concat(names, ", "))
        return
    end
    Debug.PrintJournal(key)
end

------------------------------------------------------------------------
-- Bootstrap event frame
------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:EnableMouse(false)
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)

    if event == "ADDON_LOADED" and arg1 == "ShodoQoL" then
        print(FORMAT_NAME .. "Type "
            .. COLOR_YELLOW .. "/sqol|r for options.")
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")

        -- Init or back-fill the global DB (non-profile settings: positions, etc.)
        if type(ShodoQoLDB) ~= "table" then
            ShodoQoLDB = CopyTable(ShodoQoL.DEFAULTS)
        else
            BackFill(ShodoQoLDB, ShodoQoL.DEFAULTS)
        end

        -- Resolve per-character profile. Each character gets its own enabled flags
        -- and class-check state, keyed by "CharName-RealmName".
        ShodoQoLDB.profiles = ShodoQoLDB.profiles or {}
        local charKey = UnitName("player") .. "-" .. GetRealmName()

        if not ShodoQoLDB.profiles[charKey] then
            -- First time this character has logged in with ShodoQoL.
            ShodoQoLDB.profiles[charKey] = CopyTable(ShodoQoL.PROFILE_DEFAULTS)
        else
            -- Back-fill any new keys added to PROFILE_DEFAULTS since last login.
            BackFill(ShodoQoLDB.profiles[charKey], ShodoQoL.PROFILE_DEFAULTS)
        end

        ShodoQoL._profile = ShodoQoLDB.profiles[charKey]

        -- One-time class check per character: auto-disable Evoker-only modules
        -- for non-Evokers. UnitClassBase is locale-independent.
        if not ShodoQoL._profile._classCheckDone then
            ShodoQoL._profile._classCheckDone = true
            if UnitClassBase("player") ~= "EVOKER" then
                for _, key in ipairs(EVOKER_ONLY_MODULES) do
                    ShodoQoL._profile.enabled[key] = false
                end
                print(FORMAT_NAME .. COLOR_GRAY .. " Non-Evoker detected: Evoker modules disabled."
                    .. " Re-enable anytime with |r" .. COLOR_YELLOW .. "/sqol|r.")
            end
        end

        PrintStatus()

        -- Update settings panel toggle buttons to reflect saved state
        for key, entry in pairs(ShodoQoL._toggleBtns or {}) do
            local enabled = ShodoQoL._profile.enabled[key] ~= false
            if enabled then
                entry.label:SetText("|cff33937f[ON]|r")
                entry.border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.80)
            else
                entry.label:SetText("|cffff4444[OFF]|r")
                entry.border:SetBackdropBorderColor(0.60, 0.10, 0.10, 0.80)
            end
        end

        -- Fire OnReady callbacks; wrap each in pcall and track load state in Debug
        for _, fn in ipairs(ShodoQoL.onReady or {}) do
            pcall(fn)
        end

        -- Update standalone/bundled badges
        for addonKey, fs in pairs(ShodoQoL._statusBadges or {}) do
            if C_AddOns.IsAddOnLoaded(addonKey) then
                fs:SetText("|cff52c4af[standalone]|r")
            else
                fs:SetText("|cff33937f[bundled]|r")
            end
        end

        ShodoQoL.onReady = nil
    end
end)

------------------------------------------------------------------------
-- OnReady - public API, unchanged
------------------------------------------------------------------------
function ShodoQoL.OnReady(fn)
    ShodoQoL.onReady = ShodoQoL.onReady or {}
    table.insert(ShodoQoL.onReady, fn)
end

-- After all OnReady callbacks fire (at PLAYER_LOGIN), mark each module
-- loaded or disabled based on IsEnabled.
-- We piggy-back on the existing boot frame via PLAYER_LOGIN ordering:
-- modules call ShodoQoL.OnReady during file-load (TOC order), then
-- PLAYER_LOGIN fires them all. We add our own tail callback here.
local _bootReady = CreateFrame("Frame")
_bootReady:EnableMouse(false)
_bootReady:RegisterEvent("PLAYER_LOGIN")
_bootReady:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- At this point the module OnReady callbacks have already fired
    -- (same event, TOC order means Core runs first so boot frame fires
    -- before this frame). To be safe use C_Timer.After(0) to push
    -- after all same-tick handlers.
    C_Timer.After(0, function()
        for _, mod in ipairs(MODULES) do
            if ShodoQoL.IsEnabled(mod.key) then
                if not Debug._registry[mod.key] or not Debug._registry[mod.key].loaded then
                    Debug.MarkLoaded(mod.key)
                end
            else
                Debug.MarkDisabled(mod.key)
            end
        end
    end)
end)

------------------------------------------------------------------------
-- Slash commands  /shodoqol  /sqol
--
-- /sqol                        - open settings panel
-- /sqol status                 - list all modules on/off
-- /sqol status <module>        - show debug journal for module
-- /sqol enable  <module>       - enable module (needs /rl)
-- /sqol enable  <module> --now - enable module + /reload
-- /sqol disable <module>       - disable module (needs /rl)
-- /sqol disable <module> --now - disable module + /reload
-- /sqol help                   - command reference
------------------------------------------------------------------------
SLASH_SHODOQOL1 = "/shodoqol"
SLASH_SHODOQOL2 = "/sqol"
SlashCmdList["SHODOQOL"] = function(msg)
    local raw  = msg and strtrim(msg) or ""
    local cmd  = raw:lower()

    -- Strip --now flag before further parsing
    local withReload = cmd:find("%-%-now") ~= nil
    local stripped   = raw:gsub("%s*%-%-now%s*", " "):gsub("%s+$", ""):gsub("^%s+", "")

    -- Tokenise: first word = verb, rest = argument
    local verb, rest = stripped:match("^(%S+)%s*(.*)")
    verb = verb and verb:lower() or ""
    rest = rest and strtrim(rest) or ""

    -- /sqol (no args)
    if verb == "" then
        Settings.OpenToCategory(ShodoQoL.rootCategory:GetID())
        return
    end

    -- /sqol status [module]
    if verb == "status" or verb == "modules" or verb == "mods" then
        if rest == "" then
            PrintModuleStatus()
        else
            CmdModuleJournal(rest)
        end
        return
    end

    -- /sqol enable <module> [--now]
    if verb == "enable" or verb == "on" then
        CmdEnable(rest, withReload)
        return
    end

    -- /sqol disable <module> [--now]
    if verb == "disable" or verb == "off" then
        CmdDisable(rest, withReload)
        return
    end

    -- /sqol help
    if verb == "help" then
        print(FORMAT_NAME)
        print("  " .. COLOR_YELLOW .. "/sqol|r                        - Open settings panel")
        print("  " .. COLOR_YELLOW .. "/sqol status|r                 - List all modules on/off")
        print("  " .. COLOR_YELLOW .. "/sqol status <module>|r        - Show debug journal for a module")
        print("  " .. COLOR_YELLOW .. "/sqol enable  <module>|r       - Enable a module (needs /rl)")
        print("  " .. COLOR_YELLOW .. "/sqol enable  <module> --now|r - Enable + reload immediately")
        print("  " .. COLOR_YELLOW .. "/sqol disable <module>|r       - Disable a module (needs /rl)")
        print("  " .. COLOR_YELLOW .. "/sqol disable <module> --now|r - Disable + reload immediately")
        print("  " .. COLOR_YELLOW .. "/sqol help|r                   - Show this message")
        print("  Module names are case-insensitive and support partial matching.")
        return
    end

    -- Unknown verb → open settings (matches original fallthrough behaviour)
    Settings.OpenToCategory(ShodoQoL.rootCategory:GetID())
end
