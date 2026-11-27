# Repositori T4n OS — Panduan Developer & Maintainer

Infrastruktur `repo-t4nos`: satu repositori GitHub untuk glibc dan musl, biner di
GitHub Releases, indeks di `json/`, semuanya otomatis lewat CI. Repositori ini
menghasilkan paket biner saja. Website ada di repositori terpisah (`repo-site`).

> Sumber kebenaran adalah kode. Kalau dokumen ini dan kode berbeda, kode yang
> menang lalu dokumen diperbaiki. Hal yang belum dibuktikan keluaran perintah
> ditandai "belum diverifikasi". Cuplikan status: 25 November 2026 (§12); klaim sisi GitHub/Cloudflare/website bertanggal 22–24 November dan belum diverifikasi ulang.

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
│   ├── process-tag.sh          # per-tag: inventory → verifikasi → sign → prune (PEGANG SECRET)
│   └── gen-json.py             # per-tag: repodata + template → packages.json
├── json/<tag>/packages.json    # ×9, di-commit balik oleh CI
├── keys/key.pem.pub            # satu-satunya file key yang publik
├── pkg-template/<pkg>/template # flat, tanpa folder kategori (saat ini: tpkg, zvc)
├── vdev/
│   ├── tools.sh                # dispatcher tipis
│   ├── DNS-check.sh            # uji domain/Worker read-only (§13)
│   ├── worker/index.js         # Cloudflare Worker `t4n-repo` (dikelola Founder)
│   └── src/
│       ├── common.sh           # path, konstanta, log, guard (name_safe, pkg_safe)
│       ├── template.sh         # parser template + ekspansi archs
│       ├── env.sh              # setup, sync, flag xbps-src
│       ├── build.sh            # menu paket/arsitektur + build
│       ├── upload.sh           # upload release + trigger CI
│       ├── git.sh              # tawaran push / pull-request
│       └── search.sh           # `tools search <query>`
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
| `all` | semua 9 tag (sama dengan `*`) |
| `all ~i686` | semua tag kecuali `i686` |
| `~~i686` | sama dengan `~i686` (jumlah `~` tidak dibedakan) |

⚠️ Paket C yang belum siap musl harus menulis arsitektur eksplisit; `*` membuat CI
mencoba build musl dan gagal.

⚠️ **`noarch` bukan aturan pukul rata.** Aman hanya bila paket tidak punya ELF
terkompilasi **dan** tidak ada dependensi dengan batas versi yang di-generate
otomatis. Contoh klasik: paket Python `build_style=python3-pep517` (mis. `letx`,
yang templatenya sudah dirapikan dari `pkg-template/` pada snapshot ini) membawa
`run_depends: python3>=3.14.0_1<3.15.0_1` yang di-generate dari host build;
menjadikannya `noarch` mengunci satu batas dari host yang bisa tidak terpuaskan
di arsitektur lain. Lihat §14.

**Kontrak parser.** Ada dua parser template — Bash/awk (`vdev/src/template.sh`) dan
Python (`.github/workflows/gen-json.py`) — dan keduanya **harus berperilaku
identik**; ubah keduanya sekaligus:

- Field: baris pertama yang cocok `^[ \t]*KEY=`. `#` memulai komentar hanya di
  luar kutip **dan** di awal nilai / setelah spasi-tab (`"https://x/#a"` dan
  `"A # B"` aman). Backslash meloloskan karakter berikutnya (kecuali dalam
  kutip tunggal). Lalu trim spasi/tab/CR dan buang **satu** pasang kutip pembungkus.
- `archs`: koma = spasi; kosong atau `noarch` (saja) = semua tag; token `all` = `*`;
  token berawalan satu atau lebih `~` = negasi; pola glob (`*`, `?`, `[..]`) tidak
  pernah di-glob terhadap isi direktori kerja; tanpa token positif = semua tag.

Verifikasi ekspansi tanpa bootstrap apa pun (`template.sh` hanya berisi definisi
fungsi, tidak punya mode `--selftest`):

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; expand_archs "x86_64* ~x86_64-musl"'
# → x86_64
```

## 5. Membuat Paket Baru

`pkg-template/tpkg/template` (isi persis berkas di repositori saat ini):

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

Konvensi:

- `version` **tanpa** revisi. Benar: `version=1.1.0 revision=1`. Salah:
  `version=1.1.0_1`.
- Naikkan `revision` untuk perubahan template saja; reset ke `1` saat versi
  upstream baru.
- `distributor` menandai siapa yang mengemas (Let-X akan mengisinya untuk template
  pihak lain).
- Nama paket harus di dalam `[A-Za-z0-9._+-]` dan tidak boleh diawali `.` atau `-`
  (`pkg_safe`; `-b`, `-u`, dan `-sy` menolaknya, bukan sekadar warning). Lihat §9.
- Baris `# depends="sudo"` di akhir template hanyalah komentar; parser hanya
  membaca baris `KEY=` yang diawali (boleh berindentasi) di awal baris.
- `tpkg` adalah shell murni dengan `depends="xbps"` tanpa versi, jadi **cocok**
  untuk `archs=noarch` (satu build, di-fanout ke semua tag). Namun template saat ini
  **belum menulis `archs`** (keputusan belum diambil, §12/§14): tanpa itu `-b`
  menganggap 9 arsitektur dan membangun 9 kali termasuk 5 cross, memicu build GCC
  dari source (§14).

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
vdev/tools.sh -b tpkg   -a aarch64       # satu arsitektur
vdev/tools.sh -b tpkg   -a all           # semua yang didukung
vdev/tools.sh -b tpkg   -a x86_64 i686   # beberapa
vdev/tools.sh -b zvc    -a 'x86_64*'     # x86_64 glibc + musl
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
| base arch berbeda | `-a <target lengkap>`; ditambah `-A <hostbase>[-musl]` (libc target) **hanya bila libc host ≠ libc target** |

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

Dari host `x86_64-musl` (dicek dengan meng-override `HOST_ARCH`): `x86_64` →
`-A x86_64`; `x86_64-musl` → tanpa flag; `aarch64` → `-A x86_64 -a aarch64`;
`aarch64-musl` → `-a aarch64-musl` (libc sama, **tanpa** `-A`).

Dua bug yang diperbaiki:

1. **`-a` dulu membuang `-musl`.** Target `armv6l-musl` menghasilkan `-a armv6l`,
   jadi paket yang dibangun sebenarnya **glibc** meskipun diminta musl — gagal
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

### Sync

```sh
vdev/tools.sh -sy
```

`git pull --ff-only` pada `void-packages`, lalu menyalin template baru/berubah dari
`pkg-template/` ke `void-packages/srcpkgs/`. Nama yang disalin dicatat di
`void-packages/.git/t4n-staged` (di dalam `.git`, jadi tidak mengotori `git status`).
Template yang kemudian **dihapus** dari `pkg-template/` dibersihkan dari `srcpkgs/` pada
sync berikutnya; bila namanya ada di upstream Void, resep resmi dipulihkan lewat
`git checkout`. Pelacakan dimulai sejak sync pertama dengan versi ini — salinan lama
dari sebelum itu harus dibersihkan manual (`git -C void-packages status`).

Nama paket yang masuk ke operasi path divalidasi oleh `pkg_safe` (`name_safe` ditambah
"tidak diawali `.` atau `-`"); nama tidak aman ditolak dengan error. `-b` memvalidasi
semua nama dan keberadaan template **sebelum** clone/bootstrap `void-packages`.

### Upload

```sh
vdev/tools.sh -u tpkg
```

1. `gh auth status`: belum login → error jelas dan upload/trigger dilewati (exit 1).
   Lalu cek akses write via `gh api repos/T4n-Labs/repo-t4nos --jq .permissions.push`;
   kegagalan API dilaporkan apa adanya, tidak dianggap "tanpa izin".
2. **Punya write:** mencocokkan file `.xbps` di `void-packages/hostdir/binpkgs`
   dengan `pkgname` + subpackage dan `version_revision` template, mengarahkannya
   ke tag (`noarch` → semua tag yang didukung; arsitektur di luar `archs` →
   warning dan dilewati), upload dengan `--clobber`, lalu men-trigger `process.yml`
   **sekali** dengan daftar tag yang tersentuh.
3. **Tanpa write:** upload dan trigger dilewati, dengan pemberitahuan bahwa
   maintainer akan build dan upload setelah PR di-merge.
4. Dua-duanya tetap menawarkan `git push`, dan menawarkan buka PR kalau `origin`
   bukan `T4n-Labs/repo-t4nos`. Tawaran aman tanpa TTY (EOF = "tidak") dan tidak
   mengubah exit code setelah upload sukses.

Hanya file yang cocok `version_revision` template yang diupload; build lama di
`binpkgs` di-skip dengan warning. Template adalah sumber kebenaran, bukan "file
terbaru di folder". Urutan penting: **edit template → build → upload**.

Meng-upload ulang biner **dengan nama sama** (rebuild tanpa naik `revision`) didukung:
`--clobber` mengganti `.xbps`, dan CI mendeteksi `.xbps` yang lebih baru dari
`.sig2`-nya lalu menandatangani ulang. Tetap naikkan `revision` untuk perubahan yang
harus sampai ke pengguna — klien yang sudah menyimpan file bernama sama di cache tidak
mengunduhnya lagi.

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

⚠️ **Jebakan shell container (§14):** container Void menjalankan blok `run` dengan
`sh`, yang tidak mengenal `pipefail`. Step job `json` yang diawali
`set -euo pipefail` karena itu memakai `shell: bash` (sudah diterapkan di
`process.yml`; pertahankan). Job `process` tidak kena karena `pipefail`-nya ada di
dalam `process-tag.sh`, dipanggil dengan `bash`.

### Izin dan pin di `process.yml`

- `permissions` default `contents: read`; `prepare`, `process`, dan `commit` menaikkan
  sendiri ke `contents: write` (buat release / upload-hapus asset / push `json/`),
  `json` tetap `contents: read`.
- Action dipin ke SHA commit (`checkout` v4.3.1, `upload-artifact` v4.6.2,
  `download-artifact` v4.3.0); perbarui dengan sengaja, jangan kembali ke tag mengambang.
- `persist-credentials: false` pada checkout job `process` (pemegang secret) dan `json`.
- Image container: `ghcr.io/void-linux/void-{glibc}-full:${{ vars.VOID_IMAGE_TAG || 'latest' }}`.
  Untuk memin, set variabel repo `VOID_IMAGE_TAG` ke tag bertanggal. Selama belum
  diset, image jatuh ke `latest` (**tidak terpin**; lihat §12).

### Isi job `process` (per tag)

```
inventory   daftar asset (nama + updated_at) via API paginated
rencana     per nama paket, telusuri kandidat versi tertinggi → terendah
            (xbps-uhelper getpkgname / cmpver — bukan regex)
            tepercaya = .sig2 ada DAN tidak lebih tua dari .xbps → dipilih tanpa unduh
            selain itu (tanpa .sig2, atau .xbps lebih baru dari .sig2) → unduh + verifikasi
verifikasi  baca props.plist di dalam .xbps; nama asset harus persis
            <pkgver>.<architecture>.xbps; gagal → DITOLAK (dibiarkan, TIDAK dihapus),
            penelusuran lanjut ke versi di bawahnya
prune       hanya kandidat DI BAWAH versi terpilih yang lolos verifikasi
unsigned    = terpilih tanpa .sig2 segar
skip        unsigned & prune kosong, repodata ada dan tidak lebih tua dari .xbps
            → hanya hapus .sig2 yatim, selesai
[1/3] index xbps-rindex -a *.xbps            → <tag>-repodata
[2/3] sign  xbps-rindex --sign               → kunci publik masuk ke repodata
[3/3] sign  xbps-rindex --sign-pkg           → .sig2 hanya untuk yang unsigned
upload      repodata + .sig2 baru DULU
prune       hapus .xbps + .sig2 lama TERAKHIR, lalu .sig2 yatim
```

Detail yang perlu diketahui:

- **Kalibrasi `cmpver`.** Daripada mengasumsikan apakah `xbps-uhelper cmpver`
  melapor lewat stdout atau exit code, skrip menjalankan dua probe yang jawabannya
  sudah diketahui lalu mencocokkan signature-nya. Kalau kedua probe terlihat
  identik, pruning dibatalkan daripada berisiko menghapus versi yang salah.
- **Verifikasi gagal tidak menghapus apa pun.** Versi terbaru yang ditolak dibiarkan
  di release, versi lama yang valid tetap dipakai dan tidak di-prune. Kalau satu nama
  paket tidak punya versi lolos sama sekali, hanya muncul peringatan dan semua
  berkasnya dibiarkan; kalau **tidak ada** paket lolos di tag itu, job gagal
  (`exit 1`). Asset yang ditolak tidak membuat repodata diunggah ulang setiap run;
  perbaiki dengan upload ulang bernama benar lalu hapus yang salah secara manual.
- **Upload ulang nama sama.** `.xbps` yang `updated_at`-nya lebih baru dari `.sig2`-nya
  dianggap basi: diverifikasi ulang, di-index ulang, dan `.sig2`-nya dibuat ulang.
- **`.sig2` yatim** (pasangan `.xbps`-nya sudah tidak ada) dihapus di akhir, setelah upload.
- **Berkas tepercaya yang gagal verifikasi ulang** (anomali) menghentikan job tanpa
  mengubah apa pun.
- **Tag kosong.** Kalau tidak ada `.xbps` sama sekali, `.sig2` yatim dan repodata
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

| Field | Sumber |
|---|---|
| `name` | `pkgname` |
| `version` | dari `pkgver` repodata (`<nama>-<versi>_<revisi>` → versi tanpa revisi); kategori `template`: field `version` template |
| `arch` | nama tag |
| `archs` | `archs` template, sudah di-expand (kontrak §4); subpackage tanpa template fallback ke `[tag]` |
| `size` | ukuran asset `.xbps` (byte); cadangan `filename-size` repodata; `null` untuk `template` |
| `category` | `xbps` (biner ada di tag ini) atau `template` (hanya template, biner belum dibangun) |
| `desc` | `short_desc` (repodata, cadangan template) |
| `homepage`, `maintainer`, `license` | repodata, cadangan template |
| `distributor` | hanya dari template |

JSON **tidak** memuat `filename`, `url`, atau `status`; URL unduhan dibentuk klien dari
`<BASE>/<tag>/<pkgver>.<arch>.xbps`.

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
- [ ] `json/<tag>/packages.json` memuat paket dengan `category: xbps` untuk arsitektur yang diharapkan (dan tampil di website)
- [ ] `xbps-install -S && xbps-install <pkg>` sukses di sistem uji bersih
- [ ] Versi lama hilang dari release tag (`gh release view <tag>`)

## 11. Troubleshooting

| Gejala | Penyebab / perbaikan |
|---|---|
| Job `json`: `set: Illegal option -o pipefail` | container menjalankan `sh`; pastikan step itu tetap memakai `shell: bash` (§14) |
| `::error::… DITOLAK` di job `process` | nama asset ≠ isi paket; asset dibiarkan dan versi lama yang valid tetap dipakai. Upload ulang dengan nama benar, hapus yang salah manual |
| Client: signature gagal setelah upload ulang nama sama | `.xbps` lebih baru dari `.sig2`; CI menandatangani ulang di run berikutnya — percepat dengan `gh workflow run process.yml -R T4n-Labs/repo-t4nos -f tags=<tag>` |
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

Diperbarui 25 November 2026. Setiap baris "terverifikasi" punya bukti keluaran
perintah, uji di sandbox, atau log CI; yang lain ditandai eksplisit.

### Terverifikasi

| Item | Bukti |
|---|---|
| `flags_for` benar untuk 9 target dari host `x86_64`; host `x86_64-musl`, `i686`, `aarch64` dicek lewat override `HOST_ARCH` | keluaran uji (25 Nov), cocok tabel §6 |
| **Signing berjalan** — tag punya `.xbps` + `.sig2` + `<tag>-repodata` | screenshot Releases (`tpkg-1.1.0_1`, lalu `_2`) (24 Nov) |
| `FINGERPRINT` di `setup.sh` = MD5 blob `keys/key.pem.pub` | dihitung ulang (25 Nov) |
| `json/<tag>/packages.json` ×9 sudah ter-commit CI | `ls json/*` |
| `.github/workflows/` = 3 file; `vdev/src/` = 7 modul | `ls -1` |
| `process.yml` = 4 job; step `json` memakai `shell: bash`; `permissions` per job; action dipin SHA | `grep` + `yaml.safe_load` |
| Parser Bash/awk ≡ Python (field dan `archs`), tanpa glob terhadap cwd | uji paritas 56 kasus (25 Nov) |
| `process-tag.sh`: upload ulang nama sama, versi baru ditolak, run lanjutan tanpa churn, `.sig2` yatim | harness stub (`gh`/`xbps-*` palsu), 25 Nov |
| Perbaikan `vdev/` (`route_tags`, menu `08`/`09`, urutan validasi, `pkg_safe`, `git_offer`, sync) | uji reproduksi sebelum/sesudah (25 Nov) |
| `bash -n`, `sh -n`, `ast.parse`, `yaml.safe_load`, JSON valid | keluaran perintah |

### Belum selesai / belum diterapkan

| Item | Keadaan |
|---|---|
| `xbps-install -S` end-to-end lewat domain | belum dilakukan |
| Perilaku nyata `gh release upload --clobber` (apakah `updated_at` `.xbps` maju) dan `xbps-uhelper cmpver` dengan `pkgver` penuh | hanya diuji dengan stub; verifikasi di CI nyata |
| Image container Void tidak terpin | variabel repo `VOID_IMAGE_TAG` belum diset → `latest` |
| Worker + domain aktif | `DNS-check.sh` 14/14 (22 Nov), belum diverifikasi ulang |
| Branch protection, ruleset, `.github/CODEOWNERS` | **tidak ada** (24 Nov, belum diverifikasi ulang) — ditunda sampai repo terbukti dipakai publik |
| Environment `signing` dibatasi ke `main` | `deployment-branch-policies` 404 (24 Nov) → belum dibatasi |
| `CONTRIBUTING*`, LICENSE | belum ada / belum diputuskan |
| Tag `armv6l-musl`, `armv7l-musl` | belum ada paket biner → `xbps-install -S` 404 untuk arsitektur itu |
| `./tools` dan `./vdev/tools` (tanpa `.sh`) | `tools.sh` bisa me-resolve symlink, tetapi symlink-nya tidak ada di repo |
| Aturan wajib `archs=noarch` | **belum diputuskan** — `tpkg` saat ini tanpa `archs` (§14) |
| PyYAML di mesin dev | tidak terpasang → pakai probe struktural di §14 |

Urutan tersisa: set `VOID_IMAGE_TAG` → verifikasi `--clobber`/`updated_at` di CI nyata →
`xbps-install -S` di sistem bersih dengan conf **manual ke domain** → hardening
(CODEOWNERS, branch protection, pembatasan Environment).

**Penting:** `setup.sh` secara default menunjuk domain (Worker), jadi menjalankannya
menguji Worker. Kalau `T4N_BASE` di-override ke URL release, Worker tidak ikut diuji.
Tes end-to-end bisa menulis conf manual:

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
di baris 1, sebelum perintah apa pun jalan. Saat itu **semua 9 job `json` gagal**; sudah diperbaiki.

Perbaikan (sudah diterapkan): `shell: bash` pada step yang blok `run`-nya diawali
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
Template saat ini (`revision=2`) **tidak menulis `archs=noarch`**, sehingga ia dianggap
mendukung 9 arsitektur dan `-b` membangun 9 kali termasuk 5 cross — memicu build GCC
di atas untuk menyalin enam file `.sh`. Menjadikannya `noarch` masih berupa keputusan
yang belum diambil (§12).

Satu build `noarch` menghasilkan satu `.noarch.xbps` yang di-fanout `cmd_upload`
ke semua tag yang didukung. **Hemat waktu build, bukan storage**: file yang sama
disimpan sekali per tag (9×).

⚠️ **Jangan pukul rata.** Paket Python `build_style=python3-pep517` (contoh historis:
`letx`, yang kini tidak ada di `pkg-template/`) membawa di `index.plist`-nya
`run_depends: python3>=3.14.0_1<3.15.0_1` — batas versi yang di-generate otomatis dari
python3 di masterdir saat build. Kalau dijadikan `noarch`, satu file membawa satu batas
dari host dan bisa tidak terpuaskan di arsitektur yang revisi python3-nya beda. Cek dulu
(ganti `<pkg>-<versi>_<revisi>`):

```sh
cd void-packages/hostdir/binpkgs
for f in <pkg>-<versi>_<revisi>.*.xbps; do
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
