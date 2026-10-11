# hsuanice_Metadata Embed.lua — Changelog

Metadata Embed - BWF MetaEdit helpers

History before 26.1011.2142 (moved out of the script header; last header version: `261007.1210`).

```text
261007.1210 - Fixed TR_Write(): writing --TimeReference=0 to a WAV with
           no pre-existing bext chunk was a silent no-op — bwfmetaedit
           prunes the whole bext record whenever every field in it would
           end up at its default value, so a brand-new file never got a
           TimeReference at all (confirmed directly: even writing a
           non-zero value first then 0 right after deleted the chunk
           again). TR_Write() now takes an optional 4th `originator`
           argument; when set, it's written in the SAME command, which
           keeps the chunk from being pruned. CLB.generate_reference_media
           passes "hsuanice CLB" so its reference file's TimeReference=0
           actually persists and is readable by metadata tools.

261007.1128 - Added Write_iXML_Raw(cli, wav_path, xml_text): writes a
           caller-supplied iXML document (not copied from an existing
           source WAV) via the same sidecar import mechanism the
           Copy_iXML* functions use, with the same verify-after-import
           check. For hsuanice_Conform List Browser.lua's new
           CLB.generate_reference_media, which builds a brand-new
           <BWFXML> document from EDL row data (Scene/Take/Tape/
           TRACK_LIST) for a freshly generated reference WAV with no
           source file to copy metadata from.

260824.1900 - Taipei local time cleanup pass.
           - Removed ad-hoc TRK debug noise and stale channel-guessing path.
           - Added direct-copy metadata flow for Ediload Split full-set workflow.
           - This mode assumes the source metadata is already complete and correct.
           - No metadata parsing / track-name remap required before embed-back to target files.
           - Poly-to-mono embed now preserves every source slot, including empty channels.
           - Mono output N receives source TRACK_LIST slot N with CHANNEL_INDEX=N.

260824.0153 - Normalize critical CORE text fields before write.
           - Trim Originator / OriginatorReference / OriginationDate / OriginationTime.
           - Prevent split-tool leading/trailing spaces from being preserved in embed target.

260824.0152 - Added Analyze_Metadata_Fields() and selective CORE field filtering.
           - Copy_Metadata() accepts copy_ixml=false for non-iXML selective writes.

260821.2036 - Tolerate non-fatal bwfmetaedit warnings on CORE/TR reads
  - Copy_CORE() no longer aborts solely because bwfmetaedit exits non-zero
    (e.g. "invalid Wave: iXML, missing padding byte"); it now uses the
    recovered --continue-errors report as long as output was produced.
  - TR_Read() now passes --continue-errors so TimeReference can still be
    read from source files with the same non-fatal chunk warning, instead
    of returning nil and causing "TR result: SKIP (cannot read src TR)".
  - Root cause of the reported CORE/TR FAILs: some source WAVs have an
    odd-sized chunk missing its pad byte, which bwfmetaedit flags as an
    error (exit code 1) even though it still emits a usable XML report.

260718.1728 - Synced channel-aware APIs with production fixes from Embed script
  - Build_Channel_Context now prefers TRACK_LIST slot order for interleave mapping and returns channel_index.
  - Copy_iXML now validates post-import iXML by re-exporting destination sidecar.
  - Missing source iXML sidecar is now treated as FAIL (not success).
  - Patch_iXML_For_Channel preserves non-channel iXML blocks and writes channel_index in TRACK_LIST.
  - Copy_CORE now normalizes sTRK/sTRKALL textual tokens for mono channel metadata consistency.
  - Added richer command output logging for export/import/verify operations.

260711.2215 - Added reusable channel-aware metadata copy APIs
  - Added Build_Channel_Context() for mono-of-N channel resolution from I_CHANMODE and source TRACK_LIST.
  - Added Copy_iXML(), Copy_CORE(), Set_iXML_Embedder(), and Copy_Metadata() APIs.
  - Added Copy_Take1_To_Active() as a workflow-friendly entry point for render/glue pipelines.
  - Purpose: let explode/render scripts reuse the same metadata re-embed logic.

0.3.0 (2025-10-30) - Initial Public Beta Release
  BWF MetaEdit helpers library featuring:
  - Shell quoting for safe CLI execution
  - iXML sidecar normalization
  - TimeReference read/write operations
  - Post-embed refresh (offline->online, rebuild peaks)
  - Integration with RGWH Core for BWF TimeReference embed

Internal Build v251010_0037
  - Rationale: Refresh_Items already does offline->online->rebuild peaks.
  - Prevent redundant peak rebuild (40441) after every single item refresh.

v250926_2018 (2025-09-26)
  - Change: Refresh_Items now uses 42356 (Toggle force media offline) twice (offline→online), then 40441 (Rebuild peaks), to force immediate BWF header (TimeReference) reload.
  - Rationale: 40440/40439 were insufficient in some cases after render with newly embedded TC.

v0.3.0 (2025-09-25)
  - Added: CLI_Resolve() — resolve & persist BWF MetaEdit path
    (ExtState: hsuanice_TCTools/BWFMetaEditPath; Apple Silicon default
     /opt/homebrew/bin/bwfmetaedit is tried first).
  - Added: TR_Read(), TR_Write() — read/write BWF TimeReference (samples)
    via --out-xml=- / --TimeReference= with safe quoting (exec_shell).
  - Added: SecToSamples() — floor+epsilon sample quantization to prevent +1 jitter.
  - Added: TR_PrevToActive(), TR_FromItemStart() — handle-aware TC math using
    SrcStart (D_STARTOFFS) and cross-SR safety; negative results clamped to 0.
  - Added: Refresh_Items() — batch offline→online→rebuild peaks for items/takes.
  - Kept: write_bext_umid(), refresh_media_item_take(), shell helpers (unchanged).
  - Notes: TC/TimeReference math here is the single source of truth; RGWH and tools
    should call this library. Backward-compatible insertion; UMID workflows unaffected.


v0.2.4 (2025-09-12)
  - Changed: E.write_bext_umid() now returns the actual command string
    used for execution, in addition to (ok, code, out).
    * Return signature: ok, code, out, cmd
    * cmd is the fully formatted bwfmetaedit command.
  - Purpose: allows calling tools to log the exact command
    instead of reconstructing it, avoiding stale or incorrect flags.
  - No change to write logic (still uses only --UMID=).
  - Maintains compatibility with v0.2.3 behavior if cmd return is ignored.

v0.2.2 (2025-09-12)
  - Improved: E.write_bext_umid() now aggressively cleans input
    before validation:
      * Strips all non-hex characters.
      * Forces uppercase to ensure consistent 64 hex chars.
  - Safer: Prevents hidden characters or dash-separated UMIDs
    from being rejected incorrectly.
  - No change to CLI execution or return values.
  - Compatible with v0.2.1 calling convention
    (cli_path, wav_path, umid_hex).
v0.2.1 (2025-09-12)
  - Changed: E.write_bext_umid() now requires an explicit bwfmetaedit CLI path
    and uses ExecProcess (non-blocking) instead of os.execute.
    * Usage: E.write_bext_umid(cli_path, wav_path, umid_hex)
    * CLI path can be resolved via the same logic as BWF TimeReference tool.
  - Improved: sh_wrap() and exec_shell() helpers added (consistent with TR tool).
  - Notes:
    * Only writes to BWF bext:UMID; iXML UMID is left to recorders.
    * Requires BWF MetaEdit installed and accessible (path must be provided).
  - No breaking changes besides function signature update.
```
