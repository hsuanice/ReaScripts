# hsuanice_Move selected items to track under mouse.lua — Changelog

Move selected items to track under mouse (vertical only, keep timeline position)

## 26.1012.0736

- First release in the hsuanice/ReaScripts repository.

History before 26.1012.0736 (moved out of the script header; last header version: `261001.1153`).

```text
v261001.1153
- Fix: Overwrite mode shifted the content of an overwritten item whose
  head was cut (item starting inside the moved range). It moved
  D_POSITION without compensating the take start offset. All cuts now
  use SplitMediaItem + delete, so surviving pieces keep exact source
  alignment (start offset, stretch markers, take envelopes).
- Overwrite mode re-scans the destination track per moved item, so pieces
  created by earlier splits are also trimmed correctly.

v260502.1833
- Auto-append tracks at the bottom when the destination span exceeds
  the last existing track.
- Detect overlap with existing items on destination tracks; prompt user
  with Insert / Overwrite / Cancel.
- Insert mode: insert N empty tracks at the destination.
- Overwrite mode: trim, split, or delete existing items inside each
  moved item's time range before placing the moved item.

v260502.1823
- Initial release.
```
