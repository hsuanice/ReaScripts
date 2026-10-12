# hsuanice_Reorder - Sort Items Vertically.lua — Changelog

(formerly `hsuanice_Reorder or sort selected items vertically.lua`)

ReaImGui - Vertical Reorder and Sort (items)

## 26.1012.1641

- Renamed to "Reorder - Sort Items Vertically" (was "Reorder or sort selected items vertically") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.0736

- First release in the hsuanice/ReaScripts repository.
- Requires the "hsuanice Library" package.

History before 26.1012.0736 (moved out of the script header; last header version: `261005.1820`).

```text
v261005.1820
- Fix: Copy to Sort now keeps each recording's channels together on the same
  layer of tracks ("group first, then track name"), instead of pooling all
  items by track name and letting overlaps scatter them.
  * Cause: items were bin-packed per track name one by one, so when two
    recordings overlapped, a channel of recording A could take recording B's
    place on the top track while A's other channels stayed above — mixing
    two recordings across layers, and overflow tracks were inserted right
    after their own track name (S, S overflow, S2, S2 overflow ...).
  * New: a "recording unit" = all items from the same recording (Filename
    mode: same base filename; Scene & Take mode: same scene+take) that start
    at the same timeline position. Each unit is placed WHOLE onto the first
    layer where none of its channels overlap; otherwise the whole unit moves
    to the next layer. Units starting together: more channels, then longer,
    goes on top.
  * Tracks are emitted layer by layer (layer 1: S, S2, CHING HAN, S3 ... ;
    layer 2: S, S2, CHING HAN ...), track-name/channel order within a layer.
  * Each layer's tracks get their own new REAPER track group (Media/Razor
    edit lead+follow), now in Filename mode too.
  * Both overlap modes share this logic; replaces the previous per-mode
    bin-packing (Filename range buckets / Scene & Take global slots).
v261004.0013
- Fix: Upfill (Reorder fill upward) no longer creates overlapping items.
  * Cause: still-unprocessed selected items were not counted as occupying
    their current track, so an earlier item could move onto a track where a
    later selected item still sat; that later item could not move up and
    stayed put, overlapping.
  * Now every selected item (including locked ones) is reserved on its
    current track first; the reservation is released only when it moves.
  * Upfill repeats passes until nothing can move up further, so space freed
    by an item moving up can be filled by others.
- Fix: Sort Vertically uses the same reservation logic. Each time cluster is
  placed as a whole; if any item cannot fit, the cluster stays where it was
  instead of falling back onto an occupied track.
- Fix: Overlap check ignores sub-microsecond floating-point error, so
  back-to-back items are not treated as overlapping.
v260902.0921
- New: Added ExtState-driven action wrappers for Upfill, Sort in Place, and
  Copy to Sort. Each wrapper now follows the settings last saved in this GUI.
- Update: Sort action UI now uses one mode-dependent button: Run Sort
  Vertically for Take/File keys, and Sort in Place for the Metadata key.
- Fix: Ascending preference is now stored explicitly as 1/0 in ExtState and
  is correctly followed by GUI actions and wrappers when disabled.

v260822.1314
- Fix: Copy to Sort's per-item Recorder Ch resolution no longer falls back to
  Interleave when a TRK# name has trailing/leading whitespace (e.g. "DOOR ").
  * Now resolves Ch directly from iXML CHANNEL_INDEX via the library's
    trk_name_and_channel() (Interleave -> CHANNEL_INDEX, no name matching).
  * Name-matching against TRK# fields is kept only as a trimmed cross-check
    fallback, and no longer used to silently substitute Interleave for Ch.
  * Debug now also prints normalized TRK name, matched TRK#, CHANNEL_INDEX,
    and INTERLEAVE_INDEX separately for easier troubleshooting.

v260730.1537
- Update: Copy to Sort progress/output refined for console-first workflow.
  * Console progress now emphasizes phase percentage only.
  * Removed overall percentage from progress lines.
  * Copy to Sort no longer opens ReaImGui result summary popup.
  * Final result summary (tracks created/items copied/extra overlap splits)
    is printed directly in the console.

v260711.1913
- Fix: Copy to Sort now preserves take channel mode (`I_CHANMODE`) when
  duplicating items to new tracks.
  * Keeps Rodilab-exploded mono channel playback/display state intact.
  * Prevents copied items from reverting to the source poly channel state.

v260510.1835
- Fix: Copy-to-Sort Mode 2 (Scene & Take) now consolidates tracks across slots
  when the items don't time-overlap — restoring the v260402.1924 space-saving
  behavior — but using each (group, slot) as the bin-packing unit, so a single
  slot's items never get split or interleaved with another slot's items on the
  same track.
  * Each metadata group's items are partitioned by global slot, then the
    slot-units are bin-packed: a unit is consolidated onto an existing sub_slot
    only when none of its items overlap any items already there.
  * Each sub_slot remembers its primary_slot (the slot of the unit that opened
    it). Track layout groups sub_slots by primary_slot row, then by metadata
    group, then by overflow level. So when consolidation succeeds across all
    slots, all tracks land in one row; when it fails (e.g. overlapping scenes),
    tracks split into per-slot rows aligned by recording session.
  * Track groups (MEDIA_EDIT_LEAD/FOLLOW) are still per (primary_slot, level).
  * Resolves cases where 7 channels × 4 sequential scenes were producing 20
    tracks instead of the desired 7 (one per channel, all scenes consolidated).

v260510.1721
- Fix: Copy-to-Sort Mode 2 (Scene & Take) — items from different scene+take slots
  no longer share a track within a metadata group, even when they don't overlap in
  time. Restores per-slot track alignment so each recording session occupies its
  own row of tracks across all channels.
  * Per-group bin-packing now partitions items by their global slot first, then
    packs within each (group, slot) by time only.
  * Track creation order: slot-by-slot, per slot
    [G1-primary, G2-primary, …, G1-overflow, G2-overflow, …].
    Groups with no items in a given slot are skipped, so empty tracks are not
    created (the previous v260402.1924 consolidation behavior is reverted, but
    empty per-slot tracks are still avoided).
  * Track grouping (MEDIA_EDIT_LEAD/FOLLOW) is now keyed on (slot, level), so a
    razor edit on slot 1 doesn't propagate to slot 2 even when they share a
    channel.
  * Resolves the case where e.g. BOOM1 items from session A and session B landed
    on the same track because they happened not to overlap.

v260402.1924
- New: Copy-to-Sort Mode 2 (Scene & Take) automatically assigns a REAPER track group
  to each level's tracks (primary level → Group A, overflow level → Group B, etc.).
  Media/Razor Edited Lead+Follow are grouped. Reuses existing group numbering to avoid collisions.
- Fix: Copy-to-Sort Mode 2 (Scene & Take) now uses global bin-packing per channel group
  instead of per-slot track creation.
  Items from different scene+take slots that don't overlap in time now share the same
  track, consolidating the output from (slots × channels × sub-tracks) tracks down to
  (channels × max-sub-tracks-per-channel) tracks.
  e.g. 4 channels × 3 max overlapping = 12 tracks instead of 28.

v260311.1530
- Fix: Copy-to-Sort Mode 2 (Scene & Take) overflow tracks now appear after ALL primary
  tracks in a slot, not immediately after each channel's primary track.
  Track layout per slot is now: [Ch1-primary, Ch2-primary, ..., Ch1-overflow, Ch2-overflow, ...]
  instead of: [Ch1-primary, Ch1-overflow, Ch2-primary, Ch2-overflow, ...].
  Implemented two-pass layer-by-layer track creation (bin-packing computed first,
  then tracks emitted level-by-level across all groups per slot).

v260311.1200
- Fix: Same-file, same-editing-range items no longer interleave with other recordings
  in Copy-to-Sort and Sort Vertically.
* Added RANGE_BUCKET constant (0.5 s) and get_src_offs() helper (reads D_STARTOFFS).
* Sort Vertically / File Name key: secondary sort key now includes source offset,
  so items from the same file at the same editing range sort adjacent within a cluster.
* Copy-to-Sort Mode 1 (Filename): changed from item-by-item to range-group-based
  bin-packing. Items sharing (base_filename, range_bucket) are placed as a unit on
  the same track; a new track is opened only when the whole group conflicts.
  Sort order upgraded to (bfn, range_bucket, take_name).
* Copy-to-Sort Mode 2 (Scene & Take): slot_items are sorted by (bfn, src_offs)
  before intra-slot bin-packing, so same-file same-range items tend to land on the
  same sub-track across different scene+take sessions.
v260228.1946
- Fix: GetMediaSourceFileName returns one string (not bool+string); removed incorrect
  "local _, p =" pattern so source filename is now actually read correctly.
- Fix: Scene & Take mode — when all items share the same scene+take key (or have none),
  automatically falls back to grouping by timeline start position. Items within TIME_TOL
  of each other get the same virtual key (same recording moment). The global slot
  bin-packing then separates different recording moments that overlap in time.
v260228.1930
- Fix: get_item_base_filename fallback now extracts scene+take key ("4-26-3_2") from
  take name format "TRACKNAME----SCENE_TAKE----DATE", stripping the per-channel prefix
  and date suffix. All channels of the same recording now share the same filename_base.
- Fix: Scene & Take mode now applies intra-slot bin-packing within each group×slot.
  When all items share the same scene+take (1 global slot), items within each channel
  group that overlap in time are automatically split onto separate sub-tracks.
  Items at the same timeline position (simultaneous multi-channel recording) are
  correctly routed to their own tracks.
v260228.1900
- Feature: New "Filename" option for Copy-to-Sort track order
  * Groups (tracks) are now sorted by source filename instead of track name or channel number.
  * The representative filename for each group is the alphabetically smallest base filename
    among all items in that group (channel suffix stripped, e.g. "4-5-1T1" from "4-5-1T1_A03").
  * UI option: Copy-to-Sort — order: ○ Track Name  ○ Channel  ● Filename
  * Preference persisted via ExtState (meta_order_mode=3)
v260226.2300
- Feature: New "Overlap grouping" option in Copy-to-Sort: "Scene & Take" mode
  * When enabled, overlapping items are grouped by iXML Scene & Take metadata
    instead of by base filename.
  * All metadata groups (e.g. BOOM1, NAN, FU) share the same global recording-session
    slots. Tracks are created in slot order:
      Slot 1: BOOM1 | NAN | FU | NA | YU | TIE  (all channels of session 4-29-7_1)
      Slot 2: BOOM1 | NAN | FU | NA | YU | TIE  (all channels of session 4-29-8_1)
  * Scene & Take is read from iXML metadata (SCENE + TAKE fields), with fallback to
    parsing the take name ("TRACKNAME----SCENE_TAKE----DATE" format).
  * UI option: Copy-to-Sort — Overlap grouping: ○ Filename  ● Scene & Take
  * Preference persisted via ExtState (meta_overlap_mode)
v260226.1940
- Fix: Overlap-split tracks no longer get numbered suffixes ("Ch 03 — BOOM1 2")
  * All tracks in the same metadata group keep the original label unchanged
- Fix: Within each metadata group, items are now sorted by (base filename, take name)
  before being assigned to track slots.
  * Result: items from the same poly recording (e.g. 4-5-1T1_A3, _A7, _A8) are
    always placed on consecutive tracks, grouped together.
  * Items from a later recording (e.g. 5-20-8T1) follow after, not interleaved.
- Refactor: Placement algorithm changed from "sub-group → one slot" to
  "flat sorted list → one-item-at-a-time slot assignment":
  * Each item is tried against existing slots independently.
  * If no slot is available, a new track is created with the same label.
  * This correctly handles the case where items within the same base-filename
    sub-group overlap each other (different channels of the same poly recording).
v260226.1850
- Feature: Font size control (popup menu "Aa" at top of window)
  * Presets: 75%, 100%, 125%, 150%, 175%, 200% of base size (14px)
  * Persists across sessions via ExtState
  * Uses ImGui_PushFont/PopFont for dynamic scaling (same approach as Item List Browser)
- Feature: Overlap avoidance in Copy-to-Sort via base-filename grouping
  * Items at the same timeline position with the same channel/track name are no longer forced to overlap
  * Within each metadata group (e.g., "Ch 03 — boom"), items are sub-grouped by base filename
    (base filename = filename stripped of channel suffix like _A3, .A3, _3, -3)
  * Same-base-filename items (same poly recording, split to mono) always stay on the same track
  * If base-filename sub-groups would overlap → additional tracks created:
    "Ch 03 — boom", "Ch 03 — boom 2", "Ch 03 — boom 3", …
  * Overlap count replaced by sub-track count in the result summary
v260120.1856
- Fix: Clear metadata cache at start of each Copy-to-Sort operation
  * Prevents stale metadata from previous runs causing overlaps
  * Calls META.begin_batch() to clear the global CACHE
  * Fixes issue where running Copy-to-Sort multiple times without closing
    the script window would cause overlaps due to cached I_CHANMODE values
  * Each operation now starts with fresh metadata reads
v260120.1705
- Debug: Enhanced TRK# field inspection
  * Now displays ALL non-empty TRK# fields for each item
  * Format: "→ All TRK fields: TRK1=all_mix, TRK3=boom, TRK5=YO, ..."
  * Helps diagnose why items are misclassified (e.g., wrong channel assignment)
  * Reveals when I_CHANMODE (interleave) doesn't match actual TRK# fields
  * Critical for understanding overlap and misclassification issues
v260119.2335
- Fix: Channel number now correctly extracted from BWF sTRK# metadata
  * Searches TRK1..TRK64 fields to find which number matches the track name
  * KNOWN ISSUE: Current logic relies on I_CHANMODE which can be incorrect
    if items have been moved between tracks in the timeline
  * KNOWN ISSUE: May cause misclassification when multiple TRK# fields exist
v260119.2235
- Fix: Channel parsing prioritizes filename (INCORRECT - reverted in v260119.2335)
v260119.2125
- Add: Comprehensive DEBUG_MODE with detailed logging for Copy-to-Sort operations
  * Shows metadata extraction (Track Name, Channel#) for each item
  * Displays grouping decisions and track naming
  * Logs track creation and item copying process
  * Helps diagnose overlap issues
- Add: File output for debug logs to avoid console truncation
  * Set OUTPUT_TO_FILE = true to write to file (default: enabled)
  * Output file: Scripts/hsuanice Scripts/Tools/Reorder_Debug_Output.txt
  * File is cleared at each operation
v251127.1700
- Cleanup: Removed Monitor auto-capture feature
  • Removed "Monitor auto-capture" checkbox from GUI
  • Removed request_capture() function and all related handshake logic
  • Removed CAPTURE_ON preference and set_capture_enabled() function
  • Removed cross-script ExtState signaling (SIG_NS namespace)
  • Simplified codebase - focus on core reorder/sort functionality

v250925_1038 change UI namming display
v250921_1819
  - Preferences are now persisted via ExtState:
    • Sort key (Take/File/Metadata) and Asc/Desc.
    • Metadata sort key (Track Name / Channel#).
    • Copy-to-Sort naming (Track Name / Channel#).
    • Copy-to-Sort group order (Track Name / Channel#).
    • Copy-to-Sort “Append Track Name” option.
  - All changes in the UI are saved immediately with save_pref(),
    and reloaded at startup with load_pref().
  - Result: user selections are remembered across script restarts
    and REAPER sessions, no need to reselect every time.

v250921_1732
  - Copy-to-Sort: decoupled "TCP naming (grouping)" from "Group order".
    • You can name new tracks by Track Name while ordering groups by Channel#, or vice versa.
    • When naming by Channel#, the option is now "Append Track Name to TCP label".
      Enabling it no longer just appends the most-frequent Track Name —
      it **splits each Channel# into separate tracks by Track Name**,
      e.g.:
        Ch 09 — BASS
        Ch 09 — PRODUCER
  - UI: Added separate radio groups for TCP naming and Group order in Metadata section.
  - Removed legacy two-arg signature; all callsites updated to the new 4-arg form.

v0.5.6.0
  - Copy-to-Sort: decoupled "TCP naming (grouping)" from "Group order".
    • You can name new tracks by Track Name while ordering groups by Channel#, or vice versa.
    • Optional: append the most-frequent Track Name to Channel#-named TCP labels.
  - UI: Added separate radio groups for TCP naming and Group order in Metadata section.
  - Removed legacy two-arg signature; all callsites updated to the new 4-arg form.

v0.5.5.2
  - UI refined
v0.5.5.1
  - UX: Press ESC to close the Reorder window (modal summary still closes first).
v0.5.5
  - Refactor: Decoupled auto-capture from metadata payloads.
    Reorder now issues handshake requests (req_before/req_after) and waits for ack,
    leaving all scanning to the Monitor. No TSV payload in Reorder anymore.
v0.5.4.4
  - Copy to Sort: Added result summary (tracks created, items copied) and overlap warning.
  - Summary popup now shows detailed counts right after the action completes.
v0.5.4.3 (2025-09-03)
  - Fix: Restored missing helper copy_item_to_track used by Copy-to-Sort.
    Copies item properties (pos/len/mute/vol/fades/color) and the active take
    (source, start offset, playrate, pitch, name).
v0.5.4.2 (2025-09-03)
  - Fix: Copy-to-Sort “invalid order function for sorting”.
    Replaced comparator with a stable string-key comparator (guards nil/types and enforces strict weak ordering).

v0.5.4.1 (2025-09-03)
  - Fix: Copy-to-Sort crash (“attempt to call a nil value 'snapshot_rows_tsv'”).
    Added forward declaration and bound the function definition so callers can invoke it reliably.
  - Fix: Metadata preview stability.
    Introduced PREVIEW_PAIRS / build_preview_pairs() and UI guards (generate via “Scan first 10 items”)
    to prevent nil indexing before data exists.
  - Cleanup: Removed stray duplicate emit_capture() and kept the payload-capable version used by
    run_engine() / run_copy_to_new_tracks().
  - Misc: Small refactors and comments; no functional changes to core reordering/sorting.

v0.5.4 (2025-09-03)
  - Feature: Opt-in Monitor auto-capture.
    • Added “Monitor auto-capture” checkbox; preference is persisted via ExtState.
  - Reliable Monitor auto-capture with BEFORE/AFTER payloads.
    • Emits separate ExtState keys: capture_before / capture_after.
    • Attaches snapshot_before / snapshot_after TSV payloads so the Monitor
      can restore the exact selection at the moment of action (no race).
  - Preference & UI:
    • Added “Monitor auto-capture” checkbox (persisted via ExtState).
    • Emissions are guarded by CAPTURE_ON; no Monitor dependency.
  - Integration points:
    • Wraps run_engine() and run_copy_to_new_tracks() with BEFORE/AFTER emits.
  - Fixes:
    • Removed duplicate emit_capture() implementation.
    • Sanitized TSV payload for newlines/tabs to avoid parsing issues.
v0.5.3 (2025-09-03)
  - Feature: Auto-capture hooks for Monitor integration.
    Emits an ExtState signal before/after operations so the Monitor script can snapshot automatically.
      • Namespace: "hsuanice_ReorderSort_Signal"
      • Key:       "capture"
      • Values:    "before:<timestamp>", "after:<timestamp>"
    Covered actions: Reorder, Sort vertically, Sort-in-place (if present), and Copy-to-Sort (new tracks).
  - Implementation: Added helper emit_capture(tag) and invoked it at the start ("before") and end ("after")
    of the execution paths (run_engine / run_copy_to_new_tracks). Signals are non-persistent (SetExtState …, false).
  - Safety: No dependency on the Monitor; if it’s not running the signals are simply ignored.

v0.5.2 (2025-09-02)
- Performance: Throttled selection polling to reduce per-frame rescans
  while the window is open. Replaced unconditional calls with a
  conditional helper (maybe_compute_selection).
- Logic: Recompute the selection snapshot only when
    • the number of selected items or tracks changes, or
    • the throttle timer expires (default 0.12s).
- UX: No behavior changes to actions. Main UI stays responsive;
  selection counts may update with a tiny (<120 ms) delay under heavy edits.
- Tunable: Exposed SCAN_INTERVAL constant to balance CPU vs responsiveness.

v0.5.1 (2025-09-02)
  - UX: Keep the main window open after actions.
  - New: Result Summary popup (ESC to close).
    • After any action (Reorder / Sort / Sort in Place / Copy to Sort),
      a modal popup shows “Items / Moved / Skipped”.
    • Close via the Close button or ESC; the main UI stays active.
v0.5.0 (2025-09-02)
  - New: Added "Sort in Place" for Metadata mode.
    • Works directly on existing tracks, no renaming or new tracks.
    • Sort key selectable: Track Name or Channel Number.
    • Ascending/Descending toggle supported.
  - "Copy to Sort" behavior unchanged.
  - UI: Metadata section now has two buttons:
      • Sort in Place
      • Copy to Sort
  - This allows users to sort selected items across existing tracks
    or duplicate them to new metadata-grouped tracks.
v0.4.0 (2025-09-01)
  - Switch all metadata reading to 'hsuanice Metadata Read' (>= 0.2.0):
    * iXML TRACK_LIST preferred; fallback to BWF Description sTRK#=Name (EdiLoad split).
    * Interleave from take channel mode; name/channel via Library tokens $trk/${chnum}.
  - Removed usage of legacy local parsers; UI/behavior unchanged aside from robustness.

v0.3.6
  - UI: Moved the main action button directly under
        "Sort by Metadata: Track Name / Channel Number".
        The Preview list now comes after the button so it never pushes
        the button off-screen.
v0.3.5a
  - Fix: "invalid order function for sorting" when using Copy to Sort.
         Now uses stable string-based order keys for both Track Name
         and Channel Number modes, preventing type/nil comparison errors.
  - Behavior unchanged:
      • Track Name mode → new track named by metadata Track Name.
      • Channel Number mode → new track named "Ch 01/02/…".
  - Stability: Copy-to-Sort now guaranteed consistent ordering regardless
    of mixed metadata types or missing values.
v0.3.5
  - UX: Removed duplicated "Copy to New Tracks" section.
  - UX: When Sort key = Metadata, the main action button becomes "Copy to Sort"
        and performs copy → new tracks using the chosen Metadata sub-key
        (Track Name / Channel Number) and Asc/Desc.
  - Copy naming:
      • Track Name mode → new track named by metadata Track Name.
      • Channel Number mode → new track named "Ch 01/02/…".
v0.3.4 Vertical UI
  - UI: Window renamed to "Vertical Reorder and Sort".
  - UI: Layout changed to vertical stack:
        Reorder → Sort Vertically → Sort by Metadata → Copy to New Tracks.
  - New: Sort Vertically now supports Metadata key (Track Name / Channel Number).
  - Preview: simplified to two-column mapping "Channel Number ↔ Track Name".
  - Minor: cleaned labels for clarity.

v0.3.3
  - New: Option "Order new tracks alphabetically (ignore channel #)" in Copy-to-New-Tracks.
         Uses natural sort so names with numbers order intuitively (CHEN 2.0 < CHEN 10.0).
  - Tweak: Name sort in Copy-to-New-Tracks now uses natural string key.

v0.3.2
  - Fix: "invalid order function for sorting" in Sort Vertically (Take/File).
         Comparator replaced with stable key-based ordering.
v0.3.1
  - Fix: Always call ImGui_End() to prevent "Missing End()" error.
  - Added Copy-to-New-Tracks-by-Metadata and metadata parsing improvements.
```
