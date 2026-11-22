# Repositori T4n OS (`repo-t4nos`)

Paket biner XBPS bertanda tangan yang **tidak tersedia di repositori resmi Void
Linux**. Bisa dipakai di T4n OS maupun Void Linux biasa, untuk **glibc dan
musl**. Satu repositori, sembilan release tag (`x86_64`, `x86_64-musl`,
`aarch64`, `aarch64-musl`, `armv6l`, `armv6l-musl`, `armv7l`, `armv7l-musl`,
`i686`).

- Pencarian paket: https://repo-web.t4nlabs.web.id/
- Endpoint XBPS: `https://repo.t4nlabs.web.id/<tag>`

## Instalasi cepat

```sh
curl -sLO https://raw.githubusercontent.com/T4n-Labs/repo-t4nos/main/setup.sh
less setup.sh
sudo sh setup.sh
```

## Fingerprint kunci

> **Belum dipublikasikan.** Jangan mengimpor kunci repositori sebelum
> fingerprint diumumkan di sini dan di https://repo-web.t4nlabs.web.id/.

Jawab `yes` pada prompt kunci XBPS hanya jika fingerprint yang ditampilkan sama
persis dengan yang dipublikasikan di sini.

## Dokumentasi

| | English | Bahasa Indonesia |
|---|---|---|
| Pengguna | [vdocs/EN/USER.md](vdocs/EN/USER.md) | [vdocs/ID/USER.md](vdocs/ID/USER.md) |
| Developer & maintainer | [vdocs/EN/DEV.md](vdocs/EN/DEV.md) | [vdocs/ID/DEV.md](vdocs/ID/DEV.md) |

## Berkontribusi

Kontribusi (template, tool, docs) lewat **fork + Pull Request**. Hanya Founder
yang punya akses write dan memegang kunci signing; biner dibuild, ditandatangani,
dan diindeks oleh CI. Lihat panduan developer di atas.

## Lisensi

Belum diputuskan.

---

**[T4n Labs](https://t4nlabs.web.id/)** ◉ **[Gh0sT4n](https://gh0st4n.my.id/)**