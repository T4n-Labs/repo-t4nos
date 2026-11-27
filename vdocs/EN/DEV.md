# T4n OS Repository — Developer & Maintainer Guide

Infrastructure for `repo-t4nos`: one GitHub repository for glibc and musl,
binaries on GitHub Releases, index in `json/`, everything automated by CI.
This repository produces binary packages only. The website lives in a separate
repository (`repo-site`).

> Source of truth is the code. Where this document and the code disagree, the
> code wins and the document is fixed. Items not proven by command output are
> marked "unverified". Status snapshot: 25 November 2026 (§12); GitHub/Cloudflare/website claims date from 22–24 November and were not re-verified.

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
│   ├── process-tag.sh          # per-tag: inventory → verify → sign → prune (HOLDS SECRET)
│   └── gen-json.py             # per-tag: repodata + template → packages.json
├── json/<tag>/packages.json    # ×9, committed back by CI
├── keys/key.pem.pub            # the only public key file
├── pkg-template/<pkg>/template # flat, no category folders (currently: tpkg, zvc)
├── vdev/
│   ├── tools.sh                # thin dispatcher
│   ├── DNS-check.sh            # read-only domain/Worker test (§13)
│   ├── worker/index.js         # Cloudflare Worker `t4n-repo` (managed by the Founder)
│   └── src/
│       ├── common.sh           # paths, constants, logging, guards (name_safe, pkg_safe)
│       ├── template.sh         # template parser + archs expansion
│       ├── env.sh              # setup, sync, xbps-src flags
│       ├── build.sh            # package/architecture menus + build
│       ├── upload.sh           # release upload + CI trigger
│       ├── git.sh              # push / pull-request offer
│       └── search.sh           # `tools search <query>`
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
| `all` | all 9 tags (same as `*`) |
| `all ~i686` | all tags except `i686` |
| `~~i686` | same as `~i686` (the number of `~` is not distinguished) |

⚠️ A C package not musl-ready must list architectures explicitly; `*` makes CI
attempt a musl build and fail.

⚠️ **`noarch` is not a blanket rule.** It is safe only when the package has no
compiled ELF **and** no dependency with an auto-generated version bound. Classic
example: a Python package with `build_style=python3-pep517` (e.g. `letx`, whose
template has been tidied out of `pkg-template/` in this snapshot) carries
`run_depends: python3>=3.14.0_1<3.15.0_1`, generated from the build host; making it
`noarch` bakes one host-derived bound that may be unsatisfiable on other
architectures. See §14.

**Parser contract.** There are two template parsers — Bash/awk
(`vdev/src/template.sh`) and Python (`.github/workflows/gen-json.py`) — and they
**must behave identically**; change both together:

- Field: the first line matching `^[ \t]*KEY=`. `#` starts a comment only outside
  quotes **and** at the start of the value / after a space or tab (`"https://x/#a"`
  and `"A # B"` are safe). Backslash escapes the next character (except inside single
  quotes). Then trim space/tab/CR and strip **one** wrapping pair of quotes.
- `archs`: comma = space; empty or `noarch` (alone) = all tags; token `all` = `*`;
  a token with one or more leading `~` = negation; glob patterns (`*`, `?`, `[..]`)
  are never globbed against the working directory; no positive token = all tags.

Verify expansion without bootstrapping anything (`template.sh` defines functions
only, no `--selftest` mode):

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; expand_archs "x86_64* ~x86_64-musl"'
# → x86_64
```

## 5. Creating a Package

`pkg-template/tpkg/template` (exactly the file currently in the repository):

```sh
# Template file for 'tpkg'
pkgname=tpkg
version=1.1.0
revision=2
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
	vdoc docs/docs-user-id.md
	vdoc docs/docs-user-en.md
	vdoc docs/docs-dev-id.md
	vdoc docs/docs-dev-en.md
}

# Catatan buat maintainer:
# - "sudo" sengaja tidak dimasukkan ke $depends karena tpkg tetap jalan
#   di root tanpa sudo (lihat logic $SUDO di lib/core.sh). Kalau mau
#   memaksa sudo selalu tersedia di sistem non-root, uncomment baris ini:
# - "sudo" is intentionally omitted from $depends because tpkg still runs
#   as root without sudo (see the $SUDO logic in lib/core.sh). If you want
#   to force sudo to always be available on non-root systems, uncomment this line:
# depends="sudo"
```

Conventions:

- `version` **without** the revision. Correct: `version=1.1.0 revision=1`.
  Wrong: `version=1.1.0_1`.
- Bump `revision` for template-only changes; reset to `1` on a new upstream version.
- `distributor` identifies who packaged it (Let-X will fill it for third-party templates).
- Package names must stay inside `[A-Za-z0-9._+-]` and must not start with `.` or `-`
  (`pkg_safe`; `-b`, `-u` and `-sy` reject them with an error, not just a warning). See §9.
- The trailing `# depends="sudo"` line is only a comment; the parser reads `KEY=`
  lines only (optionally indented) at the start of a line.
- `tpkg` is pure shell with unversioned `depends="xbps"`, so it is a **good fit** for
  `archs=noarch` (one build, fanned out to every tag). The current template does
  **not declare `archs`** yet (undecided, §12/§14): without it, `-b` treats it as 9
  architectures and builds 9 times including 5 cross targets, triggering a source GCC
  build (§14).

## 6. Developer Workflow
`vdev/tools.sh` is a thin dispatcher; all logic lives in `vdev/src/*.sh`. Those
modules define functions only — sourcing them has no side effects, so CI and
Let-X can reuse them safely.

```
vdev/tools.sh -s              # clone void-packages + binary-bootstrap 9 archs + enable restricted
vdev/tools.sh -sy             # git pull + copy new/changed templates
vdev/tools.sh -U              # run xbps-src bootstrap-update for all archs
vdev/tools.sh -b <pkg>        # build
vdev/tools.sh -f <pkg>        # force rebuild (xbps-src -f)
vdev/tools.sh -c              # clean build artifacts (xbps-src clean)
vdev/tools.sh -z              # remove masterdir (xbps-src zap)
vdev/tools.sh -u <pkg>        # upload + trigger CI, then offer push/PR
```

### Setup
`vdev/tools.sh -s` now prepares **all 9 architectures** at once:
- Clone void-packages (full history)
- Binary-bootstrap for `x86_64`, `x86_64-musl`, `aarch64`, `aarch64-musl`, `armv6l`, `armv6l-musl`, `armv7l`, `armv7l-musl`, `i686`
- Automatically enables `XBPS_ALLOW_RESTRICTED=yes` in `$VP/etc/conf`

Existing masterdirs are skipped (not re-bootstrapped).

### Update
`vdev/tools.sh -U` performs:
1. `git pull --ff-only` on void-packages
2. `xbps-src -A <arch> bootstrap-update` for each existing masterdir

### Force Build
`vdev/tools.sh -f` follows the same pattern as `-b`, but forces a rebuild from scratch:

```
vdev/tools.sh -f                          # interactive
vdev/tools.sh -f tpkg zvc                 # several packages
vdev/tools.sh -f tpkg   -a aarch64       # one architecture
vdev/tools.sh -f tpkg   -a all           # all supported
vdev/tools.sh -f zvc    -a 'x86_64*'     # glibc + musl x86_64
```

The `-f` flag in `xbps-src` forces rebuild even if the package exists in cache. Useful
for major template changes or retrying after build failures.

### Clean & Zap
- `vdev/tools.sh -c` — runs `xbps-src clean` to remove build artifacts
  (wrkdir, destdir), but keeps the masterdir
- `vdev/tools.sh -z` — runs `xbps-src zap` to remove **all masterdirs**.
  After zap, you need to run `-s` again to re-bootstrap (can take a while)

### Build

```sh
vdev/tools.sh -b                          # interactive
vdev/tools.sh -b tpkg zvc                 # several packages
vdev/tools.sh -b tpkg   -a aarch64       # one architecture
vdev/tools.sh -b tpkg   -a all           # all supported
vdev/tools.sh -b tpkg   -a x86_64 i686   # several
vdev/tools.sh -b zvc    -a 'x86_64*'     # glibc + musl x86_64
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
| different base arch | `-a <full target>`; plus `-A <hostbase>[-musl]` (target libc) **only when host libc ≠ target libc** |

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

From an `x86_64-musl` host (checked by overriding `HOST_ARCH`): `x86_64` →
`-A x86_64`; `x86_64-musl` → no flags; `aarch64` → `-A x86_64 -a aarch64`;
`aarch64-musl` → `-a aarch64-musl` (same libc, **no** `-A`).

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

### Sync

```sh
vdev/tools.sh -sy
```

`git pull --ff-only` on `void-packages`, then copies new/changed templates from
`pkg-template/` into `void-packages/srcpkgs/`. The names copied are recorded in
`void-packages/.git/t4n-staged` (inside `.git`, so `git status` stays clean). A
template later **removed** from `pkg-template/` is cleaned out of `srcpkgs/` on the
next sync; if the name exists upstream in Void, the official recipe is restored via
`git checkout`. Tracking starts from the first sync with this version — older copies
from before that must be cleaned manually (`git -C void-packages status`).

Package names that reach path operations are validated by `pkg_safe` (`name_safe`
plus "must not start with `.` or `-`"); unsafe names are rejected with an error.
`-b` validates every name and template existence **before** cloning/bootstrapping
`void-packages`.

### Upload

```sh
vdev/tools.sh -u tpkg
```

1. `gh auth status`: not logged in → a clear error, and upload/trigger are skipped
   (exit 1). Then checks write access via
   `gh api repos/T4n-Labs/repo-t4nos --jq .permissions.push`; an API failure is
   reported as such, not mistaken for "no permission".
2. **With write:** matches `.xbps` files in `void-packages/hostdir/binpkgs`
   against `pkgname` + subpackages and the template's `version_revision`, routes
   them to tags (`noarch` → every supported tag; an architecture outside `archs` →
   warning and skipped), uploads with `--clobber`, then triggers `process.yml`
   **once** with the list of touched tags.
3. **Without write:** upload and trigger are skipped, with a notice that a
   maintainer will build and upload after the PR is merged.
4. Either way, offers `git push`, and offers to open a PR if `origin` is not
   `T4n-Labs/repo-t4nos`. The offer is safe without a TTY (EOF = "no") and does not
   change the exit code after a successful upload.

Only files matching the template's `version_revision` are uploaded; older builds
in `binpkgs` are skipped with a warning. The template is the source of truth, not
"the newest file in the folder". Order matters: **edit template → build → upload**.

Re-uploading a binary **with the same name** (rebuild without bumping `revision`) is
supported: `--clobber` replaces the `.xbps`, and CI detects a `.xbps` newer than its
`.sig2` and re-signs it. Still bump `revision` for changes that must reach users —
clients that already cached a file with that name will not download it again.

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

⚠️ **Container shell trap (§14):** the Void container runs `run` blocks under `sh`,
which does not support `pipefail`. The `json` job step that starts with
`set -euo pipefail` therefore uses `shell: bash` (already applied in `process.yml`;
keep it). The `process` job is unaffected because its `pipefail` lives inside
`process-tag.sh`, invoked with `bash`.

### Permissions and pinning in `process.yml`

- Default `permissions` is `contents: read`; `prepare`, `process` and `commit` raise
  it to `contents: write` themselves (create releases / upload-delete assets / push
  `json/`), while `json` stays `contents: read`.
- Actions are pinned to commit SHAs (`checkout` v4.3.1, `upload-artifact` v4.6.2,
  `download-artifact` v4.3.0); update them deliberately, never back to floating tags.
- `persist-credentials: false` on the checkout of `process` (secret holder) and `json`.
- Container image: `ghcr.io/void-linux/void-glibc-full:${{ vars.VOID_IMAGE_TAG || 'latest' }}`.
  To pin, set the repo variable `VOID_IMAGE_TAG` to a dated tag. Until it is set the
  image falls back to `latest` (**not pinned**; see §12).

### Inside `process` (per tag)

```
inventory   list assets (name + updated_at) via the paginated API
plan        per package name, walk candidates from highest to lowest version
            (xbps-uhelper getpkgname / cmpver — never regex)
            trusted = .sig2 exists AND is not older than the .xbps → picked, no download
            otherwise (no .sig2, or .xbps newer than .sig2) → download + verify
verify      read props.plist inside the .xbps; the asset name must equal
            <pkgver>.<architecture>.xbps exactly; failure → REJECTED (left in place,
            NOT deleted), the walk continues to the next lower version
prune       only candidates BELOW the picked, verified version
unsigned    = picked files without a fresh .sig2
skip        unsigned and prune empty, repodata exists and is not older than the .xbps
            → only delete orphan .sig2, done
[1/3] index xbps-rindex -a *.xbps            → <tag>-repodata
[2/3] sign  xbps-rindex --sign               → public key embedded in repodata
[3/3] sign  xbps-rindex --sign-pkg           → .sig2 for unsigned packages only
upload      new repodata + new .sig2 FIRST
prune       delete old .xbps + .sig2 LAST, then orphan .sig2
```

Details worth knowing:

- **`cmpver` calibration.** Rather than assuming whether `xbps-uhelper cmpver`
  reports via stdout or exit code, the script runs two probes with known answers
  and matches the signature. If both probes look identical, pruning is aborted
  rather than risking deletion of the wrong version.
- **A failed verification deletes nothing.** A rejected newest version is left on the
  release, the valid older version keeps being served and is not pruned. If one
  package name has no verified version at all, only a warning is printed and all its
  files are left alone; if **no** package passes in the tag, the job fails (`exit 1`).
  A rejected asset does not cause repodata to be re-uploaded on every run; fix it by
  re-uploading under the correct name and deleting the bad one manually.
- **Same-name re-upload.** A `.xbps` whose `updated_at` is newer than its `.sig2`'s is
  considered stale: it is re-verified, re-indexed, and its `.sig2` is regenerated.
- **Orphan `.sig2`** (its `.xbps` no longer exists) is deleted at the very end, after upload.
- **A trusted file that fails re-verification** (an anomaly) stops the job without
  changing anything.
- **Empty tag.** If there is no `.xbps` at all, orphan `.sig2` files and the stale
  repodata are removed so clients do not read an index pointing at deleted files.

### `packages.json` schema

`json/<tag>/packages.json` is a JSON array. Metadata comes from `index.plist`
inside the repodata; fields absent there are taken from the template.

```json
[
  {
    "name": "tpkg",
    "version": "1.1.0",
    "arch": "x86_64",
    "archs": [
      "x86_64",
      "x86_64-musl",
      "aarch64",
      "aarch64-musl",
      "armv6l",
      "armv6l-musl",
      "armv7l",
      "armv7l-musl",
      "i686"
    ],
    "size": 18366,
    "category": "xbps",
    "desc": "A user-friendly package manager wrapper for XBPS",
    "homepage": "https://gitlab.com/t4n-pkg/tpkg/",
    "maintainer": "Gh0sT4n <darskevoid@gmail.com>",
    "distributor": "Gh0sT4n <darskevoid@gmail.com>",
    "license": "BSD-2-Clause"
  }
]
```

| Field | Source |
|---|---|
| `name` | `pkgname` |
| `version` | from repodata `pkgver` (`<name>-<version>_<revision>` → version without revision); `template` category: the template's `version` |
| `arch` | the tag |
| `archs` | template `archs`, expanded (contract in §4); subpackages without a template fall back to `[tag]` |
| `size` | `.xbps` asset size (bytes); fallback repodata `filename-size`; `null` for `template` |
| `category` | `xbps` (binary exists in this tag) or `template` (template only, binary not built yet) |
| `desc` | `short_desc` (repodata, fallback template) |
| `homepage`, `maintainer`, `license` | repodata, fallback template |
| `distributor` | template only |

The JSON does **not** contain `filename`, `url` or `status`; clients build the download
URL from `<BASE>/<tag>/<pkgver>.<arch>.xbps`.

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
- [ ] `json/<tag>/packages.json` lists the package with `category: xbps` for the expected architectures (and it appears on the website)
- [ ] `xbps-install -S && xbps-install <pkg>` succeeds on a clean test system
- [ ] Old version gone from the release tag (`gh release view <tag>`)

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `json` job: `set: Illegal option -o pipefail` | container runs `sh`; keep `shell: bash` on that step (§14) |
| `::error::… REJECTED` in the `process` job | asset name ≠ package contents; the asset is left in place and the valid older version keeps being served. Re-upload under the right name, delete the bad one manually |
| Client: signature failure after a same-name re-upload | `.xbps` is newer than `.sig2`; CI re-signs on the next run — speed it up with `gh workflow run process.yml -R T4n-Labs/repo-t4nos -f tags=<tag>` |
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
Updated 27 November 2026. Every "verified" row has command output, sandbox test or
CI log evidence; everything else is marked explicitly.

### Verified
| Item | Evidence |
| --- | --- |
| `cmd_setup` bootstraps 9 archs + enables restricted | code + manual test (27 Nov) |
| `cmd_update` pulls + bootstrap-updates 9 archs | code + manual test (27 Nov) |
| `cmd_force` follows `cmd_build` pattern with `-f` flag | code + manual test (27 Nov) |
| `cmd_clean` and `cmd_zap` wrap xbps-src commands | code (27 Nov) |
| flags_for correct for the 9 targets from an x86_64 host; x86_64-musl, i686, aarch64 hosts checked by overriding HOST_ARCH | test output (25 Nov), matches the §6 table |
| Signing works — tags hold .xbps + .sig2 + <tag>-repodata | Releases screenshot (tpkg-1.1.0_1, then _2) (24 Nov) |
| FINGERPRINT in setup.sh = MD5 of the keys/key.pem.pub blob | recomputed (25 Nov) |
| json/<tag>/packages.json ×9 already committed by CI | ls json/* |
| .github/workflows/ = 3 files; vdev/src/ = 7 modules | ls -1 |
| process.yml = 4 jobs; json step uses shell: bash; per-job permissions; actions pinned to SHAs | grep + yaml.safe_load |
| Bash/awk ≡ Python parser (fields and archs), no globbing against cwd | parity test, 56 cases (25 Nov) |
| process-tag.sh: same-name re-upload, rejected newer version, follow-up run without churn, orphan .sig2 | stub harness (fake gh/xbps-*), 25 Nov |
| vdev/ fixes (route_tags, menu 08/09, validation order, pkg_safe, git_offer, sync) | before/after reproduction tests (25 Nov) |
| bash -n, sh -n, ast.parse, yaml.safe_load, JSON valid | command output |

### Outstanding / not applied

| Item | State |
|---|---|
| End-to-end `xbps-install -S` through the domain | not done |
| Real behaviour of `gh release upload --clobber` (does the `.xbps` `updated_at` advance?) and `xbps-uhelper cmpver` with a full `pkgver` | tested with stubs only; verify in real CI |
| Void container image not pinned | repo variable `VOID_IMAGE_TAG` not set → `latest` |
| Worker + domain live | `DNS-check.sh` 14/14 (22 Nov), not re-verified |
| Branch protection, ruleset, `.github/CODEOWNERS` | **absent** (24 Nov, not re-verified) — deferred until public usability is proven |
| Environment `signing` restricted to `main` | `deployment-branch-policies` 404 (24 Nov) → not restricted |
| `CONTRIBUTING*`, LICENSE | absent / undecided |
| Tags `armv6l-musl`, `armv7l-musl` | no binary package yet → `xbps-install -S` 404 for those architectures |
| `./tools` and `./vdev/tools` (no `.sh`) | `tools.sh` can resolve symlinks, but no such symlinks exist in the repo |
| Mandatory `archs=noarch` rule | **undecided** — `tpkg` currently has no `archs` (§14) |
| PyYAML on the dev machine | not installed → use the structural probes in §14 |

Remaining order: set `VOID_IMAGE_TAG` → verify `--clobber`/`updated_at` in real CI →
`xbps-install -S` on a clean system with a **manual conf pointing at the domain** →
hardening (CODEOWNERS, branch protection, Environment restriction).

**Important:** `setup.sh` points at the domain (Worker) by default, so running it
does exercise the Worker. If `T4N_BASE` is overridden to the release URL, the Worker
is not tested. An end-to-end test can write the conf manually:

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
dies on line 1, before any command runs. At the time **all 9 `json` jobs failed**; this is now fixed.

Fix (applied): `shell: bash` on the step whose `run` block starts with `set -euo pipefail`.
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
The current template (`revision=2`) **does not declare `archs=noarch`**, so it is
treated as supporting 9 architectures and `-b` builds 9 times including 5 cross
targets — triggering the GCC build above just to copy six `.sh` files. Making it
`noarch` is still an open decision (§12).

One `noarch` build produces a single `.noarch.xbps` that `cmd_upload` fans out to
every supported tag. **It saves build time, not storage**: the same file is stored
once per tag (9×).

⚠️ **Do not apply this blanket rule.** A Python package with
`build_style=python3-pep517` (historical example: `letx`, no longer in
`pkg-template/`) carries in its `index.plist` `run_depends: python3>=3.14.0_1<3.15.0_1`
— a bound generated automatically from the python3 present in the masterdir at build
time. Making it `noarch` means one file carries one host-derived bound, which may be
unsatisfiable on architectures whose python3 revision differs. Check first (replace
`<pkg>-<version>_<revision>`):

```sh
cd void-packages/hostdir/binpkgs
for f in <pkg>-<version>_<revision>.*.xbps; do
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
