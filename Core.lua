-- ShodoQoL/Core.lua
-- Shared init: SavedVariables, one-shot bootstrap, Settings category.

ShodoQoL = ShodoQoL or {}

-- Evoker class colour (#33937F) used across all modules
ShodoQoL.COLOR      = { r = 0.200, g = 0.576, b = 0.498 }  -- #33937F
ShodoQoL.COLOR_HEX  = "|cff33937f"   -- for chat/print prefixes
ShodoQoL.COLOR_LITE = "|cff52c4af"   -- lighter tint for subtitles

------------------------------------------------------------------------
-- Master defaults
------------------------------------------------------------------------
ShodoQoL.DEFAULTS = {
    essenceMover = {
        x     = nil,
        y     = nil,
        scale = 1.5,
    },
    spatialParadox = {
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
}

------------------------------------------------------------------------
-- Deep back-fill
------------------------------------------------------------------------
local function BackFill(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(saved[k]) == "table" then
            BackFill(saved[k], v)
        end
    end
end

------------------------------------------------------------------------
-- Shared clean button factory — NO UIPanelButtonTemplate.
-- That template uses the ButtonSkin mixin in 12.x which injects OnUpdate
-- animation scripts for hover/press effects.  These run every frame once
-- the Settings canvas initialises the panel on first visit.
-- A bare Button + manual textures has zero built-in scripts.
------------------------------------------------------------------------
function ShodoQoL.CreateButton(parent, label, width, height)
    width  = width  or 110
    height = height or 24

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    btn:EnableMouse(true)

    -- Background layers
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

    -- Border (BackdropTemplate is fine — no scripts of its own)
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.70)
    border:EnableMouse(false)

    -- Label
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetText(label)
    fs:SetTextColor(0.90, 0.95, 0.92)

    -- Event-driven hover/push — no OnUpdate
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
    btn:SetScript("OnMouseUp",   function() bgPush:Hide() end)

    return btn
end

------------------------------------------------------------------------
-- Root Settings category  — overview, module list, footer
-- C-Inspect status is populated in OnReady (after addon load is known).
------------------------------------------------------------------------
local VERSION = "1.0.0"

local MODULES = {
    {
        name  = "Essence Mover",
        desc  = "Drag your Evoker Essence bar anywhere on screen. "
             .. "Adjust scale with a live slider. Position persists across "
             .. "reloads and spec changes.",
    },
    {
        name  = "Spatial Paradox",
        desc  = "Auto-generates a |cff52c4af/cast [@Name,nodead]|r macro for "
             .. "Spatial Paradox (Bronze). Supports cross-realm targets. "
             .. "Per-character macro slot.",
    },
    {
        name  = "HearthStoned",
        desc  = "Cycles through all owned hearthstone toys with a single "
             .. "per-character macro. Rescan at any time to pick up new toys.",
    },
    {
        name  = "C-Inspect",
        desc  = "Hold |cff52c4afCtrl|r and left-click a friendly player to "
             .. "inspect them instantly. Also registers |cff52c4af/rl|r to "
             .. "reload your UI quickly.",
        addonKey = "C-Inspect",
    },
    {
        name  = "DoNotRelease",
        desc  = "Shows a pulsing warning on screen when you die inside a group "
             .. "instance. Fully configurable text, color, font, and position. "
             .. "Use |cff52c4af/dnr test|r to preview.",
        addonKey = "DoNotRelease",
    },
}

local function Divider(parent, anchor, offY)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
    d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY)
    d:SetHeight(1)
    d:SetColorTexture(0.20, 0.58, 0.50, 0.45)
    return d
end

local rootPanel = CreateFrame("Frame")
rootPanel.name  = "ShodoQoL"
rootPanel:EnableMouse(false)
rootPanel:Hide()

-- ── Header ────────────────────────────────────────────────────────────
local titleFS = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fShodo|r|cff52c4afQoL|r")

local verFS = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
verFS:SetPoint("LEFT", titleFS, "RIGHT", 8, -1)
verFS:SetText("|cff666666v" .. VERSION .. "|r")

local subFS = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
subFS:SetText("|cff888888Personal quality-of-life tweaks for World of Warcraft|r")

local div0 = Divider(rootPanel, subFS, -10)

-- ── Modules section ───────────────────────────────────────────────────
local modTitleFS = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
modTitleFS:SetPoint("TOPLEFT", div0, "BOTTOMLEFT", 0, -14)
modTitleFS:SetText("|cff52c4afModules|r")

local prevAnchor = modTitleFS
local statusBadges = {}  -- addonKey -> fontstring

for _, mod in ipairs(MODULES) do
    local nameFS = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -16)
    nameFS:SetText("|cff33937f" .. mod.name .. "|r")

    local statusFS = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetPoint("LEFT", nameFS, "RIGHT", 10, -1)
    statusFS:SetText("|cff33937f[active]|r")
    if mod.addonKey then statusBadges[mod.addonKey] = statusFS end

    local descFS = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -5)
    descFS:SetWidth(540)
    descFS:SetJustifyH("LEFT")
    descFS:SetTextColor(0.65, 0.65, 0.65)
    descFS:SetText(mod.desc)

    prevAnchor = descFS
end

ShodoQoL._statusBadges = statusBadges

local div1 = Divider(rootPanel, prevAnchor, -16)

-- ── Footer — one row per line for clean alignment ─────────────────────
local footer1 = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footer1:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -14)
footer1:SetWidth(560)
footer1:SetJustifyH("LEFT")
footer1:SetText(
    "|cff52c4afVersion:|r  " .. VERSION
    .. "          |cff52c4afWebsite:|r  https://seemsgood.org"
    .. "          |cff52c4afKo-fi:|r  https://ko-fi.com/j51b5"
)

local footer2 = rootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footer2:SetPoint("TOPLEFT", footer1, "BOTTOMLEFT", 0, -8)
footer2:SetWidth(560)
footer2:SetJustifyH("LEFT")
footer2:SetText("|cff52c4afBugs & Issues:|r  https://github.com/Seems-Good/ShodoQoL")

ShodoQoL.rootCategory = Settings.RegisterCanvasLayoutCategory(rootPanel, "ShodoQoL")
Settings.RegisterAddOnCategory(ShodoQoL.rootCategory)

------------------------------------------------------------------------
-- Bootstrap — PLAYER_LOGIN fires once per UI load, unregisters itself.
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

    for _, fn in ipairs(ShodoQoL.onReady or {}) do
        pcall(fn)
    end

    -- Update status badges for all bundled addons
    local badges = ShodoQoL._statusBadges or {}
    for addonKey, fs in pairs(badges) do
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
