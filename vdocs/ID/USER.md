# Repositori T4n OS — Panduan Pengguna

Repositori XBPS **T4n OS** (`repo-t4nos`) menyediakan paket biner bertanda tangan
kriptografis yang **tidak tersedia di repositori resmi Void Linux**. Ia bekerja di
T4n OS maupun Void Linux biasa, untuk **glibc dan musl**.

Repositori ini adalah **tambahan**, bukan pengganti. Paket resmi Void tetap berasal
dari mirror resmi.

🔍 **Pencarian paket:** https://repo-web.t4nlabs.web.id/

---

## Arsitektur yang Didukung

Repositori dibagi menjadi 9 tag rilis. Nama tiap tag persis sama dengan string
arsitektur yang dilaporkan `xbps-uhelper arch`.

| Tag | Arsitektur | libc |
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

> `i686-musl` **tidak** disediakan.

Karena nama tag sama dengan keluaran `xbps-uhelper arch`, satu skrip setup melayani
semua sistem — tanpa pertanyaan arsitektur, tanpa pemetaan manual.

---

## 1. Menambahkan Repositori

### Opsi A — Otomatis (disarankan)

Unduh, baca, lalu jalankan. Membaca skrip sebelum menyalurkannya ke shell root
adalah kebiasaan yang baik:

```sh
curl -fsSLO https://repo.t4nlabs.web.id/setup.sh
less setup.sh
sudo sh setup.sh
```

Versi satu baris, kalau Anda memilihnya:

```sh
curl -fsSL https://repo.t4nlabs.web.id/setup.sh | sudo sh
```

Skrip mendeteksi arsitektur **dan libc** Anda, menulis satu berkas konfigurasi,
lalu menyinkronkan indeks paket.

### Opsi B — Manual

```sh
sudo mkdir -p /etc/xbps.d
echo "repository=https://repo.t4nlabs.web.id/$(xbps-uhelper arch)" \
  | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

### Perintah dan variabel lingkungan `setup.sh`

```sh
sudo sh setup.sh              # pasang repositori (default, sama dengan `setup`)
sudo sh setup.sh update       # sinkron indeks + upgrade: xbps-install -Su [opsi]
sh setup.sh --help
```

`update` mensyaratkan repositori sudah terpasang (ia memeriksa berkas konfigurasi) dan
meneruskan opsi tambahan ke `xbps-install -Su`. Lewat pipe:
`curl -fsSL https://repo.t4nlabs.web.id/setup.sh | sudo sh -s update`. Jangan memakai
`-y` pada `update` kecuali Anda sudah memverifikasi fingerprint. `setup` menimpa berkas
konfigurasi jika sudah ada.

| Variabel | Default | Fungsi |
|---|---|---|
| `T4N_BASE` | `https://repo.t4nlabs.web.id` | URL dasar; ditulis sebagai `repository=<T4N_BASE>/<arch>`. Cadangan: URL release (lihat Pemecahan Masalah) |
| `CONF_FILE` | `/etc/xbps.d/10-t4nos.conf` | Lokasi berkas konfigurasi yang ditulis |
| `T4N_ASSUME_YES` | `0` | `1` menjalankan `xbps-install -S -y` dan **melewati konfirmasi fingerprint** |

`sudo` biasanya membuang variabel lingkungan, jadi lewatkan lewat `env`:

```sh
sudo env T4N_BASE=https://github.com/T4n-Labs/repo-t4nos/releases/download sh setup.sh
sudo env T4N_ASSUME_YES=1 sh setup.sh   # HANYA setelah Anda memverifikasi fingerprint sendiri
```

Tanpa terminal (CI, pipe biasa) `setup` tidak bisa meminta konfirmasi dan berhenti,
kecuali `T4N_ASSUME_YES=1` diset.

### ⚠️ Verifikasi Fingerprint (wajib)

Pada sinkronisasi pertama, XBPS menampilkan fingerprint kunci repositori dan meminta
konfirmasi:

```
...
Fingerprint: xx:xx:xx:...
Do you want to import this public key? [Y/n]
```

> Kalimat prompt bisa berbeda antar versi XBPS; yang harus cocok adalah baris `Fingerprint`.

Fingerprint resmi saat ini: `63:35:0c:65:0d:a5:f1:87:52:7e:c5:e9:13:3a:d6:2a` (penanda tangan `T4n Labs`; kunci yang sama untuk semua tag).

Jawab `yes` **hanya** jika fingerprint cocok dengan yang dipublikasikan di
[README repositori](https://github.com/T4n-Labs/repo-t4nos) dan di website.

Konfirmasi ini satu-satunya perlindungan di rantai pasok Anda. Jangan pernah
menjawabnya sembarangan, dan jangan pakai `T4N_ASSUME_YES=1` kecuali Anda sudah
memverifikasi fingerprint sendiri.

---

## 2. Mencari dan Memasang

```sh
xbps-query -Rs "nama"        # cari, mis. zvc, tpkg
sudo xbps-install nama       # pasang
sudo xbps-install -Su        # update semuanya (resmi + T4n OS)
```

---

## 3. Pencarian Paket di Web

https://repo-web.t4nlabs.web.id/

- **Pencarian langsung** dengan penyorotan (debounce 110 ms)
- **Tab arsitektur** dengan penghitung paket langsung
- **Paginasi** untuk hasil yang banyak
- **URL yang bisa dibagikan** — status disimpan di hash URL: `#q=zvc&arch=x86_64&page=2`
- **Pintasan keyboard** — `/` memfokuskan pencarian, `Esc` menghapusnya
- **Salin satu klik** perintah pemasangan tiap paket

### Status paket

| Lencana | Arti |
|---|---|
| `ready` | Biner tersedia untuk arsitektur itu — bisa dipasang sekarang (`category: xbps` di JSON indeks) |
| `recipe` | Template ada, biner belum dibangun untuk arsitektur itu (`category: template`) |

Entri `recipe` **tidak** bisa diunduh. Ia ditampilkan agar Anda tahu apa yang akan
datang; tunggu sampai berubah menjadi `ready`.

---

## 4. Menghapus Repositori

```sh
sudo rm /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

Kunci publik yang sudah Anda impor tetap berada di `/var/db/xbps/keys/`. Hapus berkas
`.plist`-nya jika Anda juga ingin mencabut kepercayaan pada kunci T4n OS.

---

## ❓ Pemecahan Masalah

**`repository is not signed, refusing to continue!`**
Repositori XBPS jarak jauh harus bertanda tangan. Periksa bahwa URL di berkas `.conf`
benar dan Anda sudah menerima impor kunci. Sinkron ulang dengan
`sudo xbps-install -S`.

**Fingerprint berubah / kunci lama ditolak.**
Kunci repositori dirotasi. Hapus kunci lama, lalu sinkron ulang dan verifikasi
fingerprint **baru**:

```sh
sudo rm /var/db/xbps/keys/<fingerprint-lama>.plist
sudo xbps-install -S
```

**`xbps-query` tidak menemukan paket.**
1. Sudahkah Anda menjalankan `xbps-install -S` setelah menambahkan repositori?
2. Paket mungkin belum dibangun untuk arsitektur/libc Anda — lihat tab arsitektur di
   website. Lencana `recipe` berarti "belum dibangun".

**404 saat sinkronisasi.**
Ada dua kemungkinan penyebab.

1. Endpoint `repo.t4nlabs.web.id/<arch>` (proxy Cloudflare Worker) belum aktif. Pakai
   URL release langsung:

```sh
echo "repository=https://github.com/T4n-Labs/repo-t4nos/releases/download/$(xbps-uhelper arch)" \
  | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

2. Arsitektur/libc Anda belum punya paket sama sekali, sehingga indeksnya
   (`<arch>-repodata`) belum dibuat. Tidak ada yang perlu diperbaiki di sisi Anda;
   tunggu paket pertama atau tanyakan ke maintainer.

**Website menampilkan ∅ / kosong.**
CI masih membangun atau indeks belum dibuat ulang. Tunggu beberapa menit lalu muat
ulang. Indeks dihasilkan dari template, jadi paket baru muncul sebelum biner-nya
selesai dibangun.

**`i686-musl` tidak didukung.**
Benar — kombinasi itu tidak disediakan. Lihat tabel di atas.

---

**[T4n Labs](https://t4nlabs.web.id/)** ◉ **[Gh0sT4n](https://gh0st4n.my.id/)**
*Dibangun untuk komunitas, oleh komunitas.*
