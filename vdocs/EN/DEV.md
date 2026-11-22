# T4n OS Repository — Developer & Maintainer Guide

Infrastructure for `repo-t4nos`: **one GitHub repository for glibc and musl**,
binaries on **GitHub Releases**, index in `json/`, everything automated by CI.

This repository produces **binary packages only**. The website lives in a
separate repository (`repo-site`).

---

## 1. Golden Rules

1. **Binaries never enter git.** `.xbps`, `.xbps.sig2` and `<tag>-repodata` live
   on GitHub Releases. Git holds templates, scripts, docs and `json/`.
2. **Signing happens only in CI.** The private key lives in GitHub Secrets
   (Environment `signing`, restricted to `main`). It never touches a developer
   machine. `vdev/tools.sh` contains no `xbps-rindex` call and no key access.
3. **Never edit releases by hand.** CI reconciles them fully: old versions are
   pruned, orphaned index entries are rebuilt. Manual edits get overwritten.
4. **Plan first, delete last.** New repodata is uploaded *before* old assets are
   removed, so a client never reads an index pointing at a missing file.
5. **Templates are never `source`d.** They come from third parties. Parse them
   with `grep`/`sed`/regex. The job holding the secret must not read templates
   at all.

---

## 2. Layout

```
repo-t4nos/
├── .github/CODEOWNERS          # workflows/, setup.sh, keys/ → Founder
├── .github/workflows/
│   ├── process.yml         # the only workflow YAML
│   ├── process-tag.sh      # per-tag: inventory → sign → prune (HOLDS SECRET)
│   └── gen-json.py         # per-tag: repodata + template → packages.json
├── json/<tag>/packages.json    # ×9, committed back by CI
├── keys/key.pem.pub            # the only public key file
├── pkg-template/<pkg>/template # flat, no category folders
├── vdev/
│   ├── tools.sh            # thin dispatcher
│   └── src/
│       ├── common.sh       # paths, constants, logging, guards
│       ├── template.sh     # template parser + archs expansion
│       ├── env.sh          # setup, sync, xbps-src flags
│       ├── build.sh        # architecture menu + build
│       ├── upload.sh       # release upload + CI trigger
│       └── git.sh          # push / pull-request offer
├── worker/index.js             # copy of the Cloudflare Worker (repo.t4nlabs.web.id proxy)
├── vdocs/{EN,ID}/{DEV,USER}.md
├── setup.sh                # end-user one-liner
├── CONTRIBUTING.md / CONTRIBUTING.ID.md   # planned, not present yet
└── README.md / README.ID.md
```

Only `*.yml` files in `.github/workflows/` are parsed as workflows. The `.sh`
and `.py` files there are plain helpers — they live in that directory for two
concrete reasons:

- `process-tag.sh` contains the signing logic, so it inherits the CODEOWNERS +
  branch protection applied to `.github/workflows/`.
- The `process` job uses `sparse-checkout: .github/workflows`, so contributor
  templates are never checked out into the job holding the secret. The script
  it calls must therefore live inside that directory.

### Release tags (9)

`x86_64` · `x86_64-musl` · `aarch64` · `aarch64-musl` · `armv6l` ·
`armv6l-musl` · `armv7l` · `armv7l-musl` · `i686`

Tag names equal XBPS architecture strings, so `xbps-uhelper arch` maps directly
to a tag with no lookup table.

### URLs

| Purpose | URL |
|---|---|
| Website (repo-site) | `https://repo-web.t4nlabs.web.id/` |
| XBPS endpoint | `https://repo.t4nlabs.web.id/<tag>` |
| Asset storage | `https://github.com/T4n-Labs/repo-t4nos/releases/download/<tag>` |

The XBPS endpoint is a thin **reverse proxy** (Cloudflare Worker `t4n-repo`) in
front of the release assets: `/<tag>/<file>` is forwarded to
`releases/download/<tag>/<file>`. GitHub Pages cannot do this, so the domain
`repo.t4nlabs.web.id` must live in a Cloudflare zone. The Worker serves only the
9 tags and file names matching `[A-Za-z0-9._+-]`; everything else gets a 404.
Until the domain is active, use the release URL directly. Only the Founder
manages the domain and the Worker.

---

## 3. Prerequisites

- Void Linux or T4n OS (or a `ghcr.io/void-linux/void-{glibc,musl}-full` container)
- `git`, `gh` (authenticated)
- `xbps-src` — fetched automatically by `vdev/tools.sh -s`
- **Write access** to `T4n-Labs/repo-t4nos` for uploading assets and triggering
  `workflow_dispatch`. Contributors with `Read` access work through fork + PR.

---

## 4. `archs` Semantics

Glob matching, identical to `xbps-src`.

| Value | Result |
|---|---|
| unset / empty | all 9 tags |
| `noarch` | all 9 tags; built once, fanned out |
| `x86_64` | glibc x86_64 only |
| `x86_64*` | `x86_64` **and** `x86_64-musl` |
| `x86_64* aarch64` | `x86_64`, `x86_64-musl`, `aarch64` |
| `~i686` | all tags except `i686` |
| `x86_64* ~x86_64-musl` | `x86_64` only |

⚠️ A C package that is not musl-ready must list architectures explicitly. Using
`*` will make CI attempt a musl build and fail.

Pure shell/script tools (`zvc`, `letx`, `tpkg`) should use `archs=noarch`: one
build produces a `.noarch.xbps` that is uploaded to every supported tag.

Verify `archs` expansion without bootstrapping anything. `template.sh` only
defines functions and has no `--selftest` mode, so call the function directly:

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; expand_archs "x86_64* ~x86_64-musl"'
# → x86_64
```

---

## 5. Creating a Package

`pkg-template/tpkg/template`:

```sh
# Template file for 'tpkg'
pkgname=tpkg
version=1.1.0
revision=1
archs=noarch
short_desc="A user-friendly package manager wrapper for XBPS"
maintainer="Gh0sT4n <darskevoid@gmail.com>"
distributor="Gh0sT4n <darskevoid@gmail.com>"
license="BSD-2-Clause"
homepage="https://gitlab.com/t4n-pkg/tpkg/"
distfiles="https://gitlab.com/t4n-pkg/tpkg/-/archive/v${version}/tpkg-${version}.tar.gz"
checksum=b0873267cd08fefa9855a11e5f5207cff677a8781896bdafdf05ef5d3d450858
depends="xbps"

do_install() {
    vinstall tpkg 755 usr/bin
    vmkdir usr/lib/tpkg
    for _mod in core usage cmd_query cmd_pkg cmd_repo; do
        vinstall "lib/${_mod}.sh" 644 usr/lib/tpkg
    done
    vdoc README.md
    vlicense LICENSE
}
```

Conventions:

- `version` **without** the revision. Correct: `version=1.1.0 revision=1`.
  Wrong: `version=1.1.0_1`.
- Bump `revision` for template-only changes; reset to `1` on a new upstream version.
- `distributor` identifies who packaged it (added by Let-X for third-party templates).
- Package names must stay inside `[A-Za-z0-9._+-]`. See §9.

---

## 6. Developer Workflow

`vdev/tools.sh` is a thin dispatcher; all logic lives in `vdev/src/*.sh`. Those
modules define functions only — sourcing them has no side effects, so CI and
Let-X can reuse them safely.

```sh
vdev/tools.sh -s              # clone void-packages + binary-bootstrap
vdev/tools.sh -sy             # git pull + copy new/changed templates
vdev/tools.sh -b <pkg>        # build
vdev/tools.sh -u <pkg>        # upload + trigger CI, then offer push/PR
```

### Build

```sh
vdev/tools.sh -b                          # interactive
vdev/tools.sh -b tpkg zvc                 # several packages
vdev/tools.sh -b radare2 -a aarch64       # one architecture
vdev/tools.sh -b radare2 -a all           # all supported
vdev/tools.sh -b radare2 -a x86_64 i686   # several
vdev/tools.sh -b radare2 -a 'x86_64*'     # glibc + musl x86_64
```

Interactive architecture menu:

```
[+] Architecture
    [1] x86_64         [6] armv6l-musl
    [2] x86_64-musl    [7] armv7l
    [3] aarch64        [8] armv7l-musl
    [4] aarch64-musl   [9] i686
    [5] armv6l         [0] All
[?] Choose (space separated, e.g. 1 3 6) [default: host]:
```

Requested architectures are intersected with the template's `archs`; the
intersection is printed before building.

Flag selection (`src/env.sh: flags_for`):

| Situation | Flags |
|---|---|
| target == host (arch + libc) | none (native) |
| `i686` on x86_64, same libc | `-A i686` (native 32-bit masterdir) |
| different libc | `-A <hostbase>-<targetlibc>` |
| different base arch | `-a <targetbase>` |

`noarch` packages are built once, on the first selected target.

### Upload

```sh
vdev/tools.sh -u tpkg
```

1. Checks write access via `gh api repos/T4n-Labs/repo-t4nos --jq .permissions.push`.
2. **With write access:** matches `.xbps` files in `void-packages/hostdir/binpkgs`
   against `pkgname` + subpackages and the template's `version_revision`, routes
   them to tags (`noarch` → every supported tag), uploads with `--clobber`, then
   triggers `process.yml` **once** with the list of touched tags.
3. **Without write access:** upload and trigger are skipped, with a notice that
   a maintainer will build and upload after the PR is merged.
4. Either way, offers `git push`, and offers to open a PR if `origin` is a fork.

Uploaded binaries are **unsigned**. CI signs them. There is a short window where
an asset exists without its `.sig2` — do not announce a release before the
workflow is green.

Local `.sig2` files (from your own key) are deliberately **not** uploaded: a
signature made with a different key would fail client verification. CI is the
single signer.

---

## 7. CI/CD Pipeline

### Triggers

- `workflow_dispatch` with input `tags` (default `all`) — called by
  `vdev/tools.sh -u` once after all uploads finish.
- `schedule` (cron) as a safety net; a no-op when nothing needs processing.

Push triggers are deliberately absent: uploading a release asset fires no event,
and events created by `GITHUB_TOKEN` do not trigger other workflows.

`concurrency: { group: repo-process, cancel-in-progress: false }` queues runs
instead of letting them overwrite each other.

### Jobs

| # | Job | Secret | Reads templates | Task |
|---|---|---|---|---|
| 1 | `prepare` | no | no | resolve tags, create missing ones (idempotent) |
| 2 | `process` ×9 | **yes** | **no** | index, sign, prune per tag |
| 3 | `json` ×9 | no | yes | repodata + template → `packages.json` |
| 4 | `commit` | no | no | commit `json/**` once, only if changed |

### Inside `process` (per tag)

```
inventory   list assets via the paginated API
plan        group .xbps by package name, keep the highest version+revision
            (xbps-uhelper getpkgname / cmpver — never regex)
            everything else → prune list
            unsigned = kept files without a .sig2
            if unsigned and prune are both empty and repodata exists → skip
download    kept files into an EMPTY working directory
verify      read props.plist inside each .xbps; the asset name must equal
            <pkgver>.<architecture>.xbps exactly, otherwise reject
[1/3] index xbps-rindex -a *.xbps            → <tag>-repodata
[2/3] sign  xbps-rindex --sign               → public key embedded in repodata
[3/3] sign  xbps-rindex --sign-pkg           → .sig2 for unsigned packages only
upload      new repodata + new .sig2 FIRST
prune       delete old .xbps + .sig2 LAST
```

Two details worth knowing:

- **`cmpver` calibration.** Rather than assuming whether `xbps-uhelper cmpver`
  reports via stdout or exit code, the script runs two probes with known answers
  and matches the signature. If both probes look identical, pruning is aborted
  rather than risking deletion of the wrong version.
- **Empty tag.** If nothing is kept, prune runs and the stale repodata is removed
  so clients do not read an index pointing at deleted files.

### `packages.json` schema

`json/<tag>/packages.json` is a JSON array. Metadata comes from `index.plist`
inside the repodata; fields absent there are taken from the template.

```json
[
  {
    "name": "tpkg",
    "version": "1.1.0",
    "arch": "x86_64",
    "archs": ["x86_64", "x86_64-musl", "aarch64", "..."],
    "filename": "tpkg-1.1.0_1.noarch.xbps",
    "size": 184320,
    "status": "ready",
    "description": "A user-friendly package manager wrapper for XBPS",
    "desc": "A user-friendly package manager wrapper for XBPS",
    "homepage": "https://gitlab.com/t4n-pkg/tpkg/",
    "maintainer": "Gh0sT4n <darskevoid@gmail.com>",
    "distributor": "Gh0sT4n <darskevoid@gmail.com>",
    "license": "BSD-2-Clause",
    "url": "https://github.com/T4n-Labs/repo-t4nos/releases/download/x86_64/tpkg-1.1.0_1.noarch.xbps"
  }
]
```

| Field | Source |
|---|---|
| `name` | `pkgname` |
| `version` | `version` from repodata, revision stripped |
| `arch` | the tag |
| `archs` | template `archs`, expanded |
| `filename`, `size` | release asset metadata |
| `url` | `<BASE>/<tag>/<filename>`; `BASE` in `gen-json.py` (currently the GitHub release URL, see §12) |
| `description` / `desc` | `short_desc` (`desc` is an alias for the current frontend) |
| `distributor` | template only |
| `status` | `ready` (binary present) or `recipe` (template only, `filename`/`size`/`url` are `null`) |

Subpackages (`-dbg`, `-doc`, `-devel`) have no template of their own, so their
`archs` falls back to `[tag]`.

---

## 8. Keys

```sh
ssh-keygen -t rsa -b 4096 -m PEM -f key.pem -N ""
cp key.pem.pub keys/key.pem.pub
gh secret set SIGN_KEY --env signing -R T4n-Labs/repo-t4nos < key.pem
```

- Back up `key.pem` offline. It is gitignored. **Never commit it.**
- The Environment `signing` is restricted to branch `main`, so workflows on other
  branches and forks cannot read the secret.
- Only `keys/key.pem.pub` is public. `ssh-keygen` writes this file in OpenSSH
  format (`ssh-rsa AAAA…`). The fingerprint you announce to users is the **XBPS**
  fingerprint: take it from the first key-import prompt (see §12), not from
  `ssh-keygen -l`.
- Publish the fingerprint (README + website) so users can verify the first import.

**Rotation:** generate a new key → update the secret → dispatch `process.yml`
with `tags=all` (everything is re-signed) → announce the new fingerprint → users
delete the old `.plist` and re-sync.

---

## 9. Filename Characters — Verified

Tested against a throwaway release:

| Uploaded | Stored | Download URL |
|---|---|---|
| `libfake++-1.0_1.x86_64.xbps` | unchanged | raw `+` **200**, `%2B` **200** |
| `libsigc++-2.0_1.x86_64.xbps` | unchanged | — |
| `gtk+3-3.24_1.x86_64.xbps` | unchanged | — |
| `foo~bar-1.0_1.x86_64.xbps` | `foo.bar-1.0_1.x86_64.xbps` | broken name |

**`+` is safe**; packages such as `libstdc++`, `gtk+3`, `libsigc++` may be
packaged here. **`~` is renamed to `.`.**

The dangerous part: the renamed result `foo.bar-...` **passes** a character
allowlist, because `.` is legal — while `props.plist` inside the package still
says `foo~bar-1.0_1`. The repodata then points at a file that does not exist and
the client gets a 404.

That is why the real guard is **name verification**, not a character blocklist:
after download, read `props.plist` and require the asset name to equal
`<pkgver>.<architecture>.xbps` exactly. Parsing a plist is data parsing, not code
execution, so it stays safe inside the secret-holding job.

Characters outside `[A-Za-z0-9._+-]` are rejected up front. `:`, spaces and
parentheses have not been tested — do not assume they are safe.

The `repo.t4nlabs.web.id` Worker uses the same allowlist (`[A-Za-z0-9._+-]`):
anything else gets a 404 even if the file exists on the release.

---

## 10. Release Checklist

- [ ] Template correct: `archs`, `checksum`, `version` / `revision` convention
- [ ] If you touched the parser: run `expand_archs` on the §4 examples, results must match the table
- [ ] Local build on the host plus at least one cross target
- [ ] `vdev/tools.sh -u <pkg>` → workflow triggered
- [ ] All CI jobs green (`gh run watch -R T4n-Labs/repo-t4nos`)
- [ ] Package shows `ready` on the website for the expected architectures
- [ ] `xbps-install -S && xbps-install <pkg>` succeeds on a clean test system
- [ ] Old version gone from the release tag (`gh release view <tag>`)

---

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| musl job fails | package not musl-ready → list archs explicitly, or fix the build |
| ARM build skipped | `nocross=` in the template — expected, or adapt for cross |
| `props.plist` unreadable | asset is not a valid xbps package (e.g. a test dummy) |
| Asset name ≠ package contents | GitHub renamed a character; rename the package |
| Empty tag / sync 404 | no package landed in that tag yet; build the `noarch` tools first |
| 404 via `repo.t4nlabs.web.id` but the release URL works | domain/Worker not active yet or DNS wrong → use the release URL directly, contact the Founder |
| Install fails right after `-u` | binaries not signed yet; wait for the workflow |
| `commit json` warns 3× | branch protection blocks the bot's push; allow the Founder and `github-actions` to bypass, or drop the PR requirement |
| Website stale | index not regenerated; check the `json` and `commit` jobs |

---

## 12. Implementation Status

As of 22 November 2026. Checked against the code: `process.yml` is valid and has
four jobs (`prepare`, `process`, `json`, `commit`); there is no `policy` or
`deploy` job; every script passes `bash -n`. What remains waits for the domain
to go live:

| Item | Target | Current state |
|---|---|---|
| Base URL in `setup.sh` | `https://repo.t4nlabs.web.id` | `BASE` is still the GitHub release URL (temporary) |
| `url` field in `packages.json` | domain | `BASE` in `gen-json.py` is still the GitHub release URL |
| Key fingerprint | published in README + website | `FINGERPRINT` in `setup.sh` is still a placeholder; fill it after the first sync |
| Worker + domain | `repo.t4nlabs.web.id/<tag>` live | Worker `t4n-repo` is created; the custom domain is attached once the `t4nlabs.web.id` zone is Active in Cloudflare |
| End-to-end verification | `xbps-install -S` through the domain, including first key import | not done yet |

Order: domain active → `curl -I` against the domain → `xbps-install -S` on a
clean system (note the fingerprint from the prompt) → fill in `FINGERPRINT` →
switch `BASE` in `setup.sh` and `gen-json.py` → announce.

---

**T4n Labs ◉ Gh0sT4n** — *Empowering the T4n Labs ecosystem.*