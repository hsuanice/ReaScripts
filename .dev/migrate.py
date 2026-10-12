#!/usr/bin/env python3
# @noindex  (local maintenance tool for this repository, not a ReaPack package)
"""Migrate a batch of local scripts into a published ReaPack category (local dev tool).

usage (from the repo root):
  python3 .dev/migrate.py BATCH.json OUT_DIR      # dry run: writes the new tree under OUT_DIR
  python3 .dev/migrate.py BATCH.json .            # apply in place (old files are left untouched)

BATCH.json:
{
  "category": "Items Editing",
  "packages": [
    {"meta": "hsuanice_Hover Mode.lua",               # metapackage (description-only file)
     "description": "Hover Mode - ...", "about": ["line", ...],
     "files": [{"src": "Beta Testing/x.lua", "shortcut": "B"}, ...]},
    {"files": [{"src": "Beta Testing/main.lua"}, {"src": "Beta Testing/wrapper.lua"}]}
                                                      # first file is the package, others [main]
  ],
  "libs": ["Library/hsuanice_Hover.lua"],             # library files to normalize in place (@noindex)
  "lib_checks": {"x.lua": ["hsuanice_Hover.lua"]},     # missing-Library prompt for these scripts
  "notes": {"x.lua": ["Known issue: ..."]}             # extra changelog bullets per package file
}

Every header becomes a --[[ ]] block, @version = Taipei YY.MMDD.HHMM, @changelog = this release only,
old header changelog -> Changelogs/<file>.md. The code body is verified byte-identical.
"""
import json, os, re, subprocess, sys, textwrap

cfg = json.load(open(sys.argv[1], encoding="utf-8"))
OUT = sys.argv[2]
VERSION = subprocess.run(["date", "+%y.%m%d.%H%M"], env={**os.environ, "TZ": "Asia/Taipei"},
                         capture_output=True, text=True, check=True).stdout.strip()
CAT = cfg["category"]
CL_URL = "https://github.com/hsuanice/ReaScripts/tree/master/Changelogs"
FULL = f"Full history: Changelogs/ in the repository ({CL_URL})"
KEYS_NOTE = ("Shortcuts are suggestions only — nothing is assigned automatically. "
             "macOS names; on Windows Cmd = Ctrl, Option = Alt, Control = Win.")

TAG_RE = re.compile(r"^@(\w+)[ \t]*(.*)$")
BLOCK_END_RE = re.compile(r"^\s*(--)?\]\](--)?\s*$")
HANDLED = ("description", "version", "author", "link", "links", "provides", "changelog",
           "noindex", "metapackage")


def split_header(lines):
    first = lines[0].rstrip("\n")
    if first.startswith("--[["):
        content = [first[4:].strip()] if first[4:].strip() else []
        for i in range(1, len(lines)):
            if BLOCK_END_RE.match(lines[i]):
                return content, i + 1
            content.append(lines[i].rstrip("\n"))
        sys.exit("unterminated header block")
    content = []
    for i, ln in enumerate(lines):
        if not ln.startswith("--"):
            return content, i
        body = ln.rstrip("\n")[2:]
        content.append(body[1:] if body.startswith(" ") else body)
    sys.exit("header never ends")


def parse_tags(content):
    tags, order, cur = {}, [], None
    for ln in content:
        m = TAG_RE.match(ln)
        if m:
            cur = m.group(1).lower()
            cur = "notes" if cur == "note" else cur
            if cur not in tags:
                tags[cur] = []
                order.append(cur)
            if m.group(2).strip():
                tags[cur].append(m.group(2).rstrip())
        elif cur:
            tags[cur].append(ln.rstrip())
        elif ln.strip():  # untagged text before the first tag
            tags.setdefault("_pre", []).append(ln.rstrip())
    for v in tags.values():
        while v and not v[0].strip():
            v.pop(0)
        while v and not v[-1].strip():
            v.pop()
    return tags, order


def block(tag, values):
    if not values:
        return [f"@{tag}"]
    vals = textwrap.dedent("\n".join(values)).split("\n")
    if len(vals) == 1 and tag in ("description", "version", "author"):
        return [f"@{tag} {vals[0]}"]
    return [f"@{tag}"] + [("  " + v) if v.strip() else "" for v in vals]


def lib_check(libs):
    names = ", ".join(f"'{x}'" for x in libs)
    return f"""
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({{ {names} }}) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\\n\\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\\n'
        .. 'then run this script again.\\n\\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end
"""


def shortcut_about(files):
    rows = [f"- {f['name'][9:-4]}: {f['shortcut']}" for f in files if f.get("shortcut")]
    if not rows:
        return []
    return ["", "## Suggested shortcuts", *rows, "", KEYS_NOTE]


def write(rel, text):
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w", encoding="utf-8", newline="\n").write(text)


def changelog_md(name, desc, old_v, new_bullets, old_cl):
    s = f"# {name} — Changelog\n\n{desc}\n\n## {VERSION}\n\n" + "".join(f"- {b}\n" for b in new_bullets) + "\n"
    if old_cl:
        s += (f"History before {VERSION} (moved out of the script header; last header version: `{old_v}`).\n\n"
              "```text\n" + textwrap.dedent("\n".join(old_cl)).strip("\n") + "\n```\n")
    return s


def convert(src, dst, role, provides=None, bullets=(), extra_about=(), checks=()):
    lines = open(src, encoding="utf-8").readlines()
    content, n = split_header(lines)
    tags, order = parse_tags(content)
    name = os.path.basename(dst)
    pre = tags.pop("_pre", [])
    if pre and "description" not in tags:
        tags["description"], pre = [pre[0]], pre[1:]
    if pre:
        tags["about"] = pre + ([""] if tags.get("about") else []) + tags.get("about", [])
        if "about" not in order:
            order.insert(0, "about")
    desc = tags.get("description", [name[:-4]])
    if role == "pkg":  # package name shown in ReaPack: drop a leading "hsuanice_" file prefix
        desc = [re.sub(r"^hsuanice_", "", desc[0])] + desc[1:]
    hdr = ["--[["] + block("description", desc) + [f"@version {VERSION}", "@author hsuanice"]
    links = tags.get("link", []) + tags.get("links", [])
    if role == "sub":
        hdr.append("@noindex")
    elif links:
        hdr += block("links", links)
    if provides:
        hdr += block("provides", provides)
    hdr += block("changelog", [f"- {b}" for b in bullets])
    about = list(tags.get("about", [])) + list(extra_about)
    while about and not about[0].strip():
        about.pop(0)
    if about:
        tags["about"] = about
        if "about" not in order:
            order.insert(0, "about")
    for t in order:
        if t not in HANDLED:
            hdr += block(t, tags[t])
    if role == "sub" and links:
        hdr += block("links", links)
    hdr.append("--]]")
    body = "".join(lines[n:])
    body = body if body.startswith("\n") or not body else "\n" + body
    write(dst, "\n".join(hdr) + ("\n" + lib_check(checks).lstrip("\n") if checks else "") + body)
    # integrity: original code body kept, no header line lost
    kept = "\n".join(hdr) + "\n" + "\n".join(tags.get("changelog", []))
    lost = [l for l in content if l.strip() and l.strip() not in kept and not TAG_RE.match(l.strip())
            and l.rstrip() not in tags.get("provides", []) + tags.get("version", [])]
    if lost:
        sys.exit(f"LOST header lines in {name}: {lost[:5]}")
    new = open(os.path.join(OUT, dst), encoding="utf-8").read()
    if not new.endswith("".join(lines[n:])):
        sys.exit(f"BODY CHANGED in {name}")
    old_v = " ".join(tags.get("version", ["?"]))
    write(os.path.join("Changelogs", name[:-4] + ".md"),
          changelog_md(name, " ".join(desc), old_v, [b for b in bullets if not b.startswith("Full history")],
                       tags.get("changelog", [])))
    return f"{role:4} {name:62} {old_v[:22]:22} hdr {n:4} -> {len(hdr):3}"


report, notes, checks = [], cfg.get("notes", {}), cfg.get("lib_checks", {})
for pkg in cfg["packages"]:
    files = pkg["files"]
    for f in files:
        f["name"] = os.path.basename(f["src"])
    first = ["First release in the hsuanice/ReaScripts repository."]
    if any(f["name"] in checks for f in files):
        first.append("Requires the \"hsuanice Library\" package.")
    if "meta" in pkg:
        meta = pkg["meta"]
        hdr = ["--[[", f"@description {pkg['description']}", f"@version {VERSION}", "@author hsuanice",
               "@metapackage", "@provides"] + [f"  [main] {f['name']}" for f in files]
        bl = first + notes.get(meta, []) + [FULL]
        hdr += block("changelog", [f"- {b}" for b in bl])
        hdr += block("about", pkg.get("about", []) + shortcut_about(files))
        hdr += ["--]]", "-- This file only describes the package for ReaPack; it is not installed.", ""]
        write(f"{CAT}/{meta}", "\n".join(hdr))
        write(os.path.join("Changelogs", meta[:-4] + ".md"),
              changelog_md(meta, pkg["description"], "-", bl[:-1], []))
        report.append(f"meta {meta}")
        for f in files:
            report.append(convert(f["src"], f"{CAT}/{f['name']}", "sub",
                                  bullets=[f"Released as part of the {VERSION} package update.", FULL],
                                  checks=checks.get(f["name"], ())))
    else:
        main, rest = files[0], files[1:]
        sec = lambda f: f"[main={f['section']}]" if f.get("section") else "[main]"  # e.g. mediaexplorer
        provides = ([f"{sec(main)} ."] + [f"{sec(f)} {f['name']}" for f in rest]) if rest or main.get("section") else None
        if pkg.get("extra_provides"):  # e.g. helper files outside the category folder
            provides = (provides or ["[main] ."]) + pkg["extra_provides"]
        report.append(convert(main["src"], f"{CAT}/{main['name']}", "pkg", provides=provides,
                              bullets=first + notes.get(main["name"], []) + [FULL],
                              extra_about=shortcut_about(files), checks=checks.get(main["name"], ())))
        for f in rest:
            report.append(convert(f["src"], f"{CAT}/{f['name']}", "sub",
                                  bullets=[f"Released as part of the {VERSION} package update.", FULL],
                                  checks=checks.get(f["name"], ())))
for lib in cfg.get("libs", []):
    report.append(convert(lib, lib, "sub", bullets=[f"Released as part of the {VERSION} package update.", FULL]))
print(f"version {VERSION}")
print("\n".join(report))
