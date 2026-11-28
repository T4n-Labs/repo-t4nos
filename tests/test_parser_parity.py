#!/usr/bin/env python3
"""Suite: paritas parser template Bash/awk (vdev/src/template.sh) vs Python (gen-json.py).

Sisi Python diuji black-box: gen-json.py dijalankan pada pkg-template sintetis (di /tmp)
dan hasil JSON-nya dibandingkan dengan keluaran tpl_field / tpl_supported. Selain paritas,
setiap kasus punya nilai harapan LITERAL, supaya dua parser yang sama-sama salah tidak lolos.
Resep hanya DIPARSE (awk/regex) — tidak pernah di-source atau di-exec (Invarian 3).
"""
import json
import os
import sys
import unittest

sys.dont_write_bytecode = True  # tes tidak boleh menulis apa pun ke repo (__pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t4n_testlib as T  # noqa: E402

ALL = T.ALL_TAGS
# (nilai mentah setelah `KEY=`, nilai harapan)
FIELD_CASES = [
    ('"https://ex.com/#readme"', 'https://ex.com/#readme'),      # '#' di dalam kutip
    ('"A # B"', 'A # B'),
    ("'A # B'", 'A # B'),
    ('"A" # komentar', 'A'),                                    # komentar di luar kutip
    ('A#B', 'A#B'),                                             # '#' tanpa spasi bukan komentar
    ('A #B', 'A'),
    ('  "spasi"   ', 'spasi'),                                   # trimming
    ('\t"tab"\t', 'tab'),
    ('""', ''),
    ("''", ''),
    ('', ''),
    (' # hanya komentar', ''),
    ('#x', ''),
    ('"a \\"q\\" b"', 'a \\"q\\" b'),                           # escape dipertahankan literal
    ("'a \\ b'", 'a \\ b'),                                     # kutip tunggal: backslash literal
    ('a\\#b', 'a\\#b'),                                         # '#' yang di-escape bukan komentar
    ('abc\\', 'abc\\'),                                         # backslash di ujung
    ('"unterminated', '"unterminated'),
    ('"x"y"', 'x"y'),                                           # hanya SATU pasang kutip dibuang
    ('"A" "B"', 'A" "B'),
    ("'mix \"q\" ok'", 'mix "q" ok'),
    ('"Kutip ganda\' tunggal"', "Kutip ganda' tunggal"),
    ('"#awal"', '#awal'),
    ('a"b#c"d # kom', 'a"b#c"d'),
    ('"trailing space "  ', 'trailing space '),                  # spasi DI DALAM kutip dipertahankan
    ('"é unicode ✓"', 'é unicode ✓'),
    ('plain', 'plain'),
    ('a=b', 'a=b'),
    ('"a\tb"', 'a\tb'),
]
KEYS = ("homepage", "short_desc", "maintainer", "license", "distributor")
JSON_FIELD = {"homepage": "homepage", "short_desc": "desc", "maintainer": "maintainer",
              "license": "license", "distributor": "distributor", "version": "version"}

# (teks template, {key: nilai harapan}) — pemilihan baris (first-match, indentasi, awalan, komentar)
SELECT_CASES = [
    ("pkgname=%s\nversion=1\ndo_x() {\n\tversion=9\n}\n", {"version": "1"}),
    ("pkgname=%s\n\tversion=2\n", {"version": "2"}),
    ("pkgname=%s\n   version=3\n", {"version": "3"}),
    ("pkgname=%s\nxversion=2\nversion=3\n", {"version": "3"}),
    ("pkgname=%s\n# version=9\nversion=4\n", {"version": "4"}),
    ("pkgname=%s\nversion =9\nversion=5\n", {"version": "5"}),
    ("pkgname=%s\n", {"version": ""}),
    ("pkgname=%s\r\nversion=7\r\nhomepage=\"h\"\r\n", {"version": "7", "homepage": "h"}),
    ("pkgname=%s\nhomepage=a\nhomepage=b\n", {"homepage": "a"}),
]
# (nilai archs mentah, daftar harapan) — semantik dikunci di docs §4 "Kontrak parser"
ARCHS_CASES = [
    ('', ALL), ('""', ALL), ('noarch', ALL), ('all', ALL), ('"*"', ALL),
    ('x86_64', ["x86_64"]),
    ('"x86_64*"', ["x86_64", "x86_64-musl"]),
    ('"x86_64* aarch64"', ["x86_64", "x86_64-musl", "aarch64"]),
    ('"~i686"', [a for a in ALL if a != "i686"]),
    ('"~~i686"', [a for a in ALL if a != "i686"]),
    ('"x86_64* ~x86_64-musl"', ["x86_64"]),
    ('"all ~i686"', [a for a in ALL if a != "i686"]),
    ('"all ~~i686 ~armv6l*"', [a for a in ALL if a not in ("i686", "armv6l", "armv6l-musl")]),
    ('"x86_64,aarch64"', ["x86_64", "aarch64"]),
    ('"x86_64, aarch64"', ["x86_64", "aarch64"]),
    ('"  x86_64    i686 "', ["x86_64", "i686"]),
    ('"*-musl"', [a for a in ALL if a.endswith("-musl")]),
    ('"~*-musl"', [a for a in ALL if not a.endswith("-musl")]),
    ('"armv?l"', ["armv6l", "armv7l"]),
    ('"[ax]86_64"', ["x86_64"]),
    ('"aarch64 noarch"', ["aarch64"]),
    ('bogus', []),
    ('"~"', ALL), ('"~~"', ALL),
    ('"noarch ~i686"', []),          # 'noarch' hanya bermakna bila sendirian
    ('"i686 ~i686"', []),
    ('"~all"', []),
    ('"x86_64*,~x86_64-musl"', ["x86_64"]),
    ('"x86_64" # komentar', ["x86_64"]),
]


def bash_fields(root, keys):
    """{dir: {key: nilai}} dari tpl_field, satu proses bash untuk semua template."""
    script = T.vdev_src() + (
        'TPL="%s/pkg-template"; for d in "$TPL"/*/; do n=$(basename "$d"); for k in %s; do '
        "printf '%%s\\t%%s\\t%%s\\n' \"$n\" \"$k\" \"$(tpl_field \"$d/template\" \"$k\")\"; done; done"
        % (root, " ".join(keys)))
    p = T.bash(script)
    assert p.returncode == 0, p.stderr
    out = {}
    for line in p.stdout.split("\n"):
        if line:
            n, k, v = line.split("\t", 2)
            out.setdefault(n, {})[k] = v
    return out


def bash_archs(root, cwd=None):
    script = T.vdev_src() + (
        'TPL="%s/pkg-template"; for d in "$TPL"/*/; do n=$(basename "$d"); '
        "printf '%%s\\t%%s\\n' \"$n\" \"$(tpl_supported \"$n\" | xargs)\"; done" % root)
    p = T.bash(script, cwd=cwd)
    assert p.returncode == 0, p.stderr
    return {l.split("\t")[0]: (l.split("\t")[1].split() if "\t" in l else []) for l in p.stdout.split("\n") if l}


def py_entries(root, tags):
    """gen-json.py per tag → {nama: entri} (entri template; tag pertama yang memuatnya)."""
    res = {}
    for tag in tags:
        p, data = T.run_gen_json(root, tag)
        assert p.returncode == 0, p.stderr
        for e in data:
            res.setdefault(e["name"], e)
    return res


class ParserParity(T.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = T.mkdtemp("parity.")
        tpl = os.path.join(cls.root, "pkg-template")
        for i, (raw, _) in enumerate(FIELD_CASES):
            body = "pkgname=f%02d\nversion=1\n" % i + "".join("%s=%s\n" % (k, raw) for k in KEYS)
            T.write(os.path.join(tpl, "f%02d" % i, "template"), body, newline="")
        for i, (text, _) in enumerate(SELECT_CASES):
            T.write(os.path.join(tpl, "s%02d" % i, "template"), text % ("s%02d" % i), newline="")
        for i, (raw, _) in enumerate(ARCHS_CASES):
            T.write(os.path.join(tpl, "a%02d" % i, "template"), "pkgname=a%02d\narchs=%s\n" % (i, raw))
        cls.bash = bash_fields(cls.root, KEYS + ("version",))
        cls.archs_bash = bash_archs(cls.root)
        cls.py = py_entries(cls.root, ALL)          # untuk archs (union semua tag)
        cls.py_x = py_entries(cls.root, ["x86_64"])  # untuk field (archs default = semua tag)

    # ── field: komentar #, kutip, escape, trimming ──
    def test_field_literal_expectations_bash_and_python(self):
        for i, (raw, exp) in enumerate(FIELD_CASES):
            n = "f%02d" % i
            for k in KEYS:
                with self.subTest(case=raw, key=k):
                    self.assertEqual(self.bash[n][k], exp, "bash/awk")
                    self.assertEqual(self.py_x[n][JSON_FIELD[k]], exp, "python")

    def test_field_parity_bash_equals_python(self):
        for i in range(len(FIELD_CASES)):
            n = "f%02d" % i
            for k in KEYS:
                self.assertEqual(self.bash[n][k], self.py_x[n][JSON_FIELD[k]], "%s.%s" % (n, k))

    # ── pemilihan baris ──
    def test_select_cases(self):
        for i, (_, exp) in enumerate(SELECT_CASES):
            n = "s%02d" % i
            for k, v in exp.items():
                with self.subTest(case=i, key=k):
                    self.assertEqual(self.bash[n][k], v, "bash/awk")
                    self.assertEqual(self.py_x[n][JSON_FIELD[k]], v, "python")

    # ── archs ──
    def test_archs_literal_expectations_bash_and_python(self):
        for i, (raw, exp) in enumerate(ARCHS_CASES):
            n = "a%02d" % i
            with self.subTest(archs=raw):
                self.assertEqual(self.archs_bash[n], exp, "bash/awk")
                self.assertEqual(self.py[n]["archs"] if n in self.py else [], exp, "python")

    def test_archs_parity_matrix(self):
        for i in range(len(ARCHS_CASES)):
            n = "a%02d" % i
            self.assertEqual(self.archs_bash[n], self.py[n]["archs"] if n in self.py else [], n)

    # ── anti-globbing terhadap cwd ──
    def test_archs_wildcards_are_never_globbed_against_cwd(self):
        cwd = T.mkdtemp("glob.")
        for name in ("x86_64", "aarch64", "i686", "armv6l-musl"):
            T.write(os.path.join(cwd, name), "")
        t = os.path.join(T.mkdtemp("globtpl."), "pkg-template", "g")
        T.write(os.path.join(t, "template"), 'pkgname=g\narchs="x86_64* aarch64* ~i686*"\nsubpackages="g-a* ${pkgname}-b"\n')
        root = os.path.dirname(os.path.dirname(t))
        self.assertEqual(bash_archs(root, cwd=cwd)["g"], ["x86_64", "x86_64-musl", "aarch64", "aarch64-musl"])
        p = T.bash(T.vdev_src() + 'tpl_subpkgs "%s/template" g' % t, cwd=cwd)
        self.assertEqual(p.stdout.split(), ["g-a*", "g-b"], "subpackages ter-glob terhadap cwd")

    # ── Invarian 3: resep tidak pernah dieksekusi ──
    def test_poisoned_template_is_parsed_never_executed(self):
        root = T.mkdtemp("poison.")
        cwd = T.mkdtemp("poisoncwd.")
        T.write(os.path.join(root, "pkg-template", "poison", "template"),
                'pkgname=poison\nshort_desc="$(touch MARK1)"\nhomepage=`touch MARK2`\n'
                'maintainer=x; touch MARK3\nlicense=$HOME\narchs="x86_64"; touch MARK4\n'
                "distributor=$(touch MARK5)\n")
        script = T.vdev_src() + 'TPL="%s/pkg-template"; ' % root + \
            'for k in short_desc homepage maintainer license distributor; do tpl_field "$TPL/poison/template" $k; done; tpl_supported poison'
        p = T.bash(script, cwd=cwd)
        self.assertEqual(p.returncode, 0, p.stderr)
        lines = p.stdout.split("\n")
        self.assertEqual(lines[:5], ["$(touch MARK1)", "`touch MARK2`", "x; touch MARK3", "$HOME", "$(touch MARK5)"])
        p2, data = T.run_gen_json(root, "x86_64")
        self.assertEqual(p2.returncode, 0, p2.stderr)
        py = {e["name"]: e for e in (data or [])}.get("poison")
        if py:
            self.assertEqual(py["desc"], "$(touch MARK1)")
            self.assertEqual(py["license"], "$HOME")
        for root_dir in (cwd, root):
            marks = [f for f in os.listdir(root_dir) if f.startswith("MARK")]
            self.assertEqual(marks, [], "resep dieksekusi!")

    # ── template nyata di repo: kedua parser setuju ──
    def test_real_repo_templates_agree(self):
        root = T.mkdtemp("real.")
        src = os.path.join(T.REPO, "pkg-template")
        for d in sorted(os.listdir(src)):
            T.write(os.path.join(root, "pkg-template", d, "template"), T.read(os.path.join(src, d, "template")))
        bf = bash_fields(root, KEYS + ("version",))
        ba = bash_archs(root)
        py = {t: py_entries(root, [t]) for t in ALL}
        self.assertTrue(bf, "tidak ada template di repo")
        for n in bf:
            with self.subTest(template=n):
                self.assertTrue(bf[n]["version"], "version kosong")
                self.assertTrue(bf[n]["short_desc"], "short_desc kosong")
                e = py["x86_64"].get(n) or py["x86_64-musl"].get(n) or next(py[t][n] for t in ALL if n in py[t])
                for k in KEYS + ("version",):
                    self.assertEqual(bf[n][k], e[JSON_FIELD[k]], k)
                self.assertEqual(ba[n], e["archs"])

    def test_subpackages_pkgname_substitution(self):
        t = T.mkdtemp("sub.")
        T.write(os.path.join(t, "template"), 'pkgname=foo\nsubpackages="${pkgname}-devel $pkgname-doc foo-x"\n')
        p = T.bash(T.vdev_src() + 'tpl_subpkgs "%s/template" foo' % t)
        self.assertEqual(p.stdout.split(), ["foo-devel", "foo-doc", "foo-x"])

    def test_missing_template_file_yields_empty_not_error(self):
        p = T.bash(T.vdev_src() + 'set -euo pipefail; v=$(tpl_field /nonexistent/template version); echo "[$v]"')
        self.assertEqual((p.returncode, p.stdout.strip()), (0, "[]"))

    def test_expand_archs_returns_zero_under_set_e_even_when_empty(self):
        p = T.bash(T.vdev_src() + 'set -euo pipefail; out=$(expand_archs bogus); echo "rc=$? n=${#out}"')
        self.assertEqual(p.stdout.strip(), "rc=0 n=0")


if __name__ == "__main__":
    T.main()
