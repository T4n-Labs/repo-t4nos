#!/usr/bin/env bash
# T4n OS — developer tool. Entry point tipis; logika ada di src/.
set -euo pipefail
VDEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _m in common template env build upload git; do
    # shellcheck source=/dev/null
    . "$VDEV_DIR/src/$_m.sh"
done
unset _m

usage() {
    cat <<EOF
T4n OS developer tool (xbps-src)
  -s,  --setup              clone void-packages + binary-bootstrap
  -sy, --sync               git pull + salin template baru/berubah
  -b,  --build [pkg...] [-a arch...|all|'x86_64*']
  -u,  --upload [pkg...]    upload ke tag + trigger CI, lalu push/PR
  -h,  --help

Host: $HOST_ARCH
Tag : ${ALL[*]}
EOF
}

case "${1:-}" in
    -s|--setup)  cmd_setup ;;
    -sy|--sync)  cmd_sync ;;
    -b|--build)  shift; cmd_build "$@" ;;
    -u|--upload) shift; cmd_upload "$@" ;;
    -h|--help|"") usage ;;
    *) err "opsi tidak dikenal: $1"; usage; exit 1 ;;
esac