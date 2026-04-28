-- ShodoQoL/Kicksmaxxing.lua
-- Dynamic focus-macro manager for interrupts, stuns, and targeted CC.
-- Reads / writes: ShodoQoLDB.kicksmaxxing.spells[]
--   each entry: { name = string, enabled = bool }
--
-- Generated macro template (per spell):
--   #showtooltip <Spell>
--   /cast [@focus,exists,nodead,harm] <Spell>
--   /stopmacro [@focus,exists,nodead,harm]
--   /focus target
--   /cleartarget
--   /targetenemy
--   /cast <Spell>
--   /target focus
--   /clearfocus
--   /startattack
--
-- Macro naming: KM_<CamelCasedSpellName>  (max 16 chars total)
-- All macros stored in the character-specific macro tab (not General).
-- Maximum MAX_ACTIVE spells may be enabled simultaneously.

local MAX_ACTIVE   = 5
local MACRO_PREFIX = "KM_"
local GLOBAL_LIMIT = 120   -- indices 1-120 are General; 121+ are Character
local ROW_H        = 32    -- height of each spell row in the list

-- Column x-offsets (all relative to their parent's LEFT edge)
local COL_CB     = 2    -- checkbox
local COL_NAME   = 30   -- spell name label
local COL_MNAME  = 212  -- macro name label (KM_xxx)
local COL_STATUS = 326  --  / – exists label
local COL_DEL    = 400  -- delete button

------------------------------------------------------------------------
-- Local EditBox factory  (matches MacroHelpers style)
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
    eb:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed",    function(self) self:ClearFocus() end)
    return eb
end

------------------------------------------------------------------------
-- Macro helpers
------------------------------------------------------------------------

-- CamelCase the spell name and prepend KM_, hard-capped to 16 chars total.
local function MName(spellName)
    local parts = {}
    for word in spellName:gmatch("%S+") do
        parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2):lower()
    end
    local joined = table.concat(parts, "")
    return MACRO_PREFIX .. joined:sub(1, 16 - #MACRO_PREFIX)
end

local function MBody(spellName)
    return string.format(
        "#showtooltip %s\n"
     .. "/cast [@focus,exists,nodead,harm] %s\n"
     .. "/stopmacro [@focus,exists,nodead,harm]\n"
     .. "/focus target\n"
     .. "/cleartarget\n"
     .. "/targetenemy\n"
     .. "/cast %s\n"
     .. "/target focus\n"
     .. "/clearfocus\n"
     .. "/startattack",
        spellName, spellName, spellName)
end

-- Returns the character-tab index for macroName, or nil.
local function GetCharIdx(macroName)
    local idx = GetMacroIndexByName(macroName)
    if idx and idx > 0 and idx > GLOBAL_LIMIT then return idx end
    return nil
end

-- Delete any copy that accidentally ended up in the General tab.
local function PurgeGlobal(macroName)
    local idx = GetMacroIndexByName(macroName)
    if idx and idx > 0 and idx <= GLOBAL_LIMIT then DeleteMacro(idx) end
end

local function MacroExistsChar(spellName)
    return GetCharIdx(MName(spellName)) ~= nil
end

-- Create or update the character macro for spellName.
-- Returns true on success, false if the character tab is full.
local function EnableMacro(spellName)
    local mName = MName(spellName)
    PurgeGlobal(mName)
    local idx = GetCharIdx(mName)
    if idx then
        EditMacro(idx, mName, "134400", MBody(spellName))
        return true
    end
    local _, charCount = GetNumMacros()
    if charCount >= 18 then
        print(string.format(
            "|cffff6060ShodoQoL Kicksmaxxing|r: Character macro tab full (18/18). "
         .. "Cannot create |cffffd100%s|r.", mName))
        return false
    end
    CreateMacro(mName, "134400", MBody(spellName), true)
    return true
end

-- Delete the character macro for spellName (no-op if it doesn't exist).
local function DisableMacro(spellName)
    local mName = MName(spellName)
    PurgeGlobal(mName)
    local idx = GetCharIdx(mName)
    if idx then DeleteMacro(idx) end
end

local function CountActive()
    if type(ShodoQoLDB) ~= "table" or not ShodoQoLDB.kicksmaxxing then return 0 end
    local n = 0
    for _, e in ipairs(ShodoQoLDB.kicksmaxxing.spells) do
        if e.enabled then n = n + 1 end
    end
    return n
end

------------------------------------------------------------------------
-- Settings panel
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name   = "Kicksmaxxing"
panel.parent = "ShodoQoL"
panel:EnableMouse(false)
panel:Hide()

local outerScroll = CreateFrame("ScrollFrame", "ShodoQoLKickScroll", panel, "UIPanelScrollFrameTemplate")
outerScroll:SetPoint("TOPLEFT",     panel, "TOPLEFT",      4,  -4)
outerScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26,  4)

local content = CreateFrame("Frame", nil, outerScroll)
content:SetWidth(outerScroll:GetWidth() or 580)
content:SetHeight(800)   -- grown dynamically in RebuildList
outerScroll:SetScrollChild(content)
outerScroll:SetScript("OnSizeChanged", function(self)
    content:SetWidth(self:GetWidth())
end)

-------- Header --------------------------------------------------------
local titleFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", 16, -16)
titleFS:SetText("|cff33937fKicks|r|cff52c4afmaxxing|r")

local subFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
subFS:SetText("|cff888888Focus-macro generator — interrupts, stuns, and targeted CC|r")

local topDiv = content:CreateTexture(nil, "ARTWORK")
topDiv:SetPoint("TOPLEFT", subFS, "BOTTOMLEFT", 0, -10)
topDiv:SetSize(560, 1)
topDiv:SetColorTexture(0.20, 0.58, 0.50, 0.6)

-------- Info box -------------------------------------------------------
local infoBG = CreateFrame("Frame", nil, content, "BackdropTemplate")
infoBG:SetPoint("TOPLEFT",  topDiv, "BOTTOMLEFT",  0,  -10)
infoBG:SetPoint("TOPRIGHT", topDiv, "BOTTOMRIGHT", -2, -10)
infoBG:SetHeight(178)
infoBG:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})
infoBG:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
infoBG:SetBackdropBorderColor(0.20, 0.58, 0.50, 0.42)

local infoHdrFS = infoBG:CreateFontString(nil, "OVERLAY", "GameFontNormal")
infoHdrFS:SetPoint("TOPLEFT", 10, -8)
infoHdrFS:SetText("|cff52c4afHow the generated macro works|r")

local infoBodyFS = infoBG:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
infoBodyFS:SetPoint("TOPLEFT", infoHdrFS, "BOTTOMLEFT", 0, -6)
infoBodyFS:SetWidth(510)
infoBodyFS:SetJustifyH("LEFT")
infoBodyFS:SetTextColor(0.80, 0.84, 0.82)
infoBodyFS:SetText(
    "|cffffff00Focus exists & hostile?|r Cast directly on your focus target.\n"
 .. "|cffffff00No valid focus?|r Execute the following:\n1.  your current target as focus\n2.  drops target\n"
 .. "3.  /targetenemy\n4.  casts the spell\n5.  retargets focus\n6.  clears focus\n7.  starts auto-attack.\n\n"
 .. "|cff52c4afIdeal for:|r Interrupts (Quell, Kick, Mind Freeze, Spear Hand Strike, Solar Beam)"
 .. "Stuns / CC (Cheap Shot, Kidney Shot, Hammer of Justice, Leg Sweep, Sigil of Silence).\n\n"
 .. "|cff52c4afMacro naming:|r Spell --> |cffffd100KM_SpellName|r "
 .. "(e.g. Quell --> |cffffd100KM_Quell|r, Cheap Shot --> |cffffd100KM_CheapShot|r). Enable up to |cffffd100" .. MAX_ACTIVE .. "|r at once with the checkboxes below."
)

local infoDiv = content:CreateTexture(nil, "ARTWORK")
infoDiv:SetPoint("TOPLEFT", infoBG, "BOTTOMLEFT", 0, -12)
infoDiv:SetSize(560, 1)
infoDiv:SetColorTexture(0.20, 0.58, 0.50, 0.6)

-------- Add Spell row --------------------------------------------------
local addHdrFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
addHdrFS:SetPoint("TOPLEFT", infoDiv, "BOTTOMLEFT", 0, -14)
addHdrFS:SetText("|cff52c4afAdd a spell|r")

local spellEB = CreateCleanEditBox(content, 204)
spellEB:SetPoint("LEFT", addHdrFS, "RIGHT", 10, 0)
spellEB:SetMaxLetters(48)

local addBtn = ShodoQoL.CreateButton(content, "Add Spell", 90, 22)
addBtn:SetPoint("LEFT", spellEB, "RIGHT", 6, 0)

local addFeedFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
addFeedFS:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
addFeedFS:SetText("")

local function SetFeedback(text, isError)
    addFeedFS:SetText(isError
        and ("|cffff6060" .. text .. "|r")
        or  ("|cff33937f" .. text .. "|r"))
    C_Timer.After(4, function() addFeedFS:SetText("") end)
end

-------- Status line ----------------------------------------------------
local statusFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusFS:SetPoint("TOPLEFT", addHdrFS, "BOTTOMLEFT", 0, -10)

local function UpdateStatus()
    local db = ShodoQoLDB and ShodoQoLDB.kicksmaxxing
    if not db then statusFS:SetText(""); return end
    local total = #db.spells
    local active = CountActive()
    if total == 0 then
        statusFS:SetText("|cff888888No spells configured — enter a spell name above and click Add Spell.|r")
        return
    end
    local col = (active >= MAX_ACTIVE) and "|cffffff00" or "|cff52c4af"
    statusFS:SetText(string.format(
        col .. "Active: %d / %d|r  |cff666666·|r  "
     .. "|cff888888%d spell%s configured  (check up to %d)|r",
        active, MAX_ACTIVE, total, total == 1 and "" or "s", MAX_ACTIVE))
end

-------- List column headers --------------------------------------------
local listHdrFrame = CreateFrame("Frame", nil, content)
listHdrFrame:SetHeight(18)
listHdrFrame:SetPoint("TOPLEFT",  statusFS, "BOTTOMLEFT",  0,  -8)
listHdrFrame:SetPoint("TOPRIGHT", content,  "TOPRIGHT",  -20,  0)

local function MakeHdrLabel(text, xOff)
    local fs = listHdrFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", xOff, 0)
    fs:SetTextColor(0.52, 0.77, 0.69)
    fs:SetText(text)
    return fs
end
MakeHdrLabel("On",         COL_CB)
MakeHdrLabel("Spell Name", COL_NAME)
MakeHdrLabel("Macro Name", COL_MNAME)
MakeHdrLabel("Created",    COL_STATUS)

local hdrDiv = content:CreateTexture(nil, "ARTWORK")
hdrDiv:SetPoint("TOPLEFT",  listHdrFrame, "BOTTOMLEFT",  0, -2)
hdrDiv:SetPoint("TOPRIGHT", listHdrFrame, "BOTTOMRIGHT", 0, -2)
hdrDiv:SetHeight(1)
hdrDiv:SetColorTexture(0.20, 0.58, 0.50, 0.28)

-------- Row pool -------------------------------------------------------
local rowPool  = {}
local RebuildList  -- forward declaration

local function CreatePoolRow(poolIdx)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)

    -- Alternating subtle background
    local rowBG = row:CreateTexture(nil, "BACKGROUND")
    rowBG:SetAllPoints()
    local baseAlpha = (poolIdx % 2 == 0) and 0.10 or 0.0
    rowBG:SetColorTexture(0.20, 0.58, 0.50, baseAlpha)

    -- Hover highlight
    row:SetScript("OnEnter", function() rowBG:SetColorTexture(0.20, 0.58, 0.50, 0.14) end)
    row:SetScript("OnLeave", function() rowBG:SetColorTexture(0.20, 0.58, 0.50, baseAlpha) end)
    row:EnableMouse(true)

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", row, "LEFT", COL_CB, 0)
    row.cb = cb

    -- Spell name
    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("LEFT", row, "LEFT", COL_NAME, 0)
    nameFS:SetWidth(178)
    nameFS:SetJustifyH("LEFT")
    row.nameFS = nameFS

    -- Macro name  (KM_xxx)
    local mNameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mNameFS:SetPoint("LEFT", row, "LEFT", COL_MNAME, 0)
    mNameFS:SetWidth(110)
    mNameFS:SetJustifyH("LEFT")
    row.mNameFS = mNameFS

    -- Exists badge
    local statFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statFS:SetPoint("LEFT", row, "LEFT", COL_STATUS, 0)
    statFS:SetWidth(70)
    statFS:SetJustifyH("LEFT")
    row.statFS = statFS

    -- Delete button
    local delBtn = ShodoQoL.CreateButton(row, "Delete", 72, 20)
    delBtn:SetPoint("LEFT", row, "LEFT", COL_DEL, 0)
    do  -- red tint overlay
        local tint = delBtn:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(0.6, 0.05, 0.05, 0.30)
        tint:SetBlendMode("ADD")
    end
    row.delBtn = delBtn

    row:Hide()
    return row
end

-------- Bottom divider (moved by RebuildList) --------------------------
local bottomDiv = content:CreateTexture(nil, "ARTWORK")
bottomDiv:SetSize(560, 1)
bottomDiv:SetColorTexture(0.20, 0.58, 0.50, 0.6)

-------- RebuildList ----------------------------------------------------
RebuildList = function()
    if type(ShodoQoLDB) ~= "table" or not ShodoQoLDB.kicksmaxxing then return end
    local spells = ShodoQoLDB.kicksmaxxing.spells

    -- Hide all pooled rows first
    for _, row in ipairs(rowPool) do row:Hide() end

    local activeCount = CountActive()

    for i, entry in ipairs(spells) do
        if not rowPool[i] then rowPool[i] = CreatePoolRow(i) end
        local row = rowPool[i]

        -- Reanchor to correct vertical slot
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  hdrDiv, "BOTTOMLEFT",  0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT",  -20, 0)
        row:Show()

        -- ── Checkbox ────────────────────────────────────────────────
        row.cb:SetChecked(entry.enabled)

        -- Capture entry by reference (it IS the actual DB table entry)
        local capturedEntry = entry
        local capturedI     = i

        row.cb:SetScript("OnClick", function(self)
            local wantEnabled = self:GetChecked()
            if wantEnabled then
                if CountActive() >= MAX_ACTIVE then
                    self:SetChecked(false)
                    SetFeedback("Max " .. MAX_ACTIVE .. " active at once!", true)
                    return
                end
                capturedEntry.enabled = true
                if not EnableMacro(capturedEntry.name) then
                    -- Char tab was full — roll back
                    capturedEntry.enabled = false
                    self:SetChecked(false)
                end
            else
                capturedEntry.enabled = false
                DisableMacro(capturedEntry.name)
            end
            RebuildList()
        end)

        -- ── Spell name label ─────────────────────────────────────────
        row.nameFS:SetText(entry.enabled
            and ("|cffffd100" .. entry.name .. "|r")
            or  ("|cff888888" .. entry.name .. "|r"))

        -- ── Macro name ───────────────────────────────────────────────
        row.mNameFS:SetText("|cff52c4af" .. MName(entry.name) .. "|r")

        -- ── Exists badge ─────────────────────────────────────────────
        row.statFS:SetText(MacroExistsChar(entry.name)
            and "|cff33cc55yes|r"
            or  "|cff555555no|r")

        -- ── Delete ───────────────────────────────────────────────────
        row.delBtn:SetScript("OnClick", function()
            DisableMacro(capturedEntry.name)
            table.remove(ShodoQoLDB.kicksmaxxing.spells, capturedI)
            print(string.format(
                "|cff33937fShodoQoL Kicksmaxxing|r: Removed |cffffd100%s|r "
             .. "(macro |cffffd100%s|r deleted).",
                capturedEntry.name, MName(capturedEntry.name)))
            RebuildList()
        end)
    end

    -- ── Move bottom divider below last row ───────────────────────────
    bottomDiv:ClearAllPoints()
    local divOffY = -(math.max(0, #spells) * ROW_H) - 12
    bottomDiv:SetPoint("TOPLEFT",  hdrDiv, "BOTTOMLEFT",  0, divOffY)

    -- ── Grow content to fit ──────────────────────────────────────────
    -- Approximate static offset from content top to hdrDiv bottom:
    --   title(20) + gap(13) + sub(14) + 10 + topDiv(1) + 10 +
    --   infoBG(178) + 12 + infoDiv(1) + 14 + addRow(22) + 10 +
    --   status(14) + 8 + listHdr(18) + hdrDiv(1) + gap(2)  ≈ 348
    local STATIC_H = 355
    content:SetHeight(STATIC_H + (#spells * ROW_H) + 60)

    UpdateStatus()
end

-------- Add button logic -----------------------------------------------
local function TryAddSpell()
    if type(ShodoQoLDB) ~= "table" or not ShodoQoLDB.kicksmaxxing then return end

    local raw = spellEB:GetText():match("^%s*(.-)%s*$")
    if not raw or raw == "" then
        SetFeedback("Enter a spell name first.", true)
        return
    end

    -- Title-case each word (e.g. "cheap shot" → "Cheap Shot")
    local parts = {}
    for word in raw:gmatch("%S+") do
        parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2):lower()
    end
    local spellName = table.concat(parts, " ")

    -- Duplicate guard
    local spells = ShodoQoLDB.kicksmaxxing.spells
    for _, e in ipairs(spells) do
        if e.name:lower() == spellName:lower() then
            SetFeedback(spellName .. " is already in the list.", true)
            return
        end
    end

    table.insert(spells, { name = spellName, enabled = false })
    spellEB:SetText("")
    SetFeedback("Added: " .. spellName .. " (check the box to activate)")
    RebuildList()
end

addBtn:SetScript("OnClick", TryAddSpell)
spellEB:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    TryAddSpell()
end)

------------------------------------------------------------------------
-- Settings registration
------------------------------------------------------------------------
local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "Kicksmaxxing")
Settings.RegisterAddOnCategory(subCat)

------------------------------------------------------------------------
-- Bootstrap (runs after PLAYER_LOGIN once DB is available)
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("Kicksmaxxing") then return end

    local spells = ShodoQoLDB.kicksmaxxing.spells

    -- Purge any General-tab accidents
    for _, e in ipairs(spells) do
        PurgeGlobal(MName(e.name))
    end

    -- Sync: create enabled macros, ensure disabled/removed ones don't exist
    for _, e in ipairs(spells) do
        if e.enabled then
            if not EnableMacro(e.name) then
                -- Char tab full — mark as disabled so state is honest
                e.enabled = false
            end
        else
            DisableMacro(e.name)
        end
    end

    RebuildList()
end)
