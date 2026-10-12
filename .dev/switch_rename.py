#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""After .dev/rename.py: repoint reaper-kb.ini to the renamed files (REAPER must be closed).

usage: python3 .dev/switch_rename.py RENAME.json [--dry]

For every SCR line of a renamed script: the path and the "Custom: <file>" label are updated,
the action ID is kept, so shortcuts / toolbars / custom actions keep working.
Read and written as bytes so the CRLF line endings are preserved.
"""
import json, os, subprocess, sys

ren = json.load(open(sys.argv[1], encoding="utf-8"))
DRY = "--dry" in sys.argv
KB = os.path.expanduser("~/Library/Application Support/REAPER/reaper-kb.ini")
if not DRY and subprocess.run(["pgrep", "-f", "/Applications/REAPER.app/"], capture_output=True).returncode == 0:
    sys.exit("REAPER is still running — close it first.")

kb = open(KB, "rb").read()
total = 0
for old, new in ren.items():
    op, np = f'"hsuanice Scripts/{old}"'.encode(), f'"hsuanice Scripts/{new}"'.encode()
    ol = f'"Custom: {os.path.basename(old)}"'.encode()
    nl = f'"Custom: {os.path.basename(new)}"'.encode()
    n = kb.count(op)
    if n:
        kb = kb.replace(op, np).replace(ol, nl)
    total += n
    print(f"{n}x  {old}")
if not DRY:
    open(KB, "wb").write(kb)
print(f"{'DRY RUN — ' if DRY else ''}paths updated: {total} of {len(ren)} renamed files")
