-- ShodoQoL/DoNotRelease.lua
-- Shows a pulsing "DO NOT RELEASE" warning when you die in a group instance.
-- Bundled from DoNotRelease by Jeremy-Gstein (Shodo / SeemsGood).
-- Skips loading entirely if the standalone "DoNotRelease" addon is active.

if C_AddOns.IsAddOnLoaded("DoNotRelease") then return end

------------------------------------------------------------------------
-- Defaults (stored under ShodoQoLDB.doNotRelease)
------------------------------------------------------------------------
local DNR_DEFAULTS = {
    posX        = 0,
    posY        = 120,
    colorR      = 1,
    colorG      = 0.1,
    colorB      = 0.1,
    warningText = "PLEASE DO NOT RELEASE",
    fontSize    = 64,
    fontFace    = "Fonts\\FRIZQT__.TTF",
}

local MAX_TEXT_LEN  = 32
local FONT_SIZE_MIN = 32
local FONT_SIZE_MAX = 96
local TEST_DURATION = 10

local FONT_PRESETS = {
    { label = "Default", file = "Fonts\\FRIZQT__.TTF" },
    { label = "Clean",   file = "Fonts\\ARIALN.TTF"   },
    { label = "Fancy",   file = "Fonts\\MORPHEUS.TTF" },
    { label = "Runic",   file = "Fonts\\SKURRI.TTF"   },
}

local COLOR_PRESETS = {
    { label = "Red",    r = 1,   g = 0.1,  b = 0.1 },
    { label = "Orange", r = 1,   g = 0.55, b = 0.0 },
    { label = "Yellow", r = 1,   g = 1,    b = 0.0 },
    { label = "White",  r = 1,   g = 1,    b = 1   },
    { label = "Cyan",   r = 0.0, g = 1,    b = 1   },
}

local _sin   = math.sin
local _pi2   = math.pi * 2
local _floor = math.floor
local _ceil  = math.ceil

------------------------------------------------------------------------
-- DB accessor (ShodoQoLDB is guaranteed init'd by Core before OnReady)
------------------------------------------------------------------------
local function DB() return ShodoQoLDB.doNotRelease end

------------------------------------------------------------------------
-- Group / instance checks
------------------------------------------------------------------------
local function PlayerIsInInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance
        and instanceType ~= "none"
        and instanceType ~= "pvp"
        and instanceType ~= "arena"
end

local _isInGroup
if C_PartyInfo and C_PartyInfo.IsInGroup then
    _isInGroup = function()
        return C_PartyInfo.IsInGroup(LE_PARTY_CATEGORY_HOME)
            or C_PartyInfo.IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
else
    _isInGroup = function() return IsInGroup() or IsInRaid() end
end

local function ShouldWarn()
    return UnitIsDead("player") and _isInGroup() and PlayerIsInInstance()
end

------------------------------------------------------------------------
-- Warning frame
------------------------------------------------------------------------
local warnFrame = CreateFrame("Frame", "ShodoQoLDNRFrame", UIParent)
warnFrame:SetSize(800, 200)
warnFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
warnFrame:SetFrameStrata("HIGH")
warnFrame:SetFrameLevel(100)
warnFrame:EnableMouse(false)
warnFrame:Hide()

local label = warnFrame:CreateFontString(nil, "OVERLAY")
label:SetPoint("CENTER")
label:SetFont("Fonts\\FRIZQT__.TTF", 64, "OUTLINE")
label:SetTextColor(1, 0.1, 0.1, 1)
label:SetShadowColor(1, 0.55, 0, 1)
label:SetShadowOffset(0, 0)
label:SetText("PLEASE DO NOT RELEASE")

------------------------------------------------------------------------
-- Pulse (alpha-only, OnUpdate only while warnFrame is shown)
------------------------------------------------------------------------
local PULSE_PERIOD = 1.5
local ALPHA_MIN    = 0.35
local ALPHA_MAX    = 1.00
local ALPHA_MID    = (ALPHA_MAX + ALPHA_MIN) / 2
local ALPHA_AMP    = (ALPHA_MAX - ALPHA_MIN) / 2
local PHASE_OFFSET = math.pi / 2
local pulseTime    = 0
local previewMode  = false

local function onUpdate(self, elapsed)
    if not previewMode and not ShouldWarn() then
        HideWarning()
        return
    end
    pulseTime = (pulseTime + elapsed) % PULSE_PERIOD
    self:SetAlpha(ALPHA_MID + ALPHA_AMP * _sin(
        pulseTime * _pi2 / PULSE_PERIOD + PHASE_OFFSET))
end

warnFrame:SetScript("OnShow", function(self)
    pulseTime = 0
    self:SetScript("OnUpdate", onUpdate)
end)
warnFrame:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
    self:SetAlpha(1)
end)

------------------------------------------------------------------------
-- Apply DB values to the warning frame
------------------------------------------------------------------------
local function ApplyAll()
    local db = DB()
    warnFrame:ClearAllPoints()
    warnFrame:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
    label:SetTextColor(db.colorR, db.colorG, db.colorB, 1)
    label:SetText(db.warningText ~= "" and db.warningText or DNR_DEFAULTS.warningText)
    label:SetFont(db.fontFace, db.fontSize, "OUTLINE")
end

local function SavePosition()
    local x, y   = warnFrame:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not x or not cx then return end
    local db = DB()
    db.posX = x - cx
    db.posY = y - cy
end

------------------------------------------------------------------------
-- Show / Hide / Drag
------------------------------------------------------------------------
function ShowWarning()
    if ShouldWarn() then warnFrame:Show() end
end

function HideWarning()
    previewMode = false
    warnFrame:Hide()
end

local function EnableDrag()
    warnFrame:SetMovable(true)
    warnFrame:EnableMouse(true)
    warnFrame:RegisterForDrag("LeftButton")
    warnFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    warnFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
        print("|cff33937fShodoQoL|r DoNotRelease: position saved.")
    end)
end

local function DisableDrag()
    warnFrame:SetMovable(false)
    warnFrame:EnableMouse(false)
    warnFrame:SetScript("OnDragStart", nil)
    warnFrame:SetScript("OnDragStop", nil)
end

------------------------------------------------------------------------
-- Settings sub-page  (ShodoQoL > DoNotRelease)
------------------------------------------------------------------------
local function BuildPanel()
    local panel = CreateFrame("Frame")
    panel.name   = "DoNotRelease"
    panel.parent = "ShodoQoL"
    panel:EnableMouse(false)
    panel:Hide()

    local W   = 560
    local PAD = 0
    local BH  = 26
    local HW  = math.floor((W - 8) / 2)

    local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", 16, -16)
    titleFS:SetText("|cff33937fDo Not|r|cff52c4afRelease|r")

    local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
    subFS:SetText("|cff888888Pulsing reminder when you die in a group instance|r")

    local function Div(anchor, offY)
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
        d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY)
        d:SetHeight(1)
        d:SetColorTexture(0.20, 0.58, 0.50, 0.45)
        return d
    end

    local function SecLabel(anchor, offY, text)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY)
        fs:SetText("|cff52c4af" .. text .. "|r")
        return fs
    end

    -- ── Position ─────────────────────────────────────────────────────
    local div0 = Div(subFS, -12)
    local posHdr = SecLabel(div0, -14, "Position")

    local showBtn = ShodoQoL.CreateButton(panel, "Show Warning", HW, BH)
    showBtn:SetPoint("TOPLEFT", posHdr, "BOTTOMLEFT", 0, -8)
    showBtn:SetScript("OnClick", function()
        previewMode = true
        warnFrame:Show()
    end)

    local hideBtn = ShodoQoL.CreateButton(panel, "Hide Warning", HW, BH)
    hideBtn:SetPoint("LEFT", showBtn, "RIGHT", 8, 0)
    hideBtn:SetScript("OnClick", function()
        DisableDrag()
        HideWarning()
    end)

    local dragBtn = ShodoQoL.CreateButton(panel, "Drag to Reposition", HW, BH)
    dragBtn:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -6)
    dragBtn:SetScript("OnClick", function()
        previewMode = true
        warnFrame:Show()
        EnableDrag()
        print("|cff33937fShodoQoL|r DoNotRelease: drag the text, release to save.")
    end)

    local resetPosBtn = ShodoQoL.CreateButton(panel, "Reset Position", HW, BH)
    resetPosBtn:SetPoint("LEFT", dragBtn, "RIGHT", 8, 0)
    resetPosBtn:SetScript("OnClick", function()
        local db = DB()
        db.posX, db.posY = DNR_DEFAULTS.posX, DNR_DEFAULTS.posY
        ApplyAll()
    end)

    -- ── Color ────────────────────────────────────────────────────────
    local div1 = Div(dragBtn, -14)
    local colorHdr = SecLabel(div1, -14, "Warning Color")

    local colorAnchor = colorHdr
    for i, preset in ipairs(COLOR_PRESETS) do
        local btn = ShodoQoL.CreateButton(panel, preset.label, HW, BH)
        if i % 2 == 1 then
            btn:SetPoint("TOPLEFT", colorAnchor, "BOTTOMLEFT", 0, i == 1 and -8 or -6)
            colorAnchor = btn
        else
            btn:SetPoint("LEFT", colorAnchor, "RIGHT", 8, 0)
        end
        local r, g, b = preset.r, preset.g, preset.b
        btn:SetScript("OnClick", function()
            local db = DB()
            db.colorR, db.colorG, db.colorB = r, g, b
            label:SetTextColor(r, g, b, 1)
        end)
    end

    -- ── Warning Text ─────────────────────────────────────────────────
    local div2 = Div(colorAnchor, -14)
    local textHdr = SecLabel(div2, -14, "Warning Text")

    local nameBox = CreateFrame("EditBox", nil, panel)
    nameBox:SetSize(W, BH)
    nameBox:SetPoint("TOPLEFT", textHdr, "BOTTOMLEFT", 0, -8)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject("ChatFontNormal")
    nameBox:SetTextInsets(6, 6, 0, 0)
    nameBox:SetMaxLetters(MAX_TEXT_LEN)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    do  -- border
        local bg = nameBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
        local border = CreateFrame("Frame", nil, nameBox, "BackdropTemplate")
        border:SetAllPoints()
        border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                             insets = { left=2, right=2, top=2, bottom=2 } })
        border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7)
        border:EnableMouse(false)
        nameBox:SetScript("OnEditFocusGained", function() border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1) end)
        nameBox:SetScript("OnEditFocusLost",   function() border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7) end)
    end

    local setTextBtn = ShodoQoL.CreateButton(panel, "Set Text", HW, BH)
    setTextBtn:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -6)
    setTextBtn:SetScript("OnClick", function()
        local raw = strtrim(nameBox:GetText())
        if raw == "" then
            print("|cffff6060ShodoQoL|r DoNotRelease: text cannot be empty."); return
        end
        local db = DB()
        db.warningText = raw
        label:SetText(raw)
        label:SetFont(db.fontFace, db.fontSize, "OUTLINE")
        nameBox:ClearFocus()
    end)

    local resetTextBtn = ShodoQoL.CreateButton(panel, "Reset Text", HW, BH)
    resetTextBtn:SetPoint("LEFT", setTextBtn, "RIGHT", 8, 0)
    resetTextBtn:SetScript("OnClick", function()
        local db = DB()
        db.warningText = DNR_DEFAULTS.warningText
        label:SetText(db.warningText)
        label:SetFont(db.fontFace, db.fontSize, "OUTLINE")
        nameBox:SetText(db.warningText)
    end)

    -- ── Font ─────────────────────────────────────────────────────────
    local div3 = Div(setTextBtn, -14)
    local fontHdr = SecLabel(div3, -14, "Font")

    local fontAnchor = fontHdr
    for i, preset in ipairs(FONT_PRESETS) do
        local btn = ShodoQoL.CreateButton(panel, preset.label, HW, BH)
        if i % 2 == 1 then
            btn:SetPoint("TOPLEFT", fontAnchor, "BOTTOMLEFT", 0, i == 1 and -8 or -6)
            fontAnchor = btn
        else
            btn:SetPoint("LEFT", fontAnchor, "RIGHT", 8, 0)
        end
        local fFile = preset.file
        btn:SetScript("OnClick", function()
            local db = DB()
            db.fontFace = fFile
            label:SetFont(fFile, db.fontSize, "OUTLINE")
        end)
    end

    -- ── Font Size slider — bare Slider, no OptionsSliderTemplate ─────
    local div4 = Div(fontAnchor, -14)
    local sizeHdr = SecLabel(div4, -14, "Font Size")

    local sizeValFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeValFS:SetPoint("LEFT", sizeHdr, "RIGHT", 10, 0)
    sizeValFS:SetText("64pt")

    local minFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minFS:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 0, -38)
    minFS:SetText(FONT_SIZE_MIN .. "pt")
    minFS:SetTextColor(0.5, 0.5, 0.5)

    local maxFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxFS:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 300, -38)
    maxFS:SetText(FONT_SIZE_MAX .. "pt")
    maxFS:SetTextColor(0.5, 0.5, 0.5)

    local sizeCont = CreateFrame("Frame", nil, panel)
    sizeCont:SetSize(320, 36)
    sizeCont:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 0, -18)
    sizeCont:EnableMouse(false)

    local track = sizeCont:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 10, 0); track:SetPoint("RIGHT", -10, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.06, 0.18, 0.16, 0.90)

    local shine = sizeCont:CreateTexture(nil, "BORDER")
    shine:SetPoint("LEFT", 10, 1); shine:SetPoint("RIGHT", -10, 1)
    shine:SetHeight(2)
    shine:SetColorTexture(0.20, 0.68, 0.58, 0.40)

    local sizeSlider = CreateFrame("Slider", "ShodoQoLDNRSizeSlider", sizeCont)
    sizeSlider:SetAllPoints()
    sizeSlider:EnableMouse(true)
    sizeSlider:SetOrientation("HORIZONTAL")
    sizeSlider:SetMinMaxValues(FONT_SIZE_MIN, FONT_SIZE_MAX)
    sizeSlider:SetValueStep(2)
    sizeSlider:SetObeyStepOnDrag(true)

    local thumbBorder = sizeSlider:CreateTexture(nil, "OVERLAY")
    thumbBorder:SetSize(18, 26)
    thumbBorder:SetColorTexture(0.04, 0.12, 0.10, 1)
    local thumb = sizeSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 22)
    thumb:SetColorTexture(0.25, 0.78, 0.66, 1)
    thumb:SetDrawLayer("OVERLAY", 1)
    thumbBorder:SetPoint("CENTER", thumb, "CENTER", 0, 0)
    sizeSlider:SetThumbTexture(thumb)

    local lastSize = DNR_DEFAULTS.fontSize
    sizeSlider:SetScript("OnValueChanged", function(self, val)
        local size = _floor(val + 0.5)
        sizeValFS:SetText(size .. "pt")
        if size == lastSize then return end
        lastSize = size
        local db = DB()
        db.fontSize = size
        label:SetFont(db.fontFace, size, "OUTLINE")
    end)

    -- Sync panel state on show
    panel:SetScript("OnShow", function()
        local db = DB()
        nameBox:SetText(db.warningText)
        local sz = db.fontSize
        lastSize = sz
        sizeSlider:SetValue(sz)
        sizeValFS:SetText(sz .. "pt")
    end)

    if SettingsPanel then
        SettingsPanel:HookScript("OnHide", function()
            DisableDrag()
            if not ShouldWarn() then HideWarning() end
        end)
    end

    local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "DoNotRelease")
    Settings.RegisterAddOnCategory(subCat)
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_SHODO_DNR1 = "/dnr"
SlashCmdList["SHODO_DNR"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "test" then
        previewMode = true
        warnFrame:Show()
        print("|cff33937fShodoQoL|r DoNotRelease: test mode — warning shown.")
        C_Timer.After(TEST_DURATION, function()
            if not ShouldWarn() then HideWarning() end
        end)
    elseif cmd == "hide" then
        HideWarning()
    else
        print("|cff33937fShodoQoL|r DoNotRelease: |cffffd100/dnr test|r  |  |cffffd100/dnr hide|r")
    end
end

------------------------------------------------------------------------
-- Hook into Core bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    local db = ShodoQoLDB.doNotRelease
    for k, v in pairs(DNR_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end

    BuildPanel()  -- always build so user can re-enable from settings

    if not ShodoQoL.IsEnabled("DoNotRelease") then return end

    ApplyAll()

    local rosterPending = false
    local evtFrame = CreateFrame("Frame")
    evtFrame:EnableMouse(false)
    evtFrame:RegisterEvent("PLAYER_DEAD")
    evtFrame:RegisterEvent("PLAYER_ALIVE")
    evtFrame:RegisterEvent("PLAYER_UNGHOST")
    evtFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evtFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_DEAD" then
            C_Timer.After(0.3, ShowWarning)
        elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
            HideWarning(); DisableDrag()
        elseif event == "GROUP_ROSTER_UPDATE" then
            if rosterPending then return end
            rosterPending = true
            C_Timer.After(0.25, function()
                rosterPending = false
                if warnFrame:IsShown() and not ShouldWarn() then HideWarning() end
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            HideWarning()
            C_Timer.After(0.5, function()
                if ShouldWarn() then ShowWarning() end
            end)
        end
    end)
end)
