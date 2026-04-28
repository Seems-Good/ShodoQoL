-- ShodoQoL/SourceOfMagic.lua
-- Out-of-combat pulsing popup when Source of Magic is missing from your configured target.
-- Only activates when talented into Source of Magic (Augmentation Evoker).
--
-- Event architecture for near-zero raid CPU:
--   * UNIT_AURA only registered when hasSoMTalent=true AND inCombat=false.
--     Immediately unregistered on PLAYER_REGEN_DISABLED.
--   * UNIT_AURA is a unit-scoped event on the resolved target token only.
--     Zero cost for other 19 raid members' buff changes.
--   * No periodic ticker. No FindGroupToken on any hot path.
--   * OnUpdate is a pure alpha pulse -- zero game-state reads.

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local SOM_SPELL_ID   = 369459
local SOM_SPELL_NAME = "Source of Magic"
local AUG_SPEC_ID    = 1467   -- Augmentation Evoker spec ID

local SOM_DEFAULTS = {
    posX        = 0,
    posY        = 80,
    colorR      = 0.20,
    colorG      = 0.75,
    colorB      = 1.00,
    fontSize    = 52,
    targetName  = nil,
    targetRealm = nil,
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
-- DB accessor
------------------------------------------------------------------------
local function DB() return ShodoQoLDB.sourceOfMagic end

------------------------------------------------------------------------
-- Runtime state
------------------------------------------------------------------------
local State = {
    hasSoMTalent = false,
    isAugEvoker  = false,
    inCombat     = false,
    targetToken  = nil,   -- cached resolved token, e.g. "raid5" -- never resolved on hot path
}

------------------------------------------------------------------------
-- Spec / talent checks
------------------------------------------------------------------------
local function UpdateSpec()
    local idx = GetSpecialization()
    if not idx then State.isAugEvoker = false; return end
    local specID = GetSpecializationInfo(idx)
    State.isAugEvoker = (specID == AUG_SPEC_ID)
end

local function UpdateTalent()
    if not State.isAugEvoker then State.hasSoMTalent = false; return end
    State.hasSoMTalent = IsPlayerSpell(SOM_SPELL_ID)
end

------------------------------------------------------------------------
-- FindGroupToken -- called ONLY when roster or target changes,
-- never on the UNIT_AURA hot path.
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
-- Resolve and cache the target token.
-- Called after roster changes or after the target name changes.
------------------------------------------------------------------------
local function ResolveTargetToken()
    local db = DB()
    if not db.targetName or db.targetName == "" then
        State.targetToken = nil
    else
        State.targetToken = FindGroupToken(db.targetName, db.targetRealm)
    end
end

------------------------------------------------------------------------
-- Buff check -- only called by DoCheck(), never from UNIT_AURA handler
------------------------------------------------------------------------
local function TokenHasSoM(token)
    if not token or not UnitExists(token) then return false end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        return C_UnitAuras.GetAuraDataBySpellName(token, SOM_SPELL_NAME, "HELPFUL") ~= nil
    end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff(token, i)
        if not name then break end
        if spellId == SOM_SPELL_ID or name == SOM_SPELL_NAME then return true end
    end
    return false
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
label:SetShadowOffset(0, 0)
label:SetText("SOURCE OF MAGIC MISSING")

------------------------------------------------------------------------
-- Pulse -- pure alpha math; zero game-state reads per frame
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
-- Apply DB to live frame
------------------------------------------------------------------------
local function ApplyAll()
    local db = DB()
    warnFrame:ClearAllPoints()
    warnFrame:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
    label:SetTextColor(db.colorR, db.colorG, db.colorB, 1)
    label:SetText("SOURCE OF MAGIC MISSING")
    label:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
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
local function ShowSoMWarning() warnFrame:Show() end

function HideSoMWarning()
    previewMode = false
    warnFrame:Hide()
end

local function EnableDrag()
    warnFrame:SetMovable(true)
    warnFrame:EnableMouse(true)
    warnFrame:RegisterForDrag("LeftButton")
    warnFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    warnFrame:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        SavePosition()
        print("|cff33937fShodoQoL|r SoM: position saved.")
    end)
end

local function DisableDrag()
    warnFrame:SetMovable(false)
    warnFrame:EnableMouse(false)
    warnFrame:SetScript("OnDragStart", nil)
    warnFrame:SetScript("OnDragStop",  nil)
end

------------------------------------------------------------------------
-- DoCheck -- the only place the warning decision is made
------------------------------------------------------------------------
local function DoCheck()
    if not State.hasSoMTalent or State.inCombat or not State.targetToken then
        if warnFrame:IsShown() and not previewMode then HideSoMWarning() end
        return
    end
    if not UnitExists(State.targetToken) then
        if warnFrame:IsShown() and not previewMode then HideSoMWarning() end
        return
    end
    if TokenHasSoM(State.targetToken) then
        if warnFrame:IsShown() and not previewMode then HideSoMWarning() end
    else
        if not warnFrame:IsShown() then ShowSoMWarning() end
    end
end

------------------------------------------------------------------------
-- Dynamic event gating -- mirrors BSA's SetWatchedEvents()
-- UNIT_AURA is only registered when:
--   (a) player has SoM talented, AND
--   (b) player is out of combat, AND
--   (c) a target token is resolved
-- It is registered as RegisterUnitEvent on the exact token so it only
-- fires when that one player's auras change, not for all 20 raid members.
------------------------------------------------------------------------
local evtFrame               -- assigned in OnReady
local registeredAuraToken = nil

local function SetWatchedEvents()
    if not evtFrame then return end

    local wantToken = (State.hasSoMTalent and not State.inCombat) and State.targetToken or nil

    -- Unregister old unit event if token changed or event no longer wanted
    if registeredAuraToken and registeredAuraToken ~= wantToken then
        evtFrame:UnregisterUnitEvent("UNIT_AURA", registeredAuraToken)
        registeredAuraToken = nil
    end

    -- Register on new token
    if wantToken and not registeredAuraToken then
        evtFrame:RegisterUnitEvent("UNIT_AURA", wantToken)
        registeredAuraToken = wantToken
    end

    -- Talent update event only useful when Aug-talented
    if State.hasSoMTalent then
        evtFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    else
        evtFrame:UnregisterEvent("TRAIT_CONFIG_UPDATED")
    end
end

-- Public hook: called by MacroHelpers and the settings panel when SoM target changes
function ShodoQoL.NotifySoMTargetChanged()
    ResolveTargetToken()
    SetWatchedEvents()
    DoCheck()
end

------------------------------------------------------------------------
-- Settings panel
------------------------------------------------------------------------
local function CreateCleanEditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetMaxLetters(64)
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
    local border = CreateFrame("Frame", nil, eb, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                         insets = { left=2, right=2, top=2, bottom=2 } })
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

    local scrollFrame = CreateFrame("ScrollFrame", "ShodoQoLSoMScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",      4,  -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26,  4)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 580)
    content:SetHeight(800)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)

    local W  = 560
    local BH = 26
    local HW = math.floor((W - 8) / 2)

    local titleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", 16, -16)
    titleFS:SetText("|cff33937fSource|r|cff52c4afOfMagic|r")

    local subFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
    subFS:SetText("|cff888888Out-of-combat reminder when Source of Magic is missing from your target|r")

    local function Div(anchor, offY)
        local d = content:CreateTexture(nil, "ARTWORK")
        d:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY)
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

    -- Target section
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
            currentValueFS:SetText("|cff888888(none set)|r"); return
        end
        local playerRealm = GetRealmName()
        if db.targetRealm and db.targetRealm ~= "" and db.targetRealm ~= playerRealm then
            currentValueFS:SetText(string.format("|cffffd100%s|r |cff888888(%s)|r", db.targetName, db.targetRealm))
        else
            currentValueFS:SetText(string.format("|cffffd100%s|r", db.targetName))
        end
    end

    local useTargetBtn = ShodoQoL.CreateButton(content, "Use Current Target", HW, BH)
    useTargetBtn:SetPoint("TOPLEFT", currentLabelFS, "BOTTOMLEFT", 0, -8)
    useTargetBtn:SetScript("OnClick", function()
        if not UnitExists("target")       then print("|cffff6060ShodoQoL|r SoM: No target selected."); return end
        if UnitIsUnit("target","player")  then print("|cffff6060ShodoQoL|r SoM: Can't target yourself."); return end
        if not UnitIsPlayer("target")     then print("|cffff6060ShodoQoL|r SoM: Target is not a player."); return end
        local name, realm = UnitName("target")
        if not name then print("|cffff6060ShodoQoL|r SoM: Could not read target name."); return end
        local db = DB()
        db.targetName  = name
        db.targetRealm = realm or ""
        RefreshCurrentLabel()
        ShodoQoL.NotifySoMTargetChanged()
        local display = (realm and realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r SoM: Target set to |cffffd100%s|r.", display))
    end)

    local clearTargetBtn = ShodoQoL.CreateButton(content, "Clear Target", HW, BH)
    clearTargetBtn:SetPoint("LEFT", useTargetBtn, "RIGHT", 8, 0)
    clearTargetBtn:SetScript("OnClick", function()
        local db = DB()
        db.targetName, db.targetRealm = nil, nil
        RefreshCurrentLabel()
        ShodoQoL.NotifySoMTargetChanged()
        print("|cff33937fShodoQoL|r SoM: Target cleared.")
    end)

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
        if not name or name == "" then print("|cffff6060ShodoQoL|r SoM: Please enter a name."); return end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        local db = DB()
        db.targetName  = name
        db.targetRealm = realm
        RefreshCurrentLabel()
        ShodoQoL.NotifySoMTargetChanged()
        local display = (realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r SoM: Target set to |cffffd100%s|r.", display))
    end)

    local clearManualBtn = ShodoQoL.CreateButton(content, "Clear Target", 110, BH)
    clearManualBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    clearManualBtn:SetScript("OnClick", function()
        local db = DB()
        db.targetName, db.targetRealm = nil, nil
        nameBox:SetText(""); realmBox:SetText("")
        RefreshCurrentLabel()
        ShodoQoL.NotifySoMTargetChanged()
        print("|cff33937fShodoQoL|r SoM: Target cleared.")
    end)

    -- Position section
    local div1   = Div(applyBtn, -18)
    local posHdr = SecLabel(div1, -14, "Position")

    local showBtn = ShodoQoL.CreateButton(content, "Show Warning", HW, BH)
    showBtn:SetPoint("TOPLEFT", posHdr, "BOTTOMLEFT", 0, -8)
    showBtn:SetScript("OnClick", function() previewMode = true; warnFrame:Show() end)

    local hideBtn = ShodoQoL.CreateButton(content, "Hide Warning", HW, BH)
    hideBtn:SetPoint("LEFT", showBtn, "RIGHT", 8, 0)
    hideBtn:SetScript("OnClick", function() DisableDrag(); HideSoMWarning() end)

    local dragBtn = ShodoQoL.CreateButton(content, "Drag to Reposition", HW, BH)
    dragBtn:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -6)
    dragBtn:SetScript("OnClick", function()
        previewMode = true; warnFrame:Show(); EnableDrag()
        print("|cff33937fShodoQoL|r SoM: drag the text, release to save.")
    end)

    local resetPosBtn = ShodoQoL.CreateButton(content, "Reset Position", HW, BH)
    resetPosBtn:SetPoint("LEFT", dragBtn, "RIGHT", 8, 0)
    resetPosBtn:SetScript("OnClick", function()
        local db = DB(); db.posX, db.posY = SOM_DEFAULTS.posX, SOM_DEFAULTS.posY; ApplyAll()
    end)

    -- Color section
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
            local db = DB(); db.colorR, db.colorG, db.colorB = r, g, b
            label:SetTextColor(r, g, b, 1)
        end)
    end

    -- Font Size slider (anchored directly below color buttons; Warning Text section removed)
    local div4    = Div(colorAnchor, -14)
    local sizeHdr = SecLabel(div4, -14, "Font Size")

    local sizeValFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeValFS:SetPoint("LEFT", sizeHdr, "RIGHT", 10, 0)
    sizeValFS:SetText("52pt")

    local minFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minFS:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 0, -38)
    minFS:SetText(FONT_SIZE_MIN .. "pt"); minFS:SetTextColor(0.5, 0.5, 0.5)

    local maxFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxFS:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 300, -38)
    maxFS:SetText(FONT_SIZE_MAX .. "pt"); maxFS:SetTextColor(0.5, 0.5, 0.5)

    local sizeCont = CreateFrame("Frame", nil, content)
    sizeCont:SetSize(320, 36)
    sizeCont:SetPoint("TOPLEFT", sizeHdr, "BOTTOMLEFT", 0, -18)
    sizeCont:EnableMouse(false)

    local track = sizeCont:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 10, 0); track:SetPoint("RIGHT", -10, 0)
    track:SetHeight(6); track:SetColorTexture(0.06, 0.18, 0.16, 0.90)

    local sizeSlider = CreateFrame("Slider", "ShodoQoLSoMSizeSlider", sizeCont)
    sizeSlider:SetAllPoints(); sizeSlider:EnableMouse(true)
    sizeSlider:SetOrientation("HORIZONTAL")
    sizeSlider:SetMinMaxValues(FONT_SIZE_MIN, FONT_SIZE_MAX)
    sizeSlider:SetValueStep(2); sizeSlider:SetObeyStepOnDrag(true)

    local thumb = sizeSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 22); thumb:SetColorTexture(0.25, 0.78, 0.66, 1)
    sizeSlider:SetThumbTexture(thumb)

    local lastSize = SOM_DEFAULTS.fontSize
    sizeSlider:SetScript("OnValueChanged", function(self, val)
        local size = _floor(val + 0.5)
        sizeValFS:SetText(size .. "pt")
        if size == lastSize then return end
        lastSize = size
        local db = DB(); db.fontSize = size
        label:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end)

    panel:SetScript("OnShow", function()
        scrollFrame:SetVerticalScroll(0)
        local db = DB()
        nameBox:SetText(db.targetName or "")
        realmBox:SetText(db.targetRealm or "")
        local sz = db.fontSize; lastSize = sz
        sizeSlider:SetValue(sz); sizeValFS:SetText(sz .. "pt")
        RefreshCurrentLabel()
    end)

    if SettingsPanel then
        SettingsPanel:HookScript("OnHide", function()
            DisableDrag()
            if previewMode then HideSoMWarning() end
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
        previewMode = true; warnFrame:Show()
        print("|cff33937fShodoQoL|r SoM: preview shown.")
        C_Timer.After(10, function() if previewMode then HideSoMWarning() end end)
    elseif cmd == "hide" then
        HideSoMWarning()
    elseif cmd == "check" then
        print(string.format(
            "|cff33937fShodoQoL|r SoM: aug=%s  talented=%s  combat=%s  token=%s  auraReg=%s",
            tostring(State.isAugEvoker), tostring(State.hasSoMTalent),
            tostring(State.inCombat), tostring(State.targetToken),
            tostring(registeredAuraToken)))
    else
        print("|cff33937fShodoQoL|r SoM: |cffffd100/som test|r  |  |cffffd100/som hide|r  |  |cffffd100/som check|r")
    end
end

------------------------------------------------------------------------
-- Hook into Core bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    local db = ShodoQoLDB.sourceOfMagic
    for k, v in pairs(SOM_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end

    BuildPanel()
    if not ShodoQoL.IsEnabled("SourceOfMagic") then return end

    ApplyAll()

    evtFrame = CreateFrame("Frame")
    evtFrame:EnableMouse(false)

    -- Low-frequency, always-on events
    evtFrame:RegisterEvent("PLAYER_LOGIN")
    evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    evtFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    evtFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    -- UNIT_AURA and TRAIT_CONFIG_UPDATED are dynamically gated via SetWatchedEvents()

    evtFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            State.inCombat = UnitAffectingCombat("player") and true or false
            UpdateSpec(); UpdateTalent(); ResolveTargetToken()
            SetWatchedEvents(); DoCheck()

        elseif event == "PLAYER_REGEN_DISABLED" then
            State.inCombat = true
            SetWatchedEvents()   -- immediately unregisters UNIT_AURA
            if not previewMode then HideSoMWarning() end

        elseif event == "PLAYER_REGEN_ENABLED" then
            State.inCombat = false
            SetWatchedEvents()   -- re-registers UNIT_AURA if appropriate
            DoCheck()

        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            UpdateSpec(); UpdateTalent()
            SetWatchedEvents(); DoCheck()

        elseif event == "TRAIT_CONFIG_UPDATED" then
            -- Only reaches here when hasSoMTalent=true (gated by SetWatchedEvents)
            -- Filter to class talent tree; ignore profession tree commits
            local activeID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
            if activeID and arg1 ~= activeID then return end
            UpdateTalent(); SetWatchedEvents(); DoCheck()

        elseif event == "GROUP_ROSTER_UPDATE" then
            -- Token can shift when roster changes (e.g. someone leaves, slots renumber)
            ResolveTargetToken()
            SetWatchedEvents()   -- token changed, re-register unit event
            DoCheck()

        elseif event == "UNIT_AURA" then
            -- Reaches here ONLY when:
            --   hasSoMTalent=true, inCombat=false, registered on State.targetToken
            -- The arg1==State.targetToken is guaranteed by RegisterUnitEvent scope.
            DoCheck()
        end
    end)

    -- Initial bootstrap
    State.inCombat = UnitAffectingCombat("player") and true or false
    UpdateSpec(); UpdateTalent(); ResolveTargetToken()
    SetWatchedEvents(); DoCheck()
end)
