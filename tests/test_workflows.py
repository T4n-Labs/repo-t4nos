#!/usr/bin/env python3
"""Suite: struktur & keamanan workflow (process.yml, test.yml). PyYAML opsional."""
import os
import re
import sys
import unittest

sys.dont_write_bytecode = True  # tes tidak boleh menulis apa pun ke repo (__pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t4n_testlib as T  # noqa: E402

WF = os.path.join(T.REPO, ".github", "workflows")
REQUIRED_PATHS = {"vdev/**", ".github/workflows/**", "setup.sh", "pkg-template/**", "tests/**"}


def wf(name):
    return T.read(os.path.join(WF, name))


def uses(text):
    return re.findall(r"^\s*(?:-\s+)?uses:\s*([^\s#]+)", text, re.M)


class Workflows(T.TestCase):
    def test_no_tabs(self):
        for n in ("process.yml", "test.yml"):
            self.assertNotIn("\t", wf(n), n)

    def test_all_actions_pinned_to_full_sha(self):
        for n in ("process.yml", "test.yml"):
            found = uses(wf(n))
            self.assertTrue(found, n)
            for u in found:
                self.assertRegex(u, r"^[\w./-]+@[0-9a-f]{40}$", "%s: %s tidak dipin ke SHA penuh" % (n, u))

    def test_pins_documented_with_version_comment(self):
        for n in ("process.yml", "test.yml"):
            for l in wf(n).splitlines():
                if re.match(r"^\s*(-\s+)?uses:", l):
                    self.assertRegex(l, r"#\s*v\d+\.\d+\.\d+\s*$", "%s: %s" % (n, l.strip()))

    def test_same_sha_for_same_action_across_workflows(self):
        seen = {}
        for n in ("process.yml", "test.yml"):
            for u in uses(wf(n)):
                name, sha = u.split("@")
                self.assertEqual(seen.setdefault(name, sha), sha, "%s dipin ke SHA berbeda" % name)

    # ── test.yml ──
    def test_test_yml_triggers_and_paths(self):
        t = wf("test.yml")
        self.assertEqual(T.on_events(t), {"pull_request", "push", "workflow_dispatch"})
        for ev in ("pull_request", "push"):
            self.assertTrue(REQUIRED_PATHS <= set(T.event_paths(t, ev)), "paths %s kurang" % ev)
        self.assertRegex(t, r"(?s)  push:\s*\n    branches:\s*\n      - main\n")

    def test_test_yml_permissions_readonly_and_no_secrets(self):
        t = wf("test.yml")
        self.assertRegex(t, r"(?m)^permissions:\n  contents: read\n(?!  )")
        self.assertEqual(len(re.findall(r"(?m)^[ ]+permissions:", t)), 0, "tidak boleh menaikkan izin per job")
        for bad in ("secrets.", "SIGN_KEY", "environment:", "write"):
            self.assertNotIn(bad, T.no_comments(t), bad)

    def test_test_yml_checkout_does_not_persist_credentials(self):
        t = wf("test.yml")
        steps = re.split(r"(?m)^      - ", t)[1:]
        co = [s for s in steps if "actions/checkout@" in s]
        self.assertEqual(len(co), 1)
        self.assertIn("persist-credentials: false", co[0])

    def test_test_yml_runs_only_the_suite_without_expression_injection(self):
        t = wf("test.yml")
        runs = re.findall(r"(?m)^\s+run:\s*(.+)$", t)
        self.assertEqual(runs, ["bash tests/run.sh -v"])
        self.assertNotRegex("\n".join(runs), r"\$\{\{")

    def test_test_yml_has_timeout_and_cancelling_concurrency(self):
        t = wf("test.yml")
        self.assertRegex(t, r"timeout-minutes:\s*\d+")
        self.assertIn("cancel-in-progress: true", t)

    # ── process.yml ──
    def test_process_yml_default_permissions_readonly_and_per_job(self):
        t = wf("process.yml")
        self.assertRegex(t, r"(?m)^permissions:\n  contents: read\n(?!  )")
        jobs = T.job_blocks(t)
        self.assertEqual(set(jobs), {"prepare", "process", "json", "commit"})
        want = {"prepare": "write", "process": "write", "json": "read", "commit": "write"}
        for j, level in want.items():
            self.assertRegex(jobs[j], r"(?m)^    permissions:\n      contents: %s\b" % level, j)

    def test_process_yml_checkout_credentials_policy(self):
        jobs = T.job_blocks(wf("process.yml"))
        for j in ("process", "json"):
            self.assertIn("persist-credentials: false", jobs[j], j)

    def test_process_yml_json_job_has_no_secret_and_uses_bash_shell(self):
        jobs = T.job_blocks(wf("process.yml"))
        self.assertNotIn("secrets.", jobs["json"])
        self.assertIn("shell: bash", jobs["json"])

    def test_process_yml_image_not_hardcoded_latest(self):
        t = wf("process.yml")
        self.assertNotRegex(t, r"void-glibc-full:latest\s*$")
        self.assertIn("vars.VOID_IMAGE_TAG", t)

    def test_process_yml_concurrency_queues(self):
        t = wf("process.yml")
        self.assertIn("group: repo-process", t)
        self.assertIn("cancel-in-progress: false", t)

    def test_yaml_parses_when_pyyaml_available(self):
        try:
            import yaml  # noqa: WPS433
        except ImportError:
            self.skipTest("PyYAML tidak terpasang (opsional)")
        for n in ("process.yml", "test.yml"):
            d = yaml.safe_load(wf(n))
            self.assertIn("jobs", d)
            self.assertEqual(d["permissions"], {"contents": "read"})
        d = yaml.safe_load(wf("test.yml"))
        self.assertEqual(set(d["jobs"]), {"test"})
        self.assertEqual(set(d[True] if True in d else d["on"]), {"pull_request", "push", "workflow_dispatch"})


if __name__ == "__main__":
    T.main()
