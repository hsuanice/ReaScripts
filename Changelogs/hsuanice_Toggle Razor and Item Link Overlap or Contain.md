# hsuanice_Toggle Razor and Item Link Overlap or Contain.lua — Changelog

(formerly `hsuanice_Razor and Item Link with Mode Switch to Overlap or Contain like Pro Tools.lua`)

Razor and Item Link with Mode switch to Overlap or Contain like Pro Tools

## 26.1012.1641

- Renamed to "Toggle Razor and Item Link Overlap or Contain" (was "Razor and Item Link with Mode Switch to Overlap or Contain like Pro Tools") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.0958

- First release in the hsuanice/ReaScripts repository.

History before 26.1012.0958 (moved out of the script header; last header version: `0.3.0 [260509.1108]`).

```text
0.3.0 [260509.1108]
  - Track items previously selected by this script across iterations.
    When razor shrinks (Halve / Shrink Edit Selection / etc.) and an
    item that was razor-selected last tick no longer matches any
    razor on its track, it is now deselected. Manually-selected items
    (those we never touched) remain untouched — selection sync is
    "remembered scope only", not strict global sync.
  - Existing STRICT_SYNC option is unchanged (still nukes everything
    for a hard sync if user prefers).
v0.2.2 - Rename Project ExtState namespace for master toggle:
         • Namespace: "hsuanice_RazorItemLink", Key: "enabled" ("1"/"0")
         • Align with Track-Link script; no behavior change.
         Master toggle storage switched to Project ExtState (per-project, interoperable):
         • Namespace: "hsuanice_RazorItemLink", Key: "enabled" ("1"/"0")
         • Writes ON at launch, OFF on exit
         • Deprecates old global ExtState "hsuanice_RazorItemLink_ProTools"
         • No change to range logic; still add-only unless STRICT_SYNC = true
v0.2.1 - Updated header/name, added explicit inclusive contain note and credits. No functional change.
```
