#!/usr/bin/env bash
# T4n OS — developer tool. Entry point tipis; logika ada di src/.
set -euo pipefail

# resolusi symlink, supaya ./tools (root) atau symlink di PATH tetap benar
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
    _dir="$(cd -P "$(dirname "$_self")" && pwd)"
    _self="$(readlink "$_self")"
    case "$_self" in /*) ;; *) _self="$_dir/$_self" ;; esac
done
VDEV_DIR="$(cd -P "$(dirname "$_self")" && pwd)"
unset _self _dir

for _m in common template env build upload git search; do
    # shellcheck source=/dev/null
    . "$VDEV_DIR/src/$_m.sh"
done
unset _m

usage(){
    cat >&2 <<EOF
T4n OS developer tool (xbps-src)
  -s,  --setup              clone void-packages (full) + binary-bootstrap
  -sy, --sync               git pull + salin template baru/berubah
  -U,  --update             jalankan xbps-src bootstrap-update
  -b,  --build [pkg...] [-a arch...|all|'x86_64*']
  -u,  --upload [pkg...]    upload ke tag + trigger CI, lalu push/PR
       search <query>       cari template (nama atau deskripsi) + info detail
  -h,  --help

Host: $HOST_ARCH
Tag : ${ALL[*]}
EOF
}

case "${1:-}" in
    -s|--setup)      cmd_setup ;;
    -sy|--sync)      cmd_sync ;;
    -U|--update)     cmd_update ;;
    -b|--build)      shift; cmd_build "$@" ;;
    -u|--upload)     shift; cmd_upload "$@" ;;
    search)          shift; cmd_search "$@" ;;
    -h|--help|"")    usage ;;
    *) err "opsi tidak dikenal: $1"; usage; exit 1 ;;
esac