# Repositori T4n OS — Panduan Pengguna

Repositori XBPS **T4n OS** (`repo-t4nos`) menyediakan paket biner bertanda tangan
kriptografis yang **tidak tersedia di repositori resmi Void Linux**. Bisa dipakai
di T4n OS maupun Void Linux biasa, untuk **glibc dan musl**.

Repositori ini adalah **penambah**, bukan pengganti. Paket resmi Void tetap
diambil dari mirror resmi.

🔍 **Pencarian paket:** https://repo-web.t4nlabs.web.id/

---

## Arsitektur yang Didukung

Repositori dipisah menjadi 9 release tag. Nama tag sama persis dengan string
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

Karena nama tag cocok dengan `xbps-uhelper arch`, satu skrip setup melayani semua
sistem — tanpa prompt pilih arsitektur, tanpa pemetaan manual.

---

## 1. Menambahkan Repositori

### Opsi A — Otomatis (disarankan)

Unduh, baca, lalu jalankan. Membaca skrip sebelum memasukkannya ke shell root
adalah kebiasaan yang baik:

```sh
curl -sLO https://raw.githubusercontent.com/T4n-Labs/repo-t4nos/main/setup.sh
less setup.sh
sudo sh setup.sh
```

Satu baris, kalau lebih suka:

```sh
curl -sL https://raw.githubusercontent.com/T4n-Labs/repo-t4nos/main/setup.sh | sudo sh
```

Skrip mendeteksi arsitektur **dan libc** sistem Anda, menulis satu file
konfigurasi, lalu menyinkronkan indeks paket.

### Opsi B — Manual

```sh
sudo mkdir -p /etc/xbps.d
echo "repository=https://repo.t4nlabs.web.id/$(xbps-uhelper arch)" \
  | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

### ⚠️ Verifikasi Fingerprint (wajib)

Saat sinkronisasi pertama, XBPS menampilkan fingerprint kunci repositori dan
meminta konfirmasi:

```
...
Fingerprint: xx:xx:xx:...
Do you want to import this public key? [Y/n]
```

> Teks prompt bisa berbeda antar versi XBPS; yang harus dicocokkan adalah baris `Fingerprint`.

Jawab `yes` **hanya** jika fingerprint sama persis dengan yang diumumkan di
[README repositori](https://github.com/T4n-Labs/repo-t4nos) dan di website.

Konfirmasi ini satu-satunya pengaman rantai pasok Anda. Jangan pernah menjawab
asal, dan jangan pakai `T4N_ASSUME_YES=1` kecuali Anda sudah memverifikasi
fingerprint-nya sendiri.

---

## 2. Mencari dan Menginstal

```sh
xbps-query -Rs "nama"        # cari, mis. zvc, letx, tpkg
sudo xbps-install nama       # instal
sudo xbps-install -Su        # update semua (resmi + T4n OS)
```

---

## 3. Pencarian Paket Web

https://repo-web.t4nlabs.web.id/

- **Pencarian langsung** dengan highlight (debounce 110 ms)
- **Tab arsitektur** dengan penghitung paket langsung
- **Paginasi** untuk hasil banyak
- **URL bisa dibagikan** — state ada di hash URL: `#q=radare&arch=x86_64&page=2`
- **Pintasan keyboard** — `/` fokus pencarian, `Esc` bersihkan
- **Salin satu klik** perintah instal per paket

### Status paket

| Badge | Arti |
|---|---|
| `ready` | Biner ada untuk arsitektur itu — bisa diinstal sekarang |
| `recipe` | Template ada, biner belum dibangun untuk arsitektur itu |

Entri `recipe` **tidak** bisa diunduh. Ia ditampilkan supaya Anda tahu apa yang
sedang disiapkan; tunggu sampai berubah jadi `ready`.

---

## 4. Menghapus Repositori

```sh
sudo rm /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

Kunci publik yang sudah diimpor tetap tersimpan di `/var/db/xbps/keys/`. Hapus file
`.plist`-nya kalau Anda juga ingin mencabut kepercayaan pada kunci T4n OS.

---

## ❓ Troubleshooting

**`repository is not signed, refusing to continue!`**
Repositori XBPS remote wajib bertanda tangan. Pastikan URL di file `.conf` benar
dan Anda menerima impor kunci. Sinkronkan ulang dengan `sudo xbps-install -S`.

**Fingerprint berubah / kunci lama ditolak.**
Kunci repositori dirotasi. Hapus kunci lama, lalu sinkronkan ulang dan verifikasi
fingerprint **baru**:

```sh
sudo rm /var/db/xbps/keys/<fingerprint-lama>.plist
sudo xbps-install -S
```

**`xbps-query` tidak menemukan paket.**
1. Sudah menjalankan `xbps-install -S` setelah menambahkan repositori?
2. Paket mungkin belum dibangun untuk arsitektur/libc Anda — cek tab arsitektur
   di website. Badge `recipe` berarti "belum dibangun".

**404 saat sinkronisasi.**
Ada dua kemungkinan.

1. Endpoint `repo.t4nlabs.web.id/<arch>` (proxy Cloudflare Worker) belum aktif.
   Pakai URL release langsung:

```sh
echo "repository=https://github.com/T4n-Labs/repo-t4nos/releases/download/$(xbps-uhelper arch)" \
  | sudo tee /etc/xbps.d/10-t4nos.conf
sudo xbps-install -S
```

2. Arsitektur/libc Anda belum punya paket sama sekali, jadi indeksnya
   (`<arch>-repodata`) belum dibuat. Tidak ada yang perlu diperbaiki di sisi Anda;
   tunggu paket pertama masuk atau tanya maintainer.

**Website menampilkan ∅ / kosong.**
CI masih membangun atau indeks belum dibuat ulang. Tunggu beberapa menit dan
muat ulang. Indeks dibuat dari template, jadi paket baru muncul sebelum binernya
selesai dibangun.

**`i686-musl` tidak didukung.**
Benar — kombinasi itu tidak disediakan. Lihat tabel di atas.

---

**[T4n Labs](https://t4nlabs.web.id/)** ◉ **[Gh0sT4n](https://gh0st4n.my.id/)**
*Dibangun untuk komunitas, oleh komunitas.*