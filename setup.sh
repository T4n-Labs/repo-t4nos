#!/bin/sh
# T4n OS — Repository Setup & Update
#   curl -fsSLO https://repo.t4nlabs.web.id/setup.sh
#   sudo sh setup.sh            # pasang repo (arsitektur + libc dideteksi otomatis)
#   sudo sh setup.sh update     # sinkron indeks + upgrade (xbps-install -Su)
set -eu

# TEMPORER: URL release langsung sampai tes `xbps-install -S` lewat domain lulus.
# Setelah itu ganti default ke: https://repo.t4nlabs.web.id
# Uji domain tanpa mengubah berkas:
#   sudo env T4N_BASE=https://repo.t4nlabs.web.id sh setup.sh
BASE="${T4N_BASE:-https://github.com/T4n-Labs/repo-t4nos/releases/download}"

SITE="https://repo-web.t4nlabs.web.id/"
CONF="${CONF_FILE:-/etc/xbps.d/10-t4nos.conf}"
PLACEHOLDER="<ISI-SETELAH-PROSES-PERTAMA>"
FINGERPRINT="$PLACEHOLDER"

CMD="${1:-setup}"

usage() {
  cat <<EOF
T4n OS — Repository Setup & Update

Pemakaian: sudo sh setup.sh [perintah]

  setup             pasang repo T4n OS; arsitektur dan libc dideteksi otomatis
                    (default bila tanpa perintah)
  update [opsi]     sinkron indeks dan upgrade semua paket: xbps-install -Su
  -h, --help        tampilkan bantuan

Lewat pipe: curl -fsSL https://repo.t4nlabs.web.id/setup.sh | sudo sh -s update
Jangan memakai -y pada update kecuali Anda sudah memverifikasi fingerprint.
EOF
}

need_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Jalankan dengan sudo: sudo sh setup.sh $CMD"; exit 1; }
}

need_xbps() {
  command -v xbps-uhelper >/dev/null 2>&1 \
    || { echo "xbps tidak ditemukan (Void/T4n OS saja)"; exit 1; }
}

detect_arch() {
  ARCH=$(xbps-uhelper arch)
  case "$ARCH" in
    *-musl) LIBC=musl ;;
    *)      LIBC=glibc ;;
  esac
  echo "Arsitektur sistem: $ARCH ($LIBC)"
  case "$ARCH" in
    x86_64|x86_64-musl|aarch64|aarch64-musl|armv6l|armv6l-musl|armv7l|armv7l-musl|i686) ;;
    i686-musl) echo "i686-musl belum disediakan."; exit 1 ;;
    *) echo "Arsitektur $ARCH tidak didukung."; exit 1 ;;
  esac
}

do_setup() {
  need_root
  need_xbps
  detect_arch

  mkdir -p "$(dirname "$CONF")"
  echo "repository=${BASE}/${ARCH}" > "$CONF"
  echo "[OK] $CONF → repository=${BASE}/${ARCH}"
  echo
  if [ "$FINGERPRINT" = "$PLACEHOLDER" ]; then
    echo "[WARN] Fingerprint belum dicantumkan. Cocokkan dengan yang diumumkan di"
    echo "       $SITE sebelum menjawab 'yes'."
  else
    echo "Fingerprint resmi : $FINGERPRINT"
    echo "Jawab 'yes' HANYA jika yang ditampilkan XBPS persis sama."
  fi
  echo
  if [ "${T4N_ASSUME_YES:-0}" = 1 ]; then
    xbps-install -S -y
  elif ( : < /dev/tty ) 2>/dev/null; then
    xbps-install -S < /dev/tty
  else
    echo "Tidak ada tty untuk konfirmasi fingerprint. Jalankan langsung dari terminal,"
    echo "atau set T4N_ASSUME_YES=1 setelah verifikasi manual."
    exit 1
  fi
  echo
  echo "[OK] Repo aktif. Coba: xbps-query -Rs zvc"
  echo "Update berikutnya: sudo sh setup.sh update"
  echo "Web: $SITE"
}

do_update() {
  need_root
  need_xbps
  [ -f "$CONF" ] || { echo "Repo T4n OS belum dipasang. Jalankan dulu: sudo sh setup.sh"; exit 1; }
  detect_arch

  echo "Menjalankan: xbps-install -Su $*"
  # stdin dialihkan agar xbps-install tidak membaca sisa skrip saat dijalankan lewat pipe
  if ( : < /dev/tty ) 2>/dev/null; then
    xbps-install -Su "$@" < /dev/tty || update_failed
  else
    xbps-install -Su "$@" < /dev/null || update_failed
  fi
  echo
  echo "[OK] Indeks tersinkron dan paket diperbarui."
}

update_failed() {
  echo
  echo "[ERROR] xbps-install -Su gagal. Jika xbps meminta pembaruan dirinya sendiri"
  echo "        lebih dulu, jalankan: xbps-install -u xbps  lalu ulangi perintah ini."
  exit 1
}

case "$CMD" in
  setup)           do_setup ;;
  update)          shift; do_update "$@" ;;
  -h|--help|help)  usage ;;
  *)               echo "Perintah tidak dikenal: $CMD"; echo; usage; exit 1 ;;
esac