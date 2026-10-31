# hsuanice_Library.lua — Changelog

## 26.1031.1234

- Fade Tool Core: existing fades keep their shape when resized (tested)

## 26.1031.1225pre1

- Fade Tool Core: existing fades keep their shape when resized

## 26.1031.1157

- Hover: fade shape helpers shared with other edit scripts (tested)

## 26.1031.1150pre1

- Hover: fade shape helpers shared with other edit scripts

## 26.1029.2330

- Hover: edge trim / extend keeps the fade shape (tested)

## 26.1029.1741pre1

- Hover: edge trim / extend keeps the fade shape

## 26.1029.1405

- Update: hsuanice_RGWH Core.lua (render no longer fails on an item with an empty take).
- Update: hsuanice_Metadata Read.lua (UMID fallback runs bwfmetaedit once instead of twice).

## 26.1029.1359pre1

- Update: hsuanice_RGWH Core.lua (render no longer fails on an item with an empty take).
- Update: hsuanice_Metadata Read.lua (UMID fallback runs bwfmetaedit once instead of twice).

## 26.1029.1330pre1

- Update: hsuanice_Metadata Read.lua (UMID fallback runs bwfmetaedit once instead of twice).

## 26.1029.1329

- Update: hsuanice_Metadata Read.lua (bwfmetaedit fallback finds the tool on Windows and on Intel Macs).

## 26.1029.1250pre1

- Metadata Read: bwfmetaedit fallback finds the tool on Windows and on Intel Macs

## 26.1028.2249

- Update: hsuanice_AudioSweet Core.lua (works with a hidden FX track).

## 26.1028.2243pre1

- Update: hsuanice_AudioSweet Core.lua (works with a hidden FX track).

## 26.1027.1608

- Fade Tool Core: Fix: a razor over several tracks no longer pulls cuts into tracks where it only covers empty space or the middle of an item (e.g. extending both items of a gap) when other tracks have cuts or item edges in the razor.
- Release: tested in REAPER 7.82.

## 26.1027.1553pre1

- Fade Tool Core: Fix: a razor over several tracks no longer pulls cuts into tracks where it only covers empty space or the middle of an item (e.g. extending both items of a gap) when other tracks have cuts or item edges in the razor.

## 26.1026.1232

- Update: hsuanice_Fade Tool Core.lua (razor inside an item: fade in and out).

## 26.1026.1230pre1

- Update: hsuanice_Fade Tool Core.lua (razor inside an item: fade in and out).

## 26.1025.2114

- Update: hsuanice_RGWH Core.lua (Render / Glue keep the exact fade shape and curve).

## 26.1025.2110pre1

- Update: hsuanice_RGWH Core.lua (Render / Glue keep the exact fade shape and curve).

## 26.1025.1231

- Update: hsuanice_Fade Tool Core.lua (existing fade shapes are kept).

## 26.1025.1227pre1

- Update: hsuanice_Fade Tool Core.lua (existing fade shapes are kept).

## 26.1024.1009

- Update: hsuanice_Fade Tool Core.lua (crossfade across a gap).

## 26.1024.1004pre1

- Update: hsuanice_Fade Tool Core.lua (crossfade across a gap).

## 26.1023.2047

- Update: hsuanice_Fade Tool Core.lua (Smart Fade support).

## 26.1023.2032pre1

- Update: hsuanice_Fade Tool Core.lua (visible-area rule, plain fades leave crossfades alone).

## 26.1023.2012pre1

- Update: hsuanice_Fade Tool Core.lua (Smart Fade nearest crossfade fix).

## 26.1023.2008pre1

- Update: hsuanice_Fade Tool Core.lua (one-sided crossfade adjustment).

## 26.1023.1958pre1

- Update: hsuanice_Fade Tool Core.lua (Smart Fade support).

## 26.1023.1944

- Add: hsuanice_Fade Tool Core.lua (used by the new Fade Tool package).

## 26.1023.1942pre1

- Update: hsuanice_Fade Tool Core.lua (fade shapes fixed on REAPER 7.82).

## 26.1023.1853pre1

- Update: hsuanice_Fade Tool Core.lua (crossfade shape fix).

## 26.1023.1800pre1

- Add: hsuanice_Fade Tool Core.lua (used by the new Fade Tool package).

## 26.1018.1239

- Update: hsuanice_Session Fix Core.lua (Workflow cues check, scan progress and check times, Tiny items with 2-pop recognition and marking).
- Update: hsuanice_AudioSweet Core.lua (Debug switch no longer changes the RGWH Debug Level).

## 26.1015.1425

- Update: hsuanice_Session Fix Core.lua (fade shapes on hidden tracks, check order).

## 26.1015.1303

- Update: hsuanice_Session Fix Core.lua (Mixed channels fix).

## 26.1015.1125

- Update: hsuanice_Session Fix Core.lua (short titles and impact levels for the checks).

## 26.1014.2216

- Add: hsuanice_Session Fix Core.lua (used by Session Fix - Interchange Prep).

## 26.1012.1206

- Add: CLB Compare Engine, EDL Parser, OTIO Bridge, Subtitle Bridge, Process Exec, json.lua (used by Conform List Browser).

## 26.1012.1113

- Add: Metadata Cache, Metadata Rename Core, List Table, Time Format, Metadata Generator (used by the Metadata packages).

## 26.1012.0957

- Add: hsuanice_Mouse.lua (used by Set Time to Item on Right-Drag Release).

## 26.1012.0737

- Add: hsuanice_Hover.lua (used by Hover Mode).

## 26.1011.2142

- First release as a single package: installs every shared library at once.
- Library files are no longer listed in the Action List.

