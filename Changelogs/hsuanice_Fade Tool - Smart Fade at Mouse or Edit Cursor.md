# hsuanice_Fade Tool - Smart Fade at Mouse or Edit Cursor.lua — Changelog

## 26.1023.2047

- Initial release: one shortcut for fades and crossfades - razor, then time selection + selected tracks, then the mouse (Hover Mode: top half fade-in, bottom half fade-out, name bar centers the nearest crossfade, empty space opens Settings) or the edit cursor (mouse left = fade-in, right = fade-out).
- Hold the shortcut near a crossfade edge to drag it, or on the name bar / inside a crossfade to drag the whole crossfade; Cmd (Ctrl) inverts Snap while dragging.
- Never changes anything outside the arrange view.
- Release: tested in REAPER 7.82.

## 26.1023.2042pre1

- Add: hold Cmd (Ctrl on Windows) while dragging a crossfade to invert Snap - free fine-tuning when Snap is on, grid snapping when it is off.

## 26.1023.2032pre1

- Add: hold the shortcut near a crossfade edge to drag that edge, or on the name bar / inside a crossfade to drag the whole crossfade (follows Snap, one undo point; needs js_ReaScriptAPI).
- Change: a short press never changes a crossfade (no more one-sided adjustment by top / bottom half or mouse side); crossfaded edges are left alone.
- Change: never changes anything outside the arrange view (razor / time selection clipped, hidden or scrolled-out tracks and an edit cursor outside the view ignored).

## 26.1023.2012pre1

- Fix: on an item with crossfades on both sides, only the crossfade nearer to the mouse / edit cursor is adjusted.

## 26.1023.2008pre1

- Add: on a crossfade, top half moves its end to the mouse and bottom half its start (one-sided adjustment, Hover Mode).
- Add: Hover Mode off - mouse left of the edit cursor = fade-in, right = fade-out (crossfade end / start); mouse on an item name bar centers its crossfade on the cursor.
- Add: Hover Mode on, mouse over empty arrange space opens Fade Tool - Settings.
- Credits: written out in full - Fade Tool is heavily based on AZ's Fade tool (ReaTeam Scripts).

## 26.1023.1958pre1

- Initial release.

