# hsuanice_CLB Load From Reaper.lua — Changelog

CLB - Load From Reaper (wrapper)

## 26.1012.1206

- Released as part of the 26.1012.1206 package update.

History before 26.1012.1206 (moved out of the script header; last header version: `261007.1708`).

```text
v261007.1708 - Fix: GetToggleCommandStateEx-based "is it running"
  check (v261007.1640) still toggled CLB off every time, confirmed by
  real testing — CLB never registers Reaper toggle state at all, so
  the check was always false. Replaced with a heartbeat ExtState flag
  CLB itself now sets on startup / clears on exit — the only robust
  "is it running" signal available for a plain reaper.defer() script
  with no toggle-state support. Also changed to ask before launching
  CLB when it isn't already open (user's own request), using CLB's
  own known command ID instead of re-resolving its script path via
  AddRemoveReaScript every time.
v261007.1640 - Fix: was closing CLB every time it was already open
  (GetToggleCommandStateEx-based check didn't work — see above).
v261007.1632 - Initial release.
```
