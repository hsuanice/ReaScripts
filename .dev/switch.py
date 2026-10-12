#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""Point REAPER at a migrated batch (run only while REAPER is closed). Local dev tool.

usage (from the repo root):
  python3 .dev/switch.py BATCH.json [--dry]

1. reaper-kb.ini: every "hsuanice Scripts/<old path>" of the batch -> "<category>/<file>"
   (action IDs unchanged, so shortcuts / toolbars / custom actions keep working).
   The file is read and written as bytes so its CRLF line endings are preserved.
2. the old copies move to Archive/_backup/<version>----moved to <category>/
"""
import json, os, re, shutil, subprocess, sys

cfg = json.load(open(sys.argv[1], encoding="utf-8"))
DRY = "--dry" in sys.argv
RES = os.path.expanduser("~/Library/Application Support/REAPER")
KB = os.path.join(RES, "reaper-kb.ini")
CAT = cfg["category"]

if not DRY and subprocess.run(["pgrep", "-f", "/Applications/REAPER.app/"], capture_output=True).returncode == 0:
    sys.exit("REAPER is still running — close it first.")  # portable test installs have their own kb.ini

srcs = [f["src"] for p in cfg["packages"] for f in p["files"]]
for s in srcs:
    if not os.path.exists(os.path.join(CAT, os.path.basename(s))):
        sys.exit(f"new file missing: {CAT}/{os.path.basename(s)}")

kb = open(KB, "rb").read()
total = 0
for s in srcs:
    old = f'"hsuanice Scripts/{s}"'.encode()
    new = f'"hsuanice Scripts/{CAT}/{os.path.basename(s)}"'.encode()
    n = kb.count(old)
    total += n
    print(f"kb.ini {n}x  {s}")
    kb = kb.replace(old, new)
if not DRY:
    open(KB, "wb").write(kb)

ver = re.search(rb"@version (\S+)", open(os.path.join(CAT, os.path.basename(srcs[0])), "rb").read()).group(1).decode()
dest = os.path.join("Archive", "_backup", f"{ver}----moved to {CAT}")
for s in srcs:
    if os.path.exists(s):
        if not DRY:
            os.makedirs(dest, exist_ok=True)
            shutil.move(s, os.path.join(dest, os.path.basename(s)))
print(f"{'DRY RUN — nothing written. ' if DRY else ''}kb.ini paths updated: {total}; old copies -> {dest}")
