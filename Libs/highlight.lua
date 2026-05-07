-- ShodoQoL/Libs/highlight.lua
-- Lua syntax highlighter for WiM.
--
-- Public surface (ShodoQoL.Highlight):
--   Highlight.Colorize(source)  → WoW colour-escaped string
--   Highlight.Strip(text)       → plain text with all |c…|r escapes removed
--
-- Single-pass tokeniser.  Emits WoW |cffRRGGBB…|r colour escapes inline
-- so the result drops straight into an EditBox via SetText().
--
-- Written for WoW Lua 5.1 — no goto, no ::labels::, no bit operators.
--
-- Token colours (ShodoQoL evoker palette):
--   Keywords      teal-green  #52c4af
--   Built-ins     sky-blue    #8fd4f8
--   Strings       amber       #e8c56d
--   Numbers       pale-gold   #d4b96a
--   Comments      muted-grey  #5a7a6e
--   Operators     bright-teal #33d4b8
--   WoW API       lavender    #b09af0  (CamelCase identifiers)
--   Plain text    off-white   #d9ebe3

------------------------------------------------------------------------
-- Namespace
------------------------------------------------------------------------
ShodoQoL.Highlight = ShodoQoL.Highlight or {}
local HL = ShodoQoL.Highlight

------------------------------------------------------------------------
-- Colour palette
------------------------------------------------------------------------
local C = {
    KEYWORD  = "52c4af",
    BUILTIN  = "8fd4f8",
    STRING   = "e8c56d",
    NUMBER   = "d4b96a",
    COMMENT  = "5a7a6e",
    OPERATOR = "33d4b8",
    WOWAPI   = "b09af0",
    PLAIN    = "d9ebe3",
}

local function Col(hex, text)
    return "|cff" .. hex .. text .. "|r"
end

------------------------------------------------------------------------
-- Keyword / built-in lookup tables
------------------------------------------------------------------------
local KEYWORDS = {
    ["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,
    ["end"]=1,["false"]=1,["for"]=1,["function"]=1,
    ["if"]=1,["in"]=1,["local"]=1,["nil"]=1,["not"]=1,
    ["or"]=1,["repeat"]=1,["return"]=1,["then"]=1,["true"]=1,
    ["until"]=1,["while"]=1,
}

local BUILTINS = {
    ["print"]=1,["type"]=1,["tostring"]=1,["tonumber"]=1,
    ["pairs"]=1,["ipairs"]=1,["next"]=1,["select"]=1,
    ["error"]=1,["assert"]=1,["pcall"]=1,["xpcall"]=1,
    ["loadstring"]=1,["load"]=1,["dofile"]=1,["loadfile"]=1,
    ["require"]=1,["rawget"]=1,["rawset"]=1,["rawequal"]=1,["rawlen"]=1,
    ["setmetatable"]=1,["getmetatable"]=1,
    ["unpack"]=1,["table"]=1,["string"]=1,["math"]=1,["io"]=1,
    ["os"]=1,["coroutine"]=1,["package"]=1,["debug"]=1,
    ["collectgarbage"]=1,["gcinfo"]=1,
    ["_G"]=1,["UIParent"]=1,["WorldFrame"]=1,
}

------------------------------------------------------------------------
-- Main tokeniser
-- Uses a single if/elseif/else chain per iteration — no goto needed.
------------------------------------------------------------------------
function HL.Colorize(src)
    if not src or src == "" then return "" end

    local out = {}
    local i   = 1
    local len = #src

    local function At(pos)    return src:sub(pos, pos) end
    local function Slice(s,e) return src:sub(s, e) end

    while i <= len do
        local ch  = At(i)
        local ch2 = Slice(i, i+1)

        if ch2 == "--" and src:match("^%[=*%[", i+2) then
            ----------------------------------------------------------------
            -- Long comment  --[=*[...]=*]
            ----------------------------------------------------------------
            local eqPat   = src:match("^(%[=*%[)", i+2)
            local eqCount = #eqPat - 2
            local closeP  = "%]" .. ("="):rep(eqCount) .. "%]"
            local closeS, closeE = src:find(closeP, i + 2 + #eqPat)
            local span
            if closeS then
                span = Slice(i, closeE)
                i    = closeE + 1
            else
                span = Slice(i, len)
                i    = len + 1
            end
            out[#out+1] = Col(C.COMMENT, span)

        elseif ch2 == "--" then
            ----------------------------------------------------------------
            -- Line comment  --...\n
            ----------------------------------------------------------------
            local eol = src:find("\n", i, true)
            local span = eol and Slice(i, eol - 1) or Slice(i, len)
            out[#out+1] = Col(C.COMMENT, span)
            i = eol and eol or len + 1

        elseif ch == "[" and src:match("^%[=*%[", i) then
            ----------------------------------------------------------------
            -- Long string  [=*[...]=*]
            ----------------------------------------------------------------
            local eqPat   = src:match("^(%[=*%[)", i)
            local eqCount = #eqPat - 2
            local closeP  = "%]" .. ("="):rep(eqCount) .. "%]"
            local closeS, closeE = src:find(closeP, i + #eqPat)
            local span
            if closeS then
                span = Slice(i, closeE)
                i    = closeE + 1
            else
                span = Slice(i, len)
                i    = len + 1
            end
            out[#out+1] = Col(C.STRING, span)

        elseif ch == '"' or ch == "'" then
            ----------------------------------------------------------------
            -- Quoted string  "..."  '...'
            ----------------------------------------------------------------
            local q = ch
            local j = i + 1
            while j <= len do
                local c = At(j)
                if c == "\\" then
                    j = j + 2
                elseif c == q then
                    j = j + 1
                    break
                elseif c == "\n" then
                    break
                else
                    j = j + 1
                end
            end
            out[#out+1] = Col(C.STRING, Slice(i, j - 1))
            i = j

        elseif ch:match("%d") or (ch == "." and At(i+1):match("%d")) then
            ----------------------------------------------------------------
            -- Number literal  (hex, decimal, float, scientific)
            ----------------------------------------------------------------
            local j = i
            if ch == "0" and (At(i+1) == "x" or At(i+1) == "X") then
                j = i + 2
                while j <= len and At(j):match("[%x]") do j = j + 1 end
            else
                while j <= len and At(j):match("%d") do j = j + 1 end
                if j <= len and At(j) == "." then
                    j = j + 1
                    while j <= len and At(j):match("%d") do j = j + 1 end
                end
                if j <= len and At(j):match("[eE]") then
                    j = j + 1
                    if j <= len and At(j):match("[%+%-]") then j = j + 1 end
                    while j <= len and At(j):match("%d") do j = j + 1 end
                end
            end
            out[#out+1] = Col(C.NUMBER, Slice(i, j - 1))
            i = j

        elseif ch:match("[%a_]") then
            ----------------------------------------------------------------
            -- Identifier: keyword / built-in / WoW API (CamelCase) / plain
            ----------------------------------------------------------------
            local j = i + 1
            while j <= len and At(j):match("[%w_]") do j = j + 1 end
            local word = Slice(i, j - 1)
            if KEYWORDS[word] then
                out[#out+1] = Col(C.KEYWORD, word)
            elseif BUILTINS[word] then
                out[#out+1] = Col(C.BUILTIN, word)
            elseif word:match("^[A-Z]") then
                -- CamelCase = probable WoW API (UnitHealth, GetItemInfo…)
                out[#out+1] = Col(C.WOWAPI, word)
            else
                out[#out+1] = Col(C.PLAIN, word)
            end
            i = j

        elseif ch == "\n" or ch == "\r" or ch == " " or ch == "\t" then
            ----------------------------------------------------------------
            -- Whitespace — pass through verbatim (preserves newlines)
            ----------------------------------------------------------------
            local j = i
            while j <= len and At(j):match("[ \t\r\n]") do j = j + 1 end
            out[#out+1] = Slice(i, j - 1)
            i = j

        elseif ch:match("[%+%-%*/%%^#<>=~%(%)%[%]{}%;:,%.!&|]") then
            ----------------------------------------------------------------
            -- Operators and punctuation — multi-char tokens first
            ----------------------------------------------------------------
            local op3 = Slice(i, i + 2)
            local op2 = ch2
            if op3 == "..." then
                out[#out+1] = Col(C.OPERATOR, "...")
                i = i + 3
            elseif op2 == "==" or op2 == "~=" or op2 == "<="
                or op2 == ">=" or op2 == ".." then
                out[#out+1] = Col(C.OPERATOR, op2)
                i = i + 2
            else
                out[#out+1] = Col(C.OPERATOR, ch)
                i = i + 1
            end

        else
            ----------------------------------------------------------------
            -- Fallback: unknown character, emit as plain text
            ----------------------------------------------------------------
            if ch ~= "" then
                out[#out+1] = Col(C.PLAIN, ch)
            end
            i = i + 1
        end
    end

    return table.concat(out)
end

------------------------------------------------------------------------
-- Strip all WoW colour escape sequences from a string.
-- Useful when you need the raw source for re-highlighting or diffing.
------------------------------------------------------------------------
function HL.Strip(text)
    if not text then return "" end
    -- Remove |cffRRGGBB…|r pairs
    text = text:gsub("|cff%x%x%x%x%x%x(.-)%|r", "%1")
    -- Remove any orphaned |r
    text = text:gsub("|r", "")
    return text
end
