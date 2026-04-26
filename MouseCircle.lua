-- ShodoQoL/MouseCircle.lua
-- Colored ring drawn around the mouse cursor via a single atlas TGA texture.
--
-- CPU MODEL
--   One Frame + one Texture.  OnUpdate is throttled to ~30 fps equivalent
--   (POLL_INTERVAL = 0.033s).  At 144 fps the dt accumulator short-circuits
--   after one addition and a comparison — no API calls, no layout work.
--   When the interval fires: GetCursorPosition + 2 comparisons.  If the
--   cursor moved: one SetPoint (same anchor, just new offsets — no layout
--   dirty cascade).  Nothing else ever runs per-frame.
--
--   BLEND mode (not ADD): pre-multiplied alpha TGA renders identically on
--   any background without breaking the GPU sprite batch that ADD does.
--
-- TEXTURE  (circle.tga, 128×128 BGRA pre-multiplied, 2×2 atlas)
--   Four 64×64 tiles baked at different stroke widths.
--   SetTexCoord selects the tile → thickness is a UV crop, zero geometry.
--   SetVertexColor tints to any color.  Neither fires during OnUpdate.
--
-- THICKNESS vs SIZE — fully independent:
--   Thickness (1–8) → atlas UV crop (THICK_TIER → TEXCOORDS).
--   Size (radius 10–26) → ring:SetSize() only.

------------------------------------------------------------------------
-- Tunables
------------------------------------------------------------------------
local MC_DEFAULTS = {
    colorR    = 1.00,
    colorG    = 1.00,
    colorB    = 1.00,
    colorA    = 1.00,
    thickness = 2,
    radius    = 16,
}

local THICKNESS_MIN  = 1
local THICKNESS_MAX  = 8
local RADIUS_MIN     = 10
local RADIUS_MAX     = 26

-- Target ~30 position updates per second regardless of frame rate.
-- At 144 fps this means ~114 of every 144 OnUpdate calls return after
-- one addition and one comparison — negligible overhead.
local POLL_INTERVAL  = 0.033

local TEXTURE_PATH   = "Interface\\AddOns\\ShodoQoL\\circle"

-- thickness 1–8 → atlas tile 1–4
local THICK_TIER = { 1, 1, 2, 2, 3, 3, 4, 4 }

-- SetTexCoord(L, R, T, B) for each 64×64 tile within the 128×128 atlas
local TEXCOORDS = {
    [1] = { 0.0, 0.5, 0.0, 0.5 },   -- thin
    [2] = { 0.5, 1.0, 0.0, 0.5 },   -- medium
    [3] = { 0.0, 0.5, 0.5, 1.0 },   -- thick
    [4] = { 0.5, 1.0, 0.5, 1.0 },   -- extra thick
}

local COLOR_PRESETS = {
    { label = "White",  r = 1.0,  g = 1.0,  b = 1.0  },
    { label = "Cyan",   r = 0.0,  g = 1.0,  b = 1.0  },
    { label = "Green",  r = 0.20, g = 0.78, b = 0.50  },
    { label = "Yellow", r = 1.0,  g = 1.0,  b = 0.0   },
    { label = "Orange", r = 1.0,  g = 0.55, b = 0.0   },
    { label = "Red",    r = 1.0,  g = 0.15, b = 0.15  },
}

------------------------------------------------------------------------
-- DB accessor
------------------------------------------------------------------------
local function DB() return ShodoQoLDB.mouseCircle end

------------------------------------------------------------------------
-- Ring frame + texture
-- Anchored once to UIParent BOTTOMLEFT at (0,0).
-- OnUpdate moves it with SetPoint using the same anchor — WoW updates
-- offsets in-place without invalidating the full anchor chain.
------------------------------------------------------------------------
local UIPARENT = UIParent

local ring = CreateFrame("Frame", "ShodoQoLMouseCircle", UIPARENT)
ring:SetFrameStrata("TOOLTIP")
ring:SetFrameLevel(1000)
ring:EnableMouse(false)
ring:SetIgnoreParentAlpha(true)
ring:SetPoint("CENTER", UIPARENT, "BOTTOMLEFT", 0, 0)
ring:Hide()

local tex = ring:CreateTexture(nil, "OVERLAY")
tex:SetAllPoints(ring)
tex:SetTexture(TEXTURE_PATH)
tex:SetBlendMode("BLEND")   -- pre-multiplied alpha TGA; BLEND preserves GPU batching

------------------------------------------------------------------------
-- Apply helpers — only called from settings interactions, never OnUpdate
------------------------------------------------------------------------
local function ApplyThickness(thick)
    local uv = TEXCOORDS[THICK_TIER[thick] or 1]
    tex:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
end

local function ApplyRadius(radius)
    ring:SetSize(radius * 2, radius * 2)
end

local function ApplyColor(r, g, b, a)
    tex:SetVertexColor(r, g, b, a)
end

local function ApplyAll()
    local db = DB()
    ApplyColor(db.colorR, db.colorG, db.colorB, db.colorA)
    ApplyThickness(db.thickness)
    ApplyRadius(db.radius)
end

------------------------------------------------------------------------
-- OnUpdate — throttled hot path
--
-- Fast path (most frames):
--   elapsed = elapsed + dt   [float add]
--   elapsed < POLL_INTERVAL  [float compare]
--   return
--
-- Slow path (~30×/sec):
--   GetCursorPosition()
--   cx == lastCX and cy == lastCY → return   (cursor still)
--   SetPoint(...)                             (cursor moved)
------------------------------------------------------------------------
local elapsed    = 0
local lastCX     = -1
local lastCY     = -1
local cachedScale = 1

local function onUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed < POLL_INTERVAL then return end
    elapsed = 0

    local cx, cy = GetCursorPosition()
    if cx == lastCX and cy == lastCY then return end
    lastCX, lastCY = cx, cy
    ring:SetPoint("CENTER", UIPARENT, "BOTTOMLEFT", cx / cachedScale, cy / cachedScale)
end

------------------------------------------------------------------------
-- Cache UIParent scale; refresh only on resolution/scale events
------------------------------------------------------------------------
local scaleWatcher = CreateFrame("Frame")
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatcher:SetScript("OnEvent", function()
    cachedScale    = UIPARENT:GetEffectiveScale()
    lastCX, lastCY = -1, -1
end)

------------------------------------------------------------------------
-- Enable / disable
------------------------------------------------------------------------
local function Enable()
    if not ShodoQoL.IsEnabled("MouseCircle") then return end
    cachedScale    = UIPARENT:GetEffectiveScale()
    elapsed        = POLL_INTERVAL  -- fire immediately on first frame
    lastCX, lastCY = -1, -1
    ApplyAll()
    ring:Show()
    ring:SetScript("OnUpdate", onUpdate)
end

local function Disable()
    ring:SetScript("OnUpdate", nil)
    ring:Hide()
end

------------------------------------------------------------------------
-- Settings sub-page  (ShodoQoL > Mouse Circle)
------------------------------------------------------------------------
local function BuildPanel()
    local panel = CreateFrame("Frame")
    panel.name   = "Mouse Circle"
    panel.parent = "ShodoQoL"
    panel:EnableMouse(false)
    panel:Hide()

    local W  = 560
    local BH = 26
    local HW = math.floor((W - 8) / 2)

    local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", 16, -16)
    titleFS:SetText("|cff33937fMouse|r|cff52c4afCircle|r")

    local subFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -5)
    subFS:SetText("|cff888888Single texture ring — throttled 30fps poll, atlas UV thickness|r")

    local function Div(anchor, offY)
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
        d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offY)
        d:SetHeight(1)
        d:SetColorTexture(0.20, 0.58, 0.50, 0.45)
        return d
    end

    local function SecLabel(anchor, offY, text)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offY)
        fs:SetText("|cff52c4af" .. text .. "|r")
        return fs
    end

    local function MakeSlider(parent, anchorFrame, labelStr, minV, maxV, step, fmt, onChange)
        local hdr = SecLabel(anchorFrame, -14, labelStr)

        local valFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valFS:SetPoint("LEFT", hdr, "RIGHT", 10, 0)

        local minFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        minFS:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -38)
        minFS:SetText(string.format(fmt, minV))
        minFS:SetTextColor(0.5, 0.5, 0.5)

        local maxFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        maxFS:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 300, -38)
        maxFS:SetText(string.format(fmt, maxV))
        maxFS:SetTextColor(0.5, 0.5, 0.5)

        local cont = CreateFrame("Frame", nil, parent)
        cont:SetSize(320, 36)
        cont:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -18)
        cont:EnableMouse(false)

        local track = cont:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT",  10, 0)
        track:SetPoint("RIGHT", -10, 0)
        track:SetHeight(6)
        track:SetColorTexture(0.06, 0.18, 0.16, 0.90)

        local shine = cont:CreateTexture(nil, "BORDER")
        shine:SetPoint("LEFT",  10, 1)
        shine:SetPoint("RIGHT", -10, 1)
        shine:SetHeight(2)
        shine:SetColorTexture(0.20, 0.68, 0.58, 0.40)

        local sl = CreateFrame("Slider", nil, cont)
        sl:SetAllPoints()
        sl:EnableMouse(true)
        sl:SetOrientation("HORIZONTAL")
        sl:SetMinMaxValues(minV, maxV)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)

        local thumbBorder = sl:CreateTexture(nil, "OVERLAY")
        thumbBorder:SetSize(18, 26)
        thumbBorder:SetColorTexture(0.04, 0.12, 0.10, 1)

        local thumb = sl:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(14, 22)
        thumb:SetColorTexture(0.25, 0.78, 0.66, 1)
        thumb:SetDrawLayer("OVERLAY", 1)
        thumbBorder:SetPoint("CENTER", thumb, "CENTER", 0, 0)
        sl:SetThumbTexture(thumb)

        sl:SetScript("OnValueChanged", function(self, raw)
            local v = math.floor(raw / step + 0.5) * step
            valFS:SetText(string.format(fmt, v))
            onChange(v, valFS)
        end)

        return sl, valFS, cont
    end

    -- ── Color ─────────────────────────────────────────────────────────
    local div0     = Div(subFS, -12)
    local colorHdr = SecLabel(div0, -14, "Ring Color")

    local colorAnchor = colorHdr
    for i, preset in ipairs(COLOR_PRESETS) do
        local btn = ShodoQoL.CreateButton(panel, preset.label, HW, BH)
        if i % 2 == 1 then
            btn:SetPoint("TOPLEFT", colorAnchor, "BOTTOMLEFT", 0, i == 1 and -8 or -6)
            colorAnchor = btn
        else
            btn:SetPoint("LEFT", colorAnchor, "RIGHT", 8, 0)
        end
        local r, g, b = preset.r, preset.g, preset.b
        btn:SetScript("OnClick", function()
            local db = DB()
            db.colorR, db.colorG, db.colorB = r, g, b
            ApplyColor(r, g, b, db.colorA)
        end)
    end

    -- ── Thickness ─────────────────────────────────────────────────────
    local div1      = Div(colorAnchor, -14)
    local lastThick = MC_DEFAULTS.thickness

    local thickSlider, thickValFS, thickCont = MakeSlider(
        panel, div1, "Ring Thickness",
        THICKNESS_MIN, THICKNESS_MAX, 1, "%dpx",
        function(v)
            if v == lastThick then return end
            lastThick = v
            DB().thickness = v
            ApplyThickness(v)
        end
    )

    -- ── Radius ────────────────────────────────────────────────────────
    local div2       = Div(thickCont, -14)
    local lastRadius = MC_DEFAULTS.radius

    local radiusSlider, radiusValFS, _ = MakeSlider(
        panel, div2, "Ring Size",
        RADIUS_MIN, RADIUS_MAX, 2, "%dpx",
        function(v)
            if v == lastRadius then return end
            lastRadius = v
            DB().radius = v
            ApplyRadius(v)
        end
    )

    -- ── Sync on show ──────────────────────────────────────────────────
    panel:SetScript("OnShow", function()
        local db = DB()
        local t  = db.thickness
        local r  = db.radius
        lastThick  = t
        lastRadius = r
        thickSlider:SetValue(t)
        thickValFS:SetText(t .. "px")
        radiusSlider:SetValue(r)
        radiusValFS:SetText(r .. "px")
    end)

    local subCat = Settings.RegisterCanvasLayoutSubcategory(ShodoQoL.rootCategory, panel, "Mouse Circle")
    Settings.RegisterAddOnCategory(subCat)
end

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
ShodoQoL.OnReady(function()
    if not ShodoQoL.IsEnabled("MouseCircle") then return end
    Enable()
    BuildPanel()
end)
