# shellcheck shell=bash
# Pustaka mini untuk tests/test_*.sh. Di-source, bukan dieksekusi. TIDAK menulis ke repo.
# set -e tidak dipakai (uji memang memeriksa perintah yang sengaja gagal).

T4N_REPO="${T4N_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
T4N_VERBOSE="${T4N_VERBOSE:-0}"
T4N_PASS=0; T4N_FAIL=0

# Direktori kerja pribadi suite ini; dihapus saat keluar (juga saat sinyal).
t4n_init() {
  TMP="$(mktemp -d "${T4N_TMP:-${TMPDIR:-/tmp}}/t4n-$1.XXXXXX")" || exit 2
  trap 't4n_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
}
t4n_cleanup() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

section() { printf '\n-- %s\n' "$*"; }
pass() { T4N_PASS=$((T4N_PASS + 1)); [ "$T4N_VERBOSE" = 1 ] && printf '  PASS %s\n' "$1"; return 0; }
fail() { T4N_FAIL=$((T4N_FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "${2//$'\n'/$'\n       '}"; return 0; }

# check "nama" <perintah...>  → lulus bila exit code 0 (stdout/stderr perintah disembunyikan)
check() { local n="$1"; shift; local o; if o=$("$@" 2>&1); then pass "$n"; else fail "$n" "$o"; fi; }
# refuse "nama" <perintah...>  → lulus bila exit code BUKAN 0
refuse() { local n="$1"; shift; local o; if o=$("$@" 2>&1); then fail "$n" "seharusnya gagal tetapi sukses: $o"; else pass "$n"; fi; }
# eq "nama" "diharapkan" "aktual"
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "diharapkan: [$2]"$'\n'"aktual    : [$3]"; fi; }
# has "nama" "teks" "potongan"   /   lacks "nama" "teks" "potongan"
has()   { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "tidak memuat: [$3]"$'\n'"isi: ${2:0:600}" ;; esac; }
lacks() { case "$2" in *"$3"*) fail "$1" "tidak boleh memuat: [$3]"$'\n'"isi: ${2:0:600}" ;; *) pass "$1" ;; esac; }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# Memuat modul vdev di subshell bersih. Variabel T_TPL / T_VP / T_HOST (opsional) menimpa
# TPL / VP / HOST_ARCH setelah di-source. HOST_ARCH default x86_64 agar hasil deterministik.
t4n_src() {
  local m s=""
  for m in common template env build upload git search; do s+=". \"$T4N_REPO/vdev/src/$m.sh\"; "; done
  s+='TPL="${T_TPL:-$TPL}"; VP="${T_VP:-$VP}"; HOST_ARCH="${T_HOST:-x86_64}"; '
  printf '%s' "$s"
}
# vdev_bash 'perintah…' [args…]  — jalankan di bash baru dengan modul termuat
vdev_bash() { local s; s="$(t4n_src)$1"; shift; bash -c "$s" vdev_bash "$@"; }

t4n_summary() {
  printf '\n%s: %d lulus, %d gagal\n' "${1:-suite}" "$T4N_PASS" "$T4N_FAIL"
  [ "$T4N_FAIL" -eq 0 ]
}
