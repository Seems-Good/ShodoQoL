-- ShodoQoL/HearthStoned.lua
-- Cycles through all owned hearthstone toys/items via a single macro.
-- Reads/writes ShodoQoLDB.hearthStoned.

local MACRO_NAME = "HearthStoned"
local MACRO_ICON = 134400  -- question mark; always valid for CreateMacro/EditMacro

local ALL_HEARTHSTONES = {
    6948,   -- Hearthstone
    54452,  -- Ethereal Portal
    64488,  -- The Innkeeper's Daughter
    93672,  -- Dark Portal
    142542, -- Tome of Town Portal
    162973, -- Greatfather Winter's Hearthstone
    163045, -- Headless Horseman's Hearthstone
    165669, -- Lunar Elder's Hearthstone
    165670, -- Peddlefeet's Lovely Hearthstone
    165802, -- Noble Gardener's Hearthstone
    166746, -- Fire Eater's Hearthstone
    166747, -- Brewfest Reveler's Hearthstone
    168907, -- Holographic Digitalization Hearthstone
    172179, -- Eternal Traveler's Hearthstone
    188952, -- Dominated Hearthstone
    190237, -- Broker Translocation Matrix
    193588, -- Timewalker's Hearthstone
    200630, -- Ohn'ir Windsage's Hearthstone
    206195, -- Path of the Naaru
    208704, -- Deepdweller's Earthen Hearthstone
    209035, -- Hearthstone of the Flame
    210455, -- Draenic Hologem
    212337, -- Stone of the Hearth
    228940, -- Notorious Thread's Hearthstone
    235016, -- Teleportation Matrix
    246565, -- Rainbow Beacon
}

------------------------------------------------------------------------
-- Runtime list of owned hearthstones (rebuilt on login/rescan)
------------------------------------------------------------------------
local ownedItems = {}

local function ScanHearthstones()
    ownedItems = {}
    for _, itemID in ipairs(ALL_HEARTHSTONES) do
        if PlayerHasToy(itemID) or C_Item.GetItemCount(itemID) > 0 then
            table.insert(ownedItems, itemID)
        end
    end
    ShodoQoLDB.hearthStoned.items = ownedItems
    -- Reset index if it's now out of range
    if ShodoQoLDB.hearthStoned.index > #ownedItems then
        ShodoQoLDB.hearthStoned.index = 1
    end
    return ownedItems
end

------------------------------------------------------------------------
-- Macro helpers  — using the same API as the working reference:
--   CreateMacro(name, icon, body, true)  ← true = per-character
--   GetNumMacros() → accountCount, charCount
------------------------------------------------------------------------
local function MacroExists()
    local idx = GetMacroIndexByName(MACRO_NAME)
    return idx and idx > 0
end

local function CurrentMacroBody()
    local db = ShodoQoLDB.hearthStoned
    local itemID = ownedItems[db.index] or ownedItems[1]
    if not itemID then
        return "#showtooltip\n/use item:6948"
    end
    return "#showtooltip\n/run ShodoQoL.HearthStoned.Cycle()\n/use item:" .. itemID
end

local function UpdateMacro()
    if not MacroExists() then return end
    EditMacro(GetMacroIndexByName(MACRO_NAME), MACRO_NAME, MACRO_ICON, CurrentMacroBody())
end

-- Exposed so the macro's /run line can call it
ShodoQoL.HearthStoned = {}
function ShodoQoL.HearthStoned.Cycle()
    if InCombatLockdown() then return end
    if #ownedItems == 0 then return end

    local db = ShodoQoLDB.hearthStoned
    db.index = (db.index % #ownedItems) + 1
    UpdateMacro()
end

------------------------------------------------------------------------
-- Settings sub-page
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "HearthStoned"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()  -- start hidden; Settings API manages show/hide

local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fHearth|r|cff52c4afStoned|r")

local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
subFS:SetText("|cff888888Cycles through all owned hearthstone toys via one macro|r")

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
    if MacroExists() then
        statusValueFS:SetText("|cff00ff00exists|r")
    else
        statusValueFS:SetText("|cffff4444not created|r")
    end
end

local createBtn = ShodoQoL.CreateButton(panel, "Create Macro", 110, 24)
createBtn:SetPoint("TOPLEFT", statusLabelFS, "BOTTOMLEFT", 0, -10)
createBtn:SetScript("OnClick", function()
    if InCombatLockdown() then
        print("|cffff6060ShodoQoL|r: Can't create macros in combat.")
        return
    end
    if MacroExists() then
        print("|cff33937fShodoQoL|r: HearthStoned macro already exists.")
        return
    end
    if #ownedItems == 0 then
        print("|cffff6060ShodoQoL|r: No hearthstones found. Try Rescan first.")
        return
    end
    local _, charCount = GetNumMacros()
    if charCount >= 18 then
        print("|cffff6060ShodoQoL|r: Per-character macro limit reached (18/18). Delete one first.")
        return
    end
    -- true = per-character (matches working reference addon API)
    CreateMacro(MACRO_NAME, MACRO_ICON, CurrentMacroBody(), true)
    print("|cff33937fShodoQoL|r: |cffffd100" .. MACRO_NAME .. "|r macro created. Drag it to your bar.")
    RefreshStatus()
end)

local deleteBtn = ShodoQoL.CreateButton(panel, "Delete Macro", 110, 24)
deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 8, 0)
deleteBtn:SetScript("OnClick", function()
    if InCombatLockdown() then
        print("|cffff6060ShodoQoL|r: Can't delete macros in combat.")
        return
    end
    if not MacroExists() then
        print("|cff33937fShodoQoL|r: Macro does not exist.")
        return
    end
    DeleteMacro(MACRO_NAME)
    print("|cff33937fShodoQoL|r: |cffffd100" .. MACRO_NAME .. "|r macro deleted.")
    RefreshStatus()
end)

-- ── Hearthstone list ──────────────────────────────────────────────────
local div1 = panel:CreateTexture(nil, "ARTWORK")
div1:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -18)
div1:SetSize(560, 1)
div1:SetColorTexture(0.20, 0.58, 0.50, 0.3)

local listLabelFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listLabelFS:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -14)
listLabelFS:SetText("Owned hearthstones:")

local countFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
countFS:SetPoint("LEFT", listLabelFS, "RIGHT", 8, 0)
countFS:SetText("|cff888888(not scanned)|r")

local rescanBtn = ShodoQoL.CreateButton(panel, "Rescan", 80, 24)
rescanBtn:SetPoint("LEFT", countFS, "RIGHT", 12, 0)
rescanBtn:SetScript("OnClick", function()
    ScanHearthstones()
    local n = #ownedItems
    countFS:SetText(string.format("|cffffd100%d found|r", n))
    UpdateMacro()
    print(string.format("|cff33937fShodoQoL|r: Hearthstone rescan complete — %d found.", n))
end)

-- Scrollable list of owned items
local listFrame = CreateFrame("Frame", nil, panel)
listFrame:SetSize(400, 160)
listFrame:SetPoint("TOPLEFT", listLabelFS, "BOTTOMLEFT", 0, -10)

local listFS = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
listFS:SetPoint("TOPLEFT", 0, 0)
listFS:SetWidth(400)
listFS:SetJustifyH("LEFT")
listFS:SetText("|cff888888Rescan to populate list.|r")

local function RefreshList()
    if #ownedItems == 0 then
        listFS:SetText("|cff888888No hearthstones found.|r")
        countFS:SetText("|cff888888none|r")
        return
    end
    countFS:SetText(string.format("|cffffd100%d found|r", #ownedItems))
    local lines = {}
    local db = ShodoQoLDB.hearthStoned
    for i, itemID in ipairs(ownedItems) do
        local name = C_ToyBox.GetToyInfo(itemID)
                  or C_Item.GetItemNameByID(itemID)
                  or ("Item " .. itemID)
        local marker = (i == db.index) and "|cff00ff00 < next|r" or ""
        table.insert(lines, string.format("%s%s", name, marker))
    end
    listFS:SetText(table.concat(lines, "\n"))
end

-- Register sub-page
local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "HearthStoned")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Hook into Core bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    local db = ShodoQoLDB.hearthStoned
    -- Restore previously scanned list so the macro works immediately
    -- without waiting for a manual rescan
    if db.items and #db.items > 0 then
        ownedItems = db.items
    else
        ScanHearthstones()
    end

    RefreshStatus()
    RefreshList()
    UpdateMacro()
end)
