#!/usr/bin/env python3
"""Suite: .github/workflows/gen-json.py (black-box: index.plist + assets.json + pkg-template → packages.json)."""
import json
import os
import plistlib
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True  # tes tidak boleh menulis apa pun ke repo (__pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t4n_testlib as T  # noqa: E402

KEYS = {"name", "version", "arch", "archs", "size", "category", "desc", "homepage",
        "maintainer", "distributor", "license"}


class GenJson(T.TestCase):
    def setUp(self):
        self.root = T.mkdtemp("genjson.")

    def tpl(self, name, body):
        T.write(os.path.join(self.root, "pkg-template", name, "template"), body)

    def index(self, entries):
        with open(os.path.join(self.root, "index.plist"), "wb") as f:
            f.write(plistlib.dumps(entries))

    def assets(self, items):
        T.write(os.path.join(self.root, "assets.json"), json.dumps([{"name": n, "size": s} for n, s in items]))

    def gen(self, tag="x86_64"):
        p, data = T.run_gen_json(self.root, tag)
        self.assertEqual(p.returncode, 0, p.stderr)
        return p, {e["name"]: e for e in data}, data

    # ── (b) version dari pkgver ──
    def test_version_derived_from_pkgver(self):
        cases = [("tpkg", "tpkg-1.1.0_2", "1.1.0"), ("my-pkg-x", "my-pkg-x-2.3.4_5", "2.3.4"),
                 ("tilde", "tilde-1.0~rc1_1", "1.0~rc1"), ("a-b-c", "a-b-c-0.1_10", "0.1"),
                 ("pkg_x", "pkg_x-1.2_3", "1.2"), ("norev", "norev-1.0", "1.0"),
                 ("plus", "libfoo++-3.0_1", "3.0")]
        entries = {n: {"pkgver": pv, "architecture": "x86_64"} for n, pv, _ in cases}
        entries["plus"]["pkgname"] = "libfoo++"
        self.index(entries)
        _, d, _ = self.gen()
        for n, _, exp in cases:
            key = "libfoo++" if n == "plus" else n
            with self.subTest(pkgver=n):
                self.assertEqual(d[key]["version"], exp)
                self.assertNotEqual(d[key]["version"], "")

    def test_version_fallbacks(self):
        self.index({"renamed": {"pkgver": "renamed-2.0_1", "pkgname": "orig", "architecture": "x86_64"},
                    "nopkgver": {"version": "3.1_2", "architecture": "x86_64"},
                    "keyonly": {"pkgver": "keyonly-9.9_1"}})
        _, d, _ = self.gen()
        self.assertEqual(d["orig"]["version"], "2.0")       # pkgver tidak berawalan nama → '-' terakhir
        self.assertEqual(d["nopkgver"]["version"], "3.1")   # tanpa pkgver → prop `version` tanpa revisi
        self.assertEqual(d["keyonly"]["name"], "keyonly")   # pkgname dari kunci dict
        self.assertEqual(d["keyonly"]["arch"], "x86_64")    # architecture hilang → tag

    # ── ukuran ──
    def test_size_sources_and_fallbacks(self):
        self.index({
            "a": {"pkgver": "a-1_1", "architecture": "x86_64", "filename-size": 999},
            "b": {"pkgver": "b-1_1", "architecture": "x86_64", "filename-size": 999},
            "c": {"pkgver": "c-1_1", "architecture": "x86_64", "filename-size": 777},
            "d": {"pkgver": "d-1_1", "architecture": "x86_64"},
            "e": {"pkgver": "e-1_1", "architecture": "x86_64", "filename-size": 5},
            "f": {"pkgver": "f-1_1", "architecture": "noarch"},
        })
        self.assets([("a-1_1.x86_64.xbps", 111),        # asset ada → ukuran asset menang atas filename-size
                     ("b-1_1.noarch.xbps", 222),        # hanya asset noarch → dipakai
                     ("e-1_1.x86_64.xbps", 0),          # ukuran 0 tetap 0 (bukan fallback)
                     ("f-1_1.noarch.xbps", 333)])
        _, d, _ = self.gen()
        self.assertEqual(d["a"]["size"], 111)
        self.assertEqual(d["b"]["size"], 222)
        self.assertEqual(d["c"]["size"], 777)           # tanpa asset → filename-size repodata
        self.assertIsNone(d["d"]["size"])               # tidak ada sumber → null
        self.assertEqual(d["e"]["size"], 0)
        self.assertEqual(d["f"]["size"], 333)

    # ── xbps vs template ──
    def test_category_xbps_vs_template_and_archs_filter(self):
        self.tpl("zvc", 'pkgname=zvc\nversion=1.0\nshort_desc="zd"\nhomepage="zh"\nmaintainer="zm"\nlicense="MIT"\ndistributor="zdist"\n')
        self.tpl("onlyarm", 'pkgname=onlyarm\nversion=2.0\nshort_desc="o"\narchs="aarch64*"\n')
        self.tpl("built", 'pkgname=built\nversion=3.0\nshort_desc="template desc"\nhomepage="tpl-home"\n'
                          'maintainer="tpl-maint"\nlicense="tpl-lic"\ndistributor="tpl-dist"\narchs="x86_64*"\n')
        self.index({"built": {"pkgver": "built-3.0_1", "architecture": "x86_64", "short_desc": "repo desc",
                              "homepage": "repo-home", "maintainer": "repo-maint", "license": "repo-lic"}})
        _, d, data = self.gen("x86_64")
        self.assertEqual(sorted(d), ["built", "zvc"], "onlyarm tidak boleh muncul di x86_64")
        self.assertEqual([e["name"] for e in data], sorted(d), "harus terurut menurut nama")
        z = d["zvc"]
        self.assertEqual((z["category"], z["size"], z["version"], z["arch"]), ("template", None, "1.0", "x86_64"))
        self.assertEqual((z["desc"], z["homepage"], z["maintainer"], z["license"], z["distributor"]),
                         ("zd", "zh", "zm", "MIT", "zdist"))
        b = d["built"]
        self.assertEqual(b["category"], "xbps")
        self.assertEqual((b["desc"], b["homepage"], b["maintainer"], b["license"]),
                         ("repo desc", "repo-home", "repo-maint", "repo-lic"), "repodata menang atas template")
        self.assertEqual(b["distributor"], "tpl-dist", "distributor hanya dari template")
        self.assertEqual(b["archs"], ["x86_64", "x86_64-musl"])
        os.remove(os.path.join(self.root, "index.plist"))   # tanpa biner: murni filter archs template
        _, d2, _ = self.gen("aarch64")
        self.assertIn("onlyarm", d2)
        self.assertNotIn("built", d2, "template dengan archs x86_64* tidak muncul di aarch64")

    def test_description_falls_back_to_template(self):
        self.tpl("p", 'pkgname=p\nversion=1\nshort_desc="dari template"\nhomepage="th"\n')
        self.index({"p": {"pkgver": "p-1_1", "architecture": "x86_64"}})
        _, d, _ = self.gen()
        self.assertEqual((d["p"]["desc"], d["p"]["homepage"]), ("dari template", "th"))

    def test_subpackage_without_template_falls_back_to_tag(self):
        self.tpl("p", 'pkgname=p\nversion=1\nshort_desc="x"\n')
        self.index({"p-devel": {"pkgver": "p-devel-1_1", "architecture": "x86_64"}})
        _, d, _ = self.gen("x86_64")
        self.assertEqual(d["p-devel"]["archs"], ["x86_64"])
        self.assertEqual(d["p-devel"]["distributor"], "")
        self.assertEqual(d["p"]["category"], "template")

    def test_template_not_duplicated_when_binary_exists(self):
        self.tpl("p", 'pkgname=p\nversion=1\n')
        self.index({"p": {"pkgver": "p-1_1", "architecture": "x86_64"}})
        _, _, data = self.gen()
        self.assertEqual([e["category"] for e in data], ["xbps"])

    # ── masukan tidak biasa ──
    def test_without_index_plist_only_templates(self):
        self.tpl("zvc", "pkgname=zvc\nversion=1\n")
        p, d, _ = self.gen()
        self.assertIn("TIDAK ADA", p.stdout)
        self.assertEqual(list(d), ["zvc"])

    def test_non_dict_index_and_non_dict_values_are_ignored(self):
        with open(os.path.join(self.root, "index.plist"), "wb") as f:
            f.write(plistlib.dumps(["bukan", "dict"]))
        _, d, data = self.gen()
        self.assertEqual(data, [])
        self.index({"x": "string", "y": 3, "ok": {"pkgver": "ok-1_1", "architecture": "x86_64"}})
        _, d, _ = self.gen()
        self.assertEqual(list(d), ["ok"])

    def test_missing_pkg_template_dir_is_fine(self):
        self.index({"ok": {"pkgver": "ok-1_1", "architecture": "x86_64"}})
        _, d, _ = self.gen()
        self.assertEqual(list(d), ["ok"])

    def test_template_without_pkgname_or_file_is_skipped(self):
        self.tpl("noname", "version=1\n")
        os.makedirs(os.path.join(self.root, "pkg-template", "emptydir"))
        T.write(os.path.join(self.root, "pkg-template", "stray.txt"), "x")
        self.tpl("fine", "pkgname=fine\nversion=1\n")
        _, d, _ = self.gen()
        self.assertEqual(list(d), ["fine"])

    # ── bentuk keluaran / kontrak docs ──
    def test_output_schema_matches_docs(self):
        self.tpl("t", "pkgname=t\nversion=1\n")
        self.index({"x": {"pkgver": "x-1_1", "architecture": "x86_64"}})
        _, _, data = self.gen()
        self.assertEqual(len(data), 2)
        for e in data:
            self.assertEqual(set(e), KEYS, "kunci JSON harus sama dengan tabel di docs §7")
            self.assertEqual(e["arch"], "x86_64")

    def test_output_file_format(self):
        self.tpl("u", 'pkgname=u\nversion=1\nshort_desc="é ✓ unik"\n')
        self.gen("i686")
        raw = T.read(os.path.join(self.root, "json", "i686", "packages.json"))
        self.assertTrue(raw.endswith("]\n"))
        self.assertIn('\n  {\n    "name": "u"', raw, "indent 2 spasi")
        self.assertIn("é ✓ unik", raw, "unicode tidak di-escape")

    def test_tag_env_is_required_and_output_stays_in_cwd(self):
        p = subprocess.run([sys.executable, T.GEN_JSON], cwd=self.root, env=T.clean_env(),
                           capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("TAG", p.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.root, "json")))

    def test_real_repo_templates_produce_complete_entries(self):
        src = os.path.join(T.REPO, "pkg-template")
        for d in sorted(os.listdir(src)):
            T.write(os.path.join(self.root, "pkg-template", d, "template"), T.read(os.path.join(src, d, "template")))
        for tag in T.ALL_TAGS:
            _, d, _ = self.gen(tag)
            for n, e in d.items():
                with self.subTest(tag=tag, pkg=n):
                    self.assertEqual(e["category"], "template")
                    self.assertTrue(e["version"] and e["desc"])
                    self.assertIn(tag, e["archs"])


if __name__ == "__main__":
    T.main()
