#!/usr/bin/env bash
# Runner suite test repo-t4nos — dipakai lokal DAN di CI (.github/workflows/test.yml).
#
#   bash tests/run.sh                  # semua suite
#   bash tests/run.sh -v               # verbose: tampilkan setiap uji yang lulus
#   bash tests/run.sh vdev process_tag # hanya suite tertentu
#   bash tests/run.sh -l               # daftar suite
#
# Dependensi: bash >= 4.4, python3 >= 3.8 (stdlib saja), git, tar, awk.
# Tanpa jaringan, tanpa secret, tanpa root. `gh`/`xbps-*`/`id` selalu dipalsukan (stub)
# lewat PATH; setup.sh hanya dijalankan dengan CONF_FILE di direktori sementara.
# Tidak ada yang ditulis ke repo: semua berkas sementara ada di satu direktori
# ($T4N_TMP) yang SELALU dihapus oleh trap (juga saat Ctrl-C / SIGTERM).
#
# set -e sengaja TIDAK dipakai: runner harus tetap lanjut ke suite berikutnya
# dan melaporkan semua kegagalan sekaligus.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SUITES=(syntax runner invariants workflows docs parser_parity gen_json process_tag vdev)

run_suite() {
  case "$1" in
    syntax)        bash    "$HERE/test_syntax.sh" ;;
    runner)        python3 "$HERE/test_runner.py" ;;
    invariants)    python3 "$HERE/test_invariants.py" ;;
    workflows)     python3 "$HERE/test_workflows.py" ;;
    docs)          python3 "$HERE/test_docs.py" ;;
    parser_parity) python3 "$HERE/test_parser_parity.py" ;;
    gen_json)      python3 "$HERE/test_gen_json.py" ;;
    process_tag)   python3 "$HERE/test_process_tag.py" ;;
    vdev)          bash    "$HERE/test_vdev.sh" ;;
    *) return 127 ;;
  esac
}

verbose=0; selected=()
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose) verbose=1 ;;
    -l|--list)    printf '%s\n' "${SUITES[@]}"; exit 0 ;;
    -h|--help)    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           echo "opsi tidak dikenal: $1 (lihat --help)" >&2; exit 2 ;;
    *)            selected+=("$1") ;;
  esac
  shift
done
[ ${#selected[@]} -gt 0 ] || selected=("${SUITES[@]}")
for s in "${selected[@]}"; do
  case " ${SUITES[*]} " in *" $s "*) ;; *) echo "suite tidak dikenal: $s (lihat --list)" >&2; exit 2 ;; esac
done

# ── prasyarat ──
missing=()
for c in bash python3 git tar awk mktemp; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
if [ ${#missing[@]} -gt 0 ]; then echo "prasyarat tidak ada: ${missing[*]}" >&2; exit 2; fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  echo "butuh bash >= 4.4 (ada: $BASH_VERSION)" >&2; exit 2
fi
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' \
  || { echo "butuh python3 >= 3.8" >&2; exit 2; }

# ── direktori sementara tunggal, selalu dibersihkan ──
T4N_TMP="$(mktemp -d "${TMPDIR:-/tmp}/t4n-tests.XXXXXX")" || exit 2
cleanup() { [ -n "${T4N_TMP:-}" ] && [ -d "$T4N_TMP" ] && rm -rf "$T4N_TMP"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# ── lingkungan terisolasi: tidak ada token/secret/konfigurasi git pengguna yang bocor masuk ──
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN SIGN_KEY SIGNEDBY TAG GH_REPO
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export T4N_REPO="$REPO" T4N_TMP T4N_VERBOSE="$verbose" LC_ALL=C PYTHONDONTWRITEBYTECODE=1

declare -A result=()
fails=0
for s in "${selected[@]}"; do
  printf '\n══════ suite: %s ══════\n' "$s"
  if run_suite "$s"; then result[$s]=LULUS; else result[$s]=GAGAL; fails=$((fails + 1)); fi
done

printf '\n══════ RINGKASAN ══════\n'
for s in "${selected[@]}"; do printf '  %-14s %s\n' "$s" "${result[$s]}"; done
if [ "$fails" -eq 0 ]; then echo "SEMUA SUITE LULUS (${#selected[@]})"; exit 0; fi
echo "$fails dari ${#selected[@]} suite GAGAL"; exit 1
