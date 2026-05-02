-- ShodoQoL/WiM.lua
-- Vim-style Text Editor - ShodoQoL module.
--
-- Open / close:  /wim
-- Inside editor: :help  shows the full keybinding reference.
--
-- Revision 7 (new features):
--   - Header hint removed; chat message on open explains Esc / :q / Enter.
--   - Line-number jump: type digits in NORMAL mode then G  (e.g. 5G = line 5).
--       Pending count shown in status bar; clamped to last line if out of range.
--   - Substitute command: :%s/pattern/replacement/[g]
--       Plain-text (no Lua regex), / delimiter (or any char after s).
--       Without g flag replaces only the first occurrence.
--   - :help updated with new commands.

------------------------------------------------------------------------
-- Logger
------------------------------------------------------------------------
local log = ShodoQoL.Debug.GetLogger("Wim")

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local WiM = {}
WiM.mode          = "NORMAL"
WiM.visualStart   = nil
WiM.clipboard     = ""
WiM.pendingKey    = nil
WiM.exInput       = nil

-- count prefix for motions (e.g. 5G = go to line 5)
WiM.pendingCount  = ""      -- digit string accumulated before a motion

-- undo
WiM.undoStack     = {}      -- array of {text=string, cur=int}

-- search
WiM.searchQuery   = ""      -- last committed / confirmed search string
WiM.searchInput   = nil     -- non-nil while in SEARCH mode (in-progress query)
WiM.searchMatches = {}      -- [{s0=int, e0=int}, …]  0-based positions
WiM.searchIdx     = 0       -- 1-based current match  (0 = no jump yet)

local FONT_SIZE = 18        -- was 16
local LINE_H    = 20        -- bumped to match larger font
local UNDO_MAX  = 20        -- maximum undo snapshots kept in the ring

------------------------------------------------------------------------
-- Line-table cache  (KEY memory-leak fix)
-- BuildLineTable creates a fresh table+sub-tables on every call.
-- GetLines() memoises by text identity so it is called at most once
-- per actual text change instead of ~12 times per second.
------------------------------------------------------------------------
local _ltCache = { src = false }   -- false so first "" triggers a build

local function BuildLineTable(text)
    local lines = {}
    for s, e in (text.."\n"):gmatch("()[^\n]*()\n") do
        lines[#lines+1] = { s=s, e=e-1 }
    end
    return lines
end

local function GetLines(text)
    if text ~= _ltCache.src then
        _ltCache.src   = text
        _ltCache.lines = BuildLineTable(text)
    end
    return _ltCache.lines
end

------------------------------------------------------------------------
-- Plain-text substitute (no Lua pattern meta-chars)
-- Returns newText, count.  global=true replaces all occurrences.
------------------------------------------------------------------------
local function PlainReplace(text, pat, rep, global)
    if pat == "" then return text, 0 end
    local result, count, i = {}, 0, 1
    while true do
        local s, e = text:find(pat, i, true)
        if not s then break end
        result[#result+1] = text:sub(i, s - 1)
        result[#result+1] = rep
        count = count + 1
        i = e + 1
        if not global or i > #text then break end
    end
    result[#result+1] = text:sub(i)
    return table.concat(result), count
end


local COL = {
    NORMAL = { r=0.32, g=0.77, b=0.69 },  -- #52c4af  evoker teal
    INSERT = { r=0.38, g=0.90, b=0.55 },  -- brighter evoker green
    VISUAL = { r=1.00, g=0.78, b=0.30 },  -- evoker amber / scale gold
    EX     = { r=0.65, g=0.90, b=0.82 },  -- pale mint-teal
    SEARCH = { r=0.95, g=0.72, b=0.22 },  -- warm amber for search prompt
    BG     = { r=0.04, g=0.06, b=0.05 },  -- near-black with green tint
    BORDER = { r=0.20, g=0.58, b=0.50 },  -- ShodoQoL brand green
    TEXT   = { r=0.85, g=0.92, b=0.88 },  -- green-tinted off-white
    MUTED  = { r=0.28, g=0.43, b=0.38 },  -- muted teal-grey
}
local function rgb(t) return t.r, t.g, t.b end

------------------------------------------------------------------------
-- Data namespace
------------------------------------------------------------------------
local function GetDB()
    ShodoQoLDB.wim      = ShodoQoLDB.wim or {}
    ShodoQoLDB.wim.text = ShodoQoLDB.wim.text or ""
    return ShodoQoLDB.wim
end

------------------------------------------------------------------------
-- Primitive helpers
------------------------------------------------------------------------
local function GetCursorPos() return WiM.editor:GetCursorPosition() end
local function SetCursorPos(p) WiM.editor:SetCursorPosition(p) end
local function GetText()       return WiM.editor:GetText() or "" end

local function CurrentLineIndex(lines, cur0)
    for i, l in ipairs(lines) do
        if cur0 >= l.s-1 and cur0 <= l.e then return i end
    end
    return #lines
end

local function GetLineInfo0()
    local text  = GetText()
    local cur0  = GetCursorPos()
    local lines = GetLines(text)
    local idx   = CurrentLineIndex(lines, cur0)
    local l     = lines[idx] or { s=1, e=0 }
    local ls0   = l.s - 1
    local le0   = (l.e >= l.s) and (l.e - 1) or ls0
    return ls0, le0, idx, lines
end

local function ClampToLine(pos0, text)
    text = text or GetText()
    local lines = GetLines(text)
    if #lines == 0 then return 0 end
    local idx = CurrentLineIndex(lines, pos0)
    local l   = lines[idx] or { s=1, e=0 }
    local ls0 = l.s - 1
    local le0 = (l.e >= l.s) and (l.e - 1) or ls0
    return math.max(ls0, math.min(le0, pos0))
end

local function MoveLine(delta)
    local text  = GetText()
    local cur0  = GetCursorPos()
    local lines = GetLines(text)
    if #lines == 0 then return end
    local ci    = CurrentLineIndex(lines, cur0)
    local ti    = math.max(1, math.min(#lines, ci + delta))
    local srcL  = lines[ci]
    local tgtL  = lines[ti]
    if not tgtL then return end
    local col   = cur0 - (srcL.s - 1)
    local tls0  = tgtL.s - 1
    local tle0  = (tgtL.e >= tgtL.s) and (tgtL.e - 1) or tls0
    SetCursorPos(tls0 + math.min(col, tle0 - tls0))
end

------------------------------------------------------------------------
-- Text stats helper
------------------------------------------------------------------------
local function TextStats(text)
    text = text or GetText()
    local lines = select(2, text:gsub("\n", "")) + 1
    return lines, #text
end

------------------------------------------------------------------------
-- Block cursor, visual highlight, cursor-line bar, and scroll helper
------------------------------------------------------------------------
local function UpdateCursor()
    if WiM.mode ~= "NORMAL" then return end
    local cur0 = GetCursorPos()
    WiM.editor:HighlightText(cur0, cur0 + 1)
end

local function UpdateCursorLine()
    if not WiM.cursorLine then return end
    if WiM.mode ~= "NORMAL" and WiM.mode ~= "INSERT" then
        WiM.cursorLine:Hide(); return
    end
    local text  = GetText()
    local cur0  = GetCursorPos()
    local lines = GetLines(text)
    local idx   = CurrentLineIndex(lines, cur0)
    local sv    = WiM.scroll and WiM.scroll:GetVerticalScroll() or 0
    local lineTopY = 32 + 2 + (idx - 1) * LINE_H - sv
    local fH       = WiM.frame and WiM.frame:GetHeight() or 500
    if lineTopY + LINE_H < 32 or lineTopY > fH - 28 then
        WiM.cursorLine:Hide(); return
    end
    WiM.cursorLine:ClearAllPoints()
    WiM.cursorLine:SetPoint("TOPLEFT",  WiM.frame, "TOPLEFT",   6, -lineTopY)
    WiM.cursorLine:SetPoint("TOPRIGHT", WiM.frame, "TOPRIGHT", -6, -lineTopY)
    WiM.cursorLine:Show()
end

local function ScrollToCursor()
    if not WiM.scroll then return end
    local text  = GetText()
    local cur0  = GetCursorPos()
    local lines = GetLines(text)
    local idx   = CurrentLineIndex(lines, cur0)
    local lineTop    = (idx - 1) * LINE_H
    local lineBottom = lineTop + LINE_H
    local viewH      = WiM.scroll:GetHeight()
    local sv         = WiM.scroll:GetVerticalScroll()
    local svMax      = WiM.scroll:GetVerticalScrollRange()
    if lineTop >= sv and lineBottom <= sv + viewH then return end
    local target = lineTop - (viewH - LINE_H) / 2
    WiM.scroll:SetVerticalScroll(math.max(0, math.min(svMax, target)))
end

local function UpdateVisualHighlight()
    if WiM.mode ~= "VISUAL" or not WiM.visualStart then
        WiM.editor:HighlightText(0, 0); return
    end
    local cur = GetCursorPos()
    local lo  = math.min(WiM.visualStart, cur)
    local hi  = math.max(WiM.visualStart, cur)
    WiM.editor:HighlightText(lo, hi + 1)
end

------------------------------------------------------------------------
-- Status bar / mode badge
------------------------------------------------------------------------
local function SetModeBadge(mode)
    WiM.modeBadge:SetText(mode)
    local c = COL[mode] or COL.NORMAL
    WiM.modeBadge:SetTextColor(rgb(c))
    WiM.cursorLine:SetColorTexture(c.r, c.g, c.b, 0.70)
end

local function ShowStatus(msg, timeout)
    WiM.statusMsg:SetText(msg)
    if timeout then
        C_Timer.After(timeout, function()
            if WiM.mode ~= "EX" and WiM.mode ~= "SEARCH" then
                WiM.statusMsg:SetText("-- " .. WiM.mode .. " --")
            end
        end)
    end
end

------------------------------------------------------------------------
-- Save helper  (always flushes to ShodoQoLDB)
------------------------------------------------------------------------
local function SaveText()
    local text = GetText()
    GetDB().text = text
    local lines, chars = TextStats(text)
    log:Info(string.format("saved - %d lines, %d chars", lines, chars))
end

------------------------------------------------------------------------
-- Undo
------------------------------------------------------------------------
local function UndoPush()
    if not WiM.editor then return end
    local text = GetText()
    local cur0 = GetCursorPos()
    local top  = WiM.undoStack[#WiM.undoStack]
    if top and top.text == text then return end
    WiM.undoStack[#WiM.undoStack + 1] = { text = text, cur = cur0 }
    if #WiM.undoStack > UNDO_MAX then
        table.remove(WiM.undoStack, 1)
    end
    log:Info("undo push – depth " .. #WiM.undoStack)
end

local function UndoPop()
    if #WiM.undoStack == 0 then
        ShowStatus("Already at oldest change", 2); return
    end
    local snap = table.remove(WiM.undoStack)
    WiM.editor:SetText(snap.text)
    SetCursorPos(math.min(snap.cur, #snap.text))
    UpdateCursor()
    ShowStatus(string.format("Undo  (%d left)", #WiM.undoStack), 1.5)
    log:Info("undo pop – depth now " .. #WiM.undoStack)
end

------------------------------------------------------------------------
-- Search
------------------------------------------------------------------------
local function BuildSearchMatches(query)
    WiM.searchMatches = {}
    WiM.searchIdx     = 0
    if query == "" then return end
    local text  = GetText()
    local start = 1
    while true do
        local s, e = text:find(query, start, true)
        if not s then break end
        WiM.searchMatches[#WiM.searchMatches + 1] = { s0 = s - 1, e0 = e }
        start = s + 1
    end
    log:Info(string.format("search '%s' – %d match(es)", query, #WiM.searchMatches))
end

local function SearchJump(dir)
    if #WiM.searchMatches == 0 then
        ShowStatus("Pattern not found: " .. WiM.searchQuery, 2); return
    end
    local n = #WiM.searchMatches
    WiM.searchIdx = ((WiM.searchIdx - 1 + dir) % n) + 1
    local m = WiM.searchMatches[WiM.searchIdx]
    SetCursorPos(m.s0)
    ScrollToCursor()
    WiM.editor:HighlightText(m.s0, m.e0)
    ShowStatus(string.format("/%s  [%d/%d]", WiM.searchQuery, WiM.searchIdx, n))
    C_Timer.After(1.2, function()
        if WiM.mode == "NORMAL" then UpdateCursor() end
    end)
    log:Event(string.format("search jump %+d – match %d/%d at %d",
        dir, WiM.searchIdx, n, m.s0))
end

local function EnterSearch()
    WiM.mode        = "SEARCH"
    WiM.searchInput = ""
    WiM.pendingKey  = nil
    SetModeBadge("SEARCH")
    WiM.statusMsg:SetText("/")
    WiM.editor:ClearFocus()
    WiM.keyFrame:SetPropagateKeyboardInput(false)
    WiM.keyFrame:EnableKeyboard(true)
    if WiM.cursorLine then WiM.cursorLine:Hide() end
    log:Event("set mode: SEARCH")
end

------------------------------------------------------------------------
-- Mode transitions
------------------------------------------------------------------------
local function EnterNormal()
    if WiM.mode == "INSERT" then UndoPush() end

    WiM.mode        = "NORMAL"
    WiM.visualStart = nil
    WiM.pendingKey  = nil
    WiM.pendingCount = ""
    WiM.exInput     = nil
    WiM.searchInput = nil
    SetModeBadge("NORMAL")
    ShowStatus("-- NORMAL --")
    WiM.editor:ClearFocus()
    WiM.keyFrame:SetPropagateKeyboardInput(false)
    WiM.keyFrame:EnableKeyboard(true)
    local clamped = ClampToLine(GetCursorPos())
    if clamped ~= GetCursorPos() then SetCursorPos(clamped) end
    UpdateCursor()
    UpdateCursorLine()
end

local function EnterInsert(placement)
    UndoPush()

    WiM.mode       = "INSERT"
    WiM.pendingKey = nil
    WiM.pendingCount = ""
    WiM.exInput    = nil
    WiM.searchInput = nil
    SetModeBadge("INSERT")
    ShowStatus("-- INSERT --")
    WiM.editor:HighlightText(0, 0)

    if placement == "after" then
        SetCursorPos(GetCursorPos() + 1)
    elseif placement == "eol" then
        local ls0, le0 = GetLineInfo0()
        SetCursorPos(le0 + 1)
    elseif placement == "sol" then
        local ls0 = GetLineInfo0()
        SetCursorPos(ls0)
    end

    UpdateCursorLine()

    WiM.keyFrame:SetPropagateKeyboardInput(false)
    WiM.keyFrame:EnableKeyboard(true)
    C_Timer.After(0, function()
        if WiM.mode == "INSERT" then
            WiM.keyFrame:EnableKeyboard(false)
            WiM.editor:SetFocus()
        end
    end)
end

local function EnterVisual()
    WiM.mode        = "VISUAL"
    WiM.visualStart = GetCursorPos()
    WiM.pendingKey  = nil
    WiM.pendingCount = ""
    SetModeBadge("VISUAL")
    ShowStatus("-- VISUAL --")
    WiM.editor:ClearFocus()
    WiM.keyFrame:SetPropagateKeyboardInput(false)
    WiM.keyFrame:EnableKeyboard(true)
    if WiM.cursorLine then WiM.cursorLine:Hide() end
    UpdateVisualHighlight()
    log:Event("mode → VISUAL at pos " .. tostring(WiM.visualStart))
end

------------------------------------------------------------------------
-- Ex / command-line mode
------------------------------------------------------------------------
local HELP_TEXT = [[WiM - Vim Text Editor keybindings   (:q to close help)

MOTION
  h / l          move left / right  (stays on current line)
  j / k          move down / up     (preserves column)
  w              jump to next word start  (line-constrained)
  b              jump to prev word start  (line-constrained)
  0              go to start of line
  $              go to end of line
  gg             go to top of file
  G              go to last line
  {N}G           jump to line N  (e.g. 5G → line 5, 55G → line 55)
                 clamped to last line if N is out of range

ENTERING INSERT MODE
  i              insert before cursor
  a              insert after cursor
  I              insert at line start
  A              insert at line end
  o              open new line below, enter insert
  O              open new line above, enter insert
  Esc            return to NORMAL from any mode

EDITING (NORMAL)
  x              delete character under cursor
  dd             delete current line
  D              delete to end of line
  yy             yank (copy) current line
  p              paste after cursor
  P              paste before cursor
  u              undo last change  (up to 20 levels)

SEARCH
  /foo           open search prompt, type query, Enter to confirm
  n              jump to next match  (wraps)
  N              jump to previous match  (wraps)
  Search is plain-text (no Lua patterns).  Results persist until a new
  search is run.  The matched region flashes highlighted on each jump.

SUBSTITUTE (EX)
  :%s/pat/rep/g  replace all occurrences of pat with rep
  :%s/pat/rep    replace first occurrence only
  Any single-char delimiter works  (e.g. :%s|old|new|g)
  Plain-text matching only - no regex special characters.

VISUAL MODE
  v              enter visual mode
  h/j/k/l        extend selection
  0 / $          extend to line start / end
  y              yank selection
  x / d          delete selection

EX COMMANDS  (press : to enter command line)
  :w             save (write to SavedVariables)
  :q             close window
  :wq  /  :x     save and close
  :q!            close without saving
  :help          show this screen

OTHER
  Ctrl+S         save without closing

AUTHOR
  Shodo          jeremy51b5@pm.me 

LISENCE
  MIT            copy of lisence available along with source code. 
                 Github: https://github.com/Seems-Good/ShodoQoL
]]

local function EnterEx()
    WiM.mode       = "EX"
    WiM.exInput    = ""
    WiM.pendingKey = nil
    SetModeBadge("EX")
    WiM.statusMsg:SetText(":")
    WiM.editor:ClearFocus()
    WiM.keyFrame:SetPropagateKeyboardInput(false)
    WiM.keyFrame:EnableKeyboard(true)
    if WiM.cursorLine then WiM.cursorLine:Hide() end
end

local function ExAppend(ch)
    WiM.exInput = WiM.exInput .. ch
    WiM.statusMsg:SetText(":" .. WiM.exInput)
end

local function ExBackspace()
    if #WiM.exInput == 0 then EnterNormal(); return end
    WiM.exInput = WiM.exInput:sub(1, -2)
    if #WiM.exInput == 0 then EnterNormal()
    else WiM.statusMsg:SetText(":" .. WiM.exInput) end
end

local function ShowHelp()
    WiM._preHelpText = WiM.editor:GetText()
    WiM._preHelpCur  = GetCursorPos()
    WiM.editor:SetText(HELP_TEXT)
    SetCursorPos(0)
    EnterNormal()
    ShowStatus("|cff52c4af:help|r  -  :q restores previous buffer, :w saves help text", 0)
    log:Invoke(":help", "opened")
end

local function ExExecute()
    local cmd = WiM.exInput:match("^%s*(.-)%s*$")
    log:Invoke(":" .. cmd)

    if cmd == "q" or cmd == "q!" then
        if WiM._preHelpText then
            WiM.editor:SetText(WiM._preHelpText)
            WiM._preHelpText = nil
            SetCursorPos(WiM._preHelpCur or 0)
            EnterNormal()
            log:Info(":help closed - previous buffer restored")
        else
            -- Always save text to DB before closing
            GetDB().text = WiM.editor:GetText()
            log:Event("closed via :" .. cmd)
            WiM.frame:Hide()
        end

    elseif cmd == "w" then
        WiM._preHelpText = nil
        SaveText()
        EnterNormal()
        ShowStatus("Written to SavedVariables", 1.5)

    elseif cmd == "wq" or cmd == "x" then
        WiM._preHelpText = nil
        SaveText()
        log:Event("closed via :" .. cmd .. " (saved)")
        WiM.frame:Hide()

    elseif cmd == "help" then
        ShowHelp()

    -- ── Substitute  :%s/pat/rep/[g]  or  :s/pat/rep/[g] ─────────────
    else
        -- Match: optional-% s <delim> <pat> <delim> <rep> optional(<delim><flags>)
        -- Works with or without a trailing delimiter / flags.
        local d = cmd:match("^%%?s(.)") -- extract delimiter char
        local pat, rep, flags
        if d then
            -- Escape delimiter for use in pattern
            local de = d:gsub("[%(%)%.%%%+%-%*%?%[%^%$]", "%%%1")
            pat, rep, flags = cmd:match(
                "^%%?s" .. de .. "(.-)" .. de .. "(.-)" .. de .. "(.-)$")
            if not pat then
                -- No trailing delimiter — try without flags
                pat, rep = cmd:match(
                    "^%%?s" .. de .. "(.-)" .. de .. "(.-)$")
                flags = ""
            end
        end

        if d and pat then
            UndoPush()
            local global  = (flags or ""):find("g") ~= nil
            local oldText = GetText()
            local newText, count = PlainReplace(oldText, pat, rep or "", global)
            if count == 0 then
                EnterNormal()
                ShowStatus("Pattern not found: " .. pat, 2)
            else
                WiM.editor:SetText(newText)
                SetCursorPos(math.min(GetCursorPos(), #newText))
                EnterNormal()
                ShowStatus(string.format(
                    "%d substitution%s", count, count == 1 and "" or "s"), 2)
                log:Invoke(":s", string.format("%d replacement(s) of '%s'", count, pat))
            end
        else
            EnterNormal()
            log:Warn("unknown ex command: " .. cmd)
            ShowStatus("E492: Not an editor command: " .. cmd, 2)
        end
    end
end

------------------------------------------------------------------------
-- Visual operations
------------------------------------------------------------------------
local function VisualCopy()
    local cur = GetCursorPos()
    local vs  = WiM.visualStart or cur
    local lo, hi = math.min(vs,cur), math.max(vs,cur)
    WiM.clipboard = GetText():sub(lo+1, hi)
    ShowStatus(string.format("Yanked %d chars", #WiM.clipboard), 1.5)
    log:Info(string.format("visual yank - %d chars", #WiM.clipboard))
    EnterNormal()
end

local function VisualDelete()
    UndoPush()
    local cur  = GetCursorPos()
    local vs   = WiM.visualStart or cur
    local lo, hi = math.min(vs,cur), math.max(vs,cur)
    local text = GetText()
    WiM.clipboard = text:sub(lo+1, hi)
    WiM.editor:SetText(text:sub(1,lo) .. text:sub(hi+1))
    SetCursorPos(math.min(lo, #GetText()))
    ShowStatus(string.format("Deleted %d chars", #WiM.clipboard), 1.5)
    log:Info(string.format("visual delete - %d chars", #WiM.clipboard))
    EnterNormal()
end

------------------------------------------------------------------------
-- Word motions (line-constrained)
------------------------------------------------------------------------
local function WordForward()
    local text       = GetText()
    local cur0       = GetCursorPos()
    local ls0, le0   = GetLineInfo0()
    if cur0 >= le0 then return end
    local lineRest = text:sub(cur0+2, le0+1)
    if lineRest == "" then return end
    local _, nextStart = lineRest:find("^[^%s]*%s+")
    if nextStart then
        SetCursorPos(math.min(cur0 + nextStart, le0))
    else
        SetCursorPos(le0)
    end
end

local function WordBack()
    local text  = GetText()
    local cur0  = GetCursorPos()
    local ls0   = GetLineInfo0()
    if cur0 <= ls0 then return end
    local before = text:sub(ls0+1, cur0)
    local _, last = before:find(".*%f[%w]%w")
    if last then
        SetCursorPos(ls0 + last - 1)
    else
        SetCursorPos(ls0)
    end
end

------------------------------------------------------------------------
-- Main key dispatch  (NORMAL / VISUAL / EX / SEARCH)
------------------------------------------------------------------------
local function HandleNormalKey(key, ctrl, shift)
    local text = GetText()
    local cur0 = GetCursorPos()

    -- ── EX mode ──────────────────────────────────────────────────────
    if WiM.mode == "EX" then
        if     key == "ESCAPE"                        then EnterNormal()
        elseif key == "BACKSPACE"                     then ExBackspace()
        elseif key == "ENTER" or key == "NUMPADENTER" then ExExecute()
        elseif key == "SPACE"                         then ExAppend(" ")
        elseif #key == 1                              then ExAppend(key)
        end
        return
    end

    -- ── SEARCH mode ───────────────────────────────────────────────────
    if WiM.mode == "SEARCH" then
        if key == "ESCAPE" then
            WiM.searchInput = nil
            EnterNormal()

        elseif key == "BACKSPACE" then
            if #WiM.searchInput == 0 then
                WiM.searchInput = nil; EnterNormal()
            else
                WiM.searchInput = WiM.searchInput:sub(1, -2)
                if #WiM.searchInput == 0 then
                    WiM.statusMsg:SetText("/")
                else
                    WiM.statusMsg:SetText("/" .. WiM.searchInput)
                end
            end

        elseif key == "ENTER" or key == "NUMPADENTER" then
            WiM.searchQuery = WiM.searchInput
            BuildSearchMatches(WiM.searchQuery)
            WiM.searchInput = nil
            EnterNormal()
            if #WiM.searchMatches == 0 then
                ShowStatus("Pattern not found: " .. WiM.searchQuery, 2)
            else
                WiM.searchIdx = 0
                SearchJump(1)
            end

        elseif #key == 1 then
            WiM.searchInput = WiM.searchInput .. key
            WiM.statusMsg:SetText("/" .. WiM.searchInput)
        end
        return
    end

    -- ── Ctrl shortcuts ────────────────────────────────────────────────
    if ctrl and key == "s" then
        SaveText(); ShowStatus("Written to SavedVariables", 1.5); return
    end

    -- ── VISUAL ───────────────────────────────────────────────────────
    if WiM.mode == "VISUAL" then
        local ls0, le0 = GetLineInfo0()
        if     key == "ESCAPE"                    then EnterNormal()
        elseif key == "y" or (ctrl and key=="c") then VisualCopy()
        elseif key == "x" or key == "d"          then VisualDelete()
        elseif key == "h" or key == "LEFT"       then
            SetCursorPos(math.max(ls0, cur0-1)); UpdateVisualHighlight()
        elseif key == "l" or key == "RIGHT"      then
            SetCursorPos(math.min(le0, cur0+1)); UpdateVisualHighlight()
        elseif key == "j" or key == "DOWN"       then
            MoveLine(1);  ScrollToCursor(); UpdateVisualHighlight()
        elseif key == "k" or key == "UP"         then
            MoveLine(-1); ScrollToCursor(); UpdateVisualHighlight()
        elseif key == "0"                         then
            SetCursorPos(ls0); UpdateVisualHighlight()
        elseif key == "$"                         then
            SetCursorPos(le0); UpdateVisualHighlight()
        elseif key == "w"                         then
            WordForward(); UpdateVisualHighlight()
        elseif key == "b"                         then
            WordBack();    UpdateVisualHighlight()
        end
        return
    end

    -- ── NORMAL ───────────────────────────────────────────────────────
    if key == ":" then EnterEx(); return end
    if key == "/" then EnterSearch(); return end

    -- Double-key combos
    if WiM.pendingKey then
        local prev = WiM.pendingKey
        WiM.pendingKey = nil

        if prev == "d" and key == "d" then
            UndoPush()
            local lines = GetLines(text)
            local ci    = CurrentLineIndex(lines, cur0)
            local l     = lines[ci]
            if l then
                local ds, de
                if ci < #lines then
                    ds = l.s-1; de = l.e+1
                else
                    ds = math.max(0, l.s-2); de = l.e
                end
                WiM.clipboard = text:sub(ds+1, de)
                local newText = text:sub(1,ds) .. text:sub(de+1)
                WiM.editor:SetText(newText)
                SetCursorPos(ClampToLine(ds, newText))
                ShowStatus("1 line deleted", 1.5); UpdateCursor()
            end
            return

        elseif prev == "y" and key == "y" then
            local lines = GetLines(text)
            local ci    = CurrentLineIndex(lines, cur0)
            local l     = lines[ci]
            if l then
                WiM.clipboard = text:sub(l.s, math.min(l.e+1, #text))
                ShowStatus("1 line yanked", 1.5); UpdateCursor()
            end
            return

        elseif prev == "g" and key == "g" then
            WiM.pendingCount = ""
            SetCursorPos(0)
            WiM.scroll:SetVerticalScroll(0)
            UpdateCursor(); UpdateCursorLine()
            return
        end
    end

    -- Keys that start a combo (wait for second press)
    if key == "d" or key == "y" or key == "g" then
        WiM.pendingKey = key
        local snap = key
        C_Timer.After(1.0, function()
            if WiM.pendingKey == snap then WiM.pendingKey = nil end
        end)
        return
    end

    -- Single NORMAL bindings
    local ls0, le0 = GetLineInfo0()

    if key == "ESCAPE" then
        if WiM.pendingCount ~= "" then
            WiM.pendingCount = ""
            ShowStatus("-- NORMAL --")
        else
            ShowStatus("-- NORMAL --")
        end
        UpdateCursor(); UpdateCursorLine()

    -- ── Digit prefix (e.g. 5G = jump to line 5) ──────────────────────
    elseif key >= "0" and key <= "9" and not (key == "0" and WiM.pendingCount == "") then
        -- "0" alone is go-to-SOL; digits after the first build the count
        WiM.pendingCount = WiM.pendingCount .. key
        ShowStatus("-- NORMAL --  " .. WiM.pendingCount)
        return  -- don't fall through

    elseif key == "h" or key == "LEFT" then
        WiM.pendingCount = ""
        SetCursorPos(math.max(ls0, cur0-1)); UpdateCursor()
    elseif key == "l" or key == "RIGHT" then
        WiM.pendingCount = ""
        SetCursorPos(math.min(le0, cur0+1)); UpdateCursor()

    elseif key == "j" or key == "DOWN" then
        WiM.pendingCount = ""
        MoveLine(1);  ScrollToCursor(); UpdateCursor()
    elseif key == "k" or key == "UP"   then
        WiM.pendingCount = ""
        MoveLine(-1); ScrollToCursor(); UpdateCursor()

    elseif key == "w" then WordForward(); UpdateCursor()
    elseif key == "b" then WordBack();    UpdateCursor()

    elseif key == "0" then SetCursorPos(ls0); WiM.pendingCount = ""; UpdateCursor()
    elseif key == "$" then SetCursorPos(le0); WiM.pendingCount = ""; UpdateCursor()

    elseif key == "G" then
        local lines = GetLines(text)
        if WiM.pendingCount ~= "" then
            -- NnnG  →  jump to line Nnn (clamped to last line)
            local target = tonumber(WiM.pendingCount) or 1
            WiM.pendingCount = ""
            target = math.max(1, math.min(#lines, target))
            local l = lines[target]
            if l then
                local tls0 = l.s - 1
                SetCursorPos(tls0)
                ScrollToCursor()
                ShowStatus(string.format("Line %d", target), 1)
            end
        else
            -- bare G  →  last line
            if #lines > 0 then
                local l    = lines[#lines]
                local gls0 = l.e - 1
                SetCursorPos(gls0)
            end
            WiM.scroll:SetVerticalScroll(WiM.scroll:GetVerticalScrollRange())
        end
        UpdateCursor(); UpdateCursorLine()

    elseif key == "i" then EnterInsert("before")
    elseif key == "a" then EnterInsert("after")
    elseif key == "A" then EnterInsert("eol")
    elseif key == "I" then EnterInsert("sol")

    elseif key == "o" then
        UndoPush()
        local newText = text:sub(1, le0+1) .. "\n" .. text:sub(le0+2)
        WiM.editor:SetText(newText)
        SetCursorPos(le0 + 2)
        EnterInsert("before")

    elseif key == "O" then
        UndoPush()
        local ins     = (ls0 > 0) and ls0 or 0
        local newText = text:sub(1, ins) .. "\n" .. text:sub(ins+1)
        WiM.editor:SetText(newText)
        SetCursorPos(ins)
        EnterInsert("before")

    elseif key == "x" then
        if cur0 <= le0 and cur0 < #text then
            UndoPush()
            local newText = text:sub(1, cur0) .. text:sub(cur0+2)
            WiM.editor:SetText(newText)
            SetCursorPos(ClampToLine(cur0, newText))
            UpdateCursor()
        end

    elseif key == "D" then
        UndoPush()
        WiM.clipboard = text:sub(cur0+1, le0+1)
        local newText = text:sub(1, cur0) .. text:sub(le0+2)
        WiM.editor:SetText(newText)
        SetCursorPos(ClampToLine(cur0, newText))
        ShowStatus("Deleted to EOL", 1.5); UpdateCursor()

    elseif key == "v" then EnterVisual()

    elseif key == "p" then
        if WiM.clipboard ~= "" then
            UndoPush()
            local newT = text:sub(1, cur0+1) .. WiM.clipboard .. text:sub(cur0+2)
            WiM.editor:SetText(newT)
            SetCursorPos(ClampToLine(cur0 + #WiM.clipboard, newT))
            UpdateCursor()
        end
    elseif key == "P" then
        if WiM.clipboard ~= "" then
            UndoPush()
            local newT = text:sub(1, cur0) .. WiM.clipboard .. text:sub(cur0+1)
            WiM.editor:SetText(newT)
            SetCursorPos(ClampToLine(cur0 + #WiM.clipboard - 1, newT))
            UpdateCursor()
        end

    elseif key == "u" then
        UndoPop()

    elseif key == "n" then
        if WiM.searchQuery ~= "" then
            if #WiM.searchMatches == 0 then
                BuildSearchMatches(WiM.searchQuery)
            end
            SearchJump(1)
        else
            ShowStatus("No search pattern – use / to search", 2)
        end
    elseif key == "N" then
        if WiM.searchQuery ~= "" then
            if #WiM.searchMatches == 0 then
                BuildSearchMatches(WiM.searchQuery)
            end
            SearchJump(-1)
        else
            ShowStatus("No search pattern – use / to search", 2)
        end
    end
end

-- Full US-layout shifted-symbol map.
-- Without this, shift+1 → "1" (not "!"), shift+5 → "5" (not "%"), etc.
local SHIFT_MAP = {
    ["1"]=  "!", ["2"]= "@", ["3"]= "#", ["4"]= "$", ["5"]= "%",
    ["6"]=  "^", ["7"]= "&", ["8"]= "*", ["9"]= "(", ["0"]= ")",
    ["-"]=  "_", ["="]= "+", ["["]="{",  ["]"]= "}", ["\\"]="|",
    [";"]=  ":", ["'"]='"',  [","]=  "<", ["."]=">", ["/"]=  "?",
    ["`"]=  "~",
}


local function BuildFrame()
    local W, H = 640, 500
    local EDITOR_TOP_INSET = 2

    local f = CreateFrame("Frame", "WimFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={ left=4, right=4, top=4, bottom=4 },
    })
    f:SetBackdropColor(COL.BG.r, COL.BG.g, COL.BG.b, 0.97)
    f:SetBackdropBorderColor(COL.BORDER.r, COL.BORDER.g, COL.BORDER.b, 1)

    -- ── Key capture frame ──────────────────────────────────────────────
    local keyFrame = CreateFrame("Frame", "WimKeyFrame", f)
    keyFrame:SetAllPoints(f)
    keyFrame:EnableKeyboard(true)
    keyFrame:SetPropagateKeyboardInput(false)
    WiM.keyFrame = keyFrame

    keyFrame:SetScript("OnKeyDown", function(self, key)
        local ctrl  = IsControlKeyDown()
        local shift = IsShiftKeyDown()
        local dk = key
        if #key == 1 then
            if shift then
                dk = SHIFT_MAP[key] or key:upper()
            else
                dk = key:lower()
            end
        end
        HandleNormalKey(dk, ctrl, shift)
    end)

    -- ── Resize grip ────────────────────────────────────────────────────
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- ── Title bar ─────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then f:StartMoving() end
    end)
    titleBar:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    title:SetText("|cff33937fW|r|cff52c4afi|r|cff33937fm|r  -  Simple Vim Text Editor")
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")

    local badge = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("RIGHT", titleBar, "RIGHT", -10, 0)
    badge:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    WiM.modeBadge = badge

    -- ── Cursor-line highlight ──────────────────────────────────────────
    local cursorLine = f:CreateTexture(nil, "BACKGROUND")
    cursorLine:SetHeight(LINE_H + 2)
    cursorLine:Hide()
    WiM.cursorLine = cursorLine

    -- ── Line numbers ───────────────────────────────────────────────────
    local lineNumFrame = CreateFrame("Frame", nil, f)
    lineNumFrame:SetPoint("TOPLEFT",    f, "TOPLEFT",    6, -(32 + EDITOR_TOP_INSET))
    lineNumFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6,  28)
    lineNumFrame:SetWidth(38)

    local lineNums = lineNumFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lineNums:SetAllPoints()
    lineNums:SetJustifyH("RIGHT")
    lineNums:SetJustifyV("TOP")
    lineNums:SetFont("Fonts\\FRIZQT__.TTF", FONT_SIZE, "MONOCHROME")
    lineNums:SetTextColor(rgb(COL.MUTED))
    WiM.lineNums = lineNums

    -- ── Scroll + EditBox ───────────────────────────────────────────────
    local scroll = CreateFrame("ScrollFrame", "WimScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     50, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 28)

    local eb = CreateFrame("EditBox", "WimEditor", scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetWidth(W - 80)
    eb:SetFont("Fonts\\FRIZQT__.TTF", FONT_SIZE, "MONOCHROME")
    eb:SetTextColor(rgb(COL.TEXT))
    eb:SetTextInsets(4, 4, EDITOR_TOP_INSET, 2)
    eb:EnableMouse(true)

    eb:SetScript("OnMouseDown", function()
        if WiM.mode ~= "INSERT" then EnterInsert("before") end
    end)
    eb:SetScript("OnEscapePressed", function() EnterNormal() end)
    eb:SetScript("OnTabPressed", function(self)
        local pos = self:GetCursorPosition()
        local t   = self:GetText()
        self:SetText(t:sub(1,pos) .. "    " .. t:sub(pos+1))
        self:SetCursorPosition(pos+4)
    end)

    scroll:SetScrollChild(eb)
    eb:SetHeight(H - 64)
    WiM.editor = eb
    WiM.frame  = f
    WiM.scroll = scroll

    -- ── Status bar ─────────────────────────────────────────────────────
    local statusBar = CreateFrame("Frame", nil, f)
    statusBar:SetHeight(22)
    statusBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   6, 4)
    statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)

    local statusMsg = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusMsg:SetPoint("LEFT", statusBar, "LEFT", 4, 0)
    statusMsg:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    statusMsg:SetTextColor(rgb(COL.MUTED))
    WiM.statusMsg = statusMsg

    local posInfo = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    posInfo:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    posInfo:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    posInfo:SetTextColor(rgb(COL.MUTED))
    WiM.posInfo = posInfo

    -- ── Refresh callback ───────────────────────────────────────────────
    -- Memory-lean: line-number string is only rebuilt when the line COUNT
    -- changes; position string only when cursor or text length changes.
    local _lnCache  = { count = -1, str = "" }
    local _posCache = { cur = -1, len = -1 }

    local function Refresh()
        local text  = eb:GetText() or ""
        local cur0  = eb:GetCursorPosition()

        -- Line numbers – rebuild only when count changes
        local count = select(2, text:gsub("\n","")) + 1
        if count ~= _lnCache.count then
            _lnCache.count = count
            local t = {}
            for i = 1, count do t[i] = tostring(i) end
            _lnCache.str = table.concat(t, "\n")
            WiM.lineNums:SetText(_lnCache.str)
            -- Resize editbox height to content
            local numLines = math.max(1, eb:GetNumLines())
            eb:SetHeight(math.max(H-64, numLines*LINE_H+12))
        end

        -- Position readout – rebuild only when cursor or length changes
        local len = #text
        if cur0 ~= _posCache.cur or len ~= _posCache.len then
            _posCache.cur = cur0
            _posCache.len = len
            local line, col = 1, cur0
            for s, e in (text.."\n"):gmatch("()[^\n]*()\n") do
                if cur0 >= s-1 and cur0 <= e then
                    col = cur0-(s-1); break
                end
                line = line + 1
            end
            WiM.posInfo:SetText(string.format("Ln %d  Col %d  |%d|", line, col, len))
        end
    end

    eb:SetScript("OnTextChanged", function(self, userInput)
        Refresh()
        if WiM.mode == "NORMAL" then UpdateCursor() end
        if userInput and WiM.searchQuery ~= "" then
            WiM.searchMatches = {}
            WiM.searchIdx     = 0
        end
    end)
    eb:SetScript("OnCursorChanged", function()
        Refresh()
        if WiM.mode == "NORMAL" then UpdateCursor() end
    end)
    eb:SetScript("OnEditFocusGained", function() UpdateCursorLine() end)
    eb:SetScript("OnEditFocusLost",   function()
        if WiM.mode ~= "NORMAL" and WiM.mode ~= "INSERT" then
            WiM.cursorLine:Hide()
        end
    end)

    -- ── Persistent cursor tick ─────────────────────────────────────────
    -- Runs at ~12 Hz.  Block cursor (HighlightText) must be re-stamped
    -- every tick because WoW can silently clear it; everything else is
    -- guarded so no fresh tables/strings are allocated when idle.
    local _curTick  = 0
    local _lastCur0 = -1
    local _lastMode = ""

    f:SetScript("OnUpdate", function(_, elapsed)
        _curTick = _curTick + elapsed
        if _curTick < 0.08 then return end
        _curTick = 0

        local mode = WiM.mode
        local cur0 = GetCursorPos()
        local moved = (cur0 ~= _lastCur0) or (mode ~= _lastMode)
        _lastCur0 = cur0
        _lastMode = mode

        if mode == "NORMAL" then
            -- HighlightText must always be called so the block never vanishes
            UpdateCursor()
            if moved then UpdateCursorLine() end

        elseif mode == "VISUAL" then
            UpdateVisualHighlight()

        elseif mode == "INSERT" then
            if moved then UpdateCursorLine() end
        end
    end)

    -- ── Show / Hide hooks ──────────────────────────────────────────────
    f:HookScript("OnShow", function()
        local db = GetDB()
        if db.x and db.y then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
        end
        local lines, chars = TextStats(db.text or "")
        log:Event(string.format("opened - %d lines, %d chars in buffer", lines, chars))
        -- Instructional chat message styled to match ShodoQoL's color palette
        print("|cff33937f[ShodoQoL]|r |cff52c4afWiM|r"
            .. " Press |cff52c4af[Esc]|r |cff888888for NORMAL mode"
            .. "  -  then|r |cff52c4af[:q] [Enter]|r |cff888888to exit"
            .. "  -  |r|cff52c4af[:help]|r |cff888888for all commands|r")
    end)

    f:HookScript("OnHide", function()
        local db = GetDB()
        -- Always flush text on any close path (X button, /wim, etc.)
        db.text = eb:GetText()
        local x, y = f:GetLeft(), f:GetTop()
        if x and y then
            db.x = x
            db.y = y - UIParent:GetHeight()
        end
        log:Event("closed - text and position saved")
    end)

    -- Load saved text
    local db = GetDB()
    if db.text then eb:SetText(db.text) end

    EnterNormal()
    f:Hide()

    log:Info("frame built")
end

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------
local function WimToggle()
    if not WiM.frame then BuildFrame() end

    local f = WiM.frame
    if f:IsShown() then
        -- OnHide will save; just hide.
        log:Event("closed via /wim")
        f:Hide()
    else
        f:Show()
        EnterNormal()
    end
end

SLASH_WIM1 = "/wim"
SlashCmdList["WIM"] = WimToggle

------------------------------------------------------------------------
-- OnReady bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("Wim") then
        log:Info("disabled - skipping init")
        return
    end

    ShodoQoLDB.wim      = ShodoQoLDB.wim or {}
    ShodoQoLDB.wim.text = ShodoQoLDB.wim.text or ""

    log:Info("initialized - /wim to open")
end)
