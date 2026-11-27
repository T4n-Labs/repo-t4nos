# T4n OS Repository — User Guide

The **T4n OS** XBPS repository (`repo-t4nos`) provides cryptographically signed
binary packages that are **not available in the official Void Linux
repositories**. It works on both T4n OS and plain Void Linux, for **glibc and
musl**.

This repository is an **addition**, not a replacement. Official Void packages
stay on the official mirrors.

🔍 **Package search:** https://repo-web.t4nlabs.web.id/

---

## Supported Architectures

The repository is split into 9 release tags. Each tag name is exactly the
architecture string reported by `xbps-uhelper arch`.

| Tag | Architecture | libc |
|---|---|---|
| `x86_64` | x86_64 | glibc |
| `x86_64-musl` | x86_64 | musl |
| `aarch64` | aarch64 | glibc |
| `aarch64-musl` | aarch64 | musl |
| `armv6l` | armv6l | glibc |
| `armv6l-musl` | armv6l | musl |
| `armv7l` | armv7l | glibc |
| `armv7l-musl` | armv7l | musl |
| `i686` | i686 | glibc |

> `i686-musl` is **not** provided.

Because tag names match `xbps-uhelper arch`, one setup script serves every
system — no architecture prompt, no manual mapping.

---

## 1. Add the Repository

### Option A — Automatic (recommended)

Download, read, then run. Reading a script before piping it to a root shell is
a good habit:

```sh
curl -fsSLO https://repo.t4nlabs.web.id/setup.sh
less setup.sh
sudo sh setup.sh
```

One-liner, if you prefer:

```sh
curl -fsSL https://repo.t4nlabs.web.id/setup.sh | sudo sh
```

The script detects your architecture **and libc**, writes one configuration
file, then synchronises the package index.

### Option B — Manual

```sh
sudo mkdir -p /etc/xbps.d
echo "repository=https://repo.t4nlabs.web.id/$(xbps-uhelper arch)" \
  | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

### `setup.sh` commands and environment variables

```sh
sudo sh setup.sh              # install the repository (default, same as `setup`)
sudo sh setup.sh update       # sync the index + upgrade: xbps-install -Su [options]
sh setup.sh --help
```

`update` needs the repository to be installed first (it checks the configuration
file) and passes any extra options through to `xbps-install -Su`. Through a pipe:
`curl -fsSL https://repo.t4nlabs.web.id/setup.sh | sudo sh -s update`. Do not pass
`-y` to `update` unless you have already verified the fingerprint. `setup`
overwrites the configuration file if it already exists.

| Variable | Default | Purpose |
|---|---|---|
| `T4N_BASE` | `https://repo.t4nlabs.web.id` | Base URL; written as `repository=<T4N_BASE>/<arch>`. Fallback: the release URL (see Troubleshooting) |
| `CONF_FILE` | `/etc/xbps.d/10-t4nos.conf` | Where the configuration file is written |
| `T4N_ASSUME_YES` | `0` | `1` runs `xbps-install -S -y` and **skips the fingerprint prompt** |

`sudo` usually strips environment variables, so pass them through `env`:

```sh
sudo env T4N_BASE=https://github.com/T4n-Labs/repo-t4nos/releases/download sh setup.sh
sudo env T4N_ASSUME_YES=1 sh setup.sh   # ONLY after verifying the fingerprint yourself
```

Without a terminal (CI, a plain pipe) `setup` cannot ask for confirmation and stops,
unless `T4N_ASSUME_YES=1` is set.

### ⚠️ Verify the Fingerprint (mandatory)

On the first sync, XBPS displays the repository key fingerprint and asks for
confirmation:

```
...
Fingerprint: xx:xx:xx:...
Do you want to import this public key? [Y/n]
```

> The prompt wording may differ between XBPS versions; what must match is the `Fingerprint` line.

Current official fingerprint: `63:35:0c:65:0d:a5:f1:87:52:7e:c5:e9:13:3a:d6:2a` (signer `T4n Labs`; the same key for every tag).

Answer `yes` **only** if the fingerprint matches the one published in the
[repository README](https://github.com/T4n-Labs/repo-t4nos) and on the website.

This confirmation is the only protection in your supply chain. Never answer it
blindly, and never use `T4N_ASSUME_YES=1` unless you have already verified the
fingerprint yourself.

---

## 2. Search and Install

```sh
xbps-query -Rs "name"        # search, e.g. zvc, tpkg
sudo xbps-install name       # install
sudo xbps-install -Su        # update everything (official + T4n OS)
```

---

## 3. Web Package Search

https://repo-web.t4nlabs.web.id/

- **Live search** with highlighting (110 ms debounce)
- **Architecture tabs** with live package counters
- **Pagination** for large result sets
- **Shareable URLs** — state lives in the URL hash: `#q=zvc&arch=x86_64&page=2`
- **Keyboard shortcuts** — `/` focuses search, `Esc` clears it
- **One-click copy** of the install command per package

### Package status

| Badge | Meaning |
|---|---|
| `ready` | Binary exists for that architecture — installable now (`category: xbps` in the index JSON) |
| `recipe` | Template exists, binary not built yet for that architecture (`category: template`) |

A `recipe` entry is **not** downloadable. It shows up so you can see what is
coming; wait until it turns `ready`.

---

## 4. Remove the Repository

```sh
sudo rm /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

The public key you already imported stays in `/var/db/xbps/keys/`. Delete its
`.plist` file if you also want to revoke trust in the T4n OS key.

---

## ❓ Troubleshooting

**`ERROR: <package-name>: the RSA signature is not valid!`**
The package or signature file in the local XBPS cache (`/var/cache/xbps/`) is
corrupt or was not fully downloaded (e.g. due to a dropped connection). XBPS
automatically removes the bad file; simply force a fresh download from the server:

```sh
sudo xbps-remove -O
sudo xbps-install -S package-name
```

**`repository is not signed, refusing to continue!`**
Remote XBPS repositories must be signed. Check that the URL in your `.conf`
file is correct and that you accepted the key import. Re-sync with
`sudo xbps-install -S`.

**Fingerprint changed / old key rejected.**
The repository key was rotated. Remove the old key, then re-sync and verify the
**new** fingerprint:

```sh
sudo rm /var/db/xbps/keys/<old-fingerprint>.plist
sudo xbps-install -S
```

**`xbps-query` cannot find a package.**
1. Did you run `xbps-install -S` after adding the repository?
2. The package may not be built for your architecture/libc — check the
   architecture tabs on the website. A `recipe` badge means "not built yet".

**404 while syncing.**
There are two possible causes.

1. The endpoint `repo.t4nlabs.web.id/<arch>` (Cloudflare Worker proxy) is not
   active yet. Use the direct release URL instead:

```sh
echo "repository=https://github.com/T4n-Labs/repo-t4nos/releases/download/$(xbps-uhelper arch)" \
  | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

2. Your architecture/libc has no packages at all yet, so its index
   (`<arch>-repodata`) has not been created. Nothing to fix on your side; wait for
   the first package or ask a maintainer.

**Website shows ∅ / empty.**
CI is still building or the index has not been regenerated. Wait a few minutes
and reload. The index is produced from templates, so new packages appear before
their binaries finish building.

**`i686-musl` is not supported.**
Correct — that combination is not provided. See the table above.

---

**[T4n Labs](https://t4nlabs.web.id/)** ◉ **[Gh0sT4n](https://gh0st4n.my.id/)**
*Built for the community, by the community.*
