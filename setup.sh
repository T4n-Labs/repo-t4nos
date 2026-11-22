#!/bin/sh
# T4n OS — Repository Setup
#   curl -sLO https://raw.githubusercontent.com/T4n-Labs/repo-t4nos/main/setup.sh && sudo sh setup.sh
set -eu

# TEMPORER: URL release langsung (sebelum Cloudflare Worker aktif).
# Setelah Worker siap, ganti ke: BASE="https://repo.t4nlabs.web.id"
BASE="https://github.com/T4n-Labs/repo-t4nos/releases/download"

SITE="https://repo-web.t4nlabs.web.id/"
CONF="${CONF_FILE:-/etc/xbps.d/10-t4nos.conf}"
FINGERPRINT="<ISI-SETELAH-PROSES-PERTAMA>"

[ "$(id -u)" -eq 0 ] || { echo "Jalankan: sudo sh setup.sh"; exit 1; }
command -v xbps-uhelper >/dev/null 2>&1 || { echo "xbps tidak ditemukan (Void/T4n OS saja)"; exit 1; }

ARCH=$(xbps-uhelper arch)
echo "Arsitektur sistem: $ARCH"
case "$ARCH" in
  x86_64|x86_64-musl|aarch64|aarch64-musl|armv6l|armv6l-musl|armv7l|armv7l-musl|i686) ;;
  i686-musl) echo "i686-musl belum disediakan."; exit 1 ;;
  *) echo "Arsitektur $ARCH tidak didukung."; exit 1 ;;
esac

mkdir -p "$(dirname "$CONF")"
echo "repository=${BASE}/${ARCH}" > "$CONF"
echo "[OK] $CONF → repository=${BASE}/${ARCH}"
echo
if [ "$FINGERPRINT" = "<ISI-SETELAH-PROSES-PERTAMA>" ]; then
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
echo "Web: $SITE"