#!/usr/bin/env python3
"""json/<tag>/packages.json = index.plist (repodata) + field template.
Template diparse regex — TIDAK di-source/di-exec. Job ini tanpa secret."""
import fnmatch, json, os, pathlib, plistlib, re

TAG = os.environ["TAG"]
ALL = ("x86_64 x86_64-musl aarch64 aarch64-musl armv6l armv6l-musl "
       "armv7l armv7l-musl i686").split()
TPL = pathlib.Path("pkg-template")


SQ, DQ = "'", '"'


def clean(s):
    """Kontrak parser — identik dengan vdev/src/template.sh (tpl_field):
    '#' memulai komentar hanya di luar kutip dan di awal nilai / setelah
    spasi-tab; backslash meloloskan karakter berikutnya (kecuali dalam kutip
    tunggal); trim spasi/tab/CR; buang SATU pasang kutip pembungkus."""
    out, q, prev, i, n = [], "", " ", 0, len(s)
    while i < n:
        c = s[i]
        if c == "\\" and q != SQ and i + 1 < n:
            out.append(c + s[i + 1]); prev = s[i + 1]; i += 2; continue
        if q:
            if c == q:
                q = ""
            out.append(c); prev = c; i += 1; continue
        if c in (SQ, DQ):
            q = c; out.append(c); prev = c; i += 1; continue
        if c == "#" and prev in (" ", "\t"):
            break
        out.append(c); prev = c; i += 1
    v = "".join(out).strip(" \t\r")
    if len(v) >= 2 and v[0] in (SQ, DQ) and v[-1] == v[0]:
        v = v[1:-1]
    return v


def field(text, key):
    m = re.search(r"^[ \t]*" + re.escape(key) + r"=(.*)$", text, re.M)
    return clean(m.group(1)) if m else ""


def expand(archs):
    """Identik dengan expand_archs di vdev/src/template.sh: kosong/noarch = semua;
    'all' = '*'; token berawalan '~' (satu atau lebih) = negasi; tanpa token
    positif = semua tag."""
    toks = archs.replace(",", " ").split()
    if not toks or toks == ["noarch"]:
        return list(ALL)
    pos, neg = [], []
    for tok in toks:
        if tok.startswith("~"):
            t = tok.lstrip("~")
            if t == "all":
                t = "*"
            if t:
                neg.append(t)
        else:
            pos.append("*" if tok == "all" else tok)
    base = ALL if not pos else [a for a in ALL
                                if any(fnmatch.fnmatchcase(a, p) for p in pos)]
    if neg:
        base = [a for a in base
                if not any(fnmatch.fnmatchcase(a, n) for n in neg)]
    return list(base)


def split_pkgver(pkgver, name):
    """'<nama>-<versi>_<revisi>' -> versi tanpa revisi. Nama boleh berisi '-',
    versi XBPS tidak boleh, jadi pisahkan dari '-' TERAKHIR (atau awalan nama)."""
    if name and pkgver.startswith(name + "-"):
        vr = pkgver[len(name) + 1:]
    elif "-" in pkgver:
        vr = pkgver.rsplit("-", 1)[1]
    else:
        vr = pkgver
    m = re.match(r"^(.*)_(\d+)$", vr)
    return m.group(1) if m else vr


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
        for key, v in idx.items():
            if isinstance(v, dict):
                props.append({**v, "pkgname": v.get("pkgname") or key})
print(f"  index.plist: {'ada' if p.is_file() else 'TIDAK ADA'}, {len(props)} paket; "
      f"assets.json: {len(assets)} asset")

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
    size = sizes.get(fn)
    if size is None:
        size = pr.get("filename-size")   # cadangan: ukuran dari indeks repodata
    out.append({
        "name": name,
        "version": split_pkgver(pr.get("pkgver") or "", name)
                   or (pr.get("version") or "").rsplit("_", 1)[0],
        "arch": TAG,
        "archs": tpl.get("archs", [TAG]),
        "size": size,                   # byte, ukuran file .xbps (asset release)
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