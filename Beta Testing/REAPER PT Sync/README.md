# Reaper → Pro Tools Spot (v1)

Single-direction spot from Reaper to Pro Tools, using BWF Time Reference + "Spot to Original Time Stamp", **without re-rendering audio**.

## What v1 does

For each selected item in Reaper:

- If the item == its full source `.wav` (no trim, no playrate change, has a `bext` chunk) → eligible
- If the item position **already matches** the source's BWF Time Reference → use the source file as-is
- If the item position **differs** from the BWF TC → copy the file to `<project>/_PT_sync/` and patch the bext Time Reference in the **copy** (the original is never touched)
- Then on the PT side: `select_tracks_by_name` → `import_audio` (TC-based) → `rename_selected_clip` to match Reaper's take name (with `rename_file=False`)

What v1 does **not** do:

- Trimmed/edited items (only a slice of the source is used) → render first
- Playrate ≠ 1.0 → render first
- Sources without a `bext` chunk → render first (Reaper's render dialog has a "Embed timecode" option)
- Non-WAV sources

## Setup

### 1. Get py-ptsl

```sh
pip install py-ptsl
```

### 2. Get an Avid Developer SDK certificate (one-time, free)

Sign up at https://developer.avid.com/, register an app, install the certificate. Without this, PTSL connections will be rejected.

### 3. File layout

Put both files **in the same folder**, anywhere you like:

```
my_scripts/
├── reaper_spot_to_pt.lua
└── ptsync_oneshot.py
```

The Lua script looks for `ptsync_oneshot.py` next to itself.

### 4. Install the Reaper script

In Reaper: `Actions → Show action list → ReaScript: Load... → reaper_spot_to_pt.lua`. Optionally bind it to a shortcut (I'd suggest a single-key like `S` in the Media Item context, or `⌥S`).

### 5. Configure (optional)

Open `reaper_spot_to_pt.lua`, edit the top:

```lua
local PYTHON_CMD = "python3"  -- "python" on Windows if no python3 alias
```

If `python3` isn't on your PATH, put the absolute path here:
- macOS Homebrew: `/opt/homebrew/bin/python3` or `/usr/local/bin/python3`
- Windows: `C:\\Path\\To\\python.exe`

## Usage

1. **In Pro Tools**: open the destination session. Make sure the destination tracks exist and their names exactly match the Reaper track names. (Suggested convention: name them `REAPER<>PT_01`, `REAPER<>PT_02`, … on both sides.)

2. **In Reaper**: select one or more items on tracks whose names match a track in PT.

3. Run the action `Spot selected items to Pro Tools`.

4. The Reaper console will show what was patched / skipped, then hand off to Python. Python connects to PT, spots each item, and prints OK/FAIL per item.

## Verifying it works (smoke test)

1. Make a fresh Reaper project. Save it.
2. Add a track, name it `REAPER<>PT_01`.
3. Drag a BWF .wav onto it (any field recording with timecode).
4. In PT: new session, add a track named exactly `REAPER<>PT_01`.
5. In Reaper: select the item, run the action.
6. Expected: the file appears in PT on `REAPER<>PT_01` at a timeline position equal to the Reaper item's position. PT clip name == Reaper take name.

Then move the Reaper item to a different position and re-run. The second time you should see a copy land in `<project>/_PT_sync/`, with its bext patched. PT spots the copy at the new position.

## Troubleshooting

**"Bridge command failed"**
Check Reaper console for the exact `Running:` line, copy it, run it manually in a terminal — Python's stderr will tell you why.

**"py-ptsl not installed"**
`pip install py-ptsl`. If you have multiple Pythons, make sure the `pip` and the `python3` you're invoking from Lua are the same interpreter.

**"Could not open PTSL engine"**
- Is Pro Tools running with a session open?
- Is your dev certificate installed? On macOS check `~/Library/Application Support/Avid/Pro Tools/...` for it.

**"select_tracks_by_name failed" or clip lands on the wrong track**
PT track name must be an **exact** byte-for-byte match (case, spaces, the `<>` characters all matter). Check for trailing spaces.

**Clip imported but went to Clip List, not the track / not at the right TC**
This is the known soft spot in py-ptsl's `import_audio`. See the comment block at the bottom of `ptsync_oneshot.py` — there's a lower-level approach using `PTSL_pb2.ImportAudioRequestBody` with explicit `audio_options=IAO_TC, location=IL_Spot` flags. The exact field names depend on your installed PTSL version; check `PTSL_pb2.py` to confirm and adapt.

**Item skipped: "trimmed/edited or playrate != 1.0"**
That's expected for v1. Either: (a) glue / render the item in Reaper first so it becomes a fresh full-source file with a fresh bext, or (b) wait for v2 which will handle trimmed sources via `set_timeline_selection` + `trim_to_selection` on the PT side.

**Item skipped: "no bext chunk"**
Your source isn't a BWF — it's a plain WAV. Render it through Reaper with "Embed timecode" enabled in the render dialog.

## Architecture, briefly

```
┌──────────────────────────┐         ┌──────────────────────────┐
│ Reaper                   │         │ Pro Tools                │
│ ┌────────────────────┐   │         │   ┌──────────────────┐   │
│ │ reaper_spot_to_pt  │   │         │   │ open session     │   │
│ │ .lua (action)      │   │         │   └──────────────────┘   │
│ │                    │   │         │            ▲             │
│ │ - analyze items    │   │         │            │ PTSL gRPC   │
│ │ - patch bext in    │   │  spawn  │   ┌──────────────────┐   │
│ │   sync copies      │   │ ──────► │   │ ptsync_oneshot   │   │
│ │ - write manifest   │   │         │   │ .py              │   │
│ │ - exec python      │   │         │   │ (subprocess)     │   │
│ └────────────────────┘   │         │   └──────────────────┘   │
└──────────────────────────┘         └──────────────────────────┘
        writes:                                reads:
   _ptsync_manifest.json   ──────────────►   manifest, then
   (in project folder)                       drives PTSL calls
```

## Where the BWF byte-fiddling actually happens

In `reaper_spot_to_pt.lua`, look for `read_bwf_time_reference` and `write_bwf_time_reference`. The bext chunk's TimeReferenceLow/High pair lives at offset 338 from the start of the chunk's data (i.e., 8 bytes after the `bext` chunk header). Two LE uint32s, combined as `high * 2^32 + low` to get total samples since midnight. Audio data is never touched.

## Roadmap

- **v2**: trimmed/edited items via PT-side `set_timeline_selection` + `trim_to_selection`
- **v2**: long-running daemon mode so the PTSL connection isn't reopened each time
- **v3**: PT → Reaper direction (read PT clips via `track_list` + clip queries, reconcile in Reaper)
