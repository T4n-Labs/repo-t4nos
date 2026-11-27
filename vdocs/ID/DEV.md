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
5. **Template tidak pernah di-`source`; `FIX.sh` justru dieksekusi.** Template
   berasal dari pihak lain dan hanya diparse dengan `grep`/`sed`/regex.
   `FIX.sh` (§15) adalah kebalikannya: skrip yang **dijalankan** di host. Artinya
   `pkg-template/` kini zona *trusted*, bukan sekadar data. PR yang menambah atau
   mengubah `FIX.sh` wajib direview manual — jangan auto-merge. Job pemegang
   secret tetap memakai `sparse-checkout: .github/workflows`, sehingga `FIX.sh`
   **tidak pernah berjalan di CI**.
6. **File upstream yang dimutasi harus terdaftar.** `FIX.sh` hanya boleh mengubah
   file tracked upstream yang ada di `FIX_MUTABLE` (`src/common.sh`). File itu
   dipulihkan ke kondisi upstream sebelum `git pull --ff-only`, lalu di-apply
   ulang sesudahnya. `etc/conf` **dilarang** masuk daftar itu — di situ
   `XBPS_ALLOW_RESTRICTED=yes` disimpan (§15).

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
├── pkg-template/<pkg>/         # flat, tanpa folder kategori
│   ├── template                # wajib
│   └── FIX.sh                  # opsional; dieksekusi sebelum build (§15)
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

Hook FIX.sh (`fix_run`, `fix_run_all`, `fix_revert`) tinggal di `env.sh`, **bukan**
modul baru. Jumlah modul `vdev/src/` tetap 7 dan `tools.sh` tidak berubah.

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

```
vdev/tools.sh -s              # clone void-packages + binary-bootstrap 9 archs + enable restricted
vdev/tools.sh -sy             # git pull + salin template baru/berubah
vdev/tools.sh -U              # jalankan xbps-src bootstrap-update untuk semua archs
vdev/tools.sh -b <pkg>        # build
vdev/tools.sh -f <pkg>        # force rebuild (xbps-src -f)
vdev/tools.sh -c              # clean build artifacts (xbps-src clean)
vdev/tools.sh -z              # hapus masterdir (xbps-src zap)
vdev/tools.sh -u <pkg>        # upload + trigger CI, lalu tawarkan push/PR
```

### Setup
`vdev/tools.sh -s` sekarang menyiapkan **semua 9 arsitektur** sekaligus:
- Clone void-packages (full history)
- Binary-bootstrap untuk `x86_64`, `x86_64-musl`, `aarch64`, `aarch64-musl`, `armv6l`, `armv6l-musl`, `armv7l`, `armv7l-musl`, `i686`
- Otomatis mengaktifkan `XBPS_ALLOW_RESTRICTED=yes` di `$VP/etc/conf`

Masterdir yang sudah ada akan dilewati (tidak di-bootstrap ulang).

### Update
`vdev/tools.sh -U` melakukan:
1. `git pull --ff-only` pada void-packages
2. `xbps-src -A <arch> bootstrap-update` untuk setiap masterdir yang sudah ada

### Force Build
`vdev/tools.sh -f` mengikuti pola yang sama dengan `-b`, tapi memaksa rebuild dari nol:

```
vdev/tools.sh -f                         # interaktif
vdev/tools.sh -f tpkg zvc                # beberapa paket
vdev/tools.sh -f tpkg   -a aarch64       # satu arsitektur
vdev/tools.sh -f tpkg   -a all           # semua yang didukung
vdev/tools.sh -f zvc    -a 'x86_64*'     # x86_64 glibc + musl
```

Flag `-f` di `xbps-src` memaksa rebuild meskipun package sudah ada di cache. Berguna
untuk perubahan besar di template atau retry setelah build gagal.

Sebelum loop arsitektur, `tpl_stage` menyalin template lalu menjalankan `FIX.sh`
paket itu sekali (§15). Gagal → paket di-skip, `rc=1`, lanjut ke paket berikutnya.

### Clean & Zap
- `vdev/tools.sh -c` — jalankan `xbps-src clean` untuk membersihkan build artifacts
  (wrkdir, destdir), tapi masterdir tetap ada
- `vdev/tools.sh -z` — jalankan `xbps-src zap` untuk menghapus **semua masterdir**.
  Setelah zap, perlu jalankan `-s` lagi untuk bootstrap ulang (bisa lama)

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

Sebelum loop arsitektur, `tpl_stage` menyalin template lalu menjalankan `FIX.sh`
paket itu sekali (§15). Gagal → paket di-skip, `rc=1`, lanjut ke paket berikutnya.

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

    vdev/tools.sh -sy

Urutan wajib, dan urutannya sendiri adalah bagian dari kontrak:

    fix_revert            → pulihkan file di FIX_MUTABLE ke kondisi upstream
    git pull --ff-only    → tidak macet karena working tree bersih
    _staged_prune         → buang salinan template yang sudah dihapus
    salin template        → pkg-template/ → void-packages/srcpkgs/
    fix_run_all           → apply ulang SEMUA FIX.sh (fase sync)

`fix_revert` sebelum pull itu wajib: `common/shlibs` adalah file tracked upstream,
dan `git pull --ff-only` menolak jalan kalau file itu kotor. `fix_run_all` sesudah
copy juga wajib: setelah revert, pohon build kembali pristine, jadi kalau tidak
di-apply ulang maka (a) `xbps-src pkg` manual gagal pkglint, dan (b) paket lain
yang butuh SONAME paket tetangga ikut gagal — misalnya `iaito` yang memerlukan
`libr_anal.so.6.2.6` punya `radare2`, padahal `tpl_stage iaito` tidak menyentuh
`FIX.sh` radare2.

`fix_run_all` dijalankan **setelah** loop copy supaya kalau `FIX.sh`-nya sendiri
ikut diperbarui dari repo, yang dijalankan versi baru. Kegagalan `FIX.sh` di fase
sync hanya `warn`; sinkronisasi paket lain tetap lanjut.

Nama yang disalin dicatat di `void-packages/.git/t4n-staged` (di dalam `.git`,
jadi tidak mengotori `git status`). Template yang kemudian dihapus dari
`pkg-template/` dibersihkan dari `srcpkgs/` pada sync berikutnya; bila namanya
ada di upstream Void, resep resmi dipulihkan lewat `git checkout`. Entri
`common/shlibs` miliknya ikut hilang karena `fix_revert` + `fix_run_all` hanya
meng-apply paket yang masih ada.

Nama paket yang masuk ke operasi path divalidasi oleh `pkg_safe` (`name_safe`
ditambah "tidak diawali `.` atau `-`"); nama tidak aman ditolak dengan error.
`-b` memvalidasi semua nama dan keberadaan template sebelum clone/bootstrap.

Catatan: `git -C void-packages status` akan menampilkan `common/shlibs` sebagai
modified selama ada paket dengan `FIX.sh`. Itu normal dan tidak bisa dihindari —
file itu memang wajib diperbarui. Yang dijaga adalah agar pull tidak macet.

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
- [ ] If the package ships a `FIX.sh`: idempotent (run twice, identical result),
    writes no tracked file outside `FIX_MUTABLE`, does not hardcode the version
- [ ] `grep -c ' <pkg>-<ver>_<rev>$' void-packages/common/shlibs` is stable before & after `-sy`
- [ ] If the SONAME was bumped: reverse dependencies revbumped and rebuilt (§14)

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
| Baris `FIX:` tidak muncul di log | nama file bukan persis `FIX.sh` → `fix_run` no-op diam-diam (§15) |
| `common/shlibs` membengkak tiap sync | `FIX.sh` tidak idempoten: append tanpa membuang entri lama |
| `git pull --ff-only` gagal setelah ada `FIX.sh` | file yang dimutasi belum terdaftar di `FIX_MUTABLE` |
| `XBPS_ALLOW_RESTRICTED` mati sendiri | `etc/conf` masuk `FIX_MUTABLE` → keluarkan (§15) |
| `SONAME bump detected` / `please update common/shlibs` | entri belum ada; `shlib_provides` bukan pengganti (§14) |
| Paket lain rusak setelah bump SONAME | revbump + rebuild paket itu (mis. `iaito`) (§14) |
| `tools.sh` mati total, syntax error | cek `bash -n` per modul, bukan cuma `tools.sh` (§15) |

## 12. Status Implementasi
Diperbarui 27 November 2026. Setiap baris "terverifikasi" punya bukti keluaran
perintah, uji di sandbox, atau log CI; yang lain ditandai eksplisit.

### Terverifikasi
| Item | Bukti |
| --- | --- |
| `cmd_setup` bootstrap 9 archs + enable restricted | kode + uji manual (27 Nov) |
| `cmd_update` pull + bootstrap-update 9 archs | kode + uji manual (27 Nov) |
| `cmd_force` mengikuti pola `cmd_build` dengan flag `-f` | kode + uji manual (27 Nov) |
| `cmd_clean` dan `cmd_zap` wrapper untuk xbps-src | kode (27 Nov) |
| flags_for benar untuk 9 target dari host x86_64; x86_64-musl, i686, aarch64 dicek lewat override HOST_ARCH | keluaran uji (25 Nov), cocok tabel §6 |
| Signing berjalan — tag punya .xbps + .sig2 + <tag>-repodata | screenshot Releases (tpkg-1.1.0_1, lalu _2) (24 Nov) |
| FINGERPRINT di setup.sh = MD5 blob keys/key.pem.pub | dihitung ulang (25 Nov) |
| json/<tag>/packages.json ×9 sudah ter-commit CI | ls json/* |
| .github/workflows/ = 3 file; vdev/src/ = 7 modul | ls -1 |
| process.yml = 4 job; step json memakai shell: bash; permissions per job; action dipin SHA | grep + yaml.safe_load |
| Parser Bash/awk ≡ Python (field dan archs), tanpa glob terhadap cwd | uji paritas 56 kasus (25 Nov) |
| process-tag.sh: upload ulang nama sama, versi baru ditolak, run lanjutan tanpa churn, .sig2 yatim | harness stub (gh/xbps-* palsu), 25 Nov |
| Perbaikan vdev/ (route_tags, menu 08/09, urutan validasi, pkg_safe, git_offer, sync) | uji reproduksi sebelum/sesudah (25 Nov) |
| bash -n, sh -n, ast.parse, yaml.safe_load, JSON valid | keluaran perintah |
| Hook `FIX.sh` jalur build (`-b`): `radare2-6.2.6_1` + `radare2-devel` x86_64 terbangun, pkglint lolos | log build (28 Nov) |

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
| Hook `FIX.sh` jalur sync (`fix_run_all`) end-to-end | kode saja; uji `grep -c` sebelum/sesudah `-sy` (§15) |
| `FIX.sh` untuk paket selain radare2 | belum ada pengguna lain; kontrak belum diuji lintas paket |
| `FIX.sh` pada 9 arsitektur | baru x86_64 native yang dijalankan |

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

### `common/shlibs` wajib; `shlib_provides` bukan penggantinya

    => ERROR: radare2-6.2.6_1: SONAME bump detected: libr_anal.so.5.9.8 -> libr_anal.so.6.2.6
    => ERROR: radare2-6.2.6_1: please update common/shlibs with this line: "libr_anal.so.6.2.6 radare2-6.2.6_1"
    => ERROR: radare2-6.2.6_1: all reverse dependencies should also be revbumped ...
    => ERROR:    iaito-5.9.9_1
    => ERROR:   in hook() at common/hooks/pre-pkg/99-pkglint.sh:199

`common/shlibs` adalah registry global SONAME → package, dipakai untuk resolusi
dependensi *dan* pelacakan reverse dependency. Hook `99-pkglint` meng-`grep` pola
`<soname> <pkgname>-<version>_<revision>` secara harfiah di file itu; kalau tidak
ada, build ditolak. Menaruh `shlib_provides` di template **tidak** melewati
pemeriksaan ini — ia hanya menambah metadata *provides*, bukan registry.

Konsekuensi untuk repo ini: mengedit `common/shlibs` itu wajib, dan file itu
tracked upstream. Karena itu ada `FIX_MUTABLE` + `fix_revert` (§15), bukan
sekadar skrip manual.

Edit ke `common/shlibs` bersifat **persisten** — secara manual hanya perlu sekali
per version bump, bukan setiap build. Framework tetap meng-apply ulang setiap
kali supaya clone baru dan pohon pasca-sync selalu benar.

Baris `all reverse dependencies should also be revbumped` bukan hiasan: paket
yang menaut ke SONAME lama benar-benar rusak setelah bump. Naikkan `revision`
paket itu lalu bangun ulang. Kalau paket tersebut tidak ada di `pkg-template/`,
`-b` menolaknya — tambahkan dulu atau bangun dari `void-packages/srcpkgs/`.

## 15. `FIX.sh` — Hook Per-Paket

Sebagian paket butuh perbaikan **di luar template** agar `xbps-src` mau
membangunnya. Kasus kanonik: `radare2` menaikkan SONAME, dan hook
`pre-pkg/99-pkglint` menolak build sampai entri SONAME ada di `common/shlibs`
(§14). Perbaikan seperti itu tidak bisa ditulis di template. Daripada maintainer
menjalankan skrip manual setiap kali, tool menyediakan satu aturan umum.

> Kalau sebuah paket punya `pkg-template/<pkg>/FIX.sh`, tool menjalankannya
> sendiri — sekali per paket, di host, sebelum `xbps-src pkg <pkg>`.

### Kontrak

| Aspek | Aturan |
| --- | --- |
| Lokasi | `pkg-template/<pkg>/FIX.sh` — opsional |
| Nama | persis `FIX.sh`. Nama lain diabaikan **tanpa log apa pun** |
| Kapan | sekali per paket di `tpl_stage`, sebelum loop arsitektur |
| Di mana | **host**, bukan di dalam masterdir/chroot |
| CWD | `$VP/srcpkgs/<pkg>` → path relatif `../../common/shlibs` valid |
| Interpreter | shebang dihormati; bit executable di-set otomatis pada salinan |
| Wajib | **idempoten** — dijalankan ulang tiap build, force, dan sync |
| Exit ≠ 0 | build/force: paket di-skip, `rc=1`. sync: `warn`, lanjut |

Berjalan di host bukan pilihan desain bebas: di dalam chroot, `common/` bisa
ter-mount read-only, jadi mutasi `common/shlibs` tidak dijamin berhasil.

### Variabel lingkungan

| Variabel | Isi |
| --- | --- |
| `T4N_PKG` | nama paket |
| `T4N_VERSION` | field `version` template (diparse, bukan di-source) |
| `T4N_REVISION` | field `revision`, default `1` |
| `T4N_PHASE` | `build` atau `sync` |
| `T4N_VP` | path absolut `void-packages` |
| `T4N_TPL` | path absolut `pkg-template` |
| `T4N_REPO` | path absolut `repo-t4nos` |
| `T4N_HOST_ARCH` | arsitektur host |

Karena versi dan revisi disuntikkan, `FIX.sh` tidak boleh meng-hardcode keduanya.
Naik versi upstream cukup mengubah `version=` di template.

### Kapan hook berjalan

| Perintah | `FIX.sh` | Cakupan | Bila gagal |
| --- | : ---: | --- | --- |
| `-s` / `--setup` | tidak | belum ada yang ter-stage | — |
| `-sy` / `--sync` | ya, pasca-copy | **semua** paket ter-stage | `warn`, sync lanjut |
| `-b` / `--build` | ya, di `tpl_stage` | paket yang dibangun | skip paket, `rc=1` |
| `-f` / `--force` | ya, di `tpl_stage` | paket yang di-force | skip paket, `rc=1` |
| `-U` / `--update` | tidak | tidak menyentuh file tracked | — |
| `-c` / `-z` | tidak | tidak menyentuh file tracked | — |
| `-u` / `--upload` | tidak | tidak membangun | — |

### `FIX_MUTABLE`

`FIX_MUTABLE=(common/shlibs)` di `src/common.sh` adalah daftar file tracked
upstream yang boleh dimutasi `FIX.sh`. `fix_revert` memulihkan hanya file di
daftar itu sebelum pull — bukan "semua yang kotor".

⚠️ **Jangan masukkan `etc/conf`.** `cmd_setup` menulis
`XBPS_ALLOW_RESTRICTED=yes` ke sana; kalau ikut dipulihkan, restricted mati lagi.
Itu sebabnya daftarnya allowlist eksplisit, bukan sapuan `git checkout -- .`.

Kalau sebuah `FIX.sh` mengubah file tracked lain, daftarkan dulu. Tanpa itu,
`git pull --ff-only` pada `-sy` berikutnya gagal dengan
*"Your local changes would be overwritten by merge"*.

### Batasan yang harus diterima

- **Sekali per paket, bukan per arch.** Untuk SONAME ini tepat: `libr_anal.so.6.2.6`
  sama di semua arsitektur. Kalau suatu saat ada perbaikan yang harus tahu target
  arch (mis. patch khusus musl), kontrak ini **tidak cukup** — jangan dipaksa
  masuk `FIX.sh`, buat hook terpisah.
- **Kerja berat dilarang di jalur tanpa guard.** Karena hook juga jalan tiap
  sync, jangan taruh download/generate/compile di situ. Kalau memang perlu:

      [ "${T4N_PHASE:-build}" = build ] || exit 0

- **Idempotensi wajib keras.** `fix_revert` hanya memulihkan file di
  `FIX_MUTABLE`. `FIX.sh` yang append tanpa membuang entri lama akan membuat
  `common/shlibs` membengkak setiap sync.

### Contoh: `pkg-template/radare2/FIX.sh`

```sh
#!/bin/sh
# FIX.sh — radare2: daftarkan SONAME ke common/shlibs.
# Wajib: hook pre-pkg/99-pkglint menolak build kalau entri tidak ada (§14).
# Idempoten: entri lama milik radare2 dibuang, lalu ditulis ulang.
set -eu

# fallback supaya bisa juga dijalankan manual dari folder ini
: "${T4N_PKG:=radare2}"
: "${T4N_VERSION:=$(sed -n 's/^version=//p' template)}"
: "${T4N_REVISION:=$(sed -n 's/^revision=//p' template)}"
map="${T4N_VP:-../..}/common/shlibs"
pkg="${T4N_PKG}-${T4N_VERSION}_${T4N_REVISION:-1}"

[ -f "$map" ] || { echo "FIX: tidak ada $map" >&2; exit 1; }

sed -i -E '/^(libr_[a-z0-9_]+|libsdb)\.so\.[0-9.]+[[:blank:]]+radare2-/d' "$map"
for l in core config cons util flag arch asm bin anal lang debug egg bp \
         search io socket syscall fs magic reg main muta esil; do
	printf 'libr_%s.so.%s %s\n' "$l" "$T4N_VERSION" "$pkg"
done >> "$map"
printf 'libsdb.so.2.6.2 %s\n' "$pkg" >> "$map"
```

24 entri: 23 `libr_*` + `libsdb`. `libsdb` versinya sendiri (`2.6.2`), bukan
versi radare2 — jangan di-parameterisasi.

### Verifikasi

```bash
# 1. syntax semua modul (bash -n tools.sh TIDAK memeriksa file yang di-source)
for f in vdev/tools.sh vdev/src/*.sh; do bash -n "$f" || echo "ERR: $f"; done

# 2. hook benar-benar menemukan file-nya
ls -l pkg-template/*/FIX.sh

# 3. idempotensi: angka harus sama sebelum dan sesudah sync
grep -c ' radare2-6.2.6_1$' void-packages/common/shlibs   # 24
./vdev/tools.sh -sy
grep -c ' radare2-6.2.6_1$' void-packages/common/shlibs   # harus tetap 24
```

Hasil yang diharapkan dari `-sy`:

    [INFO] FIX: common/shlibs dipulihkan ke upstream
    [INFO] git pull void-packages...
    [INFO] FIX: radare2 → FIX.sh (sync)
    [OK] FIX: radare2 selesai
    [OK] FIX: 1 script dijalankan

Angka jadi **0** → `fix_run_all` belum dipanggil di `cmd_sync`.
Angka jadi **48** → `sed` pembuang entri lama tidak jalan.
Baris `FIX:` tidak muncul sama sekali → nama file bukan `FIX.sh`.

---

**T4n Labs ◉ Gh0sT4n** — *Memberdayakan ekosistem T4n Labs.*
