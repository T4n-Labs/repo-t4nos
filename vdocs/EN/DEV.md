# T4n OS Repository — Developer & Maintainer Guide

Infrastructure for `repo-t4nos`: one GitHub repository for glibc and musl,
binaries on GitHub Releases, index in `json/`, everything automated by CI.
This repository produces binary packages only. The website lives in a separate
repository (`repo-site`).

> Source of truth is the code. Where this document and the code disagree, the
> code wins and the document is fixed. Items not proven by command output are
> marked "unverified". Status snapshot: 24 November 2026 (§12).

## 1. Golden Rules

1. **Binaries never enter git.** `.xbps`, `.xbps.sig2`, `<tag>-repodata` live on
   GitHub Releases. Git holds templates, scripts, docs, `json/`, `keys/key.pem.pub`.
2. **Signing happens only in CI**, in the `process` job, using `SIGN_KEY` from
   Environment `signing`. It never touches a developer machine. `vdev/` contains
   no `xbps-rindex` call and no key access.
3. **Never edit releases by hand.** CI reconciles fully: old versions pruned,
   orphaned index entries rebuilt. Manual edits get overwritten.
4. **Plan first, delete last.** New repodata + `.sig2` are uploaded before old
   assets are removed, so a client never reads an index pointing at a missing file.
5. **Templates are never `source`d.** They come from third parties. Parse with
   `grep`/`sed`/regex. The secret-holding job must not read templates at all —
   that is why it uses `sparse-checkout: .github/workflows`.

## 2. Layout

```
repo-t4nos/
├── .github/CODEOWNERS          # NOT PRESENT yet (planned; protection deferred, §12)
├── .github/workflows/
│   ├── process.yml             # the only workflow YAML (4 jobs)
│   ├── process-tag.sh          # per-tag: inventory → sign → prune (HOLDS SECRET)
│   └── gen-json.py             # per-tag: repodata + template → packages.json
├── json/<tag>/packages.json    # ×9, committed back by CI (currently only .gitkeep, §12)
├── keys/key.pem.pub            # the only public key file
├── pkg-template/<pkg>/template # flat, no category folders
├── vdev/
│   ├── tools.sh                # thin dispatcher
│   ├── DNS-check.sh            # read-only domain/Worker test (§13)
│   └── src/
│       ├── common.sh           # paths, constants, logging, guards
│       ├── template.sh         # template parser + archs expansion
│       ├── env.sh              # setup, sync, xbps-src flags
│       ├── build.sh            # architecture menu + build
│       ├── upload.sh           # release upload + CI trigger
│       └── git.sh              # push / pull-request offer
├── vdocs/{EN,ID}/{DEV,USER}.md
├── setup.sh                    # end-user one-liner
├── CONTRIBUTING.md / CONTRIBUTING.ID.md   # planned, not present yet
└── README.md / README.ID.md
```

Only `*.yml` in `.github/workflows/` is parsed as a workflow. The `.sh` and `.py`
files there are plain helpers, placed there for two concrete reasons:

- `process-tag.sh` holds the signing logic, so it inherits the CODEOWNERS +
  branch protection intended for `.github/workflows/`.
- The `process` job uses `sparse-checkout: .github/workflows`, so contributor
  templates are never checked out into the secret-holding job. The script it
  calls must therefore live inside that directory.

**Protection status (24 Nov 2026):** `.github/CODEOWNERS` does not exist and
`main` is unprotected (no ruleset, no classic protection). This is **deliberate**:
hardening is deferred until the repo is proven usable publicly. Upside: the
`commit` job can push `json/` freely. Downside: anyone with Write access can
change `.github/workflows/` without review. When hardening, enable both together
and allow `github-actions` + Founder to bypass, or the `commit` job fails 3× (§11).

### Release tags (9)

`x86_64` · `x86_64-musl` · `aarch64` · `aarch64-musl` · `armv6l` · `armv6l-musl` ·
`armv7l` · `armv7l-musl` · `i686`

Tag names equal XBPS architecture strings, so `xbps-uhelper arch` maps directly
to a tag with no lookup table. `i686-musl` is not provided.

### URLs

| Purpose | URL |
|---|---|
| Website (repo-site) | `https://repo-web.t4nlabs.web.id/` |
| XBPS endpoint | `https://repo.t4nlabs.web.id/<tag>` |
| Asset storage | `https://github.com/T4n-Labs/repo-t4nos/releases/download/<tag>` |

The XBPS endpoint is a reverse proxy (Cloudflare Worker `t4n-repo`) in front of
the release assets: `/<tag>/<file>` is forwarded to
`releases/download/<tag>/<file>`. GitHub Pages cannot do this, so the domain must
live in a Cloudflare zone. The Worker serves only the 9 tags and file names
matching `[A-Za-z0-9._+-]`; everything else gets 404. Only the Founder manages
the domain and Worker. The Worker proxies (streams bytes, supports Range), it
does not redirect file requests — verified by `DNS-check.sh` (§13).

## 3. Prerequisites

- Void Linux or T4n OS (or a `ghcr.io/void-linux/void-{glibc,musl}-full` container)
- `git`, `gh` (authenticated)
- `xbps-src` — fetched automatically by `vdev/tools.sh -s`
- **Write access** to `T4n-Labs/repo-t4nos` for uploading assets and triggering
  `workflow_dispatch`. Contributors with `Read` access work through fork + PR.

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

⚠️ A C package not musl-ready must list architectures explicitly; `*` makes CI
attempt a musl build and fail.

⚠️ **`noarch` is not a blanket rule.** It is safe only when the package has no
compiled ELF **and** no dependency with an auto-generated version bound. `letx`
(`python3-pep517`) carries `run_depends: python3>=3.14.0_1<3.15.0_1`, generated
from the build host; making it `noarch` bakes one host-derived bound that may be
unsatisfiable on other architectures. See §14.

Verify expansion without bootstrapping anything (`template.sh` defines functions
only, no `--selftest` mode):

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; expand_archs "x86_64* ~x86_64-musl"'
# → x86_64
```

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
- `distributor` identifies who packaged it (Let-X will fill it for third-party templates).
- Package names must stay inside `[A-Za-z0-9._+-]`. See §9.
- `tpkg` is pure shell with unversioned `depends="xbps"` → `archs=noarch` is
  correct: one build, fanned out to every tag. Without it, `-b` builds 9 times
  including 5 cross targets, triggering a source GCC build for nothing (§14).

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

Requested architectures are intersected with the template's `archs`; the
intersection is printed before building. `noarch` packages build once, on the
first selected target.

### Flag selection (`src/env.sh: flags_for`) — fixed and verified 24 Nov 2026

`-A` = masterdir/host, `-a` = cross target. **`-a` takes the FULL architecture
string, including `-musl`.** glibc has no suffix (`x86_64`, not `x86_64-glibc`).

| Situation | Flags |
|---|---|
| target **identical** to `HOST_ARCH` (full string) | none (native) |
| same base arch, different libc | `-A <full target>` |
| `i686` on `x86_64` host, same libc | `-A i686` (native 32-bit masterdir) |
| different base arch | `-a <full target>`, plus `-A <hostbase>-musl` when target is musl |

Verified output from an `x86_64` (glibc) host:

| Target | Flags |
|---|---|
| `x86_64` | *(none)* |
| `x86_64-musl` | `-A x86_64-musl` |
| `i686` | `-A i686` |
| `aarch64` | `-a aarch64` |
| `aarch64-musl` | `-A x86_64-musl -a aarch64-musl` |
| `armv6l` | `-a armv6l` |
| `armv6l-musl` | `-A x86_64-musl -a armv6l-musl` |
| `armv7l` | `-a armv7l` |
| `armv7l-musl` | `-A x86_64-musl -a armv7l-musl` |

From an `x86_64-musl` host: target `x86_64` → `-A x86_64`; target `x86_64-musl` →
no flags.

Two bugs that were fixed:

1. **`-a` used to strip `-musl`.** Target `armv6l-musl` produced `-a armv6l`, so
   the package actually built was **glibc** despite requesting musl — a silent
   failure, not an error. Now `-a armv6l-musl`.
2. **`-A <hostbase>-glibc` is invalid.** A musl host with a glibc target used to
   produce `-A x86_64-glibc`; that string does not exist in Void. Now `-A x86_64`.

Both are verified **at the flag-generation level**. Not yet tested: that
`xbps-src` accepts `-A x86_64` from a musl host and produces a correct glibc
package (the current dev host is glibc, so that direction has never been run).

Verify without building anything:

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; . vdev/src/env.sh
         for a in "${ALL[@]}"; do printf "%-14s → %s\n" "$a" "$(flags_for "$a" | xargs)"; done'
```

### Upload

```sh
vdev/tools.sh -u tpkg
```

1. Checks write access via `gh api repos/T4n-Labs/repo-t4nos --jq .permissions.push`.
2. **With write:** matches `.xbps` files in `void-packages/hostdir/binpkgs`
   against `pkgname` + subpackages and the template's `version_revision`, routes
   them to tags (`noarch` → every supported tag), uploads with `--clobber`, then
   triggers `process.yml` **once** with the list of touched tags.
3. **Without write:** upload and trigger are skipped, with a notice that a
   maintainer will build and upload after the PR is merged.
4. Either way, offers `git push`, and offers to open a PR if `origin` is a fork.

Only files matching the template's `version_revision` are uploaded; older builds
in `binpkgs` are skipped with a warning. The template is the source of truth, not
"the newest file in the folder". Order matters: **edit template → build → upload**.

Uploaded binaries are **unsigned**. CI signs them. There is a short window where
an asset exists without its `.sig2` — do not announce a release before the
workflow is green. Local `.sig2` files (from your own key) are deliberately not
uploaded: a signature made with a different key fails client verification. CI is
the single signer.

## 7. CI/CD Pipeline

### Triggers

- `workflow_dispatch` with input `tags` (default `all`) — called by
  `vdev/tools.sh -u` once after all uploads finish.
- `schedule` (`23 */6 * * *`) as a safety net; a no-op when nothing needs processing.

Push triggers are deliberately absent: uploading a release asset fires no event,
and events created by `GITHUB_TOKEN` do not trigger other workflows.
`concurrency: { group: repo-process, cancel-in-progress: false }` queues runs.

### Jobs

| # | Job | Secret | Reads templates | Task |
|---|---|---|---|---|
| 1 | `prepare` | no | no | resolve tags, create missing ones (idempotent) |
| 2 | `process` ×9 | **yes** | **no** | index, sign, prune per tag |
| 3 | `json` ×9 | no | yes | repodata + template → `packages.json` |
| 4 | `commit` | no | no | commit `json/**` once, only if changed |

⚠️ **Container shell trap (§14):** the `json` job's multi-line `run` block starts
with `set -euo pipefail`, but the Void container runs it under `sh`, which does
not support `pipefail`. That step needs `shell: bash`. As of 24 Nov 2026 this is
**not applied** (`grep -n 'shell: bash'` is empty), so all 9 `json` jobs fail at
line 1. The `process` job is unaffected because its `pipefail` lives inside
`process-tag.sh`, invoked with `bash`.

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
    "url": "<BASE>/x86_64/tpkg-1.1.0_1.noarch.xbps"
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
| `url` | `<BASE>/<tag>/<filename>`; `BASE` in `gen-json.py` (see §12) |
| `description` / `desc` | `short_desc` (`desc` is an alias for the current frontend) |
| `distributor` | template only |
| `status` | `ready` (binary present) or `recipe` (template only; `filename`/`size`/`url` are `null`) |

Subpackages (`-dbg`, `-doc`, `-devel`) have no template of their own, so their
`archs` falls back to `[tag]`.

## 8. Keys

```sh
ssh-keygen -t rsa -b 4096 -m PEM -f key.pem -N ""
cp key.pem.pub keys/key.pem.pub
gh secret set SIGN_KEY --env signing -R T4n-Labs/repo-t4nos < key.pem
```

- Back up `key.pem` offline. It is gitignored. **Never commit it.**
- Environment `signing` is intended to be restricted to branch `main`. As of
  24 Nov 2026 the branch restriction is **not configured** (§12); the secret
  exists and signing works, but the "main only" guarantee is not yet enforced.
- Only `keys/key.pem.pub` is public. `ssh-keygen` writes it in OpenSSH format
  (`ssh-rsa AAAA…`). The fingerprint you announce is the **XBPS** fingerprint:
  take it from the first key-import prompt (§12), not from `ssh-keygen -l`.
- Publish the fingerprint (README + website) so users can verify the first import.

**Rotation:** generate a new key → update the secret → dispatch `process.yml`
with `tags=all` (everything re-signed) → announce the new fingerprint → users
delete the old `.plist` and re-sync.

## 9. Filename Characters — Verified

Tested against a throwaway release:

| Uploaded | Stored | Download URL |
|---|---|---|
| `libfake++-1.0_1.x86_64.xbps` | unchanged | raw `+` **200**, `%2B` **200** |
| `libsigc++-2.0_1.x86_64.xbps` | unchanged | — |
| `gtk+3-3.24_1.x86_64.xbps` | unchanged | — |
| `foo~bar-1.0_1.x86_64.xbps` | `foo.bar-1.0_1.x86_64.xbps` | broken name |

`+` is safe; packages such as `libstdc++`, `gtk+3`, `libsigc++` may be packaged
here. `~` is renamed to `.`.

The dangerous part: the renamed result `foo.bar-...` **passes** a character
allowlist, because `.` is legal — while `props.plist` inside the package still
says `foo~bar-1.0_1`. The repodata then points at a file that does not exist and
the client gets 404.

That is why the real guard is **name verification**, not a character blocklist:
after download, read `props.plist` and require the asset name to equal
`<pkgver>.<architecture>.xbps` exactly. Parsing a plist is data parsing, not code
execution, so it stays safe inside the secret-holding job.

Characters outside `[A-Za-z0-9._+-]` are rejected up front. `:`, spaces and
parentheses have not been tested — do not assume they are safe. The Worker uses
the same allowlist: anything else gets 404 even if the file exists on the release.

## 10. Release Checklist

- [ ] Template correct: `archs`, `checksum`, `version` / `revision` convention
- [ ] If you touched the parser: run `expand_archs` on the §4 examples, results match
- [ ] If you touched `flags_for`: run the §6 verification, output matches the table
- [ ] Local build on the host plus at least one cross target
- [ ] `vdev/tools.sh -u <pkg>` → workflow triggered
- [ ] All CI jobs green (`gh run watch -R T4n-Labs/repo-t4nos`)
- [ ] Package shows `ready` on the website for the expected architectures
- [ ] `xbps-install -S && xbps-install <pkg>` succeeds on a clean test system
- [ ] Old version gone from the release tag (`gh release view <tag>`)

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `json` job: `set: Illegal option -o pipefail` | container runs `sh`; add `shell: bash` to that step (§14) |
| musl job fails | package not musl-ready → list archs explicitly, or fix the build |
| ARM build skipped | `nocross=` in the template — expected, or adapt for cross |
| Cross build takes hours | toolchain built from source; check `xbps-query -Rs cross-…` first (§14) |
| `props.plist` unreadable | asset is not a valid xbps package (e.g. a test dummy) |
| Asset name ≠ package contents | GitHub renamed a character; rename the package |
| Empty tag / sync 404 | no package landed in that tag yet; build the `noarch` tools first |
| 404 via `repo.t4nlabs.web.id` but release URL works | domain/Worker not active or DNS wrong → use the release URL, contact Founder |
| Install fails right after `-u` | binaries not signed yet; wait for the workflow |
| `commit json` warns 3× | branch protection blocks the bot's push; allow Founder + `github-actions` bypass, or drop the PR requirement |
| Website stale | index not regenerated; check the `json` and `commit` jobs |
| Domain looks broken | run `bash vdev/DNS-check.sh` and compare with §13 |

## 12. Implementation Status

Updated 24 November 2026. Every "verified" row has command output or CI log
evidence; everything else is marked explicitly.

### Verified

| Item | Evidence |
|---|---|
| `flags_for` correct for 13 host×target combinations | test output, matches §6 table |
| **Signing works** — tags hold `.xbps` + `.sig2` + `<tag>-repodata` | Releases screenshot (`tpkg-1.1.0_1`, then `_2`) |
| `SIGN_KEY` present in Environment `signing` | `gh secret list --env signing` |
| `.github/workflows/` = 3 files, no legacy | `ls -1` |
| `vdev/tools.sh` split into `src/` (6 modules) | `ls -1` |
| No `restricted`/`POLICY` in workflows or `vdev/` | empty `grep` |
| `process.yml` = 4 jobs (`prepare`, `process`, `json`, `commit`) | `grep` job keys |
| Worker + domain live | `DNS-check.sh` 14/14 (22 Nov) |
| `bash -n`, `sh -n`, `ast.parse` pass | command output |

### Outstanding / not applied

| Item | State |
|---|---|
| `shell: bash` in the `json` job | **not applied** (`grep` empty). Without it all 9 `json` jobs fail — §14 |
| `json/<tag>/packages.json` | never committed; folders still `.gitkeep` |
| `FINGERPRINT` in `setup.sh` | still a placeholder |
| End-to-end `xbps-install -S` through the domain | not done |
| `BASE` consistency | **check on disk** — snapshots disagree: `setup.sh` shows the domain, `gen-json.py` shows the release URL. They must match. Run `grep -n '^BASE' setup.sh .github/workflows/gen-json.py` |
| Branch protection, ruleset, `.github/CODEOWNERS` | **absent** — deferred until public usability is proven |
| Environment `signing` restricted to `main` | `deployment-branch-policies` 404 → not restricted |
| `CONTRIBUTING*`, LICENSE | absent / undecided |
| Tags `armv6l-musl`, `armv7l-musl` | no package yet → `xbps-install -S` 404 for those architectures |
| Build summary (Success/Failed per arch) | requested; application not confirmed |
| Numbered package menu, 18/page (`n`/`p`/`q`) | requested; application not confirmed |
| `tools search <query>` + `src/search.sh` | requested; application not confirmed |
| `./tools` and `./vdev/tools` (no `.sh`) | requested; application not confirmed |
| Mandatory `archs=noarch` rule | **undecided** — see §14 |
| PyYAML on the dev machine | not installed → the `yaml.safe_load` check (§10 of PROMPT) cannot run |

Remaining order: apply `shell: bash` → `json` jobs green → `json/` committed →
`xbps-install -S` on a clean system with a **manual conf pointing at the domain**
→ record the fingerprint → fill `FINGERPRINT` → make `BASE` identical in both
files → hardening.

**Important:** running `setup.sh` does **not** test the Worker if its `BASE` is
the release URL. The end-to-end test must write the conf manually:

```sh
echo 'repository=https://repo.t4nlabs.web.id/x86_64' | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

## 13. Verifying the `repo.t4nlabs.web.id` Domain

`vdev/DNS-check.sh` tests the domain without any XBPS binary. It is read-only, so
anyone with `curl` (and `dig` for the DNS part) can run it.

```sh
bash vdev/DNS-check.sh                  # DNS, TLS, Worker behaviour
PROBE=ping.txt bash vdev/DNS-check.sh   # + proxy 200 / Range / identical content
```

Optional variables: `BASE`, `WEB`, `GH`, `TAG` (default `x86_64-musl`), `PROBE`.
The script exits 0 only if every check passes.

| Group | What is checked |
|---|---|
| DNS | `t4nlabs.web.id` NS on Cloudflare; `repo` does not point at GitHub Pages |
| Worker | `/` → 302 to website; `/<tag>` and `/<tag>/` → 302 to release page; unknown tag → 404; invalid file name → 404; POST → 405 |
| Proxy | HEAD/GET → 200, Range → 206, content via domain equals content from GitHub (only with `PROBE`) |

Proxy test with a real file (needs write access, so the Founder runs it):

```sh
echo ping-ok > ping.txt
gh release upload x86_64-musl ping.txt -R T4n-Labs/repo-t4nos
PROBE=ping.txt bash vdev/DNS-check.sh
gh release delete-asset x86_64-musl ping.txt -R T4n-Labs/repo-t4nos -y
```

CI ignores assets other than `.xbps`, so `ping.txt` does no harm, but delete it
afterwards. `<tag>-repodata` returns 404 until a package has been processed; that
is expected, not a domain failure.

Reference result (22 November 2026): 14 passed, 0 failed.

## 14. Build & CI Traps — Verified

### `sh`, not `bash`, inside the Void container

CI log for the `json` job (23 Nov 2026):

```
shell: sh -e {0}
1: set: Illegal option -o pipefail
Error: Process completed with exit code 2.
```

The runner does not recognise the Void container as a bash-default distro, so the
`run` block executes under `sh`. `set -o pipefail` is unknown there → the step
dies on line 1, before any command runs. **All 9 `json` jobs failed** because of
this.

Fix: `shell: bash` on the step whose `run` block starts with `set -euo pipefail`.
`bash` is already installed by the green **Install tools** step, so later steps
may use it. Do not set `defaults.run.shell: bash` at job level — that would force
Install tools to use bash before bash exists.

### Cross toolchains may be built from source

```
ERROR: Could not find package 'cross-aarch64-linux-gnu'
=> xbps-src: installing cross compiler: cross-aarch64-linux-gnu ...
```

When the cross toolchain is unavailable as a binary package, `xbps-src` builds it
from source: binutils, two-stage GCC, libc headers. That is **1–3 hours** per
target on a laptop, not minutes. Check before attempting cross:

```sh
xbps-query -Rs cross-aarch64-linux-gnu
xbps-query -Rs cross-armv7l-linux-gnueabihf
```

For pure shell/script packages this work is entirely wasted — see the next item.

### Script packages without `archs=noarch` trigger pointless cross builds

`tpkg` contains shell plus `.sh` modules with an unversioned `depends="xbps"`.
Because its template did not declare `archs=noarch`, it was treated as supporting
9 architectures and `-b` built 9 times including 5 cross targets — triggering the
GCC build above just to copy six `.sh` files.

One `noarch` build produces a single `.noarch.xbps` that `cmd_upload` fans out to
every supported tag. **It saves build time, not storage**: the same file is stored
once per tag (9×).

⚠️ **Do not apply this blanket rule.** `letx` uses `build_style=python3-pep517`
and its `index.plist` carries `run_depends: python3>=3.14.0_1<3.15.0_1` — a bound
generated automatically from the python3 present in the masterdir at build time.
Making it `noarch` means one file carries one host-derived bound, which may be
unsatisfiable on architectures whose python3 revision differs. Check first:

```sh
cd void-packages/hostdir/binpkgs
for f in letx-1.0.0_1.*.xbps; do
  printf '%s: ' "$f"
  bsdtar -xOf "$f" props.plist | grep -A2 run_depends | tr -d '\n\t '
  echo
done
```

Safe `noarch` criteria: no compiled ELF **and** no dependency with an
auto-generated version bound.

### `-A` triggers auto-bootstrap, and its message says ERROR

```
=> ERROR: tpkg is not a bootstrap package and cannot be built without bootstrapping first.
=> binary bootstrapping for x86_64-musl in .../masterdir-x86_64-musl...
=> xbps-src: installing base-chroot...
```

This is **not a failure**. `cmd_setup` only guarantees the host masterdir; once
`-A` points at another masterdir that does not exist, `xbps-src` creates it
mid-build. The proof is the following lines continuing.

The cost is bounded: from an `x86_64` glibc host, 9 targets need only
**3 masterdirs** — `masterdir-x86_64` (native), `masterdir-x86_64-musl` (shared by
`x86_64-musl`, `aarch64-musl`, `armv6l-musl`, `armv7l-musl`), and `masterdir-i686`.

### Pruning only runs on processed tags

`-u` triggers `process.yml` with the list of touched tags, not all 9. Old versions
in other tags persist until those tags are processed. For a full sweep:

```sh
gh workflow run process.yml -R T4n-Labs/repo-t4nos -f tags=all
```

Unchanged tags skip quickly (`tidak ada yang perlu diproses`).

### Checks that cannot be run

`python3 -c "import yaml; yaml.safe_load(...)"` fails with
`ModuleNotFoundError: No module named 'yaml'` on the dev machine. **Do not count
it as passed.** Find the package name first (`xbps-query -Rs pyyaml`), install it,
then run. Dependency-free alternative — a structural probe, not a full parse:

```sh
grep -nE '^  [a-z][a-z-]*:$' .github/workflows/process.yml   # job keys
grep -n $'\t' .github/workflows/process.yml                  # tabs, must be 0
gh api repos/T4n-Labs/repo-t4nos/actions/workflows --jq '.workflows[]|{name,path,state}'
```

The last line validates on GitHub's side: if `process.yml` appears with
`state: active`, GitHub parsed it successfully.

---

**T4n Labs ◉ Gh0sT4n** — *Empowering the T4n Labs ecosystem.*