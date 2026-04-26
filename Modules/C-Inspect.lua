-- ShodoQoL/CInspect.lua
-- Ctrl+Left Click to inspect a friendly player.
-- Bundled from C-Inspect by Jeremy-Gstein (Shodo).
-- Skips loading entirely if the standalone "C-Inspect" addon is already active.

if C_AddOns.IsAddOnLoaded("C-Inspect") then return end

local function TryInspect()
    if IsControlKeyDown() and CanInspect("mouseover") and not InCombatLockdown() then
        InspectUnit("target")
    end
end

-- Event registration deferred to OnReady so IsEnabled() can gate it.
ShodoQoL.OnReady(function()
    -- /rl shortcut registered regardless of enabled state (it's just a convenience)
    if not SlashCmdList["SHODO_RL"] then
        SLASH_SHODO_RL1 = "/rl"
        SlashCmdList["SHODO_RL"] = ReloadUI
    end

    if not ShodoQoL.IsEnabled("CInspect") then return end

    local f = CreateFrame("Frame")
    f:EnableMouse(false)
    f:RegisterEvent("MODIFIER_STATE_CHANGED")
    f:SetScript("OnEvent", function()
        local ok, err = pcall(TryInspect)
        if not ok then
            print("|cffff6060ShodoQoL|r CInspect error: " .. tostring(err))
        end
    end)
end)
