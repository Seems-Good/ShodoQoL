-- ShodoQoL/Libs/repl.lua
-- WSh REPL – execute arbitrary Lua inside the live WoW environment.
--
-- Public surface (ShodoQoL.REPL):
--   REPL.Exec(line)            → output string   (never throws)
--   REPL.ExecMulti(src)        → output string   (multi-line chunk)
--   REPL.HistoryPrev()         → string | nil
--   REPL.HistoryNext()         → string | nil
--   REPL.HistoryPush(line)
--   REPL.Reset()               → clears the persistent environment
--
-- The REPL runs inside a sandboxed-but-rich environment:
--   • All standard WoW globals are accessible (UnitHealth, GetItemInfo, …)
--   • A local `_ENV` accumulates variables set between calls (persistent
--     across REPL lines in the same session, reset by REPL.Reset()).
--   • Return values from expressions are pretty-printed automatically.
--   • Errors are caught by pcall and shown inline — they never crash WoW.
--
-- Multi-line detection:
--   If loadstring() fails with a "near '<eof>'" error the line is
--   buffered as an incomplete chunk; subsequent lines are appended until
--   the chunk either succeeds or produces a non-EOF error.

------------------------------------------------------------------------
-- Namespace
------------------------------------------------------------------------
ShodoQoL.REPL = ShodoQoL.REPL or {}
local REPL = ShodoQoL.REPL

local HISTORY_MAX = 50

------------------------------------------------------------------------
-- Persistent REPL environment
-- Starts as a proxy of _G so every WoW API is reachable, but new
-- variables are stored in the local `_replEnv` table rather than the
-- real global table.
------------------------------------------------------------------------
local _replEnv   = {}      -- user-defined vars survive across Exec() calls
local _replChunk = ""      -- buffered incomplete multi-line input
local _history   = {}      -- ring of submitted lines
local _histIdx   = 0       -- navigation cursor (0 = at live input)

-- Build the execution environment table.
-- __index falls through to _G so all WoW globals are accessible.
-- __newindex writes into _replEnv (not _G) to keep the sandbox clean.
local _envMeta = {
    __index    = function(_, k) return _replEnv[k] ~= nil and _replEnv[k] or _G[k] end,
    __newindex = function(_, k, v) _replEnv[k] = v end,
}
local _env = setmetatable({}, _envMeta)

------------------------------------------------------------------------
-- Pretty-printer
-- Converts up to 3 levels of table nesting to a readable string.
-- Avoids infinite recursion via a seen-table guard.
------------------------------------------------------------------------
local function Pretty(val, depth, seen)
    depth = depth or 0
    seen  = seen  or {}
    local t = type(val)

    if t == "nil"     then return "nil"
    elseif t == "boolean" then return tostring(val)
    elseif t == "number"  then
        -- Show integers without decimal point
        if val == math.floor(val) and math.abs(val) < 1e15 then
            return string.format("%d", val)
        else
            return string.format("%g", val)
        end
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "function" then
        return tostring(val)   -- "function: 0x…"
    elseif t == "table" then
        if seen[val] then return "{...}" end
        if depth >= 2 then return "{...}" end
        seen[val] = true
        local parts = {}
        -- Array part
        local maxn = 0
        for k, v in pairs(val) do
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                maxn = math.max(maxn, k)
            end
        end
        for idx = 1, maxn do
            parts[#parts+1] = Pretty(val[idx], depth+1, seen)
        end
        -- Hash part
        local hcount = 0
        for k, v in pairs(val) do
            local skip = (type(k) == "number" and k == math.floor(k)
                          and k >= 1 and k <= maxn)
            if not skip then
                hcount = hcount + 1
                if hcount <= 12 then   -- cap hash output to avoid spam
                    local ks = type(k) == "string"
                               and k:match("^[%a_][%w_]*$")
                               and k
                               or  ("[" .. Pretty(k, depth+1, seen) .. "]")
                    parts[#parts+1] = ks .. "=" .. Pretty(v, depth+1, seen)
                elseif hcount == 13 then
                    parts[#parts+1] = "..."
                end
            end
        end
        seen[val] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return tostring(val)   -- userdata, thread, etc.
    end
end

local function PrettyList(...)
    local n    = select("#", ...)
    local parts = {}
    for idx = 1, n do
        parts[#parts+1] = Pretty(select(idx, ...))
    end
    return table.concat(parts, "\t")
end

------------------------------------------------------------------------
-- Core executor
-- Tries "return <src>" first (expression mode), falls back to statement
-- mode.  Returns a formatted result string.
------------------------------------------------------------------------
local function TryLoad(src)
    -- WoW uses Lua 5.1 — loadstring is available and unrestricted for addons
    local fn, err

    -- Expression mode: wrap in return so bare expressions print their value
    fn, err = loadstring("return " .. src, "repl")
    if fn then
        setfenv(fn, _env)
        return fn, nil, true   -- fn, err, isExpr
    end

    -- Statement mode
    fn, err = loadstring(src, "repl")
    if fn then
        setfenv(fn, _env)
        return fn, nil, false
    end

    return nil, err, false
end

------------------------------------------------------------------------
-- Public: execute a single line (or continued chunk)
------------------------------------------------------------------------
function REPL.Exec(line)
    line = line or ""

    -- Append to any buffered incomplete chunk
    local src = (_replChunk ~= "") and (_replChunk .. "\n" .. line) or line

    local fn, err, isExpr = TryLoad(src)

    if not fn then
        -- If the error is an EOF error the chunk is incomplete — buffer it
        if err and (err:find("<eof>") or err:find("'<eof>'")) then
            _replChunk = src
            return "..."   -- signal to the REPL UI that more input is needed
        end
        -- Real syntax error
        _replChunk = ""
        return "|cffff6060Error:|r " .. (err or "unknown error")
    end

    -- Chunk is complete — clear the buffer
    _replChunk = ""

    -- Execute inside pcall so runtime errors are caught
    local results = { pcall(fn) }
    local ok      = table.remove(results, 1)

    if not ok then
        local msg = results[1]
        if type(msg) == "table" and msg.error_object then
            msg = tostring(msg.error_object)
        end
        return "|cffff6060Error:|r " .. tostring(msg)
    end

    -- Format return values (nil return from statements → empty)
    if #results == 0 or (not isExpr and results[1] == nil) then
        return nil   -- silent success for statements with no return
    end
    return PrettyList(table.unpack and table.unpack(results) or unpack(results))
end

------------------------------------------------------------------------
-- Public: execute a multi-line chunk from the editor buffer
------------------------------------------------------------------------
function REPL.ExecMulti(src)
    _replChunk = ""   -- always treat as a fresh complete chunk
    local fn, err = loadstring(src, "repl-multi")
    if not fn then
        return "|cffff6060Syntax error:|r " .. (err or "?")
    end
    setfenv(fn, _env)
    local results = { pcall(fn) }
    local ok      = table.remove(results, 1)
    if not ok then
        local msg = results[1]
        if type(msg) == "table" and msg.error_object then
            msg = tostring(msg.error_object)
        end
        return "|cffff6060Error:|r " .. tostring(msg)
    end
    if #results == 0 then return "|cff52c4afOK|r" end
    return PrettyList(table.unpack and table.unpack(results) or unpack(results))
end

------------------------------------------------------------------------
-- History
------------------------------------------------------------------------
function REPL.HistoryPush(line)
    if line == "" then return end
    -- Deduplicate consecutive identical lines
    if _history[#_history] == line then return end
    _history[#_history+1] = line
    if #_history > HISTORY_MAX then
        table.remove(_history, 1)
    end
    _histIdx = #_history + 1   -- reset cursor to "after last"
end

function REPL.HistoryPrev()
    if #_history == 0 then return nil end
    _histIdx = math.max(1, _histIdx - 1)
    return _history[_histIdx]
end

function REPL.HistoryNext()
    if #_history == 0 then return nil end
    _histIdx = math.min(#_history + 1, _histIdx + 1)
    return _history[_histIdx] or ""
end

------------------------------------------------------------------------
-- Reset: clears persistent variables and the incomplete-chunk buffer.
-- Does NOT clear history.
------------------------------------------------------------------------
function REPL.Reset()
    _replEnv   = {}
    _replChunk = ""
    -- Rebuild the proxy env against the fresh _replEnv
    _env = setmetatable({}, {
        __index    = function(_, k) return _replEnv[k] ~= nil and _replEnv[k] or _G[k] end,
        __newindex = function(_, k, v) _replEnv[k] = v end,
    })
end
