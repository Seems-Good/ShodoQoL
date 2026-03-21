-- ShodoQoL/SourceOfMagic.lua
-- Out-of-combat pulsing popup when Source of Magic is missing from your configured target.
-- Only activates when talented into Source of Magic (Augmentation Evoker).
-- Target is set via the settings panel; same cross-realm support as Spatial Paradox.

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local SOM_SPELL_ID   = 369459
local SOM_SPELL_NAME = "Source of Magic"
local CHECK_INTERVAL = 2.0   -- seconds between periodic out-of-combat checks

local SOM_DEFAULTS = {
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
}

local FONT_PRESETS = {
    { label = "Default", file = "Fonts\\FRIZQT__.TTF" },
    { label = "Clean",   file = "Fonts\\ARIALN.TTF"   },
    { label = "Fancy",   file = "Fonts\\MORPHEUS.TTF" },
    { label = "Runic",   file = "Fonts\\SKURRI.TTF"   },
}

local COLOR_PRESETS = {
    { label = "Blue",   r = 0.20, g = 0.75, b = 1.00 },
    { label = "Purple", r = 0.65, g = 0.30, b = 1.00 },
    { label = "Yellow", r = 1.00, g = 1.00, b = 0.00 },
    { label = "Orange", r = 1.00, g = 0.55, b = 0.00 },
    { label = "White",  r = 1.00, g = 1.00, b = 1.00 },
    { label = "Red",    r = 1.00, g = 0.10, b = 0.10 },
}

local FONT_SIZE_MIN = 24
local FONT_SIZE_MAX = 96

local _floor = math.floor

------------------------------------------------------------------------
-- DB accessor  (ShodoQoLDB initialised by Core before OnReady fires)
------------------------------------------------------------------------
local function DB() return ShodoQoLDB.sourceOfMagic end

------------------------------------------------------------------------
-- Talent check — true only when the player has learned Source of Magic
------------------------------------------------------------------------
local function HasSoMTalent()
    return IsPlayerSpell(SOM_SPELL_ID)
end

------------------------------------------------------------------------
-- Find a named group member's unit token (party OR raid)
------------------------------------------------------------------------
local function FindGroupToken(name, realm)
    if not name or name == "" then return nil end
    local playerRealm = GetRealmName()
    local wantRealm = (realm and realm ~= "" and realm ~= playerRealm) and realm or nil

    local function Matches(token)
        if not UnitExists(token) then return false end
        local n, r = UnitName(token)
        if n ~= name then return false end
        if wantRealm and r ~= wantRealm then return false end
        return true
    end

    if IsInRaid() then
        for i = 1, 40 do
            if Matches("raid" .. i) then return "raid" .. i end
        end
    else
        for i = 1, 4 do
            if Matches("party" .. i) then return "party" .. i end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Buff presence check — works on Dragonflight 10.x and The War Within 11.x
------------------------------------------------------------------------
local function TokenHasSoM(token)
    -- Prefer the modern struct-based API (TWW / DF 10.2+)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local data = C_UnitAuras.GetAuraDataBySpellName(token, SOM_SPELL_NAME, "HELPFUL")
        return data ~= nil
    end
    -- Fallback: iterate UnitBuff
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff(token, i)
        if not name then break end
        if spellId == SOM_SPELL_ID or name == SOM_SPELL_NAME then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Master condition — true when we should display the popup
------------------------------------------------------------------------
local function ShouldWarn()
    if UnitAffectingCombat("player") then return false end
    if not HasSoMTalent() then return false end
    local db = DB()
    if not db.targetName or db.targetName == "" then return false end  -- no target configured
    local token = FindGroupToken(db.targetName, db.targetRealm)
    if not token then return false end  -- target not in group
    return not TokenHasSoM(token)
end

------------------------------------------------------------------------
-- Warning frame
------------------------------------------------------------------------
local warnFrame = CreateFrame("Frame", "ShodoQoLSoMFrame", UIParent)
warnFrame:SetSize(800, 160)
warnFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
warnFrame:SetFrameStrata("HIGH")
warnFrame:SetFrameLevel(100)
warnFrame:EnableMouse(false)
warnFrame:Hide()

local label = warnFrame:CreateFontString(nil, "OVERLAY")
label:SetPoint("CENTER")
label:SetFont("Fonts\\FRIZQT__.TTF", 52, "OUTLINE")
label:SetTextColor(0.20, 0.75, 1.00, 1)
label:SetShadowColor(0.50, 0.10, 1.00, 1)
label:SetShadowOffset(0, 0)
label:SetText("SOURCE OF MAGIC MISSING")

------------------------------------------------------------------------
-- Pulse  (alpha only; OnUpdate fires only while frame is shown)
------------------------------------------------------------------------
local PULSE_PERIOD = 1.5
local ALPHA_MIN    = 0.30
local ALPHA_MAX    = 1.00
local ALPHA_MID    = (ALPHA_MAX + ALPHA_MIN) / 2
local ALPHA_AMP    = (ALPHA_MAX - ALPHA_MIN) / 2
local PHASE_OFFSET = math.pi / 2
local pulseTime    = 0
local previewMode  = false

local function onUpdate(self, elapsed)
    if not previewMode and not ShouldWarn() then
        HideSoMWarning()
        return
    end
    pulseTime = (pulseTime + elapsed) % PULSE_PERIOD
    self:SetAlpha(ALPHA_MID + ALPHA_AMP * math.sin(
        pulseTime * (math.pi * 2) / PULSE_PERIOD + PHASE_OFFSET))
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
-- Apply DB → frame
------------------------------------------------------------------------
local function ApplyAll()
    local db = DB()
    warnFrame:ClearAllPoints()
    warnFrame:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
    label:SetTextColor(db.colorR, db.colorG, db.colorB, 1)
    label:SetText(db.warningText ~= "" and db.warningText or SOM_DEFAULTS.warningText)
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
function ShowSoMWarning()
    if ShouldWarn() or previewMode then warnFrame:Show() end
end

function HideSoMWarning()
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
        print("|cff33937fShodoQoL|r Source of Magic: position saved.")
    end)
end

local function DisableDrag()
    warnFrame:SetMovable(false)
    warnFrame:EnableMouse(false)
    warnFrame:SetScript("OnDragStart", nil)
    warnFrame:SetScript("OnDragStop", nil)
end

------------------------------------------------------------------------
-- Periodic check + event-driven updates
------------------------------------------------------------------------
local ticker = nil

local function DoCheck()
    if ShouldWarn() then
        if not warnFrame:IsShown() then ShowSoMWarning() end
    else
        if warnFrame:IsShown() and not previewMode then HideSoMWarning() end
    end
end

local function StartTicker()
    if ticker then return end
    if UnitAffectingCombat("player") then return end
    ticker = C_Timer.NewTicker(CHECK_INTERVAL, DoCheck)
    DoCheck()  -- immediate check on start
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

------------------------------------------------------------------------
-- Settings sub-page  (ShodoQoL > Source of Magic)
------------------------------------------------------------------------
local function CreateCleanEditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetMaxLetters(64)

    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)

    local border = CreateFrame("Frame", nil, eb, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7)
    border:EnableMouse(false)

    eb:SetScript("OnEditFocusGained", function() border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1) end)
    eb:SetScript("OnEditFocusLost",   function() border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)

    return eb
end

local function BuildPanel()
    local panel = CreateFrame("Frame")
    panel.name   = "SourceOfMagic"
    panel.parent = "ShodoQoL"
    panel:EnableMouse(false)
    panel:Hide()

    -- ── ScrollFrame fills the canvas; scrollbar on the right ─────────
    local scrollFrame = CreateFrame("ScrollFrame", "ShodoQoLSoMScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",     4,  -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 580)
    content:SetHeight(960)    -- tall enough for all sections; scroll handles the rest
    scrollFrame:SetScrollChild(content)

    -- keep content width in sync if panel is ever resized
    scrollFrame:SetScript("OnSizeChanged", function(self)
        content:SetWidth(self:GetWidth())
    end)

    local W  = 560
    local BH = 26
    local HW = math.floor((W - 8) / 2)

    -- ── Header ───────────────────────────────────────────────────────
    local titleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", 16, -16)
    titleFS:SetText("|cff33937fSource|r|cff52c4afOfMagic|r")

    local subFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
    subFS:SetText("|cff888888Out-of-combat reminder when Source of Magic isn't on your target|r")

    local function Div(anchor, offY)
        local d = content:CreateTexture(nil, "ARTWORK")
        d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
        d:SetSize(W, 1)
        d:SetColorTexture(0.20, 0.58, 0.50, 0.45)
        return d
    end

    local function SecLabel(anchor, offY, text)
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY)
        fs:SetText("|cff52c4af" .. text .. "|r")
        return fs
    end

    -- ── Target ───────────────────────────────────────────────────────
    local div0   = Div(subFS, -12)
    local tgtHdr = SecLabel(div0, -14, "Target")

    local currentLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentLabelFS:SetPoint("TOPLEFT", tgtHdr, "BOTTOMLEFT", 0, -10)
    currentLabelFS:SetText("Current target:")
    currentLabelFS:SetTextColor(0.70, 0.70, 0.70)

    local currentValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    currentValueFS:SetPoint("LEFT", currentLabelFS, "RIGHT", 8, 0)
    currentValueFS:SetText("|cff888888(none set)|r")

    local function RefreshCurrentLabel()
        local db = DB()
        if not db.targetName or db.targetName == "" then
            currentValueFS:SetText("|cff888888(none set)|r")
            return
        end
        local playerRealm = GetRealmName()
        if db.targetRealm and db.targetRealm ~= "" and db.targetRealm ~= playerRealm then
            currentValueFS:SetText(string.format("|cffffd100%s|r |cff888888(%s)|r",
                db.targetName, db.targetRealm))
        else
            currentValueFS:SetText(string.format("|cffffd100%s|r", db.targetName))
        end
    end

    local useTargetBtn = ShodoQoL.CreateButton(content, "Use Current Target", HW, BH)
    useTargetBtn:SetPoint("TOPLEFT", currentLabelFS, "BOTTOMLEFT", 0, -8)
    useTargetBtn:SetScript("OnClick", function()
        if not UnitExists("target") then
            print("|cffff6060ShodoQoL|r SoM: No target selected."); return
        end
        if UnitIsUnit("target", "player") then
            print("|cffff6060ShodoQoL|r SoM: Can't target yourself."); return
        end
        if not UnitIsPlayer("target") then
            print("|cffff6060ShodoQoL|r SoM: Target is not a player."); return
        end
        local name, realm = UnitName("target")
        if not name then
            print("|cffff6060ShodoQoL|r SoM: Could not read target name."); return
        end
        local db = DB()
        db.targetName  = name
        db.targetRealm = realm or ""
        RefreshCurrentLabel()
        local display = (realm and realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r SoM: Target set to |cffffd100%s|r.", display))
        DoCheck()
    end)

    local clearTargetBtn = ShodoQoL.CreateButton(content, "Clear Target", HW, BH)
    clearTargetBtn:SetPoint("LEFT", useTargetBtn, "RIGHT", 8, 0)
    clearTargetBtn:SetScript("OnClick", function()
        local db = DB()
        db.targetName, db.targetRealm = nil, nil
        RefreshCurrentLabel()
        HideSoMWarning()
        print("|cff33937fShodoQoL|r SoM: Target cleared.")
    end)

    -- Manual name/realm entry
    local nameLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabelFS:SetPoint("TOPLEFT", useTargetBtn, "BOTTOMLEFT", 0, -12)
    nameLabelFS:SetText("Character Name")
    nameLabelFS:SetTextColor(0.62, 0.88, 0.82)

    local nameBox = CreateCleanEditBox(content, 220)
    nameBox:SetPoint("TOPLEFT", nameLabelFS, "BOTTOMLEFT", 0, -4)
    nameBox:SetMaxLetters(48)

    local realmLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    realmLabelFS:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -10)
    realmLabelFS:SetText("Realm  |cff888888(leave blank if same realm)|r")
    realmLabelFS:SetTextColor(0.62, 0.88, 0.82)

    local realmBox = CreateCleanEditBox(content, 220)
    realmBox:SetPoint("TOPLEFT", realmLabelFS, "BOTTOMLEFT", 0, -4)

    local applyBtn = ShodoQoL.CreateButton(content, "Apply", 80, BH)
    applyBtn:SetPoint("TOPLEFT", realmBox, "BOTTOMLEFT", 0, -10)
    applyBtn:SetScript("OnClick", function()
        local name  = nameBox:GetText():match("^%s*(.-)%s*$")
        local realm = realmBox:GetText():match("^%s*(.-)%s*$")
        if not name or name == "" then
            print("|cffff6060ShodoQoL|r SoM: Please enter a character name."); return
        end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        local db = DB()
        db.targetName  = name
        db.targetRealm = realm
        RefreshCurrentLabel()
        local display = (realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r SoM: Target set to |cffffd100%s|r.", display))
        DoCheck()
    end)

    local clearManualBtn = ShodoQoL.CreateButton(content, "Clear Target", 110, BH)
    clearManualBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    clearManualBtn:SetScript("OnClick", function()
        local db = DB()
        db.targetName, db.targetRealm = nil, nil
        nameBox:SetText("")
        realmBox:SetText("")
        RefreshCurrentLabel()
        HideSoMWarning()
        print("|cff33937fShodoQoL|r SoM: Target cleared.")
    end)

    -- ── Position ─────────────────────────────────────────────────────
    local div1   = Div(applyBtn, -18)
    local posHdr = SecLabel(div1, -14, "Position")

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
        HideSoMWarning()
    end)

    local dragBtn = ShodoQoL.CreateButton(content, "Drag to Reposition", HW, BH)
    dragBtn:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -6)
    dragBtn:SetScript("OnClick", function()
        previewMode = true
        warnFrame:Show()
        EnableDrag()
        print("|cff33937fShodoQoL|r SoM: drag the text, release to save.")
    end)

    local resetPosBtn = ShodoQoL.CreateButton(content, "Reset Position", HW, BH)
    resetPosBtn:SetPoint("LEFT", dragBtn, "RIGHT", 8, 0)
    resetPosBtn:SetScript("OnClick", function()
        local db = DB()
        db.posX, db.posY = SOM_DEFAULTS.posX, SOM_DEFAULTS.posY
        ApplyAll()
    end)

    -- ── Color ────────────────────────────────────────────────────────
    local div2     = Div(dragBtn, -14)
    local colorHdr = SecLabel(div2, -14, "Warning Color")

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
    local div3    = Div(colorAnchor, -14)
    local textHdr = SecLabel(div3, -14, "Warning Text")

    local nameBoxWarn = CreateFrame("EditBox", nil, content)
    nameBoxWarn:SetSize(W, BH)
    nameBoxWarn:SetPoint("TOPLEFT", textHdr, "BOTTOMLEFT", 0, -8)
    nameBoxWarn:SetAutoFocus(false)
    nameBoxWarn:SetFontObject("ChatFontNormal")
    nameBoxWarn:SetTextInsets(6, 6, 0, 0)
    nameBoxWarn:SetMaxLetters(48)
    nameBoxWarn:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBoxWarn:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    do
        local bg = nameBoxWarn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
        local border = CreateFrame("Frame", nil, nameBoxWarn, "BackdropTemplate")
        border:SetAllPoints()
        border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                             insets = { left=2, right=2, top=2, bottom=2 } })
        border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7)
        border:EnableMouse(false)
        nameBoxWarn:SetScript("OnEditFocusGained", function() border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1) end)
        nameBoxWarn:SetScript("OnEditFocusLost",   function() border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7) end)
    end

    local setTextBtn = ShodoQoL.CreateButton(content, "Set Text", HW, BH)
    setTextBtn:SetPoint("TOPLEFT", nameBoxWarn, "BOTTOMLEFT", 0, -6)
    setTextBtn:SetScript("OnClick", function()
        local raw = strtrim(nameBoxWarn:GetText())
        if raw == "" then
            print("|cffff6060ShodoQoL|r SoM: text cannot be empty."); return
        end
        local db = DB()
        db.warningText = raw
        label:SetText(raw)
        label:SetFont(db.fontFace, db.fontSize, "OUTLINE")
        nameBoxWarn:ClearFocus()
    end)

    local resetTextBtn = ShodoQoL.CreateButton(content, "Reset Text", HW, BH)
    resetTextBtn:SetPoint("LEFT", setTextBtn, "RIGHT", 8, 0)
    resetTextBtn:SetScript("OnClick", function()
        local db = DB()
        db.warningText = SOM_DEFAULTS.warningText
        label:SetText(db.warningText)
        label:SetFont(db.fontFace, db.fontSize, "OUTLINE")
        nameBoxWarn:SetText(db.warningText)
    end)

    -- ── Font ─────────────────────────────────────────────────────────
    local div4       = Div(setTextBtn, -14)
    local fontHdr    = SecLabel(div4, -14, "Font")
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
    local div5    = Div(fontAnchor, -14)
    local sizeHdr = SecLabel(div5, -14, "Font Size")

    local sizeValFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeValFS:SetPoint("LEFT", sizeHdr, "RIGHT", 10, 0)
    sizeValFS:SetText("52pt")

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

    local sizeSlider = CreateFrame("Slider", "ShodoQoLSoMSizeSlider", sizeCont)
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

    local lastSize = SOM_DEFAULTS.fontSize
    sizeSlider:SetScript("OnValueChanged", function(self, val)
        local size = _floor(val + 0.5)
        sizeValFS:SetText(size .. "pt")
        if size == lastSize then return end
        lastSize = size
        local db = DB()
        db.fontSize = size
        label:SetFont(db.fontFace, size, "OUTLINE")
    end)

    -- Sync panel state on show; also reset scroll to top
    panel:SetScript("OnShow", function()
        scrollFrame:SetVerticalScroll(0)
        local db = DB()
        nameBox:SetText(db.targetName or "")
        realmBox:SetText(db.targetRealm or "")
        nameBoxWarn:SetText(db.warningText)
        local sz = db.fontSize
        lastSize = sz
        sizeSlider:SetValue(sz)
        sizeValFS:SetText(sz .. "pt")
        RefreshCurrentLabel()
    end)

    if SettingsPanel then
        SettingsPanel:HookScript("OnHide", function()
            DisableDrag()
            if not ShouldWarn() then HideSoMWarning() end
        end)
    end

    local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "SourceOfMagic")
    Settings.RegisterAddOnCategory(subCat)
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_SHODO_SOM1 = "/som"
SlashCmdList["SHODO_SOM"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "test" then
        previewMode = true
        warnFrame:Show()
        print("|cff33937fShodoQoL|r SoM: preview shown.")
        C_Timer.After(10, function()
            if not ShouldWarn() then HideSoMWarning() end
        end)
    elseif cmd == "hide" then
        HideSoMWarning()
    elseif cmd == "check" then
        print(string.format(
            "|cff33937fShodoQoL|r SoM: talented=%s  combat=%s  shouldWarn=%s",
            tostring(HasSoMTalent()),
            tostring(UnitAffectingCombat("player")),
            tostring(ShouldWarn())
        ))
    else
        print("|cff33937fShodoQoL|r SoM: |cffffd100/som test|r  |  |cffffd100/som hide|r  |  |cffffd100/som check|r")
    end
end

------------------------------------------------------------------------
-- Hook into Core bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    -- Back-fill defaults
    local db = ShodoQoLDB.sourceOfMagic
    for k, v in pairs(SOM_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end

    BuildPanel()  -- always build so user can configure even if disabled

    if not ShodoQoL.IsEnabled("SourceOfMagic") then return end

    ApplyAll()

    -- Event frame
    local evtFrame = CreateFrame("Frame")
    evtFrame:EnableMouse(false)
    evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")    -- entered combat
    evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")     -- left combat
    evtFrame:RegisterEvent("UNIT_AURA")                -- buff changed
    evtFrame:RegisterEvent("GROUP_ROSTER_UPDATE")      -- group changed
    evtFrame:RegisterEvent("PLAYER_TALENT_UPDATE")     -- talents changed
    evtFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")  -- spec swapped
    evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    local rosterPending = false

    evtFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Entered combat: stop checking and hide
            StopTicker()
            if not previewMode then HideSoMWarning() end

        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Left combat: start periodic check
            StartTicker()

        elseif event == "UNIT_AURA" then
            -- Only react if the aura change is on a unit in our group
            local unit = ...
            if not unit then return end
            -- Quick heuristic: if not in combat and aura changed on a party/raid member
            if not UnitAffectingCombat("player") then
                DoCheck()
            end

        elseif event == "GROUP_ROSTER_UPDATE" then
            if rosterPending then return end
            rosterPending = true
            C_Timer.After(0.25, function()
                rosterPending = false
                DoCheck()
            end)

        elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
            -- Talent or spec changed — re-evaluate everything
            C_Timer.After(0.5, function()
                if not HasSoMTalent() then
                    StopTicker()
                    HideSoMWarning()
                else
                    if not UnitAffectingCombat("player") then
                        StartTicker()
                    end
                end
            end)

        elseif event == "PLAYER_ENTERING_WORLD" then
            StopTicker()
            HideSoMWarning()
            C_Timer.After(1.0, function()
                if not UnitAffectingCombat("player") and HasSoMTalent() then
                    StartTicker()
                end
            end)
        end
    end)

    -- Initial state
    if not UnitAffectingCombat("player") and HasSoMTalent() then
        StartTicker()
    end
end)
