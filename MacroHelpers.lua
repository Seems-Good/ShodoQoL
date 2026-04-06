-- ShodoQoL/MacroHelpers.lua
-- Per-character macros with compact card UI and cross-realm support.
-- Reads/writes: ShodoQoLDB.spatialParadox, .prescience1, .prescience2

local GLOBAL_MACRO_LIMIT = 120

------------------------------------------------------------------------
-- Shared EditBox factory (no InputBoxTemplate / no OnUpdate)
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

    eb:SetScript("OnEditFocusGained", function()
        border:SetBackdropBorderColor(0.33, 0.82, 0.70, 1.0)
    end)
    eb:SetScript("OnEditFocusLost", function()
        border:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.7)
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

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
            "#showtooltip\n/cast [@%s,nodead] Spatial Paradox(Bronze)\n/cast Spatial Paradox(Bronze)",
            target)
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

------------------------------------------------------------------------
-- Notify PrescienceTracker when any target changes
------------------------------------------------------------------------
local function NotifyTracker()
    if ShodoQoL.PrescienceTracker then
        ShodoQoL.PrescienceTracker.OnTargetChanged()
    end
end

------------------------------------------------------------------------
-- Settings panel (no ScrollFrame needed with compact card layout)
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "Macro Helpers"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()

local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fMacro|r|cff52c4afHelpers|r")

local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Per-character macros with cross-realm support|r")

local topDiv = panel:CreateTexture(nil, "ARTWORK")
topDiv:SetPoint("TOPLEFT", subFS, "BOTTOMLEFT", 0, -12)
topDiv:SetSize(560, 1)
topDiv:SetColorTexture(0.20, 0.58, 0.50, 0.6)

------------------------------------------------------------------------
-- Compact card factory
-- topAnchor  : texture or element to anchor this card below
-- headingText: WoW colour-escape string for the macro title
-- mgr        : CreateMacroManager instance
--
-- Layout (all on panel, no child frames needed):
--   Row 1  heading + status badge
--   Row 2  [Create Macro] [Delete Macro]   [Use Current Target]
--   Row 3  Target: <name>
--   Row 4  Name [box]  Realm [box]  [Apply]  [Clear]
--   ─── bottom divider ───
--
-- Forward-reference pattern: nameBox, realmBox, RefreshCurrentLabel are
-- pre-declared as locals so closure capture works before assignment.
------------------------------------------------------------------------
local function BuildMacroCard(topAnchor, headingText, mgr)
    local nameBox, realmBox       -- pre-declared for forward closures
    local RefreshCurrentLabel     -- pre-declared for forward closures

    -- ── Row 1: heading + live status badge ───────────────────────────
    local headFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headFS:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -14)
    headFS:SetText(headingText)

    local statusFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusFS:SetPoint("LEFT", headFS, "RIGHT", 10, 0)
    statusFS:SetText("|cff888888unknown|r")

    local function RefreshStatus()
        statusFS:SetText(mgr.Exists()
            and "|cff00ff00exists|r"
            or  "|cffff4444not created|r")
    end

    -- ── Row 2: Create / Delete / Use Current Target ───────────────────
    local createBtn = ShodoQoL.CreateButton(panel, "Create Macro", 100, 22)
    createBtn:SetPoint("TOPLEFT", headFS, "BOTTOMLEFT", 0, -8)
    createBtn:SetScript("OnClick", function()
        if mgr.Exists() then
            print("|cff33937fShodoQoL|r: Macro already exists."); return
        end
        mgr.CleanupGlobalDuplicate()
        local _, charCount = GetNumMacros()
        if charCount >= 18 then
            print("|cffff6060ShodoQoL|r: Per-character macro limit reached (18/18)."); return
        end
        CreateMacro(mgr.macroName, mgr.macroIcon, mgr.BuildBody(), true)
        print("|cff33937fShodoQoL|r: |cffffd100" .. mgr.macroName .. "|r created.")
        RefreshStatus()
    end)

    local deleteBtn = ShodoQoL.CreateButton(panel, "Delete Macro", 100, 22)
    deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 6, 0)
    deleteBtn:SetScript("OnClick", function()
        if not mgr.Exists() then
            print("|cff33937fShodoQoL|r: Macro does not exist."); return
        end
        DeleteMacro(mgr.macroName)
        print("|cff33937fShodoQoL|r: |cffffd100" .. mgr.macroName .. "|r deleted.")
        RefreshStatus()
    end)

    local useTargetBtn = ShodoQoL.CreateButton(panel, "Use Current Target", 148, 22)
    useTargetBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 14, 0)
    useTargetBtn:SetScript("OnClick", function()
        if not UnitExists("target") then
            print("|cffff6060ShodoQoL|r: No target selected."); return
        end
        if UnitIsUnit("target", "player") then
            print("|cffff6060ShodoQoL|r: Can't target yourself."); return
        end
        if not UnitIsPlayer("target") then
            print("|cffff6060ShodoQoL|r: Target is not a player."); return
        end
        local name, realm = UnitName("target")
        if not name then
            print("|cffff6060ShodoQoL|r: Could not read target name."); return
        end
        local db = mgr.GetDB()
        db.targetName  = name
        db.targetRealm = realm or ""
        nameBox:SetText(name)
        realmBox:SetText(realm or "")
        mgr.Update()
        RefreshCurrentLabel()
        NotifyTracker()
        local display = (realm and realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
    end)

    -- ── Row 3: current target display ────────────────────────────────
    local targetLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLabelFS:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -8)
    targetLabelFS:SetText("|cff888888Target:|r")

    local currentValueFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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

    -- ── Row 4: Name [box]  Realm [box]  [Apply]  [Clear] ─────────────
    -- Labels sit inline; LEFT-to-RIGHT anchoring vertically centres them
    -- against the 22px-tall edit boxes automatically.
    local nameLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabelFS:SetPoint("TOPLEFT", targetLabelFS, "BOTTOMLEFT", 0, -11)
    nameLabelFS:SetText("|cff52c4afName|r")

    nameBox = CreateCleanEditBox(panel, 148)
    nameBox:SetPoint("LEFT", nameLabelFS, "RIGHT", 5, 0)
    nameBox:SetMaxLetters(48)

    local realmLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    realmLabelFS:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
    realmLabelFS:SetText("|cff52c4afRealm|r")

    realmBox = CreateCleanEditBox(panel, 116)
    realmBox:SetPoint("LEFT", realmLabelFS, "RIGHT", 5, 0)

    local applyBtn = ShodoQoL.CreateButton(panel, "Apply", 66, 22)
    applyBtn:SetPoint("LEFT", realmBox, "RIGHT", 8, 0)
    applyBtn:SetScript("OnClick", function()
        local name  = nameBox:GetText():match("^%s*(.-)%s*$")
        local realm = realmBox:GetText():match("^%s*(.-)%s*$")
        if not name or name == "" then
            print("|cffff6060ShodoQoL|r: Please enter a character name."); return
        end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        local db = mgr.GetDB()
        db.targetName  = name
        db.targetRealm = realm
        mgr.Update()
        RefreshCurrentLabel()
        NotifyTracker()
        local display = (realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
    end)

    local clearBtn = ShodoQoL.CreateButton(panel, "Clear", 66, 22)
    clearBtn:SetPoint("LEFT", applyBtn, "RIGHT", 5, 0)
    clearBtn:SetScript("OnClick", function()
        local db = mgr.GetDB()
        db.targetName, db.targetRealm = nil, nil
        nameBox:SetText("")
        realmBox:SetText("")
        mgr.Update()
        RefreshCurrentLabel()
        NotifyTracker()
        print("|cff33937fShodoQoL|r: " .. mgr.macroName .. " target cleared.")
    end)

    -- ── Bottom divider ────────────────────────────────────────────────
    -- nameLabelFS (~12px) is the vertical reference. Edit boxes (22px)
    -- are vertically centred on it, so they extend 5px below its bottom.
    -- We offset 18px below nameLabelFS bottom → 13px clear gap after boxes.
    local bottomDiv = panel:CreateTexture(nil, "ARTWORK")
    bottomDiv:SetPoint("TOPLEFT", nameLabelFS, "BOTTOMLEFT", 0, -18)
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
-- Build three cards, each anchored below the previous card's divider
------------------------------------------------------------------------
local spCard = BuildMacroCard(topDiv,
    "|cff33937fSpatial|r|cff52c4afParadox|r", spMgr)

local p1Card = BuildMacroCard(spCard.bottomDiv,
    "|cff33937fPrescience|r |cff52c4af1|r", p1Mgr)

local p2Card = BuildMacroCard(p1Card.bottomDiv,
    "|cff33937fPrescience|r |cff52c4af2|r", p2Mgr)

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

    spCard.RefreshStatus()  ; spCard.RefreshCurrentLabel()
    p1Card.RefreshStatus()  ; p1Card.RefreshCurrentLabel()
    p2Card.RefreshStatus()  ; p2Card.RefreshCurrentLabel()

    local spDB = spMgr.GetDB()
    spCard.nameBox:SetText(spDB.targetName  or "")
    spCard.realmBox:SetText(spDB.targetRealm or "")

    local p1DB = p1Mgr.GetDB()
    p1Card.nameBox:SetText(p1DB.targetName  or "")
    p1Card.realmBox:SetText(p1DB.targetRealm or "")

    local p2DB = p2Mgr.GetDB()
    p2Card.nameBox:SetText(p2DB.targetName  or "")
    p2Card.realmBox:SetText(p2DB.targetRealm or "")

    spMgr.Update()
    p1Mgr.Update()
    p2Mgr.Update()
end)
