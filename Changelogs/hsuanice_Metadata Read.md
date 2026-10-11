# hsuanice_Metadata Read.lua — Changelog

Metadata Read (reader / normalizer / tokens)

History before 26.1011.2142 (moved out of the script header; last header version: `0.3.11`).
Newer entries are kept in each release's `@changelog` and shown in ReaPack.

```text
v0.3.11 (2026-10-02)
  - Fixed: a channel whose TRACK_LIST entry exists but has an empty name now
    resolves to an empty track name again, instead of borrowing the first
    non-empty name in the list. M.resolve_trk_name() (added in v0.3.10)
    ended with an unconditional "first non-empty name" fallback, which
    undid the v0.3.9 fix: on Cantar polys that record every channel even
    when unused (2026-01 "FISHTOWN" cards), channels 3-10 — empty in
    TRACK_LIST — all read as "CMIT 5U" ($trk, Meta Trk Name in Item List
    Browser/Editor, Reorder Monitor). The first-non-empty fallback now only
    applies when the file has no TRACK_LIST at all; a file with one describes
    all of its channels, so an empty or missing entry (also in the
    compressed AATON lists REAPER can expose) means "no name".
  - Cached names written by the old behaviour are discarded by Metadata
    Cache 261002 (CACHE_VERSION 2.3).

v0.3.10 (2026-09-11)
  - Added: M.resolve_trk_name(fields, sanitize) — single-channel track name
    resolver (meta_trk_name-first, falls back to interleave-list
    reconstruction), factored out of $trk's single-name path.
  - Fixed: $trk (single-name path) now prefers fields.meta_trk_name before
    reconstructing from TRK#= pairs in the description, fixing empty $trk
    after a Metadata.cache hit for recorders that don't embed per-channel
    TRK#= in the description (e.g. Cantar/Aaton). The poly "no explicit
    interleave → full track list" branch is unchanged.
  - Consolidated: "Rename Active Take from File Metadata.lua" and "Rename
    Source File from Metadata.lua" no longer keep local copies of
    $trk/$trkN/$trkall/$interleave/$chnum/$counter:N/$srcbaseprefix:N/
    $srcbasesuffix:N — both now delegate to this library.

v0.3.9 (2026-08-24)
  - Fixed: explicit interleave slots with empty TRACK_LIST names no longer
    fall back to the first non-empty name.
  - Fixed: recorder channel number no longer remaps via compacted AATON
    ACTIVE order (uses TRACK_LIST interleave->channel mapping first).

v0.3.8 (2026-08-24)
  - Added canonical TRACK_LIST reader via BWF MetaEdit XML output.
  - Multichannel files now prefer CLI TRACK_LIST for stable cross-recorder parsing.
  - REAPER metadata keys remain as fallback when CLI is unavailable.

v0.3.7 (2026-08-24)
  - Added recorder-family aware mapping policy (AATON / Sound Devices / Sonosax / generic).
  - AATON ACTIVE-slot remap now applies only to AATON-family files.
  - Sound Devices and Sonosax stay on strict TRACK_LIST index mapping.

v0.3.6 (2026-08-24)
  - Enforced deterministic interleave mapping priority:
    TRACK_LIST.INTERLEAVE_INDEX first, no compressed-slot fallback.
  - Only falls back to sequential names when interleave indexes are absent.

v0.3.5 (2026-08-24)
  - Fixed: interleave track-name map now uses AATON ACTIVE slot mapping
    when available and unambiguous.
  - Prevents compressed TRACK_LIST names from shifting MIX L/R to wrong slots.

v0.3.4 (2026-08-24)
  - Fixed: recorder-channel detection for exploded poly items can use
    AATON ACTIVE slot mapping instead of assuming interleave == channel.
  - Preserves previous behavior when ACTIVE metadata is unavailable.

v0.3.3 (2026-08-24)
  - Fixed: TRACK_LIST parsing now prefers full IXML XML chunk before per-key reads.
  - Fixed: preserves empty TRACK_LIST slots so interleave/channel mapping does not shift.
  - Improved: channel mapping remains stable for AATON-style poly metadata with sparse names.

v0.3.2 (2026-07-18)
  - Changed: $trk now follows Pro Tools-like display logic.
    * Poly context (no explicit mono-of-N interleave): return full track list (same as $trkall).
    * Mono/specific-channel context: return single resolved track name.
  - Added __has_explicit_interleave flag from I_CHANMODE for safer display decisions.

v0.3.1 (2026-07-18)
  - Fixed: mono rendered files now resolve $trk from iXML TRACK_LIST first.
  - Improved: TRACK_LIST parsing now stores channel_index + interleave_index.
  - Improved: interleave name list prefers iXML INTERLEAVE_INDEX mapping.
  - Fixed: trk_name_and_channel() no longer returns empty due placeholder list.
  - Behavior: poly keeps multi-track visibility; mono/specific-channel resolves to single track name.

v0.3.0 (2025-09-12)
  - Added: UMID (SMPTE ID) ingestion from BWF metadata.
    * Reads BWF:UMID (or UMID) via REAPER GetMediaFileMetadata.
    * Normalizes to strict 64-hex uppercase.
  - Added tokens: ${umid} (64-hex uppercase) and ${umid_pt}
    (Pro Tools style 26-6-16-12-4, lowercase with dashes).
  - UI/Fields: UMID values are included in the normalized field map
    returned by collect_item_fields(), so they are available to all
    rename/monitor/sort consumers without additional wiring.
  - Notes: No CLI dependency; if REAPER does not expose BWF:UMID on a
    given build, tokens will be empty (future optional CLI fallback planned).
v0.2.1 (2025-09-01)
  - Quality & robustness (no breaking changes from 0.2.0):
    * Token engine polish: consistent handling for ${trk}/${trkN}/${trkall},
      ${interleave}/${chnum} (with aliases ${interum}/${channelnum});
      safer UTF-8 slice helpers for prefix/suffix tokens.
    * BWF Description normalization: more tolerant key mirroring
      (dXXXX/sXXXX → XXXX; accepts upper/lower mixed cases).
    * Diagnostics: M.compute_interleave_diag() more defensive when iXML/TRK
      data is sparse.
    * Module hygiene: ensured clean header and explicit `return M`.
v0.2.0 (2025-09-01)
  - Integrated token engine and diagnostics:
    * Added M.expand() and M.empty_tokens_in_template():
      - Supports $trk / $trkN / $trkall
      - Supports ${interleave} / ${chnum} (from I_CHANMODE and TRK# mapping)
      - Supports ${counter:N}, ${srcbaseprefix:N}, ${srcbasesuffix:N}
    * Added UTF-8-safe substring helpers (used by prefix/suffix tokens).
    * Added M.compute_interleave_diag(fields, item) to expose index/total/name/all.
  - Field normalization:
    * M.collect_item_fields() now returns srcpath/srcfile/srcbase/srcext/srcdir,
      samplerate/channels, __trk_table, __chan_index, __trk_name, etc.
    * BWF/Description mirrors (dXXXX/sXXXX) are normalized to XXXX (both upper/lower keys).
    * Automatically populates TRK# table (trk1..trk64) for tokens/mapping.
  - Interleave mapping is more robust:
    * M.guess_interleave_index() clamps to 1..N (N derived from source channel count).
    * M.resolve_trk_by_interleave() prefers iXML TRACK_LIST; falls back to sTRK# order;
      if neither is present, returns the first non-empty name.
  - Performance:
    * Retains run-level metadata cache (M.begin_batch/M.end_batch) to avoid redundant I/O.
  - Compatibility:
    * Metadata reading is limited to PCM containers (WAV/W64/AIFF); other sources are skipped safely.

v0.1.0 (2025-09-01)
  - Initial release (read-only parsing & normalization):
    * Unwrap SECTION to get the real parent source.
    * Cached GetMediaFileMetadata lookups.
    * Read iXML TRACK_LIST (CHANNEL_INDEX/NAME).
    * When TRACK_LIST is missing, fall back to BWF/Description sTRK#=Name (EdiLoad split compatible).
    * Basic Interleave ↔ TRK# mapping to power $trk/$trkall.
```
