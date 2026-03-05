-- ShodoQoL/CInspect.lua
-- Ctrl+Left Click to inspect a friendly player.
-- Bundled from C-Inspect by Jeremy-Gstein (Shodo).
-- Skips loading entirely if the standalone "C-Inspect" addon is already active.

if C_AddOns.IsAddOnLoaded("C-Inspect") then
    -- Standalone is installed and loaded — nothing to do.
    return
end

------------------------------------------------------------------------
-- /rl shortcut  (only register if not already claimed)
------------------------------------------------------------------------
if not SlashCmdList["SHODO_RL"] then
    SLASH_SHODO_RL1 = "/rl"
    SlashCmdList["SHODO_RL"] = ReloadUI
end

------------------------------------------------------------------------
-- Ctrl+click inspect
------------------------------------------------------------------------
local function TryInspect()
    if IsControlKeyDown() and CanInspect("mouseover") and not InCombatLockdown() then
        InspectUnit("target")  -- must be "target"; "mouseover" breaks the paperdoll
    end
end

local f = CreateFrame("Frame")
f:EnableMouse(false)   -- event-only; no hit-testing overhead
f:RegisterEvent("MODIFIER_STATE_CHANGED")
f:SetScript("OnEvent", function()
    local ok, err = pcall(TryInspect)
    if not ok then
        print("|cffff6060ShodoQoL|r CInspect error: " .. tostring(err))
    end
end)
