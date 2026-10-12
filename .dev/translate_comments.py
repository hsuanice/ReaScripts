#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""Replace the comment part of given lines (used to translate comments to English).

usage: python3 .dev/translate_comments.py TRANSLATIONS.json

TRANSLATIONS.json = {"path/file.lua": {"<line number>": "new comment text", ...}, ...}

For each listed line, everything after the first "--" is replaced by "-- <new text>"
(the code before it is kept byte for byte). Use "@@LINE:<full line>" as the value to replace the
whole line instead (for lines inside a --[[ ]] block). Afterwards .dev/same_code.py proves the
compiled code did not change, and no CJK characters may remain on the edited lines.
"""
import json, os, re, shutil, subprocess, sys, tempfile

CJK = re.compile(r"[　-〿一-鿿＀-￯]")
data = json.load(open(sys.argv[1], encoding="utf-8"))
ok = True
for path, edits in data.items():
    lines = open(path, encoding="utf-8").read().split("\n")
    backup = tempfile.mktemp(suffix=".lua")
    shutil.copy(path, backup)
    for ln_s, text in edits.items():
        i = int(ln_s) - 1
        line = lines[i]
        if text.startswith("@@LINE:"):
            lines[i] = text[len("@@LINE:"):]
        else:
            k = line.find("--")
            if k < 0:
                sys.exit(f"{path}:{ln_s}: no comment on this line: {line!r}")
            lines[i] = line[:k] + "-- " + text
        if CJK.search(lines[i]):
            sys.exit(f"{path}:{ln_s}: still contains CJK: {lines[i]!r}")
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    r = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "same_code.py"), backup, path])
    if r.returncode != 0:
        shutil.copy(backup, path)
        print(f"  -> reverted {path}")
        ok = False
    left = sum(1 for l in lines if CJK.search(l))
    print(f"  {len(edits)} lines translated, CJK lines left: {left}")
sys.exit(0 if ok else 1)
