#!/usr/bin/env bash
# Suite: pemeriksaan sintaks & konvensi dasar (bash -n, sh -n, ast.parse, POSIX setup.sh).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib.sh
. "$HERE/lib.sh"
t4n_init syntax
cd "$T4N_REPO" || exit 2
shopt -s nullglob

section "bash -n"
for f in vdev/tools.sh vdev/src/*.sh vdev/DNS-check.sh .github/workflows/process-tag.sh tests/*.sh; do
  check "bash -n $f" bash -n "$f"
done

section "sh -n (POSIX) — setup.sh"
check "sh -n setup.sh" sh -n setup.sh
if command -v dash >/dev/null 2>&1; then check "dash -n setup.sh" dash -n setup.sh; fi

section "python ast.parse"
for f in .github/workflows/gen-json.py tests/*.py; do
  check "ast.parse $f" python3 -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$f"
done

section "setup.sh tanpa bashism (CLAUDE.md §4)"
body="$(grep -vE '^[[:space:]]*#' setup.sh)"
for pat in '\[\[' 'mapfile' 'readarray' '<<<' '\$\{[A-Za-z_]+(,,|\^\^)' '\bfunction [A-Za-z_]' '=\(' 'declare -A' 'local -a'; do
  if printf '%s\n' "$body" | grep -qE -- "$pat"; then fail "setup.sh bebas bashism: /$pat/"; else pass "setup.sh bebas bashism: /$pat/"; fi
done
eq "setup.sh shebang" '#!/bin/sh' "$(head -n1 setup.sh)"
has "setup.sh set -eu" "$(cat setup.sh)" 'set -eu'

section "konvensi bash di vdev/ dan process-tag.sh (set -euo pipefail)"
for f in vdev/tools.sh .github/workflows/process-tag.sh; do
  has "$f: set -euo pipefail" "$(cat "$f")" 'set -euo pipefail'
done
has "gen-json.py: stdlib saja (tanpa pip)" "$(grep -E '^(import|from) ' .github/workflows/gen-json.py | tr '\n' ' ')" 'import'
if grep -E '^(import|from) ' .github/workflows/gen-json.py | grep -qEv '^(import|from) (fnmatch|json|os|pathlib|plistlib|re|sys)\b'; then
  fail "gen-json.py hanya mengimpor stdlib" "$(grep -E '^(import|from) ' .github/workflows/gen-json.py)"
else pass "gen-json.py hanya mengimpor stdlib"; fi

section "YAML: tanpa tab"
for f in .github/workflows/*.yml; do
  if grep -qP '\t' "$f"; then fail "tanpa tab: $f"; else pass "tanpa tab: $f"; fi
done

section "shellcheck (opsional: T4N_SHELLCHECK=1)"
if [ "${T4N_SHELLCHECK:-0}" = 1 ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck --severity=error" shellcheck --severity=error vdev/tools.sh vdev/src/*.sh vdev/DNS-check.sh .github/workflows/process-tag.sh tests/*.sh
  else fail "shellcheck diminta tetapi tidak terpasang"; fi
else echo "  (dilewati)"; fi

t4n_summary syntax
