# Repositori T4n OS — Panduan Developer & Maintainer

Infrastruktur `repo-t4nos`: **satu repositori GitHub untuk glibc dan musl**,
biner di **GitHub Releases**, indeks di `json/`, semuanya otomatis lewat CI.

Repositori ini menghasilkan **paket biner saja**. Website ada di repositori
terpisah (`repo-site`).

---

## 1. Aturan Emas

1. **Biner tidak pernah masuk git.** `.xbps`, `.xbps.sig2`, dan `<tag>-repodata`
   hidup di GitHub Releases. Git hanya berisi template, skrip, docs, dan `json/`.
2. **Signing hanya di CI.** Private key ada di GitHub Secrets (Environment
   `signing`, dibatasi ke `main`). Tidak pernah menyentuh mesin developer.
   `vdev/tools.sh` tidak punya satu pun panggilan `xbps-rindex` atau akses kunci.
3. **Jangan edit release manual.** CI me-reconcile penuh: versi lama di-prune,
   entri indeks yatim dibangun ulang. Edit manual akan ditimpa.
4. **Rencana dulu, hapus terakhir.** Repodata baru diupload *sebelum* asset lama
   dihapus, supaya client tidak pernah membaca indeks yang menunjuk file hilang.
5. **Template tidak pernah di-`source`.** Template berasal dari pihak lain. Parse
   dengan `grep`/`sed`/regex. Job pemegang secret tidak boleh membaca template
   sama sekali.

---

## 2. Struktur

```
repo-t4nos/
├── .github/CODEOWNERS          # workflows/, setup.sh, keys/ → Founder
├── .github/workflows/
│   ├── process.yml         # satu-satunya workflow YAML
│   ├── process-tag.sh      # per-tag: inventory → sign → prune (PEGANG SECRET)
│   └── gen-json.py         # per-tag: repodata + template → packages.json
├── json/<tag>/packages.json    # ×9, di-commit balik oleh CI
├── keys/key.pem.pub            # satu-satunya file key yang publik
├── pkg-template/<pkg>/template # flat, tanpa folder kategori
├── vdev/
│   ├── tools.sh            # dispatcher tipis
│   └── src/
│       ├── common.sh       # path, konstanta, log, guard
│       ├── template.sh     # parser template + ekspansi archs
│       ├── env.sh          # setup, sync, flag xbps-src
│       ├── build.sh        # menu arsitektur + build
│       ├── upload.sh       # upload release + trigger CI
│       └── git.sh          # tawaran push / pull-request
├── worker/index.js             # salinan kode Cloudflare Worker (proxy repo.t4nlabs.web.id)
├── vdocs/{EN,ID}/{DEV,USER}.md
├── setup.sh                # one-liner untuk user
├── CONTRIBUTING.md / CONTRIBUTING.ID.md   # direncanakan, belum ada
└── README.md / README.ID.md
```

Hanya file `*.yml` di `.github/workflows/` yang diparse sebagai workflow. File
`.sh` dan `.py` di situ adalah helper biasa — ditaruh di direktori itu karena dua
alasan konkret:

- `process-tag.sh` berisi logika signing, jadi ikut terlindungi CODEOWNERS +
  branch protection yang diterapkan pada `.github/workflows/`.
- Job `process` memakai `sparse-checkout: .github/workflows`, jadi template
  kontributor tidak pernah ter-checkout ke job pemegang secret. Karena itu skrip
  yang dipanggil job tersebut harus berada di dalam direktori itu.

### Release tag (9)

`x86_64` · `x86_64-musl` · `aarch64` · `aarch64-musl` · `armv6l` ·
`armv6l-musl` · `armv7l` · `armv7l-musl` · `i686`

Nama tag sama dengan string arsitektur XBPS, jadi `xbps-uhelper arch` langsung
memetakan ke tag tanpa tabel pencarian.

### URL

| Kegunaan | URL |
|---|---|
| Website (repo-site) | `https://repo-web.t4nlabs.web.id/` |
| Endpoint XBPS | `https://repo.t4nlabs.web.id/<tag>` |
| Penyimpanan asset | `https://github.com/T4n-Labs/repo-t4nos/releases/download/<tag>` |

Endpoint XBPS adalah **reverse proxy** tipis (Cloudflare Worker `t4n-repo`) di depan
asset release: `/<tag>/<file>` diteruskan ke `releases/download/<tag>/<file>`.
GitHub Pages tidak bisa melakukan ini, jadi domain `repo.t4nlabs.web.id` harus
berada di zona Cloudflare. Worker hanya melayani 9 tag dan nama file
`[A-Za-z0-9._+-]`; selain itu dijawab 404. Sampai domain aktif, pakai URL release
langsung. Domain dan Worker hanya dikelola Founder.

---

## 3. Prasyarat

- Void Linux atau T4n OS (atau container `ghcr.io/void-linux/void-{glibc,musl}-full`)
- `git`, `gh` (sudah terautentikasi)
- `xbps-src` — diambil otomatis oleh `vdev/tools.sh -s`
- **Akses Write** ke `T4n-Labs/repo-t4nos` untuk upload asset dan menjalankan
  `workflow_dispatch`. Kontributor dengan akses `Read` bekerja lewat fork + PR.

---

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

⚠️ Paket C yang belum siap musl harus menulis arsitektur eksplisit. Memakai `*`
membuat CI mencoba build musl dan gagal.

Tool shell/script murni (`zvc`, `letx`, `tpkg`) sebaiknya pakai `archs=noarch`:
satu build menghasilkan `.noarch.xbps` yang diupload ke semua tag yang didukung.

Verifikasi ekspansi `archs` tanpa bootstrap apa pun. `template.sh` hanya berisi
definisi fungsi dan tidak punya mode `--selftest`, jadi panggil fungsinya langsung:

```sh
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; expand_archs "x86_64* ~x86_64-musl"'
# → x86_64
```

---

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

- `version` **tanpa** revisi. Benar: `version=1.1.0 revision=1`.
  Salah: `version=1.1.0_1`.
- Naikkan `revision` untuk perubahan template saja; reset ke `1` saat versi
  upstream baru.
- `distributor` menandai siapa yang mengemas (ditambahkan Let-X untuk template
  pihak lain).
- Nama paket harus tetap di dalam `[A-Za-z0-9._+-]`. Lihat §9.

---

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

Menu arsitektur interaktif:

```
[+] Architecture
    [1] x86_64         [6] armv6l-musl
    [2] x86_64-musl    [7] armv7l
    [3] aarch64        [8] armv7l-musl
    [4] aarch64-musl   [9] i686
    [5] armv6l         [0] All
[?] Choose (pisah spasi, contoh: 1 3 6) [default: host]:
```

Arsitektur yang diminta diiriskan dengan `archs` template; irisannya ditampilkan
sebelum build dimulai.

Pemilihan flag (`src/env.sh: flags_for`):

| Situasi | Flag |
|---|---|
| target == host (arch + libc) | tanpa flag (native) |
| `i686` di x86_64, libc sama | `-A i686` (masterdir 32-bit native) |
| libc berbeda | `-A <hostbase>-<targetlibc>` |
| base arch berbeda | `-a <targetbase>` |

Paket `noarch` dibuild sekali, pada target pertama yang dipilih.

### Upload

```sh
vdev/tools.sh -u tpkg
```

1. Cek akses write via `gh api repos/T4n-Labs/repo-t4nos --jq .permissions.push`.
2. **Punya akses write:** mencocokkan file `.xbps` di
   `void-packages/hostdir/binpkgs` dengan `pkgname` + subpackage dan
   `version_revision` template, mengarahkannya ke tag (`noarch` → semua tag yang
   didukung), upload dengan `--clobber`, lalu men-trigger `process.yml` **sekali**
   dengan daftar tag yang tersentuh.
3. **Tanpa akses write:** upload dan trigger dilewati, dengan pemberitahuan bahwa
   maintainer akan build dan upload setelah PR di-merge.
4. Dua-duanya tetap menawarkan `git push`, dan menawarkan buka PR kalau `origin`
   adalah fork.

Biner yang diupload **belum bertanda tangan**. CI yang menandatangani. Ada window
singkat di mana asset sudah ada tapi `.sig2`-nya belum — jangan umumkan rilis
sebelum workflow hijau.

File `.sig2` lokal (dari kunci Anda sendiri) sengaja **tidak** diupload: tanda
tangan dengan kunci berbeda akan gagal verifikasi di client. CI satu-satunya
penanda tangan.

---

## 7. Pipeline CI/CD

### Trigger

- `workflow_dispatch` dengan input `tags` (default `all`) — dipanggil
  `vdev/tools.sh -u` sekali setelah semua upload selesai.
- `schedule` (cron) sebagai cadangan; no-op kalau tidak ada yang perlu diproses.

Trigger push sengaja tidak ada: upload asset release tidak memicu event apa pun,
dan event yang dibuat `GITHUB_TOKEN` tidak memicu workflow lain.

`concurrency: { group: repo-process, cancel-in-progress: false }` membuat run
antri, bukan saling menimpa.

### Job

| # | Job | Secret | Baca template | Tugas |
|---|---|---|---|---|
| 1 | `prepare` | tidak | tidak | resolve tag, buat yang belum ada (idempotent) |
| 2 | `process` ×9 | **ya** | **tidak** | index, sign, prune per tag |
| 3 | `json` ×9 | tidak | ya | repodata + template → `packages.json` |
| 4 | `commit` | tidak | tidak | commit `json/**` sekali, hanya kalau berubah |

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
    "url": "https://github.com/T4n-Labs/repo-t4nos/releases/download/x86_64/tpkg-1.1.0_1.noarch.xbps"
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
| `url` | `<BASE>/<tag>/<filename>`; `BASE` di `gen-json.py` (sekarang URL release GitHub, lihat §12) |
| `description` / `desc` | `short_desc` (`desc` alias untuk frontend sekarang) |
| `distributor` | hanya dari template |
| `status` | `ready` (biner ada) atau `recipe` (template saja; `filename`/`size`/`url` bernilai `null`) |

Subpackage (`-dbg`, `-doc`, `-devel`) tidak punya template sendiri, jadi `archs`
mereka fallback ke `[tag]`.

---

## 8. Kunci

```sh
ssh-keygen -t rsa -b 4096 -m PEM -f key.pem -N ""
cp key.pem.pub keys/key.pem.pub
gh secret set SIGN_KEY --env signing -R T4n-Labs/repo-t4nos < key.pem
```

- Backup `key.pem` offline. File itu ada di `.gitignore`. **Jangan pernah commit.**
- Environment `signing` dibatasi ke branch `main`, jadi workflow di branch lain
  dan fork tidak bisa membaca secret-nya.
- Hanya `keys/key.pem.pub` yang publik. `ssh-keygen` menulis file ini dalam format
  OpenSSH (`ssh-rsa AAAA…`). Fingerprint yang diumumkan ke user adalah fingerprint
  **XBPS**: ambil dari prompt impor kunci pertama (lihat §12), bukan dari `ssh-keygen -l`.
- Umumkan fingerprint (README + website) supaya user bisa memverifikasi impor
  pertama.

**Rotasi:** generate kunci baru → update secret → dispatch `process.yml` dengan
`tags=all` (semua paket di-sign ulang) → umumkan fingerprint baru → user menghapus
`.plist` lama dan sync ulang.

---

## 9. Karakter Nama File — Terverifikasi

Diuji pada release sementara:

| Diupload | Tersimpan | URL download |
|---|---|---|
| `libfake++-1.0_1.x86_64.xbps` | utuh | raw `+` **200**, `%2B` **200** |
| `libsigc++-2.0_1.x86_64.xbps` | utuh | — |
| `gtk+3-3.24_1.x86_64.xbps` | utuh | — |
| `foo~bar-1.0_1.x86_64.xbps` | `foo.bar-1.0_1.x86_64.xbps` | nama rusak |

**`+` aman**; paket seperti `libstdc++`, `gtk+3`, `libsigc++` boleh dipaketkan di
sini. **`~` di-rename menjadi `.`.**

Bagian berbahayanya: hasil rename `foo.bar-...` justru **lolos** allowlist
karakter, karena `.` legal — sementara `props.plist` di dalam paket tetap menulis
`foo~bar-1.0_1`. Repodata lalu menunjuk file yang tidak ada dan client dapat 404.

Itu sebabnya pagar sebenarnya adalah **verifikasi nama**, bukan blocklist
karakter: setelah download, baca `props.plist` dan wajibkan nama asset sama persis
dengan `<pkgver>.<architecture>.xbps`. Parsing plist adalah parsing data, bukan
eksekusi kode, jadi tetap aman di dalam job pemegang secret.

Karakter di luar `[A-Za-z0-9._+-]` ditolak di awal. `:`, spasi, dan tanda kurung
belum diuji — jangan diasumsikan aman.

Worker `repo.t4nlabs.web.id` memakai allowlist yang sama (`[A-Za-z0-9._+-]`): nama di
luar itu dijawab 404 walaupun file-nya ada di release.

---

## 10. Checklist Rilis

- [ ] Template benar: `archs`, `checksum`, konvensi `version` / `revision`
- [ ] Kalau menyentuh parser: jalankan `expand_archs` pada contoh di §4, hasil harus sama dengan tabel
- [ ] Build lokal di host plus minimal satu target cross
- [ ] `vdev/tools.sh -u <pkg>` → workflow ter-trigger
- [ ] Semua job CI hijau (`gh run watch -R T4n-Labs/repo-t4nos`)
- [ ] Paket tampil `ready` di website untuk arsitektur yang diharapkan
- [ ] `xbps-install -S && xbps-install <pkg>` sukses di sistem uji bersih
- [ ] Versi lama hilang dari release tag (`gh release view <tag>`)

---

## 11. Troubleshooting

| Gejala | Penyebab / perbaikan |
|---|---|
| Job musl gagal | paket belum siap musl → tulis archs eksplisit, atau perbaiki build |
| Build ARM di-skip | `nocross=` di template — wajar, atau adaptasi untuk cross |
| `props.plist` tidak terbaca | asset bukan paket xbps valid (mis. dummy tes) |
| Nama asset ≠ isi paket | GitHub me-rename karakter; ganti nama paket |
| Tag kosong / sync 404 | belum ada paket masuk tag itu; build tool `noarch` dulu |
| 404 lewat `repo.t4nlabs.web.id`, tapi URL release normal | domain/Worker belum aktif atau DNS salah → pakai URL release langsung, hubungi Founder |
| Install gagal tepat setelah `-u` | biner belum di-sign; tunggu workflow selesai |
| `commit json` warning 3× | branch protection menolak push bot; izinkan Founder dan `github-actions` bypass, atau hapus syarat PR |
| Website basi | indeks belum dibuat ulang; cek job `json` dan `commit` |
| Domain terlihat bermasalah | jalankan `bash vdev/DNS-check.sh` dan cocokkan dengan §13 |

---

## 12. Status Implementasi

Per 22 November 2026. Sudah dicek terhadap kode: `process.yml` valid dan berisi
empat job (`prepare`, `process`, `json`, `commit`); tidak ada job `policy` atau
`deploy`; semua skrip lolos `bash -n`. Yang tersisa menunggu aktivasi domain:

| Item | Target | Keadaan sekarang |
|---|---|---|
| Base URL di `setup.sh` | `https://repo.t4nlabs.web.id` | `BASE` masih URL release GitHub (sementara) |
| Field `url` di `packages.json` | domain | `BASE` di `gen-json.py` masih URL release GitHub |
| Fingerprint kunci | diumumkan di README + website | `FINGERPRINT` di `setup.sh` masih placeholder; diisi setelah sinkronisasi pertama |
| Worker + domain | `repo.t4nlabs.web.id/<tag>` aktif | **Aktif**; lulus `DNS-check.sh` 14/14 (22 Nov 2026) |
| Verifikasi end-to-end | `xbps-install -S` lewat domain, termasuk impor kunci pertama | domain, TLS, dan proxy sudah terverifikasi; `xbps-install -S` menunggu paket pertama |

Urutan: domain aktif → `curl -I` ke domain → `xbps-install -S` di sistem bersih
(catat fingerprint dari prompt) → isi `FINGERPRINT` → ganti `BASE` di `setup.sh`
dan `gen-json.py` → umumkan.

## 13. Verifikasi Domain `repo.t4nlabs.web.id`

Skrip `vdev/DNS-check.sh` menguji domain **tanpa biner XBPS**. Skrip hanya
membaca, jadi aman dijalankan siapa pun yang punya `curl` (dan `dig` untuk bagian
DNS).

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
| Proxy | `HEAD`/`GET` → 200, `Range` → 206, dan isi lewat domain sama dengan isi langsung dari GitHub (hanya dengan `PROBE`) |

Uji proxy dengan file nyata (butuh akses write, jadi Founder yang menjalankan):

```sh
echo ping-ok > ping.txt
gh release upload x86_64-musl ping.txt -R T4n-Labs/repo-t4nos
PROBE=ping.txt bash vdev/DNS-check.sh
gh release delete-asset x86_64-musl ping.txt -R T4n-Labs/repo-t4nos -y
```

CI mengabaikan asset selain `.xbps`, jadi `ping.txt` tidak mengganggu, tetapi
tetap hapus setelah selesai. Jika release belum ada, buat dulu dengan
`gh release create <tag> --prerelease` (judul dan notes seperti di `process.yml`).

`<tag>-repodata` berstatus 404 selama belum ada paket yang diproses; itu normal,
bukan kegagalan domain.

Hasil acuan (22 November 2026): 14 lulus, 0 gagal.

---

**T4n Labs ◉ Gh0sT4n** — *Memberdayakan ekosistem T4n Labs.*