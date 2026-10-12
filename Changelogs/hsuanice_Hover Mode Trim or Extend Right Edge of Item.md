# hsuanice_Hover Mode Trim or Extend Right Edge of Item.lua — Changelog

Hover_Mode_-_Trim_or_Extend_Right_Edge_of_Item (Preserve Fade Start, No Flicker)

## 26.1012.0736

- Released as part of the 26.1012.0736 package update.

History before 26.1012.0736 (moved out of the script header; last header version: `2510051925 Fix Pin Track issue`).

```text
v251005_1925
  - Fixed: Hover and extend behavior when “Pin Track” feature is active.
    * Updated the library to use REAPER’s native mouse-track resolver instead of SWS functions,
      ensuring correct detection of items even when tracks are pinned in the TCP/MCP.
  - Verified consistency with Left-Edge implementation:
    * True hover, gap-extend, and selection-sync logic identical to left-edge behavior.
    * All SWS dependencies removed for native safety and performance.
  - Result: Right-edge trim/extend now functions normally on pinned tracks and ruler/TCP hover modes.

v250926_1810
  - Read Hover library and print loaded path in console.
  - Delegate right-edge handling to shared no-flicker logic.
  - Add detailed [HoverLib] right-edge logs (st/en/target, new_en, delta_len, applied).
v250926_1610
  - reading Hover library; added debug path output and delegated right-edge handling to shared library.
v0.3.2
  - Selection-sync in True Hover now requires ≥2 selected items. With a single selected item, behave like no-selection.
  - Passed `prefer_selection` into the library, gated the rightmost-per-track filter with this flag,
    and enabled the gap→extend fallback only when selection-sync is OFF (no/one selection).
v0.3.1
  - Initial Right-edge port with no-flicker writes and no-overlap extends; library integration.
```
