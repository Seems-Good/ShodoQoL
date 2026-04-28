-- ShodoQoL/MacroHelpers.lua
-- Per-character macros with compact card UI and cross-realm support.
-- Reads/writes: ShodoQoLDB.spatialParadox, .prescience1, .prescience2,
--               .cauterizingFlame, .blisteringScales, .sourceOfMagic

local GLOBAL_MACRO_LIMIT = 120

------------------------------------------------------------------------
-- Shared EditBox factory
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

    eb:SetScript("OnEditFocusGained", function() border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1.0) end)
    eb:SetScript("OnEditFocusLost",   function() border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)

    return eb
end

------------------------------------------------------------------------
-- Macro Manager factory
------------------------------------------------------------------------
local function CreateMacroManager(cfg)
    local M = {}
    M.macroName = cfg.macroName
    M.macroIcon = cfg.macroIcon

    local function GetCharIndex()
        local idx = GetMacroIndexByName(cfg.macroName)
        if not idx or idx == 0 then return nil end
        return (idx > GLOBAL_MACRO_LIMIT) and idx or nil
    end

    function M.Exists()     return GetCharIndex() ~= nil end

    function M.CleanupGlobalDuplicate()
        local idx = GetMacroIndexByName(cfg.macroName)
        if idx and idx > 0 and idx <= GLOBAL_MACRO_LIMIT then DeleteMacro(idx) end
    end

    function M.BuildBody()
        local db   = ShodoQoLDB[cfg.dbKey]
        local name = db.targetName
        if not name or name == "" then return cfg.buildBody(nil) end
        local playerRealm = GetRealmName()
        local target
        if db.targetRealm and db.targetRealm ~= "" and db.targetRealm ~= playerRealm then
            target = name .. "-" .. db.targetRealm:gsub(" ", "-")
        else
            target = name
        end
        return cfg.buildBody(target)
    end

    function M.Update()
        local idx = GetCharIndex()
        if not idx then return end
        EditMacro(idx, cfg.macroName, cfg.macroIcon, M.BuildBody())
    end

    function M.GetDB() return ShodoQoLDB[cfg.dbKey] end

    return M
end

------------------------------------------------------------------------
-- Macro definitions
------------------------------------------------------------------------
local spMgr = CreateMacroManager({
    macroName = "SpatialParadox",
    macroIcon = 134400,
    dbKey     = "spatialParadox",
    buildBody = function(target)
        if not target then return "#showtooltip\n/cast Spatial Paradox(Bronze)" end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Spatial Paradox(Bronze)\n/cast Spatial Paradox(Bronze)", target)
    end,
})

local p1Mgr = CreateMacroManager({
    macroName = "Prescience1",
    macroIcon = 134400,
    dbKey     = "prescience1",
    buildBody = function(target)
        if not target then return "#showtooltip\n/cast Prescience" end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Prescience\n/cast Prescience", target)
    end,
})

local p2Mgr = CreateMacroManager({
    macroName = "Prescience2",
    macroIcon = 134400,
    dbKey     = "prescience2",
    buildBody = function(target)
        if not target then return "#showtooltip\n/cast Prescience" end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Prescience\n/cast Prescience", target)
    end,
})

local cfMgr = CreateMacroManager({
    macroName = "CauterizingFlame",
    macroIcon = 134400,
    dbKey     = "cauterizingFlame",
    buildBody = function(target)
        if not target then return "#showtooltip\n/cast Cauterizing Flame" end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Cauterizing Flame\n/cast Cauterizing Flame", target)
    end,
})

local bsMgr = CreateMacroManager({
    macroName = "BlisteringScales",
    macroIcon = 134400,
    dbKey     = "blisteringScales",
    buildBody = function(target)
        if not target then
            return "#showtooltip Blistering Scales\n/cast [nostance:1] Black Attunement\n/cast Blistering Scales"
        end
        return string.format(
            "#showtooltip Blistering Scales\n/cast [nostance:1] Black Attunement\n/cast [@%s,nodead] Blistering Scales\n/cast Blistering Scales",
            target)
    end,
})

-- Source of Magic macro: targets the healer (configured here and mirrored
-- into ShodoQoLDB.sourceOfMagic so the SoM warning module tracks the same person).
local somMgr = CreateMacroManager({
    macroName = "SourceOfMagic",
    macroIcon = 134400,
    dbKey     = "sourceOfMagic",
    buildBody = function(target)
        if not target then return "#showtooltip\n/cast Source of Magic" end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Source of Magic\n/cast Source of Magic", target)
    end,
})

------------------------------------------------------------------------
-- Notify other modules when targets change
------------------------------------------------------------------------
local function NotifyTracker()
    if ShodoQoL.PrescienceTracker then
        ShodoQoL.PrescienceTracker.OnTargetChanged()
    end
end

local function NotifySoM()
    if ShodoQoL.NotifySoMTargetChanged then
        ShodoQoL.NotifySoMTargetChanged()
    end
end

------------------------------------------------------------------------
-- Settings panel (ScrollFrame for six cards)
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "Macro Helpers"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()

-- ScrollFrame -- all cards live inside content so the panel is scrollable
local scrollFrame = CreateFrame("ScrollFrame", "ShodoQoLMacroScroll", panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",      4,  -4)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26,  4)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetWidth(scrollFrame:GetWidth() or 580)
content:SetHeight(1)   -- measured on first OnShow once all children are laid out
scrollFrame:SetScrollChild(content)
scrollFrame:SetScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)

-- Auto-size: walk all regions and child frames on first show to find the true bottom edge.
-- Self-removes after first run so it never fires again.
content:SetScript("OnShow", function(self)
    local lowest = math.huge
    for i = 1, self:GetNumRegions() do
        local b = select(i, self:GetRegions()):GetBottom()
        if b and b < lowest then lowest = b end
    end
    for i = 1, self:GetNumChildren() do
        local b = select(i, self:GetChildren()):GetBottom()
        if b and b < lowest then lowest = b end
    end
    local top = self:GetTop()
    if top and lowest ~= math.huge then
        self:SetHeight(top - lowest + 24)
    end
    self:SetScript("OnShow", nil)
end)

-- Header sits inside content so it scrolls with everything else
local titleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fMacro|r|cff52c4afHelpers|r")

local subFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Per-character macros with cross-realm support|r")

-- Mythic+ Auto and Clear All sit in the header row
local mythicAutoBtn = ShodoQoL.CreateButton(content, "Mythic+ Auto", 110, 22)
mythicAutoBtn:SetPoint("LEFT", titleFS, "RIGHT", 16, 0)

local clearAllBtn = ShodoQoL.CreateButton(content, "Clear All", 76, 22)
clearAllBtn:SetPoint("LEFT", mythicAutoBtn, "RIGHT", 6, 0)
do
    local redTint = clearAllBtn:CreateTexture(nil, "OVERLAY")
    redTint:SetAllPoints()
    redTint:SetColorTexture(0.6, 0.05, 0.05, 0.35)
    redTint:SetBlendMode("ADD")
end

local topDiv = content:CreateTexture(nil, "ARTWORK")
topDiv:SetPoint("TOPLEFT",  subFS, "BOTTOMLEFT",  0, -12)
topDiv:SetSize(560, 1)
topDiv:SetColorTexture(0.20, 0.58, 0.50, 0.6)

------------------------------------------------------------------------
-- Compact card factory
------------------------------------------------------------------------
local function BuildMacroCard(topAnchor, headingText, mgr, onTargetSet)
    local nameBox, realmBox
    local RefreshCurrentLabel

    -- Row 1: heading + status badge
    local headFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headFS:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -14)
    headFS:SetText(headingText)

    local statusFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusFS:SetPoint("LEFT", headFS, "RIGHT", 10, 0)
    statusFS:SetText("|cff888888unknown|r")

    local function RefreshStatus()
        statusFS:SetText(mgr.Exists()
            and "|cff00ff00exists|r"
            or  "|cffff4444not created|r")
    end

    -- Row 2: Create / Delete / Use Current Target
    local createBtn = ShodoQoL.CreateButton(content, "Create Macro", 100, 22)
    createBtn:SetPoint("TOPLEFT", headFS, "BOTTOMLEFT", 0, -8)
    createBtn:SetScript("OnClick", function()
        if mgr.Exists() then print("|cff33937fShodoQoL|r: Macro already exists."); return end
        mgr.CleanupGlobalDuplicate()
        local _, charCount = GetNumMacros()
        if charCount >= 18 then
            print("|cffff6060ShodoQoL|r: Per-character macro limit reached (18/18)."); return
        end
        CreateMacro(mgr.macroName, mgr.macroIcon, mgr.BuildBody(), true)
        print("|cff33937fShodoQoL|r: |cffffd100" .. mgr.macroName .. "|r created.")
        RefreshStatus()
    end)

    local deleteBtn = ShodoQoL.CreateButton(content, "Delete Macro", 100, 22)
    deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 6, 0)
    deleteBtn:SetScript("OnClick", function()
        if not mgr.Exists() then print("|cff33937fShodoQoL|r: Macro does not exist."); return end
        DeleteMacro(mgr.macroName)
        print("|cff33937fShodoQoL|r: |cffffd100" .. mgr.macroName .. "|r deleted.")
        RefreshStatus()
    end)

    local useTargetBtn = ShodoQoL.CreateButton(content, "Use Current Target", 148, 22)
    useTargetBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 14, 0)
    useTargetBtn:SetScript("OnClick", function()
        if not UnitExists("target")       then print("|cffff6060ShodoQoL|r: No target selected."); return end
        if UnitIsUnit("target", "player") then print("|cffff6060ShodoQoL|r: Can't target yourself."); return end
        if not UnitIsPlayer("target")     then print("|cffff6060ShodoQoL|r: Target is not a player."); return end
        local name, realm = UnitName("target")
        if not name then print("|cffff6060ShodoQoL|r: Could not read target name."); return end
        local db = mgr.GetDB()
        db.targetName  = name
        db.targetRealm = realm or ""
        nameBox:SetText(name); realmBox:SetText(realm or "")
        mgr.Update(); RefreshCurrentLabel()
        if onTargetSet then onTargetSet() end
        local display = (realm and realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
    end)

    -- Row 3: current target display
    local targetLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLabelFS:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -8)
    targetLabelFS:SetText("|cff888888Target:|r")

    local currentValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    currentValueFS:SetPoint("LEFT", targetLabelFS, "RIGHT", 6, 0)
    currentValueFS:SetText("|cff888888(none set)|r")

    RefreshCurrentLabel = function()
        local db = mgr.GetDB()
        if not db.targetName or db.targetName == "" then
            currentValueFS:SetText("|cff888888(none set)|r"); return
        end
        local playerRealm = GetRealmName()
        if db.targetRealm and db.targetRealm ~= "" and db.targetRealm ~= playerRealm then
            currentValueFS:SetText(string.format(
                "|cffffd100%s|r |cff888888(%s)|r", db.targetName, db.targetRealm))
        else
            currentValueFS:SetText(string.format("|cffffd100%s|r", db.targetName))
        end
    end

    -- Row 4: Name [box]  Realm [box]  [Apply]  [Clear]
    local nameLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabelFS:SetPoint("TOPLEFT", targetLabelFS, "BOTTOMLEFT", 0, -11)
    nameLabelFS:SetText("|cff52c4afName|r")

    nameBox = CreateCleanEditBox(content, 148)
    nameBox:SetPoint("LEFT", nameLabelFS, "RIGHT", 5, 0)
    nameBox:SetMaxLetters(48)

    local realmLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    realmLabelFS:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
    realmLabelFS:SetText("|cff52c4afRealm|r")

    realmBox = CreateCleanEditBox(content, 116)
    realmBox:SetPoint("LEFT", realmLabelFS, "RIGHT", 5, 0)

    local applyBtn = ShodoQoL.CreateButton(content, "Apply", 66, 22)
    applyBtn:SetPoint("LEFT", realmBox, "RIGHT", 8, 0)
    applyBtn:SetScript("OnClick", function()
        local name  = nameBox:GetText():match("^%s*(.-)%s*$")
        local realm = realmBox:GetText():match("^%s*(.-)%s*$")
        if not name or name == "" then print("|cffff6060ShodoQoL|r: Please enter a name."); return end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        local db = mgr.GetDB()
        db.targetName  = name
        db.targetRealm = realm
        mgr.Update(); RefreshCurrentLabel()
        if onTargetSet then onTargetSet() end
        local display = (realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
    end)

    local clearBtn = ShodoQoL.CreateButton(content, "Clear", 66, 22)
    clearBtn:SetPoint("LEFT", applyBtn, "RIGHT", 5, 0)
    clearBtn:SetScript("OnClick", function()
        local db = mgr.GetDB()
        db.targetName, db.targetRealm = nil, nil
        nameBox:SetText(""); realmBox:SetText("")
        mgr.Update(); RefreshCurrentLabel()
        if onTargetSet then onTargetSet() end
        print("|cff33937fShodoQoL|r: " .. mgr.macroName .. " target cleared.")
    end)

    -- Bottom divider
    local bottomDiv = content:CreateTexture(nil, "ARTWORK")
    bottomDiv:SetPoint("TOPLEFT", nameLabelFS, "BOTTOMLEFT", 0, -12)
    bottomDiv:SetSize(560, 1)
    bottomDiv:SetColorTexture(0.20, 0.58, 0.50, 0.6)

    return {
        bottomDiv           = bottomDiv,
        nameBox             = nameBox,
        realmBox            = realmBox,
        RefreshStatus       = RefreshStatus,
        RefreshCurrentLabel = RefreshCurrentLabel,
    }
end

------------------------------------------------------------------------
-- Build all cards (each anchored below the previous card's divider)
------------------------------------------------------------------------
local p1Card = BuildMacroCard(topDiv,
    "|cff33937fPrescience|r |cff52c4af1|r", p1Mgr,
    function() NotifyTracker() end)

local p2Card = BuildMacroCard(p1Card.bottomDiv,
    "|cff33937fPrescience|r |cff52c4af2|r", p2Mgr,
    function() NotifyTracker() end)

local spCard = BuildMacroCard(p2Card.bottomDiv,
    "|cff33937fSpatial|r|cff52c4afParadox|r", spMgr, nil)

local cfCard = BuildMacroCard(spCard.bottomDiv,
    "|cff33937fCauterizing|r|cff52c4afFlame|r", cfMgr, nil)

local bsCard = BuildMacroCard(cfCard.bottomDiv,
    "|cff33937fBlistering|r|cff52c4afScales|r", bsMgr, nil)

-- Source of Magic card: setting a target here also updates the SoM warning module
local somCard = BuildMacroCard(bsCard.bottomDiv,
    "|cff33937fSource|r|cff52c4afOfMagic|r", somMgr,
    function() NotifySoM() end)

------------------------------------------------------------------------
-- Mythic+ Auto
-- Assigns:
--   P1  -> first DPS
--   P2  -> second DPS
--   BS  -> tank (Blistering Scales target)
--   SoM -> healer  (Source of Magic target — mirrors into warning module)
-- In a 5-man M+ group: tank + healer + 3 DPS
------------------------------------------------------------------------
mythicAutoBtn:SetScript("OnClick", function()
    local tank, healer, dps1, dps2

    local unitPrefix = IsInRaid() and "raid" or "party"
    local unitCount  = GetNumGroupMembers()

    for i = 1, unitCount do
        local unit = unitPrefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local role = UnitGroupRolesAssigned(unit)
            local name, realm = UnitName(unit)
            if name then
                realm = realm or ""
                if role == "TANK" and not tank then
                    tank = { name = name, realm = realm }
                elseif role == "HEALER" and not healer then
                    healer = { name = name, realm = realm }
                elseif role == "DAMAGER" then
                    if not dps1 then
                        dps1 = { name = name, realm = realm }
                    elseif not dps2 then
                        dps2 = { name = name, realm = realm }
                    end
                end
            end
        end
    end

    local function ApplyTarget(mgr, card, entry, extraNotify)
        if not entry then return end
        local db = mgr.GetDB()
        db.targetName  = entry.name
        db.targetRealm = entry.realm
        card.nameBox:SetText(entry.name)
        card.realmBox:SetText(entry.realm)
        mgr.Update()
        card.RefreshCurrentLabel()
        if extraNotify then extraNotify() end
    end

    ApplyTarget(bsMgr,  bsCard,  tank,   nil)
    ApplyTarget(somMgr, somCard, healer, function() NotifySoM() end)
    ApplyTarget(p1Mgr,  p1Card,  dps1,   function() NotifyTracker() end)
    ApplyTarget(p2Mgr,  p2Card,  dps2,   function() NotifyTracker() end)

    local function fmt(e)
        if not e then return "|cffff6060none|r" end
        return (e.realm ~= "") and
            string.format("|cffffd100%s|r |cff888888(%s)|r", e.name, e.realm) or
            string.format("|cffffd100%s|r", e.name)
    end

    print(string.format(
        "|cff33937fShodoQoL|r M+ Auto: Tank(BS)=%s  Healer(SoM)=%s  DPS1(P1)=%s  DPS2(P2)=%s",
        fmt(tank), fmt(healer), fmt(dps1), fmt(dps2)))
end)

------------------------------------------------------------------------
-- Clear All
------------------------------------------------------------------------
clearAllBtn:SetScript("OnClick", function()
    local allMgrs  = { p1Mgr, p2Mgr, spMgr, cfMgr, bsMgr, somMgr }
    local allCards = { p1Card, p2Card, spCard, cfCard, bsCard, somCard }
    for i, mgr in ipairs(allMgrs) do
        local db = mgr.GetDB()
        db.targetName, db.targetRealm = nil, nil
        allCards[i].nameBox:SetText("")
        allCards[i].realmBox:SetText("")
        mgr.Update()
        allCards[i].RefreshCurrentLabel()
    end
    NotifyTracker()
    NotifySoM()
    print("|cff33937fShodoQoL|r: All macro targets cleared.")
end)

local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "Macro Helpers")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("MacroHelpers") then return end

    spMgr.CleanupGlobalDuplicate()
    p1Mgr.CleanupGlobalDuplicate()
    p2Mgr.CleanupGlobalDuplicate()
    cfMgr.CleanupGlobalDuplicate()
    bsMgr.CleanupGlobalDuplicate()
    somMgr.CleanupGlobalDuplicate()

    for _, pair in ipairs({
        { p1Card,  p1Mgr  },
        { p2Card,  p2Mgr  },
        { spCard,  spMgr  },
        { cfCard,  cfMgr  },
        { bsCard,  bsMgr  },
        { somCard, somMgr },
    }) do
        local card, mgr = pair[1], pair[2]
        card.RefreshStatus()
        card.RefreshCurrentLabel()
        local db = mgr.GetDB()
        card.nameBox:SetText(db.targetName  or "")
        card.realmBox:SetText(db.targetRealm or "")
        mgr.Update()
    end
end)
