#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""Prove that two versions of a Lua file differ only in comments.

usage: python3 .dev/same_code.py OLD.lua NEW.lua

Both files are compiled with `luac -s` (debug info stripped, so comments and line numbers do not
matter) and the bytecode is compared. Identical bytecode = only comments / whitespace changed.
Lines that this Mac's Lua 5.5 luac rejects ("attempt to assign to const variable", a false positive
for loop variables reassigned in the loop) are patched identically in both temp copies first.
"""
import os, re, subprocess, sys, tempfile


def compile_stripped(src_text, tag):
    d = tempfile.mkdtemp()
    for _ in range(50):  # patch luac 5.5 const-loop-variable false positives one by one
        p = os.path.join(d, tag + ".lua")
        open(p, "w", encoding="utf-8").write(src_text)
        out = os.path.join(d, tag + ".luac")
        r = subprocess.run(["luac", "-s", "-o", out, p], capture_output=True, text=True)
        if r.returncode == 0:
            return open(out, "rb").read()
        m = re.search(r":(\d+): attempt to assign to const variable '(\w+)'", r.stderr)
        if not m:
            sys.exit(f"luac failed ({tag}): {r.stderr.strip()}")
        ln, var = int(m.group(1)), m.group(2)
        lines = src_text.split("\n")
        # rename the assignment target on that line so it no longer hits the loop variable
        # also handles multiple assignment ("_, x = ...") and "_" (no \b before underscore)
        patched = re.sub(rf"(?<![\w.]){re.escape(var)}(?=\s*(,|=(?!=)))", f"__luac55_{var}", lines[ln - 1], count=1)
        if patched == lines[ln - 1]:
            sys.exit(f"cannot patch luac false positive at line {ln}: {lines[ln - 1].strip()}")
        lines[ln - 1] = patched
        src_text = "\n".join(lines)
    sys.exit("too many const-variable patches")


old = open(sys.argv[1], encoding="utf-8").read()
new = open(sys.argv[2], encoding="utf-8").read()
a, b = compile_stripped(old, "old"), compile_stripped(new, "new")
if a == b:
    print(f"SAME CODE  {os.path.basename(sys.argv[2])}")
else:
    print(f"CODE DIFFERS  {os.path.basename(sys.argv[2])}")
    sys.exit(1)
