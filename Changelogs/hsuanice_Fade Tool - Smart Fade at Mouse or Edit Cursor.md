# hsuanice_Fade Tool - Smart Fade at Mouse or Edit Cursor.lua — Changelog

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

