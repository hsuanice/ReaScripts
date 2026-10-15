#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""Check every file that would be published against ReaPack/reapack-index rules (local dev tool).

usage (from the repo root):  python3 .dev/validate.py [ROOT]
ROOT defaults to "." — pass a dry-run output folder to check it instead (its files are listed
with the repo's .gitignore whitelist applied to the same relative paths).
"""
import collections, os, re, subprocess, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def published(rel):
    return subprocess.run(["git", "-C", REPO, "check-ignore", "-q", "--no-index", rel]).returncode != 0


files = []
for d, _, fs in os.walk(ROOT):
    for f in fs:
        rel = os.path.relpath(os.path.join(d, f), ROOT)
        if rel.endswith(".lua") and not rel.startswith((".", "Archive")) and published(rel):
            files.append(rel)

errs, owners, pk = [], collections.defaultdict(list), 0
backups = set()  # kept in the repository but not offered on ReaPack
for rel in sorted(files):
    s = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    m = re.match(r"--\[\[\n(.*?)\n--\]\]", s, re.S)
    if not m:
        errs.append(f"{rel}: no --[[ ]] header at top")
        continue
    h = m.group(1)
    tag = lambda t: re.search(rf"^@{t}\b[ \t]*(.*)$", h, re.M)
    v = tag("version")
    if not v:
        errs.append(f"{rel}: no @version")
        continue
    v = v.group(1).strip()
    if not re.match(r"^\d", v) or " " in v or any(int(x) > 65535 for x in re.findall(r"\d+", v)):
        errs.append(f"{rel}: bad version '{v}'")
    if tag("noindex"):
        if "backup" in tag("noindex").group(1).lower():  # "@noindex  (kept ... as a backup ...)": intentionally unlisted
            backups.add(rel)
        continue
    pk += 1
    if not tag("description") or not tag("author"):
        errs.append(f"{rel}: missing @description/@author")
    prov = re.search(r"^@provides\n((?:  .*\n?)*)", h, re.M)
    lines = [l.strip() for l in prov.group(1).splitlines()] if prov else []
    d = os.path.dirname(rel)
    if not tag("metapackage") and not any(re.sub(r"^\[[^\]]*\]\s*", "", l) == "." for l in lines):
        owners[rel].append(rel)
    for l in lines:
        p = re.sub(r"^\[[^\]]*\]\s*", "", l)
        tgt = rel if p == "." else os.path.normpath(os.path.join(d, p))
        if not os.path.exists(os.path.join(ROOT, tgt)):
            errs.append(f"{rel}: @provides file missing: {tgt}")
        owners[tgt].append(rel)
for t, o in owners.items():
    if len(o) > 1:
        errs.append(f"{t}: provided by more than one package: {o}")
for rel in files:
    if rel not in owners and rel not in backups and not re.search(r"^@metapackage", open(os.path.join(ROOT, rel), encoding="utf-8").read(3000), re.M):
        errs.append(f"{rel}: published but not installed by any package")
print(f"checked {len(files)} files, {pk} packages")
print("\n".join(errs) if errs else "NO ERRORS")
sys.exit(1 if errs else 0)
