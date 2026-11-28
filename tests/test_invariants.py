#!/usr/bin/env python3
"""Suite: pemeriksaan statis Invarian CLAUDE.md §2 terhadap isi repositori."""
import hashlib
import base64
import os
import re
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True  # tes tidak boleh menulis apa pun ke repo (__pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t4n_testlib as T  # noqa: E402

R = T.REPO
WF = os.path.join(R, ".github", "workflows")
ALLOWLIST = "^[A-Za-z0-9._+-]+$"


def rd(*p):
    return T.read(os.path.join(R, *p))


def walk(skip=(".git",)):
    for d, dirs, files in os.walk(R):
        dirs[:] = [x for x in dirs if x not in skip]
        for f in files:
            yield os.path.relpath(os.path.join(d, f), R)


def code_lines(text):
    """Baris bukan-komentar (untuk grep yang tidak boleh terkecoh komentar)."""
    return [l for l in text.splitlines() if not l.strip().startswith("#")]


class Invariants(T.TestCase):
    # ── Invarian 1: biner dilarang masuk Git ──
    def test_inv1_no_binaries_in_tree(self):
        bad = [f for f in walk() if re.search(r"(\.xbps|\.xbps\.sig2|\.sig2|-repodata|\.pem)$", f)
               and f != os.path.join("keys", "key.pem.pub")]
        self.assertEqual(bad, [], "biner/kunci pribadi terlarang di tree")

    def test_inv1_no_private_key_material(self):
        pat = re.compile("BEGIN " + "(RSA |OPENSSH |EC |DSA )?" + "PRIVATE KEY")
        hits = [f for f in walk() if pat.search(T.read(os.path.join(R, f)))]
        self.assertEqual(hits, [])

    def test_inv1_gitignore_blocks_binaries(self):
        gi = rd(".gitignore")
        for pat in ("*.xbps", "*.xbps.sig2", "*-repodata", "key.pem"):
            self.assertIn(pat, gi.splitlines(), ".gitignore harus memuat %s" % pat)

    # ── Invarian 2: signing hanya di CI ──
    def test_inv2_vdev_has_no_signing(self):
        for f in walk():
            if f.startswith("vdev" + os.sep):
                t = rd(f)
                for w in ("xbps-rindex", "privkey", "SIGN_KEY"):
                    self.assertNotIn(w, t, "%s memuat %s" % (f, w))

    def test_inv2_sign_key_scope(self):
        """SIGN_KEY hanya muncul (di luar komentar & tests/) di process.yml dan process-tag.sh."""
        allowed = {os.path.join(".github", "workflows", "process.yml"),
                   os.path.join(".github", "workflows", "process-tag.sh")}
        for f in walk():
            # hanya kode yang dieksekusi; docs/README boleh menyebut nama secret
            if not (f.startswith("vdev" + os.sep) or f.startswith(".github" + os.sep) or f == "setup.sh"
                    or f.startswith("pkg-template" + os.sep) or f.startswith("json" + os.sep)):
                continue
            if f == os.path.join(".github", "workflows", "test.yml"):
                continue  # test.yml diperiksa ketat terpisah (tanpa secrets sama sekali)
            if "SIGN_KEY" in "\n".join(code_lines(rd(f))):
                self.assertIn(f, allowed, "SIGN_KEY di luar berkas yang diizinkan: %s" % f)

    def test_inv2_secret_only_in_process_job(self):
        jobs = T.job_blocks(rd(".github", "workflows", "process.yml"))
        holders = [j for j, b in jobs.items() if "secrets.SIGN_KEY" in b]
        self.assertEqual(holders, ["process"])
        self.assertIn("environment: signing", jobs["process"])

    def test_inv2_process_tag_never_prints_key(self):
        lines = [l for l in code_lines(rd(".github", "workflows", "process-tag.sh")) if "SIGN_KEY" in l]
        for l in lines:
            ok = ('${SIGN_KEY:?}' in l) or ('> "$KEY"' in l)
            self.assertTrue(ok, "pemakaian SIGN_KEY tak terduga: %s" % l.strip())

    # ── Invarian 3: template tidak pernah di-source / di-exec ──
    def test_inv3_no_source_or_eval_of_templates(self):
        pat = re.compile(r"(^|[;&|(]\s*|\s)(source|eval|\.)\s+[^#\n]*(template|\$t\b|\$\{?TPL)", re.M)
        for f in walk():
            if not (f.startswith("vdev") or f.startswith(".github") or f == "setup.sh"):
                continue
            if f.endswith("vdev/src/template.sh") or f.endswith("common.sh"):
                continue
            for l in code_lines(rd(f)):
                # `. "$VDEV_DIR/src/$_m.sh"` memuat modul kita sendiri, bukan resep
                if re.search(r"src/\$_m\.sh|src/(common|template|env|build|upload|git|search)\.sh", l):
                    continue
                self.assertIsNone(pat.search(l), "%s: %s" % (f, l.strip()))

    def test_inv3_process_job_sparse_checkout_and_no_template_access(self):
        jobs = T.job_blocks(rd(".github", "workflows", "process.yml"))
        self.assertIn("sparse-checkout: .github/workflows", jobs["process"])
        body = "\n".join(code_lines(rd(".github", "workflows", "process-tag.sh")))
        self.assertNotIn("pkg-template", body)
        self.assertNotIn("/template", body)

    # ── Invarian 4: upload repodata + .sig2 baru SEBELUM prune ──
    def test_inv4_upload_precedes_prune_statically(self):
        t = rd(".github", "workflows", "process-tag.sh")
        up = t.index('gh release upload "$TAG" "${up[@]}" --clobber')
        pr = t.index('cut -f2 "$WORK/prune_map" | sort -u > "$WORK/prune"')
        self.assertLess(up, pr)

    # ── Invarian 5: verifikasi isi paket via props.plist ──
    def test_inv5_props_plist_verification(self):
        t = rd(".github", "workflows", "process-tag.sh")
        for w in ("props.plist", "bsdtar -xOf", "architecture", "pkgver"):
            self.assertIn(w, t)

    # ── Invarian 6: allowlist identik di 3 tempat ──
    def test_inv6_allowlist_identical(self):
        pats = {
            "vdev/src/common.sh": re.findall(r"grep -qE '(\^\[A-Za-z0-9\._\+-\]\+\$)'", rd("vdev", "src", "common.sh")),
            ".github/workflows/process-tag.sh": re.findall(r"grep -qE '(\^\[A-Za-z0-9\._\+-\]\+\$)'", rd(".github", "workflows", "process-tag.sh")),
            "vdev/worker/index.js": re.findall(r"/(\^\[A-Za-z0-9\._\+-\]\+\$)/", rd("vdev", "worker", "index.js")),
        }
        for f, found in pats.items():
            self.assertTrue(found, "pola allowlist tidak ditemukan di %s" % f)
            for p in found:
                self.assertEqual(p, ALLOWLIST, f)

    # ── Invarian 7: cmpver via xbps-uhelper dengan kalibrasi dua probe ──
    def test_inv7_cmpver_calibration(self):
        t = rd(".github", "workflows", "process-tag.sh")
        self.assertIn("xbps-uhelper getpkgname", t)
        self.assertIn("xbps-uhelper cmpver 2.0_1 1.0_1", t)
        self.assertIn("xbps-uhelper cmpver 1.0_1 2.0_1", t)
        self.assertNotIn("sort -V", t)

    # ── Invarian 8: tidak ada edit release manual / upload .sig2 lokal ──
    def test_inv8_vdev_never_uploads_sig2_or_edits_release(self):
        up = rd("vdev", "src", "upload.sh")
        self.assertNotIn("sig2", up)
        self.assertIn('for f in "$VP"/hostdir/binpkgs/*.xbps; do', up, "glob upload harus persis *.xbps")
        self.assertEqual(up.count("gh release upload"), 1)
        for f in walk():
            if f.startswith("vdev" + os.sep):
                t = rd(f)
                for w in ("release edit", "release delete", "delete-asset"):
                    self.assertNotIn(w, t, f)

    # ── Invarian 9: keamanan workflow ──
    def test_inv9_process_yml_has_no_push_or_pr_triggers(self):
        ev = T.on_events(rd(".github", "workflows", "process.yml"))
        self.assertEqual(ev, {"workflow_dispatch", "schedule"})

    def test_inv9_test_yml_is_isolated_and_readonly(self):
        t = rd(".github", "workflows", "test.yml")
        self.assertEqual(T.on_events(t), {"pull_request", "push", "workflow_dispatch"})
        body = T.no_comments(t)
        for bad in ("pull_request_target", "workflow_run", "issue_comment", "schedule"):
            self.assertNotIn(bad, body)
        for bad in ("secrets.", "SIGN_KEY", "environment:", "contents: write", "id-token", "GITHUB_TOKEN"):
            self.assertNotIn(bad, body, "test.yml tidak boleh memuat %s" % bad)
        self.assertRegex(t, r"(?m)^permissions:\n  contents: read\n(?!  )")

    def test_inv9_only_known_workflow_files(self):
        self.assertEqual(sorted(os.listdir(WF)),
                         ["gen-json.py", "process-tag.sh", "process.yml", "test.yml"],
                         "berkas workflow baru/hilang: tinjau Invarian 9 lalu perbarui daftar ini")

    # ── Invarian 10: modul vdev/src bebas side-effect saat di-source ──
    def test_inv10_sourcing_modules_has_no_side_effects(self):
        cwd = T.mkdtemp("inv10.")
        for f in sorted(os.listdir(os.path.join(R, "vdev", "src"))):
            p = T.bash('. "%s/vdev/src/%s"' % (R, f), cwd=cwd)
            self.assertEqual((p.returncode, p.stdout, p.stderr), (0, "", ""), f)
            self.assertEqual(os.listdir(cwd), [], "%s membuat berkas saat di-source" % f)

    # ── Konsistensi lintas berkas (CLAUDE.md §6) ──
    def test_tag_list_consistent_across_files(self):
        files = ["vdev/src/common.sh", ".github/workflows/process.yml", ".github/workflows/gen-json.py",
                 "vdev/worker/index.js", "setup.sh"]
        for f in files:
            t = rd(*f.split("/"))
            missing = [x for x in T.ALL_TAGS if not re.search(r"(?<![\w-])%s(?![\w-])" % re.escape(x), t)]
            self.assertEqual(missing, [], "%s tidak memuat semua 9 tag" % f)
            self.assertNotIn('"i686-musl"', t.replace("i686-musl)", ""), f)

    def test_setup_fingerprint_matches_public_key(self):
        pub = rd("keys", "key.pem.pub").split()
        self.assertEqual(pub[0], "ssh-rsa")
        blob = base64.b64decode(pub[1])
        fp = ":".join("%02x" % b for b in hashlib.md5(blob).digest())
        m = re.search(r'^FINGERPRINT="([0-9a-f:]+)"', rd("setup.sh"), re.M)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), fp)

    def test_pkg_templates_are_flat_and_named_after_directory(self):
        base = os.path.join(R, "pkg-template")
        for d in sorted(os.listdir(base)):
            self.assertTrue(os.path.isfile(os.path.join(base, d, "template")), "%s tanpa template" % d)
            p = T.bash(T.vdev_src() + 'tpl_field "%s/%s/template" pkgname' % (base, d))
            self.assertEqual(p.stdout.strip(), d, "pkgname harus sama dengan nama direktori")
            self.assertRegex(d, ALLOWLIST.replace("^", "^").replace("$", "$"))


if __name__ == "__main__":
    T.main()
