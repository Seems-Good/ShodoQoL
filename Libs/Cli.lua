-- ShodoQoL/Libs/cli.lua
-- WSh – WiM Shell: virtual filesystem stored in ShodoQoLDB,
-- POSIX-style commands, :Ex directory explorer, :term terminal mode.
--
-- Public surface (ShodoQoL.CLI):
--   CLI.GetCWD()                       → current working directory string
--   CLI.ReadFile(path)                 → content, err
--   CLI.WriteFile(path, content)       → resolvedPath, err
--   CLI.ListDir(path)                  → entries, resolvedPath
--   CLI.RunCommand(cmdline, wimRef)    → output string | nil
--
-- wimRef (passed by WiM.lua into RunCommand for editor-integration cmds):
--   wimRef.ExitTerminal()
--   wimRef.GetEditorText()   → string
--   wimRef.OpenFileInEditor(fname, content)

------------------------------------------------------------------------
-- Namespace
------------------------------------------------------------------------
ShodoQoL.CLI = ShodoQoL.CLI or {}
local CLI = ShodoQoL.CLI

------------------------------------------------------------------------
-- Filesystem storage
-- Flat path-keyed table – every node is either
--   { type="dir"  }
--   { type="file", content=string }
------------------------------------------------------------------------
local function GetFS()
    local db = ShodoQoLDB
    db.wim_fs = db.wim_fs or {}
    local fs  = db.wim_fs
    fs.nodes  = fs.nodes or {}
    fs.cwd    = fs.cwd   or {}

    -- Seed immutable root dirs (idempotent)
    local roots = { "/", "/home", "/tmp", "/shared" }
    for _, r in ipairs(roots) do
        if not fs.nodes[r] then fs.nodes[r] = { type = "dir" } end
    end
    return fs
end

------------------------------------------------------------------------
-- Character identity helpers
------------------------------------------------------------------------
local function GetCharName()
    return ((UnitName("player") or "unknown"):lower())
end

local function GetCharKey()
    local name  = UnitName("player")  or "unknown"
    local realm = GetRealmName()       or "unknown"
    -- lowercase, strip spaces (some realm names have spaces)
    return name:lower() .. "-" .. realm:lower():gsub("%s+", "")
end

------------------------------------------------------------------------
-- Path utilities
------------------------------------------------------------------------
-- Collapse /./ and /../ sequences into a canonical absolute path.
local function NormalizePath(raw)
    local parts = {}
    for seg in raw:gmatch("[^/]+") do
        if seg == ".." then
            parts[#parts] = nil   -- pop
        elseif seg ~= "." then
            parts[#parts + 1] = seg
        end
    end
    return "/" .. table.concat(parts, "/")
end

-- Resolve `path` against `cwd`.  Absolute paths pass straight through.
local function ResolvePath(path, cwd)
    if not path or path == "" then return cwd or "/" end
    if path == "~" then return "/home/" .. GetCharName() end
    if path:sub(1, 1) == "/" then return NormalizePath(path) end
    -- relative
    local base = (cwd or "/"):gsub("/$", "")
    return NormalizePath(base .. "/" .. path)
end

local function ParentPath(path)
    if path == "/" then return "/" end
    return path:match("^(.+)/[^/]+$") or "/"
end

local function BaseName(path)
    return path:match("[^/]+$") or path
end

-- Lua-pattern-escape a string so it can be used in :match()
local function Escape(s)
    return (s:gsub("[%(%)%.%%%+%-%*%?%[%^%$]", "%%%1"))
end

------------------------------------------------------------------------
-- CWD management (per character)
------------------------------------------------------------------------
function CLI.GetCWD()
    local fs      = GetFS()
    local key     = GetCharKey()
    local home    = "/home/" .. GetCharName()

    -- Ensure home dir exists
    if not fs.nodes[home] then fs.nodes[home] = { type = "dir" } end

    -- Initialise or repair CWD
    if not fs.cwd[key]
    or not fs.nodes[fs.cwd[key]]
    or fs.nodes[fs.cwd[key]].type ~= "dir" then
        fs.cwd[key] = home
    end
    return fs.cwd[key]
end

local function SetCWD(path)
    local fs      = GetFS()
    fs.cwd[GetCharKey()] = path
end

------------------------------------------------------------------------
-- Node access
------------------------------------------------------------------------
local function NodeAt(path)
    return GetFS().nodes[path]
end

-- Returns a sorted array of { name, path, type } for immediate children.
local function ListDir(path)
    local fs      = GetFS()
    local seen    = {}
    local results = {}

    for nodePath, node in pairs(fs.nodes) do
        if nodePath ~= path then
            local rest
            if path == "/" then
                rest = nodePath:match("^/([^/]+)$")
            else
                rest = nodePath:match("^" .. Escape(path) .. "/([^/]+)$")
            end
            if rest and not seen[rest] then
                seen[rest] = true
                results[#results + 1] = { name = rest, path = nodePath, type = node.type }
            end
        end
    end

    -- Dirs first, then alphabetical within group
    table.sort(results, function(a, b)
        if a.type ~= b.type then return a.type == "dir" end
        return a.name < b.name
    end)
    return results
end

------------------------------------------------------------------------
-- Public ListDir (resolves path first)
------------------------------------------------------------------------
function CLI.ListDir(rawPath)
    local cwd  = CLI.GetCWD()
    local path = rawPath and ResolvePath(rawPath, cwd) or cwd
    return ListDir(path), path
end

------------------------------------------------------------------------
-- Public ReadFile / WriteFile
------------------------------------------------------------------------
function CLI.ReadFile(rawPath)
    local path = ResolvePath(rawPath, CLI.GetCWD())
    local node = NodeAt(path)
    if not node           then return nil, "no such file: "    .. path end
    if node.type == "dir" then return nil, "is a directory: "  .. path end
    return node.content or "", nil
end

function CLI.WriteFile(rawPath, content)
    local fs     = GetFS()
    local path   = ResolvePath(rawPath, CLI.GetCWD())
    local parent = ParentPath(path)
    if not fs.nodes[parent] or fs.nodes[parent].type ~= "dir" then
        return nil, "no such directory: " .. parent
    end
    -- Do not overwrite a directory
    if fs.nodes[path] and fs.nodes[path].type == "dir" then
        return nil, "is a directory: " .. path
    end
    fs.nodes[path] = { type = "file", content = content }
    return path, nil
end

------------------------------------------------------------------------
-- Individual command implementations
-- Each returns a string (may be nil for silent success).
------------------------------------------------------------------------
local function Cmd_pwd()
    return CLI.GetCWD()
end

local function Cmd_whoami()
    return (UnitName("player") or "unknown") .. "@" .. (GetRealmName() or "unknown")
end

local function Cmd_ls(args)
    local cwd  = CLI.GetCWD()
    local path = ResolvePath(args[1], cwd)
    local node = NodeAt(path)
    if not node then
        return "ls: " .. (args[1] or ".") .. ": No such file or directory"
    end
    if node.type == "file" then return path end

    local entries = ListDir(path)
    if #entries == 0 then return "(empty)" end

    local out = {}
    for _, e in ipairs(entries) do
        if e.type == "dir" then
            out[#out + 1] = "|cff52c4af" .. e.name .. "/|r"
        else
            out[#out + 1] = e.name
        end
    end
    return table.concat(out, "\n")
end

local function Cmd_cd(args)
    local cwd  = CLI.GetCWD()
    local dest = args[1] or "~"
    local path = ResolvePath(dest, cwd)

    -- Ensure /home/<char> always exists
    if path == "/home/" .. GetCharName() then
        local fs = GetFS()
        if not fs.nodes[path] then fs.nodes[path] = { type = "dir" } end
    end

    local node = NodeAt(path)
    if not node            then return "cd: " .. dest .. ": No such file or directory" end
    if node.type ~= "dir"  then return "cd: " .. dest .. ": Not a directory" end
    SetCWD(path)
    return nil   -- silent success; caller shows new prompt
end

local function Cmd_mkdir(args)
    if not args[1] then return "mkdir: missing operand" end
    local fs  = GetFS()
    local cwd = CLI.GetCWD()
    local out = {}
    for _, a in ipairs(args) do
        local path   = ResolvePath(a, cwd)
        local parent = ParentPath(path)
        if fs.nodes[path] then
            out[#out + 1] = "mkdir: " .. a .. ": File exists"
        elseif not fs.nodes[parent] then
            out[#out + 1] = "mkdir: " .. a .. ": No such file or directory"
        else
            fs.nodes[path] = { type = "dir" }
        end
    end
    return #out > 0 and table.concat(out, "\n") or nil
end

local function Cmd_touch(args)
    if not args[1] then return "touch: missing operand" end
    local fs  = GetFS()
    local cwd = CLI.GetCWD()
    local out = {}
    for _, a in ipairs(args) do
        local path   = ResolvePath(a, cwd)
        local parent = ParentPath(path)
        if not fs.nodes[parent] or fs.nodes[parent].type ~= "dir" then
            out[#out + 1] = "touch: " .. a .. ": No such file or directory"
        elseif not fs.nodes[path] then
            fs.nodes[path] = { type = "file", content = "" }
        end
        -- existing files: no-op (would update mtime in a real fs)
    end
    return #out > 0 and table.concat(out, "\n") or nil
end

local function Cmd_rm(args)
    if not args[1] then return "rm: missing operand" end
    local fs        = GetFS()
    local cwd       = CLI.GetCWD()
    local recursive = false
    local targets   = {}
    local out       = {}

    for _, a in ipairs(args) do
        if a == "-r" or a == "-rf" or a == "-fr" or a == "-r" then
            recursive = true
        else
            targets[#targets + 1] = a
        end
    end

    -- Protected paths
    local protected = { ["/"] = true, ["/home"] = true,
                        ["/shared"] = true, ["/tmp"] = true }

    for _, a in ipairs(targets) do
        local path = ResolvePath(a, cwd)
        if protected[path] then
            out[#out + 1] = "rm: '" .. a .. "': Permission denied"
        elseif not fs.nodes[path] then
            out[#out + 1] = "rm: " .. a .. ": No such file or directory"
        elseif fs.nodes[path].type == "dir" and not recursive then
            out[#out + 1] = "rm: " .. a .. ": Is a directory  (use -r to remove recursively)"
        else
            -- Collect all nodes to remove (the node itself + any descendants)
            local toRemove = {}
            for nodePath in pairs(fs.nodes) do
                if nodePath == path
                or nodePath:sub(1, #path + 1) == path .. "/" then
                    toRemove[#toRemove + 1] = nodePath
                end
            end
            for _, p in ipairs(toRemove) do fs.nodes[p] = nil end
        end
    end
    return #out > 0 and table.concat(out, "\n") or nil
end

------------------------------------------------------------------------
-- rmdir: remove directories only if empty (POSIX behaviour).
-- Unlike  rm -r  this refuses to delete a dir that still has children.
------------------------------------------------------------------------
local function Cmd_rmdir(args)
    if not args[1] then return "rmdir: missing operand" end
    local fs  = GetFS()
    local cwd = CLI.GetCWD()
    local out = {}

    -- Protected paths (same set as rm)
    local protected = { ["/"] = true, ["/home"] = true,
                        ["/shared"] = true, ["/tmp"] = true }

    for _, a in ipairs(args) do
        local path = ResolvePath(a, cwd)

        if protected[path] then
            out[#out + 1] = "rmdir: '" .. a .. "': Permission denied"
        elseif not fs.nodes[path] then
            out[#out + 1] = "rmdir: " .. a .. ": No such file or directory"
        elseif fs.nodes[path].type ~= "dir" then
            out[#out + 1] = "rmdir: " .. a .. ": Not a directory"
        else
            -- Check for any immediate or deeper children
            local hasChildren = false
            for nodePath in pairs(fs.nodes) do
                if nodePath ~= path
                and nodePath:sub(1, #path + 1) == path .. "/" then
                    hasChildren = true
                    break
                end
            end
            if hasChildren then
                out[#out + 1] = "rmdir: " .. a .. ": Directory not empty  (use rm -r to force)"
            else
                fs.nodes[path] = nil
                -- If CWD was inside the removed dir, reset it to home
                local key = GetCharKey()
                local currentCWD = fs.cwd[key] or "/"
                if currentCWD == path
                or currentCWD:sub(1, #path + 1) == path .. "/" then
                    fs.cwd[key] = "/home/" .. GetCharName()
                end
            end
        end
    end
    return #out > 0 and table.concat(out, "\n") or nil
end

local function Cmd_mv(args)
    if not args[1] or not args[2] then return "mv: missing operand" end
    local fs  = GetFS()
    local cwd = CLI.GetCWD()
    local src = ResolvePath(args[1], cwd)
    local dst = ResolvePath(args[2], cwd)

    if not fs.nodes[src] then
        return "mv: " .. args[1] .. ": No such file or directory"
    end
    -- If dst is an existing dir, move src INTO it
    if fs.nodes[dst] and fs.nodes[dst].type == "dir" then
        dst = (dst == "/" and "/" or dst .. "/") .. BaseName(src)
    end
    if fs.nodes[dst] then
        return "mv: " .. args[2] .. ": destination already exists"
    end
    local parent = ParentPath(dst)
    if not fs.nodes[parent] then
        return "mv: " .. args[2] .. ": No such file or directory"
    end

    local srcNode = fs.nodes[src]
    if srcNode.type == "file" then
        fs.nodes[dst] = srcNode
        fs.nodes[src] = nil
    else
        -- Move entire subtree
        local remap = {}
        for nodePath, node in pairs(fs.nodes) do
            if nodePath == src
            or nodePath:sub(1, #src + 1) == src .. "/" then
                local rel = nodePath:sub(#src + 1)   -- includes leading /
                remap[dst .. rel] = node
                fs.nodes[nodePath] = nil
            end
        end
        for newPath, node in pairs(remap) do
            fs.nodes[newPath] = node
        end
    end
    return nil
end

local function Cmd_cp(args)
    if not args[1] or not args[2] then return "cp: missing operand" end
    local fs  = GetFS()
    local cwd = CLI.GetCWD()
    local src = ResolvePath(args[1], cwd)
    local dst = ResolvePath(args[2], cwd)

    local srcNode = fs.nodes[src]
    if not srcNode then
        return "cp: " .. args[1] .. ": No such file or directory"
    end
    if srcNode.type == "dir" then
        return "cp: " .. args[1] .. ": Is a directory  (-r not yet supported)"
    end
    if fs.nodes[dst] and fs.nodes[dst].type == "dir" then
        dst = (dst == "/" and "/" or dst .. "/") .. BaseName(src)
    end
    local parent = ParentPath(dst)
    if not fs.nodes[parent] then
        return "cp: " .. args[2] .. ": No such file or directory"
    end
    fs.nodes[dst] = { type = "file", content = srcNode.content }
    return nil
end

local function Cmd_cat(args)
    if not args[1] then return "cat: missing operand" end
    local out = {}
    for _, a in ipairs(args) do
        local content, err = CLI.ReadFile(a)
        out[#out + 1] = err and ("cat: " .. err) or content
    end
    return table.concat(out, "\n")
end

local function Cmd_echo(args)
    return table.concat(args, " ")
end

local function Cmd_help()
    return [[WSh – WiM Shell  (virtual filesystem inside SavedVariables)

NAVIGATION
  pwd               print working directory
  ls  [path]        list directory  (dirs shown in teal)
  cd  [path]        change directory   (cd ~ goes home)
  whoami            print character@realm

FILES
  touch <file>      create empty file
  mkdir <dir>       create directory
  rm    <path>      remove file  (-r to remove directory recursively)
  rmdir <dir>       remove empty directory  (fails if not empty)
  mv    <src> <dst> move / rename
  cp    <src> <dst> copy file
  cat   <file>      print file contents
  echo  <text>      print text

EDITOR INTEGRATION
  edit  <file>      open file in WiM, exit terminal
  write <file>      save current buffer to VFS file
  clear             clear terminal output

EXPLORER
  :Ex               open directory-explorer panel
  :e  <file>        open VFS file in editor (normal mode)
  :cd <path>        change VFS directory from Ex command line

Type  exit  or press Esc to leave the terminal.]]
end

------------------------------------------------------------------------
-- Argument tokeniser  (whitespace-split; no shell quoting needed)
------------------------------------------------------------------------
local function ParseArgs(line)
    local args = {}
    for tok in line:gmatch("%S+") do args[#args + 1] = tok end
    return args
end

------------------------------------------------------------------------
-- Main dispatcher
-- wimRef table (optional, supplied by WiM.lua):
--   .ExitTerminal()
--   .GetEditorText()          → string
--   .OpenFileInEditor(fname, content)
------------------------------------------------------------------------
function CLI.RunCommand(line, wimRef)
    line = line and line:match("^%s*(.-)%s*$") or ""
    if line == "" then return nil end

    local args    = ParseArgs(line)
    local cmdRaw  = table.remove(args, 1)
    local cmd     = cmdRaw:lower()

    if     cmd == "pwd"      then return Cmd_pwd()
    elseif cmd == "whoami"   then return Cmd_whoami()
    elseif cmd == "ls"       then return Cmd_ls(args)
    elseif cmd == "cd"       then return Cmd_cd(args)
    elseif cmd == "mkdir"    then return Cmd_mkdir(args)
    elseif cmd == "touch"    then return Cmd_touch(args)
    elseif cmd == "rm"       then return Cmd_rm(args)
    elseif cmd == "rmdir"    then return Cmd_rmdir(args)
    elseif cmd == "mv"       then return Cmd_mv(args)
    elseif cmd == "cp"       then return Cmd_cp(args)
    elseif cmd == "cat"      then return Cmd_cat(args)
    elseif cmd == "echo"     then return Cmd_echo(args)
    elseif cmd == "help"     then return Cmd_help()

    elseif cmd == "clear" then
        -- Caller (TerminalSubmit) detects "clear" before calling RunCommand
        -- and wipes the output buffer itself.  This branch is a fallback.
        return nil

    elseif cmd == "exit" or cmd == "quit" then
        if wimRef and wimRef.ExitTerminal then wimRef.ExitTerminal() end
        return nil

    elseif cmd == "edit" then
        if not args[1] then return "edit: missing filename" end
        local content, err = CLI.ReadFile(args[1])
        if err then return "edit: " .. err end
        if wimRef and wimRef.OpenFileInEditor then
            wimRef.OpenFileInEditor(args[1], content)
        end
        return nil

    elseif cmd == "write" then
        if not args[1] then return "write: missing filename" end
        local text = wimRef and wimRef.GetEditorText and wimRef.GetEditorText() or ""
        local path, err = CLI.WriteFile(args[1], text)
        if err then return "write: " .. err end
        return string.format('"%s"  %dB written', path, #text)

    else
        return cmdRaw .. ": command not found  (type 'help')"
    end
end

------------------------------------------------------------------------
-- Bootstrap: seed home dir and a welcome file on first login
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    local fs   = GetFS()
    local home = "/home/" .. GetCharName()

    if not fs.nodes[home] then
        fs.nodes[home] = { type = "dir" }
    end

    local readme = home .. "/readme.txt"
    if not fs.nodes[readme] then
        local name = UnitName("player") or "Adventurer"
        fs.nodes[readme] = {
            type    = "file",
            content = "Welcome to WSh, " .. name .. "!\n"
                   .. "\n"
                   .. "Your home directory is " .. home .. "\n"
                   .. "\n"
                   .. "Useful commands:\n"
                   .. "  :term        open a terminal inside WiM\n"
                   .. "  :Ex          browse the virtual filesystem\n"
                   .. "  :e <file>    open a VFS file in the editor\n"
                   .. "  :w <file>    write the editor buffer to a VFS file\n"
                   .. "\n"
                   .. "Inside the terminal, type 'help' for all commands.\n",
        }
    end

    -- Always validate CWD (repairs stale paths after rm -r on home)
    CLI.GetCWD()
end)
