-- ShodoQoL/EssenceMover.lua
-- Moves and scales the Evoker Essence bar.
-- Optional "Modern Look": replaces it with a rectangular green bar.
-- Reads/writes ShodoQoLDB.essenceMover:
--   x, y, scale, modernLook, bgOpacity, barAlpha, modernScaleW, modernScaleH
--
-- Performance notes
-- -----------------
-- Zero C_Timer.NewTicker usage.  Charging pip animation runs via WoW's
-- AnimationGroup system (GPU-side, zero Lua ticks).  Power updates fire
-- only from UNIT_POWER_UPDATE (integer changes only — not sub-pip churn).
-- EssencePlayerFrame has its mouse disabled while the modern bar is active
-- so its tooltip no longer ghosts at the original position under the
-- character frame.

------------------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------------------
local ApplyModernBarSize   -- forward declaration
local modernBar      = nil
local modernEventFrm = nil
local specListener

------------------------------------------------------------------------
-- Defaults (also defined in your DB init; these are fallback guards)
------------------------------------------------------------------------
local DEFAULT_BG_OPACITY    = 0.90
local DEFAULT_CORNER_RADIUS = 4
local DEFAULT_BAR_ALPHA     = 1.00
local DEFAULT_MODERN_SCALE_W = 1.0
local DEFAULT_MODERN_SCALE_H = 1.0

------------------------------------------------------------------------
-- ApplyPosition
------------------------------------------------------------------------
local function ApplyPosition()
    local db = ShodoQoLDB.essenceMover

    if modernBar then
        ApplyModernBarSize()   -- uses SetSize(W*scaleW, H*scaleH) — no SetScale in modern mode
        if db.x and db.y then
            modernBar:ClearAllPoints()
            modernBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
        end
        -- Keep original invisible AND non-interactive — critical fix for the
        -- tooltip-at-character-frame bug (SetAlpha alone doesn't stop hover).
        if EssencePlayerFrame then
            EssencePlayerFrame:SetAlpha(0)
            EssencePlayerFrame:EnableMouse(false)
        end
        return
    end

    local frame = EssencePlayerFrame
    if not frame then return end
    frame:SetScale(db.scale)
    if db.x and db.y then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    end
end

------------------------------------------------------------------------
-- Modern Essence Bar
------------------------------------------------------------------------
local ESSENCE_POWER = Enum.PowerType.Essence  -- 18

local PIP_W   = 32
local PIP_H   = 28
local PIP_GAP =  5
local BAR_PAD =  7

local CR,  CG,  CB  = 0.25, 0.78, 0.64   -- charged fill
local CHR, CHG, CHB = 0.16, 0.52, 0.40   -- charging fill
local BDR, BDG, BDB = 0.22, 0.70, 0.56   -- border accent
local BGR, BGG, BGB = 0.03, 0.10, 0.08   -- background colour

------------------------------------------------------------------------
-- CreateChargeAnimation – GPU-driven alpha bounce, zero Lua ticks
------------------------------------------------------------------------
local function CreateChargeAnimation(texture)
    local ag    = texture:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.15)
    alpha:SetToAlpha(0.65)
    alpha:SetDuration(0.75)
    alpha:SetSmoothing("IN_OUT")
    return ag
end

------------------------------------------------------------------------
-- ApplyBgOpacity – live-updates background strip alpha without rebuild
------------------------------------------------------------------------
local function ApplyBgOpacity(a)
    if not modernBar then return end
    if modernBar.bgH then modernBar.bgH:SetAlpha(a) end
    if modernBar.bgV then modernBar.bgV:SetAlpha(a) end
    ShodoQoLDB.essenceMover.bgOpacity = a
end

------------------------------------------------------------------------
-- ApplyBarAlpha – sets overall opacity for ALL bar assets at once.
------------------------------------------------------------------------
local function ApplyBarAlpha(a)
    if not modernBar then return end
    modernBar:SetAlpha(a)
    ShodoQoLDB.essenceMover.barAlpha = a
end

------------------------------------------------------------------------
-- ApplyCornerRadius
------------------------------------------------------------------------
local function ApplyCornerRadius(r)
    if not modernBar then return end
    r = math.floor(r + 0.5)

    if modernBar.bgH then
        modernBar.bgH:ClearAllPoints()
        modernBar.bgH:SetPoint("TOPLEFT",     modernBar, "TOPLEFT",     0, -r)
        modernBar.bgH:SetPoint("BOTTOMRIGHT", modernBar, "BOTTOMRIGHT", 0,  r)
    end
    if modernBar.bgV then
        modernBar.bgV:ClearAllPoints()
        modernBar.bgV:SetPoint("TOPLEFT",     modernBar, "TOPLEFT",      r, 0)
        modernBar.bgV:SetPoint("BOTTOMRIGHT", modernBar, "BOTTOMRIGHT", -r, 0)
    end
    if modernBar.outerBorder then
        local eSize = math.max(8, 8 + math.floor(r * 1.2))
        modernBar.outerBorder:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = eSize,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        modernBar.outerBorder:SetBackdropBorderColor(BDR, BDG, BDB, 0.88)
    end

    ShodoQoLDB.essenceMover.cornerRadius = r
end

------------------------------------------------------------------------
-- ApplyModernBarSize
------------------------------------------------------------------------
ApplyModernBarSize = function()
    if not modernBar then return end
    local db   = ShodoQoLDB.essenceMover
    local wS   = db.modernScaleW or DEFAULT_MODERN_SCALE_W
    local hS   = db.modernScaleH or DEFAULT_MODERN_SCALE_H
    local natW = modernBar.naturalW or 0
    local natH = modernBar.naturalH or 0

    if natW == 0 or natH == 0 then return end

    modernBar:SetSize(natW * wS, natH * hS)

    local pipW = math.max(1, math.floor(PIP_W   * wS + 0.5))
    local pipH = math.max(1, math.floor(PIP_H   * hS + 0.5))
    local gap  = math.max(1, math.floor(PIP_GAP * wS + 0.5))
    local pad  = math.max(1, math.floor(BAR_PAD * wS + 0.5))

    for i, pip in ipairs(modernBar.pips or {}) do
        pip:SetSize(pipW, pipH)
        pip:ClearAllPoints()
        pip:SetPoint("LEFT", modernBar, "LEFT", pad + (i - 1) * (pipW + gap), 0)
    end

    for i, sep in ipairs(modernBar.separators or {}) do
        local sepX = pad + i * (pipW + gap) - math.floor(gap / 2)
        sep:SetSize(1, pipH - 4)
        sep:ClearAllPoints()
        sep:SetPoint("LEFT", modernBar, "LEFT", sepX, 0)
    end

    ApplyCornerRadius(db.cornerRadius or DEFAULT_CORNER_RADIUS)
end

------------------------------------------------------------------------
-- RehookHoverGlow
------------------------------------------------------------------------
local function RehookHoverGlow(anchor)
    if not anchor then return end

    if HoverTracker and HoverTracker.SetEssenceAnchor then
        HoverTracker.SetEssenceAnchor(anchor)
        return
    end

    local glow = _G["HoverTrackerEssGlow"]
    if not glow then return end
    local db = ShodoQoLDB and ShodoQoLDB.hoverTracker
    local bX = db and db.essBleedX or 0
    local bY = db and db.essBleedY or 0
    local w  = math.max(anchor:GetWidth(),  10) + bX * 2
    local h  = math.max(anchor:GetHeight(), 10) + bY * 2
    glow:SetSize(w, h)
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", anchor, "CENTER", 0, 0)
end

------------------------------------------------------------------------
-- BuildModernBar
------------------------------------------------------------------------
local function BuildModernBar()
    if modernBar then return end
    if not EssencePlayerFrame then return end

    local db   = ShodoQoLDB.essenceMover
    local bgA  = db.bgOpacity    or DEFAULT_BG_OPACITY
    local bA   = db.barAlpha     or DEFAULT_BAR_ALPHA
    local cR   = db.cornerRadius or DEFAULT_CORNER_RADIUS
    local maxE = UnitPowerMax("player", ESSENCE_POWER) or 6
    local barW = maxE * PIP_W + (maxE - 1) * PIP_GAP + BAR_PAD * 2
    local barH = PIP_H + 8

    modernBar = CreateFrame("Frame", "ShodoQoLModernEssence", UIParent)
    modernBar:SetSize(barW, barH)
    modernBar:SetFrameStrata("LOW")
    modernBar:SetFrameLevel(10)
    modernBar:EnableMouse(false)
    modernBar.maxEssence = maxE
    modernBar.naturalW = barW
    modernBar.naturalH = barH

    local bgH = modernBar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgH:SetColorTexture(BGR, BGG, BGB, 1.0)
    bgH:SetAlpha(bgA)
    modernBar.bgH = bgH

    local bgV = modernBar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgV:SetColorTexture(BGR, BGG, BGB, 1.0)
    bgV:SetAlpha(bgA)
    modernBar.bgV = bgV

    local outerBorder = CreateFrame("Frame", nil, modernBar, "BackdropTemplate")
    outerBorder:SetAllPoints()
    outerBorder:EnableMouse(false)
    modernBar.outerBorder = outerBorder

    ApplyCornerRadius(cR)

    modernBar.pips = {}

    for i = 1, maxE do
        local pipX = BAR_PAD + (i - 1) * (PIP_W + PIP_GAP)
        local pip  = CreateFrame("Frame", nil, modernBar)
        pip:SetSize(PIP_W, PIP_H)
        pip:SetPoint("LEFT", modernBar, "LEFT", pipX, 0)
        pip:EnableMouse(false)

        local pipBg = pip:CreateTexture(nil, "BACKGROUND")
        pipBg:SetAllPoints()
        pipBg:SetColorTexture(0.06, 0.17, 0.13, 1.0)

        local fill = pip:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT",     pip, "TOPLEFT",     1, -1)
        fill:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -1,  1)
        fill:SetColorTexture(CR, CG, CB, 1.0)
        fill:Hide()
        pip.fill = fill

        local sheen = pip:CreateTexture(nil, "OVERLAY")
        sheen:SetPoint("TOPLEFT",  pip, "TOPLEFT",  1, -1)
        sheen:SetPoint("TOPRIGHT", pip, "TOPRIGHT", -1, -1)
        sheen:SetHeight(6)
        sheen:SetColorTexture(0.80, 1.0, 0.92, 0.22)
        sheen:Hide()
        pip.sheen = sheen

        local chargeFill = pip:CreateTexture(nil, "ARTWORK")
        chargeFill:SetPoint("TOPLEFT",     pip, "TOPLEFT",     1, -1)
        chargeFill:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -1,  1)
        chargeFill:SetColorTexture(CHR, CHG, CHB, 0.15)
        chargeFill:Hide()
        pip.chargeFill = chargeFill

        pip.chargeAnim = CreateChargeAnimation(chargeFill)

        local pipBorder = CreateFrame("Frame", nil, pip, "BackdropTemplate")
        pipBorder:SetAllPoints()
        pipBorder:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        pipBorder:SetBackdropBorderColor(0.14, 0.44, 0.34, 0.50)
        pipBorder:EnableMouse(false)

        modernBar.pips[i] = pip
    end

    modernBar.separators = {}
    for i = 1, maxE - 1 do
        local sepX = BAR_PAD + i * (PIP_W + PIP_GAP) - math.floor(PIP_GAP / 2)
        local sep  = modernBar:CreateTexture(nil, "OVERLAY")
        sep:SetSize(1, PIP_H - 4)
        sep:SetPoint("LEFT", modernBar, "LEFT", sepX, 0)
        sep:SetColorTexture(0.10, 0.30, 0.24, 0.50)
        modernBar.separators[i] = sep
    end

    if db.x and db.y then
        modernBar:ClearAllPoints()
        modernBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        modernBar:ClearAllPoints()
        modernBar:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", -7, -13)
    end

    ApplyModernBarSize()
    modernBar:SetAlpha(bA)

    EssencePlayerFrame:SetAlpha(0)
    EssencePlayerFrame:EnableMouse(false)
end

------------------------------------------------------------------------
-- UpdateModernBar – event-driven, no polling
------------------------------------------------------------------------
local function UpdateModernBar()
    if not modernBar then return end

    local current = UnitPower("player", ESSENCE_POWER) or 0
    local max     = modernBar.maxEssence or 6

    for i = 1, max do
        local pip = modernBar.pips[i]
        if not pip then break end

        if i <= current then
            pip.fill:Show()
            pip.sheen:Show()
            pip.chargeFill:Hide()
            if pip.chargeAnim:IsPlaying() then pip.chargeAnim:Stop() end

        elseif i == current + 1 and current < max then
            pip.fill:Hide()
            pip.sheen:Hide()
            pip.chargeFill:Show()
            if not pip.chargeAnim:IsPlaying() then pip.chargeAnim:Play() end

        else
            pip.fill:Hide()
            pip.sheen:Hide()
            pip.chargeFill:Hide()
            if pip.chargeAnim:IsPlaying() then pip.chargeAnim:Stop() end
        end
    end
end

------------------------------------------------------------------------
-- DestroyModernBar
------------------------------------------------------------------------
local function DestroyModernBar()
    if modernEventFrm then
        modernEventFrm:UnregisterAllEvents()
        modernEventFrm = nil
    end
    if modernBar then
        for _, pip in ipairs(modernBar.pips or {}) do
            if pip.chargeAnim and pip.chargeAnim:IsPlaying() then
                pip.chargeAnim:Stop()
            end
        end
        modernBar:Hide()
        modernBar = nil
    end
    if EssencePlayerFrame then
        EssencePlayerFrame:SetAlpha(1)
        EssencePlayerFrame:EnableMouse(true)
        local db = ShodoQoLDB.essenceMover
        EssencePlayerFrame:SetScale(db.scale)
        if db.x and db.y then
            EssencePlayerFrame:ClearAllPoints()
            EssencePlayerFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
        end
    end
    RehookHoverGlow(EssencePlayerFrame)
end

------------------------------------------------------------------------
-- EnableModernLook / DisableModernLook
------------------------------------------------------------------------
local EnableModernLook
local function DisableModernLook()
    DestroyModernBar()
    ShodoQoLDB.essenceMover.modernLook = false
end

EnableModernLook = function()
    if not EssencePlayerFrame then
        print("|cffff6060ShodoQoL|r: Essence bar not found - are you on an Evoker?")
        return
    end
    BuildModernBar()
    UpdateModernBar()
    RehookHoverGlow(modernBar)

    if not modernEventFrm then
        modernEventFrm = CreateFrame("Frame")
        modernEventFrm:EnableMouse(false)
        modernEventFrm:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        modernEventFrm:RegisterUnitEvent("UNIT_MAXPOWER",     "player")
        modernEventFrm:SetScript("OnEvent", function(_, event, _, powerType)
            if event == "UNIT_MAXPOWER" then
                local newMax = UnitPowerMax("player", ESSENCE_POWER) or 6
                if modernBar and newMax ~= modernBar.maxEssence then
                    DestroyModernBar()
                    EnableModernLook()
                    ApplyPosition()
                    RehookHoverGlow(modernBar)
                else
                    UpdateModernBar()
                end
            elseif powerType == "ESSENCE" then
                UpdateModernBar()
            end
        end)
    end

    ShodoQoLDB.essenceMover.modernLook = true
end

------------------------------------------------------------------------
-- Lock button
------------------------------------------------------------------------
local lockBtn = ShodoQoL.CreateButton(UIParent, "Lock Position", 148, 26)
lockBtn:SetFrameStrata("DIALOG")
lockBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
lockBtn:Hide()

local function ExitDragMode()
    local frame = modernBar or EssencePlayerFrame
    if not frame then return end
    frame:StopMovingOrSizing()
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    local db = ShodoQoLDB.essenceMover
    db.x = math.floor(left   + 0.5)
    db.y = math.floor(bottom + 0.5)
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop",  nil)
    lockBtn:Hide()
end

local function EnterDragMode()
    local frame = modernBar or EssencePlayerFrame
    if not frame then
        print("|cffff6060ShodoQoL|r: EssencePlayerFrame not found - are you on an Evoker?")
        return
    end
    frame:SetMovable(true)
    frame:SetUserPlaced(false)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    lockBtn:Show()
end

lockBtn:SetScript("OnClick", ExitDragMode)

------------------------------------------------------------------------
-- Slider factory
------------------------------------------------------------------------
local function CreateCleanSlider(parent, name, minVal, maxVal, step)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(320, 36)
    container:EnableMouse(false)

    local track = container:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT",  10, 0)
    track:SetPoint("RIGHT", -10, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.06, 0.18, 0.16, 0.90)

    local shine = container:CreateTexture(nil, "BORDER")
    shine:SetPoint("LEFT",  10, 1)
    shine:SetPoint("RIGHT", -10, 1)
    shine:SetHeight(2)
    shine:SetColorTexture(0.20, 0.68, 0.58, 0.40)

    local s = CreateFrame("Slider", name, container)
    s:SetAllPoints()
    s:EnableMouse(true)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minVal, maxVal)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)

    local thumbBorder = s:CreateTexture(nil, "OVERLAY")
    thumbBorder:SetSize(18, 26)
    thumbBorder:SetColorTexture(0.04, 0.12, 0.10, 1.00)

    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 22)
    thumb:SetColorTexture(0.25, 0.78, 0.66, 1.00)
    thumb:SetDrawLayer("OVERLAY", 1)
    thumbBorder:SetPoint("CENTER", thumb, "CENTER", 0, 0)
    s:SetThumbTexture(thumb)

    container.slider = s
    return container
end

------------------------------------------------------------------------
-- Settings sub-page
-- SCROLLBAR FIX: The canvas panel is wrapped in a ScrollFrame so content
-- never overflows the settings box.  All widgets are children of
-- `content` (the scroll child) instead of `panel` directly.
-- panel  → registered with the Settings API (fixed size, clipped)
-- sf     → ScrollFrame filling panel
-- content → scroll child; grows to fit all widgets; receives all
--            CreateFontString / CreateTexture / CreateFrame calls that
--            previously targeted panel.
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "Essence Mover"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()

-- ScrollFrame that fills the registered canvas
local sf = CreateFrame("ScrollFrame", nil, panel)
sf:SetAllPoints(panel)
sf:EnableMouse(true)

-- Scroll child — tall enough to hold all content; width matches panel
local content = CreateFrame("Frame", nil, sf)
content:SetWidth(580)
content:SetHeight(900)   -- will be adjusted below once all widgets are placed
sf:SetScrollChild(content)

-- Mouse-wheel scrolling
sf:EnableMouseWheel(true)
sf:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local max     = self:GetVerticalScrollRange()
    local new     = math.max(0, math.min(max, current - delta * 30))
    self:SetVerticalScroll(new)
end)

-- ── Title ─────────────────────────────────────────────────────────────
local titleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fEssence|r|cff52c4afMover|r")

local subFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Reposition and scale the Evoker Essence bar|r")

local div1 = content:CreateTexture(nil, "ARTWORK")
div1:SetPoint("TOPLEFT", subFS, "BOTTOMLEFT", 0, -12)
div1:SetSize(560, 1)
div1:SetColorTexture(0.20, 0.58, 0.50, 0.6)

-- ── Bar Scale ─────────────────────────────────────────────────────────
local scaleLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
scaleLabelFS:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -18)
scaleLabelFS:SetText("Bar Scale")

local scaleValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleValueFS:SetPoint("LEFT", scaleLabelFS, "RIGHT", 10, 0)
scaleValueFS:SetText("1.50x")

local scaleMinFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
scaleMinFS:SetPoint("TOPLEFT", scaleLabelFS, "BOTTOMLEFT", 0, -42)
scaleMinFS:SetText("0.5x")
scaleMinFS:SetTextColor(0.5, 0.5, 0.5)

local scaleMaxFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
scaleMaxFS:SetPoint("TOPLEFT", scaleLabelFS, "BOTTOMLEFT", 300, -42)
scaleMaxFS:SetText("3.0x")
scaleMaxFS:SetTextColor(0.5, 0.5, 0.5)

local scaleSliderC = CreateCleanSlider(content, "ShodoQoLEssenceScaleSlider", 0.5, 3.0, 0.05)
scaleSliderC:SetPoint("TOPLEFT", scaleLabelFS, "BOTTOMLEFT", 0, -18)
local scaleSlider = scaleSliderC.slider
scaleSlider:SetScript("OnValueChanged", function(_, value)
    local v = math.floor(value / 0.05 + 0.5) * 0.05
    scaleValueFS:SetText(string.format("%.2fx", v))
    if ShodoQoLDB then
        ShodoQoLDB.essenceMover.scale = v
        ApplyPosition()
    end
end)

-- ── Modern Look ──────────────────────────────────────────────────────
local divML = content:CreateTexture(nil, "ARTWORK")
divML:SetPoint("TOPLEFT", scaleSliderC, "BOTTOMLEFT", 0, -20)
divML:SetSize(560, 1)
divML:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local mlHeadFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mlHeadFS:SetPoint("TOPLEFT", divML, "BOTTOMLEFT", 0, -18)
mlHeadFS:SetText("Modern Look")

local mlToggle = CreateFrame("Button", nil, content)
mlToggle:SetSize(58, 22)
mlToggle:SetPoint("LEFT", mlHeadFS, "RIGHT", 10, 1)
mlToggle:EnableMouse(true)

local mlTBg = mlToggle:CreateTexture(nil, "BACKGROUND")
mlTBg:SetAllPoints()
mlTBg:SetColorTexture(0.12, 0.12, 0.12, 0.90)

local mlTBorder = CreateFrame("Frame", nil, mlToggle, "BackdropTemplate")
mlTBorder:SetAllPoints()
mlTBorder:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
mlTBorder:SetBackdropBorderColor(0.60, 0.10, 0.10, 0.80)
mlTBorder:EnableMouse(false)

local mlTLabel = mlToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
mlTLabel:SetAllPoints()
mlTLabel:SetJustifyH("CENTER")
mlTLabel:SetJustifyV("MIDDLE")
mlTLabel:SetText("|cffff4444[OFF]|r")

local function SyncModernToggle()
    if ShodoQoLDB and ShodoQoLDB.essenceMover.modernLook then
        mlTLabel:SetText("|cff33937f[ON]|r")
        mlTBorder:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.80)
    else
        mlTLabel:SetText("|cffff4444[OFF]|r")
        mlTBorder:SetBackdropBorderColor(0.60, 0.10, 0.10, 0.80)
    end
end

mlToggle:SetScript("OnClick", function()
    if not ShodoQoLDB then return end
    if ShodoQoLDB.essenceMover.modernLook then DisableModernLook()
    else EnableModernLook() end
    SyncModernToggle()
end)
mlToggle:SetScript("OnEnter", function() mlTBg:SetColorTexture(0.20, 0.20, 0.20, 0.90) end)
mlToggle:SetScript("OnLeave", function() mlTBg:SetColorTexture(0.12, 0.12, 0.12, 0.90) end)

local mlDescFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
mlDescFS:SetPoint("TOPLEFT", mlHeadFS, "BOTTOMLEFT", 0, -6)
mlDescFS:SetWidth(540)
mlDescFS:SetJustifyH("LEFT")
mlDescFS:SetTextColor(0.65, 0.65, 0.65)
mlDescFS:SetText("Replaces the Essence bar with a clean rectangle of essence. ")

-- ── Bar Appearance ────────────────────────────────────────────────────
local divApp = content:CreateTexture(nil, "ARTWORK")
divApp:SetPoint("TOPLEFT", mlDescFS, "BOTTOMLEFT", -2, -18)
divApp:SetSize(560, 1)
divApp:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local appHeadFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
appHeadFS:SetPoint("TOPLEFT", divApp, "BOTTOMLEFT", 0, -18)
appHeadFS:SetText("Bar Appearance")

-- ── Global Bar Opacity (all elements) ────────────────────────────────
local barAlphaLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
barAlphaLabelFS:SetPoint("TOPLEFT", appHeadFS, "BOTTOMLEFT", 0, -14)
barAlphaLabelFS:SetText("Bar Opacity  |cff666666(all elements)|r")
barAlphaLabelFS:SetTextColor(0.80, 0.80, 0.80)

local barAlphaValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
barAlphaValueFS:SetPoint("LEFT", barAlphaLabelFS, "RIGHT", 8, 0)
barAlphaValueFS:SetText("100%")

local baMinFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
baMinFS:SetPoint("TOPLEFT", barAlphaLabelFS, "BOTTOMLEFT", 0, -42)
baMinFS:SetText("10%")
baMinFS:SetTextColor(0.5, 0.5, 0.5)

local baMaxFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
baMaxFS:SetPoint("TOPLEFT", barAlphaLabelFS, "BOTTOMLEFT", 300, -42)
baMaxFS:SetText("100%")
baMaxFS:SetTextColor(0.5, 0.5, 0.5)

local barAlphaSliderC = CreateCleanSlider(content, "ShodoQoLEssenceBarAlphaSlider", 0.10, 1.00, 0.05)
barAlphaSliderC:SetPoint("TOPLEFT", barAlphaLabelFS, "BOTTOMLEFT", 0, -18)
local barAlphaSlider = barAlphaSliderC.slider
barAlphaSlider:SetScript("OnValueChanged", function(_, value)
    local v = math.floor(value / 0.05 + 0.5) * 0.05
    barAlphaValueFS:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
    if ShodoQoLDB then ApplyBarAlpha(v) end
end)

-- ── Background Opacity (bg strips only) ──────────────────────────────
local opacityLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
opacityLabelFS:SetPoint("TOPLEFT", barAlphaSliderC, "BOTTOMLEFT", 0, -14)
opacityLabelFS:SetText("Background Opacity  |cff666666(bg strips only)|r")
opacityLabelFS:SetTextColor(0.80, 0.80, 0.80)

local opacityValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
opacityValueFS:SetPoint("LEFT", opacityLabelFS, "RIGHT", 8, 0)
opacityValueFS:SetText("90%")

local opMinFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
opMinFS:SetPoint("TOPLEFT", opacityLabelFS, "BOTTOMLEFT", 0, -42)
opMinFS:SetText("20%")
opMinFS:SetTextColor(0.5, 0.5, 0.5)

local opMaxFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
opMaxFS:SetPoint("TOPLEFT", opacityLabelFS, "BOTTOMLEFT", 300, -42)
opMaxFS:SetText("100%")
opMaxFS:SetTextColor(0.5, 0.5, 0.5)

local opacitySliderC = CreateCleanSlider(content, "ShodoQoLEssenceOpacitySlider", 0.20, 1.00, 0.05)
opacitySliderC:SetPoint("TOPLEFT", opacityLabelFS, "BOTTOMLEFT", 0, -18)
local opacitySlider = opacitySliderC.slider
opacitySlider:SetScript("OnValueChanged", function(_, value)
    local v = math.floor(value / 0.05 + 0.5) * 0.05
    opacityValueFS:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
    if ShodoQoLDB then ApplyBgOpacity(v) end
end)

-- ── Modern Bar Size ───────────────────────────────────────────────────
local divWH = content:CreateTexture(nil, "ARTWORK")
divWH:SetPoint("TOPLEFT", opacitySliderC, "BOTTOMLEFT", -2, -20)
divWH:SetSize(560, 1)
divWH:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local whHeadFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
whHeadFS:SetPoint("TOPLEFT", divWH, "BOTTOMLEFT", 0, -18)
whHeadFS:SetText("Modern Bar Size  |cff666666(Modern Look only)|r")

-- Width slider
local barWidthLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
barWidthLabelFS:SetPoint("TOPLEFT", whHeadFS, "BOTTOMLEFT", 0, -14)
barWidthLabelFS:SetText("Bar Width")
barWidthLabelFS:SetTextColor(0.80, 0.80, 0.80)

local barWidthValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
barWidthValueFS:SetPoint("LEFT", barWidthLabelFS, "RIGHT", 8, 0)
barWidthValueFS:SetText("1.00x")

local bwMinFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bwMinFS:SetPoint("TOPLEFT", barWidthLabelFS, "BOTTOMLEFT", 0, -42)
bwMinFS:SetText("0.5x")
bwMinFS:SetTextColor(0.5, 0.5, 0.5)

local bwMaxFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bwMaxFS:SetPoint("TOPLEFT", barWidthLabelFS, "BOTTOMLEFT", 300, -42)
bwMaxFS:SetText("3.0x")
bwMaxFS:SetTextColor(0.5, 0.5, 0.5)

local barWidthSliderC = CreateCleanSlider(content, "ShodoQoLEssenceBarWidthSlider", 0.5, 3.0, 0.05)
barWidthSliderC:SetPoint("TOPLEFT", barWidthLabelFS, "BOTTOMLEFT", 0, -18)
local barWidthSlider = barWidthSliderC.slider
barWidthSlider:SetScript("OnValueChanged", function(_, value)
    local v = math.floor(value / 0.05 + 0.5) * 0.05
    barWidthValueFS:SetText(string.format("%.2fx", v))
    if ShodoQoLDB then
        ShodoQoLDB.essenceMover.modernScaleW = v
        if modernBar then ApplyModernBarSize() end
    end
end)

-- Height slider
local barHeightLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
barHeightLabelFS:SetPoint("TOPLEFT", barWidthSliderC, "BOTTOMLEFT", 0, -14)
barHeightLabelFS:SetText("Bar Height")
barHeightLabelFS:SetTextColor(0.80, 0.80, 0.80)

local barHeightValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
barHeightValueFS:SetPoint("LEFT", barHeightLabelFS, "RIGHT", 8, 0)
barHeightValueFS:SetText("1.00x")

local bhMinFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bhMinFS:SetPoint("TOPLEFT", barHeightLabelFS, "BOTTOMLEFT", 0, -42)
bhMinFS:SetText("0.5x")
bhMinFS:SetTextColor(0.5, 0.5, 0.5)

local bhMaxFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bhMaxFS:SetPoint("TOPLEFT", barHeightLabelFS, "BOTTOMLEFT", 300, -42)
bhMaxFS:SetText("3.0x")
bhMaxFS:SetTextColor(0.5, 0.5, 0.5)

local barHeightSliderC = CreateCleanSlider(content, "ShodoQoLEssenceBarHeightSlider", 0.5, 3.0, 0.05)
barHeightSliderC:SetPoint("TOPLEFT", barHeightLabelFS, "BOTTOMLEFT", 0, -18)
local barHeightSlider = barHeightSliderC.slider
barHeightSlider:SetScript("OnValueChanged", function(_, value)
    local v = math.floor(value / 0.05 + 0.5) * 0.05
    barHeightValueFS:SetText(string.format("%.2fx", v))
    if ShodoQoLDB then
        ShodoQoLDB.essenceMover.modernScaleH = v
        if modernBar then ApplyModernBarSize() end
    end
end)

-- ── Bar Position ──────────────────────────────────────────────────────
local div2 = content:CreateTexture(nil, "ARTWORK")
div2:SetPoint("TOPLEFT", barHeightSliderC, "BOTTOMLEFT", -2, -20)
div2:SetSize(560, 1)
div2:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local posLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
posLabelFS:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -18)
posLabelFS:SetText("Bar Position")

local configBtn = ShodoQoL.CreateButton(content, "Configure Position", 160, 26)
configBtn:SetPoint("TOPLEFT", posLabelFS, "BOTTOMLEFT", 0, -10)
configBtn:SetScript("OnClick", function()
    HideUIPanel(SettingsPanel)
    EnterDragMode()
end)

local hintFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintFS:SetPoint("TOPLEFT", configBtn, "BOTTOMLEFT", 2, -6)
hintFS:SetText("|cff888888This menu closes. Drag the Essence bar, then click Lock Position.|r")

local div3 = content:CreateTexture(nil, "ARTWORK")
div3:SetPoint("TOPLEFT", hintFS, "BOTTOMLEFT", -2, -18)
div3:SetSize(560, 1)
div3:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local resetBtn = ShodoQoL.CreateButton(content, "Reset to Default", 120, 26)
resetBtn:SetPoint("TOPLEFT", div3, "BOTTOMLEFT", 0, -14)
resetBtn:SetScript("OnClick", function()
    local db = ShodoQoLDB.essenceMover
    if db.modernLook then DisableModernLook(); SyncModernToggle() end
    db.x, db.y, db.scale    = nil, nil, 1.5
    db.bgOpacity             = DEFAULT_BG_OPACITY
    db.cornerRadius          = DEFAULT_CORNER_RADIUS
    db.barAlpha              = DEFAULT_BAR_ALPHA
    db.modernScaleW          = DEFAULT_MODERN_SCALE_W
    db.modernScaleH          = DEFAULT_MODERN_SCALE_H
    local frame = EssencePlayerFrame
    if frame then
        frame:SetUserPlaced(false)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", -7, -13)
    end
    scaleValueFS:SetText("1.50x")
    scaleSlider:SetValue(1.5)
    barAlphaValueFS:SetText("100%")
    barAlphaSlider:SetValue(DEFAULT_BAR_ALPHA)
    opacityValueFS:SetText("90%")
    opacitySlider:SetValue(DEFAULT_BG_OPACITY)
    barWidthValueFS:SetText("1.00x")
    barWidthSlider:SetValue(DEFAULT_MODERN_SCALE_W)
    barHeightValueFS:SetText("1.00x")
    barHeightSlider:SetValue(DEFAULT_MODERN_SCALE_H)
    ApplyPosition()
end)

-- Seed all sliders when the panel is opened; also reset scroll to top.
panel:HookScript("OnShow", function()
    sf:SetVerticalScroll(0)
    SyncModernToggle()
    if not ShodoQoLDB then return end
    local db = ShodoQoLDB.essenceMover
    scaleSlider:SetValue(db.scale          or 1.5)
    barAlphaSlider:SetValue(db.barAlpha    or DEFAULT_BAR_ALPHA)
    opacitySlider:SetValue(db.bgOpacity    or DEFAULT_BG_OPACITY)
    barWidthSlider:SetValue(db.modernScaleW  or DEFAULT_MODERN_SCALE_W)
    barHeightSlider:SetValue(db.modernScaleH or DEFAULT_MODERN_SCALE_H)
end)

local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "Essence Mover")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("EssenceMover") then return end

    local db = ShodoQoLDB.essenceMover
    if db.bgOpacity    == nil then db.bgOpacity    = DEFAULT_BG_OPACITY    end
    if db.cornerRadius == nil then db.cornerRadius = DEFAULT_CORNER_RADIUS  end
    if db.barAlpha     == nil then db.barAlpha     = DEFAULT_BAR_ALPHA      end
    if db.modernScaleW == nil then db.modernScaleW = DEFAULT_MODERN_SCALE_W end
    if db.modernScaleH == nil then db.modernScaleH = DEFAULT_MODERN_SCALE_H end

    scaleSlider:SetValue(db.scale or 1.5)
    SyncModernToggle()

    if db.modernLook then EnableModernLook() end

    local applyPending = false
    local function DeferredApply()
        if applyPending then return end
        applyPending = true
        C_Timer.After(0.05, function()
            applyPending = false
            ApplyPosition()
            if modernBar then UpdateModernBar() end
            local db2 = ShodoQoLDB.essenceMover
            if db2.modernLook then
                RehookHoverGlow(modernBar)
            else
                RehookHoverGlow(EssencePlayerFrame)
            end
        end)
    end

    local pewFrame = CreateFrame("Frame")
    pewFrame:EnableMouse(false)
    pewFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    pewFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    pewFrame:RegisterUnitEvent("UNIT_AURA", "player")
    pewFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_EXITED_VEHICLE" and unit ~= "player" then return end
        DeferredApply()
    end)

    if EssencePlayerFrame then
        specListener = CreateFrame("Frame")
        specListener:EnableMouse(false)
        specListener:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        specListener:SetScript("OnEvent", function(_, _, unit)
            if unit ~= "player" then return end
            C_Timer.After(0, function()
                if modernBar then
                    local newMax = UnitPowerMax("player", ESSENCE_POWER) or 6
                    if newMax ~= modernBar.maxEssence then
                        DestroyModernBar()
                        EnableModernLook()
                        ApplyPosition()
                        RehookHoverGlow(modernBar)
                        return
                    end
                end
                ApplyPosition()
            end)
        end)
    end
end)

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------
SLASH_ESSENCEBAR1 = "/essencebar"
SlashCmdList["ESSENCEBAR"] = function()
    if not ShodoQoLDB then
        print("|cffff6060ShodoQoL|r: DB not ready.")
        return
    end
    local db = ShodoQoLDB.essenceMover
    if not db.x or not db.y then
        print("|cff33937fShodoQoL|r: No saved Essence bar position.")
        return
    end
    ApplyPosition()
    if modernBar then UpdateModernBar() end
    print(string.format(
        "|cff33937fShodoQoL|r: Essence bar snapped to (%d, %d) @ %.2fx%s.",
        db.x, db.y, db.scale,
        db.modernLook and " [Modern Look]" or ""
    ))
end
