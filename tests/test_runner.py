#!/usr/bin/env python3
"""Suite: perilaku tests/run.sh sendiri — pembersihan /tmp (trap), kode keluar, argumen."""
import os
import signal
import subprocess
import sys
import time
import unittest

sys.dont_write_bytecode = True  # tes tidak boleh menulis apa pun ke repo (__pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t4n_testlib as T  # noqa: E402

RUN = os.path.join(T.REPO, "tests", "run.sh")


def run(args, tmpdir, **kw):
    env = T.clean_env(TMPDIR=tmpdir)
    for k in ("T4N_TMP", "T4N_REPO", "T4N_VERBOSE"):
        env.pop(k, None)
    return subprocess.run(["bash", RUN, *args], env=env, capture_output=True, text=True, cwd=T.REPO, **kw)


class Runner(T.TestCase):
    def setUp(self):
        self.tmp = T.mkdtemp("runner.")

    def leftovers(self):
        return sorted(os.listdir(self.tmp))

    def test_list_matches_dispatcher(self):
        p = run(["-l"], self.tmp)
        self.assertEqual(p.returncode, 0)
        suites = p.stdout.split()
        self.assertEqual(suites, ["syntax", "runner", "invariants", "workflows", "docs",
                                  "parser_parity", "gen_json", "process_tag", "vdev"])
        for s in suites:   # setiap suite punya berkas pengujinya
            names = {"syntax": "test_syntax.sh", "vdev": "test_vdev.sh"}
            self.assertTrue(os.path.isfile(os.path.join(T.REPO, "tests", names.get(s, "test_%s.py" % s))), s)

    def test_help_and_bad_arguments(self):
        self.assertEqual(run(["-h"], self.tmp).returncode, 0)
        p = run(["tidak_ada"], self.tmp)
        self.assertEqual(p.returncode, 2)
        self.assertIn("suite tidak dikenal", p.stderr)
        self.assertEqual(run(["--bogus"], self.tmp).returncode, 2)
        self.assertEqual(self.leftovers(), [], "argumen salah tidak boleh meninggalkan berkas sementara")

    def test_temp_dir_removed_after_successful_run(self):
        p = run(["syntax"], self.tmp)
        self.assertEqual(p.returncode, 0, p.stdout[-400:])
        self.assertIn("SEMUA SUITE LULUS", p.stdout)
        self.assertEqual(self.leftovers(), [])

    def test_failing_suite_gives_exit_1_and_still_cleans_up(self):
        fake = T.mkdtemp("fakerepo.")
        os.makedirs(os.path.join(fake, "tests"))
        for f in os.listdir(os.path.join(T.REPO, "tests")):
            src = os.path.join(T.REPO, "tests", f)
            if os.path.isfile(src):
                T.write(os.path.join(fake, "tests", f), T.read(src), 0o755)
        T.write(os.path.join(fake, "tests", "test_syntax.sh"),
                '#!/usr/bin/env bash\n. "$(dirname "$0")/lib.sh"; t4n_init syntax; fail "sengaja gagal"; t4n_summary syntax\n', 0o755)
        env = T.clean_env(TMPDIR=self.tmp)
        p = subprocess.run(["bash", os.path.join(fake, "tests", "run.sh"), "syntax"], env=env,
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 1, p.stdout)
        self.assertIn("1 dari 1 suite GAGAL", p.stdout)
        self.assertEqual(self.leftovers(), [])

    def test_temp_dir_removed_when_killed_midway(self):
        env = T.clean_env(TMPDIR=self.tmp)
        proc = subprocess.Popen(["bash", RUN, "vdev"], env=env, cwd=T.REPO, start_new_session=True,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.time() + 20
            while time.time() < deadline and not any(n.startswith("t4n-tests.") for n in self.leftovers()):
                time.sleep(0.05)
            self.assertTrue(any(n.startswith("t4n-tests.") for n in self.leftovers()), "runner tidak membuat direktori temp")
            time.sleep(0.5)                                # biarkan suite benar-benar berjalan
            os.killpg(proc.pid, signal.SIGTERM)            # seperti pembatalan CI / Ctrl-C
            proc.wait(timeout=30)
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
        self.assertEqual(self.leftovers(), [], "direktori sementara tidak dibersihkan setelah SIGTERM")

    def test_runner_never_writes_into_repo(self):
        before = subprocess.run(["bash", "-c", "find . -path ./.git -prune -o -type f -printf '%p %s %T@\\n' | sort"],
                                cwd=T.REPO, capture_output=True, text=True).stdout
        run(["syntax", "gen_json", "parser_parity"], self.tmp)      # suite Python ikut → tidak boleh ada __pycache__
        after = subprocess.run(["bash", "-c", "find . -path ./.git -prune -o -type f -printf '%p %s %T@\\n' | sort"],
                               cwd=T.REPO, capture_output=True, text=True).stdout
        self.assertEqual(before, after, "suite mengubah berkas di dalam repo")
        self.assertFalse(os.path.exists(os.path.join(T.REPO, "tests", "__pycache__")))

    def test_unsets_credentials_for_suites(self):
        env = T.clean_env(TMPDIR=self.tmp, GH_TOKEN="rahasia-gh", GITHUB_TOKEN="rahasia-gh2", SIGN_KEY="rahasia-sign")
        probe = T.mkdtemp("probe.")
        os.makedirs(os.path.join(probe, "tests"))
        for f in os.listdir(os.path.join(T.REPO, "tests")):
            s = os.path.join(T.REPO, "tests", f)
            if os.path.isfile(s):
                T.write(os.path.join(probe, "tests", f), T.read(s), 0o755)
        T.write(os.path.join(probe, "tests", "test_syntax.sh"),
                '#!/usr/bin/env bash\necho "TOKENS=[${GH_TOKEN:-}${GITHUB_TOKEN:-}${SIGN_KEY:-}] GITCFG=${GIT_CONFIG_GLOBAL:-}"\n', 0o755)
        p = subprocess.run(["bash", os.path.join(probe, "tests", "run.sh"), "syntax"], env=env, capture_output=True, text=True)
        self.assertIn("TOKENS=[]", p.stdout)
        self.assertIn("GITCFG=/dev/null", p.stdout)


if __name__ == "__main__":
    T.main()
