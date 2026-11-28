#!/usr/bin/env python3
"""Suite: konsistensi dokumentasi (tautan, paritas ID↔EN, sinkron dengan kode)."""
import os
import re
import sys
import unittest

sys.dont_write_bytecode = True  # tes tidak boleh menulis apa pun ke repo (__pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t4n_testlib as T  # noqa: E402

R = T.REPO
DOCS = ["README.md", "README.ID.md", "vdocs/EN/USER.md", "vdocs/ID/USER.md", "vdocs/EN/DEV.md", "vdocs/ID/DEV.md"]
PAIRS = [("vdocs/ID/DEV.md", "vdocs/EN/DEV.md"), ("vdocs/ID/USER.md", "vdocs/EN/USER.md")]
SCHEMA_KEYS = ["name", "version", "arch", "archs", "size", "category", "desc", "homepage",
               "maintainer", "distributor", "license"]


def rd(p):
    return T.read(os.path.join(R, *p.split("/")))


class Docs(T.TestCase):
    def test_relative_links_resolve(self):
        for f in DOCS:
            for m in re.finditer(r"\]\((?!https?:|#|mailto:)([^)#\s]+)", rd(f)):
                p = os.path.normpath(os.path.join(R, os.path.dirname(f), m.group(1)))
                self.assertTrue(os.path.exists(p), "%s -> %s rusak" % (f, m.group(1)))

    def test_id_en_parity_structure(self):
        for a, b in PAIRS:
            ta, tb = rd(a), rd(b)
            h = lambda t: len(re.findall(r"(?m)^#{1,3} ", t))
            c = lambda t: len(re.findall(r"(?m)^```", t))
            self.assertEqual(h(ta), h(tb), "jumlah heading %s vs %s" % (a, b))
            self.assertEqual(c(ta), c(tb), "jumlah blok kode %s vs %s" % (a, b))
            tab = lambda t: len(re.findall(r"(?m)^\|", t))
            self.assertEqual(tab(ta), tab(tb), "jumlah baris tabel %s vs %s" % (a, b))

    def test_id_en_parity_numbered_sections(self):
        for a, b in PAIRS[:1]:
            sec = lambda t: re.findall(r"(?m)^## (\d+)\.", t)
            self.assertEqual(sec(rd(a)), sec(rd(b)))

    def test_no_stale_claims(self):
        stale = ["aunque", "§10 PROMPT", "masih placeholder", "belum diterapkan** (`grep",
                 "6 modul", "6 modules"]
        for f in DOCS:
            t = rd(f)
            for s in stale:
                self.assertNotIn(s, t, "%s memuat klaim usang: %s" % (f, s))

    def test_build_examples_use_existing_templates(self):
        for f in DOCS:
            for name in re.findall(r"tools\.sh -b ([A-Za-z0-9._+-]+)", rd(f)):
                if name.startswith("-"):
                    continue
                self.assertTrue(os.path.isfile(os.path.join(R, "pkg-template", name, "template")),
                                "%s: contoh `-b %s` merujuk template yang tidak ada" % (f, name))

    def test_fingerprint_in_docs_matches_setup_sh(self):
        fp = re.search(r'^FINGERPRINT="([0-9a-f:]+)"', rd("setup.sh"), re.M).group(1)
        for f in DOCS:
            for m in re.findall(r"\b(?:[0-9a-f]{2}:){15}[0-9a-f]{2}\b", rd(f)):
                self.assertEqual(m, fp, "%s: fingerprint tidak cocok dengan setup.sh" % f)

    def test_dev_docs_describe_json_schema_keys(self):
        for f in ("vdocs/ID/DEV.md", "vdocs/EN/DEV.md"):
            t = rd(f)
            sec = re.search(r"### (Skema `packages.json`|`packages.json` schema)(.*?)\n## ", t, re.S).group(2)
            for k in SCHEMA_KEYS:
                self.assertIn('"%s"' % k, sec, "%s: contoh JSON tanpa kunci %s" % (f, k))

    def test_dev_docs_mention_test_suite(self):
        for f in ("vdocs/ID/DEV.md", "vdocs/EN/DEV.md"):
            t = rd(f)
            for s in ("tests/run.sh", "test.yml", "tests/"):
                self.assertIn(s, t, "%s tidak menyebut %s" % (f, s))
            tree = re.search(r"```\nrepo-t4nos/(.*?)\n```", t, re.S).group(1)
            self.assertIn("tests/", tree)
            self.assertIn("test.yml", tree)

    def test_user_docs_document_setup_options(self):
        for f in ("vdocs/ID/USER.md", "vdocs/EN/USER.md"):
            t = rd(f)
            for s in ("T4N_BASE", "CONF_FILE", "T4N_ASSUME_YES", "setup.sh update", "sudo env"):
                self.assertIn(s, t, "%s tidak mendokumentasikan %s" % (f, s))

    def test_user_docs_architecture_tags_complete(self):
        for f in ("vdocs/ID/USER.md", "vdocs/EN/USER.md"):
            t = rd(f)
            for tag in T.ALL_TAGS:
                self.assertIn("`%s`" % tag, t, "%s tanpa tag %s" % (f, tag))

    def test_claude_md_if_present_mentions_tests(self):
        p = os.path.join(R, "CLAUDE.md")
        if not os.path.isfile(p):
            self.skipTest("CLAUDE.md tidak ada di dalam repo (disimpan terpisah)")
        t = T.read(p)
        for s in ("tests/", "test.yml", "tests/run.sh"):
            self.assertIn(s, t)


if __name__ == "__main__":
    T.main()
