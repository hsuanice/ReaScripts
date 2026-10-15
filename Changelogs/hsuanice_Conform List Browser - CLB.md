# hsuanice_Conform List Browser - CLB.lua — Changelog

(formerly `hsuanice_Conform List Browser.lua`)

Conform List Browser

## 26.1015.1941

- Fix: CLB Jump Old New TC could show the previous video frame; jumps land exactly on the frame now, and DME Recut stores jump targets with full precision.

## 26.1015.1609

- First stable (non pre-release) version: EDL / AAF / XML / OTIO / subtitle import, matching, item generation, Jump / Link / Load / Reveal.
- Known limitation: comparing old / new cuts (Compare view) is not finished yet - it may change or be incomplete.

## 26.1012.1641pre1

- Renamed to "Conform List Browser - CLB" (was "Conform List Browser") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1206pre1

- First release in the hsuanice/ReaScripts repository.
- Requires the "hsuanice Library" package.
- Pre-release: everything is in daily use except Compare, which is still being tested — only installed when "Enable pre-releases" is on in ReaPack.
- Includes the CLB wrappers (Jump Old-New TC, Link Reaper Items, Load From Reaper, Reveal Item) and the Python helpers in Tools/ for AAF / XML / OTIO / subtitle import.
- EDL works out of the box. AAF / XML / OTIO need Python 3 + OpenTimelineIO; AAF also needs LibAAF's aaftool.
- Fix: the wrappers now find CLB from its file path, so they work on any machine.
- Window title / console version is read from the header.

History before 26.1012.1206pre1 (moved out of the script header; last header version: `261010.1341`).

```text
v261010.1341
- Fix: a box-select (drag) in the timeline panel never scrolled the event
  table to what it selected — real user report: a single click "linked"
  to the list, a drag didn't, even when it caught only one clip. The rows
  WERE selected, just off-screen. When the drag ends, the table now
  scrolls to the topmost selected row (in its own sorted/filtered order)
  and the selection's first/last rows become the Shift/arrow-key anchor/
  cursor. Selected guids gathered in one pass over SEL.cells.

v261010.1329
- New: right-click a clip in the timeline panel → the same row context
  menu as the event table (Assign Reel / Group, ...) — user's own request.
  Reuses draw_table's deferred popup (CLB.row_context/_open_row_ctx), so
  both menus stay identical. Right-clicking a clip outside the current
  selection selects it alone first (the menu acts on the selection).
- (Related, not this file: Tools/otio_to_clb.py v261010.1318 — AAF events
  with no reel/tape get "AX"; tape now read from the media's local copy
  next to the AAF. Src TC untouched.)

v261010.0026
- New: Follow Reaper is now two-way for multi-selection — user's own
  report: Reaper multi-select showed up in CLB, but not the reverse.
  Any CLB row-selection change (click, Cmd/Shift+click, Cmd+A, arrows,
  the timeline panel's click/box-select) now makes the selected rows'
  linked items Reaper's item selection (CLB.sync_reaper_from_table_sel).
  Detected generically via a new SEL.version counter (bumped by
  sel_clear/add/remove/toggle) rather than hooking every call site;
  synced once the mouse is released (a box-select drag rebuilds the
  selection every frame). Reaper's selection is left alone when none of
  the selected rows is linked; selections that came FROM Reaper (Reveal/
  Follow) are marked synced so they never bounce back; turning Follow on
  lets Reaper's current selection win first. Arrow-key nav now uses the
  same sync (plus moving the edit cursor to the cursor row's item).

v261010.0021
- Fix: every "Cmd" shortcut on macOS (Cmd+A/C/V/Z/Shift+Z/Y, Cmd+click
  multi-select) actually needed the physical Control key — real user
  report: Cmd+A did nothing. _mods() read ImGui_Mod_Super on macOS, but
  ReaImGui's ConfigVar_MacOSXBehaviors ("Enabled by default on macOS.
  Swap Cmd<>Ctrl keys") makes Mod_Ctrl the Cmd key there. Now reads
  Mod_Ctrl everywhere, and on macOS also still accepts Mod_Super (=
  Control, or Cmd if MacOSXBehaviors were ever turned off).
  (Item List Browser/Editor and the Reorder Monitor were checked too —
  their _mods() already accepts Ctrl OR Super, so Cmd already worked.)
- New: event table keyboard nav — user's own request. ↑/↓ move the
  selection one row (key repeat when held), Home/End (or Cmd+↑/↓) jump
  to the first/last row, Shift+any of these extends a range from the
  anchor. Visible (filtered/sorted) rows only, keeps the current
  column. Scrolls only as far as needed, with the list clipper still on
  (ListClipper_IncludeItemByIndex) so holding an arrow stays cheap. With
  Follow Reaper on, the selected rows' linked items get selected in
  Reaper and the edit cursor moves to the cursor row's item.
- New: Cmd+F jumps into the Search box.
- Fix: table shortcuts no longer fire while typing in a text field
  (Search, popups) — Cmd+A/C/V/Z, arrows, Home/End, Delete/Backspace,
  Esc now belong to that field (ImGui_IsAnyItemActive guard). Before,
  e.g. Backspace in an EMPTY Search box (no text change, so no
  sel_clear) also tagged the selected rows "Delete".
- Fix: Shift-range selection (Shift+click, and now Shift+arrows) walked
  raw ROWS, so it also silently selected rows hidden by filters/search
  in between (which Delete would then tag unseen) — now visible rows
  only. It also lost its anchor after one use (sel_clear wiped it), so
  a second Shift+click acted like a plain click — anchor now kept.
- New: Follow Reaper / Reveal Item / the Reveal wrapper handle a
  MULTI-item Reaper selection — every selected item's linked event rows
  get selected (CLB.reveal_reaper_selection). User's own choice: with
  several items, ALREADY-LINKED ones only (on-the-spot matching reads
  each item's audio metadata — too slow for e.g. a whole track);
  unlinked ones are counted in the status ("use Link"). One item works
  as before (matched + linked on the spot). Follow's change detection
  is now a count+first+last selection signature (CLB._reaper_sel_sig, 3
  API calls/frame) instead of just the first item.
- Cmd+A now also sets the Shift/arrow anchor (first row) and cursor
  (last row).

v261009.2349
- Change: Conform (All/Sel) now adds the matched audio as new take(s) on
  the linked Reaper item for rows linked via "Link Reaper Items"/Reveal
  (row.reaper_item_guid) too — not only Load From Reaper rows — instead
  of creating a new item on a new track. User's own request; reverses
  v261009.1505's deliberate separation. Both link kinds now go through
  CLB.row_linked_item. Track-suffixing still keys off row.__reaper_item
  only (only a Load From Reaper row's track is a live Reaper track name).
- New: on a linked item, Conform skips any audio file the item already
  has a take of (counted in the completion message) — several rows can
  share one linked item (same cut on V1 + a NONE track; A1/A2 matching
  the same file), and a re-Conform would otherwise stack duplicate takes.
- Perf: CLB.find_item_by_guid rescans the project on a miss at most once
  per project state change (GetProjectStateChangeCount), so Conform over
  many rows with stale links can't rescan once per row.

v261009.2122
- UI: button color groups recolored in rainbow order 紅橙黃綠藍靛紫
  (user's own request), following the left sidebar top→bottom: danger
  red, recut orange, align (Shift Range / Calibrate TC) purple → YELLOW,
  build green, io blue (top toolbar), list (Remove Dups / Consolidate)
  teal → INDIGO, link → a MUTED violet (lower saturation/alpha — user:
  Link/Reveal aren't serious enough to need an eye-catching color).
  CLB.push/pop_btn_color now take an optional 4th palette entry (text
  color) — used for yellow, where the default white text is hard to read.
- UI: "Auto Match" checkbox moved from the top toolbar (next to Load
  From Reaper) to the left sidebar, right under Match All, with the other
  match controls — user's own request. Same persisted setting/behavior;
  tooltip now names Load From Reaper explicitly since it no longer sits
  beside it. Always shown (Match All itself only appears once both a list
  and audio are loaded).

v261009.2104
- UI: Link Reaper Items, a new "Reveal Item" button and the "Follow
  Reaper" checkbox (+ its status text, now wrapped) moved out of the top
  toolbar to the very bottom of the left sidebar, in their own new
  magenta "link" button color group (CLB.BTN_GROUP_COLORS.link) — user's
  own request. Reveal Item = the same action as the
  hsuanice_CLB Reveal Item.lua wrapper, on the first selected Reaper item.

v261009.1823
- New: reverse link — Reaper item → its event row(s) in CLB
  (CLB.reveal_reaper_item; selects their Clip Name cells, scrolls the
  table and centers the timeline panel there). User's own choices:
  • Two triggers: a persisted "Follow Reaper" checkbox (off by default,
    next to Link Reaper Items) that reveals on every change of Reaper's
    first selected item — one pointer compare per frame, lookup only on
    change, result shown as small status text, no dialogs — and a new
    wrapper hsuanice_CLB Reveal Item.lua (pending_action "reveal_item")
    for a keyboard shortcut.
  • An item not linked yet is matched on the spot with the same 4-TC
    rules and the link is STORED (saved with the .clb) — but only onto
    rows without a link yet, never stealing one linked to another item.
  • A row hidden by current filters/search is still selected, with a
    note to clear filters to see it.
  • Clicking a linked Clip Name (CLB → Reaper) marks that item as already
    seen, so Follow doesn't bounce it straight back.
- Refactor: Link Reaper Items' matching extracted into shared
  CLB._build_link_index / CLB._match_item_rows (Link and Reveal share them).

v261009.1608
- New: pending_action "link_reaper_items" → CLB.link_reaper_items_selection(),
  driven by the new standalone wrapper hsuanice_CLB Link Reaper Items.lua
  (same heartbeat/ExtState pattern as the Load From Reaper wrapper). When
  CLB isn't open the wrapper only offers to open it — linking needs a list
  already loaded, which a fresh CLB never has.

v261009.1505
- New: "Link Reaper Items" button (next to Load From Reaper / Auto
  Match) — user's own request: link the rows of an ALREADY LOADED list
  (e.g. a .clb) to real items already in the session, so clicking a
  row's Clip Name selects and scrolls to its item. Real case: Picture
  Cut items generated from this list long ago and since converted to
  audio, item Notes / take data still intact. Unlike Load From Reaper
  (creates NEW rows from items), this only attaches items to existing
  rows. Select items in Reaper, click the button.
  • Matching: all 4 TCs, ±1 frame. Src In/Out from the item's take
    P_EXT:CLB_SRC_TC_* → else the item Notes' "Src In:/Src Out:" lines
    → else its source's BWF TimeReference + take offset (reverse
    conform, for real production audio with no CLB data at all). Rec
    In/Out from P_EXT:CLB_REC_TC_* vs the row's raw Rec TC first
    (survives an item that's since been moved), else the item's real
    position/length vs the row's calibrated Rec TC. When several rows
    share all 4 TCs, P_EXT:CLB_TRACK narrows them; any that remain
    are the same edit, so all get linked. Items matching nothing are
    listed in the report and NOT linked (no position-only guessing).
  • Persisted: stored per row as the item's GUID (new 23rd field of the
    .clb "R|" line — older files load unchanged; older CLB versions
    just ignore it). Resolved via a GUID→item cache rebuilt on miss.
  • Kept SEPARATE from row.__reaper_item on purpose: that pointer also
    makes Conform add takes onto the linked item and skips track-
    suffixing — a GUID link only drives jump/select, so linking an EDL
    row to a reference item never changes Conform's behavior.
  • Clip Name of a linked row shows a "Click to select its linked
    Reaper item" tooltip; a link whose item is gone logs a console note.
  Verified offline against the real session (POINT R1 Dialog .rpp,
  478 Picture Cut items) + conform_20260918.clb: 478/478 matched,
  via take data alone and via Notes alone, no multi-row ambiguity.
- Refactor: Load From Reaper's per-item read extracted into the shared
  CLB._read_item_event (used by both features). One behavior change:
  Load From Reaper's Src TC now also falls back to the item Notes'
  "Src In:/Src Out:" lines before BWF TimeReference — a glued/rendered
  item's BWF TC is the glue file's own, not the original source's.

v261008.1052
- Change: unified default filenames across Export and Save CLB
  Project, per the user's own explicit spec — "export_YYMMDD_HHMMSS"
  for all 3 Export formats (prefix changed from the previous pass's
  "clb_" to "export_") and "conform_YYMMDD_HHMMSS" for Save CLB
  Project (added seconds + switched from 4-digit to 2-digit year,
  matching Export's own format — was "conform_YYYYMMDD_HHMM" with no
  seconds before this).

v261008.1033
- Change: all 3 Export formats (EDL/TSV/CSV) now default to a
  timestamped filename ("clb_YYMMDD_HHMMSS.<ext>") instead of the
  generic "export.<ext>" — user's own request, same idea Save CLB
  Project's own default filename already uses.

v261008.1021
- New: Export TSV / Export CSV — user's own request. New
  CLB._build_edl_table_text(format_type, rows) mirrors the Audio Files
  panel's existing build_audio_table_text (same escape_field_value
  helper, same tab/comma separator convention), but against the main
  table's own HEADER_LABELS/get_cell_text — includes every CURRENTLY
  VISIBLE column, in the user's current column order (EDL_COL_ORDER/
  EDL_COL_VISIBILITY), unlike Export EDL's fixed narrow CMX3600
  schema. New CLB.export_tsv_csv(format_type) handles the save dialog
  + file write, exporting the full list (not just the filtered view —
  same convention Export EDL already used).
- Change: "Export EDL" button replaced with a unified "Export..."
  button opening a popup menu (Export EDL.../Export TSV.../Export
  CSV...) — user's own request: "Export整合成和Import一樣，點下去後才看到
  要輸出什麼格式" (make Export work like Import — show format choices
  only after clicking). Same pattern as the existing "Load List..."
  button, which already consolidates Load EDL/XML/AAF/Subtitle the
  same way.

v261007.1711
- New: "Load From Reaper" no longer re-asks the same two confirm
  dialogs on every run — user's own request, since it's commonly
  re-run many times while iterating on a match. (1) FPS confirm: now
  skipped after the first successful run IN THE SAME REAPER PROJECT
  (tracked via GetProjExtState/SetProjExtState — lives in the .rpp
  itself, so a different project correctly asks again). (2) Replace/
  Append dialog: new Options setting CLB.ref_load_merge_mode ("ask"
  default | "replace" | "append") skips it entirely when set to a
  fixed choice. _apply_timeline_results (the shared load pipeline
  every loader uses) gained an optional 4th `opts` table
  ({force_choice, skip_fps_confirm}) to support both — every other
  loader (EDL/XML/AAF/Subtitle) always passes neither, unaffected.
  New "Load From Reaper: Replace/Append" radio buttons in Options.

v261007.1701
- New: "is_running" heartbeat ExtState flag — set on startup, cleared
  via reaper.atexit on exit. Real user report: the "Load From Reaper"
  wrapper's GetToggleCommandStateEx-based "is CLB already running?"
  check (v261007.1635) still toggled CLB OFF every time it was
  already open, confirmed by testing — this script never registers
  Reaper's own toggle-command state at all, so that check was always
  false regardless of whether CLB was actually running. This flag is
  the robust alternative: the wrapper (now hsuanice_CLB Load From
  Reaper.lua v261007.1708) reads it directly instead.
- Fix: a row loaded via "Load From Reaper" could get its real, live
  Reaper track name mangled with a confusing source-index suffix
  (e.g. real track "A1" coming out as something like "A1 - 3") —
  real user report with a screenshot, triggered whenever
  CLB.edl_sources held more than one entry (any other load mixed in,
  or "Load From Reaper" itself run more than once in one session).
  Root cause: _apply_track_suffixes() exists to disambiguate an EDL's
  own ABSTRACT track label (e.g. "A1" meaning "that file's own audio
  track 1") when the same label shows up across several separately-
  loaded EDL files covering one reel — it was never written with
  "Load From Reaper" in mind, where row.track is already the REAL,
  live Reaper track name, not an abstract label needing
  disambiguation at all. Now skips any row with row.__reaper_item set
  entirely, in both its "restore original" (single source) and
  "apply suffix" (multiple sources) branches.

v261007.1653
- Fix: "Load From Reaper" rows had an empty Notes column even when the
  item they came from had real Notes text — user's own observation.
  Root cause: _make_rows_from_events's row.notes was only ever
  populated from evt.comments (EDL comment lines), a concept
  CLB.load_from_reaper_selection has no equivalent for. Added a second,
  direct evt.notes string field (appended to, not replacing, any
  evt.comments-derived text — the two are mutually exclusive in
  practice) — CLB.load_from_reaper_selection now sets it to the item's
  own P_NOTES verbatim (multi-line text collapsed to the same " | "-
  joined single line as EDL comments, for consistent display).

v261007.1635
- Fix: "Load From Reaper" rows showed the frozen P_EXT:CLB_TRACK value
  (whatever track the item was ON WHEN GENERATED) instead of the
  item's actual CURRENT Reaper track — real user report with a
  screenshot. User's own framing: this list should reflect the
  session's current state, and an item may have moved to a different
  track (or that track been renamed) since it was created. Swapped
  the fallback order: Track now prefers the live Reaper track name,
  falling back to P_EXT only if that's somehow unavailable.
- New: CLB's main loop now polls a one-shot ExtState flag
  (hsuanice_ConformListBrowser / "pending_action") at the top of every
  frame, consuming it immediately — lets an external wrapper script
  drive CLB (currently: "load_from_reaper" → runs
  CLB.load_from_reaper_selection()) via a Reaper Action List shortcut,
  whether CLB's window is already open or needs to be launched fresh;
  the flag is picked up on the very next frame either way. New
  standalone wrapper hsuanice_CLB Load From Reaper.lua — user's own
  request: select items in Reaper, run the wrapper, it brings up CLB
  and runs the rest automatically, same pattern as the existing
  hsuanice_CLB Jump Old-New TC.lua wrapper (though that one never
  needs CLB running at all, since it only reads real project data —
  this one actually has to call INTO CLB, a new class of wrapper for
  this toolkit). Documented honestly in the wrapper's own @about: if
  CLB is already open but not focused, Reaper doesn't guarantee
  bringing its window to front just because its action command runs
  again while its defer loop is active — only the ACTION itself
  (load + optional auto-match) is guaranteed, not window focus.

v261007.1625
- Fix: conform_matched_items — every conformed take's own name was
  showing the EDL clip name instead of the matched audio file's own
  name, including the first/primary match (not just additional ones
  from a "Multiple" match). Real user report with a screenshot
  (REAPER's own Take list showing "Take 2/7: 26_01_T02_B - Merged" —
  a clip name, not a filename). Root cause: the take-naming code had a
  ti==1-vs-ti>1 split (first take = row.clip_name, later ones =
  af.filename) left over from an earlier design; since both the
  normal new-item path AND the new Load-From-Reaper linked-item path
  share this one loop, a single-match row always hits ti==1 — so
  EVERY normal conform's take, and the one real new take added onto a
  linked Reaper item, used clip_name. The clip name is already visible
  elsewhere (item Notes, P_EXT, the event list itself); the matched
  file's own name is the one thing you need on the take itself to
  verify which file actually matched. Removed the ti split entirely —
  take name is now always af.filename (or af.basename, or row.clip_name
  only as a last-resort fallback if neither exists). Also removed a
  dead first_take/else branch that called the identical
  AddTakeToMediaItem(item) in both arms.

v261007.1618
- New: rows loaded via "Load From Reaper" now carry a direct link
  (row.__reaper_item) back to the real item they came from. Clicking
  the Clip Name cell on such a row selects and scrolls to that exact
  item in Reaper — user's own request, parallel to the existing 4-TC-
  column click-to-jump but precise to one specific item (a shared TC
  position alone could land on the wrong one among several). Threaded
  through _make_rows_from_events (evt.__reaper_item → row.__reaper_item,
  nil for every other load path) and set when building the synthetic
  events in CLB.load_from_reaper_selection. Lost on .clb save/reload,
  same already-accepted limitation as row.__match_candidates (a raw
  item pointer can't be serialized).
- Change: conform_matched_items — a row with a valid, still-alive
  row.__reaper_item now adds the matched audio as a NEW TAKE on that
  SAME real item instead of creating a separate item on a separate
  track. User's own request: "套到的資訊，應該直接變成原本那個item 的
  takes，不需要額外增加一軌新的" (the matched info should become that
  original item's own takes, no need for an extra new track). The
  item's own position/length are left untouched (only a take is
  added, never a move/resize); falls back to the normal new-item-on-
  a-track path if the linked item was deleted since loading. Track
  collection now skips linked rows entirely, so no empty unused track
  gets created for them. Confirm dialog and completion message both
  mention the linked-item count for transparency.

v261007.1606
- New: "Load From Reaper" — reads currently selected Reaper item(s)
  back into the event list, the reverse of Generate Items/Generate Ref
  Media. User's own framing: "另外一種list來源" (another kind of list
  source), deliberately general-purpose, not just for testing — real
  motivating case given: re-verify a just-generated batch of Full-mode
  reference items actually Find-Matches correctly, without re-
  exporting/re-loading any EDL file. Builds a synthetic
  EDL.parse()-shaped event list from the selection (sorted by timeline
  position for event numbering) and hands it to the SAME
  _apply_timeline_results pipeline every other loader already uses —
  gets the existing Replace/Append/Cancel prompt, source registration,
  filter rebuild, and FPS confirm for free. Per-item field fallback
  chain: Src TC prefers P_EXT:CLB_SRC_TC_IN/OUT (exact round-trip for
  CLB-generated items) then the take's own source BWF TimeReference +
  D_STARTOFFS/D_PLAYRATE (same math as
  hsuanice_Item List Editor.lua's calculate_source_position, for real
  production audio); Reel/Scene/Take prefer P_EXT/the item's own Notes
  (CLB's "Reel:"/"Scene:"/"Take:" convention) then the source file's
  own iXML fields. New CLB._read_metadata_from_source(src) factored out
  of the existing read_audio_metadata(filepath) so this reuses the
  exact same BWF/iXML field-reading logic already proven for the Audio
  Files panel, instead of a second implementation.
- New: "Auto Match" checkbox next to the button (persisted setting,
  off by default) — when on, loading also runs Find Match right after
  (loading Audio first via the same folder-picker as "Load Audio..."
  if none is loaded yet, otherwise matching immediately). Discussed
  and iterated on with the user before implementing: originally
  proposed as two separate buttons ("Load" vs. "Load + Auto Match"),
  changed to one button + a toggle at the user's own suggestion.
- Fix (caught before shipping): _apply_timeline_results (the shared
  loader pipeline every Load action — EDL/XML/AAF/Subtitle/this one —
  already uses) now returns true/false for whether it actually applied
  anything, instead of nothing. It silently returned on an unchanged
  ROWS when the user picked Cancel on its own Replace/Append prompt;
  every EXISTING caller already ignored the return value so this is
  backward-compatible, but CLB.load_from_reaper_selection needed it —
  without it, cancelling that prompt while "Auto Match" was on would
  still have run Find Match against the OLD, unchanged list.

v261007.1451
- Change: removed the "Simple" (shared-file) mode from Generate Ref
  Media entirely — user's own request: "我希望保留 full完整版就好...
  因為如果要basic，那用一般 empty item的就好" (just keep the Full
  version — if Basic/no-real-metadata is what's wanted, the plain
  "Generate Items" empty-item placeholder already covers that; this
  feature's reason to exist is specifically the real embedded BWF/
  iXML metadata). Deleted CLB.generate_reference_media_shared and
  CLB._build_ref_ixml (the shared-mode-only iXML builder) entirely.
  CLB.ref_media_mode setting removed.
- New: the popup that used to pick Simple-vs-Full now picks SCOPE
  instead — "Visible list (currently filtered/shown)" (default,
  unchanged existing behavior) vs. "Selected rows only" (matches the
  existing convention used by Conform Selected/Remove Dups/etc., via
  get_selected_rows()) — new CLB.ref_media_scope setting ("visible"
  default | "selected"), shows a live "N row(s) in scope" count that
  updates as the radio choice changes. Row-set resolution + the "no
  rows have Src/Rec TC" check moved from
  CLB.generate_reference_media_prepare() into
  CLB.generate_reference_media_pick_folder_and_run() (now has to
  happen after the scope choice, not before it) — prepare() itself is
  now just guards + opening the popup.
- Fix (caught before shipping, not a user report): the moved
  CLB.generate_reference_media_pick_folder_and_run() calls
  get_selected_rows(), a `local function` declared much later in this
  file (every other caller already happens to be below its
  declaration) — bare local references resolve lexically, so code
  positioned before a local's declaration can't see it regardless of
  call-time order; luac -p can't catch this class of bug (same as the
  DME Recut ctx-argument miss noted earlier this session), only
  manual scope-tracing does. Relocated the whole function to
  immediately after get_selected_rows()'s own definition instead of
  leaving it up near the rest of Generate Ref Media.

v261007.1434
- Revert: the v261007.1417 "simplify Full mode to drop all BWF/iXML
  metadata" change is reverted — real user report immediately after
  testing both modes side by side: Item List Editor (a separate
  hsuanice metadata-reading tool) showed Source TC for Basic/shared-
  mode items but blank Source TC for Adv/independent-mode ones, since
  there was no metadata left to compute it from (D_STARTOFFS=0, no
  embedded TimeReference at all — Source TC existed only as text in
  each item's own Notes). Asked whether this was acceptable; answer was
  explicit and strict: "ADV 模式就是要有完整的metadata，包含TC 嚴格！"
  (Adv mode must have complete metadata including TC — strict).
  Restored CLB._build_ref_ixml_independent and the per-event
  TR_Write(tr_samples)/Write_iXML_Raw/SecToSamples calls exactly as
  they were at v261007.1336 — "Full" mode embeds real per-event BWF
  TimeReference + iXML (Scene/Take/Reel) again, batch_size back to 10.
  The "_REF" filename prefix added in the same v261007.1417 pass is
  KEPT (that part was never in question — only the metadata-dropping
  part was reverted).

v261007.1417
- Change: "Full" (independent) mode's filenames now get a leading
  "_REF" prefix — "_REF001_AX_Universal Counting Leader.wav" instead
  of "001_AX_Universal Counting Leader.wav" — user's own request: once
  these files end up bundled into one delivery folder alongside real
  production media, a leading "_" (rare in ordinary filenames) plus
  "REF" makes them unmistakably reference-only at a glance.
- Simplify: "Full" mode no longer embeds any BWF/iXML metadata at all
  (removed CLB._build_ref_ixml_independent and the TR_Write/
  Write_iXML_Raw/SecToSamples calls entirely) — user's own
  simplification, after reflecting that the cross-software Source-TC
  problem which originally motivated embedding a real per-event
  TimeReference turns out to be a Pro Tools import/translation
  question, out of CLB's control either way ("這是別的軟體的事了我們先
  不處理"). Now follows
  hsuanice_Convert empty items to audio items.lua's own approach
  exactly: one real silent WAV per event (still sized to that event's
  own Rec duration, still in its own subfolder) just so the item is
  portable to other DAWs, D_STARTOFFS=0/D_PLAYRATE=1.0, take name =
  clip name, and Source TC/Scene/Take/Reel/Speed-flag all live in the
  item's own Notes (already had most of this from v261007.1300 for a
  different reason — now it's ALSO this mode's only metadata record,
  not just a human-review convenience alongside embedded BWF). No
  longer needs bwfmetaedit at all for this mode specifically (sox
  only) — lighter and simpler; batch_size raised 10→20 accordingly.

v261007.1355
- Change: user's own suggestion after the v261007.1345 fix — ask which
  mode (Simple/Full) BEFORE the folder picker, not after. Reordered:
  CLB.generate_reference_media_prepare() now only validates + opens the
  mode popup (no folder dialog at all); its "Next: Choose Folder..."
  button (renamed from "Generate") closes the popup, then a new
  CLB.generate_reference_media_pick_folder_and_run() shows the folder
  dialog and dispatches to the matching generator. This also happens
  to be a cleaner fix for v261007.1345's bug than the deferred-flag
  workaround: the popup now opens from a plain button click with NO
  blocking dialog before it at all (same shape as the already-working
  DME Recut Settings popup), so CLB.ref_media_want_popup is gone
  entirely — nothing left to defer. Applied the same caution in the
  new direction too: the folder dialog isn't called directly from the
  "Next" button (which fires while still inside that popup's Begin/End
  pair) — it's deferred via CLB.ref_media_want_folder_pick, consumed
  right after EndPopup in the same frame, so the blocking dialog never
  straddles an open ImGui widget boundary either way.

v261007.1345
- Fix: real user report — clicking "Generate Ref Media..." only showed
  the Finder folder picker; after choosing a folder, nothing happened
  (no settings popup, no progress). Root cause: unlike
  CLB.dme_recut_prepare (pure synchronous Lua, no I/O) which this
  popup's prepare/popup/execute split was modeled on,
  CLB.generate_reference_media_prepare() calls
  reaper.ImGui_OpenPopup() right after returning from a BLOCKING
  native dialog (JS_Dialog_BrowseForFolder) — a combination with no
  precedent anywhere else in this file (Load Audio Folder uses the same
  blocking dialog but never follows it with an ImGui popup). Whatever
  ImGui frame/ID-stack state a blocking modal mid-frame leaves behind,
  OpenPopup couldn't latch onto it, so the matching BeginPopup never
  saw it open. Fixed by deferring: prepare() now just sets
  CLB.ref_media_want_popup = true; the button's own draw code consumes
  it (OpenPopup + reset) on the very next frame, right before its
  BeginPopup check — decouples the popup-open call from the dialog's
  return entirely.

v261007.1336
- New: "Generate Ref Media..." now opens a mode-picker popup first
  (mirrors the DME Recut Settings dialog) instead of generating
  directly — user feedback on the shared-file design: BWF survives
  being handed between software more reliably than anything that
  lives only inside this REAPER project (D_STARTOFFS), and even iXML
  itself can get dropped in some conversions in their experience, so
  the existing "ONE shared file" approach risks failing on a transfer
  to other software.
- New: "Full" mode (CLB.generate_reference_media_independent) — one
  real silent WAV PER EVENT, each with its OWN embedded BWF
  TimeReference (that event's real Source TC, via
  E.SecToSamples — not fixed at 0) + its own iXML carrying Scene/Take/
  Reel. Each item's D_STARTOFFS is 0 (the file itself already starts
  at the right Source TC, no REAPER-side trick needed). Written into
  an auto-created subfolder (reaper.RecursiveCreateDirectory) named
  from the same ${timestamp} template, not loose in the chosen parent
  folder — this mode can create hundreds/thousands of files. Filename
  per event: "{event_num}_{reel}_{clip_name}" (sanitized), always
  collision-free since event_num is unique. Slower than the existing
  mode (real sox + bwfmetaedit x2 per event) — smaller batch_size (10
  vs 60) to keep the progress bar responsive.
- Change: the pre-existing single-shared-file behavior is now "Simple"
  mode (CLB.generate_reference_media_shared, logic unchanged from
  v261007.1300) — split out from the old CLB.generate_reference_media
  together with a new CLB.generate_reference_media_prepare() (guards +
  folder picker + usable_rows, same prepare/popup/execute split as
  CLB.dme_recut_prepare/_execute) and a new CLB.ref_media_mode setting
  ("shared" default | "independent"). CLB._build_track_map_for_rows()
  factored out of the old single function so both modes build their
  per-row Reaper tracks identically.

v261007.1300
- New: "Speed" column (COL.SPEED) — surfaces an EDL M2 (aux source
  timecode) line's raw rate per event, e.g. "48.0" or "-24.0". Real
  user comparison (292-event production EDL vs. its own generated
  item list, event-by-event) found 114 Source-End-TC mismatches, ALL
  and ONLY on events carrying an M2 line — confirmed via exact ratio
  math (Src-duration/Rec-duration == M2-rate/project-fps for every
  single one, no residual error) that M2 flags a clip shot at a
  different native frame rate (speed retime) or, when negative,
  reverse playback. hsuanice_EDL Parser.lua (v261007.1253) now parses
  this into event.aux_rate; carried through to row.aux_rate (both the
  initial parse and the .clb/Compare-session save formats, new
  trailing field, backward-compatible). User's own framing after
  seeing this: CLB's job is to show which events are retimed, not to
  guess how to correct them — "我們只負責套原始檔案，或是知道正確的長度"
  (we're only responsible for referencing the original file, or
  knowing the correct length) — so this column is informational only,
  not a correction.
- Change: Generate Ref Media's confirm dialog now mentions how many
  visible events carry this flag (if any), and each such item's own
  Notes get a "⚠ Speed: N.N" line — human-review flag, not a
  correction (Source End TC in that item still assumes normal speed).
- Change: Generate Items / Conform Matched Items / Generate Ref Media
  now all include Scene/Take (when present) in each created item's
  Notes, alongside the existing Reel/Src In/Src Out — user's own
  simplification of an earlier, much bigger ask (embedding into real
  audio FILES after matching): "generate時，把這些metadata資訊，寫在
  item note裡就好" (just write it into the item's own Notes at
  generate time) — no file writes at all, so this carries none of the
  risk embedding into original production recordings would have.

v261007.1246
- Fix: a short, no-name "BL" (blank/slug) event — real user report with
  a screenshot, a 2.333s-long event at Rec 03:00:01:20 — still showed
  padded/extended audio past the shared reference file's end. The
  v261007.1212 B_LOOPSRC=0 fix only covers an item whose own START-
  OFFSET (real Source TC, often hours) exceeds the file's short
  physical length; it does nothing when an item's start-offset is
  small/zero but its own REC DURATION ALONE already exceeds the file's
  fixed 2.0s. Fixed by sizing REF_DURATION_SEC to the LONGEST usable
  event's own Rec duration instead of a flat 2.0s (verified safe on
  this real 292-event list: longest event is 34s, nowhere near the
  multi-GB territory v261007.1149 fixed — this only ever has to cover
  one event's own duration, never the full absolute Source TC range).
  Both fixes are complementary, not alternatives: this one and
  B_LOOPSRC=0 each close a different failure mode of the same single-
  shared-file design.

v261007.1212
- Fix: generated filename came out literally as "_.wav" — real user
  report with a screenshot. Root cause: ref_media_name_format was
  persisted in ExtState from BEFORE the v261007.1149 redesign changed
  its default from "${reel}_${track}" to "!CLB_Mute_${timestamp}";
  load_prefs()'s default-on-missing-key logic doesn't touch a value
  that WAS already saved, so the stale old-style template kept loading
  with ${reel}/${track} tokens the new design no longer provides,
  silently expanding to nothing. load_prefs() now detects and migrates
  any old-style value (contains ${reel}/${track}, or is missing
  ${timestamp}) back to the current default.
- Fix: generated items' Source Start/End TC read back completely blank
  in hsuanice_Item List Editor.lua (and presumably any other BWF-reading
  tool) — real user report with a screenshot (14 items, both columns
  empty). Root cause, confirmed by direct bwfmetaedit testing: writing
  --TimeReference=0 to a WAV with no pre-existing bext chunk is a
  silent no-op — bwfmetaedit prunes the WHOLE bext chunk back out
  whenever every field in it would end up at its default value, so the
  reference file's bext chunk (and therefore its TimeReference) never
  actually got created at all, even though the write command itself
  reported success. hsuanice_Metadata Embed.lua's TR_Write() now takes
  an optional 4th `originator` argument that's written in the SAME
  command (confirmed this keeps the chunk from being pruned); CLB now
  passes "hsuanice CLB".
- Fix: generated items could show a looped/repeated waveform — user's
  own report plus a concrete, directly relevant precedent they pointed
  to (hsuanice_Convert empty items to audio items.lua, which avoids
  this by sizing its own shared silent file to the longest item in
  each group). Investigated that approach for this feature too, but
  it doesn't actually apply here: that script always uses
  D_STARTOFFS=0, so a file merely longer than the longest item is
  enough; CLB's items instead set D_STARTOFFS to each event's real
  Source TC (often far larger than any practical shared-file length),
  so sizing the file to "longest event length" wouldn't reliably avoid
  the loop and would reopen the huge-file problem v261007.1149 fixed
  for lists spanning hours. Used a cheaper, fully general fix instead:
  new items now have B_LOOPSRC off, so playback past the shared file's
  short physical end reads as silence past end-of-source (correct —
  the file is silent throughout anyway) instead of wrapping/looping,
  regardless of how large an individual item's own D_STARTOFFS is.

v261007.1149
- Fix: "Generate Ref Media..." (v261007.1135) generated one WAV per
  (reel, track) group spanning that group's FULL real TC range —
  real user report with a screenshot: files up to 10.4 GB each, for a
  session with reels spanning hours of real timeline. Root cause: the
  file's own audio content never needed to be that long in the first
  place — D_STARTOFFS can exceed a source's own physical duration
  without Reaper objecting (it just plays silence past the end,
  indistinguishable from this file's own silence anyway), and that
  metadata (not real sample data sitting at that offset) is exactly
  what AAF/OMF/XML conform interchange actually reads to compute a
  clip's Source TC.
- Change: now generates exactly ONE short (2s) shared reference WAV
  for the entire run — user's own request, confirmed by them: same
  idea as EdiLoad's own generic "!EdiLoad_Mute_<timestamp>.WAV" file
  (which turned out to be the right real-world precedent all along).
  The shared file's own BWF TimeReference is fixed at 0; every item's
  own Source TC is instead baked entirely into its own D_STARTOFFS
  (that event's real, fully-calibrated Source TC in seconds) — so
  (file TR=0 + item's own offset) still gives each item's correct
  absolute Source TC independently, regardless of which reel/track it
  came from, with no per-reel file needed at all. This also makes the
  (reel, track) grouping from v261007.1135 unnecessary — removed.
  ref_media_name_format's default changed from "${reel}_${track}" to
  "!CLB_Mute_${timestamp}" (only token now: ${timestamp}) to match.
  The file's iXML no longer carries per-reel Tape/Track fields (there's
  only one universal file now) — just a note identifying it as CLB-
  generated reference media; reel/track identity still travels via
  each item's own P_EXT fields and take name, unaffected.
- Feature: progress bar for item creation — already free via the
  existing generic draw_loading_progress()/CLB.batch_job mechanism
  (same one Generate Items already uses), not new code; collapsing
  file-generation down to one fast step (was a per-group loop with no
  progress) addresses the "need progress display" request for that
  part on its own, since there's no longer a slow multi-file loop to
  show progress for.
- Verified TimeReference=0 writes and reads back correctly via
  bwfmetaedit (not a special/reserved "unset" value) before relying on
  it as the shared file's fixed baseline.
- Feature: "Generate Ref Media..." — a client reported that an exported
  picture-cut track carries no Source TC at all, so they can't
  re-conform the original files themselves; "Generate Items" only ever
  creates REAPER-internal placeholders (P_EXT fields, no real
  underlying file), which don't survive export to another tool at all.
  This generates REAL silent WAV files with embedded BWF TimeReference
  + iXML (Tape/Track name), so any professional tool reading the
  exported/conformed media can compute each clip's own correct Source
  TC (file's BWF TimeReference + that clip's start-offset — standard
  broadcast-wave math every NLE/DAW already understands) alongside its
  Clip Name (the item/take's own name, sequence-level metadata that
  travels with the edit regardless) and a real, meaningful filename.
  Deliberately NOT one WAV per event (user's own reference: this is how
  EdiLoad V4 behaves) — ONE shared reference WAV per (reel, track)
  group, long enough to span every event in that group; each event
  becomes a REAPER item referencing that SAME file via D_STARTOFFS
  (the same "many items, one shared PCM source" mechanism
  CLB.dme_recut_execute's Copy mode already uses), so a list with a
  few thousand events but a few dozen reels only generates a few dozen
  real files, not thousands. Grouped by (reel, track) specifically, not
  just reel — different tracks on one reel are genuinely different
  audio content (e.g. DME stems share one embedded timecode baseline
  but are NOT interchangeable — the real bug CLB.dme_recut's own
  duplicate-content warning exists for) and must never share one file.
  Settings: output folder (asked each run, like Load Audio) and a
  filename template (Options > Formats, ${reel}/${track} tokens,
  default "${reel}_${track}"). Reuses existing shared libraries end to
  end — hsuanice_Metadata Embed.lua's CLI_Resolve/TR_Write/SecToSamples
  for bwfmetaedit, plus a new Write_iXML_Raw added there for this (see
  its own changelog); hsuanice_Process Exec.lua's run_capture/
  shell_quote for the new sox call (synthesizes the silent audio — sox
  resolved via the same candidate-path + ExtState-cache pattern
  CLI_Resolve already uses for bwfmetaedit). A separate action from
  Generate Items, not a replacement (confirmed with the user) — this is
  much heavier (real disk I/O, external processes per group) where
  Generate Items is instant and file-free. The full sox+bwfmetaedit
  command pipeline was validated directly on this machine (real WAV
  generated, real BWF TimeReference + iXML written and read back
  correctly, including with a folder path containing a space) before
  wiring it into CLB, but the REAPER-side integration itself (item/
  track creation, D_STARTOFFS math, UI) could not be — first real
  round-trip in REAPER still pending.
- Fix: CLB.populate_recut_track (v261005.1455) could silently delete a
  NEIGHBORING move's CLB Recut item instead of only replacing its own.
  Real user report, confirmed from an RGWH Monitor dump: an Old item
  was missing even though its New counterpart existed. Root cause: the
  old-item-cleanup check was a loose "do these ranges overlap" test
  with TOL padding on both edges — since consecutive EDL events
  routinely share an exact boundary (one event's Src TC Out equals the
  next one's Src TC In), the TOL padding treated two merely-ADJACENT
  (not actually overlapping) moves' items as colliding. Replaced with
  an exact match (position AND length both within TOL) — only a prior
  run's item at the EXACT SAME range gets replaced now; a neighboring,
  merely-touching move's item is never touched.
- Change: the wrapper (hsuanice_CLB Jump Old-New TC.lua) now preserves
  the cursor's exact position within a CLB Recut item when jumping,
  instead of always landing on the paired item's own start — e.g.
  landing 3 seconds into a 10-second Old item now jumps to 3 seconds
  into its New counterpart, not just New's start. Both sides of a move
  always share the same length (CMX3600 rule — see
  CLB.populate_recut_track's own doc comment), so this is a simple
  offset carried over, no new data needed on the CLB side.
- Feature: "CLB Recut" track — Phase 1 of a planned "Jump Old/New TC"
  feature (user-requested, modeled on Matchbox's old/new jump, but
  runnable from REAPER's own Action List with a keyboard shortcut,
  which Matchbox's own version can't do — it only works from inside
  Matchbox). CLB.dme_recut_execute now also records each recut move as
  a pair of real, empty items on a shared "CLB Recut" track (created at
  the top of the track list, not hidden, if it doesn't exist yet): one
  spanning the move's OLD (Src TC) range, one spanning its NEW (Rec TC)
  range, each with the other's position written into its own item
  Notes ("CLB_JUMP:<seconds>") — real REAPER project data as the
  exchange format, no separate file/ExtState sync needed between CLB
  and the new standalone wrapper script (hsuanice_CLB Jump Old-New
  TC.lua — load it into REAPER's Action List and assign a shortcut to
  use it). Re-running DME Recut on the same moves replaces, not piles
  up, overlapping items on that track. Scoped to DME Recut only for
  Phase 1 (Compare's own Trimmed/Extended/Moved Apply isn't built yet,
  so there's no "move" to pair there) — deliberately single old<->new
  pair only, no multi-version chain (V1->V2->V3) or overlap/folder-
  track handling yet; those are planned Phase 2, after this basic
  mechanism gets validated in real use.
- Revert: removed the entire "NONE Track → B" feature (v261005.1339,
  fixed in v261005.1401, renamed B-Roll→B) — user reconsidered: wants
  the list to faithfully reflect the original EDL's own content, no
  automatic track/group rewriting. Removed CLB.none_track_to_b (and its
  ExtState key), CLB._convert_none_tracks_to_b and all its call sites
  (build_rows_from_parsed/append_rows_from_parsed/load_clb_project/the
  Options toggle), the Options popup UI, and the "B" special-casing in
  _get_track_group/DEFAULT_GROUP_NAMES/consolidate_by_group's
  _group_prefix — all back to exactly their pre-v261005.1339 state.
  NONE tracks are plain NONE again, same as before this whole feature.
v261005.1401
- Fix: "NONE Track → B" (v261005.1339) never actually ran for a loaded
  .clb project file — `load_clb_project` restores `row.track`/
  `row.group` verbatim from the saved data and never called
  `CLB._convert_none_tracks_to_b`, unlike the two EDL/XML/AAF parse
  paths. Real user report: the toggle was on, but Track Filter and the
  timeline's track rows still showed "NONE" after re-opening a saved
  project — confirmed from a live screenshot: "NONE (223)" in Track
  Filter alongside a genuinely unrelated "B (202)" group that just
  happened to already exist from the source EDL's own real "B"-prefixed
  tracks. Now also wired into `load_clb_project`. Also upgrades
  `row.group` from the stale "NONE"/empty auto-assignment to "B" on a
  converted row (leaves any other group alone — the user may have
  re-grouped it by hand on purpose).
- Change: renamed the group itself from "B-Roll" to plain "B" — user
  feedback, simpler/more concise, matching Audio/Video's own bare
  single-letter group names. `DEFAULT_GROUP_NAMES`, `_get_track_group`,
  and `consolidate_by_group`'s `_group_prefix` all updated; Consolidate
  output unchanged (still B1, B2, B3 ... with no space).
v261005.1354
- Change: Delete now behaves the same everywhere — main table AND
  timeline alike — confirmed with the user over keeping the main
  table's old "clear selected cell values" behavior. Previously only
  the timeline tagged selected clips as the "Delete" group (see
  v261005.1339); the main table's Delete still destructively blanked
  out selected cells regardless of selection shape (a single cell, a
  whole column across many rows, or Cmd+A everything). Both now tag
  every selected row's group as "Delete" and hide the Delete group, a
  single consistent "remove this from the cut, non-destructively"
  gesture either way. To clear an individual cell's text, double-click
  to edit it and delete the text directly instead.
- Change: the "Delete" group filter now defaults to hidden (visible =
  false) wherever it's seeded or freshly discovered — a fresh list
  load, or loading a project/file with Delete-tagged rows already in
  it, now starts with Delete already out of view, consistent with the
  Delete-key handler's own "hide it immediately" behavior rather than
  only hiding it on the very first keypress.
- Refactor: removed CLB.tl_focused (the window-focus flag added in
  v261005.1339 to distinguish timeline vs. table Delete presses) — no
  longer needed now that both contexts do the same thing.
v261005.1339
- Feature: timeline mini-view now supports drag box-select (multiple
  clips at once), not just single click-select — draws a live
  selection rectangle and rebuilds the selection from scratch every
  frame while dragging. This REPLACES drag-to-pan (confirmed via
  AskUserQuestion): horizontal panning moves to Shift+scroll, which
  already existed as an alternative, so nothing is lost.
- Fix: pressing Delete after selecting clip(s) in the timeline was
  wiping those events' TC/Reel/Clip Name data — the timeline reuses
  the same cell-selection state the main table's spreadsheet editing
  uses, so the existing "Delete = clear selected cells" handler fired
  on it too. Now, Delete pressed while the timeline has window focus
  instead tags the selected clips' group as "Delete" (non-destructive)
  and turns the Delete group's visibility off, so they drop out of
  view immediately — same idea as using the row context menu's "Assign
  Group: Delete," just reachable with one keypress from the timeline.
  Delete in the main table is unchanged (still clears selected cells).
- Change: unselected timeline clips now use a lighter, legible slate
  gray fill (was a near-black 0x3A3A3A that read as empty space) and
  brighter clip-name text — still clearly duller than a selected
  clip's full-brightness per-track-type color, so the two states stay
  easy to tell apart.
- Feature: new Options toggle "NONE Track → B (B-Roll)" — real EDLs
  (e.g. from Premiere) commonly leave some usable audio events with a
  literal "NONE" track field, which CLB was grouping into a dead-end
  "NONE" group that Consolidate doesn't meaningfully bin-pack. When on,
  those rows get rewritten to track "B" on load (and immediately for
  already-loaded rows when switched on) — groups as "B-Roll" and
  Consolidate names them B1, B2, B3 ..., parallel to Audio → A1, A2 ...
  "B-Roll" added to the default group seed list and to
  _get_track_group's prefix rules (B* → B-Roll). Does not revert
  already-converted rows when switched back off.
v261005.1309
- Feature: "Clear List" and "Clear Audio" moved to the top of the left
  sidebar as their own red "danger" color group (CLB.BTN_GROUP_COLORS.
  danger) — kept visually separate from the other action groups since
  they're destructive resets, not routine workflow steps.
- Change: the status text ("Events: N | Showing: N") and the Sources/
  Tracks/Filters/Audio panel-toggle buttons moved from the end of row 1
  to row 2, right after Search — row 1 now ends with Options right
  after the Load List/Export EDL/Load Audio group.
v261005.1248
- Feature: all "action" buttons (Compare, DME Recut, Shift Range,
  Calibrate TC, Generate Items, Conform All, Conform Sel, Scene Cuts,
  Match All, Remove Dups, Consolidate) moved out of the top toolbar
  rows into a new vertical left sidebar (CLB.draw_left_sidebar) —
  user's own workflow: the list itself only needs a glance most of the
  time, but these buttons get clicked constantly while flipping back
  and forth checking REAPER's own window, so they need to stay
  reachable even when this window is narrow and parked to one side of
  the screen. The non-action toolbar (Save/Open/Clear List, Load
  List/Load Audio, FPS, Search, Sources/Tracks/Filters/Audio toggles,
  Columns, Fit Widths, Timeline, Apply Clip Name Format, Options)
  deliberately stays at the top — confirmed via AskUserQuestion.
- Change: Export EDL moved up next to Load List... in the top toolbar
  (both I/O, per the existing color grouping) instead of living among
  the relocated action buttons.
v261005.1235
- Feature: main toolbar buttons now color-coded by function group
  (user-requested, confirmed via AskUserQuestion), via a new
  CLB.push_btn_color/pop_btn_color helper (CLB.BTN_GROUP_COLORS) —
  purely visual, no behavior change. Five groups: list editing/cleanup
  (teal — Remove Dups, Consolidate), input/output (blue — Load List,
  Load Audio, Export EDL), position correction (purple — Shift Range,
  Calibrate TC), recut/reconform (orange — Compare, DME Recut), and
  build real content from the list (green — Generate Items, Conform
  All, Conform Sel, Scene Cuts, Match All). Anything not wrapped in one
  of these keeps the theme's default button color.
v261005.1229
- Change: "Load EDL...", "Load XML...", "Load AAF...", "Load
  Subtitle..." (4 separate toolbar buttons) consolidated into one
  "Load List..." button opening a popup menu — same pattern as the
  existing Options popup. "Load Audio..." stays as its own separate
  button (a genuinely different kind of load — a folder of audio
  files, not an EDL/XML/AAF/subtitle list).
- Change: Track Format and Clip Name Format template fields moved out
  of the toolbar rows into a new "Formats:" section inside the Options
  popup — both are set once and rarely touched again, so keeping them
  permanently visible in the toolbar cost more space than it was worth.
  Clip Name Format's "Apply" action button stays where it was (near the
  Audio table, where it's contextually useful right after matching),
  now reading the template from Options instead of its own inline
  field; relabeled "Apply Clip Name Format" since the field next to it
  is gone.
v261005.1205
- Change: "Shift Range..." no longer creates/updates a "CLB: OLD"/"CLB:
  NEW" region marking the shifted span — user feedback right after
  v261005.1157 shipped it. Now scoped to an explicit Razor Edit/Time
  Selection range the user already made themselves, so an extra auto-
  generated region restating that same span added no information.
v261005.1157
- Feature: "Shift Tracks..." rebuilt as "Shift Range..." — scoped to a
  Razor Edit selection (priority) or a Time Selection + REAPER-selected
  track(s), instead of unconditionally shifting an entire track. Items
  are split at the range edges so only the portion actually inside the
  range moves (`CLB.cut_shift_range`, a new shared primitive — see
  below). Requires an explicit range now; refuses to run on "just
  select tracks and click" alone, confirmed over falling back to the
  old whole-track behavior, since a silent scope change could move far
  more than intended.
- Feature: project markers AND regions inside the same time span now
  move together with the items (`CLB.shift_markers_regions`) — a marker
  moves if its own position falls in range; a region moves only if BOTH
  its start and end fall fully inside (a region straddling the edge is
  left alone rather than guessed at). Repositions each one IN PLACE via
  `SetProjectMarker4` (same ID) rather than deleting and recreating —
  REAPER's ReaScript API has no getter/setter for the newer marker/
  region ruler "lane" assignment, but since nothing is ever deleted,
  lane (and anything else ReaScript can't see) is never touched and
  stays exactly as REAPER already has it.
- Refactor: extracted `CLB.cut_shift_range(track, range_start,
  range_end, delta, TOL)` — isolate whatever overlaps a range on a
  track (splitting at the edges, locked items included) and move it by
  a constant delta — as a shared primitive. DME Recut's Cut mode
  (`CLB.dme_recut_execute`) now delegates to it too (delta = mv.rec_in
  - mv.src_in per move) instead of its own near-identical inline loop:
  the two features turned out to be the exact same mechanical
  operation once Shift Range needed per-track range-splitting too, not
  just a hypothetical future refactor (see the open question noted in
  v261005.1129). A future Compare Trimmed/Extended/Moved Apply could
  reuse the same primitive once content-identity matching picks the
  target range.
- Change: `CMP.offset_selected_tracks` renamed to `CMP.shift_range`
  (only call sites were internal to this file — the toolbar "Shift
  Range..." button and Compare's "Modes..." > Offset Old). No longer
  auto-disables the matching side's "virtual offset" checkbox after a
  shift — a scoped shift may only bake in some Compare dedup entries,
  not all of them like the old whole-track version always did, so
  deciding whether the virtual offset is now redundant is left to the
  user instead of guessed.
v261005.1129
- Refactor: renamed the internal "Mode A/B/C" naming throughout the
  live code (variables, function doc comments, match-result tags) to
  the same descriptive names the UI has used since v260917.2117
  ("Matched Item", "Length Match", "Range Clear") — no more bare
  letters anywhere, including internally. `CLB.apply_mode_a/c/b` →
  `CLB.apply_mode_matched/length/range`; `m.mode`/`c.match.kind` values
  "A"/"C"/"B" → "matched"/"length"/"range" (and "auto_a"/"auto_c" →
  "auto_matched"/"auto_length"); `mode_a_count`/`mode_c_count`/
  `mode_b_count` → `matched_count`/`length_count`/`range_count`. The
  ExtState keys used to persist these toggles ("apply_mode_a"/"_c"/"_b")
  were deliberately NOT renamed — purely internal plumbing, invisible
  to the user, and changing them would silently reset everyone's saved
  Modes... toggle state on next load. Dated @changelog entries from
  before this pass keep their original "Mode A/B/C" wording as a
  historical record, not live documentation — only current, non-dated
  code/comments were renamed. No behavior change.
v261005.1114
- Fix: DME Recut's new "Cut" mode left the result incomplete/patchy —
  real user report, first test: output looked like some events moved
  and others silently didn't, no error shown. Root cause: Cut mode's
  inner scan iterated `reaper.GetTrackMediaItem(track, i)` by index
  (backward, 0..n-1 captured once per move) while ALSO calling
  `SplitMediaItem`/changing `D_POSITION` on the very track being
  scanned — REAPER's own per-track item index order isn't guaranteed
  stable once items are split/repositioned mid-scan, so later indices
  in the same backward sweep could silently point at the wrong item or
  get skipped. This is the exact same class of bug `CMP.
  offset_selected_tracks` ("Shift Tracks") already hit and fixed by
  snapshotting item pointers first (see its own history). Fixed the
  same way here: each move now snapshots its selected tracks' item
  POINTERS into a plain Lua array immediately before scanning (fresh
  per move, so it still sees every earlier move's real result — unlike
  "Copy" mode's single upfront-for-the-whole-run snapshot), then
  iterates that array instead of live indices. Untested against a real
  session this session (no REAPER runtime access) — still needs the
  user's next real round-trip to confirm.
v261004.2048
- Feature: "DME Recut" now opens a "DME Recut Settings" dialog (modeled
  on Matchbox/Ediload's own "Run Reconform" dialog, scoped to the
  minimum viable for v1) instead of running immediately: a Copy/Cut mode
  choice and a Delete/Insert-marker on/off toggle, both remembered
  between runs (CLB.dme_recut_mode/dme_recut_markers, persisted via
  save_prefs/load_prefs same as every other toolbar setting). The
  existing validation + duplicate-Src-TC-range warning now run up front
  in CLB.dme_recut_prepare() and show inside the dialog itself (not a
  separate confirm box); "Run It" calls the new CLB.dme_recut_execute(),
  "Cancel" discards the pending analysis.
- Feature: "Cut" mode added as an alternative to the existing Copy-only
  behavior — really splits/repositions the original items (matching
  Matchbox/Ediload's own Cut/Paste mode) instead of duplicating from
  them. Implemented as a live per-move track scan (not a snapshot, as
  Copy mode uses): a moved chunk's position changes to its Rec TC slot,
  so it naturally drops out of a later move's Src TC-range scan on its
  own, the same safety property Copy mode gets from snapshotting up
  front. Copy stays the default (safer — never touches V1's real
  content).
v261004.1929
- Feature: "DME Recut" now adds Delete/Insert project markers describing
  what happened at each gap — the point of DME Recut mode (see its doc
  comment): Src TC already IS V1's real position for printed-to-pitch
  stems, so comparing consecutive events' own Src TC against their Rec
  TC (no second EDL/Compare needed) tells you directly where content was
  dropped or added. Walking the recut events in their new (Rec) order: a
  Rec TC gap with no matching Src TC gap is new content with no V1
  source ("Insert For <duration>", green); a Src TC gap with no matching
  Rec TC gap is V1 content that didn't make it into V2 ("Delete For
  <duration>", red — reusing CMP.TYPE_COLOR for visual consistency with
  Analyze & Match). Modeled on Matchbox's (Cargo Cult) own marker
  vocabulary, confirmed from a real Matchbox session + its Markers list
  view — deliberately not its bare "x"/">"/"<" edge markers (clear to
  Matchbox's own users, opaque to anyone else, and tellingly absent from
  its own categorized Markers list) or its Trim/Extend/Reorder types
  (those only arise comparing TWO different EDLs' clip selections, not
  within one EDL's own Src-vs-Rec — see Trimmed/Extended/Moved in
  hsuanice_CLB Compare Engine.lua for where those belong). Verified the
  gap math against the real ADR sequence from the dup-overlap bug
  report: correctly finds "Insert For 00:00:03:04" and "Delete For
  00:00:04:22" at the two real gaps.
- Change: default group set is now Video, Audio, Dialog, Music, Effects,
  Location, ADR, Delete (was Video, Audio, ADR, Location, Effects,
  Music, Delete) — user's real DME workflow needs Dialog/Music/Effects
  grouped together in that order so Consolidate (bin-pack by group into
  non-overlapping tracks) correctly separates DME stems that the raw EDL
  otherwise places on one generic track (e.g. "AA") with no real
  separation — confirmed via a real session where DX/ADR/FX/MU rows all
  showed Track=AA, needing Consolidate-by-group to actually split them.
  ADR kept (not removed) for productions that still track it separately.
v261004.1106
- Feature: "DME Recut" now pre-flight-checks for overlapping Src TC
  ranges before creating anything. Real bug report: recutting a filtered
  list that mixed DX + ADR rows duplicated every real item (9 → 18 on
  the affected track, confirmed via RGWH Monitor) — root cause is that
  DX/ADR/FX/MU all share ONE embedded timecode baseline (see this
  function's own doc comment), so the exact same real cut point shows up
  as a separate event per stem type whenever more than one stem's rows
  are processed together; the user confirmed even Matchbox (Cargo Cult)
  shows this same duplication (the identical match listed 4x, once per
  stem, in its own Matches view) on the same kind of list. Rather than
  guessing which duplicate is "right" and silently dropping/merging the
  rest (see feedback_warn_dont_guess_ambiguous_heuristics), this now
  detects moves whose Src TC ranges overlap/duplicate each other and
  lists them (grouped, with sample clip names) in the confirmation
  dialog and the completion report — items are still created if the user
  confirms, but now with clear warning of where duplicate copies are
  likely. Verified the detection against the real DX/ADR data from the
  bug report (3 overlapping pairs, all found).
v261004.0136
- Feature: "Shift Tracks..." — the same real-item-moving action
  Compare's "Offset Old" already had (CMP.offset_selected_tracks, type
  a number of hours, click, moves every unlocked item on the Reaper-
  selected track(s)), now exposed as its own toolbar button too. DME
  Recut doesn't use Compare mode at all, so that existing action was
  unreachable from it — e.g. to stage V1's real content out of the way
  before a DME Recut run. No new logic — delegates straight to the
  existing function; the Compare-only "Offset Old" checkbox (a virtual
  offset for Analyze & Match's matching math) stays where it was, since
  it has no meaning outside Compare.
v261004.0125
- Change: "DME Recut" now COPIES instead of cutting/moving — user
  feedback: the original v261003.2338 implementation split and
  repositioned the real items it found, which consumed/altered V1's
  content at its Src TC position, breaking the "keep the old pristine"
  principle the rest of this pipeline already follows (see
  CMP.offset_selected_tracks). Now creates a brand new item at the Rec
  TC position whose take points at the SAME underlying source media as
  whatever occupied the Src TC range, with D_STARTOFFS adjusted to play
  the exact portion that was there (handles partial item overlaps
  correctly too) — the original items are only ever read, never split or
  moved. Verified the position/source-offset math for both a fully-
  contained and a partial-overlap case.
v261004.0100
- Fix: Calibrate TC popup crashed on open ("'reaper.ImGui_Checkbox'
  argument 1: expected ImGui_Context*") — v261004.0035's new axis_row()
  helper dropped the `ctx` argument from its ImGui_Checkbox call. Fixed.
v261004.0035
- Feature: "Calibrate TC (Anchor)" now supports TWO independent axes per
  source — "New (Rec TC)" (the original, used everywhere outside DME
  Recut) and "Old (Src TC)" (DME Recut mode only, where Src TC is
  repurposed as V1's real Reaper timeline position rather than a
  position inside an audio source file). Real case that prompted this:
  V1's actual content staged at +10h, a separate V2 reference at +20h,
  and the EDL's raw Rec TC already matching the real target (V3)
  position — DME Recut needed a way to tell it "look +10h away from the
  raw Src TC," without touching the Rec TC side at all. The popup now
  has an axis selector (radio buttons) above Set Anchor/Target-TC-Apply,
  and lists both axes' status per source. CLB.calibrate_tc_via_anchor/
  CLB.calibrate_tc_to_target take an optional axis parameter ("rec"
  default, or "src") instead of being duplicated per axis. New
  CLB.src_tc_seconds/CLB.calibrated_src_tc_string mirror the existing
  Rec-axis helpers; Src TC table display and click-to-jump now honor
  this calibration too (previously Src TC never read any calibration at
  all, correctly so before DME Recut gave it a second meaning). Persisted
  per-source in the .clb format (S| line gains 3 more trailing fields;
  old .clb files without them load as "no Src calibration," unaffected).
  Verified the combined math against the real example: with V1 staged at
  +10h, DME Recut now correctly looks for content at the staged position
  and moves it to the real target, combining the +10h removal with the
  scene's own +8.5s picture-lock shift correctly.
v261003.2338
- Feature: "DME Recut" — a new, Compare-free recut tool for a specific
  real workflow: an editor cuts a V2 edit from V1's printed-to-pitch DME
  stems (DX/ADR/FX/MU, each bounced with the SAME embedded start
  timecode baked across the whole reel) and exports an EDL. Because of
  that convention, each event's Src TC is already V1's real Reaper
  timeline position — a different sense of "Src TC" than the rest of
  CLB uses (position inside an audio source file) — and Rec TC is V2's
  target position, so the single EDL already IS the old->new mapping;
  no second EDL or Compare step needed. Also confirmed: per CMX3600
  format rules a plain cut event always has equal Src/Rec duration (a
  real trim/extend only ever shows up as separate adjacent events, or
  when comparing Src TC across TWO different EDLs — not within one),
  so this is purely a position MOVE, never a trim/extend.
  New "DME Recut..." toolbar button: select the Reaper track(s) to
  recut, filter the loaded list down to the relevant rows first (e.g.
  search "DX"), click — for every visible event whose Src TC position
  differs from its Rec TC position, whatever currently occupies that
  Src TC range on the selected track(s) is split out and shifted
  (position only) to the Rec TC range. No identity/content matching,
  same "just the range, not which item" spirit as Mode B (Range Clear).
  Verified the move/skip classification against the real example that
  prompted this (a scene edited upstream causing matching +8.5s shifts
  across both the DX and ADR stems' corresponding events).
v260923.2158
- Change: reverted v260923.2148's 2-minute duration cutoff for Scene
  Cuts — correctly flagged by the user as unsafe: some real Taiwanese
  films legitimately use long takes running 10+ minutes, which a fixed
  duration limit would silently exclude from Scene Cuts entirely (worse
  than the overlap it was meant to prevent — a false negative that's
  invisible, vs. a false positive that's at least visible as an
  overlap). Replaced with detect-and-warn: "Create Scene Cut Track"
  still creates every item as before (no filtering), but now scans the
  merged result for cross-scene overlaps and surfaces them —
  grouped by the "wide" item causing each cluster, not listed pairwise
  (the real shape of this problem is one long item overlapping many
  real scenes, which would otherwise mean one dialog line per real
  scene — confirmed 154 pairwise lines collapsing to 4 readable summary
  lines on the same real session). The confirmation dialog lists each
  cluster (which scene, its range, how many/which others it overlaps)
  before creating anything; after creation, the culprit items themselves
  are colored red and take-name-suffixed " ⚠ overlap" directly on the
  Scene Cuts track, so the user can find and resolve them with full
  editorial judgement in Reaper — the tool no longer tries to guess
  which is real footage and which isn't.
v260923.2148
- Fix: "Create Scene Cut Track" still produced overlapping items (one
  per reel) after v260923.2131's fix — root cause was different: an
  un-flattened video track carrying a single whole-reel reference/
  pic-lock clip (real case: "S.O. ... PICLOCK R1 for AAF.mov" spanning
  the entire ~28-minute reel on V1, alongside the real per-scene cut on
  V2) still carries SOME scene value in its own metadata, so it got
  collected like any other scene occurrence — and being the length of
  the whole reel, swallowed every real scene's interval into one giant
  merged overlap. Fixed by skipping any Video row longer than 2 minutes
  from scene detection entirely (new REF_CLIP_MAX_DUR_SEC), logged to
  console when it fires. Threshold chosen from real data: real shots had
  a 3.1s median / 27s p99 duration; the reference clips were
  1200-1900s — 2 minutes sits comfortably above the former, well below
  the latter. Confirmed: scene "7" (previously merged into a bogus
  1680s span) now correctly spans its real 70s range.
v260923.2131
- Fix: "Create Scene Cut Track" produced overlapping items when a
  session had non-scene technical clips on a Video track (a leader like
  "Universal Counting Leader", raw camera-roll dumps like
  "DVA001_070_260414.MTS") whose row.scene was correctly left empty by
  Match All (it tried and found no scene from overlapping audio, since
  these genuinely aren't scenes) — get_scene_id's clip_name-first-token
  fallback then guessed a fake "scene" from the filename anyway
  ("Universal", "DVA001"), which occupied the same time range as real
  scenes and overlapped them once dumped onto the shared output track.
  Confirmed via a real 3846-row session: the old logic produced 174
  "scenes" (mostly junk); the fix produces 33, all real. Fallback to
  clip_name now only applies when NO Video row anywhere in the list has
  row.scene populated at all (Match All hasn't run this session, or the
  source has no Scene column) — once any row.scene exists, an empty one
  elsewhere is trusted as Match All's own confirmed "no scene here",
  not re-guessed. (Considered filtering fallback results by pattern —
  e.g. digits-only — instead, but rejected: this production's real
  scene labels include alpha-prefixed ones like "X1", which a pattern
  filter would have wrongly excluded too.)
v260923.2052
- Fix: the Recut Group Details "Assign Selected Reaper Item"/"Clear
  Match" buttons (added v260923.1900) were invisible — CMP.draw_group_
  details_table passed its ENTIRE height budget straight to BeginTable,
  so the table claimed all available space and the buttons, laid out
  right after it, ended up below the window's visible bounds. Now
  reserves room for the toolbar (one text line + one button row) before
  sizing the table, so both are visible together.
v260923.2026
- Fix: loading a .clb file into Compare (Load Old.../Load New...) ignored
  any "Calibrate TC (Anchor)" correction saved on its sources — CMP.
  load_side's .clb branch read data.rows but never looked at data.sources
  at all, so Compare silently ran on the pre-calibration Rec TC even
  though the main table showed (and Generate Items/Conform would have
  used) the corrected values. Now bakes each row's source-level
  calibration into rec_tc_in/rec_tc_out at load time, since Compare's
  old/new entries are a disconnected snapshot with no ongoing link back
  to CLB.edl_sources once loaded (unlike the main list's virtual/
  toggleable calibration). Confirmed with a real calibrated .clb.
v260923.1900
- Feature: manual match-correction UI (Recut Group Details' "Matched
  Item" column) — pipeline step 4 of the Recut/Reconform TODO. Click a
  row's Matched Item cell to select it, select the correct item in
  Reaper, click "Assign Selected Reaper Item" to override whatever
  Analyze & Match either missed or got wrong; "Clear Match" removes it
  (and its coloring/take marker). Not offered for Deleted groups —
  Deleted intentionally clears every overlapping item, not one specific
  match (see CMP.assign_group_detail_match's doc comment).
- CMP.analyze_and_match_session now persists a single definitive match on
  each candidate (c.match = {item, kind}) whenever it's unambiguous
  (Mode A's own pick, or exactly one Mode C hit) — previously it only
  ever wrote to the Reaper item's own color/take-marker, with no queryable
  record the script itself could show or let the user correct.
- Refactor: extracted CMP.mark_matched_item/CMP.unmark_matched_item from
  analyze_and_match_session's inline set_take_marker, now shared with the
  new manual-assign path so both leave identical visual feedback.
- Requires hsuanice_CLB Compare Engine.lua v0.3.1+ (M.group() now stamps
  item.__group = g on every recut candidate, so this file can find a
  candidate's type/label/color without threading the parent group
  through separately).
- Scope note: match state (c.match/c.__group) lives only on the current
  in-memory Compare result — it's rebuilt fresh (lost) if you reload a
  .clbcmp Compare Session or re-run Compare, same as Analyze & Match's
  auto-matches already were. The item's own color/take marker, being
  real Reaper project data, still persists regardless.
v260923.1448
- Feature: "Calibrate TC (Anchor)" popup gains a second calibration
  method — no Reaper item needed at all. Select one event row and type
  the Rec TC In it SHOULD be (e.g. a Universal Counting Leader that's
  always placed 2 seconds before each hour mark: 00:59:58:00,
  01:59:58:00, ...); the delta is derived from the difference between
  that target and the row's current raw Rec TC In (CLB.
  calibrate_tc_to_target). Same per-source storage/behavior as Set
  Anchor — whichever row you use picks the source, re-running either
  method replaces that source's delta outright.
- Feature: the new target-TC input (and the main Search box, which had
  identical inline logic — now shares this) accepts either "HH:MM:SS:FF"
  or 8 bare digits with no colons (e.g. "00595800"), via new
  CLB.normalize_tc_input.
v260923.1345
- Fix: an .edl reel split across several files (CMX3600's 4-audio-track-
  per-file limit means a full channel set commonly exports as A1-2/A3-4/
  .../Video, one reel spread across N files sitting together in a reel
  folder — e.g. "R01/POINT_DIR_v8_R1_*.edl" x7) was being registered as N
  SEPARATE sources, one per file, so "Calibrate TC (Anchor)" (per-source
  since v260923.1330) needed one Set Anchor per file instead of once for
  the whole reel. _register_source now folds multiple .edl files sharing
  the same parent FOLDER into one source entry (name becomes "R01 (7
  files)"), so Set Anchor on any one of them calibrates the whole reel.
  Confirmed this holds even when selecting many reels' files together in
  one giant multi-select (e.g. R01 through R05 in a single "Load EDL..."
  dialog, the user's actual workflow) — grouping is per-folder, not
  per-load-action, so R01/R02/.../R05 still end up as separate sources.
  XML/AAF are unaffected (always one file per reel already; the
  4-track-per-file limit is EDL-specific).
v260923.1330
- Change: "Calibrate TC (Anchor)" (added in v260923.1303) is now PER
  SOURCE instead of one global correction — the common real case is
  loading several reels/episodes at once, each exported by the editor
  starting at 0 but placed by audio post at its own hour slot on the
  session timeline (00595800, 01595800, 02595800...), which a single
  delta can't correct. Calibration state moved from global CLB fields to
  CLB.edl_sources[i].tc_calib_enabled/tc_calib_delta_sec/tc_calib_note;
  CLB.rec_tc_seconds/CLB.calibrated_rec_tc_string now take the row (to
  look up its source via row.__source_idx) alongside the TC string.
  "Set Anchor..." still just needs one selected row + one selected
  Reaper item — it calibrates whichever source that row belongs to, so
  running it once per loaded reel handles the whole multi-source case.
  The toolbar popup now lists every loaded source with its own
  Enabled/offset/Clear, instead of one global row. Persisted per-source
  in the .clb project format (S| line gains 3 fields; old .clb files
  without them load as "no calibration", unaffected).
v260923.1303
- Feature: "Calibrate TC (Anchor)" — a virtual, toggleable Rec TC
  correction for the whole currently-loaded list, computed from one
  user-confirmed event<->item pair instead of a typed round number of
  hours (the "Set Anchor" idea from the paused Recut TODO, generalized
  to work on any loaded list, not just a Compare/recut result). Select
  one event row + one Reaper item that IS that event's real content,
  click "Set Anchor..." (new "Calibrate TC..." button/popup in the main
  toolbar) — the script verifies the item's length matches the row's Rec
  duration (refuses on mismatch, since that usually means the wrong item
  was picked), then derives delta = item's real position - event's
  expected position. Never rewrites row.rec_tc_in/rec_tc_out — applied
  on top wherever a Rec TC becomes a real Reaper timeline position or a
  table display value (REC_IN/REC_OUT columns, click-to-jump, Generate
  Items, Conform Matched Items, Create Scene Cut Track), so it can be
  switched off at any time to see the untouched original list again.
  Inline cell editing of Rec TC always operates on the true raw value
  regardless of calibration state (new CLB.get_cell_edit_text), so
  editing a cell never accidentally bakes the calibration delta into the
  stored data. Persisted across sessions (tc_calib_enabled/delta_sec).
v260923.1154
- Docs: expanded the header's "Supported formats" section with real,
  confirmed software/version info gathered from a 39-file real-project
  test corpus (Tools/format_tests/) — Adobe Premiere Pro confirmed for
  both AAF and XML export paths (versions 15.0.0/25.6.4/26.3.0 for AAF);
  FCP7/Resolve XMEML noted as same-parser-path but not yet real-sample
  tested. No behavior change; internal reference only (not surfaced in
  the UI — ${format} still shows the collapsed "XML"/"EDL"/"AAF" label).
- Fix (Tools/otio_to_clb.py, not this file): _detect_xml_format() only
  sniffed the first 2KB of the file, missing Premiere's real signature
  (authoringApp="PremierePro") which sits much deeper in real exports —
  was silently mislabeling every real Premiere XML as FCP7_XML internally
  (CLB.loaded_format). Now scans the whole file in chunks. See that
  file's own changelog for details.

v260922.1854
- Feature: the main event list's Search box now auto-detects an 8-digit
  timecode typed without colons (e.g. "01102203") and also matches it
  against "01:10:22:03" — no need to type the colons to find a Src/Rec
  TC In/Out. Tooltip on the search box explains it.

v260922.1604
- Fix: "Generate Items" reused an existing track whenever its computed
  track name matched one already in the project, so a second run landed
  its items on top of whatever the first run already placed there.
  Now always inserts a fresh track per run, matching what Conform All/
  Sel already did (see its own "always create a new track" comment).

v260922.1546
- Feature: Generate Items, Conform All/Sel, and Match All now show a
  progress bar (same yellow style as loading EDL/XML) instead of
  freezing Reaper for the whole run — these are the three most likely to
  actually be slow (Generate/Conform make heavy Reaper API calls per
  row; Match All's fuzzy scan is O(rows × audio files), and this tool
  routinely sees thousands of both). Built on a new generic chunked-
  batch-job runner (CLB.process_batch_job, modeled on the existing Load
  Audio metadata batch loader): each processes a bounded chunk of rows
  per frame instead of one giant synchronous loop, so the progress bar
  actually redraws between chunks. Clicking any of these three while
  another is still running now shows a message instead of silently
  corrupting the in-progress one. Remove Dups / Consolidate / Scene Cuts
  were left as plain synchronous loops — they're pure in-memory Lua with
  no Reaper API calls per row, fast enough in practice that a progress
  bar would likely just flash and disappear.

v260919.0106
- Fix: "Scene Cuts" never actually used Match All's audio-inferred
  row.scene — it preferred row.clip_name whenever clip_name was merely
  non-empty (true for almost every row, even filler/"Empty" items with
  no real scene in the name), so the inferred value sat there unused.
  Now prefers row.scene when it's set (the authoritative, already-
  resolved value) and only falls back to parsing clip_name when
  row.scene is empty.
- Fix: scene numbers differing only by leading zeros (e.g. "4" and "04")
  were treated as different scenes, splitting what should have been one
  Scene Cuts segment. Now normalised the same way track/reel/group names
  already are elsewhere in the tool, so "4" and "04" group together.

v260919.0052
- Change: moved the audio-based Scene/Take inference from "Scene Cuts"
  into Match All, per feedback — it now runs for every Video row whose
  Scene/Take is empty, backfilling row.scene/row.take verbatim (not
  split) from the majority Scene/Take among overlapping Audio rows.
  Inferred rows are flagged (row.__scene_inferred), colored orange on
  the Scene/Take columns (with a tooltip explaining why, mirroring the
  Fallback convention), and noted in the Notes column. Never overwrites
  an existing value. The console summary reports how many were
  inferred.
- Change: "Scene Cuts" no longer does its own audio scanning/inference
  or (inferred) labeling — it now simply reads row.scene as a fallback
  when the clip name itself has no scene, and always strips down to
  just the leading scene token for grouping (e.g. "P1" out of a
  Match-All-backfilled "P1-1"), regardless of source.

v260919.0033
- Fix: audio-inferred scenes were showing the full "Scene-Shot" value
  from the audio's Scene metadata (e.g. "P1-1", "P1-WT", "P2-13") instead
  of just the Scene half ("P1", "P2") — fragmenting what should have been
  one Scene Cuts segment per scene. Now splits the audio Scene field into
  Scene + Shot, votes/groups on Scene only, and separately tracks a
  representative Shot (nested majority vote among the winning scene's
  own audio entries).
- Feature: that inference now also syncs back onto the actual Video row
  — not just the transient Scene Cuts item — filling row.scene (from the
  inferred Scene) and row.take (from the inferred Shot) whenever those
  fields are currently empty, so it shows up in the main table's Scene/
  Take columns and persists. Never overwrites existing values; applies
  as soon as Scene Cuts runs, independent of whether you go on to create
  the track. The confirm dialog reports how many rows were backfilled.

v260919.0024
- Feature: "Scene Cuts" now infers a scene for video clips whose own clip
  name has no scene info at all, from whichever scene the majority of
  overlapping audio events (row.scene — parsed from the audio clip name
  or backfilled from matched BWF metadata by Match All) agree on; a
  handful of inserts/cutaways from a different scene in the same range
  are outvoted and ignored. Inferred items are colored orange with
  "(inferred)" appended to the take name — same "double check this one"
  visual language as Fallback audio matches — since it's a majority-vote
  guess, not read directly off the clip. Requires Match All to have been
  run first so audio rows actually have row.scene populated; the confirm
  and completion dialogs both report how many items were inferred.

v260919.0010
- Fix: "Scene Cuts" produced overlapping, fragmented items for the same
  scene — the algorithm walked rows sequentially (essentially detecting
  picture CUTS, not real scene continuity), so a second video track
  (B-roll/insert coverage) carrying the same scene number over an
  overlapping time range produced its own separate, shorter same-scene
  item that visually overlapped the main one. Now collects every Video-
  row occurrence of each scene from ALL video tracks first, then merges
  overlapping-or-touching (within ~2 frames, to bridge a cut/transition
  gap) intervals per scene into one continuous item — a scene number
  that genuinely recurs later with a real gap still gets its own item,
  but continuous coverage of the same scene across multiple tracks now
  collapses into a single non-overlapping segment as expected.

v260919.0002
- Change: "Scene Cuts" now groups by just the FIRST clip-name token (e.g.
  "06" in "06_01_T03_A - Merged") instead of "scene_shot" combined
  ("06_01") — for episodic naming, the shot number right after the scene
  number isn't itself a scene boundary, so shots 06_01/06_02/06_03 etc.
  should all merge into one Scene Cuts segment rather than each starting
  a new one. Kept separate from Strategy 6's audio Scene+Take matching,
  which still needs the fuller "scene_shot" to avoid matching audio to
  the wrong shot within a scene.

v260918.2358
- Fix: "Scene Cuts" used its own crude, hardcoded scene-ID parser instead
  of the same robust ones Strategy 6 (audio Scene+Take matching) already
  uses — it required clip names to split into exactly 4+ underscore
  tokens with the 4th starting with "T", so real video clips like
  "06_01_T03_A - Merged" (take lands at token 3, not 4, once the " -
  Merged" suffix and trailing channel letter are accounted for) were
  silently skipped, while unrelated audio-recorder filenames like
  "BK9526_56B_..._t1..." happened to satisfy that same narrow check and
  got wrongly treated as scenes. Now reuses the shared scene/take parsers
  and only scans Video-track rows (audio clip names aren't scene/shot/
  take names at all, so they were never meant to be scanned here).

v260918.2144
- Fix: sorting the main table by "Matched File" couldn't actually group
  Scene+Take fallback matches apart from Tape+TC ones (or from real
  matches), even though the header showed a sort arrow and appeared to
  do something — the "[Scene+Take] "/"[Tape+TC] " prefix added in
  v260918.2133 was only applied at draw time, never part of the actual
  value being compared, so identical-looking "(N)" candidate-count
  strings just kept their original row order. The prefix now lives in
  get_cell_text() itself (single source of truth for both display and
  sort), so sorting by Matched File clusters Scene+Take, Tape+TC, and
  plain matches into separate blocks as expected — e.g. to bulk-assign
  all Scene+Take rows to their own Group.

v260918.2133
- Fix: Strategy 6 (normalised Scene+Take) audio matches were reported as
  plain "Found"/"Multiple" — identical to an actual filename- or TC-
  verified match — even though Strategy 6 never checks source TC at all
  (it's the last-resort strategy, tried only when Strategies 1-5,
  including the Tape+TC fallback, all found nothing). Confirmed by a real
  case: an EDL row matched several audio files sharing its Scene+Take
  despite their embedded Source TC being hours off from the row's Src TC
  In. Strategy 6 matches are now flagged "Fallback" (same orange
  highlighting as the existing Tape+TC fallback) with their own "[Scene+
  Take]" Matched File label and tooltip explaining source TC was never
  checked, instead of silently looking identical to a solid match. The
  matching-complete console summary now also breaks fallback counts down
  by which kind.

v260918.1740
- Fix: Audio List / conform matching sorted files strictly alphabetically
  (A1, A10, A11, A12, A2, A3...), not naturally — confirmed by a real
  folder of PN_AAP.A2–A12.WAV files listing out of order. Now uses the
  same natural-sort helper already used for track/reel/group names (A1,
  A2, A3...A10, A11, A12) in three places: scanning an audio folder fresh,
  loading a previously-saved audio metadata cache (so an old cache from
  before this fix still comes back in the right order), and the Audio
  table's own column-header sort when sorting by a text column.

v260918.1534
- Feature: "Shift Selected Tracks Now" now adds a region ("CLB: OLD",
  gray) spanning the full range of the just-shifted items, so the offset
  stretch is obviously labeled on the ruler/timeline at a glance.
  Re-running the shift replaces the same-named region with a fresh one
  covering the new bounds, instead of piling up duplicates.

v260918.1527
- Feature: "Shift Selected Tracks Now" now bakes the same shift into the
  loaded Compare result's Old Rec TC (cr.old_dedup), not just the real
  Reaper items — Recut Group Details, the graphical Compare timeline, and
  every click-to-jump were still reading the pre-shift position, which no
  longer matched where the item actually sits after a real shift. "Show
  as Table"'s cached rows are rebuilt too if currently viewing them. The
  matching-only "Offset Old" checkbox (Modes... popup) is then turned off
  automatically, since the shift is now baked directly into the data —
  leaving it on would double-count it in later Analyze & Match / Apply
  runs.

v260918.1521
- Fix: "Shift Selected Tracks Now" could scatter items across several
  different landing spots instead of a uniform +Nh shift, and not every
  item actually moved — confirmed on a real 526-item run via before/after
  RGWH Monitor track dumps (a touching run of items fragmented into
  isolated items at irregular gaps after shifting). Cause: the shift loop
  re-read GetTrackMediaItem(track, i) by index on every iteration while
  moving items — Reaper keeps each track's item list sorted by position,
  so moving item i re-sorts the list the remaining indices point into,
  silently skipping some items and reprocessing others. Fixed by
  snapshotting every item pointer into a fixed list before moving
  anything, then looping over that snapshot.
- Change: locked items are no longer skipped — each is temporarily
  unlocked, shifted, then re-locked to its original state, so a locked
  item no longer gets left behind when the rest of the track moves out
  of the way.

v260918.1454
- Feature: "Shift Selected Tracks Now" now confirms exactly how many
  items it moved ("Shifted N item(s) by +Nh on N track(s)") after
  finishing, instead of finishing silently — the shift itself was never
  limited to a subset (it always walks every item on every selected
  track, skipping only locked ones), but with no completion feedback a
  docked overview panel bound to a stale time selection could look like
  proof that fewer items moved than expected.

v260918.1450
- Fix: Reconform Offset controls in the Modes popup were cramped at
  larger font scales (e.g. 125%) — the hours field, its "h" label, and
  the "Shift Selected Tracks Now" button all ran into each other on one
  line ("10 - + h Shift Selected Tracks Now"). Widened the hours field,
  replaced the glued-on "h" with a spaced-out "hours" label, and moved
  "Shift Selected Tracks Now" to its own indented line below each
  checkbox+field row instead of packing everything horizontally.

v260918.1442
- Feature: "Analyze & Match..." — step 3 of the reconform pipeline
  (Compare → Offset Old → Analyze & Match → manual fixes → Apply).
  Non-destructive preview: scans the Reaper-selected track(s) and matches
  every recut candidate (all groups except Added, which has no old item)
  to a real item there, using the same Matched Item (metadata identity)
  and Length Match strategies Apply uses — offset-aware, so if Offset Old
  is enabled the search targets the shifted position, not the original
  one. Matched items are colored by recut type (Deleted red, Trimmed
  blue, Extended green, Moved orange, Shift gray) and get a take marker
  (prefixed "[CLB] ", reused on repeat runs rather than piling up) naming
  the group's own label, e.g. "Trimmed (head +0f/tail+78f)" or "Shift
  +86392f (635 clips)" — a glance at the arrange view shows what Apply
  would do, before anything is actually touched. Ends with a match-count
  summary (Matched Item / Length Match / Unmatched).
- Refactor: extracted the Mode A/C matcher functions (find_metadata_match,
  find_all_length_matches) and track_label/item_take_name out of
  CMP.apply_to_reaper into standalone CMP.* functions so both Apply and
  the new Analyze & Match share one implementation instead of two. Apply
  itself is unchanged — its local names now just delegate to the shared
  versions.

v260918.1350
- Change: Remove Dups and Consolidate now only scan/act on the currently-
  filtered (visible) event list, like Generate Items already did — rows
  hidden by the Track/Reel/Group/search filters are left completely
  untouched. Lets you e.g. hide everything but the Audio group and click
  Remove Dups to dedupe just Audio, without touching Video/other groups
  that happen to share reel/clip names. Hidden rows are always preserved
  regardless (the final rebuild still starts from the full list).

v260918.1333
- Fix: saving a CLB session (Save As .clb) immediately changed the header
  label from e.g. "XML Events" to "EDL Events", with no reload needed.
  Cause: CLB.loaded_format doubled as both "the original content format
  (XML/AAF/EDL), used for the header label and ${format} token" AND "is
  the loaded file a .clb project, for the toolbar's Quick Save button" —
  saving set it to the literal string "CLB" to mark the second thing,
  which clobbered the first. Split into two fields: loaded_format now
  stays untouched by saving/loading .clb (always the true original
  format), and a new loaded_is_clb flag alone gates Quick Save.
- Feature: added "ADR" to the default group set (now Video, Audio, ADR,
  Location, Effects, Music, Delete).

v260918.1322
- Fix: the actual root cause of Add/Rename Group (and Rename Track/Reel)
  "silently doing nothing" — these popups used ImGui_InputTextFlags_
  EnterReturnsTrue and only copied the typed text into Lua state when
  that flag's return value was true (i.e. only on the exact frame Enter
  was pressed). Typing a name and clicking OK instead of pressing Enter
  left the tracked buffer at its original value ("" for Add, the old name
  for Rename), so OK read back an empty/unchanged name and the previous
  build's new empty/collision message ("Group name can't be empty")
  fired even though text was clearly visible in the field. All four
  popups (Add Group, Rename Group, Rename Track, Rename Reel) now use
  plain InputText, synced on every keystroke, with Enter-to-submit
  detected separately via IsKeyPressed — both Enter and clicking OK work
  correctly now regardless of which one is used.

v260918.1309
- Feature: new lists now start with a default group set — Video, Audio,
  Location, Effects, Music, Delete — so they're all pickable right away
  (right-click a group → Assign Selected Rows Here) instead of having to
  "+" add each by hand. Add/Rename/Delete Group already existed (the "+"
  button, and right-click → Rename.../Delete Group... on any group).
- Fix: adding or renaming a group silently did nothing when the trimmed
  name collided with an existing group, or produced a group that looked
  identical to an existing one (a stray leading/trailing space, e.g. from
  a fat-fingered space or IME artifact, made "Audio " coexist invisibly
  next to "Audio") — this read as "add/rename doesn't work." Both now
  trim whitespace and show a message box on an empty or colliding name
  instead of silently no-op'ing; Rename previously had no collision check
  at all (could invisibly merge two groups under one name).
- Fix: CMP.rebuild_filters (used when reopening the graphical Compare
  view) dropped any manually added/renamed group with zero events —
  unlike the main list's own _rebuild_group_filters, which already
  preserves those. Now consistent between the two.

v260918.1258
- Feature: first step of the reconform pipeline redesign — "Reconform
  Offset" controls in the Apply "Modes..." popup. Offset Old (checkbox +
  hours, default +10h) and Offset New (checkbox + hours, for matching
  math only) let the old Reaper session be shifted out of the way before
  Trim/Extend/Moved matching begins, so the pristine old cut survives
  untouched as a source pool while the new cut gets rebuilt in the
  vacated real-timeline space. "Shift Selected Tracks Now" (next to
  Offset Old) performs the actual move: every unlocked item on the
  Reaper-selected track(s) shifts by the configured hours, wrapped in one
  undo block. This is the first of several planned steps (analyze/match
  session, per-item color + take-marker planned-action labels, manual
  match override, then Apply) — Trim/Extend/Moved matching/apply itself
  isn't wired up yet.

v260918.1219
- Feature: Recut Group Details table now has its own "Columns" button
  (next to Hide) with show/hide checkboxes per column, persisted like the
  main event-list's column visibility. Default view hides the four Src TC
  columns (Old/New Src In/Out) — after Compare, Src TC has already turned
  into a relative trim/extend number shown in the main table's Notes
  column, so most review only needs Old/New Rec TC. Any column can be
  toggled back on.
- Refactor: moved `local CMP = {}` earlier in the file (right before
  save_prefs/load_prefs) so those two functions can read/write the new
  CMP.GD_COL_VISIBILITY table directly; previously CMP was declared after
  both, which would have made a CMP.* reference from inside them resolve
  to an unrelated global. No behavior change to anything already using
  CMP.

v260917.2349
- Change: TC columns are no longer user-resizable, in every table/mode
  that shows them — main event list (Src/Rec TC In/Out), Audio list (Src
  TC), and Recut Group Details (all 8 Old/New Src/Rec In/Out columns).
  Their content is fixed-format "HH:MM:SS:FF" text, so a fixed width made
  more sense than letting them be dragged. Width source per table, for
  hand-tuning: main event list → DEFAULT_COL_WIDTH (top of file, indices
  6-9 = Src In/Out, Rec In/Out); Audio list → AUDIO_COL_WIDTH (index 2 =
  Src TC); Recut Group Details → the local TC_W in
  CMP.draw_group_details_table.

v260917.2344
- Fix: Recut Group Details table columns were cramped (equal stretch
  across all 11 columns squeezed the fixed-format TC text). TC columns
  (Src/Rec In/Out, old and new) now use a fixed width, matching the main
  event-list table's Fit-Widths treatment of TC columns; Reel, Tracks and
  Clip Name stretch to fill the remaining space instead.
- Change: column order now puts Src TC (Old/New In/Out) left of Rec TC
  (Old/New In/Out), matching the main table's existing Src-before-Rec
  order and the manual-conform workflow (jump to Src TC first to find the
  source content, then to Rec TC to place it).

v260917.2333
- Feature: Recut Group Details table now supports all four TC columns for
  click-to-jump, matching the main table. Added "Old Src Out" and "New
  Src Out" columns (previously only Src In was shown, and as plain text),
  and converted Old/New Src In into clickable cells alongside them. Every
  Rec/Src In/Out cell now jumps Reaper's edit cursor to its own literal
  TC value — same rationale as the main-table fix in v260917.2326: a
  Source TC is a real, independent absolute Reaper timeline position,
  used for manual conform (jump to Src TC to grab the right source
  content, then move it to Rec TC).

v260917.2326
- Fix: main-table click-to-jump was wrongly conflating Src TC with Rec TC
  (jumping Src TC In/Out to rec_tc_in/rec_tc_out instead of their own
  values). Reaper's timeline spans 0 to infinity, so a Source TC value is
  just as valid an absolute timeline position as a Rec TC value — this
  matters for manual conform, where raw/source dailies are commonly
  parked on a track at their own embedded timecode, separate from where
  the edited/conformed material sits at Rec TC. Each of the four TC
  columns (Src TC In, Src TC Out, Rec TC In, Rec TC Out) now jumps
  independently to its own literal TC value.

v260917.2316
- Feature: click-to-jump extended to the main table (every loaded list,
  including "Show as Table" recut groups — not Compare-specific). All
  four TC columns — Src TC In, Src TC Out, Rec TC In, Rec TC Out — are
  now clickable and move Reaper's edit cursor: Src TC In and Rec TC In
  both jump to rec_tc_in, Src TC Out and Rec TC Out both jump to
  rec_tc_out, since source-media timecode has no timeline position of
  its own — all four are just different views of the same two moments
  (an event's start and end). Selection/multi-select behavior on these
  cells is unchanged; the jump happens alongside it, not instead of it.

v260917.2306
- Feature: click-to-jump — Compare events can now move Reaper's edit
  cursor directly, mirroring Matchbox's old/new jump behavior:
  • Graphical Compare view: clicking a block in the SRC (old) timeline
    moves the edit cursor to that event's old Rec TC and scrolls the
    arrange view to it; clicking a block in the DEST (new) timeline does
    the same for its new Rec TC — each panel already carries its own
    side's native position, so no extra lookup is needed.
  • Recut Group Details table: the Old/New Rec TC In/Out cells are now
    clickable (hover shows "Click to move edit cursor here") — jumps to
    that specific value for that specific item, old or new independently.
  • Uses SetEditCurPos(pos, moveview=true, seekplay=false) — scrolls the
    arrange view into view without forcing playback to jump.

v260917.2259
- Change: the Apply confirmation dialog no longer lists every individual
  plan entry (didn't scale once there are many recut events) — it's now
  a compact summary: how many deleted events, the old TC range they
  span, how many selected tracks, and a per-strategy breakdown (N via
  Matched Item, N via Length Match, N via Range Clear [full/partial
  split], N not found, N locked/skipped). Full per-item detail (track,
  take name, action, strategy) still lives in the HTML report generated
  right after Apply runs — the confirm step is a sanity check, the
  report is the record.

v260917.2117
- Fix: Length Match was finding only the FIRST length-matching item and
  stopping (so it silently duplicated Matched Item's result whenever
  metadata happened to still be intact, and missed any other item that
  coincidentally shared the same length). Confirmed via real testing: the
  intent is that Length Match ignores metadata entirely and sweeps EVERY
  item overlapping the target's old range whose own length matches —
  including unrelated content deliberately cut in with the same
  duration. Now does exactly that (excluding whatever Matched Item
  already claimed for the same target, so it's never listed/deleted
  twice); Matched Item itself stays a single precise match, as content
  identity is meant to be unique.
- Fix: track references in the preview and HTML report now include the
  1-based track number ("#5 XML - A3") — Reaper does not enforce unique
  track names, so the name alone could refer to more than one track.
- Change: renamed the A/B/C resolution-strategy labels to descriptive
  text throughout the UI and messages — "Matched Item", "Length Match",
  "Range Clear" — no bare letters left anywhere user-facing.
- Feature: HTML Apply report. Every "Apply to Reaper" run now writes a
  self-contained HTML report (Reaper's own render-completion page was
  the model) to Resources/CLB_Apply_Reports/ and opens it in the default
  browser — one row per target: track, take name, status (done/partial/
  skipped/none), action, which strategy resolved it, old Rec TC In/Out,
  and the target's label. Built from the exact same plan/locked_list
  used to execute, so it's a precise record of what actually happened,
  not a re-derived summary — for tracking/audit beyond the console log
  and the timeline markers. Validated standalone: escaping (HTML
  entities, CJK text intact), table structure, and the macOS `open`
  launch all checked before shipping.

v260917.2057
- Feature: "Apply to Reaper" resolution strategies (A/B/C) are now
  individually toggleable via a new "Modes..." button/popup next to
  Apply to Reaper (persisted across sessions). Tried in fixed priority
  A > C > B regardless of toggle order; disabling a mode skips it
  entirely (skip all three and Apply refuses to run, with a message).
  • Added Mode C — length match: an item overlapping the target's old
    REC TC range whose own length matches the target's, with no
    metadata required. Sits between A (exact content identity) and B
    (identity-blind range clear) — useful when an item has drifted
    slightly but wasn't trimmed, so it no longer sits at the exact old
    position Mode B's overlap check would still catch, but retains its
    original duration. Resolved via Mode C deletes the whole item
    outright (no split), same as Mode A.
  • The preview list now labels which mode (A/C/B) resolved each target.

v260917.2001
- Change: "Apply to Reaper" (Deleted) rebuilt around two proper strategies
  instead of the previous exact position+length coincidence match (which
  risked deleting an unrelated item that happened to occupy the same TC
  range — confirmed by hands-on testing):
  • Mode A (matched item): if any item on the selected track(s) carries
    P_EXT:CLB_REEL + CLB_SRC_TC_IN/OUT metadata (written by Generate
    Items / conform_matched_items) identifying it as this event's own
    content, delete that specific item by identity — regardless of
    exactly where it now sits.
  • Mode B (range clear): when no item carries that identity (e.g.
    content that's been edited/rendered since conform, so metadata no
    longer applies — the common case recut is actually for), clear
    whatever occupies the old REC TC range on the selected track(s)
    instead, splitting items at the range edges as needed (partial
    overlaps are trimmed, not deleted whole) rather than requiring an
    exact boundary match.
  • Each target tries Mode A first, falls back to Mode B automatically —
    no manual mode selection needed.
  • The preview (see below) now shows which mode resolved each target
    and, for Mode B, whether the overlap was full or partial.
- Feature: "Apply to Reaper" (Deleted) now previews exactly what it found
  before deleting anything, instead of just a count. Confirmed by hands-
  on testing: matching is purely by position+length on the selected
  track(s) — no name/content/metadata check — so it's possible (if rare)
  for an unrelated item that happens to occupy the identical TC range to
  match too. The confirmation dialog now lists each matched item's track
  name and current take name (capped at 15, "...and N more" beyond that)
  so a coincidental or unexpected match can be caught and cancelled
  before committing, not discovered afterward via Undo. Locked items that
  matched are also called out separately. The scan-then-confirm-then-
  delete now reuses one match list throughout (previously re-scanned at
  delete time), so what's previewed is exactly what gets deleted.

v260917.1844
- Fix: once a compare result existed, the graphical Compare view had no
  way back to Load Old/New/Session — "Close" only exited the whole
  Compare window (back to the normal table), and the Load Old/New/
  Session setup screen only appears when CLB.compare_result is nil, which
  nothing on the result screen could trigger. Added "Load Session..."
  (load a different .clbcmp, replacing this one) and "Clear Comparison"
  (discard compare_old/compare_new/compare_result and return to the
  Load Old/New/Session setup screen, still inside Compare view) next to
  Save Session on the result screen.

v260917.1839
- Feature: Compare Session save/load (.clbcmp) — unifies the two
  previously-separate, both-incomplete saves into one that actually
  restores everything. Saving from the graphical Compare view ("Save
  Session...") now writes both sides' raw rows (names, fps/is_drop,
  every row) instead of just the flattened group-summary table; loading
  it ("Load Session...", in the Load Old/New setup screen) restores
  CLB.compare_old/.compare_new and re-runs Compare in one step —
  reconstructing the graphical SRC/DEST view, the live Details panel,
  and "Show as Table" exactly, since all of those are pure functions of
  the two row-sets. Plain "Save"/"Save As" (main toolbar) is unchanged
  and still just exports whatever flat table is currently in ROWS — a
  valid, simpler, separate use case, not a full session.
- Fix: the new session-file row writer (_write_cmp_row) had a format-
  string arg-count bug (20 specifiers for 21 values, since the row-
  prefix needed a dynamic "OR"/"NR" %s that the original single-purpose
  R| writer didn't need) that would have crashed on the very first Save
  Session. Caught during validation, fixed, and round-trip tested against
  the real 803/842-row V1/V2 dataset — identical Compare results (14
  groups, 454 changes) before and after a save+reload cycle.

v260917.1829
- Change: Group Details is now live and auto-opens, instead of a manual
  one-shot button. "Show as Table" opens it automatically; from then on
  it refreshes every frame from whatever recut-group row(s) are currently
  selected — click a different event above and its matched items appear
  below immediately, the same way the Audio List already follows matches
  elsewhere in CLB. The banner button is now a "Hide Details"/"Show
  Details" toggle (matching the panel's own "Hide"); no selection just
  shows an empty/placeholder state instead of an error.

v260917.1823
- Change: Group Details is now an inline split-view panel instead of a
  popup — it takes over the same lower-pane slot the Audio List normally
  occupies (Compare mode has no use for the audio panel there anyway),
  complete with the same draggable splitter. "Details..." now toggles it
  open/refreshed from the current selection; "Hide" in its header closes
  it, matching the Audio List's own Hide button.

v260917.1817
- Feature: "Details..." button while viewing Compare recut groups — opens
  a read-only popup listing every individual item behind the currently-
  selected group row(s): reel, tracks, old/new Rec TC In/Out, old/new Src
  TC In/Out, clip name. Lets you verify exactly what a group (e.g. a
  360-item "Shift") actually covers before hitting Apply, without losing
  the group-level selection workflow — Apply itself already always
  operates on each item's own precise data internally, never the
  aggregated/joined display text in the table's Reel/Track columns.
  Per-item selective exclusion within a group is a later increment.

v260917.1813
- Feature: Shift vs. Moved distinction. A "Moved" recut group that turns
  out to hold more than one item (many clips sharing the exact same
  delta — a whole block displaced together, e.g. from a global base-
  offset between versions, or the downstream effect of something
  inserted/removed earlier) is now labeled "Shift +N frame(s) (M clips)"
  and drawn in a distinct muted color, separate from a single clip
  genuinely moved on its own (still "Moved", bright blue). Compare's
  summary line and console output now report Shift/Moved counts
  separately. No detection/assumption involved — purely what the
  grouping already reveals (shared vs. unique delta).

v260917.1752
- Change: Compare no longer assumes ripple. Removed the ripple-aware /
  running-offset classification from hsuanice_CLB Compare Engine.lua's
  M.compare() and the align_shift compare-view alignment aid — every
  change is now classified and displayed purely by absolute REC TC.
  Reason: the ripple assumption correctly collapsed a real ripple-insert
  cascade in one test, but produced a false "Moved" for a plain non-
  rippling single-track delete in another — indistinguishable from EDL
  data alone, so absolute position is the safer default for recut/apply.
  A genuine base-offset between two versions (e.g. different sequence
  start TC) will again show as many "Moved" entries, but M.group()'s
  signature-based grouping still collapses same-shift items into one
  group, so it doesn't flood the recut-group list.
- Feature: "Apply to Reaper" now refuses to run while Reaper's Ripple
  Editing is on (checks commands 41990/41991), since a ripple-mode
  delete/move would let Reaper shift other items to compensate,
  corrupting the absolute-position result. Also now checks each matched
  item's lock state (C_LOCK) before deleting it — locked items are left
  untouched and reported in the console summary instead of being forced.

v260917.1717
- Feature: Phase 3 (recut apply engine) — first increment, Deleted only.
  • New "Apply to Reaper..." button, shown alongside "Exit" while viewing
    Compare's "Show as Table" recut-group list.
  • Select one or more Deleted-type group rows, select the target
    track(s) in Reaper, then Apply: for each deleted item, searches the
    selected track(s) for a media item positioned at that item's old REC
    TC range (±1.5 frame tolerance) and removes it, leaving a red project
    marker at that position for QC. Confirms before running (shows how
    many items/tracks are affected) and wraps everything in one Undo
    block. Trimmed/Extended/Moved/Added rows are reported as not yet
    supported and left untouched if selected alongside Deleted ones.
  • This is the first Phase 3 piece that actually modifies the REAPER
    project (deletes items) — please test on a project you can safely
    Undo, and confirm Cmd/Ctrl+Z fully reverts it, before relying on it.

v260917.1704
- Fix: "Show as Table" recut-group rows had Src TC In/Out hardcoded to
  00:00:00:00 — never actually populated. Now computed the same way as
  Rec TC In/Out (min/max across the group's visible member items' source
  timecode): a single-item group shows that item's exact src range; a
  multi-item group (e.g. an "Added" block) shows the span covering all
  of them.

v260917.1653
- Fix: toggling a track off in the Track Filter panel while viewing
  Compare now collapses that track's entire lane in the SRC/DEST
  timelines (saves vertical space), instead of only hiding its clips
  while leaving an empty row behind.

v260917.1648
- Feature: "Clear List" toolbar button — resets the main table to empty
  (confirms first if anything is loaded; doesn't touch loaded audio files
  or Compare's independent Old/New state).
- Feature: "Save..." in the Compare view — saves the current compare
  result's recut groups directly to a .clb project file, without needing
  "Show as Table" first and without disturbing whatever the main table
  currently has loaded (temporarily swaps ROWS for the save, then
  restores it exactly).
- Fix: the Compare view (graphical dual timeline and "Show as Table")
  now actually respects the Track/Reel/Group filter panels shown above
  it. CMP.rebuild_filters() re-points those panels at Compare's own old+
  new dedup data whenever a compare result is (re)computed or reopened,
  and both the graphical renderer and the group-rows builder skip
  events/items whose reel or category is hidden (a recut group left with
  zero visible items after filtering is omitted from "Show as Table"
  entirely). Closing the Compare view restores the filter panels to
  reflect ROWS again, so the main table's own filtering isn't left showing
  Compare's data by mistake.
- Internal: consolidated ~9 Compare-related top-level locals (functions,
  color tables) into one CMP namespace table — the file had hit Lua's
  200-local-per-chunk limit for the main script after this session's
  additions ("too many local variables"); no behavior change.

v260917.1559
- Feature: Compare workflow redesign — independent Load Old/New, own
  session (.clb) support, and "Show as Table" for recut groups.
  • "Compare..." is now a self-contained workflow: it no longer needs (or
    touches) the main table's currently-loaded ROWS/sources. Opening it
    shows a setup screen with dedicated "Load Old..." / "Load New..."
    buttons; Compare runs automatically once both sides are loaded.
  • Each side accepts .edl / .xml / .aaf (parsed synchronously via
    OTIO.parse) or an existing .clb project — loading a .clb carries its
    already-curated row.group categories straight into the comparison,
    via a new pure _parse_clb_file() parser extracted from
    load_clb_project() (same behavior, now reusable without mutating the
    live session).
  • New "<< Show as Table" button: converts the compare result's recut
    groups into one row per group (via _build_group_rows_from_compare)
    and shows them in the main table, reusing its existing sort / filter
    / search / right-click group-rename — no bespoke Change List UI
    needed. Each group's category is inherited by majority vote from the
    original rows' own .group field (Video/Audio/Other, or whatever the
    user had already curated).
  • This temporarily replaces the main table's ROWS; a banner ("Showing
    Compare recut groups...") with an "Exit (restore my list)" button
    appears until the user switches back, restoring the exact prior list.
  • The graphical dual-timeline view (Phase 2) is otherwise unchanged.

v260917.1526
- Fix: "Compare..." button was completely hidden from the toolbar unless
  exactly two sources were already loaded, making the whole reconform
  feature undiscoverable. Now always visible; disabled/grayed with a
  tooltip explaining what's missing (0 sources / 1 source / >2 sources)
  until exactly two are loaded, then enables normally.

v260917.1516
- Feature: Compare view (reconform) — Phase 2, visual dual timeline.
  • Clicking "Compare..." now opens a dedicated Compare view instead of
    only printing to console: a summary bar (Deleted/Trimmed/Extended/
    Moved/Added counts + a color legend + a "Matched %" indicator) above
    two stacked timeline canvases — SRC (old) on top, DEST (new) on
    bottom, split by a draggable divider, sharing one horizontal zoom/pan
    (scroll wheel = vertical scroll, Alt+scroll = zoom, drag = pan).
  • Blocks are colored by change type instead of by track (red=Deleted,
    green=Trimmed, yellow=Extended, blue=Moved, purple=Added, neutral
    gray=Unchanged); hover shows clip name, reel, tracks, change type,
    recut-group label, and rec TC.
  • DEST events are displayed using the new `align_shift` the Compare
    Engine now computes per event (new.rec_in - old.rec_in for matched
    pairs, the running ripple offset for Added) — subtracting it
    normalizes away ripple/base-offset so unchanged content lines up
    with SRC at the same x position, and only genuinely-changed items
    visibly diverge between the two panels, without needing Matchbox-
    style connector lines (deferred; may revisit later).
  • "<< Back to Table" returns to the normal EDL table/timeline view;
    the Compare view is otherwise a full replacement of the content area
    while active (CLB.show_compare_view).
  • Interactive group/item selection and the actual recut/apply engine
    (Stage Offset, Mode 1 bulk move, Mode 2 per-item metadata recut,
    Deleted auto-delete, Added auto-conform) are Phase 3 — not yet
    implemented; this pass is view-only.

v260917.1352
- Feature: Old-vs-new Compare (reconform) — Phase 1, console output only.
  • New "Compare..." toolbar button, shown when exactly two sources are
    loaded (load the OLD version, then Load EDL/XML/AAF again and choose
    Append for the NEW version).
  • New Library/hsuanice_CLB Compare Engine.lua: matches old→new events by
    Reel + Source TC (5-frame tolerance), collapses cross-track duplicates
    (e.g. a stereo pair on A1/A2) into one canonical event, then walks the
    timeline tracking a running ripple offset so moves fully explained by
    upstream Added/Deleted/Trimmed/Extended content (or a constant
    project-start-TC difference between the two files) are not reported as
    independent changes — only genuinely anomalous moves are.
  • Classifies each real change as Trimmed / Extended / Moved / Added /
    Deleted, then groups changes that share the exact same transformation
    ("recut signature") into one reviewable/applicable group instead of
    listing every affected clip separately; Added/Deleted are grouped by
    timeline contiguity instead.
  • Results print to console (summary counts + group breakdown) and are
    stored in CLB.compare_result for the upcoming Change List / dual
    SRC-DEST timeline review UI (Phase 2) and the recut/apply engine
    (Phase 3) — not yet implemented; this pass only computes and reports.

v260911.1950
- Fix: Subtitle import no longer fails when the saved OTIO Python path is
  stale (e.g. a pyenv virtualenv that was later removed). Subtitle Bridge
  now validates the interpreter itself and auto-falls-back to a working
  python3 (subtitle parsing never needed opentimelineio to begin with).
  Also hardened the main script's startup check to re-detect Python when
  the saved path is invalid, not just when it's empty.
- Feature: Batch SRT import
  • "Load Subtitle..." now supports multi-select; selecting several .srt
    files parses and applies them all in one go, using the same
    Replace/Append prompt already used for multi-file EDL/XML/AAF import.
  • If a mixed selection also includes CSV/TSV/XLSX (which need a per-file
    sheet/column choice), those files are skipped with a console notice;
    load them one at a time as before.
- Fix: SRT display-formatting tags (e.g. <i>, <font color=#RRGGBBAA>) are
  now stripped from clip-name text at parse time (Tools/subtitle_to_clb.py),
  so styled lyrics/dialogue SRTs no longer carry raw tag markup into CLB.

v260426.1458
- Feature: Custom CJK font (Options → CJK Font…)
  • Lets users point CLB at a font file (.ttf / .ttc / .otf) or family
    name. Useful for Taiwanese / Hakka characters not covered by PingFang.
  • Path is persisted via CJK_FONT_PATH ExtState key.
  • Apply switches the font immediately; no script restart needed.
  • Empty path falls back to platform candidates (PingFang / msyh / Noto).

- Fix: Subtitle imports now use track name "SUBTITLE" instead of the raw
  "SUBTITLE_XLSX" / "SUBTITLE_CSV" etc. internal format identifier.
- Fix: Track-name template expansion now strips dangling separators left
  by empty tokens (e.g. "SUBTITLE - " with empty ${track} → "SUBTITLE").

- Tweak: Subtitle import dialog no longer shows a Frame Rate row.
  • Parsing uses the current CLB.fps; the existing post-import "Confirm
    Frame Rate" prompt remains the canonical place to set FPS / drop frame
  • A small hint shows the FPS that will be used at parse time

v260426.1426
- Feature: Subtitle / Dialogue List import (.srt / .csv / .tsv / .xlsx)
  • New "Load Subtitle..." toolbar button next to Load EDL/XML/AAF
  • SRT loads silently using the current CLB FPS for TC conversion
  • CSV / TSV / XLSX open a column-picker dialog with sample-row preview
  • Auto-detects IN/OUT columns by scanning for time-like cells (left-most
    pair wins). User picks sheet (xlsx) and text column manually
  • Subtitle in/out are written to rec_tc_in / rec_tc_out (absolute
    timeline position). Source TC, reel, scene, take left empty
  • Overlapping subtitles preserved as-is (no shifting)
  • New: Tools/subtitle_to_clb.py and Library/hsuanice_Subtitle Bridge.lua

- Feature: CJK-capable font for clip-name display
  • Loads PingFang.ttc (macOS), Microsoft YaHei (Windows), or Noto CJK
    (Linux) at startup so Chinese / Japanese clip names render properly
  • Falls back silently to ImGui default if no CJK font is available

v260404.1358
- Fix: ${format} token now correctly reflects source format after saving/reloading .clb
  • Previously CLB.loaded_format was hardcoded to "CLB" on .clb load, causing ${format}
    to always expand to "EDL" regardless of the original source (AAF, XML, EDL)
  • .clb save now writes SOURCE_FORMAT|<format> (e.g. SOURCE_FORMAT|AAF)
  • .clb load restores CLB.loaded_format from SOURCE_FORMAT; defaults to "CLB" for
    older files without the key (backwards compatible)

- Fix: Event count header now shows format-aware label (AAF Events / XML Events / EDL Events)
  • Used _friendly_format(CLB.loaded_format) to derive the label from the loaded format
  • Empty state now shows "No Event Loaded" instead of "No EDL loaded"
  • Empty hint text updated to mention 'Load AAF...' alongside EDL and XML options

v260404.1340
- Fix: Matching no longer overwrites Clip Name automatically
  • Previously, matching with a single candidate would overwrite row.clip_name with
    af_meta.orig_filename (or the audio file basename), saving the old value to Notes
  • This caused UUID-style filenames (e.g. f5d25fae-3db0-8413-2c63-c3ad0000007c.wav)
    to replace scene/take-derived clip names when linking AAF media
  • Clip Name is now only changed via the explicit "Apply" button with a format template
  • Reel/Tape, Scene, and Take are still auto-repaired from matched audio as before
  • Removed backfill_n.clip_name counter and its console summary line

- Fix: Add Group popup — keyboard focus and OK button now work on first attempt
  • Replaced manual focused-flag + SetKeyboardFocusHere(-1) pattern with the correct
    Dear ImGui idiom: IsWindowAppearing → SetKeyboardFocusHere(0) before the InputText
  • OK button previously created an empty group because CLB.add_group.buf was only
    updated when Enter was pressed (EnterReturnsTrue flag); now new_buf is always synced
    every frame so both Enter and OK submit the correct typed text

v260403.1448
- Fix: Timeline panel scroll wheel controls reworked for macOS compatibility
  • Scroll (no modifier)  → vertical scroll through track rows (unchanged)
  • Shift+scroll          → horizontal pan; macOS converts Shift+scroll to the
                            horizontal scroll axis, so this now reads scroll_h from
                            ImGui_GetMouseWheel's second return value — no OS interception
  • Option/Alt+scroll     → horizontal zoom anchored to cursor position
  • When no tracks overflow (vscroll_visible = false), plain scroll falls back to zoom
  • Hint label in label column updated to "opt+scroll:zoom"
  • Previously Ctrl/Cmd+scroll was used for zoom; replaced with Option/Alt per request

v260402.1405
- Feature: Click EDL row → auto-filter Audio Files panel to matched file(s)
  • Clicking any row with a Found/Fallback/Multiple match narrows the Audio Files
    table below to show only the matched ISO audio file(s) for that row
  • Works for all match types: single (real path), multiple candidates (__match_candidates),
    and Fallback+multiple (matched_path = "(N)" is correctly resolved via __match_candidates)
  • Audio Files header shows "[ Showing matched ]" in cyan while filter is active
  • "Show All" button clears the filter; audio search still works within it
  • Purpose: quickly inspect the matched file and manually reject wrong matches

- Feature: Reel repair from matched ISO audio (for all match types)
  • On match, row.reel is always overwritten with the audio file's IXML:TAPE / BWF REEL value
  • If the original Reel value was non-empty and different, it is saved to the Notes column
    as "Orig Tape: <original>" for reference
  • Applies to both single-candidate matches (#candidates == 1) and multi-candidate matches
    (#candidates > 1) — previously only single-candidate rows were repaired
  • Repaired rows show "Found ✦" or "Fallback ✦" in cyan in the Match Status column
  • Tooltip on hover: "Tape / Clip Name repaired from matched ISO audio. Original values
    saved to Notes column."
  • Reel Filter sidebar is rebuilt after every match run to reflect updated reel names

- Feature: Clip Name format template with Apply button
  • New text input in EDL toolbar: type a template (e.g. $reel----$sceneT$take)
  • Tokens: $reel, $scene, $take (case-insensitive)
  • Example: $reel----$sceneT$take → D043----9-9-12T1
  • Blank field = no rename (original clip names preserved)
  • "Apply" button to the right immediately renames all matched rows (Found/Fallback/
    Multiple) using the current template; greyed out when field is empty
  • Template is NOT applied automatically during matching — only on explicit Apply
  • Template persisted across sessions via ExtState

- Feature: Right-click context menu → Assign Reel (multi-select)
  • Right-click any EDL row → context menu shows "Assign Reel (N rows):"
  • Lists all existing reels with their event count; current reel is checkmarked
  • "New reel name:" input + Create button to define and assign a new reel in one step
  • "(Unassign Reel)" sets reel to empty
  • Group assignment section follows below (unchanged)
  • All operations apply to the full multi-selection (same as Group assignment)

- Feature: Scene and Take fields now persisted in .clb project files
  • row.scene saved as p[20], row.take as p[21] in the R| row format
  • Backwards-compatible: old .clb files default to "" for both new fields
  • Scene and Take now included in __search_text for full-text search
  • __search_text is also rebuilt after match_audio_files() so newly filled
    scene/take/reel values are immediately searchable

- Fix: Conform All / Conform Sel buttons now appear when matches are Fallback-only
  • Previously has_matches check only tested for "Found" or "Multiple" status
  • Fallback matches (Tape+TC strategy) were never shown the Conform buttons
  • Fixed to include "Fallback" in the has_matches check

- Fix: Audio filter on click now works for Fallback+multiple rows
  • Fallback rows with multiple candidates store matched_path = "(N)" (not a real path)
  • Click handler now detects the "(N)" placeholder and builds the filter from
    __match_candidates instead, so the correct audio files are highlighted

- Fix: Clip Name auto-rename removed from matching
  • _apply_clip_name_format() was erroneously called inside match_audio_files() for
    both single and multiple-candidate branches
  • Now only called when the user explicitly clicks the Apply button in the toolbar

- Fix: Reel Filter sidebar not refreshing after matching
  • _rebuild_reel_filters() was not called after match_audio_files() completed
  • Reel values updated by tape repair were invisible in the sidebar until next reload

- Fix: _rebuild_reel_filters forward declaration
  • match_audio_files() is defined before _rebuild_reel_filters() in source order
  • Added forward declaration (local _rebuild_reel_filters) to resolve the nil-call crash
    ("attempt to call a nil value (global '_rebuild_reel_filters')")

── New / updated support files ────────────────────────────────────────────

Tools/otio_to_clb.py  (v260402)
- Replaces direct CMX3600 / FCP7-XML parsers; all timeline formats now go through
  OpenTimelineIO (OTIO) so the same code handles EDL, FCP7 XML, Resolve XML, and AAF
- _rt_to_tc(): rescales OTIO RationalTime to project FPS before TC conversion;
  fixes wrong Src TC when AAF stores timestamps at 48 000 Hz sample rate
- _load_aaf(): tries OTIO native AAF adapter first, falls back to aaf_to_otio.py /
  LibAAF if the native adapter is unavailable
- _aaf_user_comments(): reads AAF UserComments dict from clip.metadata['AAF']
- _scene_take(): checks UserComments SCENE/TAKE keys first, then falls back to
  _parse_scene_take_from_name() — handles both clean and concatenated clip names
- _parse_scene_take_from_name(): strips Merged/Synced/channel suffix, matches
  {body}_T{digits} pattern, normalises tokens (leading-zero strip, uppercase alpha)
- _write_progress() / --progress-file arg: writes phase/current/total/name to a
  temp file every 50 clips so Lua can display a live progress bar during long loads
- logging level set to ERROR to prevent pyaaf2 debug output contaminating JSON stdout

Tools/aaf_to_otio.py  (v260402)
- Wraps LibAAF's aaftool binary to extract AAF essence metadata without needing the
  full pyaaf2 / OTIO AAF adapter stack
- parse_essences(): reads aaftool stdout; now captures SCENE, TAKE, TAPE metadata
  lines (- Name: "Scene"  Text: "…") that follow each "File:" line
- build_otio(): attaches clip_meta = {scene, take, tape} into Clip.1 metadata so
  otio_to_clb.py can read them back via _aaf_user_comments()

Library/hsuanice_OTIO Bridge.lua  (v0.3.0)
- New async API: parse_async_start(filepath, opts) / parse_async_poll(handle) /
  parse_async_progress(handle)
- parse_async_start(): writes a temp .sh launcher script, calls
  reaper.ExecProcess("/bin/sh script.sh", -1) so Python runs truly non-blocking
  (os.execute would block REAPER's UI thread on macOS)
- parse_async_poll(): reads sentinel file (done.txt); strips non-JSON prefix before
  JSON decode to handle any residual stdout before the "{" (pyaaf2 warnings, etc.)
- parse_async_progress(): reads the progress file written by otio_to_clb.py;
  returns {phase, current, total, name} for live progress bar rendering
- Sync M.parse() path also strips non-JSON prefix for robustness

Library/json.lua
- Standalone JSON encode/decode for Lua (MIT licence, rxi/json.lua)
- Used by hsuanice_OTIO Bridge.lua to decode the JSON output of otio_to_clb.py

v260323.2201
- Fix: FPS confirmation dialog now correctly shows the saved FPS (e.g. 24) instead
  of always defaulting to 25 — EDL Parser now respects CLB's saved FPS preference
  when the EDL has no explicit FPS comment (plain NON-DROP FRAME header)

v260323.2151
- Change: Default frame rate changed from 25 to 24
- Feature: Frame rate confirmation dialog on EDL/XML load and before Scene Cut Track creation
  • After loading any EDL or XML, a dialog appears showing the detected FPS
  • User can correct it before events are used (e.g. if EDL header has wrong FCM)
  • "Scene Cuts" button also asks for FPS confirmation before generating items
  • Cancelling the dialog cancels the Scene Cut generation (load still proceeds)
  • Drop Frame flag is also shown and editable in the same dialog

v260323.2041
- Feature: Create Scene Cut Track
  • New "Scene Cuts" button in toolbar
  • Loads the currently-open EDL, walks events in timeline order, and groups
    consecutive events sharing the same EP_Scene into one empty item
  • Clip name format: EP_Scene_Shot_Ttake[_Camera] (e.g. 06_01B_01_T05_A)
  • Non-matching events (Black Video, graphics, etc.) act as scene breaks
  • If scene 01B → 02A → 01B, two separate 01B items are created
  • Each item's take name is set to the EP_Scene label (e.g. "06_01B")
  • Creates a new "Scene Cuts" track appended to the project

v260323.0202
- Feature: Remove Duplicates now heals consecutive split clips (Pass 3)
  • If event A's rec_out == event B's rec_in AND src_out_A == src_in_B (within 1 frame),
    they are recognised as the same clip split at an edit point
  • Merged into a single event spanning the full range (rec_tc_out and src_tc_out extended)
  • Supports chains of 3+ consecutive splits; debug log shows [HEAL] entries
  • Confirm dialog and summary updated to show split-healed count separately

v260323.0148
- Fix: Remove Duplicates containment check now guards against different source content —
  if two events have the same Reel+ClipName but sync offsets differ by more than 5 frames,
  they are treated as different content (not duplicates), even if rec TC ranges nest

v260323.0054
- Fix: Near-duplicate tolerance reduced from 24 to 5 frames to prevent false removals

v260323.0051
- Feature: Remove Duplicates now detects near-duplicates within 5-frame tolerance
  • Exact duplicates: same Reel + Src TC In/Out + Rec TC In/Out + Clip Name (unchanged)
  • Near-duplicates: same Reel + Clip Name, sync offset (rec_in - src_in) matches within
    5 frames, and rec TC ranges overlap — catches multi-channel recordings where both
    src and rec in-points shift by the same small amount (different trim, same content)
  • Keeps the event with the widest Rec TC range (largest duration)
  • Confirmation dialog now shows exact vs near-duplicate counts separately

v260322.1541
- Fix: Conform now works for Fallback (Tape+TC) matches with multiple candidates
  • Fallback rows with multiple candidates (matched_path="(N)") now correctly use
    __match_candidates and insert all as multiple takes, same as "Multiple" status
  • Previously these rows silently produced 0 items due to path lookup failure

v260322.0026
- Change: Conform always creates new tracks, never reuses existing project tracks
  • Previous behavior: searched for a matching track name and inserted items into it
  • New behavior: a fresh track is always created for each conform run, regardless of
    what already exists in the REAPER project
- Feature: Tape+TC fallback matching (Strategy 5)
  • When Strategies 1–4 all fail (e.g. EDL has wrong clip name), matching retries
    using Reel+TC range only — ignores clip/filename entirely
  • A file matches if its BWF src_tc ≤ EDL src_tc_in < src_tc + file duration
  • Match column shows "Fallback" (orange); Matched File column shows "[Tape+TC]
    filename" in red; hover tooltip explains the fallback reason and shows full path

v260322.0015
- Fix: Transition events fading out to BL now correctly show the real outgoing clip name
  • Previous logic always preferred TO CLIP NAME when non-empty — correct for fade-in from
    BL, wrong for fade-out to BL (where TO CLIP NAME = "BL" and FROM CLIP NAME = real file)
  • New logic: skip "BL" as clip name source; prefer whichever of FROM/TO is a real non-BL
    filename; fall back to the other side only if both are BL or empty

v260228.1401
- Feature: Reel multi-select in sidebar (and horizontal panel)
  • Click on reel name text → select only that reel (sets shift-anchor; no visible change)
  • Shift+click text → range-select from anchor to here
  • Ctrl/Cmd+click text → toggle individual reel in/out of selection
  • Click [ ] checkbox → toggles visible only (no selection change)
  • Right-click → context menu; if 2+ selected: "Check selected" / "Uncheck selected" shown
    at top; single-item options (Rename, Delete, Batch Rename) always available below
  • All / None buttons clear selection
  • Selection is cleared when reel list is rebuilt (file reload, rename, delete)
  • Selected rows shown with blue highlight behind both checkbox and text

v260402.1520
- Feature: Multi-pattern clip-name parser for Scene/Take matching
  • SCENE_TAKE_PARSERS table — tried in order until a hit is found in audio index:
      Pattern A  EP_SCENE_SHOT_T##    "06_01B_02_T01 - Merged" → 6-1B-2 / 1
      Pattern B  SCENE /t##           "9-1-1    /t2    .new.01" → 9-1-1 / 2
      Pattern C  SCENE-T## / SCENE T## "9-1-1-T2", "Scene01 T5"
  • Strategy 6 tries existing row metadata first, then each parser in turn
  • Console summary shows which pattern matched how many clips + backfill counts
  • Extendable: add entries to SCENE_TAKE_PARSERS for new project naming conventions

v260402.1153
- Feature: Scene/Take parsing from structured clip names (EP_SCENE_SHOT_T##)
  • otio_to_clb.py: if AAF UserComments have no SCENE/TAKE, parse from clip name
    e.g. "06_01B_02_T01 - Merged" → Scene "6-1B-2", Take "1"
  • normalize_scene_key(): strips leading zeros and separators for flexible comparison
    "6-01B-02" == "06_01B_02" == "6-1B-2" (all normalise to same key)
  • Strategy 6 in match_audio_files(): match EDL rows to ISO audio by
    normalised Scene + Take (works even when filenames differ completely)
  • When a single match is found (any strategy), backfill empty scene/take/reel
    fields in the EDL row from the matched audio file's iXML metadata

v260401.2003
- Fix: Src TC for AAF now uses absolute recording TC (PhysicalSourceMob) via OTIO native
  AAF adapter — matches EdiLoad output. Previously showed SourceOffset (merged file offset).
- Fix: Scene/Take metadata now extracted from AAF UserComments (SCENE/TAKE keys).
- Feature: Async (non-blocking) loading for AAF/XML files.
  • File-open dialog returns immediately; loading indicator shown while Python runs in background.
  • Animated progress bar ("Loading filename...") shown in place of content area.
  • Multiple files load sequentially in the background.

v260401.1748
- Feature: AAF support via LibAAF (aaftool) — replaces aaf2/OTIO AAF adapter
  • AAF parsed by Tools/aaf_to_otio.py using LibAAF's aaftool binary
    (aaftool must be in PATH; install from https://github.com/agfline/LibAAF)
  • Tools/otio_to_clb.py dispatches .aaf → aaf_to_otio → OTIO → CLB JSON
  • Supports: multi-track audio, drop-frame TC, fades, X-FADE transitions
  • "Load AAF..." tooltip updated to reflect LibAAF requirement

v260228.0136
- Feature: Premiere Pro XML and AAF support (via OpenTimelineIO)
  • "Load XML..." now handles FCP7 XML, DaVinci Resolve XML, and Premiere Pro XML
    (Premiere detected by content sniffing; routed through OTIO fcp_xml adapter)
  • New "Load AAF..." button (AAF via opentimelineio aaf2 adapter — superseded in v260401)
  • otio_to_clb.py v0.2.0: detect_format() handles .aaf; _detect_xml_format()
    distinguishes Premiere XML from FCP7 XML by peeking at file content

v260228.0135
- Feature: Save / Save As for open CLB projects
  • When a .clb project is loaded, toolbar shows "Save" (silent overwrite) + "Save As..." (dialog)
  • "Save" tooltip shows the current filename
  • "Save As..." updates the loaded file path so subsequent saves go to the new file
  • When no project is loaded, original "Save..." button (dialog) is shown as before

v260228.1600
- Fix: json.lua decode_number — negate=true caused immediate stop at digit (empty number string)
  • Changed next_char(str, i, delimiters, true) → next_char(str, i, delimiters) (negate=nil)
- Fix: json.lua decode_literal — ["null"]=nil was silently dropped from table (key absent)
  • Replaced literals hash with literal_list (ipairs) so nil value is returned correctly
- Fix: Reel filter sidebar capped at scale(220)px to prevent long reel/clip names from
  squeezing the Event List
- Feature: Scene and Take columns in Event List (COL 18, 19; hidden by default)
  • Populated automatically from OTIO/XML metadata (FCP7/Premiere masterComment1/2)
  • Enable via Cols button in the Event List toolbar
- Compat: Old .clb projects and saved column orders (17 cols) are migrated automatically;
  new columns appended at end of order on first load

v260228.0122
- Fix: Splitter between Event List and Audio List now responds to vertical drag (up/down)
  • Was reading delta_x instead of delta_y from ImGui_GetMouseDelta
- Feature: "Reels >>" button replaced with "Filters >>" — toggles Reels and Groups together

v260228.0052
- Feature: Fit Widths button is now a toggle (Fit Widths ↔ Default) for both EDL and Audio tables
  • "Fit Widths" only stretches content-heavy columns (Clip Name, Notes, Filename, etc.);
    fixed-content columns (TC, Duration, Level, SR, Ch, FPS, Speed) keep their default widths
  • Clicking "Default" restores all columns to their default pixel widths
  • Audio table now uses the same fixed+stretchy strategy as the EDL table
- Fix: Audio File List column visibility is now persisted across sessions
  • Show/hide state saved via ExtState "audio_col_visibility"
  • Restored on script load; any change in the Columns popup is saved immediately

v260227.1717
- Fix: Search box now correctly matches TC columns (Src TC In/Out, Rec TC In/Out, Duration)
  • __search_text is rebuilt in 4 places; all now include TC fields
  • Previously only the initial EDL load rebuilt search text with TC — after any cell edit,
    paste, undo/redo, or .clb project load, TC was dropped from search index

v260227.1714
- Fix: Fit Widths now works correctly and is idempotent (same result every click, no drift)
  • EDL table: fixed-width columns (Reel, Track, Edit, Level, all TC/Duration) stay at
    their default widths; stretchy columns (Clip Name, Source File, Notes, Matched File,
    Group) share the remaining window width proportionally
  • Both EDL and audio tables: always compute from DEFAULT widths, never from already-
    fitted widths (which caused slow shrinkage each click due to rounding/scrollbar drift)
  • Table ID bumped on each Fit Widths click so ImGui creates fresh column state
- Fix: Transition events (e.g. BL reel wipes) now show correct clip name
  • When TO CLIP NAME is present, it is used as clip_name instead of FROM CLIP NAME
  • FROM CLIP NAME and TO CLIP NAME lines now also appear in the Notes column
  • Example: BL → W001 wipe event now shows "4-1-4T1.WAV" not blank

v260227.1330
- Fix: FPS option now shows "24/23.97" so users can find 23.976 FPS files
- Fix: Fit Widths now works reliably every click (calculates proportional widths directly,
  no longer uses WidthStretch toggle which caused revert on second click)
- Feature: Timeline block color scheme reworked for clearer selection feedback
  • Unselected clips: neutral dark gray (0x3A3A3A) — reduces visual noise
  • Selected clips: full-brightness track color (blue/amber/green)
  • Edge and text label also dim/brighten with selection state

v260227.1300
- Fix: Toolbar row height increased by 14px to prevent scrollbar from clipping buttons
- Fix: FPS 23.976 and 24 merged into single "24" option (match tolerance widened to 0.03)
- Fix: EDL "Fit Widths" button now correctly stretches columns to fill table width
- Feature: Timeline TC ruler now shows HH:MM:SS:FF timecode (uses EDL.seconds_to_tc)
  • Tick spacing increased to 80px minimum to accommodate wider TC labels
  • Sub-second (frame-level) tick intervals added at high zoom
- Feature: Timeline horizontal scrollbar (SliderDouble at bottom of panel)
  • TL_PANEL_H increased from 120 to 136px to accommodate scrollbar
- Feature: Timeline ↔ List bidirectional selection sync
  • Clicking a block in timeline selects all columns of that row in the list
  • List now scrolls to the selected row (SetScrollHereY, clipper disabled for that frame)
  • Clicking a row in list centers timeline view on that row's block
  • Timeline block highlight now reflects any-column selection (sel_has_row)
- Fix: $format token now returns user-friendly names (CMX3600→"EDL", *XML*→"XML", AAF→"AAF")

v260227.1230
- Feature: Level column (COL.LEVEL = 17) for audio/video level dB values
  • New "Level" column positioned between Edit and Dissolve (Edit → Level → Dissolve)
  • Auto-populated from EDL AUDIO/VIDEO LEVEL comments on file load
  • Multiple level values joined with " | " separator
  • Editable by user; included in full-text search
  • Persisted in .clb project file (backward-compatible: p[19])
  • Visible by default; can be toggled in Columns popup

v260227.1400
- Feature: Extra EDL comments preserved in Notes column
  • All * comment lines that are not FROM CLIP NAME / SOURCE FILE / TO CLIP NAME
    are now auto-populated into the Notes column on EDL load
  • Includes: AUDIO LEVEL, VIDEO LEVEL, EFFECTS NAME IS, and any other * lines
  • Multiple extra comments joined with " | " separator
  • Notes remain editable (user can clear/modify freely)
- Feature: audio_levels field on each row (parsed from EDL AUDIO/VIDEO LEVEL comments)
  • row.audio_levels = [{ type, tc, db, reel, src_track }]
  • reel/src_track populated from "(REEL REEL_NAME TRACK)" suffix when present
  • Available for programmatic use (e.g., future auto-level or source-track matching)
- Requires hsuanice_EDL Parser.lua ≥ v0.3.0

v260227.0140
- Feature: Mini-timeline visualization panel
  • Collapsible horizontal panel (toggle "Timeline >>" in EDL header)
  • Events displayed as colored blocks on a horizontal track layout
  • A-tracks: blue, V-tracks: amber, others: green
  • TC ruler with adaptive tick intervals
  • Drag to pan, scroll wheel to zoom (zoom anchored to cursor)
  • Click block → selects + scrolls to corresponding table row
  • Hover → tooltip with clip name, Rec TC In/Out, duration
  • Respects current Track/Reel/Group filters and search box

v260227.0120
- Feature: OpenTimelineIO integration for XML import (FCP7, Resolve)
  • New files: Tools/otio_to_clb.py, Library/hsuanice_OTIO Bridge.lua, Library/json.lua
  • "Load XML..." button now functional: FCP7 XML and DaVinci Resolve XML — NEW
  • load_edl_file() and load_xml_file() share a common _load_timeline_via_otio() helper
  • CLB.loaded_format reflects actual format name (e.g. "FCP7_XML")
  • OTIO Bridge auto-routes .edl → native Lua parser (OTIO CMX3600 adapter loses
    record TC offsets and has dual-track bugs — not suitable for conform workflows)
- Requires for XML: python3 in PATH, opentimelineio installed

v260221.1500
- Perf: Switch get_view_rows() and get_audio_view_rows() from frame-based to dirty-flag cache
  • Previously both functions rebuilt the filtered list every single frame (O(n) per frame)
  • Now the cached result is reused until explicitly invalidated (CLB.cached_rows = nil)
  • Eliminates redundant O(n) filtering on 6,000–10,000+ audio file lists every 60+ Hz frame
  • Removed frame_counter, cached_rows_frame, audio_cached_frame fields entirely

v260221.1400
- Fix: REAPER lag when audio files are loaded
  • Audio table was rendering ALL rows every frame (no virtualization)
  • Added ListClipper to draw_audio_table() — same as EDL table
  • Now only visible rows are rendered per frame (50+ row threshold)

v260221.1128
- Revert: removed all loop rate-cap experiments
  • Rate cap (early return) → context invalidity crash on macOS
  • do_draw content skip → window flickering + buttons unclickable
  • ImGui immediate mode requires full redraw every frame; partial draw
    or skipped frames are not viable in ReaImGui
  • Loop restored to original structure (render everything every defer call)
  • REAPER lag issue deferred — needs a different investigation approach

v260221.1041
- Fix: REAPER lag when CLB is open
  • Added frame rate cap to the defer loop: 30fps when window active, 10fps when idle
  • Previously the loop ran at full REAPER main-thread rate (60+ Hz), consuming
    continuous main-thread time even when nothing was changing
  • Audio metadata loading batch still runs at full defer rate (unaffected)
- Fix: Filter state (Track/Reel/Group checked/unchecked) now saved in .clb project
  • Unchecked tracks, reels, and groups are restored exactly on Open
  • Filter panel visibility (show/hide sidebar panels) also saved and restored
  • Audio panel show/hide state saved and restored

v260221.1019
- Feature: Save / Open project (.clb format)
  • "Save..." button in toolbar: saves full session to a .clb file
    - FPS, drop-frame, track format, audio folder path
    - EDL column order and visibility
    - All EDL sources (path, name, visibility)
    - All event rows (including edits, groups, match status, matched paths)
  • "Open..." button in toolbar: restores session from .clb file
    - All row data restored (edits, groups, match state preserved — no re-matching needed)
    - If audio folder has a cache (.clbcache), audio files auto-restored
    - If no cache, click "Load Audio..." to re-scan
  • File format: CLB_PROJECT_V1 (pipe-delimited, with escape for special chars)

v260220.1535
- Fix: Consolidate track naming rules
  • Audio group → A1, A2, A3 ... (no space)
  • Video group → V1, V2, V3 ... (no space)
  • Other groups → GroupName 1, GroupName 2, ... (space before number)
  • Each group's track numbers restart from 1 independently
- Fix: Conform / Generate Items track order now sorted (natural sort: A1, A2, A10)
  • Tracks appear in correct order in REAPER project after conform

v260209.1846
- Feature: Group as table column (COL.GROUP = 16, hidden by default, enable via Columns popup)
  • Double-click cell to inline edit group name
  • Group column included in search text and undo/redo
- Feature: User-managed Group list in sidebar
  • + button to add new group
  • Right-click group checkbox: Rename / Delete / Assign Selected Rows
  • Delete group: events become unassigned (group = "")
  • Unassigned events shown as "(Unassigned)" in sidebar
- Feature: Consolidate button in toolbar (next to Remove Dups)
  • Consolidates tracks by group via bin-packing (no time overlap)
  • Tracks renumbered as GroupName1, GroupName2, ... globally across all groups
- Feature: Table right-click → Assign Group
  • Applies to all selected rows (multi-select via Shift/Cmd+click)
  • Falls back to clicked row if nothing selected
  • (Unassign) option to clear group
- Fix: All right-click context menu popups now work (rename/delete/batch rename)
  • Root cause: OpenPopup was called inside context menu popup (wrong scope)
  • Fixed with deferred flags for track, reel, and group context menus
- Fix: Cell edit confirmed when clicking elsewhere (not just Enter)
  • Added IsItemDeactivated check so clicking away closes edit mode
- Fix: Column reorder now works via table header drag (EDL + Audio tables)
  • Column editor popup simplified to show/hide only (no drag list)
  • EDL table headers switched from Text() to TableHeader() to enable drag reorder
- Fix: Track name normalization on EDL load (AA→A, VV→V, etc.)
- Fix: Sidebar Reel/Group panel minimum width increased (~5 chars wider)
  • To adjust: draw_reel_filter_sidebar() → max_text_w (line ~4694) and sidebar_w padding (line ~4710)

v260209.1625
- Fix: Remove Duplicates now compares by Reel + Src TC + Rec TC + Clip Name (excludes Track)
  • More robust duplicate detection that ignores track changes
  • Prevents false duplicates when same event appears on multiple tracks

v260207.1600
- Feature: Group Filter in sidebar
  • Auto-groups tracks by prefix: A* → Audio, V* → Video, NONE → NONE
  • Groups panel below Reels panel (Reels 2/3, Groups 1/3 height)
  • Toggle group visibility to filter events by category
  • Hover to see which tracks belong to each group
- Fix: Track Filter right-click menu now works
  • Popup was opening in wrong ImGui scope
- Fix: Reel Filter right-click menu now works
  • Added Rename, Delete, and Batch Rename options

v260207.1500
- Feature: Track Consolidation (like EdiLoad)
  • Right-click Track Filter → "Consolidate Tracks..."
  • Select which tracks to consolidate (e.g., A1~A17 for Dialog)
  • Merges events into minimum tracks without time overlap
  • Uses greedy bin-packing algorithm for optimal track count
  • Specify new track name prefix (e.g., "DX" → DX1, DX2...)
  • Preview shows estimated result before applying

v260207.1400
- Feature: Natural sorting for Track/Reel filters
  • Now sorts correctly: A1, A2, A3... A10 (instead of A1, A10, A2)
- Feature: Batch Rename for Tracks and Reels
  • Right-click any Track/Reel → "Batch Rename All..."
  • Find and replace text across all track/reel names
  • Shows preview count of affected events
- Fix: Track Filter panel height increased
  • Checkboxes no longer cut off by horizontal scrollbar

v260207.1300
- Feature: EDL column editor with drag reorder
  • New "Columns" button in EDL panel header
  • Show/hide individual columns with checkboxes
  • Drag to reorder columns (like Audio panel)
  • "All" / "None" / "Reset" buttons for quick configuration
  • Column settings saved and restored across sessions
- Feature: Scrollable toolbar and filter panels
  • Toolbar rows now scroll horizontally when window is narrow
  • Track Filter panel now scrolls horizontally for many tracks (A1~A30+)
  • Prevents UI clipping on small windows or large track counts
- UI: Toolbar layout improvements
  • Search field moved after FPS selector (more accessible)
  • Track Format field moved to end (rarely modified)

v260207.0900
- Feature: Track naming for multiple EDL imports
  • Tracks renamed with source suffix when multiple EDLs loaded
  • Example: EDL1 tracks A,V → A1,V1; EDL2 tracks A,V → A2,V2
  • Already-numbered tracks preserve number: A2 from EDL1 → A1-2
  • Single EDL keeps original track names
- Feature: Event Number renumbering on EDL export
  • Events are automatically renumbered sequentially (001, 002, 003...)
  • Ensures clean, consecutive numbering regardless of original event numbers
- Feature: Improved Track/Reel filter context menu
  • Right-click only (removed double-click which conflicted with checkbox)
  • Context menu with "Rename..." and "Delete..." options
  • Delete shows confirmation dialog with event count before removing

v260206.2226
- Feature: Simplified toolbar status
  • Removed EDL filename display, shows only "Events: X | Showing: Y"
  • Search box moved to right side of row 2 (after Export EDL)
- Feature: Rename Track/Reel filters
  • Right-click on Track/Reel checkbox for context menu
  • Updates all matching EDL events automatically
  • Tooltip shows right-click hint on hover
- Feature: Audio panel toolbar buttons
  • Fit Widths: auto-adjust column widths based on content
  • Copy (TSV): copy visible rows to clipboard
  • Save .tsv / Save .csv: export to file
  • Cols: show/hide columns popup (no presets needed)
- Feature: Audio table column order
  • New order: Folder, Tape/Roll, Filename, Tracks, Src TC, Scene, Take,
    Ch, Duration, SR, Project, FPS, Speed, Orig File, Description
  • Reset table ID to clear previous column order memory
- Fix: TSV/CSV export handles newlines in Description field
  • TSV: replaces newlines and tabs with spaces
  • CSV: properly quotes fields containing special characters

v260206.2152
- Feature: Reel filter sidebar
  • Moved from horizontal bar to left sidebar panel
  • Displays alongside EDL table for better space utilization
  • Auto-width based on longest reel name
  • Scrollable when many reels present
- Feature: Additional BWF Description parsing
  • sPROJECT, sFRAMERATE, sSPEED, sTRKx (track names), sFiLENAME
  • New audio table columns: Framerate, Speed, Orig Filename, Track Names
- Feature: Audio table sortable and reorderable
  • Click headers to sort by column
  • Drag headers to reorder columns
- Feature: FPS setting now remembered
  • Saves both FPS value and drop-frame flag
  • Persists across script restarts
- Fix: Generate Items / Conform All now respects filters
  • Only processes visible events (filtered by Source/Track/Reel)
  • Hidden events are skipped
- Fix: Track and Reel filters visible by default
- Fix: Cache format updated to support new metadata fields

v260206.1500
- Feature: Reel filter (similar to Sources/Tracks filter)
  • "Reels >>" toggle button in toolbar shows/hides panel
  • Each unique reel listed with event count and checkbox
  • Show All / Hide All buttons for quick toggling
  • Scrollable list for EDLs with many reels
- Feature: Audio metadata cache
  • Caches metadata to disk after first scan
  • Subsequent loads of same folder use cache (instant load)
  • Cache invalidated if files no longer exist
  • Cache file stored in audio folder as !CLB_Audio_Cache.clbcache
- Feature: FPS dropdown selector
  • Common frame rates: 23.976, 24, 25, 29.97 DF, 30, 50, 59.94 DF, 60
  • Automatically sets drop-frame mode for 29.97/59.94
- Feature: Enhanced Track Format tokens
  • Supports: ${track} ${reel} ${clip} ${event} ${format} ${title} ${edit_type}
  • Items grouped by expanded track name (e.g., "${reel} - ${track}")
- Fix: Audio panel toggle
  • "Audio >>" toggle button in toolbar to show/hide audio panel
  • Previously hidden panel could not be shown again

v260206.1300
- Feature: Conform Matched functionality
  • "Conform All" button: insert matched audio files as items
  • "Conform Sel" button: conform selected rows only
  • Multiple matches create multiple takes on the same item
  • Source offset calculated from EDL src_tc_in vs audio BWF TimeReference
  • Preserves metadata as P_EXT fields including matched file path
- Note: Original "Generate Items" kept for empty item creation

v260206.1230
- Fix: Improved metadata reading for audio files
  • Check file type before reading metadata (WAV/AIFF/W64 only)
  • Convert BWF TimeReference (samples) to timecode string
  • Parse BWF Description for Scene/Take/Tape/Reel (EdiLoad format)
  • Reorganized audio table columns for conform workflow:
    Filename | Src TC | Scene | Take | Tape/Roll | Folder | Duration | SR | Ch | Project | Description

v260206.1200
- Feature: Audio file matching
  • "Load Audio..." button to select folder with audio files
  • Reads BWF/iXML metadata (scene, take, tape, reel, timereference, etc.)
  • Recursive folder scanning (configurable)
  • Auto-matching with multiple strategies:
    1. Clip name ↔ filename exact match
    2. Source file ↔ filename exact match
    3. Reel ↔ tape/reel metadata + partial name match
    4. Fuzzy partial name match
  • "Match All" button to re-run matching
  • "Clear Audio" button to reset audio panel
- Feature: Split-view UI
  • Draggable splitter between EDL and Audio tables
  • Audio files table shows: filename, folder, duration, SR, channels,
    scene, take, tape, reel, timereference, description, project
  • Search filter for audio files
  • Progress indicator during async loading
- Feature: New EDL columns
  • Match Status: "Found" / "Multiple" / "Not Found"
  • Matched File: shows matched audio file path


v260203.2241
- Feature: Remove Duplicates button in toolbar
  • Detects duplicates by composite key (reel + src TC in/out + rec TC in/out + clip name)
  • Shows confirmation dialog with duplicate count before removing
  • Updates per-source event counts after removal
  • Supports undo/redo
- Fix: Sources panel now scrollable when many EDLs are loaded
  • Wraps checkbox list in scrollable child region (max 6 visible rows)

v260203.2216
- Feature: Multi-file EDL selection in file dialog
  • Uses JS_Dialog_BrowseForOpenFiles for multi-select (shift/cmd-click)
  • Handles macOS (full paths) and Windows (directory + filenames) return formats
  • Falls back to single-file dialog if JS extension unavailable
- Feature: EDL Sources panel with visibility filtering
  • "Sources >>" toggle button in toolbar shows/hides panel
  • Each loaded EDL listed with filename, event count, and checkbox
  • Show All / Hide All buttons for quick toggling
  • Unchecked sources are filtered from table display
- Fix: Multi-file path parsing on macOS (was concatenating full paths as directory + filename)

v260203.1854
- Feature: Multiple EDL import support
  • Loading a second EDL when events already exist prompts Replace / Append / Cancel
  • Append adds new events to the existing list with unique GUIDs
- Feature: Generated items now write Reel and Source TC In/Out to item notes
  • Human-readable format: "Reel: xxx / Src In: xx:xx:xx:xx / Src Out: xx:xx:xx:xx"
  • P_EXT metadata fields retained for programmatic access

v260203.1845
- Fix: Single vertical scrollbar (table only, no duplicate window scrollbar)
  • Window now uses NoScrollbar + NoScrollWithMouse flags
  • Table height correctly uses available height from GetContentRegionAvail
- Fix: Selection highlight uses ImGui_Selectable instead of DrawList
  • Resolves ImGui_GetColumnWidth nil error and Missing EndTable cascade

v260203.1500
- Initial release: CMX3600 EDL parser, table UI, item generation, EDL export
```
