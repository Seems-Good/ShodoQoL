-- ShodoQoL/ShoStats.lua
-- Live secondary stat percentages display.
-- DB lives at ShodoQoLDB.shoStats (defaults registered in Core.lua).
-- statOrder is the single source of truth: visible = in the array,
-- display order = array order. Checking a stat appends it to the end.

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ROW_H    = 16
local PAD_X    = 8
local PAD_Y    = 7
local FRAME_W  = 118
local BOLD_FONT = "Fonts\\FRIZQT__.TTF"
local BOLD_SIZE = 9
local BOLD_FLAG = "OUTLINE"

local ALL_STATS = {
    { id="crit",  label="Crit",  r=1.00, g=0.82, b=0.00, isPct=true  },
    { id="haste", label="Haste", r=0.35, g=1.00, b=0.35, isPct=true  },
    { id="mast",  label="Mast",  r=0.20, g=0.80, b=1.00, isPct=true  },
    { id="vers",  label="Vers",  r=0.85, g=0.40, b=1.00, isPct=true  },
    { id="leech", label="Leech", r=1.00, g=0.30, b=0.30, isPct=true  },
    { id="main",  label="???",   r=0.90, g=0.90, b=0.90, isPct=false },
}

local STAT_BY_ID = {}
for _, s in ipairs(ALL_STATS) do STAT_BY_ID[s.id] = s end

------------------------------------------------------------------------
-- DB accessor (safe: returns nil before OnReady)
------------------------------------------------------------------------
local function db() return ShodoQoLDB and ShodoQoLDB.shoStats end

------------------------------------------------------------------------
-- Stat readers
------------------------------------------------------------------------
local function ReadCrit()
    if GetCritChance then return GetCritChance() end
    if C_Stats and C_Stats.GetCritChance then return C_Stats.GetCritChance() end
    return 0
end
local function ReadHaste()
    if GetHaste then return GetHaste() end
    if C_Stats and C_Stats.GetHaste then return C_Stats.GetHaste() end
    return 0
end
local function ReadMastery()
    if GetMastery then return GetMastery() end
    if C_Stats and C_Stats.GetMastery then return C_Stats.GetMastery() end
    return 0
end
local function ReadVers()
    if GetVersatilityBonus then
        return GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE or 40)
    end
    if GetCombatRatingBonus then
        return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE or 40)
    end
    if C_Stats and C_Stats.GetVersatility then return C_Stats.GetVersatility() end
    return 0
end
local function ReadLeech()
    if GetLifesteal then return GetLifesteal() end
    if C_Stats and C_Stats.GetLifesteal then return C_Stats.GetLifesteal() end
    return 0
end

local mainLabel = "???"
local function ReadMain()
    local str = UnitStat("player", 1) or 0
    local agi = UnitStat("player", 2) or 0
    local int = UnitStat("player", 4) or 0
    if str >= agi and str >= int then mainLabel = "Str" ; return str
    elseif agi >= int            then mainLabel = "Agi" ; return agi
    else                              mainLabel = "Int" ; return int end
end

local READERS = {
    crit=ReadCrit, haste=ReadHaste, mast=ReadMastery,
    vers=ReadVers, leech=ReadLeech, main=ReadMain,
}

------------------------------------------------------------------------
-- Display frame
------------------------------------------------------------------------
local BG_R,  BG_G,  BG_B,  BG_A  = 0.04, 0.04, 0.07, 0.76
local BDR_R, BDR_G, BDR_B, BDR_A = 0.22, 0.22, 0.28, 0.90

local frame = CreateFrame("Frame", "ShoStatsFrame", UIParent, "BackdropTemplate")
frame:SetSize(FRAME_W, 20)
frame:SetFrameStrata("MEDIUM")
frame:SetFrameLevel(10)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets   = { left=1, right=1, top=1, bottom=1 },
})
frame:SetBackdropColor(BG_R, BG_G, BG_B, BG_A)
frame:SetBackdropBorderColor(BDR_R, BDR_G, BDR_B, BDR_A)

local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
header:SetPoint("BOTTOM", frame, "TOP", 0, 3)
header:SetTextColor(0.20, 0.58, 0.50, 0.90)   -- evoker green
header:SetText("ShoStats")

-- Pre-create one label+value pair per stat. Shown/hidden by RebuildFrame.
-- Alpha pinned to 1 on both so opacity setting never dims stat values.
local rows = {}
for _, s in ipairs(ALL_STATS) do
    local lbl = frame:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(BOLD_FONT, BOLD_SIZE, BOLD_FLAG)
    lbl:SetTextColor(s.r * 0.80, s.g * 0.80, s.b * 0.80, 1)
    lbl:SetText(s.label) ; lbl:Hide()

    local val = frame:CreateFontString(nil, "OVERLAY")
    val:SetFont(BOLD_FONT, BOLD_SIZE, BOLD_FLAG)
    val:SetTextColor(s.r, s.g, s.b, 1)
    val:SetText("--") ; val:Hide()

    rows[s.id] = { lbl=lbl, val=val, cached=-1 }
end

------------------------------------------------------------------------
-- RebuildFrame
-- statOrder is the visible ordered list. Only stats in that array show.
------------------------------------------------------------------------
local function RebuildFrame()
    local order = db() and db().statOrder or {}
    frame:SetHeight(PAD_Y * 2 + #order * ROW_H)

    -- Hide all rows first, then show only ordered ones
    for _, s in ipairs(ALL_STATS) do
        rows[s.id].lbl:Hide()
        rows[s.id].val:Hide()
    end

    for i, id in ipairs(order) do
        local r = rows[id]
        if r then
            local yOff = -(PAD_Y + (i - 1) * ROW_H + ROW_H * 0.5)
            r.lbl:ClearAllPoints()
            r.lbl:SetPoint("LEFT",  frame, "TOPLEFT",  PAD_X,  yOff)
            r.lbl:Show()
            r.val:ClearAllPoints()
            r.val:SetPoint("RIGHT", frame, "TOPRIGHT", -PAD_X, yOff)
            r.val:Show()
            r.cached = -1
        end
    end
end

------------------------------------------------------------------------
-- UpdateStats — only redraws FontStrings whose value changed
------------------------------------------------------------------------
local fmtPct = "%.2f%%"
local fmtInt = "%d"

local function UpdateStats()
    local order = db() and db().statOrder or {}
    for _, id in ipairs(order) do
        local s = STAT_BY_ID[id]
        local r = rows[id]
        if s and r then
            local val = READERS[id]()
            if id == "main" and mainLabel ~= s.label then
                s.label = mainLabel
                r.lbl:SetText(mainLabel)
                r.cached = -1
            end
            if val ~= r.cached then
                r.cached = val
                r.val:SetText(s.isPct and format(fmtPct, val) or format(fmtInt, val))
            end
        end
    end
end

------------------------------------------------------------------------
-- Gate frame — zero OnUpdate cost at rest
------------------------------------------------------------------------
local gateFrame = CreateFrame("Frame")
local updateDue = false
gateFrame:Hide()
gateFrame:SetScript("OnUpdate", function(self)
    if updateDue then updateDue = false ; UpdateStats() end
    self:Hide()
end)

local function QueueUpdate()
    updateDue = true
    gateFrame:Show()
end

------------------------------------------------------------------------
-- Apply helpers
------------------------------------------------------------------------
local function ApplyLock(locked)
    db().locked = locked
    frame:EnableMouse(not locked)
end

local function ApplyScale(s)
    db().scale = s
    frame:SetScale(s)
end

local function ApplyOpacity(a)
    db().opacity = a
    frame:SetBackdropColor(BG_R, BG_G, BG_B, BG_A * a)
    frame:SetBackdropBorderColor(BDR_R, BDR_G, BDR_B, BDR_A * a)
    header:SetAlpha(a)
end

------------------------------------------------------------------------
-- Stat events (registered on a plain frame, not the display frame)
------------------------------------------------------------------------
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("PLAYER_LOGOUT")
evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evtFrame:RegisterEvent("COMBAT_RATING_UPDATE")
evtFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
evtFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- Scoped to "player" so these don't fire for every raid member's buff changes.
evtFrame:RegisterUnitEvent("UNIT_STATS", "player")
evtFrame:RegisterUnitEvent("UNIT_AURA",  "player")

evtFrame:SetScript("OnEvent", function(_, event, arg1)
    if not db() then return end   -- guard before OnReady

    if event == "PLAYER_LOGOUT" then
        local pt, _, rpt, x, y = frame:GetPoint(1)
        if pt then
            db().point, db().relTo, db().relPt = pt, "UIParent", rpt
            db().x, db().y = x, y
        end
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        rows["main"].cached = -1
    end

    -- UNIT_STATS and UNIT_AURA are scoped to "player" via RegisterUnitEvent;
    -- no arg1 guard needed.
    QueueUpdate()
end)

frame:SetScript("OnDragStart", function(self)
    if db() and not db().locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

------------------------------------------------------------------------
-- Settings panel  (canvas subcategory, Evoker theme)
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "ShoStats"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()

-- ── Helpers ──────────────────────────────────────────────────────────
local function Div(anchor, offY, alpha)
    local d = panel:CreateTexture(nil, "ARTWORK")
    d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY or -12)
    d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY or -12)
    d:SetHeight(1)
    d:SetColorTexture(0.20, 0.58, 0.50, alpha or 0.45)
    return d
end

local function CreateCleanSlider(name, minVal, maxVal, step)
    local c = CreateFrame("Frame", nil, panel)
    c:SetSize(320, 36) ; c:EnableMouse(false)
    local track = c:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 10, 0) ; track:SetPoint("RIGHT", -10, 0)
    track:SetHeight(6) ; track:SetColorTexture(0.06, 0.18, 0.16, 0.90)
    local shine = c:CreateTexture(nil, "BORDER")
    shine:SetPoint("LEFT", 10, 1) ; shine:SetPoint("RIGHT", -10, 1)
    shine:SetHeight(2) ; shine:SetColorTexture(0.20, 0.68, 0.58, 0.40)
    local s = CreateFrame("Slider", name, c)
    s:SetAllPoints() ; s:EnableMouse(true) ; s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minVal, maxVal) ; s:SetValueStep(step) ; s:SetObeyStepOnDrag(true)
    local thumbBorder = s:CreateTexture(nil, "OVERLAY")
    thumbBorder:SetSize(18, 26) ; thumbBorder:SetColorTexture(0.04, 0.12, 0.10, 1)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 22) ; thumb:SetColorTexture(0.25, 0.78, 0.66, 1)
    thumb:SetDrawLayer("OVERLAY", 1)
    thumbBorder:SetPoint("CENTER", thumb, "CENTER", 0, 0)
    s:SetThumbTexture(thumb)
    c.slider = s
    return c
end

-- ── Header ───────────────────────────────────────────────────────────
local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fSho|r|cff52c4afStats|r")

local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Live secondary stat percentages — works in combat|r")

local div0 = Div(subFS, -12, 0.60)

-- ── Scale ────────────────────────────────────────────────────────────
local scaleLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
scaleLabelFS:SetPoint("TOPLEFT", div0, "BOTTOMLEFT", 0, -16)
scaleLabelFS:SetText("Frame Scale")

local scaleValueFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleValueFS:SetPoint("LEFT", scaleLabelFS, "RIGHT", 10, 0)
scaleValueFS:SetText("1.00x")

local scaleSliderC = CreateCleanSlider("ShoStatsScaleSlider", 0.5, 2.0, 0.05)
scaleSliderC:SetPoint("TOPLEFT", scaleLabelFS, "BOTTOMLEFT", 0, -16)
local scaleSlider = scaleSliderC.slider
scaleSlider:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / 0.05 + 0.5) * 0.05
    scaleValueFS:SetText(string.format("%.2fx", v))
    if db() then ApplyScale(v) end
end)

local div1 = Div(scaleSliderC, -14, 0.30)

-- ── Opacity ──────────────────────────────────────────────────────────
local opacityLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
opacityLabelFS:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -16)
opacityLabelFS:SetText("Opacity  |cff888888(backdrop + title only — stats always opaque)|r")

local opacityValueFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
opacityValueFS:SetPoint("LEFT", opacityLabelFS, "RIGHT", 10, 0)
opacityValueFS:SetText("1.00")

local opacitySliderC = CreateCleanSlider("ShoStatsOpacitySlider", 0.0, 1.0, 0.05)
opacitySliderC:SetPoint("TOPLEFT", opacityLabelFS, "BOTTOMLEFT", 0, -16)
local opacitySlider = opacitySliderC.slider
opacitySlider:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / 0.05 + 0.5) * 0.05
    opacityValueFS:SetText(string.format("%.2f", v))
    if db() then ApplyOpacity(v) end
end)

local div2 = Div(opacitySliderC, -14, 0.30)

-- ── Position ─────────────────────────────────────────────────────────
local posLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
posLabelFS:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -16)
posLabelFS:SetText("Frame Position")

local lockBtn = ShodoQoL.CreateButton(panel, "Lock Position", 120, 26)
lockBtn:SetPoint("TOPLEFT", posLabelFS, "BOTTOMLEFT", 0, -10)
lockBtn:SetScript("OnClick", function() ApplyLock(true)  end)

local unlockBtn = ShodoQoL.CreateButton(panel, "Unlock Position", 130, 26)
unlockBtn:SetPoint("LEFT", lockBtn, "RIGHT", 8, 0)
unlockBtn:SetScript("OnClick", function() ApplyLock(false) end)

local resetPosBtn = ShodoQoL.CreateButton(panel, "Reset Position", 120, 26)
resetPosBtn:SetPoint("LEFT", unlockBtn, "RIGHT", 8, 0)
resetPosBtn:SetScript("OnClick", function()
    if not db() then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    db().x, db().y = 0, 200
    print("|cff33937fShodoQoL|r ShoStats: position reset.")
end)

local posHintFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
posHintFS:SetPoint("TOPLEFT", lockBtn, "BOTTOMLEFT", 2, -6)
posHintFS:SetTextColor(0.55, 0.55, 0.55)
posHintFS:SetText("Drag the ShoStats frame while unlocked to reposition it.")

local div3 = Div(posHintFS, -16, 0.45)

-- ── Visible Stats ────────────────────────────────────────────────────
-- Checkboxes. statOrder is the visible+ordered list.
-- Check  → append id to statOrder end.
-- Uncheck → remove id from statOrder.
local visLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
visLabelFS:SetPoint("TOPLEFT", div3, "BOTTOMLEFT", 0, -16)
visLabelFS:SetText("Visible Stats  |cff888888(check order = display order)|r")

local COL_W = 185
local CB_H  = 24
local checkboxes = {}

for i, s in ipairs(ALL_STATS) do
    local col  = (i - 1) % 2
    local row  = math.floor((i - 1) / 2)
    local cb   = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", visLabelFS, "BOTTOMLEFT",
        col * COL_W - 2,
        -(row * CB_H + 6))
    if s.id == "main" then
        cb.text:SetText("|cffe6e6e6Main Stat|r  |cff888888(Str/Agi/Int)|r")
    else
        cb.text:SetTextColor(s.r, s.g, s.b)
        cb.text:SetText(s.label)
    end

    local sid = s.id
    cb:SetScript("OnClick", function(self)
        if not db() then return end
        local order = db().statOrder
        if self:GetChecked() then
            -- Append to end — "last checked = bottom of display"
            local already = false
            for _, id in ipairs(order) do
                if id == sid then already = true ; break end
            end
            if not already then order[#order + 1] = sid end
        else
            -- Remove from order
            for j = #order, 1, -1 do
                if order[j] == sid then table.remove(order, j) ; break end
            end
        end
        RebuildFrame()
        QueueUpdate()
    end)
    checkboxes[sid] = cb
end

local numRows  = math.ceil(#ALL_STATS / 2)
local div4     = Div(visLabelFS, -(numRows * CB_H + 20), 0.30)

-- ── Reset Stats button ───────────────────────────────────────────────
local resetStatsBtn = ShodoQoL.CreateButton(panel, "Reset to All Stats", 148, 26)
resetStatsBtn:SetPoint("TOPLEFT", div4, "BOTTOMLEFT", 0, -14)
resetStatsBtn:SetScript("OnClick", function()
    if not db() then return end
    db().statOrder = {"crit","haste","mast","vers","leech","speed","main"}
    -- Sync checkboxes
    for _, s in ipairs(ALL_STATS) do
        if checkboxes[s.id] then checkboxes[s.id]:SetChecked(true) end
    end
    RebuildFrame() ; QueueUpdate()
end)

-- Register subcategory
local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "ShoStats")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Slash commands  (/sho  /shostats)
------------------------------------------------------------------------
SLASH_SHOSTATS1 = "/sho"
SLASH_SHOSTATS2 = "/shostats"
SlashCmdList["SHOSTATS"] = function(msg)
    local cmd = strtrim(msg):lower()
    if not db() then return end

    if cmd == "lock" then
        ApplyLock(true)
        print("|cff33937fShodoQoL|r ShoStats: frame locked.")
    elseif cmd == "unlock" then
        ApplyLock(false)
        print("|cff33937fShodoQoL|r ShoStats: frame unlocked.")
    elseif cmd == "hide" then
        db().shown = false ; frame:Hide()
        print("|cff33937fShodoQoL|r ShoStats: hidden — /sho show to restore.")
    elseif cmd == "show" then
        db().shown = true ; frame:Show() ; QueueUpdate()
    elseif cmd:match("^scale%s+") then
        local v = tonumber(cmd:match("^scale%s+(.+)"))
        if v and v >= 0.5 and v <= 2.0 then ApplyScale(v)
        else print("|cff33937fShodoQoL|r ShoStats: scale must be 0.5 – 2.0") end
    elseif cmd == "reset" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        ApplyScale(1.0) ; db().x, db().y = 0, 200
        print("|cff33937fShodoQoL|r ShoStats: position reset.")
    else
        print("|cff33937fShodoQoL|r ShoStats commands:")
        print("  |cffffd700/sho lock|r / |cffffd700unlock|r  — toggle drag lock")
        print("  |cffffd700/sho show|r / |cffffd700hide|r    — toggle visibility")
        print("  |cffffd700/sho scale 1.2|r       — resize (0.5 – 2.0)")
        print("  |cffffd700/sho reset|r             — reset to default position")
    end
end

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("ShoStats") then return end

    local d = db()

    -- BackFill in Core merges arrays by index, so removed stats get re-injected
    -- from the defaults on every reload. Sanitize here: keep only known ids,
    -- deduplicate, preserve the order the player set.
    do
        local clean, seen = {}, {}
        for _, id in ipairs(d.statOrder) do
            if STAT_BY_ID[id] and not seen[id] then
                clean[#clean + 1] = id
                seen[id] = true
            end
        end
        d.statOrder = clean
    end

    -- Apply saved settings to the display frame
    frame:SetScale(d.scale)
    ApplyOpacity(d.opacity)
    frame:ClearAllPoints()
    frame:SetPoint(d.point, d.relTo, d.relPt, d.x, d.y)
    ApplyLock(d.locked)
    if not d.shown then frame:Hide() end

    -- Sync panel sliders
    scaleSlider:SetValue(d.scale)
    opacitySlider:SetValue(d.opacity)

    -- Sync checkboxes to statOrder membership
    local inOrder = {}
    for _, id in ipairs(d.statOrder) do inOrder[id] = true end
    for _, s in ipairs(ALL_STATS) do
        if checkboxes[s.id] then
            checkboxes[s.id]:SetChecked(inOrder[s.id] == true)
        end
    end

    RebuildFrame()
    QueueUpdate()
end)
