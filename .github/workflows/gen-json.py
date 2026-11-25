#!/usr/bin/env python3
"""json/<tag>/packages.json = index.plist (repodata) + field template.
Template diparse regex — TIDAK di-source/di-exec. Job ini tanpa secret."""
import fnmatch, json, os, pathlib, plistlib, re

TAG = os.environ["TAG"]
ALL = ("x86_64 x86_64-musl aarch64 aarch64-musl armv6l armv6l-musl "
       "armv7l armv7l-musl i686").split()
TPL = pathlib.Path("pkg-template")


def field(text, key):
    m = re.search(r"^\s*" + key + r"=(.*)$", text, re.M)
    if not m:
        return ""
    v = m.group(1).split("#", 1)[0].strip()
    if v[:1] in ("\"", "'") and v[-1:] == v[:1]:
        v = v[1:-1]
    return v.strip()


def expand(archs):
    if not archs or archs == "noarch":
        return list(ALL)
    pos, neg = [], []
    for tok in archs.replace(",", " ").split():
        (neg if tok.startswith("~") else pos).append(tok.lstrip("~"))
    base = ALL if not pos else [a for a in ALL
                                if any(fnmatch.fnmatchcase(a, p) for p in pos)]
    if neg:
        base = [a for a in base
                if not any(fnmatch.fnmatchcase(a, n) for n in neg)]
    return base


templates = {}
if TPL.is_dir():
    for d in sorted(TPL.iterdir()):
        f = d / "template"
        if not f.is_file():
            continue
        t = f.read_text(errors="replace")
        name = field(t, "pkgname")
        if not name:
            continue
        templates[name] = {
            "archs": expand(field(t, "archs")),
            "version": field(t, "version"),
            "description": field(t, "short_desc"),
            "homepage": field(t, "homepage"),
            "maintainer": field(t, "maintainer"),
            "distributor": field(t, "distributor"),
            "license": field(t, "license"),
        }

assets = []
if pathlib.Path("assets.json").is_file():
    assets = json.loads(pathlib.Path("assets.json").read_text())
sizes = {a["name"]: a["size"] for a in assets}

props = []
p = pathlib.Path("index.plist")
if p.is_file():
    idx = plistlib.loads(p.read_bytes())
    if isinstance(idx, dict):
        props = [v for v in idx.values() if isinstance(v, dict) and "pkgname" in v]

out, seen = [], set()
for pr in props:
    name = pr["pkgname"]
    pv = pr.get("pkgver") or f"{name}-{pr.get('version', '')}"
    arch = pr.get("architecture") or TAG
    fn = f"{pv}.{arch}.xbps"
    if fn not in sizes and f"{pv}.noarch.xbps" in sizes:
        fn = f"{pv}.noarch.xbps"
    tpl = templates.get(name, {})
    desc = pr.get("short_desc") or tpl.get("description", "")
    out.append({
        "name": name,
        "version": (pr.get("version") or "").rsplit("_", 1)[0],
        "arch": TAG,
        "archs": tpl.get("archs", [TAG]),
        "size": sizes.get(fn),          # byte, ukuran asset .xbps di release
        "category": "xbps",             # biner sudah ada di tag ini
        "desc": desc,
        "homepage": pr.get("homepage") or tpl.get("homepage", ""),
        "maintainer": pr.get("maintainer") or tpl.get("maintainer", ""),
        "distributor": tpl.get("distributor", ""),
        "license": pr.get("license") or tpl.get("license", ""),
    })
    seen.add(name)

for name, t in templates.items():
    if name in seen or TAG not in t["archs"]:
        continue
    out.append({
        "name": name, "version": t["version"], "arch": TAG, "archs": t["archs"],
        "size": None, "category": "template",   # template saja, biner belum dibangun
        "desc": t["description"],
        "homepage": t["homepage"], "maintainer": t["maintainer"],
        "distributor": t["distributor"], "license": t["license"],
    })

out.sort(key=lambda e: e["name"])
dst = pathlib.Path("json") / TAG
dst.mkdir(parents=True, exist_ok=True)
(dst / "packages.json").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")

n_xbps = sum(1 for e in out if e["category"] == "xbps")
print(f"✓ json/{TAG}/packages.json: {len(out)} entri ({n_xbps} xbps, {len(out)-n_xbps} template)")