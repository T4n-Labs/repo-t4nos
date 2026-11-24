# Repositori T4n OS — Panduan Developer & Maintainer

Infrastruktur `repo-t4nos`: satu repositori GitHub untuk glibc dan musl, biner di
GitHub Releases, indeks di `json/`, semuanya otomatis lewat CI. Repositori ini
menghasilkan paket biner saja. Website ada di repositori terpisah (`repo-site`).

> Sumber kebenaran adalah kode. Kalau dokumen ini dan kode berbeda, kode yang
> menang lalu dokumen diperbaiki. Hal yang belum dibuktikan keluaran perintah
> ditandai "belum diverifikasi". Cuplikan status: 24 November 2026 (§12).

## 1. Aturan Emas

1. **Biner tidak pernah masuk git.** `.xbps`, `.xbps.sig2`, `<tag>-repodata` hidup
   di GitHub Releases. Git hanya berisi template, skrip, docs, `json/`,
   `keys/key.pem.pub`.
2. **Signing hanya di CI**, di job `process`, memakai `SIGN_KEY` dari Environment
   `signing`. Tidak pernah menyentuh mesin developer. `vdev/` tidak punya satu pun
   panggilan `xbps-rindex` atau akses kunci.
3. **Jangan edit release manual.** CI me-reconcile penuh: versi lama di-prune,
   entri indeks yatim dibangun ulang. Edit manual akan ditimpa.
4. **Rencana dulu, hapus terakhir.** Repodata + `.sig2` baru diupload sebelum
   asset lama dihapus, supaya client tidak pernah membaca indeks yang menunjuk
   file hilang.
5. **Template tidak pernah di-`source`.** Berasal dari pihak lain. Parse dengan
   `grep`/`sed`/regex. Job pemegang secret tidak boleh membaca template sama
   sekali — itu alasan ia memakai `sparse-checkout: .github/workflows`.

## 2. Struktur

```
repo-t4nos/
├── .github/CODEOWNERS          # BELUM ADA (direncanakan; proteksi ditunda, §12)
├── .github/workflows/
│   ├── process.yml             # satu-satunya workflow YAML (4 job)
│   ├── process-tag.sh          # per-tag: inventory → sign → prune (PEGANG SECRET)
│   └── gen-json.py             # per-tag: repodata + template → packages.json
├── json/<tag>/packages.json    # ×9, di-commit balik oleh CI (sekarang cuma .gitkeep, §12)
├── keys/key.pem.pub            # satu-satunya file key yang publik
├── pkg-template/<pkg>/template # flat, tanpa folder kategori
├── vdev/
│   ├── tools.sh                # dispatcher tipis
│   ├── DNS-check.sh            # uji domain/Worker read-only (§13)
│   └── src/
│       ├── common.sh           # path, konstanta, log, guard
│       ├── template.sh         # parser template + ekspansi archs
│       ├── env.sh              # setup, sync, flag xbps-src
│       ├── build.sh            # menu arsitektur + build
│       ├── upload.sh           # upload release + trigger CI
│       └── git.sh              # tawaran push / pull-request
├── vdocs/{EN,ID}/{DEV,USER}.md
├── setup.sh                    # one-liner untuk user
├── CONTRIBUTING.md / CONTRIBUTING.ID.md   # direncanakan, belum ada
└── README.md / README.ID.md
```

Hanya `*.yml` di `.github/workflows/` yang diparse sebagai workflow. File `.sh`
dan `.py` di situ adalah helper biasa, ditaruh di sana karena dua alasan konkret:

- `process-tag.sh` berisi logika signing, jadi ikut terlindungi CODEOWNERS +
  branch protection yang dimaksudkan untuk `.github/workflows/`.
- Job `process` memakai `sparse-checkout: .github/workflows`, jadi template
  kontributor tidak pernah ter-checkout ke job pemegang secret. Skrip yang
  dipanggil job itu karena itu harus berada di dalam direktori tersebut.

**Status proteksi (24 Nov 2026):** `.github/CODEOWNERS` belum ada dan `main` belum
diproteksi (tidak ada ruleset maupun classic protection). Ini **disengaja**:
hardening ditunda sampai repo terbukti bisa dipakai publik. Sisi baik: job
`commit` bisa push `json/` tanpa hambatan. Sisi buruk: siapa pun dengan akses
Write bisa mengubah `.github/workflows/` tanpa review. Saat hardening, aktifkan
keduanya bersamaan dan izinkan `github-actions` + Founder bypass, kalau tidak job
`commit` gagal 3× (§11).

### Release tag (9)

`x86_64` · `x86_64-musl` · `aarch64` · `aarch64-musl` · `armv6l` · `armv6l-musl` ·
`armv7l` · `armv7l-musl` · `i686`

Nama tag sama dengan string arsitektur XBPS, jadi `xbps-uhelper arch` langsung
memetakan ke tag tanpa tabel pencarian. `i686-musl` tidak disediakan.

### URL

| Kegunaan | URL |
|---|---|
| Website (repo-site) | `https://repo-web.t4nlabs.web.id/` |
| Endpoint XBPS | `https://repo.t4nlabs.web.id/<tag>` |
| Penyimpanan asset | `https://github.com/T4n-Labs/repo-t4nos/releases/download/<tag>` |

Endpoint XBPS adalah reverse proxy (Cloudflare Worker `t4n-repo`) di depan asset
release: `/<tag>/<file>` diteruskan ke `releases/download/<tag>/<file>`. GitHub
Pages tidak bisa melakukan ini, jadi domain harus berada di zona Cloudflare.
Worker hanya melayani 9 tag dan nama file `[A-Za-z0-9._+-]`; selain itu dijawab
404. Domain dan Worker hanya dikelola Founder. Worker mem-proxy (stream byte,
mendukung Range), bukan redirect untuk request file — terverifikasi `DNS-check.sh`
(§13).

## 3. Prasyarat

- Void Linux atau T4n OS (atau container `ghcr.io/void-linux/void-{glibc,musl}-full`)
- `git`, `gh` (sudah terautentikasi)
- `xbps-src` — diambil otomatis oleh `vdev/tools.sh -s`
- **Akses Write** ke `T4n-Labs/repo-t4nos` untuk upload asset dan menjalankan
  `workflow_dispatch`. Kontributor dengan akses `Read` bekerja lewat fork + PR.

## 4. Semantik `archs`

Pencocokan glob, identik dengan `xbps-src`.

| Isi | Hasil |
|---|---|
| tidak ditulis / kosong | semua 9 tag |
| `noarch` | semua 9 tag; dibuild sekali, di-fanout |
| `x86_64` | hanya x86_64 glibc |
| `x86_64*` | `x86_64` **dan** `x86_64-musl` |
| `x86_64* aarch64` | `x86_64`, `x86_64-musl`, `aarch64` |
| `~i686` | semua tag kecuali `i686` |
| `x86_64* ~x86_64-musl` | hanya `x86_64` |

⚠️ Paket C yang belum siap musl harus menulis arsitektur eksplisit; `*` membuat CI
mencoba build musl dan gagal.

⚠️ **`noarch` bukan aturan pukul rata.** Aman hanya bila paket tidak punya ELF
terkompilasi **dan** tidak ada dependensi dengan batas versi yang di-generate
otomatis. `letx` (`python3-pep517`) membawa `run_depends:
python3>=3.14.0_1<3.15.0_1`, di-generate dari host build; menjadikannya `noarch`
mengunci satu batas dari host yang bisa tidak terpuaskan di arsitektur lain.
Lihat §14.

Verifikasi ekspansi tanpa bootstrap apa pun (`template.sh` hanya berisi definisi
fungsi, tidak punya mode `--selftest`):

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; expand_archs "x86_64* ~x86_64-musl"'
# → x86_64
```

## 5. Membuat Paket Baru

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

Konvensi:

- `version` **tanpa** revisi. Benar: `version=1.1.0 revision=1`. Salah:
  `version=1.1.0_1`.
- Naikkan `revision` untuk perubahan template saja; reset ke `1` saat versi
  upstream baru.
- `distributor` menandai siapa yang mengemas (Let-X akan mengisinya untuk template
  pihak lain).
- Nama paket harus tetap di dalam `[A-Za-z0-9._+-]`. Lihat §9.
- `tpkg` shell murni dengan `depends="xbps"` tanpa versi → `archs=noarch` benar:
  satu build, di-fanout ke semua tag. Tanpa itu, `-b` membangun 9 kali termasuk 5
  cross, memicu build GCC dari source untuk hal sia-sia (§14).

## 6. Alur Developer

`vdev/tools.sh` adalah dispatcher tipis; semua logika ada di `vdev/src/*.sh`.
Modul-modul itu hanya mendefinisikan fungsi — men-source-nya tidak menimbulkan
side effect, jadi CI dan Let-X bisa memakainya ulang dengan aman.

```sh
vdev/tools.sh -s              # clone void-packages + binary-bootstrap
vdev/tools.sh -sy             # git pull + salin template baru/berubah
vdev/tools.sh -b <pkg>        # build
vdev/tools.sh -u <pkg>        # upload + trigger CI, lalu tawarkan push/PR
```

### Build

```sh
vdev/tools.sh -b                          # interaktif
vdev/tools.sh -b tpkg zvc                 # beberapa paket
vdev/tools.sh -b radare2 -a aarch64       # satu arsitektur
vdev/tools.sh -b radare2 -a all           # semua yang didukung
vdev/tools.sh -b radare2 -a x86_64 i686   # beberapa
vdev/tools.sh -b radare2 -a 'x86_64*'     # x86_64 glibc + musl
```

Arsitektur yang diminta diiriskan dengan `archs` template; irisannya ditampilkan
sebelum build. Paket `noarch` dibuild sekali, pada target pertama yang dipilih.

### Pemilihan flag (`src/env.sh: flags_for`) — diperbaiki dan diverifikasi 24 Nov 2026

`-A` = masterdir/host, `-a` = target cross. **`-a` menerima string arsitektur
LENGKAP, termasuk `-musl`.** glibc tidak punya suffix (`x86_64`, bukan
`x86_64-glibc`).

| Situasi | Flag |
|---|---|
| target **identik** dengan `HOST_ARCH` (string penuh) | tanpa flag (native) |
| base arch sama, libc berbeda | `-A <target lengkap>` |
| `i686` di host `x86_64`, libc sama | `-A i686` (masterdir 32-bit native) |
| base arch berbeda | `-a <target lengkap>`, ditambah `-A <hostbase>-musl` bila target musl |

Hasil terverifikasi dari host `x86_64` (glibc):

| Target | Flag |
|---|---|
| `x86_64` | *(tanpa)* |
| `x86_64-musl` | `-A x86_64-musl` |
| `i686` | `-A i686` |
| `aarch64` | `-a aarch64` |
| `aarch64-musl` | `-A x86_64-musl -a aarch64-musl` |
| `armv6l` | `-a armv6l` |
| `armv6l-musl` | `-A x86_64-musl -a armv6l-musl` |
| `armv7l` | `-a armv7l` |
| `armv7l-musl` | `-A x86_64-musl -a armv7l-musl` |

Dari host `x86_64-musl`: target `x86_64` → `-A x86_64`; target `x86_64-musl` →
tanpa flag.

Dua bug yang diperbaiki:

1. **`-a` dulu membuang `-musl`.** Target `armv6l-musl` menghasilkan `-a armv6l`,
   jadi paket yang dibangun sebenarnya **glibc** aunque diminta musl — gagal
   diam-diam, bukan error. Sekarang `-a armv6l-musl`.
2. **`-A <hostbase>-glibc` tidak valid.** Host musl dengan target glibc dulu
   menghasilkan `-A x86_64-glibc`; string itu tidak ada di Void. Sekarang
   `-A x86_64`.

Keduanya terverifikasi **di tingkat pembangkitan flag**. Yang belum diuji:
`xbps-src` menerima `-A x86_64` dari host musl dan menghasilkan paket glibc yang
benar (host pengembang sekarang glibc, jadi arah itu belum pernah dijalankan).

Verifikasi tanpa build apa pun:

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; . vdev/src/env.sh
         for a in "${ALL[@]}"; do printf "%-14s → %s\n" "$a" "$(flags_for "$a" | xargs)"; done'
```

### Upload

```sh
vdev/tools.sh -u tpkg
```

1. Cek akses write via `gh api repos/T4n-Labs/repo-t4nos --jq .permissions.push`.
2. **Punya write:** mencocokkan file `.xbps` di `void-packages/hostdir/binpkgs`
   dengan `pkgname` + subpackage dan `version_revision` template, mengarahkannya
   ke tag (`noarch` → semua tag yang didukung), upload dengan `--clobber`, lalu
   men-trigger `process.yml` **sekali** dengan daftar tag yang tersentuh.
3. **Tanpa write:** upload dan trigger dilewati, dengan pemberitahuan bahwa
   maintainer akan build dan upload setelah PR di-merge.
4. Dua-duanya tetap menawarkan `git push`, dan menawarkan buka PR kalau `origin`
   adalah fork.

Hanya file yang cocok `version_revision` template yang diupload; build lama di
`binpkgs` di-skip dengan warning. Template adalah sumber kebenaran, bukan "file
terbaru di folder". Urutan penting: **edit template → build → upload**.

Biner yang diupload **belum bertanda tangan**. CI yang menandatangani. Ada window
singkat di mana asset sudah ada tapi `.sig2`-nya belum — jangan umumkan rilis
sebelum workflow hijau. File `.sig2` lokal (dari kunci Anda sendiri) sengaja tidak
diupload: tanda tangan dengan kunci berbeda gagal verifikasi di client. CI
satu-satunya penanda tangan.

## 7. Pipeline CI/CD

### Trigger

- `workflow_dispatch` dengan input `tags` (default `all`) — dipanggil
  `vdev/tools.sh -u` sekali setelah semua upload selesai.
- `schedule` (`23 */6 * * *`) sebagai cadangan; no-op kalau tidak ada yang perlu
  diproses.

Trigger push sengaja tidak ada: upload asset release tidak memicu event apa pun,
dan event yang dibuat `GITHUB_TOKEN` tidak memicu workflow lain.
`concurrency: { group: repo-process, cancel-in-progress: false }` membuat run
antri.

### Job

| # | Job | Secret | Baca template | Tugas |
|---|---|---|---|---|
| 1 | `prepare` | tidak | tidak | resolve tag, buat yang belum ada (idempotent) |
| 2 | `process` ×9 | **ya** | **tidak** | index, sign, prune per tag |
| 3 | `json` ×9 | tidak | ya | repodata + template → `packages.json` |
| 4 | `commit` | tidak | tidak | commit `json/**` sekali, hanya kalau berubah |

⚠️ **Jebakan shell container (§14):** blok `run` multi-baris job `json` diawali
`set -euo pipefail`, tapi container Void menjalankannya dengan `sh`, yang tidak
mengenal `pipefail`. Step itu butuh `shell: bash`. Per 24 Nov 2026 ini **belum
diterapkan** (`grep -n 'shell: bash'` kosong), jadi 9 job `json` gagal di baris 1.
Job `process` tidak kena karena `pipefail`-nya ada di dalam `process-tag.sh`,
dipanggil dengan `bash`.

### Isi job `process` (per tag)

```
inventory   daftar asset via API paginated
rencana     kelompokkan .xbps per nama paket, keep versi+revisi tertinggi
            (xbps-uhelper getpkgname / cmpver — bukan regex)
            sisanya → prune list
            unsigned = file yang di-keep tapi belum punya .sig2
            kalau unsigned & prune kosong dan repodata ada → skip
unduh       file yang di-keep ke folder kerja KOSONG
verifikasi  baca props.plist di dalam tiap .xbps; nama asset harus persis
            <pkgver>.<architecture>.xbps, kalau tidak → tolak
[1/3] index xbps-rindex -a *.xbps            → <tag>-repodata
[2/3] sign  xbps-rindex --sign               → kunci publik masuk ke repodata
[3/3] sign  xbps-rindex --sign-pkg           → .sig2 hanya untuk yang unsigned
upload      repodata + .sig2 baru DULU
prune       hapus .xbps + .sig2 lama TERAKHIR
```

Dua detail yang perlu diketahui:

- **Kalibrasi `cmpver`.** Daripada mengasumsikan apakah `xbps-uhelper cmpver`
  melapor lewat stdout atau exit code, skrip menjalankan dua probe yang jawabannya
  sudah diketahui lalu mencocokkan signature-nya. Kalau kedua probe terlihat
  identik, pruning dibatalkan daripada berisiko menghapus versi yang salah.
- **Tag kosong.** Kalau tidak ada yang di-keep, prune tetap jalan dan repodata
  basi dihapus supaya client tidak membaca indeks yang menunjuk file terhapus.

### Skema `packages.json`

`json/<tag>/packages.json` adalah array JSON. Metadata diambil dari `index.plist`
di dalam repodata; field yang tidak ada di sana diambil dari template.

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

| Field | Sumber |
|---|---|
| `name` | `pkgname` |
| `version` | `version` dari repodata, revisi dibuang |
| `arch` | nama tag |
| `archs` | `archs` template, sudah di-expand |
| `filename`, `size` | metadata asset release |
| `url` | `<BASE>/<tag>/<filename>`; `BASE` di `gen-json.py` (lihat §12) |
| `description` / `desc` | `short_desc` (`desc` alias untuk frontend sekarang) |
| `distributor` | hanya dari template |
| `status` | `ready` (biner ada) atau `recipe` (template saja; `filename`/`size`/`url` bernilai `null`) |

Subpackage (`-dbg`, `-doc`, `-devel`) tidak punya template sendiri, jadi `archs`
mereka fallback ke `[tag]`.

## 8. Kunci

```sh
ssh-keygen -t rsa -b 4096 -m PEM -f key.pem -N ""
cp key.pem.pub keys/key.pem.pub
gh secret set SIGN_KEY --env signing -R T4n-Labs/repo-t4nos < key.pem
```

- Backup `key.pem` offline. File itu ada di `.gitignore`. **Jangan pernah commit.**
- Environment `signing` dimaksudkan dibatasi ke branch `main`. Per 24 Nov 2026
  pembatasan branch **belum dikonfigurasi** (§12); secret ada dan signing jalan,
  tapi jaminan "hanya main" belum ditegakkan.
- Hanya `keys/key.pem.pub` yang publik. `ssh-keygen` menulisnya dalam format
  OpenSSH (`ssh-rsa AAAA…`). Fingerprint yang diumumkan adalah fingerprint
  **XBPS**: ambil dari prompt impor kunci pertama (§12), bukan dari
  `ssh-keygen -l`.
- Umumkan fingerprint (README + website) supaya user bisa memverifikasi impor
  pertama.

**Rotasi:** generate kunci baru → update secret → dispatch `process.yml` dengan
`tags=all` (semua paket di-sign ulang) → umumkan fingerprint baru → user menghapus
`.plist` lama dan sync ulang.

## 9. Karakter Nama File — Terverifikasi

Diuji pada release sementara:

| Diupload | Tersimpan | URL download |
|---|---|---|
| `libfake++-1.0_1.x86_64.xbps` | utuh | raw `+` **200**, `%2B` **200** |
| `libsigc++-2.0_1.x86_64.xbps` | utuh | — |
| `gtk+3-3.24_1.x86_64.xbps` | utuh | — |
| `foo~bar-1.0_1.x86_64.xbps` | `foo.bar-1.0_1.x86_64.xbps` | nama rusak |

`+` aman; paket seperti `libstdc++`, `gtk+3`, `libsigc++` boleh dipaketkan di sini.
`~` di-rename menjadi `.`.

Bagian berbahayanya: hasil rename `foo.bar-...` justru **lolos** allowlist
karakter, karena `.` legal — sementara `props.plist` di dalam paket tetap menulis
`foo~bar-1.0_1`. Repodata lalu menunjuk file yang tidak ada dan client dapat 404.

Itu sebabnya pagar sebenarnya adalah **verifikasi nama**, bukan blocklist
karakter: setelah download, baca `props.plist` dan wajibkan nama asset sama persis
dengan `<pkgver>.<architecture>.xbps`. Parsing plist adalah parsing data, bukan
eksekusi kode, jadi tetap aman di dalam job pemegang secret.

Karakter di luar `[A-Za-z0-9._+-]` ditolak di awal. `:`, spasi, dan tanda kurung
belum diuji — jangan diasumsikan aman. Worker memakai allowlist yang sama: nama di
luar itu dijawab 404 walaupun file-nya ada di release.

## 10. Checklist Rilis

- [ ] Template benar: `archs`, `checksum`, konvensi `version` / `revision`
- [ ] Kalau menyentuh parser: jalankan `expand_archs` pada contoh §4, hasil cocok
- [ ] Kalau menyentuh `flags_for`: jalankan verifikasi §6, keluaran cocok tabel
- [ ] Build lokal di host plus minimal satu target cross
- [ ] `vdev/tools.sh -u <pkg>` → workflow ter-trigger
- [ ] Semua job CI hijau (`gh run watch -R T4n-Labs/repo-t4nos`)
- [ ] Paket tampil `ready` di website untuk arsitektur yang diharapkan
- [ ] `xbps-install -S && xbps-install <pkg>` sukses di sistem uji bersih
- [ ] Versi lama hilang dari release tag (`gh release view <tag>`)

## 11. Troubleshooting

| Gejala | Penyebab / perbaikan |
|---|---|
| Job `json`: `set: Illegal option -o pipefail` | container menjalankan `sh`; tambah `shell: bash` ke step itu (§14) |
| Job musl gagal | paket belum siap musl → tulis archs eksplisit, atau perbaiki build |
| Build ARM di-skip | `nocross=` di template — wajar, atau adaptasi untuk cross |
| Build cross berjam-jam | toolchain dibangun dari source; cek `xbps-query -Rs cross-…` dulu (§14) |
| `props.plist` tidak terbaca | asset bukan paket xbps valid (mis. dummy tes) |
| Nama asset ≠ isi paket | GitHub me-rename karakter; ganti nama paket |
| Tag kosong / sync 404 | belum ada paket masuk tag itu; build tool `noarch` dulu |
| 404 lewat `repo.t4nlabs.web.id` tapi URL release normal | domain/Worker belum aktif atau DNS salah → pakai URL release, hubungi Founder |
| Install gagal tepat setelah `-u` | biner belum di-sign; tunggu workflow selesai |
| `commit json` warning 3× | branch protection menolak push bot; izinkan Founder + `github-actions` bypass, atau hapus syarat PR |
| Website basi | indeks belum dibuat ulang; cek job `json` dan `commit` |
| Domain terlihat bermasalah | jalankan `bash vdev/DNS-check.sh` dan cocokkan dengan §13 |

## 12. Status Implementasi

Diperbarui 24 November 2026. Setiap baris "terverifikasi" punya bukti keluaran
perintah atau log CI; yang lain ditandai eksplisit.

### Terverifikasi

| Item | Bukti |
|---|---|
| `flags_for` benar untuk 13 kombinasi host×target | keluaran uji, cocok tabel §6 |
| **Signing berjalan** — tag punya `.xbps` + `.sig2` + `<tag>-repodata` | screenshot Releases (`tpkg-1.1.0_1`, lalu `_2`) |
| `SIGN_KEY` ada di Environment `signing` | `gh secret list --env signing` |
| `.github/workflows/` = 3 file, tanpa legacy | `ls -1` |
| `vdev/tools.sh` terpecah ke `src/` (6 modul) | `ls -1` |
| Tidak ada `restricted`/`POLICY` di workflows maupun `vdev/` | `grep` kosong |
| `process.yml` = 4 job (`prepare`, `process`, `json`, `commit`) | `grep` kunci job |
| Worker + domain aktif | `DNS-check.sh` 14/14 (22 Nov) |
| `bash -n`, `sh -n`, `ast.parse` lulus | keluaran perintah |

### Belum selesai / belum diterapkan

| Item | Keadaan |
|---|---|
| `shell: bash` di job `json` | **belum diterapkan** (`grep` kosong). Tanpa ini 9 job `json` gagal — §14 |
| `json/<tag>/packages.json` | belum pernah ter-commit; folder masih `.gitkeep` |
| `FINGERPRINT` di `setup.sh` | masih placeholder |
| Tes end-to-end `xbps-install -S` lewat domain | belum dilakukan |
| Konsistensi `BASE` | **cek di disk** — snapshot beda: `setup.sh` menampilkan domain, `gen-json.py` menampilkan URL release. Keduanya harus sama. Jalankan `grep -n '^BASE' setup.sh .github/workflows/gen-json.py` |
| Branch protection, ruleset, `.github/CODEOWNERS` | **tidak ada** — ditunda sampai repo terbukti dipakai publik |
| Environment `signing` dibatasi ke `main` | `deployment-branch-policies` 404 → belum dibatasi |
| `CONTRIBUTING*`, LICENSE | belum ada / belum diputuskan |
| Tag `armv6l-musl`, `armv7l-musl` | belum ada paket → `xbps-install -S` 404 untuk arsitektur itu |
| Ringkasan build (Success/Failed per arch) | diminta; penerapan belum dikonfirmasi |
| Menu paket bernomor 18/halaman (`n`/`p`/`q`) | diminta; penerapan belum dikonfirmasi |
| `tools search <query>` + `src/search.sh` | diminta; penerapan belum dikonfirmasi |
| `./tools` dan `./vdev/tools` (tanpa `.sh`) | diminta; penerapan belum dikonfirmasi |
| Aturan wajib `archs=noarch` | **belum diputuskan** — lihat §14 |
| PyYAML di mesin dev | tidak terpasang → cek `yaml.safe_load` (§10 PROMPT) tidak bisa dijalankan |

Urutan tersisa: terapkan `shell: bash` → job `json` hijau → `json/` ter-commit →
`xbps-install -S` di sistem bersih dengan conf **manual ke domain** → catat
fingerprint → isi `FINGERPRINT` → samakan `BASE` di dua file → hardening.

**Penting:** menjalankan `setup.sh` **tidak** menguji Worker kalau `BASE`-nya URL
release. Tes end-to-end harus menulis conf manual:

```sh
echo 'repository=https://repo.t4nlabs.web.id/x86_64' | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

## 13. Verifikasi Domain `repo.t4nlabs.web.id`

`vdev/DNS-check.sh` menguji domain tanpa biner XBPS. Skrip hanya membaca, jadi
aman dijalankan siapa pun yang punya `curl` (dan `dig` untuk bagian DNS).

```sh
bash vdev/DNS-check.sh                  # DNS, TLS, perilaku Worker
PROBE=ping.txt bash vdev/DNS-check.sh   # + uji proxy 200 / Range / isi identik
```

Variabel opsional: `BASE`, `WEB`, `GH`, `TAG` (default `x86_64-musl`), `PROBE`.
Skrip keluar dengan kode 0 hanya bila semua uji lulus.

| Kelompok | Yang diuji |
|---|---|
| DNS | NS `t4nlabs.web.id` di Cloudflare; `repo` tidak mengarah ke GitHub Pages |
| Worker | `/` → 302 ke website; `/<tag>` dan `/<tag>/` → 302 ke halaman release; tag tak dikenal → 404; nama file tak valid → 404; POST → 405 |
| Proxy | HEAD/GET → 200, Range → 206, isi lewat domain sama dengan isi dari GitHub (hanya dengan `PROBE`) |

Uji proxy dengan file nyata (butuh akses write, jadi Founder yang menjalankan):

```sh
echo ping-ok > ping.txt
gh release upload x86_64-musl ping.txt -R T4n-Labs/repo-t4nos
PROBE=ping.txt bash vdev/DNS-check.sh
gh release delete-asset x86_64-musl ping.txt -R T4n-Labs/repo-t4nos -y
```

CI mengabaikan asset selain `.xbps`, jadi `ping.txt` tidak mengganggu, tetapi
tetap hapus setelah selesai. `<tag>-repodata` berstatus 404 selama belum ada paket
yang diproses; itu normal, bukan kegagalan domain.

Hasil acuan (22 November 2026): 14 lulus, 0 gagal.

## 14. Jebakan Build & CI — Terverifikasi

### `sh`, bukan `bash`, di dalam container Void

Log CI job `json` (23 Nov 2026):

```
shell: sh -e {0}
1: set: Illegal option -o pipefail
Error: Process completed with exit code 2.
```

Runner tidak mengenali container Void sebagai distro ber-bash default, jadi blok
`run` dijalankan dengan `sh`. `set -o pipefail` tidak dikenal di sana → step mati
di baris 1, sebelum perintah apa pun jalan. **Semua 9 job `json` gagal** karena
ini.

Perbaikan: `shell: bash` pada step yang blok `run`-nya diawali
`set -euo pipefail`. `bash` sudah dipasang step **Install tools** yang hijau, jadi
step sesudahnya boleh memakainya. Jangan pakai `defaults.run.shell: bash` di level
job — itu memaksa Install tools memakai bash sebelum bash terpasang.

### Toolchain cross bisa dibangun dari source

```
ERROR: Could not find package 'cross-aarch64-linux-gnu'
=> xbps-src: installing cross compiler: cross-aarch64-linux-gnu ...
```

Kalau toolchain cross tidak tersedia sebagai paket biner, `xbps-src` membangunnya
dari source: binutils, GCC dua tahap, header libc. Itu **1–3 jam** per target di
laptop, bukan menit. Cek dulu sebelum mencoba cross:

```sh
xbps-query -Rs cross-aarch64-linux-gnu
xbps-query -Rs cross-armv7l-linux-gnueabihf
```

Untuk paket shell/script murni, kerja ini nol manfaat — lihat butir berikut.

### Paket script tanpa `archs=noarch` memicu cross build sia-sia

`tpkg` isinya shell + modul `.sh` dengan `depends="xbps"` tanpa batas versi.
Karena template-nya tidak menulis `archs=noarch`, ia dianggap mendukung 9
arsitektur dan `-b` membangun 9 kali termasuk 5 cross — memicu build GCC di atas
untuk menyalin enam file `.sh`.

Satu build `noarch` menghasilkan satu `.noarch.xbps` yang di-fanout `cmd_upload`
ke semua tag yang didukung. **Hemat waktu build, bukan storage**: file yang sama
disimpan sekali per tag (9×).

⚠️ **Jangan pukul rata.** `letx` memakai `build_style=python3-pep517` dan
`index.plist`-nya berisi `run_depends: python3>=3.14.0_1<3.15.0_1` — batas versi
yang di-generate otomatis dari python3 di masterdir saat build. Kalau dijadikan
`noarch`, satu file membawa satu batas dari host dan bisa tidak terpuaskan di
arsitektur yang revisi python3-nya beda. Cek dulu:

```sh
cd void-packages/hostdir/binpkgs
for f in letx-1.0.0_1.*.xbps; do
  printf '%s: ' "$f"
  bsdtar -xOf "$f" props.plist | grep -A2 run_depends | tr -d '\n\t '
  echo
done
```

Kriteria `noarch` yang aman: tidak ada ELF terkompilasi **dan** tidak ada
dependensi dengan batas versi yang di-generate otomatis.

### `-A` memicu auto-bootstrap, dan pesannya memakai kata ERROR

```
=> ERROR: tpkg is not a bootstrap package and cannot be built without bootstrapping first.
=> binary bootstrapping for x86_64-musl in .../masterdir-x86_64-musl...
=> xbps-src: installing base-chroot...
```

Itu **bukan kegagalan**. `cmd_setup` hanya menjamin masterdir host; begitu `-A`
menunjuk masterdir lain yang belum ada, `xbps-src` membuatnya sendiri di tengah
build. Buktinya ada di baris berikutnya yang terus jalan.

Biayanya terbatas: dari host `x86_64` glibc, 9 target hanya butuh **3 masterdir**
— `masterdir-x86_64` (native), `masterdir-x86_64-musl` (dipakai bersama oleh
`x86_64-musl`, `aarch64-musl`, `armv6l-musl`, `armv7l-musl`), dan `masterdir-i686`.

### Prune hanya berjalan di tag yang diproses

`-u` men-trigger `process.yml` dengan daftar tag yang tersentuh, bukan 9 tag.
Versi lama di tag lain tetap tersimpan sampai tag itu diproses. Untuk bersih
menyeluruh:

```sh
gh workflow run process.yml -R T4n-Labs/repo-t4nos -f tags=all
```

Tag tanpa perubahan akan skip cepat (`tidak ada yang perlu diproses`).

### Pemeriksaan yang tidak bisa dijalankan

`python3 -c "import yaml; yaml.safe_load(...)"` gagal dengan
`ModuleNotFoundError: No module named 'yaml'` di mesin dev. **Jangan dianggap
lulus.** Cari nama paketnya dulu (`xbps-query -Rs pyyaml`), pasang, baru jalankan.
Alternatif tanpa dependensi — probe struktural, bukan pengganti parse penuh:

```sh
grep -nE '^  [a-z][a-z-]*:$' .github/workflows/process.yml   # kunci job
grep -n $'\t' .github/workflows/process.yml                  # tab, harus 0
gh api repos/T4n-Labs/repo-t4nos/actions/workflows --jq '.workflows[]|{name,path,state}'
```

Baris terakhir memvalidasi sisi GitHub: kalau `process.yml` muncul dengan
`state: active`, GitHub berhasil mem-parse-nya.

---

**T4n Labs ◉ Gh0sT4n** — *Memberdayakan ekosistem T4n Labs.*