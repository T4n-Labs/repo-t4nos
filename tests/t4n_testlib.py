"""Pustaka kecil untuk tests/*.py — stdlib saja. Tidak pernah menulis ke repo.

Semua direktori sementara dibuat lewat mkdtemp() dan dihapus saat proses keluar
(atexit), termasuk setelah SIGINT/SIGTERM/SIGHUP.
"""
import atexit
import json
import re
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.environ.get("T4N_REPO") or os.path.join(HERE, ".."))
VERBOSITY = 2 if os.environ.get("T4N_VERBOSE") == "1" else 1
ALL_TAGS = ["x86_64", "x86_64-musl", "aarch64", "aarch64-musl",
            "armv6l", "armv6l-musl", "armv7l", "armv7l-musl", "i686"]
GEN_JSON = os.path.join(REPO, ".github", "workflows", "gen-json.py")

_dirs = []


def _cleanup():
    for d in _dirs:
        shutil.rmtree(d, ignore_errors=True)


def _on_signal(signum, _frame):
    sys.exit(128 + signum)


atexit.register(_cleanup)
for _s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(_s, _on_signal)


def mkdtemp(prefix="t4n-py."):
    d = tempfile.mkdtemp(prefix=prefix, dir=os.environ.get("T4N_TMP") or None)
    _dirs.append(d)
    return d


def write(path, text, mode=None, newline=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline=newline) as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def clean_env(**extra):
    env = {k: v for k, v in os.environ.items()
           if k not in ("GH_TOKEN", "GITHUB_TOKEN", "SIGN_KEY", "SIGNEDBY", "TAG", "GH_REPO")}
    env.update(extra)
    return env


def bash(script, cwd=None, env=None, input=None, args=()):
    """Jalankan `bash -c script` dan kembalikan CompletedProcess (text)."""
    return subprocess.run(["bash", "-c", script, "bash", *args], cwd=cwd,
                          env=env or clean_env(), input=input,
                          capture_output=True, text=True)


def vdev_src(*mods):
    mods = mods or ("common", "template")
    return "; ".join('. "%s/vdev/src/%s.sh"' % (REPO, m) for m in mods) + "; "


def run_gen_json(cwd, tag):
    """Jalankan gen-json.py (black-box) di cwd; kembalikan (proc, daftar entri JSON)."""
    p = subprocess.run([sys.executable, GEN_JSON], cwd=cwd,
                       env=clean_env(TAG=tag), capture_output=True, text=True)
    out = os.path.join(cwd, "json", tag, "packages.json")
    data = json.loads(read(out)) if os.path.isfile(out) else None
    return p, data


def _trunc(x, n=300):
    x = x if isinstance(x, str) else repr(x)
    return x if len(x) <= n else x[:n] + "…(+%d)" % (len(x) - n)


class TestCase(unittest.TestCase):
    """unittest.TestCase dengan pesan gagal yang dipotong (tanpa membuang seluruh dokumen)."""

    def assertIn(self, member, container, msg=None):
        if member not in container:
            self.fail("%s%r tidak ada di %s" % ((msg + ": ") if msg else "", member, _trunc(container)))

    def assertNotIn(self, member, container, msg=None):
        if member in container:
            self.fail("%s%r tidak boleh ada di %s" % ((msg + ": ") if msg else "", member, _trunc(container)))

    def assertRegex(self, text, regex, msg=None):
        if not re.search(regex, text):
            self.fail("%spola %r tidak cocok di %s" % ((msg + ": ") if msg else "", regex, _trunc(text)))

    def assertNotRegex(self, text, regex, msg=None):
        m = re.search(regex, text)
        if m:
            self.fail("%spola %r cocok: %r" % ((msg + ": ") if msg else "", regex, _trunc(m.group(0))))


def no_comments(text):
    """Buang baris komentar penuh (# ...) — untuk pemeriksaan kata terlarang."""
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def main():
    unittest.main(verbosity=VERBOSITY)


# ── pembantu parsing workflow YAML tanpa PyYAML (regex sederhana, cukup untuk berkas kita) ──


def job_blocks(text):
    """{nama_job: teks_blok} dari bagian `jobs:` (job berindentasi 2 spasi)."""
    m = re.search(r"^jobs:\s*$", text, re.M)
    if not m:
        return {}
    parts = re.split(r"^  ([A-Za-z0-9_-]+):\s*$", text[m.end():], flags=re.M)
    return dict(zip(parts[1::2], parts[2::2]))


def on_block(text):
    m = re.search(r"^on:\s*\n((?:[ ]+.*\n|\n)+)", text, re.M)
    return m.group(1) if m else ""


def on_events(text):
    return set(re.findall(r"^  ([a-z_]+):", on_block(text), re.M))


def event_paths(text, event):
    m = re.search(r"^  %s:\s*\n((?:    .*\n)+)" % re.escape(event), on_block(text), re.M)
    if not m:
        return []
    pm = re.search(r"^    paths:\s*\n((?:      - .*\n)+)", m.group(1), re.M)
    return [x.strip().strip("'\"") for x in re.findall(r"^      - (.*)$", pm.group(1), re.M)] if pm else []
