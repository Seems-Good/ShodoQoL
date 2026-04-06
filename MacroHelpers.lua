-- ShodoQoL/MacroHelpers.lua
-- Manages per-character macros: Spatial Paradox, Prescience 1, Prescience 2.
-- Cross-realm support for all targets.
-- Reads/writes ShodoQoLDB.spatialParadox, .prescience1, .prescience2.

local GLOBAL_MACRO_LIMIT = 120

------------------------------------------------------------------------
-- Shared EditBox factory (no InputBoxTemplate; zero OnUpdate scripts)
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
-- cfg = {
--   macroName : string   (max 16 chars; unique WoW macro name)
--   macroIcon : number   (texture FileID; 134400 = question mark fallback)
--   dbKey     : string   (key in ShodoQoLDB)
--   buildBody : function(targetStr_or_nil) -> string
-- }
------------------------------------------------------------------------
local function CreateMacroManager(cfg)
    local M  = {}
    M.macroName = cfg.macroName
    M.macroIcon = cfg.macroIcon

    local function GetCharIndex()
        local idx = GetMacroIndexByName(cfg.macroName)
        if not idx or idx == 0 then return nil end
        return (idx > GLOBAL_MACRO_LIMIT) and idx or nil
    end

    function M.Exists()
        return GetCharIndex() ~= nil
    end

    function M.CleanupGlobalDuplicate()
        local idx = GetMacroIndexByName(cfg.macroName)
        if idx and idx > 0 and idx <= GLOBAL_MACRO_LIMIT then
            DeleteMacro(idx)
        end
    end

    function M.BuildBody()
        local db   = ShodoQoLDB[cfg.dbKey]
        local name = db.targetName
        if not name or name == "" then
            return cfg.buildBody(nil)
        end
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

    function M.GetDB()
        return ShodoQoLDB[cfg.dbKey]
    end

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
        if not target then
            return "#showtooltip\n/cast Spatial Paradox(Bronze)"
        end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Spatial Paradox(Bronze)\n/cast Spatial Paradox(Bronze)",
            target
        )
    end,
})

local p1Mgr = CreateMacroManager({
    macroName = "Prescience1",
    macroIcon = 134400,
    dbKey     = "prescience1",
    buildBody = function(target)
        if not target then
            return "#showtooltip\n/cast Prescience"
        end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Prescience\n/cast Prescience",
            target
        )
    end,
})

local p2Mgr = CreateMacroManager({
    macroName = "Prescience2",
    macroIcon = 134400,
    dbKey     = "prescience2",
    buildBody = function(target)
        if not target then
            return "#showtooltip\n/cast Prescience"
        end
        return string.format(
            "#showtooltip\n/cast [@%s,nodead] Prescience\n/cast Prescience",
            target
        )
    end,
})

------------------------------------------------------------------------
-- Settings panel
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "Macro Helpers"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()

-- ── Fixed header (not scrolled) ───────────────────────────────────────
local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fMacro|r|cff52c4afHelpers|r")

local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Per-character macros with cross-realm support|r")

local headerDiv = panel:CreateTexture(nil, "ARTWORK")
headerDiv:SetPoint("TOPLEFT", subFS, "BOTTOMLEFT", 0, -12)
headerDiv:SetSize(560, 1)
headerDiv:SetColorTexture(0.20, 0.58, 0.50, 0.6)

-- ── ScrollFrame fills the panel below the header ──────────────────────
-- Leave 28px on the right for the scrollbar thumb.
local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     headerDiv, "BOTTOMLEFT",  0, -8)
scrollFrame:SetPoint("BOTTOMRIGHT", panel,     "BOTTOMRIGHT", -28, 8)

-- Scroll child — fixed width, tall enough for all three sections (~900px).
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(530, 900)
scrollFrame:SetScrollChild(content)

-- Invisible 1px sentinel at the very top of content so the first
-- section can use the same BOTTOMLEFT anchor as the rest.
local contentTop = content:CreateTexture(nil, "ARTWORK")
contentTop:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
contentTop:SetSize(1, 1)
contentTop:SetAlpha(0)

------------------------------------------------------------------------
-- Section factory — builds the full UI block for one macro inside
-- `content` (the scroll child).  All child frames / textures are
-- parented to `content` so they scroll with it.
-- Returns { bottomAnchor, nameBox, realmBox, RefreshStatus, RefreshCurrentLabel }
------------------------------------------------------------------------
local function BuildMacroSection(anchorAbove, headingText, mgr)
    local W = 530  -- usable width inside scroll child

    -- ── Section heading ──────────────────────────────────────────────
    local headFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headFS:SetPoint("TOPLEFT", anchorAbove, "BOTTOMLEFT", 0, -18)
    headFS:SetText(headingText)

    -- ── Macro status ─────────────────────────────────────────────────
    local statusLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabelFS:SetPoint("TOPLEFT", headFS, "BOTTOMLEFT", 0, -10)
    statusLabelFS:SetText("Macro status:")

    local statusValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusValueFS:SetPoint("LEFT", statusLabelFS, "RIGHT", 8, 0)
    statusValueFS:SetText("|cff888888unknown|r")

    local function RefreshStatus()
        statusValueFS:SetText(mgr.Exists() and "|cff00ff00exists|r" or "|cffff4444not created|r")
    end

    -- ── Create / Delete ───────────────────────────────────────────────
    local createBtn = ShodoQoL.CreateButton(content, "Create Macro", 110, 24)
    createBtn:SetPoint("TOPLEFT", statusLabelFS, "BOTTOMLEFT", 0, -10)
    createBtn:SetScript("OnClick", function()
        if mgr.Exists() then
            print("|cff33937fShodoQoL|r: Macro already exists."); return
        end
        mgr.CleanupGlobalDuplicate()
        local _, charCount = GetNumMacros()
        if charCount >= 18 then
            print("|cffff6060ShodoQoL|r: Per-character macro limit reached (18/18). Delete one first.")
            return
        end
        CreateMacro(mgr.macroName, mgr.macroIcon, mgr.BuildBody(), true)
        if mgr.Exists() then
            print("|cff33937fShodoQoL|r: |cffffd100" .. mgr.macroName .. "|r macro created (per-character).")
        else
            print("|cffff6060ShodoQoL|r: Could not create macro.")
        end
        RefreshStatus()
    end)

    local deleteBtn = ShodoQoL.CreateButton(content, "Delete Macro", 110, 24)
    deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 8, 0)
    deleteBtn:SetScript("OnClick", function()
        if not mgr.Exists() then
            print("|cff33937fShodoQoL|r: Macro does not exist."); return
        end
        DeleteMacro(mgr.macroName)
        print("|cff33937fShodoQoL|r: |cffffd100" .. mgr.macroName .. "|r macro deleted.")
        RefreshStatus()
    end)

    -- ── Current target display ────────────────────────────────────────
    local divA = content:CreateTexture(nil, "ARTWORK")
    divA:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -14)
    divA:SetSize(W, 1)
    divA:SetColorTexture(0.20, 0.58, 0.50, 0.3)

    local currentLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentLabelFS:SetPoint("TOPLEFT", divA, "BOTTOMLEFT", 0, -14)
    currentLabelFS:SetText("Current target:")

    local currentValueFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    currentValueFS:SetPoint("LEFT", currentLabelFS, "RIGHT", 8, 0)
    currentValueFS:SetText("|cff888888(none set)|r")

    local function RefreshCurrentLabel()
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

    -- ── Set from current in-game target ──────────────────────────────
    local divB = content:CreateTexture(nil, "ARTWORK")
    divB:SetPoint("TOPLEFT", currentLabelFS, "BOTTOMLEFT", 0, -18)
    divB:SetSize(W, 1)
    divB:SetColorTexture(0.20, 0.58, 0.50, 0.3)

    local setLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setLabelFS:SetPoint("TOPLEFT", divB, "BOTTOMLEFT", 0, -14)
    setLabelFS:SetText("Set from current selection")

    local hintFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintFS:SetPoint("TOPLEFT", setLabelFS, "BOTTOMLEFT", 0, -6)
    hintFS:SetText("|cff888888Target a player in-game, then click the button below.|r")

    local setBtn = ShodoQoL.CreateButton(content, "Use Current Target", 160, 24)
    setBtn:SetPoint("TOPLEFT", hintFS, "BOTTOMLEFT", 0, -8)
    setBtn:SetScript("OnClick", function()
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
        mgr.Update()
        RefreshCurrentLabel()
        local display = (realm and realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
    end)

    -- ── Manual entry ──────────────────────────────────────────────────
    local divC = content:CreateTexture(nil, "ARTWORK")
    divC:SetPoint("TOPLEFT", setBtn, "BOTTOMLEFT", 0, -14)
    divC:SetSize(W, 1)
    divC:SetColorTexture(0.20, 0.58, 0.50, 0.3)

    local manualLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    manualLabelFS:SetPoint("TOPLEFT", divC, "BOTTOMLEFT", 0, -14)
    manualLabelFS:SetText("Or enter manually")

    local nameLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabelFS:SetPoint("TOPLEFT", manualLabelFS, "BOTTOMLEFT", 0, -10)
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

    local applyBtn = ShodoQoL.CreateButton(content, "Apply", 80, 24)
    applyBtn:SetPoint("TOPLEFT", realmBox, "BOTTOMLEFT", 0, -10)
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
        local display = (realm ~= "") and (name .. " (" .. realm .. ")") or name
        print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
    end)

    local clearBtn = ShodoQoL.CreateButton(content, "Clear Target", 110, 24)
    clearBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    clearBtn:SetScript("OnClick", function()
        local db = mgr.GetDB()
        db.targetName, db.targetRealm = nil, nil
        nameBox:SetText("")
        realmBox:SetText("")
        mgr.Update()
        RefreshCurrentLabel()
        print("|cff33937fShodoQoL|r: " .. mgr.macroName .. " target cleared.")
    end)

    return {
        bottomAnchor        = applyBtn,
        nameBox             = nameBox,
        realmBox            = realmBox,
        RefreshStatus       = RefreshStatus,
        RefreshCurrentLabel = RefreshCurrentLabel,
    }
end

------------------------------------------------------------------------
-- Build three sections separated by full-weight dividers
------------------------------------------------------------------------
local spSection = BuildMacroSection(contentTop,
    "|cff33937fSpatial|r|cff52c4afParadox|r",
    spMgr)

local divSP = content:CreateTexture(nil, "ARTWORK")
divSP:SetPoint("TOPLEFT", spSection.bottomAnchor, "BOTTOMLEFT", 0, -22)
divSP:SetSize(530, 1)
divSP:SetColorTexture(0.20, 0.58, 0.50, 0.6)

local p1Section = BuildMacroSection(divSP,
    "|cff33937fPrescience|r |cff52c4af1|r",
    p1Mgr)

local divP1 = content:CreateTexture(nil, "ARTWORK")
divP1:SetPoint("TOPLEFT", p1Section.bottomAnchor, "BOTTOMLEFT", 0, -22)
divP1:SetSize(530, 1)
divP1:SetColorTexture(0.20, 0.58, 0.50, 0.6)

local p2Section = BuildMacroSection(divP1,
    "|cff33937fPrescience|r |cff52c4af2|r",
    p2Mgr)

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

    spSection.RefreshStatus()
    spSection.RefreshCurrentLabel()
    p1Section.RefreshStatus()
    p1Section.RefreshCurrentLabel()
    p2Section.RefreshStatus()
    p2Section.RefreshCurrentLabel()

    local spDB = spMgr.GetDB()
    spSection.nameBox:SetText(spDB.targetName  or "")
    spSection.realmBox:SetText(spDB.targetRealm or "")

    local p1DB = p1Mgr.GetDB()
    p1Section.nameBox:SetText(p1DB.targetName  or "")
    p1Section.realmBox:SetText(p1DB.targetRealm or "")

    local p2DB = p2Mgr.GetDB()
    p2Section.nameBox:SetText(p2DB.targetName  or "")
    p2Section.realmBox:SetText(p2DB.targetRealm or "")

    spMgr.Update()
    p1Mgr.Update()
    p2Mgr.Update()
end)
