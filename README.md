# ShodoQoL
Quality-of-Life addons and modifications designed for Evokers

<img width="770" height="642" alt="image" src="https://github.com/user-attachments/assets/4af23eac-a820-490b-a8e0-605e1c275346" />

***

# Usage:
```
/shodoqol          - Open Settings Menu
/shodoqol status   - Show all Active/Inactive Modules available. 
/shodoqol help     - Prints all available commands
/sqol              - alias for all /shodoqol commands

```

# Modules For Evokers:

### Essence Mover
**Key:** `EssenceMover`  
**Description:**  
Drag your Evoker Essence bar anywhere on screen. Adjust scale with a live slider. Position persists across reloads and spec changes.

### Hover Tracker
**Key:** `HoverTracker`  
**Description:**  
Evoker-only. Glows green, amber, or red behind your cast bar based on whether Hover lets you move while casting. Alerts when Hover has no charges. Configurable font, size, and opacity.

### Prescience Tracker
**Key:** `PrescienceTracker`  
**Description:**  
Live Prescience buff state tracking "aura" on your P1 and P2 targets. Purely event-driven with zero CPU overhead. Augmentation Evoker only.  
Color-coded:
- 🟢 active (`o`)
- 🟠 expiring (`!`)
- 🔴 missing (`x`)
- ⚪ not in group/not assigned (`-`)  

### Macro Helpers
**Key:** `MacroHelpers`  
**Description:**  
Per-character macros with cross-realm support: `Spatial Paradox`, `Prescience 1`, and `Prescience 2` - each targeting an independent player. Also provides helpers for `Cauterizing Flame`, `Blistering Scales`, and `Source of Magic` targets so your macros stay stable across realm names and renames.

### Source of Magic
**Key:** `SourceOfMagic`  
**Description:**  
Out-of-combat popup when Source of Magic is missing from your configured target. Only active when talented into Source of Magic. Uses token-scoped events (no global UNIT_AURA spam) so it stays lightweight even in large raids. Use `/som test` to preview.

***

# Modules for all classes:

### Mouse Circle (Mouse icon tracker)
**Key:** `MouseCircle`  
**Description:**  
Configure Size, Thickness, and Color of the circle around your mouse. Uses a local `circle.tga`, capped at refreshing every 30 frames.

### Kicksmaxxing
**Key:** `Kicksmaxxing`  
**Description:**  
Dynamic focus-macro generator for interrupts, stuns, and CC. Enter any spell name to get a `KM_SpellName` character macro that casts on your focus when it is alive and hostile, otherwise focuses-and-casts on the next enemy. Enable up to 5 spells at once from the settings panel. 

### HearthStoned
**Key:** `HearthStoned`  
**Description:**  
Cycles through all owned hearthstone toys with a single per-character macro. Rescan at any time to pick up new toys.

### C-Inspect
**Key:** `CInspect`  
**Addon Key:** `C-Inspect` - [Github](https://github.com/Jeremy-Gstein/C-Inspect) - [Curse](https://www.curseforge.com/wow/addons/c-inspect)  

**Description:**  
Hold `Ctrl` and `left-click` a friendly player to inspect them. Also registers `/rl` to reload your UI quickly.

### DoNotRelease
**Key:** `DoNotRelease`  
**Addon Key:** `DoNotRelease` - [Github](https://github.com/Seems-Good/DNRs) - [Curse](https://www.curseforge.com/wow/addons/do-not-release)  

**Description:**  
Pulsing warning when you die in a group instance. Configurable text, color, font, and position. Use `/dnr test` to preview. Includes an optional 2FA-style overlay for release confirmation, with a low-cost timer that updates the “code refreshes in Xs” countdown once per second.

---

~~**Key:** `ShoStats`  
**Description:**  
Lightweight stat readout frame: Crit, Haste, Mastery, Vers, Leech, Speed, and main stat, with draggable frame, opacity/scale sliders, and per-stat visibility toggles.~~

### ShoStats [disabled after v1.7.1]  (Broken in WoW patch 12.0.5 with new combat API restrictions)

---

### Contributing

**ReleaseHelpers:**

```bash

patch (0.0.*+1):
    - just build (git tag --sort=-v:refname | head -n1 | awk -F'[v.]' '{printf "%d.%d.%d\n",$2,$3,$4+1}') "[feature] [bugfix] [UI] [Module/$NAME]"
minor/feature (0.*+1.*):
    - just build (git tag --sort=-v:refname | head -n1 | awk -F'[v.]' '{printf "%d.%d.%d\n",$2,$3+1,$4}') "[new] [feature] [bugfix] [UI] [Module/$NAME]"
major/breaking (*+1.0.0):
    - just build (git tag --sort=-v:refname | head -n1 | awk -F'[v.]' '{printf "%d.%d.%d\n",$2+1,$3,$4}') "[new] [feature] [bugfix] [UI] [Module/$NAME]"

```
