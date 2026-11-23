# PROMPT.md — Konteks Pengembangan & Maintenance `repo-t4nos`

Berkas ini adalah **prompt konteks**. Tempel seluruh isinya di awal sesi dengan
asisten AI (atau baca sendiri sebelum mengubah kode), lalu tulis tugasnya di
bawah baris `TUGAS:` di bagian paling akhir.

Isinya merangkum arsitektur, aturan yang tidak boleh dilanggar, peta kode, dan
pekerjaan yang belum selesai, per **22 November 2026**. Kalau kode berubah,
perbarui berkas ini bersama `vdocs/*/DEV.md` §12.

**Sumber kebenaran adalah kode.** Kalau dokumen dan kode berbeda, kode yang
menang, lalu dokumennya diperbaiki. Jangan mengarang: tandai apa pun yang belum
diverifikasi sebagai "belum diverifikasi".

---

## 0. Peran dan cara kerja

Kamu membantu mengembangkan dan merawat `repo-t4nos`. Aturan kerja:

1. Baca file yang relevan dulu. Jangan mengubah kode dari ingatan.
2. Kerja bertahap, **satu file per langkah**: tunjukkan diff, jelaskan
   alasannya, lalu tunggu konfirmasi sebelum ke file berikutnya (kecuali diminta
   sekaligus).
3. Ubah seminimal mungkin. Jangan merapikan kode yang tidak terkait tugas.
4. Sebelum menyentuh apa pun di §2 (Invarian), berhenti dan tanyakan.
5. Setelah mengubah, jalankan pemeriksaan di §10 dan laporkan hasilnya apa
   adanya, termasuk yang gagal atau tidak bisa dijalankan.
6. Kalau perilaku berubah, perbarui dokumen terkait (ID dan EN bersamaan).
7. Balas dalam bahasa yang dipakai penanya. Pesan log dan komentar di kode
   memakai Bahasa Indonesia, seperti kode yang ada.

---

## 1. Proyek

`repo-t4nos` adalah satu repositori GitHub (organisasi `T4n-Labs`) yang
menyajikan **paket biner XBPS bertanda tangan** untuk T4n OS dan Void Linux,
glibc dan musl. Biner ada di **GitHub Releases** (satu release per tag), bukan
di git.

| Item | Nilai |
|---|---|
| Repo paket | `https://github.com/T4n-Labs/repo-t4nos` |
| Repo website | `T4n-Labs/repo-site` (terpisah; kodenya tidak ada di repo ini) |
| Website | `https://repo-web.t4nlabs.web.id/` |
| Endpoint XBPS (target) | `https://repo.t4nlabs.web.id/<tag>` (proxy ke release) |
| Asset | `https://github.com/T4n-Labs/repo-t4nos/releases/download/<tag>/<file>` |

9 tag, sama dengan keluaran `xbps-uhelper arch`: `x86_64`, `x86_64-musl`,
`aarch64`, `aarch64-musl`, `armv6l`, `armv6l-musl`, `armv7l`, `armv7l-musl`,
`i686`. `i686-musl` **tidak** disediakan.

Peran manusia:

- **Founder**: satu-satunya pemegang akses write, private key signing, serta
  akun Cloudflare dan Citrahost.
- **Core Team**: hanya akses `Read`. Kontribusi lewat **fork + Pull Request**;
  PR dari fork tidak mendapat secret.

---

## 2. Invarian (jangan dilanggar tanpa persetujuan eksplisit Founder)

1. **Biner tidak masuk git.** `.xbps`, `.xbps.sig2`, dan `<tag>-repodata` hanya
   ada di Releases. Git hanya berisi template, skrip, docs, `json/`, dan
   `keys/key.pem.pub`.
2. **Signing hanya di CI**, di job `process`, memakai secret `SIGN_KEY` dari
   Environment `signing` (dibatasi ke `main`). Tidak boleh ada `xbps-rindex`
   atau akses kunci di `vdev/`. Jangan mencetak, menyimpan, atau meneruskan
   `SIGN_KEY`.
3. **Template tidak pernah di-`source` atau dieksekusi.** Template berasal dari
   pihak lain. Parse dengan `grep`/`sed` (bash) atau regex (Python). Job
   pemegang secret (`process`) **tidak boleh membaca template sama sekali**;
   itu alasan ia memakai `sparse-checkout: .github/workflows`.
4. **Rencana dulu, hapus terakhir.** Di `process-tag.sh`, repodata dan `.sig2`
   baru diupload **sebelum** asset lama dihapus.
5. **Verifikasi nama asset** terhadap `props.plist` di dalam paket
   (`<pkgver>.<architecture>.xbps`). Itu pagar utama, bukan blocklist karakter
   (GitHub me-rename `~` menjadi `.`).
6. **Allowlist nama file `[A-Za-z0-9._+-]`** ada di tiga tempat dan harus tetap
   identik: `common.sh: name_safe`, `process-tag.sh`, dan Worker.
7. **Versi dibandingkan dengan `xbps-uhelper getpkgname` / `cmpver`, bukan
   regex**, dengan kalibrasi dua probe. Kalau hasilnya tidak bisa dibedakan,
   pruning dibatalkan.
8. **Jangan edit Release secara manual** (CI me-reconcile penuh) dan **jangan
   upload `.sig2` lokal** (kunci berbeda gagal verifikasi di client).
9. **Workflow:** jangan tambahkan trigger `pull_request_target` atau `push`,
   jangan beri secret ke job yang membaca template, jangan longgarkan
   `permissions` atau `environment`. `.github/workflows/`, `setup.sh`, dan
   `keys/` dilindungi CODEOWNERS.
10. **Modul `vdev/src/*.sh` hanya mendefinisikan fungsi**, tanpa side effect
    saat di-source, supaya CI dan Let-X bisa memakainya ulang.

---

## 3. Peta kode

| File | Isi |
|---|---|
| `vdev/tools.sh` | dispatcher bash tipis (`-s`, `-sy`, `-b`, `-u`, `-h`); `set -euo pipefail`, men-source semua modul |
| `vdev/src/common.sh` | konstanta (`REPO_DIR`, `VP`, `TPL`, `GH_REPO`, `ALL`, `HOST_ARCH`), warna, `info/ok/warn/err/die`, `need`, `name_safe`, `in_list` |
| `vdev/src/template.sh` | parser: `tpl_field`, `tpl_subpkgs`, `expand_archs`, `tpl_supported`, `tpl_is_noarch` |
| `vdev/src/env.sh` | `cmd_setup` (clone void-packages + binary-bootstrap), `cmd_sync`, `tpl_stage`, `flags_for` |
| `vdev/src/build.sh` | `menu_arch`, `cmd_build` (iriskan arsitektur dengan `archs`, panggil `xbps-src`) |
| `vdev/src/upload.sh` | `route_tags`, `cmd_upload` (cek akses write, upload `--clobber`, trigger `process.yml` sekali) |
| `vdev/src/git.sh` | `git_offer` (tawarkan push; tawarkan PR bila `origin` bukan `T4n-Labs/repo-t4nos`) |
| `.github/workflows/process.yml` | satu-satunya workflow: `prepare` → `process` ×9 → `json` ×9 → `commit` |
| `.github/workflows/process-tag.sh` | per tag: inventory → rencana → unduh → verifikasi → index → sign → upload → prune (**memegang secret**) |
| `.github/workflows/gen-json.py` | `index.plist` + field template → `json/<tag>/packages.json` (tanpa secret) |
| `setup.sh` | skrip user, **POSIX sh**: `setup` (default; deteksi arsitektur+libc, tulis `/etc/xbps.d/10-t4nos.conf`, `xbps-install -S`) dan `update` (`xbps-install -Su`); `T4N_BASE` menimpa base URL |
| `pkg-template/<pkg>/template` | resep paket format xbps-src, datar tanpa folder kategori |
| `json/<tag>/packages.json` | keluaran CI, di-commit balik oleh job `commit`; jangan diedit manual |
| `keys/key.pem.pub` | satu-satunya file kunci yang publik |
| `vdocs/{EN,ID}/{DEV,USER}.md` | dokumentasi; versi ID dan EN harus selalu sinkron |

File `.sh` dan `.py` ada di `.github/workflows/` dengan sengaja: `process-tag.sh`
ikut terlindungi CODEOWNERS, dan job `process` hanya meng-checkout direktori itu.

---

## 4. Konvensi kode

- **`vdev/` dan `process-tag.sh`: bash.** Memakai array, `mapfile`, `[[ ]]`.
  Karena `set -euo pipefail`, array kosong dipakai dengan idiom
  `${arr[@]+"${arr[@]}"}`, dan pipeline yang boleh gagal diakhiri `|| true`.
- **`setup.sh`: POSIX sh** (`#!/bin/sh`, `set -eu`). Tidak boleh ada bashism.
- **`gen-json.py`: Python 3 stdlib saja.** Tanpa `pip`.
- Quote semua variabel. Jangan pakai `eval`. Jangan pernah `source` input dari
  luar (template, keluaran GitHub).
- Pesan ke pengguna lewat `info`, `ok`, `warn`, `err`, `die`.
- YAML: indentasi 2 spasi; setiap blok `run` multi-baris diawali
  `set -euo pipefail`.
- Jangan menambah dependensi di job `process` tanpa alasan kuat. Alat
  dipasang lewat `xbps-install` di container `void-glibc-full`.

---

## 5. Pipeline CI (`process.yml`)

Trigger: `workflow_dispatch` (input `tags`, default `all`; dipanggil
`vdev/tools.sh -u` sekali setelah semua upload) dan `schedule`
(`23 */6 * * *`, cadangan, no-op bila tidak ada pekerjaan). `concurrency:
repo-process`, `cancel-in-progress: false`. Upload asset tidak memicu event
apa pun, karena itu tidak ada trigger `push`.

| Job | Secret | Baca template | Tugas |
|---|---|---|---|
| `prepare` | tidak | tidak | resolve tag, buat release yang belum ada (idempotent) |
| `process` ×9 | **ya** (`signing`) | **tidak** | `process-tag.sh` per tag |
| `json` ×9 | tidak | ya | repodata + template → `packages.json` |
| `commit` | tidak | tidak | commit `json/**` sekali, hanya bila berubah (`t4n-bot`, 3× retry rebase) |

Isi `process-tag.sh` per tag: kalibrasi `cmpver` → inventory asset → kelompokkan
`.xbps` per nama paket, simpan versi+revisi tertinggi (sisanya masuk prune) →
`unsigned` = yang di-keep tapi belum punya `<file>.sig2` → skip bila tidak ada
yang perlu diproses → unduh yang di-keep → verifikasi nama via `props.plist` →
`xbps-rindex -a` → `--sign` → `--sign-pkg` (hanya unsigned) → upload repodata +
`.sig2` baru → **prune terakhir**. Tag tanpa paket: asset dan repodata dihapus,
exit 0.

---

## 6. Template dan `archs`

- `version` **tanpa** revisi (`version=1.1.0`, `revision=1`). Naikkan `revision`
  hanya untuk perubahan template; reset ke `1` saat versi upstream baru.
- `distributor` menandai siapa yang mengemas (nanti diisi Let-X untuk template
  pihak lain).
- Nama paket harus di dalam `[A-Za-z0-9._+-]`.

| `archs` | Hasil |
|---|---|
| kosong / `noarch` | semua 9 tag (`noarch`: dibuild sekali, di-fanout) |
| `x86_64` | hanya x86_64 glibc |
| `x86_64*` | `x86_64` dan `x86_64-musl` |
| `x86_64* aarch64` | `x86_64`, `x86_64-musl`, `aarch64` |
| `~i686` | semua kecuali `i686` |
| `x86_64* ~x86_64-musl` | hanya `x86_64` |

Paket C yang belum siap musl harus menulis arsitektur eksplisit. Tool
shell/script murni sebaiknya `archs=noarch`.

---

## 7. Infrastruktur domain (dikelola Founder)

Developer **tidak** membutuhkan akses ke akun Cloudflare atau Citrahost, dan
tidak boleh diminta menempelkan token.

- Registrar: Citrahost. DNS: Cloudflare (zona `t4nlabs.web.id`).
- `repo-web`, `t4nos`, `t4nos-docs`, `vur`, `www`, dan root: CNAME/A ke GitHub
  Pages (`t4n-labs.github.io`), **DNS only**.
- `repo.t4nlabs.web.id`: custom domain Cloudflare Worker `t4n-repo`. Jangan
  membuat record manual ke GitHub Pages untuk nama ini.

| Request ke Worker | Hasil |
|---|---|
| `/` | redirect 302 ke `https://repo-web.t4nlabs.web.id/` |
| `/setup.sh` | disajikan dari `raw.githubusercontent.com/T4n-Labs/repo-t4nos/main/setup.sh` (`text/plain`; cache 300 dtk saat sukses, sebaiknya `no-store` saat error); sumber URL tetap, tanpa input user |
| `/<tag>` | redirect 302 ke halaman release GitHub tag itu |
| `/<tag>/<file>` | diproxy ke `releases/download/<tag>/<file>` (hanya GET/HEAD; header `range`, `if-modified-since`, `if-none-match`, `user-agent` diteruskan) |
| lainnya | 404 |

Kode Worker disimpan sebagai salinan di `worker/index.js` (bila belum ada,
tambahkan lewat PR). Versi yang aktif di Cloudflare adalah sumber sebenarnya
sampai salinan itu ada.

---

## 8. Status dan backlog (22 November 2026)

Sudah ada: struktur repo, `vdev/`, CI (`process.yml` valid, 4 job), template
awal, dokumentasi ID/EN, Worker `t4n-repo` dibuat.

Urutan pekerjaan yang tersisa:

1. **Selesai** (22-23 Nov 2026): zona Active, custom domain terpasang,
   `vdev/DNS-check.sh` lulus, `/setup.sh` disajikan Worker.
2. Minimal satu paket di setiap tag yang diumumkan. `x86_64-musl-repodata`
   sudah ada (HTTP 200, 23 Nov 2026); tag lain belum dicek.
3. **Selesai** (23 Nov 2026): tes end-to-end lewat domain lulus di x86_64
   (repodata, `.sig2`, dan `.xbps` diunduh via `repo.t4nlabs.web.id`, tanda tangan
   RSA terverifikasi, `tpkg` terpasang). Catatan uji: hapus cache
   `/var/cache/xbps` dulu, kalau tidak paket diambil dari cache, bukan dari domain.
4. Fingerprint `63:35:0c:65:0d:a5:f1:87:52:7e:c5:e9:13:3a:d6:2a` sudah diisi di `setup.sh`,
   README, dan USER; **website belum**. Perbandingan modulus kunci terimpor
   dengan `keys/key.pem.pub` belum dilaporkan.
5. Berkas hasil edit (`setup.sh`, `gen-json.py` dengan `BASE` ke domain, README,
   USER) siap diterapkan; penerapan di repo tidak dikonfirmasi. Field `url` di
   `packages.json` berubah pada run `process.yml` berikutnya. Perbarui
   `vdocs/*/DEV.md` §12.
6. Tambah `worker/index.js`, serta `/worker/` dan `/vdocs/` ke CODEOWNERS.
7. `CONTRIBUTING.md` / `CONTRIBUTING.ID.md` belum ada. LICENSE belum diputuskan.

Backlog teknis (opsional): download incremental di `process-tag.sh`; sumber data
website (`raw.githubusercontent.com` punya cache dan rate limit; alternatif
Pages di subdomain sendiri); integrasi `xbps-src` di Let-X.

---

## 9. Jebakan yang sudah diketahui

1. **Dua parser harus berperilaku sama**: bash (`tpl_field`, `expand_archs`) dan
   Python (`field`, `expand`). Ketidakcocokan saat ini: bash menganggap
   `archs=all` berarti semua tag, Python tidak (hasilnya kosong). Hindari
   `archs=all`, atau perbaiki Python.
2. Kedua parser membuang `#...` dari nilai field, jadi
   `homepage="https://x/#a"` terpotong.
3. **Tag tanpa paket tidak punya `<tag>-repodata`**, sehingga `xbps-install -S`
   mendapat 404 untuk pengguna arsitektur itu. `setup.sh` tidak memeriksanya.
4. `flags_for` (env.sh): host musl membuild target glibc menghasilkan
   `-A <hostbase>-glibc`, yang kemungkinan bukan nilai valid `xbps-src`
   (**belum diverifikasi**; uji sebelum mengandalkannya).
5. `schedule` tiap 6 jam tetap menyalakan job `process` (masuk Environment
   `signing`) walau tidak ada pekerjaan.
6. Setelah `-u`, asset sudah ada tetapi `.sig2`-nya belum sampai CI selesai;
   jangan umumkan rilis sebelum workflow hijau.
7. `process-tag.sh` mengunduh semua paket yang di-keep di setiap run.
8. Subpackage tidak punya template sendiri; `archs`-nya di JSON fallback ke
   `[tag]`.
9. Job `commit` gagal 3× kalau branch protection menolak push bot; izinkan
   bypass untuk `github-actions` dan Founder.
10. Karakter `:`, spasi, dan tanda kurung pada nama file belum diuji.

---

## 10. Pemeriksaan sebelum menyatakan selesai

```sh
bash -n vdev/tools.sh vdev/src/*.sh .github/workflows/process-tag.sh
sh -n setup.sh
python3 -c "import ast; ast.parse(open('.github/workflows/gen-json.py').read())"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/process.yml'))"
shellcheck vdev/tools.sh vdev/src/*.sh .github/workflows/process-tag.sh   # bila tersedia

# ekspansi archs tanpa bootstrap apa pun
bash -c '. vdev/src/common.sh; . vdev/src/template.sh; expand_archs "x86_64* ~x86_64-musl"'
```

Setiap kali Worker atau DNS diubah, jalankan juga `bash vdev/DNS-check.sh`.
Laporkan hasil tiap perintah. Kalau suatu perintah tidak bisa dijalankan (alat
tidak ada, tidak ada akses), katakan itu, jangan dianggap lulus.

---

## 11. Resep tugas umum

- **Paket baru / ubah paket:** edit `pkg-template/<pkg>/template` →
  `vdev/tools.sh -b <pkg>` → `vdev/tools.sh -u <pkg>` (butuh akses write; tanpa
  itu, buka PR dan maintainer yang upload) → tunggu CI hijau → cek status
  `ready` di website.
- **Ubah parser:** ubah versi bash **dan** Python bersamaan, lalu uji semua baris
  tabel di §6.
- **Ubah CI:** patuhi §2; uji di fork dengan secret uji sendiri, bukan secret
  produksi. Perubahan di `.github/workflows/` wajib direview Founder (CODEOWNERS).
- **Rotasi kunci:** kunci baru → perbarui secret → dispatch `process.yml`
  dengan `tags=all` → umumkan fingerprint baru → pengguna menghapus `.plist`
  lama dan sinkron ulang (lihat `vdocs/*/DEV.md` §8).
- **Ganti `BASE` ke domain:** hanya setelah tes end-to-end lulus (§8 butir 3);
  ubah `setup.sh` dan `gen-json.py`, lalu dokumen.
- **Tambah/ubah arsitektur (tag):** daftar tag diduplikasi di enam tempat dan
  semuanya harus sinkron: `ALL` di `common.sh`, `ALL` di `gen-json.py`,
  `ALL_TAGS` di `process.yml`, menu hardcode di `build.sh: menu_arch`,
  `case` di `setup.sh`, dan `TAGS` di Worker, plus dokumen.

---

## 12. Larangan

- Jangan commit `key.pem`, token, atau secret apa pun, dan jangan meminta
  pengguna menempelkannya di chat.
- Jangan commit biner (`.xbps`, `.sig2`, repodata).
- Jangan force-push ke `main`, dan jangan hapus Release atau asset secara manual.
- Jangan ubah `.github/workflows/`, `setup.sh`, atau `keys/` tanpa review Founder.
- Jangan menjalankan langkah yang membutuhkan akun Cloudflare/Citrahost atas
  nama Founder; tulis instruksinya saja.
- Jangan mengklaim sesuatu "sudah berfungsi" tanpa bukti keluaran perintah.

---

TUGAS:
<tulis tugas di sini>