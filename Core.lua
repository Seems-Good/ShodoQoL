-- ShodoQoL/Core.lua
-- Shared init: SavedVariables, one-shot bootstrap, Settings category.

ShodoQoL = ShodoQoL or {}

ShodoQoL.COLOR = { r = 0.200, g = 0.576, b = 0.498 }
ShodoQoL.COLOR_HEX = "|cff33937f"
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
        targetName = nil,
        targetRealm = nil,
    },
    prescience1 = {
        targetName = nil,
        targetRealm = nil,
    },
    prescience2 = {
        targetName = nil,
        targetRealm = nil,
    },
    cauterizingFlame = {
        targetName = nil,
        targetRealm = nil,
    },
    blisteringScales = {
        targetName = nil,
        targetRealm = nil,
    },
    hearthStoned = {
        items = {},
        index = 1,
    },
    doNotRelease = {
        posX = 0,
        posY = 120,
        colorR = 1,
        colorG = 0.1,
        colorB = 0.1,
        warningText = "PLEASE DO NOT RELEASE",
        fontSize = 64,
        fontFace = "Fonts\\FRIZQT__.TTF",
    },
    sourceOfMagic = {
        posX        = 0,
        posY        = 80,
        colorR      = 0.20,
        colorG      = 0.75,
        colorB      = 1.00,
        warningText = "SOURCE OF MAGIC MISSING",
        fontSize    = 52,
        fontFace    = "Fonts\\FRIZQT__.TTF",
        targetName  = nil,
        targetRealm = nil,
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
    -- Per-module enabled flags. false = disabled (requires reload to take effect).
    enabled = {
        EssenceMover    = true,
        MacroHelpers    = true,
        HearthStoned    = true,
        CInspect        = true,
        DoNotRelease    = true,
        --ShoStats        = true,
        SourceOfMagic   = true,
        HoverTracker    = true,
        PrescienceTracker = true,
        MouseCircle     = false,
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
    if type(ShodoQoLDB) == "table" then
        return ShodoQoLDB.enabled[key] ~= false
    end
    -- DB not ready yet — consult compile-time defaults
    return ShodoQoL.DEFAULTS.enabled[key] ~= false
end

------------------------------------------------------------------------
-- Shared clean button
------------------------------------------------------------------------
function ShodoQoL.CreateButton(parent, label, width, height)
    width = width or 110
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
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
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
    btn:SetScript("OnMouseUp", function() bgPush:Hide() end)

    return btn
end

------------------------------------------------------------------------
-- Root Settings panel
------------------------------------------------------------------------
local VERSION = "v1.7.1"
local TIMESTAMP = "2026-04-22T03:56:26Z"

local MODULES = {
    { name = "Essence Mover", key = "EssenceMover",
      desc = "Drag your Evoker Essence bar anywhere on screen. "
          .. "Adjust scale with a live slider. Position persists across reloads and spec changes." },
    { name = "Macro Helpers", key = "MacroHelpers",
      desc = "Per-character macros with cross-realm support: |cff52c4afSpatial Paradox|r, "
          .. "|cff52c4afPrescience 1|r, and |cff52c4afPrescience 2|r — each targeting an independent player." },
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
 --         .. "with draggable frame, opacity/scale sliders, and per-stat visibility toggles." },
    { name = "Hover Tracker", key = "HoverTracker",
      desc = "Evoker-only. Glows green/amber/red behind your cast bar based on whether Hover lets you "
          .. "move while casting. Alerts when Hover has no charges. Configurable font, size, and opacity." },
    { name = "Prescience Tracker", key = "PrescienceTracker",
      desc = "Live Prescience buff state tracking 'aura' on your P1 and P2 targets. "
          .. "Color-coded: green o (active), orange ! (expiring), red x (missing), grey - (not in group). "
          .. "Purely event-driven with zero CPU overhead. Augmentation Evoker only." },
    { name = "Mouse Circle", key = "MouseCircle",
      desc = "Draws a thin colored ring around your cursor at all times. "
          .. "Configurable color and thickness. Uses a minimal OnUpdate — "
          .. "just one API call and a SetPoint per frame, no logic or allocations." },
  }

local function Divider(parent, anchor, offY)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY)
    d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY)
    d:SetHeight(1)
    d:SetColorTexture(0.20, 0.58, 0.50, 0.45)
    return d
end

-- Canvas frame registered with Settings — never scrolls itself
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

local prevAnchor = modTitleFS
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
        local cur = ShodoQoLDB.enabled[modKey]
        local new = (cur == false) and true or false
        ShodoQoLDB.enabled[modKey] = new
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
    -- Walk all regions AND child frames to find the lowest screen-space Y edge.
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
local boot = CreateFrame("Frame")
boot:EnableMouse(false)
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if type(ShodoQoLDB) ~= "table" then
        ShodoQoLDB = CopyTable(ShodoQoL.DEFAULTS)
    else
        BackFill(ShodoQoLDB, ShodoQoL.DEFAULTS)
    end

    for key, entry in pairs(ShodoQoL._toggleBtns or {}) do
        local enabled = ShodoQoLDB.enabled[key] ~= false
        if enabled then
            entry.label:SetText("|cff33937f[ON]|r")
            entry.border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.80)
        else
            entry.label:SetText("|cffff4444[OFF]|r")
            entry.border:SetBackdropBorderColor(0.60, 0.10, 0.10, 0.80)
        end
    end

    for _, fn in ipairs(ShodoQoL.onReady or {}) do
        pcall(fn)
    end

    for addonKey, fs in pairs(ShodoQoL._statusBadges or {}) do
        if C_AddOns.IsAddOnLoaded(addonKey) then
            fs:SetText("|cff52c4af[standalone]|r")
        else
            fs:SetText("|cff33937f[bundled]|r")
        end
    end

    ShodoQoL.onReady = nil
end)

function ShodoQoL.OnReady(fn)
    ShodoQoL.onReady = ShodoQoL.onReady or {}
    table.insert(ShodoQoL.onReady, fn)
end

------------------------------------------------------------------------
-- Slash commands  /shodoqol  /sqol
------------------------------------------------------------------------
SLASH_SHODOQOL1 = "/shodoqol"
SLASH_SHODOQOL2 = "/sqol"
SlashCmdList["SHODOQOL"] = function()
    Settings.OpenToCategory(ShodoQoL.rootCategory:GetID())
end
