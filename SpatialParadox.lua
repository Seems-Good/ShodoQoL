-- ShodoQoL/SpatialParadox.lua
-- Manages a per-character Spatial Paradox macro with cross-realm support.
-- Reads/writes ShodoQoLDB.spatialParadox.

local MACRO_NAME = "SpatialParadox"
local MACRO_ICON = 134400  -- question mark; always valid

local GLOBAL_MACRO_LIMIT = 120

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function GetCharMacroIndex()
    local idx = GetMacroIndexByName(MACRO_NAME)
    if not idx or idx == 0 then return nil end
    if idx > GLOBAL_MACRO_LIMIT then return idx end
    return nil
end

local function MacroExists()
    return GetCharMacroIndex() ~= nil
end

local function CleanupGlobalDuplicate()
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx and idx > 0 and idx <= GLOBAL_MACRO_LIMIT then
        DeleteMacro(idx)
    end
end

local function BuildMacroBody()
    local db   = ShodoQoLDB.spatialParadox
    local name = db.targetName
    if not name or name == "" then
        return "#showtooltip\n/cast Spatial Paradox(Bronze)"
    end
    local playerRealm = GetRealmName()
    local target
    if db.targetRealm and db.targetRealm ~= "" and db.targetRealm ~= playerRealm then
        target = name .. "-" .. db.targetRealm:gsub(" ", "-")
    else
        target = name
    end
    return string.format(
        "#showtooltip\n/cast [@%s,nodead] Spatial Paradox(Bronze)\n/cast Spatial Paradox(Bronze)",
        target
    )
end

local function UpdateMacro()
    local idx = GetCharMacroIndex()
    if not idx then return end
    EditMacro(idx, MACRO_NAME, MACRO_ICON, BuildMacroBody())
end

------------------------------------------------------------------------
-- Settings sub-page
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "Spatial Paradox"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()  -- start hidden; Settings API manages show/hide

local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fSpatial|r|cff52c4afParadox|r")

local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Per-character macro with cross-realm support|r")

local div0 = panel:CreateTexture(nil, "ARTWORK")
div0:SetPoint("TOPLEFT", subFS, "BOTTOMLEFT", 0, -12)
div0:SetSize(560, 1)
div0:SetColorTexture(0.20, 0.58, 0.50, 0.6)

-- ── Macro status ──────────────────────────────────────────────────────
local statusLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusLabelFS:SetPoint("TOPLEFT", div0, "BOTTOMLEFT", 0, -18)
statusLabelFS:SetText("Macro status:")

local statusValueFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
statusValueFS:SetPoint("LEFT", statusLabelFS, "RIGHT", 8, 0)
statusValueFS:SetText("|cff888888unknown|r")

local function RefreshStatus()
    statusValueFS:SetText(MacroExists() and "|cff00ff00exists|r" or "|cffff4444not created|r")
end

local createBtn = ShodoQoL.CreateButton(panel, "Create Macro", 110, 24)
createBtn:SetPoint("TOPLEFT", statusLabelFS, "BOTTOMLEFT", 0, -10)
createBtn:SetScript("OnClick", function()
    if MacroExists() then
        print("|cff33937fShodoQoL|r: Macro already exists.")
        return
    end
    CleanupGlobalDuplicate()
    local _, charCount = GetNumMacros()
    if charCount >= 18 then
        print("|cffff6060ShodoQoL|r: Per-character macro limit reached (18/18). Delete one first.")
        return
    end
    CreateMacro(MACRO_NAME, MACRO_ICON, BuildMacroBody(), true)
    if MacroExists() then
        print("|cff33937fShodoQoL|r: |cffffd100" .. MACRO_NAME .. "|r macro created (per-character).")
    else
        print("|cffff6060ShodoQoL|r: Could not create macro.")
    end
    RefreshStatus()
end)

local deleteBtn = ShodoQoL.CreateButton(panel, "Delete Macro", 110, 24)
deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 8, 0)
deleteBtn:SetScript("OnClick", function()
    if not MacroExists() then
        print("|cff33937fShodoQoL|r: Macro does not exist.")
        return
    end
    DeleteMacro(MACRO_NAME)
    print("|cff33937fShodoQoL|r: |cffffd100" .. MACRO_NAME .. "|r macro deleted.")
    RefreshStatus()
end)

-- ── Current target ────────────────────────────────────────────────────
local div1 = panel:CreateTexture(nil, "ARTWORK")
div1:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -18)
div1:SetSize(560, 1)
div1:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local currentLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
currentLabelFS:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -18)
currentLabelFS:SetText("Current target:")

local currentValueFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
currentValueFS:SetPoint("LEFT", currentLabelFS, "RIGHT", 8, 0)
currentValueFS:SetText("|cff888888(none set)|r")

local function RefreshCurrentLabel()
    local db = ShodoQoLDB.spatialParadox
    if not db.targetName or db.targetName == "" then
        currentValueFS:SetText("|cff888888(none set)|r")
        return
    end
    local playerRealm = GetRealmName()
    if db.targetRealm and db.targetRealm ~= "" and db.targetRealm ~= playerRealm then
        currentValueFS:SetText(string.format("|cffffd100%s|r |cff888888(%s)|r", db.targetName, db.targetRealm))
    else
        currentValueFS:SetText(string.format("|cffffd100%s|r", db.targetName))
    end
end

-- ── Set from target ───────────────────────────────────────────────────
local div2 = panel:CreateTexture(nil, "ARTWORK")
div2:SetPoint("TOPLEFT", currentLabelFS, "BOTTOMLEFT", 0, -22)
div2:SetSize(560, 1)
div2:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local setLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
setLabelFS:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -18)
setLabelFS:SetText("Set from current selection")

local hintFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintFS:SetPoint("TOPLEFT", setLabelFS, "BOTTOMLEFT", 0, -6)
hintFS:SetText("|cff888888Target a player in-game, then click the button below.|r")

local setBtn = ShodoQoL.CreateButton(panel, "Use Current Target", 160, 24)
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
    local db = ShodoQoLDB.spatialParadox
    db.targetName  = name
    db.targetRealm = realm or ""
    UpdateMacro()
    RefreshCurrentLabel()
    local display = (realm and realm ~= "") and (name .. " (" .. realm .. ")") or name
    print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
end)

-- ── Manual entry — stacked vertically to avoid any overlap ────────────
local div3 = panel:CreateTexture(nil, "ARTWORK")
div3:SetPoint("TOPLEFT", setBtn, "BOTTOMLEFT", 0, -18)
div3:SetSize(560, 1)
div3:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local manualLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
manualLabelFS:SetPoint("TOPLEFT", div3, "BOTTOMLEFT", 0, -18)
manualLabelFS:SetText("Or enter manually")

-- Name field
local nameLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nameLabelFS:SetPoint("TOPLEFT", manualLabelFS, "BOTTOMLEFT", 0, -12)
nameLabelFS:SetText("Character Name")
nameLabelFS:SetTextColor(0.62, 0.88, 0.82)

-- Manual EditBox builder — NO InputBoxTemplate.
-- InputBoxTemplate inherits InputBoxInstructionsTemplate which has an
-- OnUpdate for placeholder-text animation that fires every frame forever.
-- A bare EditBox has zero scripts until we add them ourselves.
local function CreateCleanEditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetMaxLetters(64)

    -- Simple background + border via textures, no template needed
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

    -- Highlight border on focus
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

local nameBox  = CreateCleanEditBox(panel, 220)
nameBox:SetPoint("TOPLEFT", nameLabelFS, "BOTTOMLEFT", 0, -4)
nameBox:SetMaxLetters(48)

local realmLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
realmLabelFS:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -10)
realmLabelFS:SetText("Realm  |cff888888(leave blank if same realm)|r")
realmLabelFS:SetTextColor(0.62, 0.88, 0.82)

local realmBox = CreateCleanEditBox(panel, 220)
realmBox:SetPoint("TOPLEFT", realmLabelFS, "BOTTOMLEFT", 0, -4)

-- Apply / Clear — below realm box
local applyBtn = ShodoQoL.CreateButton(panel, "Apply", 80, 24)
applyBtn:SetPoint("TOPLEFT", realmBox, "BOTTOMLEFT", 0, -10)
applyBtn:SetScript("OnClick", function()
    local name  = nameBox:GetText():match("^%s*(.-)%s*$")
    local realm = realmBox:GetText():match("^%s*(.-)%s*$")
    if not name or name == "" then
        print("|cffff6060ShodoQoL|r: Please enter a character name."); return
    end
    name = name:sub(1,1):upper() .. name:sub(2):lower()
    local db = ShodoQoLDB.spatialParadox
    db.targetName  = name
    db.targetRealm = realm
    UpdateMacro()
    RefreshCurrentLabel()
    local display = (realm ~= "") and (name .. " (" .. realm .. ")") or name
    print(string.format("|cff33937fShodoQoL|r: Target set to |cffffd100%s|r.", display))
end)

local clearBtn = ShodoQoL.CreateButton(panel, "Clear Target", 110, 24)
clearBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
clearBtn:SetScript("OnClick", function()
    local db = ShodoQoLDB.spatialParadox
    db.targetName, db.targetRealm = nil, nil
    nameBox:SetText("")
    realmBox:SetText("")
    UpdateMacro()
    RefreshCurrentLabel()
    print("|cff33937fShodoQoL|r: Spatial Paradox target cleared.")
end)

local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "Spatial Paradox")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("SpatialParadox") then return end
    CleanupGlobalDuplicate()
    RefreshStatus()
    RefreshCurrentLabel()
    local db = ShodoQoLDB.spatialParadox
    nameBox:SetText(db.targetName  or "")
    realmBox:SetText(db.targetRealm or "")
    UpdateMacro()
end)
