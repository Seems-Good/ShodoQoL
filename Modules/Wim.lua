-- ShodoQoL/WiM.lua
-- Vim-style Text Editor - ShodoQoL module.
--
-- Open / close:  /wim
-- Inside editor: :help  shows the full keybinding reference.
--
-- Revision 8 (WSh integration):
--   - :term / :terminal   — open a WSh terminal panel inside the editor.
--       Type POSIX-style commands (ls, cd, mkdir, cat, edit …).
--       Press Esc or type 'exit' to return to the editor.
--   - :Ex                 — directory-explorer overlay.  Click dirs to
--       navigate, click files to open them in the editor.
--   - :e <file>           — open a VFS file directly (skips explorer).
--   - :w <file>           — write current buffer to a VFS path.
--   - :cd <path>          — change VFS working directory.
--   Previous revision features unchanged (line-jump {N}G, :%s substitute).

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

-- terminal
WiM._termOutput   = nil     -- accumulated terminal output string
WiM._preTermText  = nil     -- editor buffer saved before entering TERM
WiM._preTermCur   = nil     -- cursor position saved before entering TERM

-- explorer
WiM._exButtons  = {}      -- pool of entry buttons (reused across refreshes)
WiM._exActions  = {}      -- parallel action-function table for hjkl activation
WiM._exSelected = 1       -- 1-based currently-highlighted row
WiM._exRowCount = 0       -- total rows visible after last refresh

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
    NORMAL   = { r=0.32, g=0.77, b=0.69 },  -- #52c4af  evoker teal
    INSERT   = { r=0.38, g=0.90, b=0.55 },  -- brighter evoker green
    VISUAL   = { r=1.00, g=0.78, b=0.30 },  -- evoker amber / scale gold
    EX       = { r=0.65, g=0.90, b=0.82 },  -- pale mint-teal
    SEARCH   = { r=0.95, g=0.72, b=0.22 },  -- warm amber for search prompt
    TERM     = { r=0.45, g=0.95, b=0.65 },  -- bright green for terminal
    EXPLORER = { r=0.55, g=0.85, b=1.00 },  -- sky blue for explorer
    BG       = { r=0.04, g=0.06, b=0.05 },  -- near-black with green tint
    BORDER   = { r=0.20, g=0.58, b=0.50 },  -- ShodoQoL brand green
    TEXT     = { r=0.85, g=0.92, b=0.88 },  -- green-tinted off-white
    MUTED    = { r=0.28, g=0.43, b=0.38 },  -- muted teal-grey
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

------------------------------------------------------------------------
-- Visual highlight
------------------------------------------------------------------------
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
    -- cursorLine colour only applies to editing modes
    if WiM.cursorLine and mode ~= "TERM" then
        WiM.cursorLine:SetColorTexture(c.r, c.g, c.b, 0.70)
    end
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
-- Forward-declared so EnterTerminal / ExitTerminal can call it
local EnterNormal

EnterNormal = function()
    if WiM.mode == "INSERT" then UndoPush() end

    WiM.mode        = "NORMAL"
    WiM.visualStart = nil
    WiM.pendingKey  = nil
    WiM.pendingCount = ""
    WiM.exInput     = nil
    WiM.searchInput = nil

    -- Tear down ex-command bar if it was open
    if WiM.exInputBox    then WiM.exInputBox:ClearFocus(); WiM.exInputBox:Hide()    end
    if WiM.exPromptLabel then WiM.exPromptLabel:Hide()                              end
    if WiM.statusMsg     then WiM.statusMsg:Show()                                  end

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
-- Terminal mode  (:term / :terminal)
------------------------------------------------------------------------

-- ExitTerminal is defined before EnterTerminal so TerminalSubmit can reference it.
local function ExitTerminal()
    if WiM.mode ~= "TERM" then return end
    -- Restore UI
    if WiM.termBar   then WiM.termBar:Hide()          end
    if WiM.termInput then WiM.termInput:ClearFocus()  end
    if WiM.statusMsg then WiM.statusMsg:Show()         end
    if WiM.posInfo   then WiM.posInfo:Show()           end
    if WiM.lineNums  then WiM.lineNums:Show()          end
    -- Restore editor content
    WiM.editor:SetText(WiM._preTermText or "")
    SetCursorPos(math.min(WiM._preTermCur or 0, #(WiM._preTermText or "")))
    WiM._preTermText = nil
    WiM._preTermCur  = nil
    WiM._termOutput  = nil
    log:Event("terminal closed")
    EnterNormal()
end

local function TerminalPrompt()
    local CLI = ShodoQoL.CLI
    if not CLI then return "$ " end
    return CLI.GetCWD() .. " $ "
end

local function TerminalFlush()
    -- Write output buffer to editor and scroll to bottom
    WiM.editor:SetText(WiM._termOutput or "")
    local len = #(WiM._termOutput or "")
    SetCursorPos(len)
    WiM.scroll:SetVerticalScroll(WiM.scroll:GetVerticalScrollRange())
end

local function TerminalSubmit(line)
    local CLI = ShodoQoL.CLI
    if not CLI then ExitTerminal(); return end

    line = line and line:match("^%s*(.-)%s*$") or ""
    local cwdBefore = CLI.GetCWD()

    -- Handle 'clear' locally before calling RunCommand
    if line == "clear" then
        WiM._termOutput = TerminalPrompt()
        TerminalFlush()
        return
    end

    -- Append the submitted line (with prompt) to the output
    if line ~= "" then
        WiM._termOutput = (WiM._termOutput or "") .. cwdBefore .. " $ " .. line .. "\n"
    end

    -- Build the wimRef callback table
    local wimRef = {
        ExitTerminal  = ExitTerminal,
        GetEditorText = function() return WiM._preTermText or "" end,
        OpenFileInEditor = function(fname, content)
            ExitTerminal()
            UndoPush()
            WiM.editor:SetText(content)
            SetCursorPos(0)
            ShowStatus(string.format('"%s"  opened from VFS', fname), 2)
            log:Invoke(":edit", fname)
        end,
    }

    local output = CLI.RunCommand(line, wimRef)

    -- RunCommand may have called ExitTerminal (e.g. 'exit', 'edit')
    if WiM.mode ~= "TERM" then return end

    if output then
        WiM._termOutput = (WiM._termOutput or "") .. output .. "\n"
    end

    -- Append fresh prompt
    WiM._termOutput = (WiM._termOutput or "") .. TerminalPrompt()
    TerminalFlush()
end

local function EnterTerminal()
    local CLI = ShodoQoL.CLI
    if not CLI then
        ShowStatus("WSh: Libs/cli.lua not loaded", 3)
        log:Warn(":term - cli.lua unavailable")
        return
    end

    -- Save editor state
    WiM._preTermText = GetText()
    WiM._preTermCur  = GetCursorPos()

    -- Initial terminal buffer
    local home = "/home/" .. (UnitName("player") or "?"):lower()
    WiM._termOutput =
        "|cff52c4afWSh – WiM Shell|r  (type 'help' for commands, 'exit' to quit)\n"
        .. TerminalPrompt()

    WiM.mode = "TERM"
    SetModeBadge("TERM")

    -- Populate the read-only display
    WiM.editor:SetText(WiM._termOutput)
    SetCursorPos(#WiM._termOutput)
    WiM.scroll:SetVerticalScroll(WiM.scroll:GetVerticalScrollRange())

    -- Hide editor chrome that doesn't apply in terminal
    if WiM.lineNums  then WiM.lineNums:Hide()  end
    if WiM.cursorLine then WiM.cursorLine:Hide() end

    -- Show terminal input bar
    if WiM.statusMsg then WiM.statusMsg:Hide() end
    if WiM.posInfo   then WiM.posInfo:Hide()   end
    if WiM.termBar   then WiM.termBar:Show()   end
    if WiM.termInput then
        WiM.termInput:SetText("")
        -- Defer one tick so the editor's ClearFocus has settled; prevents WoW
        -- from stealing focus to the game chatbox.
        C_Timer.After(0, function()
            if WiM.mode == "TERM" then WiM.termInput:SetFocus() end
        end)
    end

    -- Disable keyFrame so it doesn't compete with termInput for keystrokes.
    -- Propagation stays FALSE so keystrokes never reach the game chatbox.
    WiM.keyFrame:EnableKeyboard(false)
    WiM.keyFrame:SetPropagateKeyboardInput(false)

    log:Event("terminal opened")
end

------------------------------------------------------------------------
-- Explorer mode  (:Ex)
------------------------------------------------------------------------

-- Highlight the row at `idx`, scroll it into view.
local function ExplorerHighlight(idx)
    -- Clamp to valid range
    local n = WiM._exRowCount
    if n == 0 then return end
    idx = math.max(1, math.min(n, idx))

    -- Deselect old row
    local old = WiM._exButtons[WiM._exSelected]
    if old and old._sel then old._sel:Hide() end

    WiM._exSelected = idx

    -- Select new row
    local btn = WiM._exButtons[idx]
    if not btn then return end
    if btn._sel then btn._sel:Show() end

    -- Scroll exScroll so the row is visible
    if WiM.exScroll then
        local btnH   = 24   -- btnHeight + btnPad
        local rowTop = (idx - 1) * btnH
        local rowBot = rowTop + btnH
        local sv     = WiM.exScroll:GetVerticalScroll()
        local viewH  = WiM.exScroll:GetHeight()
        if rowTop < sv then
            WiM.exScroll:SetVerticalScroll(rowTop)
        elseif rowBot > sv + viewH then
            WiM.exScroll:SetVerticalScroll(rowBot - viewH)
        end
    end
end

local function CloseExplorer()
    if WiM.exPanel then WiM.exPanel:Hide() end
    EnterNormal()
    log:Event("explorer closed")
end

-- Forward-declared so RefreshExplorer can be called recursively on navigate.
local RefreshExplorer

RefreshExplorer = function(targetPath)
    local CLI = ShodoQoL.CLI
    if not CLI then return end

    -- Navigate to targetPath if given
    if targetPath then CLI.RunCommand("cd " .. targetPath) end

    local entries, cwd = CLI.ListDir()

    -- Update title  (hjkl hint in header)
    if WiM.exTitle then
        WiM.exTitle:SetText(
            "|cff33937fEx|r  |cff888888" .. cwd
            .. "  |r|cff52c4afj/k|r|cff888888=move  |r"
            .. "|cff52c4afl|r|cff888888=open  "
            .. "|r|cff52c4afh|r|cff888888=parent  "
            .. "|r|cff52c4af:q|r|cff888888=back|r")
    end

    -- Reset nav state
    WiM._exActions  = {}
    WiM._exRowCount = 0

    -- Hide all recycled buttons
    for _, btn in ipairs(WiM._exButtons) do btn:Hide() end

    local panel     = WiM.exContent
    local btnHeight = 22
    local btnPad    = 2

    local function MakeOrRecycle(idx)
        local btn = WiM._exButtons[idx]
        if not btn then
            btn = CreateFrame("Button", nil, panel)
            btn:SetHeight(btnHeight)
            btn:EnableMouse(true)

            -- Hover highlight (mouse)
            local hov = btn:CreateTexture(nil, "BACKGROUND")
            hov:SetAllPoints()
            hov:SetColorTexture(0.20, 0.58, 0.50, 0.18)
            hov:Hide()
            btn._hov = hov

            -- Selection highlight (keyboard cursor) — drawn above hover
            local sel = btn:CreateTexture(nil, "ARTWORK")
            sel:SetAllPoints()
            sel:SetColorTexture(0.55, 0.85, 1.00, 0.28)
            sel:Hide()
            btn._sel = sel

            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("LEFT",  btn, "LEFT",  8, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            fs:SetJustifyH("LEFT")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "MONOCHROME")
            btn._label = fs

            btn:SetScript("OnEnter", function(s) s._hov:Show() end)
            btn:SetScript("OnLeave", function(s) s._hov:Hide() end)

            WiM._exButtons[idx] = btn
        end
        btn._sel:Hide()   -- always reset selection on recycle
        btn:Show()
        return btn
    end

    -- Row helper: registers both the visual button and the action for hjkl
    local rowIdx = 0
    local function AddRow(label, color, action)
        rowIdx = rowIdx + 1
        local btn = MakeOrRecycle(rowIdx)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -(rowIdx-1)*(btnHeight+btnPad))
        btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(rowIdx-1)*(btnHeight+btnPad))
        btn._label:SetText("|cff" .. color .. label .. "|r")
        btn:SetScript("OnClick", action)         -- mouse still works
        WiM._exActions[rowIdx] = action          -- keyboard path
    end

    -- ".." parent dir entry (never at root)
    if cwd ~= "/" then
        local parent = cwd:match("^(.+)/[^/]+$") or "/"
        AddRow("  ../", "52c4af", function() RefreshExplorer(parent) end)
    end

    -- Directory and file entries
    for _, e in ipairs(entries) do
        local ePath = e.path
        local eType = e.type
        local eName = e.name
        if eType == "dir" then
            AddRow("  " .. eName .. "/", "52c4af", function()
                RefreshExplorer(ePath)
            end)
        else
            AddRow("  " .. eName, "c8d8cc", function()
                local content, err = CLI.ReadFile(ePath)
                CloseExplorer()
                if err then
                    ShowStatus("E: " .. err, 3)
                else
                    UndoPush()
                    WiM.editor:SetText(content)
                    SetCursorPos(0)
                    ShowStatus(string.format('"%s"  %dL', eName, select(1, TextStats(content))), 2)
                    log:Invoke(":Ex open", ePath)
                end
            end)
        end
    end

    if rowIdx == 0 then
        AddRow("  (empty directory)", "666666", function() end)
    end

    WiM._exRowCount = rowIdx
    panel:SetHeight(math.max(1, rowIdx * (btnHeight + btnPad)))
    WiM.exPanel:Show()

    -- Restore / initialise selection cursor (clamp in case dir got smaller)
    ExplorerHighlight(math.min(WiM._exSelected, rowIdx))

    log:Event("explorer refresh – " .. cwd .. "  (" .. rowIdx .. " entries)")
end

local function OpenExplorer()
    local CLI = ShodoQoL.CLI
    if not CLI then
        ShowStatus("WSh: Libs/cli.lua not loaded", 3)
        log:Warn(":Ex - cli.lua unavailable")
        return
    end
    -- Switch to EXPLORER mode: keyFrame stays enabled and non-propagating so
    -- hjkl, ESC, and ':' are all captured inside Wim (no chatbox leak).
    WiM.mode = "EXPLORER"
    SetModeBadge("EXPLORER")
    WiM._exSelected = 1
    WiM.keyFrame:EnableKeyboard(true)
    WiM.keyFrame:SetPropagateKeyboardInput(false)
    RefreshExplorer()
    log:Event("explorer opened")
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
  Input is captured in the WiM status bar – the game chatbox never opens.
  Navigation inside the command bar:
    h / l          move cursor left / right within the typed command
    j / k          scroll the editor buffer up / down (preview while typing)
    Arrow keys     also move cursor left / right
    Backspace      delete character
    Enter          execute the command
    Esc            cancel and return to NORMAL
  :w             save buffer to SavedVariables
  :w  <file>     write buffer to VFS file
  :q             close window
  :wq  /  :x     save and close
  :q!            close without saving
  :help          show this screen
  Note: because h and l navigate the command cursor, type :he<Arrow>lp
        or use the mouse cursor to reach :help if needed.

FILESYSTEM / SHELL
  :Ex            open directory-explorer panel
  :e  <file>     open VFS file in editor
  :cd <path>     change VFS working directory
  :term          open WSh terminal  (full POSIX-style shell)
  :terminal      alias for :term

  Inside the terminal, input goes to the WiM terminal bar – not the
  game chatbox.  Type 'help' for all shell commands.
  Type 'exit' (or press Esc) to close the terminal and return to the
  last editor buffer.

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
    WiM.editor:ClearFocus()
    -- Disable keyFrame so the game chatbox is never activated.
    -- The exInputBox EditBox captures all typing directly inside Wim.
    WiM.keyFrame:EnableKeyboard(false)
    WiM.keyFrame:SetPropagateKeyboardInput(false)
    if WiM.cursorLine then WiM.cursorLine:Hide() end
    -- Show the inline ex-command bar
    if WiM.statusMsg     then WiM.statusMsg:Hide()           end
    if WiM.exPromptLabel then WiM.exPromptLabel:Show()       end
    if WiM.exInputBox then
        WiM.exInputBox:Show()
        WiM.exInputBox:SetText("")
        -- Defer focus one tick so the editor's ClearFocus has settled
        C_Timer.After(0, function()
            if WiM.mode == "EX" then WiM.exInputBox:SetFocus() end
        end)
    end
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
    -- Prefer the live text from the dedicated EditBox; fall back to WiM.exInput
    -- (which keyFrame-based callers may have set).
    local src = (WiM.exInputBox and WiM.exInputBox:GetText()) or WiM.exInput or ""
    local raw = src:match("^%s*(.-)%s*$")   -- full trimmed input
    local cmdWord = raw:match("^(%S+)") or ""            -- first word
    local cmdArgs = raw:match("^%S+%s+(.-)%s*$")        -- everything after first word

    log:Invoke(":" .. raw)

    -- ── Core editor commands ──────────────────────────────────────────
    if cmdWord == "q" or cmdWord == "q!" then
        if WiM._preHelpText then
            WiM.editor:SetText(WiM._preHelpText)
            WiM._preHelpText = nil
            SetCursorPos(WiM._preHelpCur or 0)
            EnterNormal()
            log:Info(":help closed - previous buffer restored")
        else
            GetDB().text = WiM.editor:GetText()
            log:Event("closed via :" .. cmdWord)
            WiM.frame:Hide()
        end

    elseif cmdWord == "w" and not cmdArgs then
        -- plain :w → save to SavedVariables
        WiM._preHelpText = nil
        SaveText()
        EnterNormal()
        ShowStatus("Written to SavedVariables", 1.5)

    elseif cmdWord == "w" and cmdArgs then
        -- :w <file> → write to VFS
        local CLI = ShodoQoL.CLI
        if not CLI then
            EnterNormal()
            ShowStatus("WSh: Libs/cli.lua not loaded", 3); return
        end
        local content = GetText()
        local path, err = CLI.WriteFile(cmdArgs, content)
        EnterNormal()
        if err then
            ShowStatus("E: " .. err, 3)
            log:Warn(":w - " .. err)
        else
            ShowStatus(string.format('"%s"  %dB written', path, #content), 2)
            log:Invoke(":w", path)
        end

    elseif cmdWord == "wq" or cmdWord == "x" then
        WiM._preHelpText = nil
        SaveText()
        log:Event("closed via :" .. cmdWord .. " (saved)")
        WiM.frame:Hide()

    elseif cmdWord == "help" then
        ShowHelp()

    -- ── Filesystem / shell commands ───────────────────────────────────
    elseif cmdWord == "Ex" or cmdWord == "ex" then
        EnterNormal()
        OpenExplorer()

    elseif cmdWord == "term" or cmdWord == "terminal" then
        EnterNormal()
        EnterTerminal()

    elseif cmdWord == "e" and cmdArgs then
        -- :e <file>  open VFS file in editor
        local CLI = ShodoQoL.CLI
        if not CLI then
            EnterNormal()
            ShowStatus("WSh: Libs/cli.lua not loaded", 3); return
        end
        local content, err = CLI.ReadFile(cmdArgs)
        if err then
            EnterNormal()
            ShowStatus("E: " .. err, 3)
            log:Warn(":e - " .. err)
        else
            UndoPush()
            WiM.editor:SetText(content)
            SetCursorPos(0)
            EnterNormal()
            local lc = select(1, TextStats(content))
            ShowStatus(string.format('"%s"  %dL', cmdArgs, lc), 2)
            log:Invoke(":e", cmdArgs)
        end

    elseif cmdWord == "cd" then
        -- :cd [path]  change VFS working directory
        local CLI = ShodoQoL.CLI
        if not CLI then
            EnterNormal()
            ShowStatus("WSh: Libs/cli.lua not loaded", 3); return
        end
        local dest = cmdArgs or "~"
        local out  = CLI.RunCommand("cd " .. dest)
        EnterNormal()
        if out then
            ShowStatus(out, 3)
        else
            ShowStatus("cd: " .. CLI.GetCWD(), 2)
        end

    -- ── Substitute  :%s/pat/rep/[g]  or  :s/pat/rep/[g] ─────────────
    else
        local d = raw:match("^%%?s(.)")
        local pat, rep, flags
        if d then
            local de = d:gsub("[%(%)%.%%%+%-%*%?%[%^%$]", "%%%1")
            pat, rep, flags = raw:match(
                "^%%?s" .. de .. "(.-)" .. de .. "(.-)" .. de .. "(.-)$")
            if not pat then
                pat, rep = raw:match(
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
            log:Warn("unknown ex command: " .. raw)
            ShowStatus("E492: Not an editor command: " .. raw, 2)
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
-- TERM mode: keyFrame is disabled; the terminal EditBox handles keys.
------------------------------------------------------------------------
local function HandleNormalKey(key, ctrl, shift)
    -- TERM mode keys are eaten by the termInput EditBox, not here.
    if WiM.mode == "TERM" then return end

    local text = GetText()
    local cur0 = GetCursorPos()

    -- ── EXPLORER mode ────────────────────────────────────────────────
    -- All navigation stays inside the explorer panel; the editor cursor
    -- must never move while the panel is open.
    if WiM.mode == "EXPLORER" then
        if key == "ESCAPE" or key == "q" then
            CloseExplorer()
        elseif key == "j" or key == "DOWN" then
            ExplorerHighlight(WiM._exSelected + 1)
        elseif key == "k" or key == "UP" then
            ExplorerHighlight(WiM._exSelected - 1)
        elseif key == "l" or key == "RIGHT" or key == "ENTER" or key == "NUMPADENTER" then
            -- Activate the currently highlighted row
            local action = WiM._exActions[WiM._exSelected]
            if action then action() end
        elseif key == "h" or key == "LEFT" then
            -- Navigate to parent directory
            local CLI = ShodoQoL.CLI
            if CLI then
                local cwd    = CLI.GetCWD()
                local parent = cwd:match("^(.+)/[^/]+$") or "/"
                if parent ~= cwd then RefreshExplorer(parent) end
            end
        end
        return
    end

    -- ── EX mode ──────────────────────────────────────────────────────
    -- Character input is now handled by WiM.exInputBox (an EditBox in the
    -- status bar).  The keyFrame is disabled while exInputBox has focus, so
    -- this branch is only reached if something unexpected re-enables it.
    -- Keep the ESCAPE safety-net just in case.
    if WiM.mode == "EX" then
        if key == "ESCAPE" then EnterNormal() end
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
        WiM.pendingCount = WiM.pendingCount .. key
        ShowStatus("-- NORMAL --  " .. WiM.pendingCount)
        return

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
local SHIFT_MAP = {
    ["1"]=  "!", ["2"]= "@", ["3"]= "#", ["4"]= "$", ["5"]= "%",
    ["6"]=  "^", ["7"]= "&", ["8"]= "*", ["9"]= "(", ["0"]= ")",
    ["-"]=  "_", ["="]= "+", ["["]="{",  ["]"]= "}", ["\\"]="|",
    [";"]=  ":", ["'"]='"',  [","]=  "<", ["."]=">", ["/"]=  "?",
    ["`"]=  "~",
}

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------
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
        if WiM.mode ~= "INSERT" and WiM.mode ~= "TERM" then EnterInsert("before") end
    end)
    eb:SetScript("OnEscapePressed", function()
        if WiM.mode == "TERM" then ExitTerminal()
        else EnterNormal() end
    end)
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

    -- ── Ex command bar (visible only in EX mode) ────────────────────────
    -- A ":" prompt label + an EditBox sit in the same space as statusMsg.
    -- They are shown/hidden by EnterEx / EnterNormal so they never overlap.
    local exPromptLabel = statusBar:CreateFontString(nil, "OVERLAY")
    exPromptLabel:SetPoint("LEFT", statusBar, "LEFT", 4, 0)
    exPromptLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    exPromptLabel:SetTextColor(rgb(COL.EX))
    exPromptLabel:SetText(":")
    exPromptLabel:Hide()
    WiM.exPromptLabel = exPromptLabel

    local exInputBox = CreateFrame("EditBox", "WimExInput", statusBar)
    exInputBox:SetPoint("LEFT",  exPromptLabel, "RIGHT",  2, 0)
    exInputBox:SetPoint("RIGHT", posInfo,       "LEFT",  -8, 0)
    exInputBox:SetHeight(18)
    exInputBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "MONOCHROME")
    exInputBox:SetTextColor(rgb(COL.EX))
    exInputBox:SetAutoFocus(false)
    exInputBox:SetMaxLetters(500)
    exInputBox:SetMultiLine(false)
    exInputBox:Hide()

    -- ENTER → run the command
    exInputBox:SetScript("OnEnterPressed", function(self)
        WiM.exInput = self:GetText()
        ExExecute()
    end)
    -- ESC → cancel, return to NORMAL
    exInputBox:SetScript("OnEscapePressed", function()
        EnterNormal()
    end)
    -- While the EditBox has focus, keep the keyFrame out of the picture so
    -- keystrokes are never forwarded to the game chatbox.
    exInputBox:SetScript("OnEditFocusGained", function()
        WiM.keyFrame:EnableKeyboard(false)
        WiM.keyFrame:SetPropagateKeyboardInput(false)
    end)
    -- ── Ex command bar key handling ────────────────────────────────────
    -- IMPORTANT: EditBox:SetPropagateKeyboardInput() is a protected function
    -- in WoW's secure execution environment.  Calling it from an OnKeyDown
    -- script triggers ADDON_ACTION_BLOCKED and breaks focus management.
    --
    -- The correct approach: keyFrame already has propagation locked to false
    -- for the entire WiM frame (set in EnterEx and OnEditFocusGained above).
    -- That single parent-level lock is sufficient to prevent any keystroke
    -- from leaking to the game chatbox.  We therefore never touch propagation
    -- on the EditBox itself – we simply act on the keys we care about and let
    -- the EditBox process everything else normally.
    --
    -- h / l  →  move the command-line cursor left / right
    -- j / k  →  scroll the editor buffer up / down (preview while typing)
    -- All other keys (letters, digits, SPACE, BACKSPACE, arrows, ENTER, ESC)
    -- fall through to the EditBox's default handling untouched.
    exInputBox:SetScript("OnKeyDown", function(self, key)
        if key == "h" then
            self:SetCursorPosition(math.max(0, self:GetCursorPosition() - 1))
        elseif key == "l" then
            self:SetCursorPosition(
                math.min(#(self:GetText() or ""), self:GetCursorPosition() + 1))
        elseif key == "j" then
            if WiM.scroll then
                WiM.scroll:SetVerticalScroll(math.min(
                    WiM.scroll:GetVerticalScrollRange(),
                    WiM.scroll:GetVerticalScroll() + LINE_H))
            end
        elseif key == "k" then
            if WiM.scroll then
                WiM.scroll:SetVerticalScroll(
                    math.max(0, WiM.scroll:GetVerticalScroll() - LINE_H))
            end
        end
        -- No SetPropagateKeyboardInput calls here – see comment above.
    end)

    WiM.exInputBox = exInputBox

    -- ── Terminal input bar (visible only in TERM mode) ─────────────────
    -- Positioned identically to statusBar; the two never overlap because
    -- statusMsg/posInfo are hidden whenever termBar is shown.
    local termBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    termBar:SetHeight(22)
    termBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   6, 4)
    termBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 4)
    termBar:SetBackdrop({
        bgFile  = "Interface\\ChatFrame\\ChatFrameBackground",
        tile=true, tileSize=8,
        insets={ left=2, right=2, top=2, bottom=2 },
    })
    termBar:SetBackdropColor(0.06, 0.10, 0.08, 0.95)
    termBar:Hide()

    local termPromptLabel = termBar:CreateFontString(nil, "OVERLAY")
    termPromptLabel:SetPoint("LEFT", termBar, "LEFT", 4, 0)
    termPromptLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    termPromptLabel:SetText("|cff52c4af>|r")

    local termInput = CreateFrame("EditBox", "WimTermInput", termBar)
    termInput:SetPoint("LEFT",  termPromptLabel, "RIGHT", 4, 0)
    termInput:SetPoint("RIGHT", termBar, "RIGHT", -4, 0)
    termInput:SetHeight(18)
    termInput:SetFont("Fonts\\FRIZQT__.TTF", 11, "MONOCHROME")
    termInput:SetTextColor(rgb(COL.TEXT))
    termInput:SetAutoFocus(false)
    termInput:SetMaxLetters(500)
    termInput:SetMultiLine(false)

    termInput:SetScript("OnEnterPressed", function(self)
        local line = self:GetText()
        self:SetText("")
        TerminalSubmit(line)
    end)
    termInput:SetScript("OnEscapePressed", function()
        ExitTerminal()
    end)
    -- Keep keyFrame off while terminal is active; never propagate to the game.
    termInput:SetScript("OnEditFocusGained", function()
        WiM.keyFrame:EnableKeyboard(false)
        WiM.keyFrame:SetPropagateKeyboardInput(false)
    end)

    WiM.termBar   = termBar
    WiM.termInput = termInput

    -- ── Explorer panel (:Ex) ───────────────────────────────────────────
    local exPanel = CreateFrame("Frame", "WimExPanel", f, "BackdropTemplate")
    exPanel:SetPoint("TOPLEFT",     f, "TOPLEFT",     50, -32)
    exPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 28)
    exPanel:SetFrameStrata("DIALOG")
    exPanel:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=12,
        insets={ left=3, right=3, top=3, bottom=3 },
    })
    exPanel:SetBackdropColor(COL.BG.r, COL.BG.g, COL.BG.b, 0.98)
    exPanel:SetBackdropBorderColor(0.32, 0.77, 0.69, 0.80)
    exPanel:Hide()

    -- Explorer header
    local exTitle = exPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exTitle:SetPoint("TOPLEFT",  exPanel, "TOPLEFT",  10, -10)
    exTitle:SetPoint("TOPRIGHT", exPanel, "TOPRIGHT", -40, -10)
    exTitle:SetJustifyH("LEFT")
    exTitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    WiM.exTitle = exTitle

    -- Explorer close button
    local exClose = CreateFrame("Button", nil, exPanel)
    exClose:SetSize(18, 18)
    exClose:SetPoint("TOPRIGHT", exPanel, "TOPRIGHT", -8, -8)
    local exCloseTex = exClose:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exCloseTex:SetAllPoints()
    exCloseTex:SetJustifyH("CENTER")
    exCloseTex:SetText("|cffff6060X|r")
    exClose:SetScript("OnClick", CloseExplorer)

    -- Divider line below header
    local exDiv = exPanel:CreateTexture(nil, "ARTWORK")
    exDiv:SetPoint("TOPLEFT",  exTitle, "BOTTOMLEFT",  0, -6)
    exDiv:SetPoint("TOPRIGHT", exTitle, "BOTTOMRIGHT", 0, -6)
    exDiv:SetHeight(1)
    exDiv:SetColorTexture(0.20, 0.58, 0.50, 0.45)

    -- Scrollable content
    local exScroll = CreateFrame("ScrollFrame", "WimExScroll", exPanel,
        "UIPanelScrollFrameTemplate")
    exScroll:SetPoint("TOPLEFT",     exDiv,    "BOTTOMLEFT",  0, -4)
    exScroll:SetPoint("BOTTOMRIGHT", exPanel, "BOTTOMRIGHT", -24, 6)

    local exContent = CreateFrame("Frame", nil, exScroll)
    exContent:SetWidth(exScroll:GetWidth() or 400)
    exContent:SetHeight(1)   -- will be resized by RefreshExplorer
    exScroll:SetScrollChild(exContent)
    WiM.exPanel   = exPanel
    WiM.exContent = exContent
    WiM.exScroll  = exScroll

    -- ── Refresh callback ───────────────────────────────────────────────
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
        if WiM.mode == "TERM" then return end   -- don't update chrome in terminal
        Refresh()
        if WiM.mode == "NORMAL" then UpdateCursor() end
        if userInput and WiM.searchQuery ~= "" then
            WiM.searchMatches = {}
            WiM.searchIdx     = 0
        end
    end)
    eb:SetScript("OnCursorChanged", function()
        if WiM.mode == "TERM" then return end
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
    local _curTick  = 0
    local _lastCur0 = -1
    local _lastMode = ""

    f:SetScript("OnUpdate", function(_, elapsed)
        _curTick = _curTick + elapsed
        if _curTick < 0.08 then return end
        _curTick = 0

        local mode = WiM.mode
        if mode == "TERM" then return end   -- no cursor work in terminal

        local cur0  = GetCursorPos()
        local moved = (cur0 ~= _lastCur0) or (mode ~= _lastMode)
        _lastCur0 = cur0
        _lastMode = mode

        if mode == "NORMAL" then
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
        print("|cff33937f[ShodoQoL]|r |cff52c4afWiM|r"
            .. " Press |cff52c4af[Esc]|r |cff888888for NORMAL mode"
            .. "  -  then|r |cff52c4af[:q] [Enter]|r |cff888888to exit"
            .. "  -  |r|cff52c4af[:help]|r |cff888888for all commands|r")
    end)

    f:HookScript("OnHide", function()
        local db = GetDB()

        if WiM.mode == "TERM" then
            -- Save the pre-terminal text, not the terminal output
            db.text = WiM._preTermText or ""
            -- Minimal cleanup without full ExitTerminal transition
            WiM._preTermText = nil
            WiM._preTermCur  = nil
            WiM._termOutput  = nil
            if WiM.termBar   then WiM.termBar:Hide()         end
            if WiM.termInput then WiM.termInput:ClearFocus() end
            if WiM.statusMsg then WiM.statusMsg:Show()        end
            if WiM.posInfo   then WiM.posInfo:Show()          end
            if WiM.lineNums  then WiM.lineNums:Show()         end
            WiM.mode = "NORMAL"
        elseif WiM.mode == "EX" then
            -- Clean up ex input bar without triggering EnterNormal side-effects
            if WiM.exInputBox    then WiM.exInputBox:ClearFocus(); WiM.exInputBox:Hide()    end
            if WiM.exPromptLabel then WiM.exPromptLabel:Hide()                              end
            if WiM.statusMsg     then WiM.statusMsg:Show()                                  end
            db.text = eb:GetText()
            WiM.mode = "NORMAL"
        else
            db.text = eb:GetText()
        end

        -- Always close explorer if open
        if WiM.exPanel and WiM.exPanel:IsShown() then WiM.exPanel:Hide() end

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
