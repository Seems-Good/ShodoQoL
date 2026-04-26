-- ShodoQoL/DoNotRelease.lua
-- Shows a pulsing "DO NOT RELEASE" warning when you die in a group instance.
-- Bundled from DoNotRelease by Jeremy-Gstein (Shodo / SeemsGood).
-- Skips loading entirely if the standalone "DoNotRelease" addon is active.
--
-- Release Guard modes (intercept the native Release Spirit popup):
--   "off"       — no guard (default)
--   "timer"     — countdown timer before native popup appears
--   "code"      — type a random 4-digit code to confirm release
--   "totp"      — enter a 6-digit TOTP code from an authenticator app
--
-- Slash commands:
--   /dnr test   — preview the warning for 10 seconds
--   /dnr hide   — hide the warning
--   (Settings panel lives at ShodoQoL > DoNotRelease)

if C_AddOns.IsAddOnLoaded("DoNotRelease") then return end

------------------------------------------------------------------------
-- Defaults (stored under ShodoQoLDB.doNotRelease)
------------------------------------------------------------------------
local DNR_DEFAULTS = {
    posX         = 0,
    posY         = 120,
    colorR       = 1,
    colorG       = 0.1,
    colorB       = 0.1,
    warningText  = "PLEASE DO NOT RELEASE",
    fontSize     = 64,
    fontFace     = "Fonts\\FRIZQT__.TTF",
    releaseGuard = "off",   -- "off" | "timer" | "code" | "totp"
    totpSecret   = nil,
}

local MAX_TEXT_LEN       = 32
local FONT_SIZE_MIN      = 32
local FONT_SIZE_MAX      = 96
local TEST_DURATION      = 10
local RELEASE_TIMER_SECS = 5

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
    { label = "Green",  r = 0.2, g = 1,    b = 0.2 },
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

local function HideWarning()
    previewMode = false
    warnFrame:Hide()
end

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
local function ShowWarning()
    if ShouldWarn() then warnFrame:Show() end
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
-- Release Guard — Timer overlay
------------------------------------------------------------------------
local timerFrame = CreateFrame("Frame", "ShodoQoLDNRTimerFrame", UIParent, "BasicFrameTemplate")
timerFrame:SetSize(300, 130)
timerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
timerFrame:SetFrameStrata("DIALOG")
timerFrame:SetFrameLevel(250)
timerFrame:Hide()
timerFrame:SetMovable(true)
timerFrame:EnableMouse(true)
timerFrame:RegisterForDrag("LeftButton")
timerFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
timerFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

local timerLabel = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
timerLabel:SetPoint("CENTER", timerFrame, "CENTER", 0, 18)

local timerCancelBtn = CreateFrame("Button", nil, timerFrame, "UIPanelButtonTemplate")
timerCancelBtn:SetSize(140, 26)
timerCancelBtn:SetPoint("BOTTOM", timerFrame, "BOTTOM", 0, 14)
timerCancelBtn:SetText("Cancel")

local timerRemaining  = 0
local timerTicker     = nil
local timerDismissing = false
local _dnrSuppressNext = false

local function StopReleaseTimerInternal()
    timerDismissing = true
    if timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
    timerFrame:Hide()
    timerDismissing = false
end

local function FinishTimerAndShowNative()
    StopReleaseTimerInternal()
    _dnrSuppressNext = true
    StaticPopup_Show("DEATH")
end

timerCancelBtn:SetScript("OnClick", FinishTimerAndShowNative)

timerFrame:SetScript("OnHide", function()
    if not timerDismissing and timerTicker and UnitIsDeadOrGhost("player") then
        timerTicker:Cancel()
        timerTicker = nil
        _dnrSuppressNext = true
        StaticPopup_Show("DEATH")
    elseif timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end)

local function StartReleaseTimerOverlay()
    StopReleaseTimerInternal()
    timerRemaining = RELEASE_TIMER_SECS
    timerLabel:SetText(string.format("Release available in %d\226\128\166", timerRemaining))
    timerFrame:Show()
    timerTicker = C_Timer.NewTicker(1, function()
        timerRemaining = timerRemaining - 1
        if timerRemaining <= 0 then
            FinishTimerAndShowNative()
        else
            timerLabel:SetText(string.format("Release available in %d\226\128\166", timerRemaining))
        end
    end, RELEASE_TIMER_SECS)
end

------------------------------------------------------------------------
-- Release Guard — Random Code overlay
------------------------------------------------------------------------
local codeFrame = CreateFrame("Frame", "ShodoQoLDNRCodeFrame", UIParent, "BasicFrameTemplate")
codeFrame:SetSize(320, 190)
codeFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
codeFrame:SetFrameStrata("DIALOG")
codeFrame:SetFrameLevel(250)
codeFrame:Hide()
codeFrame:SetMovable(true)
codeFrame:EnableMouse(true)
codeFrame:RegisterForDrag("LeftButton")
codeFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
codeFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

local codeTitle = codeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
codeTitle:SetPoint("TOP", codeFrame, "TOP", 0, -28)
codeTitle:SetText("Confirm Release")

local codeInstr = codeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
codeInstr:SetPoint("TOP", codeTitle, "BOTTOM", 0, -6)
codeInstr:SetTextColor(0.8, 0.8, 0.8, 1)
codeInstr:SetText("Type the code below to release:")

local codeDisplay = codeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
codeDisplay:SetPoint("TOP", codeInstr, "BOTTOM", 0, -8)
codeDisplay:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
codeDisplay:SetTextColor(1, 0.82, 0.0, 1)

local codeInput = CreateFrame("EditBox", "ShodoQoLDNRCodeInput", codeFrame, "InputBoxTemplate")
codeInput:SetSize(120, 28)
codeInput:SetPoint("TOP", codeDisplay, "BOTTOM", 0, -10)
codeInput:SetMaxLetters(4)
codeInput:SetAutoFocus(false)
codeInput:SetNumeric(true)

local codeFeedback = codeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
codeFeedback:SetPoint("TOP", codeInput, "BOTTOM", 0, -4)
codeFeedback:SetTextColor(1, 0.2, 0.2, 1)
codeFeedback:SetText("")

local codeConfirmBtn = CreateFrame("Button", nil, codeFrame, "UIPanelButtonTemplate")
codeConfirmBtn:SetSize(130, 26)
codeConfirmBtn:SetPoint("BOTTOMLEFT", codeFrame, "BOTTOMLEFT", 14, 14)
codeConfirmBtn:SetText("Confirm")

local codeCancelBtn = CreateFrame("Button", nil, codeFrame, "UIPanelButtonTemplate")
codeCancelBtn:SetSize(130, 26)
codeCancelBtn:SetPoint("BOTTOMRIGHT", codeFrame, "BOTTOMRIGHT", -14, 14)
codeCancelBtn:SetText("Cancel")

local codeCurrentCode = ""
local codeDismissing  = false

local function StopCodeInternal()
    codeDismissing = true
    codeCurrentCode = ""
    codeFrame:Hide()
    codeInput:SetText("")
    codeFeedback:SetText("")
    codeInput:ClearFocus()
    codeDismissing = false
end

local function FinishCodeAndShowNative()
    StopCodeInternal()
    _dnrSuppressNext = true
    StaticPopup_Show("DEATH")
end

local function AttemptCodeConfirm()
    local entered = strtrim(codeInput:GetText())
    if entered == codeCurrentCode then
        FinishCodeAndShowNative()
    else
        codeFeedback:SetText("Incorrect code... try again.")
        codeInput:SetText("")
        codeInput:SetFocus()
    end
end

codeConfirmBtn:SetScript("OnClick", AttemptCodeConfirm)
codeInput:SetScript("OnEnterPressed", AttemptCodeConfirm)
codeCancelBtn:SetScript("OnClick", FinishCodeAndShowNative)

codeFrame:SetScript("OnHide", function()
    if not codeDismissing and codeCurrentCode ~= "" and UnitIsDeadOrGhost("player") then
        codeCurrentCode = ""
        codeInput:SetText("")
        codeFeedback:SetText("")
        codeInput:ClearFocus()
        _dnrSuppressNext = true
        StaticPopup_Show("DEATH")
    else
        codeCurrentCode = ""
    end
end)

local function StartCodeOverlay()
    codeCurrentCode = string.format("%04d", math.random(0, 9999))
    codeDisplay:SetText(codeCurrentCode)
    codeInput:SetText("")
    codeFeedback:SetText("")
    codeFrame:Show()
    codeInput:SetFocus()
end

------------------------------------------------------------------------
-- Release Guard — TOTP overlay
------------------------------------------------------------------------
local totpFrame = CreateFrame("Frame", "ShodoQoLDNRTotpFrame", UIParent, "BasicFrameTemplate")
totpFrame:SetSize(340, 210)
totpFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
totpFrame:SetFrameStrata("DIALOG")
totpFrame:SetFrameLevel(250)
totpFrame:Hide()
totpFrame:SetMovable(true)
totpFrame:EnableMouse(true)
totpFrame:RegisterForDrag("LeftButton")
totpFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
totpFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

local totpTitle = totpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
totpTitle:SetPoint("TOP", totpFrame, "TOP", 0, -28)
totpTitle:SetText("Authenticator Required")

local totpInstr = totpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totpInstr:SetPoint("TOP", totpTitle, "BOTTOM", 0, -6)
totpInstr:SetTextColor(0.8, 0.8, 0.8, 1)
totpInstr:SetText("Enter the 6-digit code from your authenticator:")

local totpCountdown = totpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totpCountdown:SetPoint("TOP", totpInstr, "BOTTOM", 0, -4)
totpCountdown:SetTextColor(0.6, 0.6, 0.6, 1)

local totpInput = CreateFrame("EditBox", "ShodoQoLDNRTotpInput", totpFrame, "InputBoxTemplate")
totpInput:SetSize(140, 28)
totpInput:SetPoint("TOP", totpCountdown, "BOTTOM", 0, -10)
totpInput:SetMaxLetters(6)
totpInput:SetAutoFocus(false)
totpInput:SetNumeric(true)

local totpFeedback = totpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totpFeedback:SetPoint("TOP", totpInput, "BOTTOM", 0, -4)
totpFeedback:SetTextColor(1, 0.2, 0.2, 1)
totpFeedback:SetText("")

local totpConfirmBtn = CreateFrame("Button", nil, totpFrame, "UIPanelButtonTemplate")
totpConfirmBtn:SetSize(140, 26)
totpConfirmBtn:SetPoint("BOTTOMLEFT", totpFrame, "BOTTOMLEFT", 14, 14)
totpConfirmBtn:SetText("Confirm")

local totpCancelBtn = CreateFrame("Button", nil, totpFrame, "UIPanelButtonTemplate")
totpCancelBtn:SetSize(140, 26)
totpCancelBtn:SetPoint("BOTTOMRIGHT", totpFrame, "BOTTOMRIGHT", -14, 14)
totpCancelBtn:SetText("Cancel")

local totpCountdownAccum = 0
totpFrame:SetScript("OnUpdate", function(self, elapsed)
    totpCountdownAccum = totpCountdownAccum + elapsed
    if totpCountdownAccum >= 1 then
        totpCountdownAccum = 0
        if DNR_TOTP then
            totpCountdown:SetText(string.format("Code refreshes in %ds", DNR_TOTP.SecondsRemaining()))
        end
    end
end)

local totpSessionActive = false
local totpDismissing    = false

local function StopTotpInternal()
    totpDismissing = true
    totpSessionActive = false
    totpFrame:Hide()
    totpInput:SetText("")
    totpFeedback:SetText("")
    totpInput:ClearFocus()
    totpDismissing = false
end

local function FinishTotpAndShowNative()
    StopTotpInternal()
    _dnrSuppressNext = true
    StaticPopup_Show("DEATH")
end

local function AttemptTotpConfirm()
    local db = DB()
    if not DNR_TOTP or not db.totpSecret or db.totpSecret == "" then
        FinishTotpAndShowNative()
        return
    end
    if DNR_TOTP.Verify(db.totpSecret, strtrim(totpInput:GetText())) then
        FinishTotpAndShowNative()
    else
        totpFeedback:SetText("Incorrect code... try again.")
        totpInput:SetText("")
        totpInput:SetFocus()
    end
end

totpConfirmBtn:SetScript("OnClick", AttemptTotpConfirm)
totpInput:SetScript("OnEnterPressed", AttemptTotpConfirm)
totpCancelBtn:SetScript("OnClick", FinishTotpAndShowNative)

totpFrame:SetScript("OnHide", function()
    if not totpDismissing and totpSessionActive and UnitIsDeadOrGhost("player") then
        totpSessionActive = false
        totpInput:SetText("")
        totpFeedback:SetText("")
        totpInput:ClearFocus()
        _dnrSuppressNext = true
        StaticPopup_Show("DEATH")
    else
        totpSessionActive = false
    end
end)

local function StartTotpOverlay()
    totpSessionActive = true
    totpCountdownAccum = 0
    totpInput:SetText("")
    totpFeedback:SetText("")
    if DNR_TOTP then
        totpCountdown:SetText(string.format("Code refreshes in %ds", DNR_TOTP.SecondsRemaining()))
    end
    totpFrame:Show()
    totpInput:SetFocus()
end

------------------------------------------------------------------------
-- Hide all guard overlays (called on PLAYER_ALIVE / PLAYER_UNGHOST)
------------------------------------------------------------------------
local function HideGuardFrames()
    StopReleaseTimerInternal()

    codeDismissing = true
    codeCurrentCode = ""
    codeInput:SetText("")
    codeFeedback:SetText("")
    codeInput:ClearFocus()
    codeFrame:Hide()
    codeDismissing = false

    totpDismissing = true
    totpSessionActive = false
    totpInput:SetText("")
    totpFeedback:SetText("")
    totpInput:ClearFocus()
    totpFrame:Hide()
    totpDismissing = false
end

------------------------------------------------------------------------
-- Hook the native Release Spirit popup
------------------------------------------------------------------------
hooksecurefunc("StaticPopup_Show", function(which)
    if which ~= "DEATH" then return end
    if _dnrSuppressNext then
        _dnrSuppressNext = false
        return
    end
    if not ShodoQoL.IsEnabled("DoNotRelease") then return end
    local db = DB()
    if not db then return end
    local guard = db.releaseGuard or "off"
    if guard == "off" then return end
    if not UnitIsDeadOrGhost("player") then return end

    StaticPopup_Hide("DEATH")

    if guard == "timer" then
        StartReleaseTimerOverlay()
    elseif guard == "code" then
        StartCodeOverlay()
    elseif guard == "totp" then
        if DNR_TOTP and db.totpSecret and db.totpSecret ~= "" then
            StartTotpOverlay()
        else
            print("|cff33937fShodoQoL|r DoNotRelease: No TOTP secret configured. Set one up in settings.")
        end
    end
end)

------------------------------------------------------------------------
-- Settings sub-page  (ShodoQoL > DoNotRelease)
------------------------------------------------------------------------
local function BuildPanel()
    -- Canvas frame registered with Settings — never scrolls itself
    local panel = CreateFrame("Frame")
    panel.name   = "DoNotRelease"
    panel.parent = "ShodoQoL"
    panel:EnableMouse(false)
    panel:Hide()

    -- ScrollFrame fills the canvas (leave 28px on the right for the scrollbar)
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",      0,  -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28,   4)

    -- All content parented to this child; width fixed, height measured on first show
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(560)
    content:SetHeight(400)  -- placeholder; OnShow will correct it
    scrollFrame:SetScrollChild(content)

    local W  = 540
    local BH = 26
    local HW = math.floor((W - 8) / 2)

    -- ── Header ───────────────────────────────────────────────────────
    local titleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", 16, -16)
    titleFS:SetText("|cff33937fDoNot|r|cff52c4afRelease|r")

    local subFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
    subFS:SetText("|cff888888Pulsing reminder when you die in a group instance|r")

    local function Div(anchor, offY)
        local d = content:CreateTexture(nil, "ARTWORK")
        d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
        d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY)
        d:SetHeight(1)
        d:SetColorTexture(0.20, 0.58, 0.50, 0.45)
        return d
    end

    local function SecLabel(anchor, offY, text)
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY)
        fs:SetText("|cff52c4af" .. text .. "|r")
        return fs
    end

    -- ── Position ─────────────────────────────────────────────────────
    local div0   = Div(subFS, -12)
    local posHdr = SecLabel(div0, -14, "Position")

    local showBtn = ShodoQoL.CreateButton(content, "Show Warning", HW, BH)
    showBtn:SetPoint("TOPLEFT", posHdr, "BOTTOMLEFT", 0, -8)
    showBtn:SetScript("OnClick", function()
        previewMode = true
        warnFrame:Show()
    end)

    local hideBtn = ShodoQoL.CreateButton(content, "Hide Warning", HW, BH)
    hideBtn:SetPoint("LEFT", showBtn, "RIGHT", 8, 0)
    hideBtn:SetScript("OnClick", function()
        DisableDrag()
        HideWarning()
    end)

    local dragBtn = ShodoQoL.CreateButton(content, "Drag to Reposition", HW, BH)
    dragBtn:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -6)
    dragBtn:SetScript("OnClick", function()
        previewMode = true
        warnFrame:Show()
        EnableDrag()
        print("|cff33937fShodoQoL|r DoNotRelease: drag the text, release to save.")
    end)

    local resetPosBtn = ShodoQoL.CreateButton(content, "Reset Position", HW, BH)
    resetPosBtn:SetPoint("LEFT", dragBtn, "RIGHT", 8, 0)
    resetPosBtn:SetScript("OnClick", function()
        local db = DB()
        db.posX, db.posY = DNR_DEFAULTS.posX, DNR_DEFAULTS.posY
        ApplyAll()
    end)

    -- ── Color ────────────────────────────────────────────────────────
    local div1     = Div(dragBtn, -14)
    local colorHdr = SecLabel(div1, -14, "Warning Color")

    local colorAnchor = colorHdr
    for i, preset in ipairs(COLOR_PRESETS) do
        local btn = ShodoQoL.CreateButton(content, preset.label, HW, BH)
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
    local div2    = Div(colorAnchor, -14)
    local textHdr = SecLabel(div2, -14, "Warning Text")

    local nameBox = CreateFrame("EditBox", nil, content)
    nameBox:SetSize(W, BH)
    nameBox:SetPoint("TOPLEFT", textHdr, "BOTTOMLEFT", 0, -8)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject("ChatFontNormal")
    nameBox:SetTextInsets(6, 6, 0, 0)
    nameBox:SetMaxLetters(MAX_TEXT_LEN)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    do
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

    local setTextBtn = ShodoQoL.CreateButton(content, "Set Text", HW, BH)
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

    local resetTextBtn = ShodoQoL.CreateButton(content, "Reset Text", HW, BH)
    resetTextBtn:SetPoint("LEFT", setTextBtn, "RIGHT", 8, 0)
    resetTextBtn:SetScript("OnClick", function()
        local db = DB()
        db.warningText = DNR_DEFAULTS.warningText
        label:SetText(db.warningText)
        label:SetFont(db.fontFace, db.fontSize, "OUTLINE")
        nameBox:SetText(db.warningText)
    end)

    -- ── Font ─────────────────────────────────────────────────────────
    local div3    = Div(setTextBtn, -14)
    local fontHdr = SecLabel(div3, -14, "Font")

    local fontAnchor = fontHdr
    for i, preset in ipairs(FONT_PRESETS) do
        local btn = ShodoQoL.CreateButton(content, preset.label, HW, BH)
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

    -- ── Font Size slider ─────────────────────────────────────────────
    local div4    = Div(fontAnchor, -14)
    local sizeHdr = SecLabel(div4, -14, "Font Size")

    local sizeValFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeValFS:SetPoint("LEFT", sizeHdr, "RIGHT", 10, 0)
    sizeValFS:SetText("64pt")

    local minFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minFS:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 0, -38)
    minFS:SetText(FONT_SIZE_MIN .. "pt")
    minFS:SetTextColor(0.5, 0.5, 0.5)

    local maxFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxFS:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 300, -38)
    maxFS:SetText(FONT_SIZE_MAX .. "pt")
    maxFS:SetTextColor(0.5, 0.5, 0.5)

    local sizeCont = CreateFrame("Frame", nil, content)
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

    -- ── Release Guard ────────────────────────────────────────────────
    local div5     = Div(sizeCont, -18)
    local guardHdr = SecLabel(div5, -14, "Release Guard")

    local guardDescFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    guardDescFS:SetPoint("TOPLEFT", guardHdr, "BOTTOMLEFT", 0, -6)
    guardDescFS:SetWidth(W)
    guardDescFS:SetJustifyH("LEFT")
    guardDescFS:SetTextColor(0.65, 0.65, 0.65)
    guardDescFS:SetText("Intercept the Release Spirit button with a confirmation dialog or countdown timer.")

    local GUARD_MODES = {
        { mode = "off",   label = "Off"                               },
        { mode = "timer", label = "Timer (" .. RELEASE_TIMER_SECS .. "s)" },
        { mode = "code",  label = "Random Code"                       },
        { mode = "totp",  label = "Two-Factor (TOTP)"                 },
    }

    local guardBtns   = {}
    local guardAnchor = guardDescFS

    local function RefreshGuardButtons()
        local current = DB().releaseGuard or "off"
        for _, info in ipairs(guardBtns) do
            local active = info.mode == current
            if info.border then
                if active then
                    info.border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1.0)
                else
                    info.border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.70)
                end
            end
            if info.labelFS then
                if active then
                    info.labelFS:SetText("[" .. info.label .. "]")
                    info.labelFS:SetTextColor(0.33, 0.93, 0.78)
                else
                    info.labelFS:SetText(info.label)
                    info.labelFS:SetTextColor(0.90, 0.95, 0.92)
                end
            end
        end
    end

    for i, gm in ipairs(GUARD_MODES) do
        local btn = ShodoQoL.CreateButton(content, gm.label, HW, BH)
        if i % 2 == 1 then
            btn:SetPoint("TOPLEFT", guardAnchor, "BOTTOMLEFT", 0, i == 1 and -8 or -6)
            guardAnchor = btn
        else
            btn:SetPoint("LEFT", guardAnchor, "RIGHT", 8, 0)
        end

        local labelFS, borderFrame
        for j = 1, btn:GetNumRegions() do
            local r = select(j, btn:GetRegions())
            if r:GetObjectType() == "FontString" then labelFS = r end
        end
        for j = 1, btn:GetNumChildren() do
            local c = select(j, btn:GetChildren())
            if c:GetObjectType() == "Frame" then borderFrame = c end
        end

        local modeVal = gm.mode
        local function clickFn()
            DB().releaseGuard = modeVal
            if modeVal == "off" then HideGuardFrames() end
            RefreshGuardButtons()
        end
        btn:SetScript("OnClick", clickFn)

        table.insert(guardBtns, {
            btn     = btn,
            mode    = modeVal,
            label   = gm.label,
            border  = borderFrame,
            labelFS = labelFS,
            clickFn = clickFn,
        })
    end

    -- ── TOTP Setup ───────────────────────────────────────────────────
    local div6    = Div(guardAnchor, -14)
    local totpHdr = SecLabel(div6, -14, "TOTP Authenticator Setup")

    local totpDescFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totpDescFS:SetPoint("TOPLEFT", totpHdr, "BOTTOMLEFT", 0, -6)
    totpDescFS:SetWidth(W)
    totpDescFS:SetJustifyH("LEFT")
    totpDescFS:SetTextColor(0.65, 0.65, 0.65)
    totpDescFS:SetText("Pair with Google Authenticator, Authy, or any TOTP app (RFC 6238). "
        .. "Choose \"Enter setup key manually\" in your app.")

    local totpKeyLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totpKeyLabelFS:SetPoint("TOPLEFT", totpDescFS, "BOTTOMLEFT", 0, -10)
    totpKeyLabelFS:SetTextColor(0.65, 0.65, 0.65)
    totpKeyLabelFS:SetText("Your secret key (keep this private!):")

    local totpKeyDisplayFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totpKeyDisplayFS:SetPoint("TOPLEFT", totpKeyLabelFS, "BOTTOMLEFT", 0, -6)
    totpKeyDisplayFS:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    totpKeyDisplayFS:SetTextColor(1, 0.82, 0.0, 1)
    totpKeyDisplayFS:SetText("(none - click Generate below)")

    local totpRevealBtn = ShodoQoL.CreateButton(content, "Reveal", 80, BH)
    totpRevealBtn:SetPoint("LEFT", totpKeyDisplayFS, "RIGHT", 10, 0)

    local totpStep1FS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totpStep1FS:SetPoint("TOPLEFT", totpKeyDisplayFS, "BOTTOMLEFT", 0, -12)
    totpStep1FS:SetWidth(W)
    totpStep1FS:SetJustifyH("LEFT")
    totpStep1FS:SetTextColor(0.65, 0.65, 0.65)
    totpStep1FS:SetText("1. Open your authenticator app --> Add account --> Enter a setup key manually.")

    local totpStep2FS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totpStep2FS:SetPoint("TOPLEFT", totpStep1FS, "BOTTOMLEFT", 0, -6)
    totpStep2FS:SetWidth(W)
    totpStep2FS:SetJustifyH("LEFT")
    totpStep2FS:SetTextColor(0.65, 0.65, 0.65)
    totpStep2FS:SetText("2. Account name: DoNotRelease, Key type: Time-based.")

    local totpStep3FS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totpStep3FS:SetPoint("TOPLEFT", totpStep2FS, "BOTTOMLEFT", 0, -6)
    totpStep3FS:SetWidth(W)
    totpStep3FS:SetJustifyH("LEFT")
    totpStep3FS:SetTextColor(0.65, 0.65, 0.65)
    totpStep3FS:SetText("3. Enter the secret key into the app, then verify with your app's code below:")

    -- Verify row
    local totpVerifyBox = CreateFrame("EditBox", nil, content)
    totpVerifyBox:SetSize(100, BH)
    totpVerifyBox:SetPoint("TOPLEFT", totpStep3FS, "BOTTOMLEFT", 0, -8)
    totpVerifyBox:SetAutoFocus(false)
    totpVerifyBox:SetFontObject("ChatFontNormal")
    totpVerifyBox:SetTextInsets(6, 6, 0, 0)
    totpVerifyBox:SetMaxLetters(6)
    totpVerifyBox:SetNumeric(true)
    do
        local bg = totpVerifyBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
        local border = CreateFrame("Frame", nil, totpVerifyBox, "BackdropTemplate")
        border:SetAllPoints()
        border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                             insets = { left=2, right=2, top=2, bottom=2 } })
        border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7)
        border:EnableMouse(false)
        totpVerifyBox:SetScript("OnEditFocusGained", function() border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1) end)
        totpVerifyBox:SetScript("OnEditFocusLost",   function() border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7) end)
    end

    local totpVerifyBtn = ShodoQoL.CreateButton(content, "Test Code", HW, BH)
    totpVerifyBtn:SetPoint("LEFT", totpVerifyBox, "RIGHT", 8, 0)

    local totpStatusFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totpStatusFS:SetPoint("TOPLEFT", totpVerifyBox, "BOTTOMLEFT", 0, -6)
    totpStatusFS:SetText("")

    local totpGenBtn = ShodoQoL.CreateButton(content, "Generate New Secret", HW, BH)
    totpGenBtn:SetPoint("TOPLEFT", totpStatusFS, "BOTTOMLEFT", 0, -8)

    local totpWarnFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totpWarnFS:SetPoint("TOPLEFT", totpGenBtn, "BOTTOMLEFT", 0, -6)
    totpWarnFS:SetWidth(W)
    totpWarnFS:SetJustifyH("LEFT")
    totpWarnFS:SetTextColor(1, 0.55, 0.1, 1)
    totpWarnFS:SetText("(!) Regenerating invalidates any existing authenticator pairing.")

    -- TOTP helpers
    local secretVisible = false

    local function GetFormattedSecret()
        local db = DB()
        if not db.totpSecret or db.totpSecret == "" then return nil end
        if DNR_TOTP then return DNR_TOTP.FormatSecret(db.totpSecret) end
        return db.totpSecret
    end

    local function RefreshTotpSection()
        local db = DB()
        if db.totpSecret and db.totpSecret ~= "" then
            if secretVisible then
                totpKeyDisplayFS:SetText(GetFormattedSecret() or "")
                totpRevealBtn:SetText("Hide")
            else
                local fmt = GetFormattedSecret() or ""
                totpKeyDisplayFS:SetText(fmt:gsub("%S", "*"))
            end
            totpGenBtn:SetText("Regenerate Secret")
        else
            totpKeyDisplayFS:SetText("(none - click Generate below)")
            totpRevealBtn:SetText("Reveal")
            totpGenBtn:SetText("Generate New Secret")
        end
        totpStatusFS:SetText("")
        totpVerifyBox:SetText("")
    end

    totpRevealBtn:SetScript("OnClick", function()
        secretVisible = not secretVisible
        RefreshTotpSection()
    end)

    totpGenBtn:SetScript("OnClick", function()
        if not DNR_TOTP then
            print("|cff33937fShodoQoL|r DoNotRelease: DNR_TOTP library not available.")
            return
        end
        DB().totpSecret = DNR_TOTP.GenerateSecret(16)
        secretVisible = false
        RefreshTotpSection()
        print("|cff33937fShodoQoL|r DoNotRelease: New TOTP secret generated.")
    end)

    local function DoVerify()
        local db = DB()
        if not DNR_TOTP or not db.totpSecret or db.totpSecret == "" then
            totpStatusFS:SetTextColor(1, 0.2, 0.2, 1)
            totpStatusFS:SetText("Generate a secret first.")
            return
        end
        local input = strtrim(totpVerifyBox:GetText())
        if DNR_TOTP.Verify(db.totpSecret, input) then
            totpStatusFS:SetTextColor(0.2, 1, 0.2, 1)
            totpStatusFS:SetText("Code verified!")
            totpVerifyBox:SetText("")
        else
            totpStatusFS:SetTextColor(1, 0.2, 0.2, 1)
            totpStatusFS:SetText("Wrong code. Check time sync.")
            totpVerifyBox:SetText("")
        end
    end

    totpVerifyBtn:SetScript("OnClick", DoVerify)
    totpVerifyBox:SetScript("OnEnterPressed", function(self) DoVerify(); self:ClearFocus() end)
    totpVerifyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- ── Measure and set scroll child height on first show ─────────────
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

    -- ── Sync panel state on show ──────────────────────────────────────
    panel:SetScript("OnShow", function()
        local db = DB()
        nameBox:SetText(db.warningText)
        local sz = db.fontSize
        lastSize = sz
        sizeSlider:SetValue(sz)
        sizeValFS:SetText(sz .. "pt")
        RefreshGuardButtons()
        RefreshTotpSection()
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

    BuildPanel()  -- always build so user can configure from settings

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
            HideWarning()
            HideGuardFrames()
            DisableDrag()
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
