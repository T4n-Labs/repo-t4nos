# process.md — Riwayat Proses Pembuatan `repo-t4nos`

Untuk: asisten AI (Qwen) dan developer yang baru masuk. Berkas ini menceritakan
**bagaimana sistem dibangun**, keputusan beserta alasannya, masalah yang
ditemukan, dan keadaan terakhir. Aturan kerja dan invarian ada di `PROMPT.md`.
Pakai keduanya: baca `PROMPT.md` dulu, lalu berkas ini.

Terakhir diperbarui: 23 November 2026 (kejadian di bawah berlangsung 22 November
2026). Kalau dokumen ini berbeda dari kode di repositori, **kode yang benar**.
Hal yang tidak pernah dikonfirmasi ditandai "tidak dikonfirmasi"; jangan
menganggapnya sudah selesai.

---

## 1. Tujuan

Menyajikan paket biner XBPS bertanda tangan untuk T4n OS dan Void Linux (glibc
dan musl, 9 arsitektur) dari **satu repositori GitHub** (`T4n-Labs/repo-t4nos`),
dengan URL repo untuk client XBPS:

```
https://repo.t4nlabs.web.id/<arch>        # contoh: .../x86_64-musl
```

Biner disimpan sebagai asset **GitHub Releases** (satu release per tag, nama tag
= keluaran `xbps-uhelper arch`), bukan di git.

## 2. Titik awal

Bahan yang sudah ada sebelum proses ini: `setup.sh`, `vdev/tools.sh` dan
`vdev/src/{common,template,env,build,upload,git}.sh`,
`.github/workflows/{process.yml,process-tag.sh,gen-json.py}`, `CODEOWNERS`,
`plan.md`, dan `README.md` lama (isinya hanya "repo-glibc"). Struktur
`json/<tag>/`, `keys/key.pem.pub`, `pkg-template/` (burpsuite, calamares, letx,
metasploit, radare2, tpkg, zvc), dan `vdocs/{EN,ID}` juga sudah ada.

Yang belum ada: domain `repo.t4nlabs.web.id` yang berfungsi, paket XBPS pertama,
fingerprint kunci yang dipublikasikan.

## 3. Desain (hasil membaca kode)

```
developer (vdev/tools.sh -b / -u)
   │  build lokal dengan xbps-src, upload .xbps ke release per tag
   ▼
GitHub Releases  ──▶  process.yml (workflow_dispatch + cron 6 jam)
                        prepare → process ×9 → json ×9 → commit
                        process-tag.sh: verifikasi nama via props.plist,
                        xbps-rindex index + sign, upload repodata + .sig2,
                        prune TERAKHIR
   ▲
   │  proxy
Cloudflare Worker t4n-repo  ◀──  client xbps: https://repo.t4nlabs.web.id/<tag>
```

Prinsip yang membentuk desain (rinciannya di `PROMPT.md` §2):
- Biner tidak pernah masuk git; kunci signing hanya ada di job CI `process`
  (Environment `signing`, dibatasi ke `main`).
- Template berasal dari pihak lain, jadi tidak pernah di-`source`; di-parse
  dengan `grep`/`sed` (bash) atau regex (Python). Job pemegang secret tidak
  membaca template sama sekali.
- Pemeriksaan keamanan utama adalah mencocokkan nama asset dengan isi paket
  (`props.plist`), bukan blocklist karakter.
- GitHub Pages tidak bisa jadi endpoint repo (tidak bisa meneruskan ke asset
  release), jadi dipakai **Cloudflare Worker sebagai reverse proxy**.

---

## 4. Kronologi proses

### Fase 1 — Membaca kode dan menyusun rencana setup

Seluruh file di atas dibaca, lalu disusun urutan setup dari nol:
1. Push repo ke GitHub (`.github/workflows/` harus ada di `main` supaya
   `workflow_dispatch` jalan; `CODEOWNERS` ditaruh di `.github/CODEOWNERS`).
2. Buat key signing RSA tanpa passphrase (dipakai CI), simpan hanya
   `keys/key.pem.pub` di git.
3. Buat Environment `signing` (dibatasi ke `main`), isi secret `SIGN_KEY`.
4. Setelan repo: Workflow permissions Read and write; ruleset `main` dengan
   review Code Owners.
5. Buat tag pertama dan build/upload satu paket (`zvc`) lewat `vdev/tools.sh`,
   lalu jalankan `process.yml`.
6. Pasang Worker untuk `repo.t4nlabs.web.id`.
7. Uji `xbps-install -S` di sistem bersih, catat fingerprint dari prompt impor kunci.
8. Isi `FINGERPRINT` dan ganti `BASE` di `setup.sh` ke domain.

Temuan awal: (a) `plan.md` mengarahkan CNAME GitHub Pages `repo-site` ke
`repo.t4nlabs.web.id`, bentrok dengan Worker; nama itu dipindah ke
`repo-web.t4nlabs.web.id` (sesuai `SITE` di `setup.sh`); (b) tag tanpa paket
tidak punya `<tag>-repodata`, jadi pengguna arsitektur itu mendapat 404.

### Fase 2 — Cloudflare Worker `t4n-repo`

Dibuat lewat dashboard ("Start with Hello World!", nama `t4n-repo`, tanpa
Cloudflare Access), kodenya ditempel ke `worker.js`. Perilaku akhir:

| Request | Hasil |
|---|---|
| `/` | redirect 302 ke `https://repo-web.t4nlabs.web.id/` |
| `/setup.sh` | disajikan dari `raw.githubusercontent.com/T4n-Labs/repo-t4nos/main/setup.sh` (ditambahkan di Fase 7) |
| `/<tag>` | redirect 302 ke `github.com/T4n-Labs/repo-t4nos/releases/tag/<tag>` |
| `/<tag>/<file>` | diproxy ke `releases/download/<tag>/<file>` (GET/HEAD; header `range`, `if-modified-since`, `if-none-match`, `user-agent` diteruskan) |
| lainnya | 404 (tag di luar 9 tag, atau nama file di luar `[A-Za-z0-9._+-]`) |

Dua redirect itu hanya kenyamanan untuk manusia di browser; `xbps` hanya memakai
`/<tag>/<file>`. Sempat ada salah paham ("kok mengarah ke web?"): redirect hanya
terkena bila path persis `/`. Alamat `workers.dev` dipakai untuk uji awal (302
terbukti benar), lalu dimatikan.

### Fase 3 — Masalah DNS dan pemindahan zona

Setelah Worker benar, `repo.t4nlabs.web.id` tetap menampilkan 404 "There isn't a
GitHub Pages site here". `dig` menunjukkan dua penyebab:
- record `repo` masih CNAME ke `t4n-labs.github.io`;
- nameserver `t4nlabs.web.id` masih di Citrahost, sehingga Worker tidak bisa
  melayani domain itu (custom domain Worker hanya untuk zona di Cloudflare).

Penyelesaian: zona dipindah ke Cloudflare (plan Free). Hal-hal yang menjebak:
- halaman "Add a site" di dashboard sempat macet; tersambung lewat jalur
  "Connect a domain" setelah dicoba ulang;
- sempat tak sengaja terdaftar zona salah ketik `t4blabs.web.id` (terlihat dari
  screenshot), lalu dibuat ulang dengan nama benar;
- scan otomatis hanya mengimpor 4 record A root, `www`, dan TXT; record
  `repo-web`, `t4nos`, `t4nos-docs`, `vur` ditambahkan manual setelah
  membandingkan dengan panel DNS Citrahost, semuanya **DNS only**; record `repo`
  lama sengaja tidak diimpor;
- nameserver di Citrahost diganti ke pasangan `jarred`/`monika` `.ns.cloudflare.com`;
- custom domain `repo.t4nlabs.web.id` dipasang di Worker.

### Fase 4 — Verifikasi domain tanpa biner

Karena belum ada paket XBPS, diuji lapisan domain dan Worker dengan skrip
`check-domain.sh` (di repo bernama `vdev/DNS-check.sh`). Logikanya lebih dulu
diuji dengan mock lokal (sehat: 12 lulus; rusak: 6 gagal terdeteksi). Hasil
nyata pada 22 November 2026: **14 lulus, 0 gagal**, mencakup NS Cloudflare,
`repo` tidak ke GitHub Pages, semua perilaku Worker di tabel atas, dan proxy ke
release (HEAD/GET 200, Range 206, isi identik dengan langsung dari GitHub)
memakai file uji `ping.txt` yang lalu dihapus. `x86_64-musl-repodata` masih 404,
dan itu normal sebelum ada paket. Error `422 tag_name already exists` saat
`gh release create` tidak masalah: release `x86_64-musl` memang sudah ada.

### Fase 5 — Audit dan perbaikan dokumentasi

`DEV.md`/`USER.md` (ID dan EN) dan `README.md` dicocokkan dengan kode yang
diupload. Yang salah dan diperbaiki:
- `DEV` §12 menyebut job `policy`/`deploy` dan `process.yml` rusak; kode asli
  valid dengan 4 job (`prepare`, `process`, `json`, `commit`). Ditulis ulang.
- `template.sh --selftest` tidak ada; diganti perintah `expand_archs` yang sudah
  diuji (7 contoh `archs` cocok dengan tabel).
- URL `setup.sh` di USER menunjuk `repo.t4nlabs.web.id/setup.sh`, yang dijawab 404
  oleh Worker; disamakan ke
  `https://raw.githubusercontent.com/T4n-Labs/repo-t4nos/main/setup.sh`
  (komentar header `setup.sh` ikut disamakan).
- "Lapisan redirect" dikoreksi menjadi reverse proxy; contoh `url` di
  `packages.json` disesuaikan dengan kode (masih URL release GitHub).
- `README.md` ditulis ulang (ID dan EN), termasuk blok fingerprint placeholder.
- Contoh teks prompt impor kunci di USER diganti `...` plus catatan, karena
  teks persis XBPS tidak diverifikasi.

File hasil audit diserahkan; apakah semuanya sudah diterapkan di repo
**tidak dikonfirmasi** (tambahan `DEV` §13 tentang verifikasi domain ditempel
manual oleh pemilik repo).

### Fase 6 — Dokumen konteks untuk developer

`PROMPT.md` dibuat sebagai prompt konteks (peran, invarian, peta kode, jebakan,
resep tugas, larangan). Berkas ini (`process.md`) melengkapinya dengan sejarah
dan keputusan.

### Fase 7 — Route `/setup.sh` dan temuan 23 November 2026

Worker diberi route `/setup.sh` yang menyajikan `setup.sh` terbaru dari `main`
(sumber URL tetap, tanpa input user; `cache-control` 300 dtk saat sukses,
sebaiknya `no-store` saat error). Dengan itu one-liner resmi menjadi
`curl -fsSL https://repo.t4nlabs.web.id/setup.sh | sudo sh` (dijalankan dengan
`sh`, karena skrip POSIX). Hasil uji: `HEAD` 200 `text/plain`, isi diawali
`#!/bin/sh`, dan `DNS-check.sh` tanpa `PROBE` 10 lulus, 0 gagal (empat uji proxy
berkas uji dilewati karena `PROBE` kosong, bukan regresi). Perintah `cmp` gagal
hanya karena dijalankan di folder tanpa `setup.sh`.

Temuan: `x86_64-musl-repodata` kini HTTP 200 (sebelumnya 404). Artinya CI
`process` sudah menghasilkan index untuk tag itu. Karena hanya `process-tag.sh`
yang membuat repodata dan ia mewajibkan `SIGN_KEY`, key dan secret hampir pasti
sudah terpasang (tidak dikonfirmasi langsung). Docs (USER, README, header
`setup.sh`) diperbarui ke URL domain.

### Fase 8 — `setup.sh` dua perintah dan tes end-to-end (23 November 2026)

`setup.sh` diperluas: `setup` (default; deteksi arsitektur dan libc otomatis) dan
`update` (`xbps-install -Su`, dengan pengecekan repo terpasang dan stdin dialihkan
agar aman lewat pipe). Variabel `T4N_BASE` menimpa base URL. Diuji dengan mock
`xbps` (setup, update, pipe, penolakan arsitektur, bukan root).

Tes nyata di T4n OS x86_64 glibc: one-liner lewat pipe berjalan dan menampilkan
prompt impor kunci (`RSA signed by "T4n Labs"`, fingerprint `63:35:0c:65:0d:a5:f1:87:52:7e:c5:e9:13:3a:d6:2a`); `tpkg 1.1.0_1`
terpasang dengan tanda tangan RSA terverifikasi. Config sempat memakai URL release
(karena `BASE` default belum diganti), lalu diganti ke domain: repodata lewat domain
berhasil. Tes pertama lewat domain **tidak** membuktikan unduhan paket karena
log menunjukkan `0 downloaded` (paket diambil dari cache XBPS); setelah `tpkg`
dihapus beserta cache-nya, `.sig2` dan `.xbps` terunduh lewat domain (`1 downloaded`)
dan tanda tangan lulus. Default `BASE` lalu dialihkan ke domain, dan fingerprint
diisi di `setup.sh`, README, dan USER.

---

## 5. Keputusan dan alasannya

| Keputusan | Alasan |
|---|---|
| Satu repo, 9 release tag bernama sama dengan `xbps-uhelper arch` | satu `setup.sh` melayani semua sistem tanpa pemetaan manual |
| Biner di Releases, bukan git | ukuran repo; `--clobber` dan prune dikelola CI |
| Signing hanya di CI, Environment `signing` ke `main` | PR dari fork tidak boleh menyentuh kunci |
| Template di-parse, tidak di-source | template pihak lain = kode tak tepercaya |
| Worker sebagai reverse proxy, bukan redirect | mempertahankan URL `repo.t4nlabs.web.id/<tag>` di config user dan memegang kendali atas asal unduhan |
| Website di `repo-web.t4nlabs.web.id` | membebaskan `repo.t4nlabs.web.id` untuk Worker |
| Record GitHub Pages **DNS only** | GitHub harus bisa menerbitkan sertifikat HTTPS sendiri |
| Worker mempertahankan redirect `/` dan `/<tag>` | memudahkan orang yang membuka domain di browser; tidak mengganggu `xbps` |
| `setup.sh` disajikan Worker di `https://repo.t4nlabs.web.id/setup.sh` | satu domain untuk semua; sumber tetap `main` di raw GitHub, tanpa input user |
| `BASE` di `setup.sh`/`gen-json.py` dialihkan ke `https://repo.t4nlabs.web.id` setelah tes `xbps-install -S` lewat domain lulus (23 Nov) | client asli terbukti jalan lewat domain; cadangan: `T4N_BASE=<URL release>` |
| Allowlist nama file `[A-Za-z0-9._+-]` identik di `common.sh`, `process-tag.sh`, Worker | `+` terbukti aman di GitHub Releases, `~` tidak |

## 6. Masalah dan jebakan yang ditemukan

| Temuan | Status |
|---|---|
| Record `repo` lama ke GitHub Pages + NS masih Citrahost | **selesai** (zona dipindah, domain aktif) |
| Zona salah ketik `t4blabs.web.id` di Cloudflare | perlu dipastikan sudah dihapus (**tidak dikonfirmasi**) |
| Tag tanpa paket → tidak ada repodata → `xbps-install -S` 404 untuk arsitektur itu | terbuka; pastikan tiap tag yang diumumkan punya minimal satu paket |
| Parser bash menganggap `archs=all` = semua tag, Python (`gen-json.py`) tidak (hasil kosong) | terbuka; hindari `archs=all` atau samakan Python |
| Kedua parser membuang `#...` dari nilai field (`homepage` dengan `#` terpotong) | terbuka |
| `flags_for` (env.sh): host musl + target glibc menghasilkan `-A <hostbase>-glibc`, kemungkinan tidak valid | **belum diverifikasi** |
| Daftar tag diduplikasi di enam tempat (`common.sh`, `gen-json.py`, `process.yml`, `build.sh` menu, `setup.sh`, Worker) | catatan; ubah semuanya bersamaan |
| `ssh-keygen` menulis `key.pem.pub` dalam format OpenSSH; fingerprint yang diumumkan harus dari prompt XBPS | catatan; sudah di docs |
| `schedule` tiap 6 jam menyalakan job `process` walau tidak ada pekerjaan | catatan |
| `process-tag.sh` mengunduh semua paket yang di-keep tiap run | backlog |

## 7. Keadaan terakhir

| Item | Status |
|---|---|
| Domain `repo.t4nlabs.web.id` aktif, lulus `DNS-check.sh` 14/14 | **terkonfirmasi** (22 Nov 2026) |
| Worker `t4n-repo` aktif, `workers.dev` dimatikan | terkonfirmasi |
| Release `x86_64-musl` ada | terkonfirmasi |
| `/setup.sh` lewat Worker | terkonfirmasi (HTTP 200, isi `#!/bin/sh`, 23 Nov 2026) |
| Paket XBPS `x86_64` | `tpkg 1.1.0_1` terpasang via URL release dan via domain (23 Nov 2026); `x86_64-musl-repodata` HTTP 200; tag lain belum dicek |
| Key signing, secret `SIGN_KEY`, Environment `signing` | kemungkinan besar sudah (repodata hanya dibuat `process-tag.sh`, yang mewajibkan `SIGN_KEY`); tidak dikonfirmasi langsung |
| Ruleset `main` | tidak dikonfirmasi |
| `FINGERPRINT` di `setup.sh`/README/USER | `63:35:0c:65:0d:a5:f1:87:52:7e:c5:e9:13:3a:d6:2a` (dari prompt XBPS, 23 Nov 2026); website belum; perbandingan modulus dengan `keys/key.pem.pub` belum dilaporkan |
| `BASE` di `setup.sh` dan `gen-json.py` | berkas hasil edit (domain) diserahkan; penerapan di repo tidak dikonfirmasi |
| Tes `xbps-install -S` end-to-end lewat domain | **terkonfirmasi** (x86_64 glibc, 23 Nov 2026): repodata, `.sig2`, dan `.xbps` diunduh via domain, RSA terverifikasi |
| `worker/index.js` di repo, `/worker/` dan `/vdocs/` di CODEOWNERS | tidak dikonfirmasi |
| `CONTRIBUTING.md` / `CONTRIBUTING.ID.md`, LICENSE | belum ada / belum diputuskan |

## 8. Langkah berikutnya (berurutan)

1. Pastikan ruleset `main` terpasang dan hapus zona salah `t4blabs.web.id`
   bila masih ada (key dan secret kemungkinan sudah ada, lihat §7).
2. Cek isi release `x86_64-musl` (`.xbps` dan `.xbps.sig2` ada) dan pastikan
   setiap tag yang diumumkan punya minimal satu paket.
3. **Selesai** (23 Nov 2026): tes end-to-end lewat domain lulus (lihat Fase 8).
4. Isi fingerprint di website; bandingkan modulus kunci yang diimpor XBPS dengan
   `keys/key.pem.pub`.
5. Terapkan berkas hasil edit (`setup.sh`, `gen-json.py`, README, USER) ke repo,
   lalu jalankan `process.yml` supaya `packages.json` memakai URL domain.
6. Tambah `worker/index.js`, `/worker/` dan `/vdocs/` ke CODEOWNERS, tulis
   `CONTRIBUTING*`, putuskan LICENSE.
7. Selesaikan jebakan di §6 (terutama `archs=all` dan tag kosong).

## 9. Catatan untuk AI pembaca

- Baca `PROMPT.md` dulu. Berkas ini hanya konteks sejarah dan keputusan.
- Jangan menganggap sesuatu sudah selesai kalau di sini tertulis "tidak
  dikonfirmasi" atau "belum"; tanyakan atau minta bukti keluaran perintah.
- Jangan mengubah invarian di `PROMPT.md` §2 tanpa persetujuan eksplisit pemilik repo.
- Domain dan akun Cloudflare/Citrahost dikelola pemilik repo. Jangan meminta
  token atau kredensial, dan jangan menyuruh menempelkannya di chat.
- Kerja bertahap satu file per langkah, tampilkan diff, laporkan hasil
  pemeriksaan apa adanya, dan tandai apa pun yang belum diverifikasi.