#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""Rename published scripts (local dev tool). Run from the repo root, REAPER may stay open;
afterwards run .dev/switch_rename.py with REAPER closed to repoint reaper-kb.ini.

usage: python3 .dev/rename.py RENAME.json DESCRIPTIONS.json

RENAME.json        {"old/path.lua": "new/path.lua", ...}
DESCRIPTIONS.json  {"new/path.lua": "new @description for a package file", ...}

1. git mv every file (case-only renames go through a temp name) + its Changelogs/*.md
2. replace every old file name with the new one in published .lua files (and in the
   local helper scripts listed in EXTRA_TEXT_FILES) — @provides, dofile paths, docs
3. set the new @description of package files
4. bump every renamed file with .dev/bump.py and a "Renamed" changelog bullet
   (package files also get "reinstall + re-assign shortcuts")
"""
import json, os, re, subprocess, sys

ren = json.load(open(sys.argv[1], encoding="utf-8"))
descs = json.load(open(sys.argv[2], encoding="utf-8"))
EXTRA_TEXT_FILES = ["Beta Testing/hsuanice_Track and Razor Item Link Monitor.lua"]
CATS = ["Rendering", "Items Editing", "Items Properties", "Selection", "Tracks", "Metadata",
        "Conform", "Various", "Library"]


def git(*a):
    subprocess.run(["git", *a], check=True)


def gmv(src, dst):
    if src.lower() == dst.lower():  # case-only rename on a case-insensitive disk
        tmp = dst + ".tmp-rename"
        git("mv", src, tmp)
        git("mv", tmp, dst)
    else:
        git("mv", src, dst)


# 1) move files + changelogs
for old, new in ren.items():
    gmv(old, new)
    om = os.path.join("Changelogs", os.path.basename(old)[:-4] + ".md")
    nm = os.path.join("Changelogs", os.path.basename(new)[:-4] + ".md")
    if os.path.exists(om):
        gmv(om, nm)
        t = open(nm, encoding="utf-8").read()
        first, _, rest = t.partition("\n")
        if first.startswith("# "):
            t = (f"# {os.path.basename(new)} — Changelog\n\n"
                 f"(formerly `{os.path.basename(old)}`)\n" + rest)
            open(nm, "w", encoding="utf-8").write(t)

# 2) replace old names everywhere they are referenced (longest first)
pairs = sorted(((os.path.basename(o), os.path.basename(n)) for o, n in ren.items()),
               key=lambda p: -len(p[0]))
targets = [os.path.join(c, f) for c in CATS if os.path.isdir(c)
           for f in os.listdir(c) if f.endswith(".lua")] + EXTRA_TEXT_FILES
edited = 0
for f in targets:
    if not os.path.exists(f):
        continue
    s = open(f, encoding="utf-8").read()
    o = s
    for a, b in pairs:
        s = s.replace(a, b)
    if s != o:
        open(f, "w", encoding="utf-8").write(s)
        edited += 1
print(f"references updated in {edited} files")

# 3) package descriptions
for path, d in descs.items():
    s = open(path, encoding="utf-8").read()
    s2 = re.sub(r"^@description .*$", "@description " + d.replace("\\", "\\\\"), s, count=1, flags=re.M)
    assert s2 != s or ("@description " + d) in s, path
    open(path, "w", encoding="utf-8").write(s2)

# 4) bump with a rename note
for old, new in ren.items():
    head = open(new, encoding="utf-8").read(4000)
    is_pkg = not re.search(r"^@noindex", head, re.M)
    on, nn = os.path.basename(old)[9:-4], os.path.basename(new)[9:-4]
    bullets = [f"Renamed to \"{nn}\" (was \"{on}\") as part of the 2026-10-12 naming clean-up."]
    if is_pkg:
        bullets.append("Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.")
    subprocess.run([sys.executable, ".dev/bump.py", new, *bullets], check=True)
