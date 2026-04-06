-- ShodoQoL/PrescienceTracker.lua
-- Compact HUD: Prescience buff state for the two targets in Macro Helpers.
--
-- Only active when the player is an Augmentation Evoker (spec ID 1473).
-- Hides automatically on spec change; reappears if swapping back to Aug.
--
-- CPU design — zero OnUpdate, zero polling:
--   UNIT_AURA fires on buff apply/expire → instant green or red.
--   One C_Timer.NewTimer per active buff fires once at (expiry - WARN_SEC)
--     to flip the slot orange.  Not a repeating loop; cancelled on each new
--     UNIT_AURA so it always tracks the latest application.
--   A second one-shot expiry timer fires at (expirationTime + 0.1 s) to
--     guarantee the red transition even if UNIT_AURA is dropped in combat.
--   GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD → rebuild unitData, rescan.
--   PLAYER_SPECIALIZATION_CHANGED → re-evaluate spec gate + full refresh.
--   PLAYER_REGEN_ENABLED → flush deferred roster rebuild after combat.
--   UNIT_CONNECTION → treat like roster update.
--
-- Display: ● dot + name, three states only (no bar, no ticker):
--   Green  = buff active, > WARN_SEC remaining
--   Orange = buff active, ≤ WARN_SEC remaining
--   Red    = buff missing / expired

ShodoQoL.PrescienceTracker = ShodoQoL.PrescienceTracker or {}
local PT = ShodoQoL.PrescienceTracker

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local PRESCIENCE_NAME = "Prescience"
local WARN_SEC        = 5        -- seconds remaining → orange
local AUG_SPEC_ID     = 1473     -- Augmentation Evoker specialization ID

------------------------------------------------------------------------
-- Spec gate
------------------------------------------------------------------------
local function IsAugEvoker()
    local _, class = UnitClass("player")
    if class ~= "EVOKER" then return false end
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == AUG_SPEC_ID
end

------------------------------------------------------------------------
-- Runtime state
------------------------------------------------------------------------
local unitData = {}           -- unitToken → { name, realm, hasBuff, expirationTime }
local p1Token, p2Token        -- resolved unitTokens for the two slots
local pendingRefresh = false  -- deferred FullRefresh flagged during combat

-- One-shot warn timers — one per slot.
-- Each fires exactly once at (expirationTime - WARN_SEC) to flip orange.
-- Cancelled and rescheduled on every UNIT_AURA for that slot.
local warnTimer   = { [1] = nil, [2] = nil }

-- One-shot expiry timers — one per slot.
-- Each fires exactly once at (expirationTime + 0.1 s) to force the red
-- transition in case UNIT_AURA is throttled / dropped during combat.
local expiryTimer = { [1] = nil, [2] = nil }

------------------------------------------------------------------------
-- Aura scanner
------------------------------------------------------------------------
local function ScanUnit(token)
    if not UnitExists(token) then return false, 0 end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex(token, i)
        if not aura then break end
        if aura.name == PRESCIENCE_NAME then
            return true, aura.expirationTime or 0
        end
    end
    return false, 0
end

------------------------------------------------------------------------
-- Build unitData from the current roster
------------------------------------------------------------------------
local function RebuildUnitData()
    wipe(unitData)
    local function Add(token)
        if not UnitExists(token) then return end
        local name, realm = UnitName(token)
        if not name then return end
        unitData[token] = { name = name, realm = realm or "",
                            hasBuff = false, expirationTime = 0 }
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do Add("party" .. i) end
    end
    Add("player")
end

------------------------------------------------------------------------
-- Find the unitToken for a target DB entry
------------------------------------------------------------------------
local function TokenForTarget(db)
    if not db or not db.targetName or db.targetName == "" then return nil end
    local needle      = db.targetName:lower()
    local realmNeedle = db.targetRealm and db.targetRealm:lower() or ""
    for token, d in pairs(unitData) do
        if d.name:lower() == needle then
            if realmNeedle == "" or d.realm == "" or d.realm:lower() == realmNeedle then
                return token
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Scan aura state into unitData for one token
------------------------------------------------------------------------
local function ScanSlot(token)
    if not token or not unitData[token] then return end
    local ok, hasBuff, expTime = pcall(ScanUnit, token)
    if not ok then return end
    local d = unitData[token]
    d.hasBuff        = hasBuff
    d.expirationTime = expTime
end

------------------------------------------------------------------------
-- HUD frame
------------------------------------------------------------------------
local hud = CreateFrame("Frame", "ShodoQoLPrescienceHUD", UIParent, "BackdropTemplate")
hud:SetSize(220, 44)
hud:SetClampedToScreen(true)
hud:SetMovable(true)
hud:EnableMouse(false)
hud:Hide()

hud:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
hud:SetBackdropColor(0.04, 0.04, 0.04, 0.90)
hud:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.85)

-- Opacity affects only the backdrop bg + border, never the text.
local function ApplyHudOpacity(val)
    hud:SetBackdropColor(0.04, 0.04, 0.04, 0.90 * val)
    hud:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.85 * val)
    if hud._rowDiv then hud._rowDiv:SetAlpha(val) end
end

hud:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" then self:StartMoving() end
end)
hud:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local pt, _, rpt, x, y = self:GetPoint()
    local db = ShodoQoLDB.prescienceTracker
    db.point, db.relPoint, db.posX, db.posY = pt, rpt, x, y
end)

------------------------------------------------------------------------
-- Row factory — dot + slot label + name (no bar, no ticker)
------------------------------------------------------------------------
local function MakeRow(yOffset)
    local row = {}
    row.dot = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.dot:SetPoint("TOPLEFT", hud, "TOPLEFT", 7, yOffset)
    row.dot:SetWidth(14)
    row.dot:SetJustifyH("CENTER")
    do local f, s = row.dot:GetFont(); row.dot:SetFont(f, s, "OUTLINE") end

    row.slotFS = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.slotFS:SetPoint("LEFT", row.dot, "RIGHT", 4, 0)
    row.slotFS:SetWidth(22)
    row.slotFS:SetJustifyH("LEFT")
    do local f, s = row.slotFS:GetFont(); row.slotFS:SetFont(f, s, "OUTLINE") end

    row.nameFS = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameFS:SetPoint("LEFT", row.slotFS, "RIGHT", 4, 0)
    row.nameFS:SetPoint("RIGHT", hud, "RIGHT", -8, 0)
    row.nameFS:SetJustifyH("LEFT")
    do local f, s = row.nameFS:GetFont(); row.nameFS:SetFont(f, s, "OUTLINE") end

    return row
end

local row1 = MakeRow(-9)
local row2 = MakeRow(-27)
row1.slotFS:SetText("|cffaaaaaa 1|r")
row2.slotFS:SetText("|cffaaaaaa 2|r")

-- Thin separator
local rowDiv = hud:CreateTexture(nil, "ARTWORK")
rowDiv:SetPoint("TOPLEFT",  hud, "TOPLEFT",  6, -19)
rowDiv:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -6, -19)
rowDiv:SetHeight(1)
rowDiv:SetColorTexture(0.20, 0.58, 0.50, 0.25)
hud._rowDiv = rowDiv  -- expose for ApplyHudOpacity

-- Auto-fit HUD width to the widest name row (left chrome + name + right pad).
local HUD_CHROME_W = 7 + 14 + 4 + 22 + 4  -- dot + slot + gaps
local HUD_PAD_R    = 12
local HUD_MIN_W    = 120
local function ResizeHUD()
    local w = math.max(
        row1.nameFS:GetStringWidth(),
        row2.nameFS:GetStringWidth(),
        HUD_MIN_W - HUD_CHROME_W - HUD_PAD_R
    )
    hud:SetWidth(HUD_CHROME_W + w + HUD_PAD_R)
end

------------------------------------------------------------------------
-- DrawRow — sets dot + name to one of three states; called only from
-- events / the one-shot warn/expiry timers.  No per-frame work.
------------------------------------------------------------------------
local function DrawRow(slotIdx)
    local row        = slotIdx == 1 and row1 or row2
    local token      = slotIdx == 1 and p1Token or p2Token
    local db         = slotIdx == 1 and ShodoQoLDB.prescience1 or ShodoQoLDB.prescience2
    local targetName = db and db.targetName ~= "" and db.targetName or nil

    if not targetName then
        row.dot:SetText("|cff444444x|r")
        row.nameFS:SetText("|cff555555(none set)|r")
        ResizeHUD(); return
    end

    local d = token and unitData[token]
    if not d then
        -- target set but not found in group
        row.dot:SetText("|cff555555-|r")
        row.nameFS:SetText("|cff777777" .. targetName .. "|r")
        ResizeHUD(); return
    end

    local remaining = 0
    if d.hasBuff and d.expirationTime >= 0 then
        remaining = math.max(0, d.expirationTime - GetTime())
    end

    if d.hasBuff and remaining >= 0 then
        if remaining >= WARN_SEC then
            -- ── State 1: active, healthy ── green
            row.dot:SetText("|cff00cc44o|r")
            row.nameFS:SetText("|cff00cc44" .. d.name .. "|r")
        else
            -- ── State 2: active, expiring ── orange
            row.dot:SetText("|cffff9900!|r")
            row.nameFS:SetText("|cffff9900" .. d.name .. "|r")
        end
    else
        -- ── State 3: missing / expired ── red
        row.dot:SetText("|cffff3333x|r")
        row.nameFS:SetText("|cffff5555" .. d.name .. "|r")
    end
    ResizeHUD()
end

------------------------------------------------------------------------
-- ScheduleBuffTimers — cancels any pending warn/expiry timers for a slot
-- and schedules fresh one-shots:
--   • warn   fires at (expirationTime - WARN_SEC)  → orange
--   • expiry fires at (expirationTime + 0.1 s)     → rescan + force red
--
-- The +0.1 s buffer gives the server time to remove the aura from the
-- API before we scan.  Even if ScanUnit somehow still returns the buff,
-- we force hasBuff = false when GetTime() is past expirationTime.
------------------------------------------------------------------------
local function ScheduleBuffTimers(slotIdx, expirationTime)
    -- Always cancel both old timers first
    if warnTimer[slotIdx]   then warnTimer[slotIdx]:Cancel();   warnTimer[slotIdx]   = nil end
    if expiryTimer[slotIdx] then expiryTimer[slotIdx]:Cancel(); expiryTimer[slotIdx] = nil end

    if not expirationTime or expirationTime <= 0 then return end

    local now      = GetTime()
    local warnIn   = expirationTime - now - WARN_SEC
    local expiryIn = expirationTime - now

    if warnIn > 0 then
        warnTimer[slotIdx] = C_Timer.NewTimer(warnIn, function()
            warnTimer[slotIdx] = nil
            DrawRow(slotIdx)
        end)
    end

    -- Always schedule the expiry timer regardless of warn window.
    -- +0.1 s so the server has cleared the aura before we scan.
    if expiryIn > 0 then
        expiryTimer[slotIdx] = C_Timer.NewTimer(expiryIn + 0.1, function()
            expiryTimer[slotIdx] = nil
            local token = slotIdx == 1 and p1Token or p2Token
            ScanSlot(token)
            -- Force off if clock says we're past expiry, regardless of API state
            local d = token and unitData[token]
            if d and d.hasBuff and d.expirationTime <= GetTime() then
                d.hasBuff = false
            end
            DrawRow(slotIdx)
        end)
    end
end

------------------------------------------------------------------------
-- CancelAllTimers — helper used by FullRefresh / OnTargetChanged
------------------------------------------------------------------------
local function CancelAllTimers()
    for i = 1, 2 do
        if warnTimer[i]   then warnTimer[i]:Cancel();   warnTimer[i]   = nil end
        if expiryTimer[i] then expiryTimer[i]:Cancel(); expiryTimer[i] = nil end
    end
end

------------------------------------------------------------------------
-- Visibility — hides if module disabled, wrong spec, or no targets set
------------------------------------------------------------------------
local function UpdateVisibility()
    if not ShodoQoL.IsEnabled("PrescienceTracker") then hud:Hide(); return end
    if not IsAugEvoker() then hud:Hide(); return end
    local db1 = ShodoQoLDB.prescience1
    local db2 = ShodoQoLDB.prescience2
    if (db1 and db1.targetName and db1.targetName ~= "")
    or (db2 and db2.targetName and db2.targetName ~= "") then
        hud:Show()
    else
        hud:Hide()
    end
end

------------------------------------------------------------------------
-- Full refresh — roster rebuild + token resolution + aura scan + redraw
------------------------------------------------------------------------
local function FullRefresh()
    CancelAllTimers()
    RebuildUnitData()
    p1Token = TokenForTarget(ShodoQoLDB.prescience1)
    p2Token = TokenForTarget(ShodoQoLDB.prescience2)
    ScanSlot(p1Token)
    ScanSlot(p2Token)
    -- Schedule both timers from freshly scanned state
    local d1 = p1Token and unitData[p1Token]
    local d2 = p2Token and unitData[p2Token]
    if d1 and d1.hasBuff then ScheduleBuffTimers(1, d1.expirationTime) end
    if d2 and d2.hasBuff then ScheduleBuffTimers(2, d2.expirationTime) end
    DrawRow(1)
    DrawRow(2)
    UpdateVisibility()
end

------------------------------------------------------------------------
-- OnTargetChanged — called by MacroHelpers when a P1/P2 target is edited
------------------------------------------------------------------------
function PT.OnTargetChanged()
    CancelAllTimers()
    p1Token = TokenForTarget(ShodoQoLDB.prescience1)
    p2Token = TokenForTarget(ShodoQoLDB.prescience2)
    ScanSlot(p1Token)
    ScanSlot(p2Token)
    local d1 = p1Token and unitData[p1Token]
    local d2 = p2Token and unitData[p2Token]
    if d1 and d1.hasBuff then ScheduleBuffTimers(1, d1.expirationTime) end
    if d2 and d2.hasBuff then ScheduleBuffTimers(2, d2.expirationTime) end
    DrawRow(1)
    DrawRow(2)
    UpdateVisibility()
end

------------------------------------------------------------------------
-- Event handler
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UNIT_CONNECTION")

eventFrame:SetScript("OnEvent", function(_, event, unitID)
    if event == "UNIT_AURA" then
        -- Hot path: two comparisons, bail immediately for irrelevant units
        if unitID ~= p1Token and unitID ~= p2Token then return end
        local slotIdx = (unitID == p1Token) and 1 or 2

        local ok, hasBuff, expTime = pcall(ScanUnit, unitID)
        if not ok then return end

        local d = unitData[unitID]
        if d then
            d.hasBuff        = hasBuff
            d.expirationTime = expTime
        end

        ScheduleBuffTimers(slotIdx, hasBuff and expTime or nil)
        DrawRow(slotIdx)

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec changes cannot happen in combat so no lockdown guard needed.
        -- FullRefresh calls UpdateVisibility which re-checks IsAugEvoker().
        FullRefresh()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRefresh then
            pendingRefresh = false
            FullRefresh()
        end

    else
        -- GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD / UNIT_CONNECTION
        if InCombatLockdown() then
            pendingRefresh = true
        else
            FullRefresh()
        end
    end
end)

------------------------------------------------------------------------
-- Settings sub-page helpers
------------------------------------------------------------------------

-- Clean slider matching ShoStats style:
--   label + value on one row, full-width track + teal thumb below.
-- Returns container (320×52), slider, valueFS, labelFS.
local function MakeSlider(parent, labelText, minVal, maxVal, step, anchorFrame, offY)
    -- Row anchor: label text
    local labelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, offY)
    labelFS:SetText(labelText)

    -- Value readout sits to the right of the label
    local valueFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueFS:SetPoint("LEFT", labelFS, "RIGHT", 10, 0)
    valueFS:SetWidth(52)
    valueFS:SetJustifyH("LEFT")

    -- Container for the track + slider (so anchoring the next row is easy)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(320, 36)
    c:EnableMouse(false)
    c:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -6)

    -- Track
    local track = c:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT",  10, 0)
    track:SetPoint("RIGHT", -10, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.06, 0.18, 0.16, 0.90)

    -- Shine highlight on top of track
    local shine = c:CreateTexture(nil, "BORDER")
    shine:SetPoint("LEFT",  10, 1)
    shine:SetPoint("RIGHT", -10, 1)
    shine:SetHeight(2)
    shine:SetColorTexture(0.20, 0.68, 0.58, 0.40)

    -- Slider frame fills the container
    local slider = CreateFrame("Slider", nil, c)
    slider:SetAllPoints()
    slider:EnableMouse(true)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Thumb: dark border block + teal fill on top
    local thumbBorder = slider:CreateTexture(nil, "OVERLAY")
    thumbBorder:SetSize(18, 26)
    thumbBorder:SetColorTexture(0.04, 0.12, 0.10, 1)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 22)
    thumb:SetColorTexture(0.25, 0.78, 0.66, 1)
    thumb:SetDrawLayer("OVERLAY", 1)
    thumbBorder:SetPoint("CENTER", thumb, "CENTER", 0, 0)
    slider:SetThumbTexture(thumb)

    -- Expose the container as the "row" frame for anchoring
    c.slider = slider

    return slider, valueFS, labelFS, c
end

------------------------------------------------------------------------
-- Settings sub-page
------------------------------------------------------------------------
local sp = CreateFrame("Frame")
sp.name   = "Prescience Tracker"
sp.parent = "ShodoQoL"
sp:EnableMouse(false)
sp:Hide()

local sTitleFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
sTitleFS:SetPoint("TOPLEFT", 16, -16)
sTitleFS:SetText("|cff33937fPrescience|r|cff52c4afTracker|r")

local sSubFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sSubFS:SetPoint("TOPLEFT", sTitleFS, "BOTTOMLEFT", 0, -6)
sSubFS:SetText("|cff888888Live Prescience state. event-driven, zero CPU at rest|r")

local sDiv0 = sp:CreateTexture(nil, "ARTWORK")
sDiv0:SetPoint("TOPLEFT", sSubFS, "BOTTOMLEFT", 0, -12)
sDiv0:SetSize(560, 1)
sDiv0:SetColorTexture(0.20, 0.58, 0.50, 0.6)

-- ── Lock ──────────────────────────────────────────────────────────────
local lockLabelFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lockLabelFS:SetPoint("TOPLEFT", sDiv0, "BOTTOMLEFT", 0, -18)
lockLabelFS:SetText("HUD lock")

local lockHintFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
lockHintFS:SetPoint("TOPLEFT", lockLabelFS, "BOTTOMLEFT", 0, -5)
lockHintFS:SetText("|cff888888Unlock to drag the HUD. Lock when positioned.|r")

local lockStateFS = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
lockStateFS:SetPoint("TOPLEFT", lockHintFS, "BOTTOMLEFT", 0, -10)
lockStateFS:SetText("")

local function RefreshLockState()
    local locked = ShodoQoLDB.prescienceTracker.locked
    lockStateFS:SetText(locked and "|cff00ff00x Locked|r"
                                or "|cffffd100o Unlocked: drag the HUD to reposition|r")
    hud:EnableMouse(not locked)
end

local toggleLockBtn = ShodoQoL.CreateButton(sp, "Toggle Lock", 110, 24)
toggleLockBtn:SetPoint("LEFT", lockStateFS, "RIGHT", 14, 0)
toggleLockBtn:SetScript("OnClick", function()
    ShodoQoLDB.prescienceTracker.locked = not ShodoQoLDB.prescienceTracker.locked
    RefreshLockState()
end)

-- ── Scale & Opacity ───────────────────────────────────────────────────
local sDiv1 = sp:CreateTexture(nil, "ARTWORK")
sDiv1:SetPoint("TOPLEFT", lockStateFS, "BOTTOMLEFT", 0, -22)
sDiv1:SetSize(560, 1)
sDiv1:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local appearanceLabelFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
appearanceLabelFS:SetPoint("TOPLEFT", sDiv1, "BOTTOMLEFT", 0, -14)
appearanceLabelFS:SetText("Appearance")

-- Scale  0.5 – 2.0  step 0.05
local scaleSlider, scaleValueFS, _, scaleSliderC = MakeSlider(sp, "Scale", 0.5, 2.0, 0.05,
                                                               appearanceLabelFS, -10)
scaleSlider:SetScript("OnValueChanged", function(self, val)
    val = math.floor(val / 0.05 + 0.5) * 0.05
    scaleValueFS:SetText(string.format("%.2fx", val))
    ShodoQoLDB.prescienceTracker.scale = val
    hud:SetScale(val)
end)

-- Opacity  0.1 – 1.0  step 0.05
local opacitySlider, opacityValueFS, _, opacitySliderC = MakeSlider(sp, "Opacity", 0.0, 1.0, 0.05,
                                                                      scaleSliderC, -20)
opacitySlider:SetScript("OnValueChanged", function(self, val)
    val = math.floor(val / 0.05 + 0.5) * 0.05
    opacityValueFS:SetText(string.format("%d%%", math.floor(val * 100 + 0.5)))
    ShodoQoLDB.prescienceTracker.opacity = val
    ApplyHudOpacity(val)
end)

-- Restore slider positions from DB whenever the sub-page opens
sp:SetScript("OnShow", function()
    local db = ShodoQoLDB.prescienceTracker
    scaleSlider:SetValue(db.scale or 1.0)
    opacitySlider:SetValue(db.opacity or 1.0)
end)

-- ── Preview ───────────────────────────────────────────────────────────
local sDiv2 = sp:CreateTexture(nil, "ARTWORK")
sDiv2:SetPoint("TOPLEFT", opacitySliderC, "BOTTOMLEFT", 0, -14)
sDiv2:SetSize(560, 1)
sDiv2:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local previewLabelFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
previewLabelFS:SetPoint("TOPLEFT", sDiv2, "BOTTOMLEFT", 0, -14)
previewLabelFS:SetText("Preview")

local previewHintFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
previewHintFS:SetPoint("TOPLEFT", previewLabelFS, "BOTTOMLEFT", 0, -5)
previewHintFS:SetText("|cff888888Force-show the HUD to reposition it (unlock first).|r")

local showBtn = ShodoQoL.CreateButton(sp, "Show HUD", 100, 24)
showBtn:SetPoint("TOPLEFT", previewHintFS, "BOTTOMLEFT", 0, -10)
showBtn:SetScript("OnClick", function() hud:Show() end)

local hideBtn = ShodoQoL.CreateButton(sp, "Hide HUD", 100, 24)
hideBtn:SetPoint("LEFT", showBtn, "RIGHT", 8, 0)
hideBtn:SetScript("OnClick", function() UpdateVisibility() end)

-- ── Legend ────────────────────────────────────────────────────────────
local sDiv3 = sp:CreateTexture(nil, "ARTWORK")
sDiv3:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -22)
sDiv3:SetSize(560, 1)
sDiv3:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local infoFS = sp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
infoFS:SetPoint("TOPLEFT", sDiv3, "BOTTOMLEFT", 0, -14)
infoFS:SetWidth(520)
infoFS:SetJustifyH("LEFT")
infoFS:SetTextColor(0.65, 0.65, 0.65)
infoFS:SetText(
    "Targets are configured in |cff52c4afMacro Helpers|r.\n"
    .. "The HUD appears automatically once at least one Prescience target is set.\n"
    .. "Hidden automatically when not playing Augmentation Evoker.\n\n"
    .. "|cff00cc44o Green|r  Buff active (> " .. WARN_SEC .. "s)    "
    .. "|cffff9900! Orange|r  Expiring (≤ " .. WARN_SEC .. "s)    "
    .. "|cffff3333x Red|r  Missing\n"
    .. "|cff555555- Grey|r  Target not in group"
)

local subCat = Settings.RegisterCanvasLayoutSubcategory(
    ShodoQoL.rootCategory, sp, "Prescience Tracker")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("PrescienceTracker") then return end
    local db = ShodoQoLDB.prescienceTracker
    hud:ClearAllPoints()
    hud:SetPoint(db.point or "CENTER", UIParent,
                 db.relPoint or "CENTER", db.posX or 0, db.posY or -200)
    hud:SetScale(db.scale or 1.0)
    ApplyHudOpacity(db.opacity or 1.0)
    RefreshLockState()
    FullRefresh()
end)
