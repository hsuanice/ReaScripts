# hsuanice_Match Room Tone of Joined Items.lua — Changelog

## 26.1026.1523pre1

- Initial release: level-match the room tone of touching / crossfaded selected items by take volume - however far apart the levels are; only groups fully in view.
- Room tone is measured on the WHOLE source file (quietest 10 %), so movement in the trimmed pauses does not count; an item whose own part is more than 6 dB louder than its file's quietest is listed. Items that play the same file share one analysis.
- Spectrum check: the room tone's 1/3-octave spectrum (63 Hz - 6.3 kHz, level removed) is compared with the group's median; only a different room tone (generator, air conditioning, another room, or speech all the way through) is moved to a '<track> - RT mismatch' track, with the band named.
- Progress window (gfx), updated between items; Esc / close cancels with nothing changed; all changes applied together at the end.
- Fix: an item was left opened up across defer cycles while measuring - REAPER drew it stretched and its audio stopped reading ('nothing to measure', no volume change). Each item is now measured in one go; items that cannot be measured are listed with the reason.

## 26.1026.1503pre1

- Initial release: level-match the room tone of touching / crossfaded selected items by take volume - however far apart the levels are; only groups fully in view.
- Room tone is measured on the WHOLE source file (quietest 10 %), so movement in the trimmed pauses does not count; an item whose own part is more than 6 dB louder than its file's quietest is listed.
- Spectrum check: the room tone's 1/3-octave spectrum (63 Hz - 6.3 kHz, level removed) is compared with the group's median; only a different room tone (generator, air conditioning, another room, or speech all the way through) is moved to a '<track> - RT mismatch' track, with the band named. A level difference alone never moves an item.
- Progress window (gfx) while analyzing; Esc / close cancels with nothing changed; all changes applied together at the end.

## 26.1026.1501pre1

- Initial release: level-match the room tone of touching / crossfaded selected items by take volume; more than 12 dB off -> moved to a '<track> - RT mismatch' track; only groups fully in view.
- Room tone is measured on the WHOLE source file (quietest 10 %), so movement in the trimmed pauses does not count; an item whose own part is more than 6 dB louder than its file's quietest is listed.
- Spectrum check: the room tone's 1/3-octave spectrum (63 Hz - 6.3 kHz, level removed) is compared with the group's median; a different room tone (generator, air conditioning, another room) is moved to the mismatch track with the band named.
- Progress window (gfx) while analyzing; Esc / close cancels with nothing changed; all changes applied together at the end.

## 26.1026.1456pre1

- Initial release: level-match the room tone of touching / crossfaded selected items by take volume; more than 12 dB off -> moved to a '<track> - RT mismatch' track; only groups fully in view.
- Room tone is measured on the WHOLE source file (quietest 10 %), so movement in the trimmed pauses does not count; an item whose own part is more than 6 dB louder than its file's quietest is listed.
- Spectrum check: the room tone's 1/3-octave spectrum (63 Hz - 6.3 kHz, level removed) is compared with the group's median; a different room tone (generator, air conditioning, another room: one band > 8 dB or > 3 dB on average off) is not level-matched but moved to the mismatch track, with the band named (e.g. '+14 dB around 100 Hz'). Two items that differ are both listed and left alone. The reference is chosen among the matching items.

## 26.1026.1446pre1

- Initial release: level-match the room tone of touching / crossfaded selected items by take volume (reference = the longest item with pauses); more than 12 dB off -> moved to a '<track> - RT mismatch' track; only groups fully in view.
- Room tone is measured on the WHOLE source file (quietest 10 %), so movement in the trimmed pauses does not count; an item whose own part is more than 6 dB louder than its file's quietest is listed.

## 26.1026.1430pre1

- Initial release: level-match the room tone of touching / crossfaded selected items by take volume (reference = the longest item with pauses); more than 12 dB off -> moved to a '<track> - RT mismatch' track; only groups fully in view.

