-- ShodoQoL/HoverTracker.lua
-- Evoker Hover state tracker: glows behind cast bar + essence bar.
-- Reads/writes ShodoQoLDB.hoverTracker.
--
-- MIDNIGHT AURA RESTRICTION:
--   C_UnitAuras.GetPlayerAuraBySpellID() is secret in combat.
--   Hover is detected via UNIT_SPELLCAST_SUCCEEDED (own casts are never secret).

local HOVER_SPELL         = 358267
local HOVER_BASE_DURATION = 10
local HOVER_WARN_BEFORE   = 3
local PLAYER              = "player"
local EVOKER_CLASS        = "EVOKER"



-- ---------------------------------------------------------------------------
-- States
-- ---------------------------------------------------------------------------
local S = {
    IDLE            = "IDLE",
    CASTING         = "CASTING",
    HOVERING        = "HOVERING",
    HOVER_WARNING   = "HOVER_WARNING",
    HOVER_CASTING   = "HOVER_CASTING",
    HOVER_CAST_WARN = "HOVER_CAST_WARN",
}

local SIG = {
    HOVER_GAINED  = "HOVER_GAINED",
    HOVER_WARNING = "HOVER_WARNING",
    HOVER_LOST    = "HOVER_LOST",
    CAST_START    = "CAST_START",
    CAST_END      = "CAST_END",
}

local TRANSITIONS = {
    [S.IDLE]            = { [SIG.HOVER_GAINED]  = S.HOVERING,       [SIG.CAST_START]    = S.CASTING         },
    [S.CASTING]         = { [SIG.HOVER_GAINED]  = S.HOVER_CASTING,  [SIG.CAST_END]      = S.IDLE            },
    [S.HOVERING]        = { [SIG.HOVER_WARNING] = S.HOVER_WARNING,  [SIG.HOVER_GAINED]  = S.HOVERING,
                            [SIG.HOVER_LOST]    = S.IDLE,           [SIG.CAST_START]    = S.HOVER_CASTING   },
    [S.HOVER_WARNING]   = { [SIG.HOVER_GAINED]  = S.HOVERING,       [SIG.HOVER_LOST]    = S.IDLE,
                            [SIG.CAST_START]    = S.HOVER_CAST_WARN                                         },
    [S.HOVER_CASTING]   = { [SIG.HOVER_WARNING] = S.HOVER_CAST_WARN,[SIG.HOVER_GAINED]  = S.HOVER_CASTING,
                            [SIG.HOVER_LOST]    = S.CASTING,        [SIG.CAST_END]      = S.HOVERING        },
    [S.HOVER_CAST_WARN] = { [SIG.HOVER_GAINED]  = S.HOVER_CASTING,  [SIG.HOVER_LOST]    = S.CASTING,
                            [SIG.CAST_END]      = S.HOVER_WARNING                                           },
}

-- =============================================================================
-- FSM
-- =============================================================================
local FSM = {}
FSM.__index = FSM

function FSM.New(initialState, onTransition)
    return setmetatable({ state = initialState, onTransition = onTransition }, FSM)
end

function FSM:State() return self.state end

function FSM:Send(signal)
    local row       = TRANSITIONS[self.state]
    local nextState = row and row[signal]
    if not nextState then return end
    local prev   = self.state
    self.state   = nextState
    if self.onTransition then self.onTransition(prev, signal, nextState) end
end

-- =============================================================================
-- UI
-- =============================================================================
local COL = {
    free   = { 0.18, 0.92, 0.38 },
    warn   = { 1.00, 0.78, 0.00 },
    locked = { 0.90, 0.18, 0.12 },
}

local STATE_COL = {
    [S.IDLE]            = COL.locked,
    [S.CASTING]         = COL.locked,
    [S.HOVERING]        = COL.free,
    [S.HOVER_CASTING]   = COL.free,
    [S.HOVER_WARNING]   = COL.warn,
    [S.HOVER_CAST_WARN] = COL.warn,
}

local UI = {}

local function FindEssenceBar()
    local tries = { "EssencePlayerFrame", "PlayerFrame.classResources", "PlayerFrame.classbar" }
    for _, name in ipairs(tries) do
        local f = _G[name]
        if f and f.GetWidth and f:GetWidth() > 0 then return f end
    end
    return PlayerFrame
end

local function FindCastBar()
    local tries = { "PlayerCastingBarFrame", "CastingBarFrame" }
    for _, name in ipairs(tries) do
        local f = _G[name]
        if f then return f end
    end
    return PlayerFrame
end

local function MakeGlowFrame(name, parent, anchor, bleedX, bleedY, subLevel)
    local f = CreateFrame("Frame", name, parent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(subLevel or 1)
    local w = math.max(anchor:GetWidth(),  10) + bleedX * 2
    local h = math.max(anchor:GetHeight(), 10) + bleedY * 2
    f:SetSize(w, h)
    f:SetPoint("CENTER", anchor, "CENTER", 0, 0)

    local bloom = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    bloom:SetAllPoints(f)
    bloom:SetColorTexture(1, 1, 1, 0)

    local core = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    core:SetPoint("TOPLEFT",     f, "TOPLEFT",      5, -5)
    core:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5,  5)
    core:SetColorTexture(1, 1, 1, 0)

    return f, bloom, core
end

function UI.Build()
    local db      = ShodoQoLDB.hoverTracker
    local castBar = FindCastBar()
    local essBar  = FindEssenceBar()

    -- Cast bar glow: parented to castBar so it auto-hides with it
    local castRoot, castBloom, castCore =
        MakeGlowFrame("HoverTrackerCastGlow", castBar, castBar, 10, 10, 2)
    UI.castRoot  = castRoot
    UI.castBloom = castBloom
    UI.castCore  = castCore

    local ag   = castRoot:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1.0)
    fade:SetToAlpha(0.15)
    fade:SetDuration(0.50)
    fade:SetSmoothing("IN_OUT")
    UI.pulseAnim = ag

    -- Essence glow: parented to UIParent; shown/hidden by us
    local essRoot, essBloom, _ =
        MakeGlowFrame("HoverTrackerEssGlow", UIParent, essBar, db.essBleedX, db.essBleedY, 1)
    UI.essRoot  = essRoot
    UI.essBloom = essBloom
    essRoot:Hide()

    UI.castBar   = castBar
    UI.essBar    = essBar
    UI.built     = true
end

-- Apply all DB-driven visual properties — called after build and from every slider
function UI.ApplySettings()
    if not UI.built then return end
    local db = ShodoQoLDB.hoverTracker

    -- Essence glow size — always recalculated from UI.essBar so that whichever
    -- frame is currently the active anchor (original bar or modern bar) is used.
    local bX = db.essBleedX
    local bY = db.essBleedY
    local w  = math.max(UI.essBar:GetWidth(),  10) + bX * 2
    local h  = math.max(UI.essBar:GetHeight(), 10) + bY * 2
    UI.essRoot:SetSize(w, h)

    -- Refresh glow colours with updated opacities
    if HoverTracker and HoverTracker.fsm then
        UI.Update(HoverTracker.fsm:State())
    end
end

function UI.Update(state)
    if not UI.built then return end
    local c = STATE_COL[state]
    if not c then return end
    local r, g, b    = c[1], c[2], c[3]
    local db         = ShodoQoLDB.hoverTracker
    local castAlpha  = db.castOpacity
    local essAlpha   = db.essOpacity

    UI.castBloom:SetColorTexture(r, g, b, 0.70 * castAlpha)
    UI.castCore:SetColorTexture( r, g, b, 1.00 * castAlpha)

    local hoverActive = (state == S.HOVERING     or state == S.HOVER_CASTING
                      or state == S.HOVER_WARNING or state == S.HOVER_CAST_WARN)
    if hoverActive then
        UI.essRoot:Show()
        UI.essBloom:SetColorTexture(r, g, b, 0.55 * essAlpha)
    else
        UI.essRoot:Hide()
    end

    local warning = (state == S.HOVER_WARNING or state == S.HOVER_CAST_WARN)
    if warning then
        if not UI.pulseAnim:IsPlaying() then UI.pulseAnim:Play() end
    else
        if UI.pulseAnim:IsPlaying() then
            UI.pulseAnim:Stop()
            UI.castRoot:SetAlpha(1)
        end
    end
end

-- =============================================================================
-- Module table (global so UI.ApplySettings can reference back to it)
-- =============================================================================
HoverTracker = {}
HoverTracker.hoverTimer    = nil
HoverTracker.warnTimer     = nil
HoverTracker.hoverDuration = HOVER_BASE_DURATION

------------------------------------------------------------------------
-- SetEssenceAnchor
-- Called by EssenceMover whenever it redirects the HoverTracker essence
-- glow to a different frame (e.g. switching between the custom modern bar
-- and the original EssencePlayerFrame).
--
-- Updating UI.essBar here is the critical step: without it,
-- UI.ApplySettings() keeps recalculating the glow size from the stale
-- original-bar dimensions and silently overwrites whatever EssenceMover
-- set — making the HoverTracker height/width padding sliders appear to
-- "reset" every time a position-apply or spec-change fires.
------------------------------------------------------------------------
function HoverTracker.SetEssenceAnchor(anchor)
    if not UI.built or not anchor then return end
    UI.essBar = anchor
    -- Recalculate size from the new anchor's dimensions + saved bleed values.
    UI.ApplySettings()
    -- Re-anchor the glow frame's CENTER to the new frame.
    UI.essRoot:ClearAllPoints()
    UI.essRoot:SetPoint("CENTER", anchor, "CENTER", 0, 0)
end

function HoverTracker:CancelTimers()
    if self.hoverTimer then self.hoverTimer:Cancel(); self.hoverTimer = nil end
    if self.warnTimer  then self.warnTimer:Cancel();  self.warnTimer  = nil end
end

function HoverTracker:StartHoverTimers(duration)
    self:CancelTimers()
    local dur       = duration or self.hoverDuration
    local warnDelay = dur - HOVER_WARN_BEFORE
    if warnDelay > 0 then
        self.warnTimer = C_Timer.NewTimer(warnDelay, function()
            self.warnTimer = nil
            self.fsm:Send(SIG.HOVER_WARNING)
        end)
    else
        self.fsm:Send(SIG.HOVER_WARNING)
    end
    self.hoverTimer = C_Timer.NewTimer(dur, function()
        self.hoverTimer = nil
        self.fsm:Send(SIG.HOVER_LOST)
    end)
end

local function SafeGetHoverAura()
    local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, HOVER_SPELL)
    if ok and result then return result end
    return nil
end


function HoverTracker:SyncAuraOutOfCombat()
    local aura = SafeGetHoverAura()
    if aura then
        if aura.duration and aura.duration > 0 then
            self.hoverDuration = aura.duration
        end
        self.fsm:Send(SIG.HOVER_GAINED)
    else
        self.fsm:Send(SIG.HOVER_LOST)
    end
end

function HoverTracker:OnEvent(event, unitID, ...)
    if event == "UNIT_AURA" then
        if unitID ~= PLAYER then return end
        if not InCombatLockdown() then self:SyncAuraOutOfCombat() end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unitID ~= PLAYER then return end
        local spellID = select(2, ...)
        if spellID == HOVER_SPELL then
            self:StartHoverTimers()
            self.fsm:Send(SIG.HOVER_GAINED)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Out of combat: API is readable again, resync everything.
        self:CancelTimers()
        self:SyncAuraOutOfCombat()

    elseif event == "UNIT_SPELLCAST_START" then
        if unitID ~= PLAYER then return end
        self.fsm:Send(SIG.CAST_START)

    elseif event == "UNIT_SPELLCAST_STOP"
        or  event == "UNIT_SPELLCAST_FAILED"
        or  event == "UNIT_SPELLCAST_INTERRUPTED" then
        if unitID ~= PLAYER then return end
        self.fsm:Send(SIG.CAST_END)

    end
end

-- =============================================================================
-- Settings sub-page
-- Uses UIPanelScrollFrameTemplate — same pattern as SourceOfMagic.lua
-- =============================================================================
local function CreateSlider(parent, name, minVal, maxVal, step)
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

local function Div(parent, anchor, offY)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
    d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY)
    d:SetHeight(1)
    d:SetColorTexture(0.20, 0.58, 0.50, 0.35)
    return d
end

-- Outer panel registered with Settings API
local panel = CreateFrame("Frame")
panel.name   = "Hover Tracker"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()

-- ScrollFrame fills the canvas; scrollbar on the right (matches SourceOfMagic pattern)
local scrollFrame = CreateFrame("ScrollFrame", "HoverTrackerScroll", panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",      4,  -4)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26,  4)

local c = CreateFrame("Frame", nil, scrollFrame)  -- "c" = content child
c:SetWidth(scrollFrame:GetWidth() or 560)
c:SetHeight(800)   -- tall enough for all sections
scrollFrame:SetScrollChild(c)

scrollFrame:SetScript("OnSizeChanged", function(self)
    c:SetWidth(self:GetWidth())
end)

panel:SetScript("OnShow", function()
    scrollFrame:SetVerticalScroll(0)
end)

local W = 540   -- usable content width

-- ── Header ────────────────────────────────────────────────────────────────────
local titleFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fHover|r|cff52c4afTracker|r")

local subFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Glows green when Hover lets you move and cast freely — Evoker only|r")

local div0 = Div(c, subFS, -12)

local div1 = Div(c, subFS, -12)

-- ── Essence Bar Size ──────────────────────────────────────────────────────────
local essHeaderFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
essHeaderFS:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -14)
essHeaderFS:SetText("|cff52c4afEssence Bar Glow Size|r")

local essHintFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
essHintFS:SetPoint("TOPLEFT", essHeaderFS, "BOTTOMLEFT", 0, -6)
essHintFS:SetText("|cff666666Padding added to each side of the essence bar glow in pixels|r")

local essWidthLabelFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
essWidthLabelFS:SetPoint("TOPLEFT", essHintFS, "BOTTOMLEFT", 0, -10)
essWidthLabelFS:SetText("Width Padding")
essWidthLabelFS:SetTextColor(0.62, 0.88, 0.82)

local essWidthValueFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
essWidthValueFS:SetPoint("LEFT", essWidthLabelFS, "RIGHT", 8, 0)

local essWidthContainer = CreateSlider(c, "HoverTrackerEssWidthSlider", 0, 40, 1)
essWidthContainer:SetPoint("TOPLEFT", essWidthLabelFS, "BOTTOMLEFT", 0, -14)
essWidthContainer.slider:SetScript("OnValueChanged", function(_, value)
    essWidthValueFS:SetText(value .. "px")
    if ShodoQoLDB then
        ShodoQoLDB.hoverTracker.essBleedX = value
        UI.ApplySettings()
    end
end)

local essHeightLabelFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
essHeightLabelFS:SetPoint("TOPLEFT", essWidthContainer, "BOTTOMLEFT", 0, -12)
essHeightLabelFS:SetText("Height Padding")
essHeightLabelFS:SetTextColor(0.62, 0.88, 0.82)

local essHeightValueFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
essHeightValueFS:SetPoint("LEFT", essHeightLabelFS, "RIGHT", 8, 0)

local essHeightContainer = CreateSlider(c, "HoverTrackerEssHeightSlider", 0, 40, 1)
essHeightContainer:SetPoint("TOPLEFT", essHeightLabelFS, "BOTTOMLEFT", 0, -14)
essHeightContainer.slider:SetScript("OnValueChanged", function(_, value)
    essHeightValueFS:SetText(value .. "px")
    if ShodoQoLDB then
        ShodoQoLDB.hoverTracker.essBleedY = value
        UI.ApplySettings()
    end
end)

local div2 = Div(c, essHeightContainer, -14)

-- ── Opacity ───────────────────────────────────────────────────────────────────
local opacityHeaderFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
opacityHeaderFS:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -14)
opacityHeaderFS:SetText("|cff52c4afOpacity|r")

local function MakeOpacityRow(name, label, prevAnchor, dbKey)
    local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -14)
    lbl:SetText(label)
    lbl:SetTextColor(0.62, 0.88, 0.82)

    local valFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valFS:SetPoint("LEFT", lbl, "RIGHT", 8, 0)

    local container = CreateSlider(c, name, 0, 1, 0.05)
    container:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -14)
    container.slider:SetScript("OnValueChanged", function(_, value)
        local snapped = math.floor(value / 0.05 + 0.5) * 0.05
        valFS:SetText(string.format("%d%%", math.floor(snapped * 100 + 0.5)))
        if ShodoQoLDB then
            ShodoQoLDB.hoverTracker[dbKey] = snapped
            UI.ApplySettings()
        end
    end)
    return container
end

local castOpContainer = MakeOpacityRow("HoverTrackerCastOpSlider",  "Cast Bar Glow",    opacityHeaderFS,  "castOpacity")
local essOpContainer  = MakeOpacityRow("HoverTrackerEssOpSlider",   "Essence Bar Glow", castOpContainer,  "essOpacity")

local div3 = Div(c, essOpContainer, -14)

local resetBtn = ShodoQoL.CreateButton(c, "Reset to Defaults", 130, 24)
resetBtn:SetPoint("TOPLEFT", div3, "BOTTOMLEFT", 0, -14)
resetBtn:SetScript("OnClick", function()
    local def = ShodoQoL.DEFAULTS.hoverTracker
    local db  = ShodoQoLDB.hoverTracker
    for k, v in pairs(def) do db[k] = v end
    essWidthContainer.slider:SetValue(db.essBleedX)
    essHeightContainer.slider:SetValue(db.essBleedY)
    castOpContainer.slider:SetValue(db.castOpacity)
    essOpContainer.slider:SetValue(db.essOpacity)
    UI.ApplySettings()
end)

local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "Hover Tracker")
Settings.RegisterAddOnCategory(subCat)

-- =============================================================================
-- Bootstrap
-- =============================================================================
ShodoQoL.OnReady(function()
    local _, classFile = UnitClass(PLAYER)
    if classFile ~= EVOKER_CLASS then return end
    if not ShodoQoL.IsEnabled("HoverTracker") then return end

    local db = ShodoQoLDB.hoverTracker

    -- Seed all sliders from saved DB values
    essWidthContainer.slider:SetValue(db.essBleedX)
    essHeightContainer.slider:SetValue(db.essBleedY)
    castOpContainer.slider:SetValue(db.castOpacity)
    essOpContainer.slider:SetValue(db.essOpacity)

    -- Highlight the active font button

    -- Seed FSM from live state (always safe at login — never in combat)
    local seedState = S.IDLE
    local seedAura  = (function()
        local ok, r = pcall(C_UnitAuras.GetPlayerAuraBySpellID, HOVER_SPELL)
        return ok and r or nil
    end)()
    if seedAura then
        seedState = S.HOVERING
        if seedAura.duration and seedAura.duration > 0 then
            HoverTracker.hoverDuration = seedAura.duration
        end
    end

    HoverTracker.fsm = FSM.New(seedState, function(prev, sig, next)
        if UI.built then
            UI.Update(next)
        end
    end)

    -- Phase 1: register events now
    -- Phase 2: build UI in PLAYER_ENTERING_WORLD (Blizzard frames not ready at login)
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_AURA",                  PLAYER)
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",   PLAYER)
    f:RegisterUnitEvent("UNIT_SPELLCAST_START",       PLAYER)
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP",        PLAYER)
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",      PLAYER)
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", PLAYER)
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
            UI.Build()
            UI.ApplySettings()
            UI.Update(HoverTracker.fsm:State())
        else
            HoverTracker:OnEvent(event, ...)
        end
    end)
    HoverTracker.events = f
end)
