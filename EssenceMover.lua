-- ShodoQoL/EssenceMover.lua
-- Moves and scales the Evoker Essence bar.
-- Reads/writes ShodoQoLDB.essenceMover.

local function ApplyPosition()
    local frame = EssencePlayerFrame
    if not frame then return end
    local db = ShodoQoLDB.essenceMover
    frame:SetScale(db.scale)
    if db.x and db.y then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    end
end

local specListener

------------------------------------------------------------------------
-- Lock button
------------------------------------------------------------------------
local lockBtn = ShodoQoL.CreateButton(UIParent, "Lock Position", 148, 26)
lockBtn:SetFrameStrata("DIALOG")
lockBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
lockBtn:Hide()

local function ExitDragMode()
    local frame = EssencePlayerFrame
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
    local frame = EssencePlayerFrame
    if not frame then
        print("|cffff6060ShodoQoL|r: EssencePlayerFrame not found — are you on an Evoker?")
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
-- Slider — pure SetColorTexture, no file paths, no template OnUpdate.
------------------------------------------------------------------------
local function CreateCleanSlider(parent, name, minVal, maxVal, step)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(320, 36)
    container:EnableMouse(false)

    local track = container:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 10, 0)
    track:SetPoint("RIGHT", -10, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.06, 0.18, 0.16, 0.90)   -- dark evoker trough

    local shine = container:CreateTexture(nil, "BORDER")
    shine:SetPoint("LEFT", 10, 1)
    shine:SetPoint("RIGHT", -10, 1)
    shine:SetHeight(2)
    shine:SetColorTexture(0.20, 0.68, 0.58, 0.40)   -- evoker green sheen

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
    thumb:SetColorTexture(0.25, 0.78, 0.66, 1.00)   -- bright evoker green thumb
    thumb:SetDrawLayer("OVERLAY", 1)
    thumbBorder:SetPoint("CENTER", thumb, "CENTER", 0, 0)
    s:SetThumbTexture(thumb)

    container.slider = s
    return container
end

------------------------------------------------------------------------
-- Settings sub-page
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "Essence Mover"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()  -- start hidden; Settings API manages show/hide

local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fEssence|r|cff52c4afMover|r")

local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Reposition and scale the Evoker Essence bar|r")

local div1 = panel:CreateTexture(nil, "ARTWORK")
div1:SetPoint("TOPLEFT", subFS, "BOTTOMLEFT", 0, -12)
div1:SetSize(560, 1)
div1:SetColorTexture(0.20, 0.58, 0.50, 0.6)

local scaleLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
scaleLabelFS:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -18)
scaleLabelFS:SetText("Bar Scale")

local scaleValueFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleValueFS:SetPoint("LEFT", scaleLabelFS, "RIGHT", 10, 0)
scaleValueFS:SetText("1.50x")

local minLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
minLabelFS:SetPoint("TOPLEFT", scaleLabelFS, "BOTTOMLEFT", 0, -42)
minLabelFS:SetText("0.5x")
minLabelFS:SetTextColor(0.5, 0.5, 0.5)

local maxLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
maxLabelFS:SetPoint("TOPLEFT", scaleLabelFS, "BOTTOMLEFT", 300, -42)
maxLabelFS:SetText("3.0x")
maxLabelFS:SetTextColor(0.5, 0.5, 0.5)

local sliderContainer = CreateCleanSlider(panel, "ShodoQoLEssenceSlider", 0.5, 3.0, 0.05)
sliderContainer:SetPoint("TOPLEFT", scaleLabelFS, "BOTTOMLEFT", 0, -18)

local slider = sliderContainer.slider
slider:SetScript("OnValueChanged", function(self, value)
    local snapped = math.floor(value / 0.05 + 0.5) * 0.05
    scaleValueFS:SetText(string.format("%.2fx", snapped))
    if ShodoQoLDB then
        ShodoQoLDB.essenceMover.scale = snapped
        ApplyPosition()
    end
end)

local div2 = panel:CreateTexture(nil, "ARTWORK")
div2:SetPoint("TOPLEFT", sliderContainer, "BOTTOMLEFT", 0, -20)
div2:SetSize(560, 1)
div2:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local posLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
posLabelFS:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -18)
posLabelFS:SetText("Bar Position")

local configBtn = ShodoQoL.CreateButton(panel, "Configure Position", 160, 26)
configBtn:SetPoint("TOPLEFT", posLabelFS, "BOTTOMLEFT", 0, -10)
configBtn:SetScript("OnClick", function()
    HideUIPanel(SettingsPanel)
    EnterDragMode()
end)

local hintFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintFS:SetPoint("TOPLEFT", configBtn, "BOTTOMLEFT", 2, -6)
hintFS:SetText("|cff888888This menu closes. Drag the Essence bar, then click Lock Position.|r")

local div3 = panel:CreateTexture(nil, "ARTWORK")
div3:SetPoint("TOPLEFT", hintFS, "BOTTOMLEFT", -2, -18)
div3:SetSize(560, 1)
div3:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local resetBtn = ShodoQoL.CreateButton(panel, "Reset to Default", 120, 26)
resetBtn:SetPoint("TOPLEFT", div3, "BOTTOMLEFT", 0, -14)
resetBtn:SetScript("OnClick", function()
    local db = ShodoQoLDB.essenceMover
    db.x, db.y, db.scale = nil, nil, 1.5
    local frame = EssencePlayerFrame
    if frame then
        frame:SetUserPlaced(false)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", -7, -13)
    end
    scaleValueFS:SetText("1.50x")
    slider:SetValue(1.5)
    ApplyPosition()
end)

local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "Essence Mover")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("EssenceMover") then return end
    slider:SetValue(ShodoQoLDB.essenceMover.scale)

    -- Blizzard re-anchors EssencePlayerFrame on EVERY PLAYER_ENTERING_WORLD
    -- (initial login, /reload, zone transitions, dungeon entries, death/release).
    -- We must listen permanently and reapply each time — NOT unregister after
    -- the first fire, which was the source of the reset-on-death/zone bug.
    -- ApplyPosition() is a no-op when db.x/y are nil, so there is no cost
    -- when the user has never moved the bar.
    --
    -- UNIT_EXITED_VEHICLE is also registered because leaving a vehicle triggers
    -- a Blizzard UI re-anchor without firing PLAYER_ENTERING_WORLD.
    -- NOTE: PLAYER_ENTERING_WORLD passes isInitialLogin (boolean) as its first
    -- payload arg — NOT nil — so we must branch on the event name, not the unit.
    -- Debounce flag: collapses rapid UNIT_AURA churn (e.g. combat buff spam)
    -- into a single deferred apply so we never hammer ApplyPosition.
    local applyPending = false
    local function DeferredApply()
        if applyPending then return end
        applyPending = true
        -- 0.05 s gives Blizzard's own re-anchor code (including the one triggered
        -- by the Augmentation Evoker "Future Self" aura expiring on UNIT_AURA)
        -- time to finish before we re-apply our saved position on top of it.
        C_Timer.After(0.05, function()
            applyPending = false
            ApplyPosition()
        end)
    end

    local pewFrame = CreateFrame("Frame")
    pewFrame:EnableMouse(false)
    pewFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    pewFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    -- UNIT_AURA catches the Augmentation Evoker "Future Self" buff falling off
    -- at the end of Breath of Eons.  Blizzard hooks the same event internally
    -- to re-anchor EssencePlayerFrame, which caused the post-landing reset.
    pewFrame:RegisterEvent("UNIT_AURA")
    pewFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_EXITED_VEHICLE" and unit ~= "player" then return end
        if event == "UNIT_AURA"           and unit ~= "player" then return end
        DeferredApply()
    end)

    -- Spec changes also cause Blizzard to re-anchor. Register only on Evoker.
    if EssencePlayerFrame then
        specListener = CreateFrame("Frame")
        specListener:EnableMouse(false)
        specListener:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        specListener:SetScript("OnEvent", function(_, _, unit)
            if unit == "player" then C_Timer.After(0, ApplyPosition) end
        end)
    end
end)

------------------------------------------------------------------------
-- Slash command — macro-friendly manual reposition.
-- Usage:  /essencebar
-- Snaps the bar back to the saved DB position without a reload.
-- Safe to bind to a macro for edge cases (e.g. selfie camera reset).
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
    print(string.format("|cff33937fShodoQoL|r: Essence bar snapped to (%d, %d) @ %.2fx.", db.x, db.y, db.scale))
end
