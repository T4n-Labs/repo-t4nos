#!/usr/bin/env python3
"""Suite: .github/workflows/process-tag.sh dengan stub gh / xbps-uhelper / bsdtar / xbps-rindex.

Tidak ada jaringan, tidak ada xbps, tidak ada secret nyata. Fixture .xbps dibuat saat uji
berjalan (tar berisi props.plist) di direktori sementara — tidak ada biner yang masuk repo (Invarian 1).
"""
import io
import os
import plistlib
import sys
import tarfile
import unittest

sys.dont_write_bytecode = True  # tes tidak boleh menulis apa pun ke repo (__pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t4n_testlib as T  # noqa: E402

SCRIPT = os.path.join(T.REPO, ".github", "workflows", "process-tag.sh")
SECRET = "T4N-TEST-SECRET-KEY-DO-NOT-USE-0123456789"
T0, T1, T2, T3 = ("2026-11-24T10:00:00Z", "2026-11-25T10:00:00Z", "2026-11-26T10:00:00Z", "2026-11-27T10:00:00Z")

GH = r'''#!/usr/bin/env bash
echo "gh $*" >> "$T4N_H/calls.log"
case "$1 $2" in
  "api repos/"*) echo 1 ;;
  "api --paginate") cat "$T4N_H/fix/assets.tsv" ;;
  "release download") cp "$T4N_H/fix/files/$5" "$7/" ;;
  "release upload") shift 3; for f in "$@"; do [ "$f" = --clobber ] || echo "UPLOAD $(basename "$f")" >> "$T4N_H/events.log"; done ;;
  "release delete-asset") echo "DELETE $4" >> "$T4N_H/events.log" ;;
  *) echo "gh: subperintah tak terduga: $*" >&2; exit 99 ;;
esac
'''
UHELPER = r'''#!/usr/bin/env python3
import os, re, sys
c = sys.argv[1]
if c == "getpkgname":
    print(re.sub(r"-[^-]*$", "", sys.argv[2]))
elif c == "cmpver":
    if os.environ.get("T4N_CMPVER_BROKEN") == "1":
        sys.exit(0)                      # kedua probe tampak identik → harus membatalkan pruning
    k = lambda v: [int(x) for x in re.split(r"[._]", re.sub(r"^.*-(?=[0-9])", "", v))]
    a, b = k(sys.argv[2]), k(sys.argv[3])
    sys.exit(1 if a > b else (255 if a < b else 0))
'''
RINDEX = r'''#!/usr/bin/env bash
case "$1" in
  -a) echo "INDEX arch=$XBPS_ARCH $(shift; for f in "$@"; do basename "$f"; done | sort | tr '\n' ' ')" >> "$T4N_H/events.log"
      touch "$(dirname "$2")/$XBPS_ARCH-repodata" ;;
  --privkey)
      printf 'KEY %s %s %s\n' "$2" "$(stat -c %a "$2")" "$(cat "$2")" >> "$T4N_H/keys.log"
      case "$3" in
        --sign) echo "SIGN-REPODATA signedby=$5" >> "$T4N_H/events.log" ;;
        --sign-pkg) shift 3; for f in "$@"; do echo "SIGN-PKG $(basename "$f")" >> "$T4N_H/events.log"; touch "$f.sig2"; done ;;
      esac ;;
esac
'''


class Result:
    def __init__(self, rc, out, events, calls, keys):
        self.rc, self.out, self.events, self.calls, self.keys = rc, out, events, calls, keys

    def has(self, prefix):
        return any(e.startswith(prefix) for e in self.events)

    @property
    def uploads(self):
        return [e[7:] for e in self.events if e.startswith("UPLOAD ")]

    @property
    def deletes(self):
        return [e[7:] for e in self.events if e.startswith("DELETE ")]

    @property
    def mutated(self):
        return any(e.startswith(("UPLOAD", "DELETE", "INDEX", "SIGN")) for e in self.events)

    def upload_before_delete(self):  # Invarian 4
        ups = [i for i, e in enumerate(self.events) if e.startswith("UPLOAD")]
        dels = [i for i, e in enumerate(self.events) if e.startswith("DELETE")]
        return not ups or not dels or max(ups) < min(dels)


class ProcessTag(T.TestCase):
    def setUp(self):
        self.h = T.mkdtemp("ptag.")
        self.cwd = T.mkdtemp("ptagcwd.")
        os.makedirs(os.path.join(self.h, "bin"))
        os.makedirs(os.path.join(self.h, "fix", "files"))
        T.write(os.path.join(self.h, "bin", "gh"), GH, 0o755)
        T.write(os.path.join(self.h, "bin", "xbps-uhelper"), UHELPER, 0o755)
        T.write(os.path.join(self.h, "bin", "bsdtar"), '#!/usr/bin/env bash\nexec tar "$@"\n', 0o755)
        T.write(os.path.join(self.h, "bin", "xbps-rindex"), RINDEX, 0o755)

    # ── fixture ──
    def put(self, fn, pkgver, arch, corrupt=False):
        path = os.path.join(self.h, "fix", "files", fn)
        if corrupt:
            with open(path, "wb") as fh:
                fh.write(b"bukan arsip tar")
            return
        d = plistlib.dumps({"pkgver": pkgver, "architecture": arch})
        with tarfile.open(path, "w") as t:
            i = tarfile.TarInfo("props.plist")
            i.size = len(d)
            t.addfile(i, io.BytesIO(d))

    def pkg(self, name, ver, arch="x86_64", valid=True, corrupt=False):
        fn = "%s-%s.%s.xbps" % (name, ver, arch)
        self.put(fn, "%s-%s" % (name, ver), arch if valid else "noarch", corrupt)
        return fn

    def run_tag(self, assets, tag="x86_64", drop=(), **env):
        T.write(os.path.join(self.h, "fix", "assets.tsv"), "".join("%s\t%s\n" % a for a in assets))
        for f in ("calls.log", "events.log", "keys.log"):
            open(os.path.join(self.h, f), "w").close()
        e = T.clean_env(PATH=os.path.join(self.h, "bin") + os.pathsep + os.environ["PATH"], T4N_H=self.h,
                        TAG=tag, SIGN_KEY=SECRET, GH_REPO="x/y")
        e.update(env)
        for k in drop:
            e.pop(k, None)
        p = subprocess_run(["bash", SCRIPT], cwd=self.cwd, env=e)
        rd = lambda n: [l for l in T.read(os.path.join(self.h, n)).split("\n") if l]
        return Result(p.returncode, p.stdout + p.stderr, rd("events.log"), rd("calls.log"), rd("keys.log"))

    # ── (c1) re-upload nama sama → harus re-sign ──
    def test_same_name_reupload_with_old_sig2_is_resigned(self):
        f = self.pkg("tpkg", "1.1.0_2")
        r = self.run_tag([(f, T2), (f + ".sig2", T1), ("x86_64-repodata", T1)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("SIGN-PKG " + f, r.events)
        self.assertTrue(r.has("INDEX"))
        self.assertEqual(sorted(r.uploads), sorted([f + ".sig2", "x86_64-repodata"]))
        self.assertEqual(r.deletes, [])

    def test_fresh_signature_and_repodata_means_nothing_to_do(self):
        f = self.pkg("tpkg", "1.1.0_2")
        r = self.run_tag([(f, T2), (f + ".sig2", T3), ("x86_64-repodata", T3)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("tidak ada yang perlu diproses", r.out)
        self.assertEqual(r.events, [])
        self.assertFalse([c for c in r.calls if "release download" in c], "tidak perlu mengunduh apa pun")

    # ── (c2) versi baru gagal verifikasi tidak menghapus versi lama; (c3) tanpa churn ──
    def test_rejected_newer_version_keeps_older_valid_one_and_causes_no_churn(self):
        a, z = self.pkg("tpkg", "1.0_1"), self.pkg("zvc", "1.0_1")
        bad = self.pkg("tpkg", "1.1_1", valid=False)
        assets = [(a, T1), (a + ".sig2", T2), (bad, T2), (z, T1), (z + ".sig2", T2), ("x86_64-repodata", T3)]
        r = self.run_tag(assets)
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("DITOLAK", r.out)
        self.assertEqual(r.deletes, [], "versi lama yang valid tidak boleh dihapus")
        self.assertEqual(r.events, [], "tanpa churn: tidak ada index/upload ulang")
        r2 = self.run_tag(assets)          # run berikutnya: hasil identik (idempoten)
        self.assertEqual((r2.rc, r2.events), (0, []))

    def test_rejected_newer_version_with_other_work_still_keeps_older(self):
        a, z = self.pkg("tpkg", "1.0_1"), self.pkg("zvc", "1.0_1")
        bad = self.pkg("tpkg", "1.1_1", valid=False)
        r = self.run_tag([(a, T1), (a + ".sig2", T2), (bad, T2), (z, T1), ("x86_64-repodata", T3)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("SIGN-PKG " + z, r.events)
        self.assertEqual(r.deletes, [])
        idx = [e for e in r.events if e.startswith("INDEX")][0]
        self.assertIn(a, idx)
        self.assertNotIn("tpkg-1.1_1", idx)

    def test_each_package_decided_independently(self):
        ta, tbad = self.pkg("tpkg", "1.0_1"), self.pkg("tpkg", "1.1_1", valid=False)
        z0, z1 = self.pkg("zvc", "1.0_1"), self.pkg("zvc", "1.1_1")
        r = self.run_tag([(ta, T1), (ta + ".sig2", T2), (tbad, T2), (z0, T1), (z0 + ".sig2", T2),
                          (z1, T3), ("x86_64-repodata", T2)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertEqual(sorted(r.deletes), sorted([z0, z0 + ".sig2"]), "hanya zvc lama yang di-prune")
        idx = [e for e in r.events if e.startswith("INDEX")][0]
        self.assertTrue(ta in idx and z1 in idx and z0 not in idx)

    # ── (c) prune setelah upload (Invarian 4) ──
    def test_prune_happens_after_all_uploads_invariant_4(self):
        old, new = self.pkg("tpkg", "1.0_1"), self.pkg("tpkg", "1.2_1")
        r = self.run_tag([(old, T1), (old + ".sig2", T2), (new, T3), ("x86_64-repodata", T2)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("SIGN-PKG " + new, r.events)
        self.assertEqual(sorted(r.deletes), sorted([old, old + ".sig2"]))
        self.assertNotIn(new, r.deletes)
        self.assertTrue(r.upload_before_delete(), r.events)
        self.assertIn(new + ".sig2", r.uploads)
        self.assertIn("x86_64-repodata", r.uploads)

    def test_versions_compare_numerically_not_lexically(self):
        v9, v10 = self.pkg("tpkg", "1.9_1"), self.pkg("tpkg", "1.10_1")
        r = self.run_tag([(v9, T1), (v9 + ".sig2", T2), (v10, T3), ("x86_64-repodata", T2)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("SIGN-PKG " + v10, r.events)
        self.assertIn(v9, r.deletes)

    def test_same_pkgver_arch_specific_wins_and_noarch_is_pruned_after_upload(self):
        sp = self.pkg("tpkg", "1.0_1")
        na = self.pkg("tpkg", "1.0_1", arch="noarch")
        r = self.run_tag([(sp, T1), (na, T1), ("x86_64-repodata", T0)])
        self.assertEqual(r.rc, 0, r.out)
        idx = [e for e in r.events if e.startswith("INDEX")][0]
        self.assertIn(sp, idx)
        self.assertNotIn("noarch", idx)
        self.assertIn(na, r.deletes)
        self.assertTrue(r.upload_before_delete())

    # ── (c4) .sig2 yatim, tag kosong ──
    def test_orphan_sig2_is_removed_without_reindex(self):
        z = self.pkg("zvc", "1.0_1")
        r = self.run_tag([(z, T1), (z + ".sig2", T2), ("x86_64-repodata", T3), ("ghost-0.9_1.x86_64.xbps.sig2", T1)])
        self.assertEqual((r.rc, r.events), (0, ["DELETE ghost-0.9_1.x86_64.xbps.sig2"]), r.out)

    def test_orphan_sig2_is_removed_after_upload_when_there_is_work(self):
        z = self.pkg("zvc", "1.0_1")
        r = self.run_tag([(z, T2), ("x86_64-repodata", T1), ("ghost-0.9_1.x86_64.xbps.sig2", T1)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("DELETE ghost-0.9_1.x86_64.xbps.sig2", r.events)
        self.assertTrue(r.upload_before_delete())

    def test_empty_tag_removes_stale_repodata_and_orphans(self):
        r = self.run_tag([("x86_64-repodata", T1), ("ghost-0.9_1.x86_64.xbps.sig2", T1)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertEqual(set(r.events), {"DELETE ghost-0.9_1.x86_64.xbps.sig2", "DELETE x86_64-repodata"})

    def test_empty_tag_with_nothing_to_clean_is_a_noop(self):
        r = self.run_tag([("README.txt", T1)])
        self.assertEqual((r.rc, r.events), (0, []), r.out)

    # ── (c5) kegagalan verifikasi ──
    def test_no_package_passes_verification_fails_job_without_changes(self):
        bad = self.pkg("tpkg", "1.1_1", valid=False)
        r = self.run_tag([(bad, T2), ("x86_64-repodata", T1)])
        self.assertEqual(r.rc, 1, r.out)
        self.assertFalse(r.mutated)

    def test_trusted_file_failing_reverification_stops_without_changes(self):
        c = self.pkg("tpkg", "2.0_1", corrupt=True)
        z = self.pkg("zvc", "1.0_1")
        r = self.run_tag([(c, T1), (c + ".sig2", T2), (z, T2), ("x86_64-repodata", T1)])
        self.assertEqual(r.rc, 1, r.out)
        self.assertIn("tepercaya gagal verifikasi", r.out)
        self.assertFalse(r.mutated, r.events)

    def test_github_renamed_asset_is_rejected_by_props_plist_check_invariant_5(self):
        renamed = "foo.bar-1.0_1.x86_64.xbps"       # GitHub: '~' → '.'; lolos allowlist
        self.put(renamed, "foo~bar-1.0_1", "x86_64")
        z = self.pkg("zvc", "1.0_1")
        r = self.run_tag([(renamed, T2), (z, T2), ("x86_64-repodata", T1)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertIn("DITOLAK", r.out)
        idx = [e for e in r.events if e.startswith("INDEX")][0]
        self.assertNotIn("foo.bar", idx)
        self.assertIn(z, idx)

    def test_unsafe_names_and_foreign_arch_are_skipped_before_download(self):
        z = self.pkg("zvc", "1.0_1")
        r = self.run_tag([("tpkg-1.0~rc1_1.x86_64.xbps", T2), ("other-1.0_1.aarch64.xbps", T2), (z, T2),
                          ("x86_64-repodata", T1)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertEqual(r.out.count("::error::"), 2, r.out)
        dl = [c for c in r.calls if "release download" in c]
        self.assertEqual(len(dl), 1)
        self.assertIn(z, dl[0])

    def test_download_failure_aborts_without_changes(self):
        f = "tpkg-1.0_1.x86_64.xbps"      # terdaftar tetapi fixture berkasnya tidak ada
        r = self.run_tag([(f, T2), ("x86_64-repodata", T1)])
        self.assertNotEqual(r.rc, 0)
        self.assertFalse(r.mutated)

    # ── indeks basi / hilang ──
    def test_stale_repodata_triggers_reindex_without_resigning(self):
        f = self.pkg("tpkg", "1.0_1")
        r = self.run_tag([(f, T1), (f + ".sig2", T2), ("x86_64-repodata", T0)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertTrue(r.has("INDEX"))
        self.assertFalse(r.has("SIGN-PKG"))
        self.assertEqual(r.uploads, ["x86_64-repodata"])

    def test_missing_repodata_is_created(self):
        f = self.pkg("tpkg", "1.0_1")
        r = self.run_tag([(f, T1), (f + ".sig2", T2)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertTrue(r.has("INDEX"))
        self.assertEqual(r.uploads, ["x86_64-repodata"])

    # ── (c6) kalibrasi cmpver ──
    def test_ambiguous_cmpver_aborts_before_touching_anything(self):
        f = self.pkg("tpkg", "1.0_1")
        r = self.run_tag([(f, T1), ("x86_64-repodata", T0)], T4N_CMPVER_BROKEN="1")
        self.assertEqual(r.rc, 1)
        self.assertIn("pruning dibatalkan", r.out)
        self.assertEqual((r.events, r.calls), ([], []))

    # ── rahasia & lingkungan ──
    def test_sign_key_never_printed_file_private_and_removed(self):
        f = self.pkg("tpkg", "1.0_1")
        r = self.run_tag([(f, T1), ("x86_64-repodata", T0)])
        self.assertEqual(r.rc, 0, r.out)
        for blob in (r.out, "\n".join(r.calls), "\n".join(r.events)):
            self.assertNotIn(SECRET, blob, "SIGN_KEY bocor ke log/keluaran")
        self.assertTrue(r.keys, "xbps-rindex --privkey tidak dipanggil")
        _, path, mode, content = r.keys[0].split(" ", 3)
        self.assertEqual((mode, content), ("600", SECRET))
        self.assertFalse(os.path.exists(path), "berkas kunci sementara harus dihapus")
        self.assertFalse(os.path.exists(os.path.dirname(path)), "direktori kerja harus dihapus")

    def test_signedby_default_and_override(self):
        f = self.pkg("tpkg", "1.0_1")
        r = self.run_tag([(f, T1), ("x86_64-repodata", T0)])
        self.assertIn("SIGN-REPODATA signedby=T4n Labs", r.events)
        r = self.run_tag([(f, T1), ("x86_64-repodata", T0)], SIGNEDBY="Lain")
        self.assertIn("SIGN-REPODATA signedby=Lain", r.events)

    def test_index_runs_with_xbps_arch_of_the_tag(self):
        f = self.pkg("tpkg", "1.0_1", arch="aarch64-musl")
        r = self.run_tag([(f, T1), ("aarch64-musl-repodata", T0)], tag="aarch64-musl")
        self.assertEqual(r.rc, 0, r.out)
        self.assertTrue(any(e.startswith("INDEX arch=aarch64-musl ") for e in r.events), r.events)

    def test_missing_required_env_fails_fast(self):
        f = self.pkg("tpkg", "1.0_1")
        for var in ("SIGN_KEY", "TAG", "GH_REPO"):
            r = self.run_tag([(f, T1)], drop=(var,))
            self.assertNotEqual(r.rc, 0, var)
            self.assertEqual(r.calls, [], "%s: tidak boleh memanggil gh" % var)

    def test_script_uses_only_expected_gh_subcommands(self):
        """Stub menolak subperintah gh tak dikenal; secara statis script juga tidak boleh memakainya."""
        t = T.read(SCRIPT)
        for bad in ("release edit", "release create", "release delete "):
            self.assertNotIn(bad, t)

    # ── Invarian 3 pada job pemegang secret ──
    def test_poisoned_pkg_template_in_cwd_is_never_executed_or_needed(self):
        T.write(os.path.join(self.cwd, "pkg-template", "evil", "template"),
                "pkgname=evil\n$(touch PWNED1)\ntouch PWNED2\n")
        f = self.pkg("tpkg", "1.0_1")
        r = self.run_tag([(f, T1), ("x86_64-repodata", T0)])
        self.assertEqual(r.rc, 0, r.out)
        self.assertEqual([x for x in os.listdir(self.cwd) if x.startswith("PWNED")], [])
        r2 = self.run_tag([(f, T1), ("x86_64-repodata", T0)])
        os.rename(os.path.join(self.cwd, "pkg-template"), os.path.join(self.cwd, "moved"))
        r3 = self.run_tag([(f, T1), ("x86_64-repodata", T0)])
        self.assertEqual((r2.rc, r3.rc), (0, 0), "hasil tidak boleh bergantung pada keberadaan pkg-template/")
        self.assertEqual(r2.events, r3.events)


def subprocess_run(cmd, cwd, env):
    import subprocess
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)


if __name__ == "__main__":
    T.main()
