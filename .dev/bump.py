#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""Bump a ReaPack script for a new release (local dev tool, not published).

usage (from the repo root):
  python3 .dev/bump.py FILE "bullet" ["bullet" ...]

- @version  -> current Taipei time, YY.MMDD.HHMM (ReaPack segment limit is 65535)
- @changelog -> only the given bullets (what ReaPack shows for this release)
- Changelogs/<file>.md -> the previous header entry is archived (if not yet),
  then the new entry is added on top. Releases are listed newest first.
"""
import os, re, subprocess, sys

path, bullets = sys.argv[1], sys.argv[2:]
if not bullets:
    sys.exit("give at least one changelog bullet")
version = subprocess.run(["date", "+%y.%m%d.%H%M"], env={**os.environ, "TZ": "Asia/Taipei"},
                         capture_output=True, text=True, check=True).stdout.strip()

src = open(path, encoding="utf-8").read()
head, sep, body = src.partition("\n--]]\n")
if not sep:
    sys.exit("no --[[ ... --]] header")

old_version = re.search(r"^@version (.+)$", head, re.M).group(1).strip()
m = re.search(r"^@changelog\n((?:(?:  .*)?\n)*?)(?=@\w|\Z)", head + "\n", re.M)
if not m:
    sys.exit("no @changelog block")
old_bullets = [l.strip()[2:] for l in m.group(1).splitlines()
               if l.strip().startswith("- ") and not l.strip().startswith("- Full history")]

new_cl = "@changelog\n" + "".join(f"  - {b}\n" for b in bullets)
head = (head + "\n")[:m.start()] + new_cl + (head + "\n")[m.end():]
head = re.sub(r"^@version .*$", f"@version {version}", head, count=1, flags=re.M)
open(path, "w", encoding="utf-8").write(head.rstrip("\n") + sep + body)


def entry(v, items):
    return f"## {v}\n\n" + "".join(f"- {b}\n" for b in items) + "\n"


md = os.path.join("Changelogs", os.path.basename(path)[:-4] + ".md")
if os.path.exists(md):
    text = open(md, encoding="utf-8").read()
else:
    text = f"# {os.path.basename(path)} — Changelog\n\n"
add = entry(version, bullets)
if f"## {old_version}\n" not in text and old_bullets:
    add += entry(old_version, old_bullets)
pos = re.search(r"^(## |History before )", text, re.M)
pos = pos.start() if pos else len(text)
open(md, "w", encoding="utf-8").write(text[:pos] + add + text[pos:])
print(f"{path}: {old_version} -> {version}")
