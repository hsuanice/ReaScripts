# hsuanice_Fix Edges Off Grid.lua — Changelog

hsuanice_Review_Edges_Off_Grid

## 26.1012.0736

- Released as part of the 26.1012.0736 package update.

History before 26.1012.0736 (moved out of the script header; last header version: `260128.1555`).

```text
v260128.1555
- Improved logging: clamp messages now include track name, take name, and position
- Easier to identify which item has the issue when "left extend clamped" occurs
v251203_1515
- Crossfade protection: Skip edges with auto-crossfade (D_FADEINLEN_AUTO/D_FADEOUTLEN_AUTO) when items overlap on same track
- Fade endpoint preservation: All fade in/out points maintain their absolute timeline position when edges are adjusted
- Smart overlap detection: Only treats auto-fade as crossfade when items actually overlap; handles moved items correctly
- Content-locked strategy: When adjusting left edge, automatically compensates right edge position if it has auto-crossfade
v250929_0329
- Fixed-markers now placed slightly INSIDE the item edges using project-time inset (MARKER_EDGE_INSET_PROJ_SEC) so they remain visible even when the edge sits on the item boundary.
- Keeps existing source-boundary inset (MARKER_INSET_SEC) as a secondary safeguard.
v250929_0508
- Ensure right-edge take markers are visible when very close to the source end: added MARKER_INSET_SEC to nudge markers slightly inward from 0/end.
- Remove temporary console debug line for right markers.
v250929_0456
- Take marker labels now indicate the operation: "trim to grid" or "extend to grid" for each edge.
- Ensure Right-edge fixed marker is created after length update and using refreshed pos/len; extra debug log prints marker source position on add.
v250929_0430
- Content-lock invariant fix: when moving item start by +Δ, all takes' STARTOFFS must shift by **+Δ×rate** (not −Δ×rate). This keeps source mapping startoffs+(t-pos)*rate unchanged ⇒ content truly stays fixed.
v250929_0412
- CONTENT-LOCK fix: when moving item position by +Δ (trim left) the takes' STARTOFFS now shift by **-Δ×rate** so timeline content truly stays fixed.
- Trim-only logic: compute right-edge target **once from the original right time**; after fixing left edge, snap right to that original target (never re-round upward). Prevents unintended rounding to a later frame.
v250929_0310
- After left-edge fix, recompute pos/len and recalc right edge target to avoid overshoot.
- Right-edge console now prints the NEW right-edge time (pos+len) after the fix.
v250929_0231
- Fix: after left-edge adjustment (content_locked may move item position), recompute right edge time before deciding right-edge target. Prevents overshoot.
- Fix: "Fixed: Right ..." console log now shows the NEW right-edge time (pos+len), not item position.
v250927_2116
- Initial release. Modes: Frame (default) / Beats / Seconds / Samples.
  Adds "Review:" take markers at off-grid left/right edges, rate/offset-safe, de-duplicated.
v250928_2010
- Switch scope to ALL project items (no selection needed).
- Add console reporting (header, per-flag lines, and summary).
- Minor: clearer undo text.
v250928_2055
- Add per-mode tolerance to avoid false positives due to float rounding (default: ±0.01 frame).
- Console now shows Δ vs grid in native units and milliseconds.
v250928_2122
- Robustness: clamp marker source position into [0, source_length) and use 5-arg SetTakeMarker(..., color=0).
- Debug: log when clamping occurs or when SetTakeMarker fails.
v250928_2335
- Add ACTION_MODE:
  1 = Review only (no edits),
  2 = Fix to nearest grid (extend or trim),
  3 = Fix by trimming only (never extend).
- Guaranteed no-move of timeline content: left-edge ops adjust start offset + length (keep item position), right-edge ops adjust length only.
- Detailed "Fixed:" console logs and per-edge take markers after edits.
v250928_2359
- Left-edge edit now updates STARTOFFS for **all takes** in the item (not just the active take).
  * Extend clamp honors the most restrictive take (min available start offset across takes).
  * Trim clamp still honors current item length.
v250929_0018
- Console logs for "Fixed:" now include the active take name.
v250929_0119
- Add LEFT_EDGE_STRATEGY:
  * "position_locked" (default): keep item start time fixed; left extend impossible, only trim-in or shift content via startoffs/length (previous behavior).
  * "content_locked": move item position by Δ and offset all takes' STARTOFFS by the same Δ*rate to keep absolute timeline content unchanged (left edge truly snaps).
- Fix-nearest now respects the chosen strategy to ensure visible left-edge movement when desired.
```
