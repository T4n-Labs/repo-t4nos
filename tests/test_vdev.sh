#!/usr/bin/env bash
# Suite: vdev/ (tools.sh + src/*.sh) dan setup.sh. gh / xbps-* / id dipalsukan lewat PATH;
# xbps-src palsu; void-packages = repo git sementara. Tidak ada jaringan, tidak ada root,
# tidak ada penulisan di luar $TMP. setup.sh hanya dijalankan dengan CONF_FILE di $TMP.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib.sh
. "$HERE/lib.sh"
t4n_init vdev
cd "$T4N_REPO" || exit 2

# ───────── stub ─────────
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "${GH_LOG:-/dev/null}"
case "$1" in
  auth) [ "${GH_MODE:-}" = noauth ] && exit 1; exit 0 ;;
  api)  case "${GH_MODE:-}" in apifail) echo "HTTP 404 Not Found"; exit 1 ;; nowrite) echo false; exit 0 ;; esac; echo true ;;
  release) [ "$2" = view ] && exit "${GH_VIEW_RC:-0}"; exit 0 ;;
esac
exit 0
GH
cat > "$STUB/xbps-uhelper" <<'UH'
#!/usr/bin/env python3
import re, sys
if sys.argv[1] == "getpkgname":
    print(re.sub(r"-[^-]*$", "", sys.argv[2]))
elif sys.argv[1] == "arch":
    print("x86_64")
UH
chmod +x "$STUB/gh" "$STUB/xbps-uhelper"
export PATH="$STUB:$PATH" GH_LOG="$TMP/gh.log" XSRC_LOG="$TMP/xsrc.log"

mk_tpl() { # <dir-template> <nama> [baris tambahan...]
  local d="$1/$2"; mkdir -p "$d"; local n="$2"; shift 2
  { printf 'pkgname=%s\nversion=%s\nrevision=%s\n' "$n" "${V:-1.0}" "${REV:-1}"; [ $# -gt 0 ] && printf '%s\n' "$@"; } > "$d/template"
}
mk_vp() { # <dir>  → void-packages palsu (cmd_setup melihatnya "sudah siap")
  mkdir -p "$1/.git" "$1/srcpkgs" "$1/masterdir-x86_64" "$1/hostdir/binpkgs"
  cat > "$1/xbps-src" <<'XS'
#!/usr/bin/env bash
echo "XBPS-SRC $*" >> "$XSRC_LOG"
if [ -n "${XSRC_FAIL:-}" ]; then case " $* " in *" $XSRC_FAIL "*) exit 1 ;; esac; fi
exit 0
XS
  chmod +x "$1/xbps-src"
}
count_lines() { if [ -s "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

# ═════════════════════════════════════════════════════════════════
section "guard nama: name_safe (charset, Invarian 6) vs pkg_safe (path-safe)"
for good in tpkg 'x+y_z.1' a-b A1 'lib++' 'gtk+3'; do
  check "name_safe menerima '$good'" vdev_bash 'name_safe "$1"' "$good"
  check "pkg_safe menerima '$good'"  vdev_bash 'pkg_safe "$1"' "$good"
done
for bad in '' ' ' 'a b' 'a/b' 'a;b' 'a$b' 'tpkg~1' "a'b" 'ä' 'a:b'; do
  refuse "name_safe menolak '$bad'" vdev_bash 'name_safe "$1"' "$bad"
  refuse "pkg_safe  menolak '$bad'" vdev_bash 'pkg_safe "$1"' "$bad"
done
for tricky in . .. -x -rf .hidden; do
  check  "name_safe (hanya charset) menerima '$tricky'" vdev_bash 'name_safe "$1"' "$tricky"
  refuse "pkg_safe menolak '$tricky'" vdev_bash 'pkg_safe "$1"' "$tricky"
done

# ═════════════════════════════════════════════════════════════════
section "flags_for — tabel terdokumentasi (DEV §6), per host"
exp_x86_64='x86_64:|x86_64-musl:-A x86_64-musl|i686:-A i686|aarch64:-a aarch64|aarch64-musl:-A x86_64-musl -a aarch64-musl|armv6l:-a armv6l|armv6l-musl:-A x86_64-musl -a armv6l-musl|armv7l:-a armv7l|armv7l-musl:-A x86_64-musl -a armv7l-musl'
exp_musl='x86_64:-A x86_64|x86_64-musl:|aarch64:-A x86_64 -a aarch64|aarch64-musl:-a aarch64-musl|armv6l:-A x86_64 -a armv6l|armv6l-musl:-a armv6l-musl|armv7l:-A x86_64 -a armv7l|armv7l-musl:-a armv7l-musl'
exp_aarch64='aarch64:|aarch64-musl:-A aarch64-musl|armv7l:-a armv7l|armv7l-musl:-A aarch64-musl -a armv7l-musl'
for host in x86_64 x86_64-musl aarch64; do
  case "$host" in x86_64) exp="$exp_x86_64";; x86_64-musl) exp="$exp_musl";; aarch64) exp="$exp_aarch64";; esac
  IFS='|' read -ra pairs <<< "$exp"
  for pr in "${pairs[@]}"; do
    tgt="${pr%%:*}"; want="${pr#*:}"
    got=$(T_HOST=$host vdev_bash 'flags_for "$1" | xargs' "$tgt")
    eq "host $host → $tgt" "$want" "$got"
  done
done
refuse "flags_for menolak arsitektur tak dikenal (i686-musl)" vdev_bash 'flags_for i686-musl'

# ═════════════════════════════════════════════════════════════════
section "menu: input berawalan nol ('08'/'09') dibaca desimal, bukan oktal"
TP="$TMP/tpl-menu"; mk_tpl "$TP" t1; mk_tpl "$TP" t2
out=$(printf '08 09 1\n' | T_TPL="$TP" vdev_bash 'set -euo pipefail; menu_arch t1' 2>/dev/null | xargs)
eq "menu_arch '08 09 1' → armv7l-musl i686 x86_64" "armv7l-musl i686 x86_64" "$out"
out=$(printf '10\n' | T_TPL="$TP" vdev_bash 'menu_arch t1' 2>/dev/null | xargs)
eq "menu_arch '10' (= semua) → 9 arsitektur" "9" "$(echo "$out" | wc -w | tr -d ' ')"
out=$(printf '010\n' | T_TPL="$TP" vdev_bash 'menu_arch t1' 2>/dev/null | xargs)
eq "menu_arch '010' juga = semua" "9" "$(echo "$out" | wc -w | tr -d ' ')"
out=$(printf 'all\n' | T_TPL="$TP" vdev_bash 'menu_arch t1' 2>/dev/null | xargs)
eq "menu_arch 'all' → 9 arsitektur" "9" "$(echo "$out" | wc -w | tr -d ' ')"
err=$(printf '08 02\n' | T_TPL="$TP" vdev_bash 'set -euo pipefail; menu_pkg' 2>&1 >/dev/null | strip_ansi)
lacks "menu_pkg '08' tanpa error aritmetika" "$err" "value too great"
out=$(printf '08 02\n' | T_TPL="$TP" vdev_bash 'menu_pkg' 2>/dev/null | xargs)
eq "menu_pkg: '08' di luar rentang diabaikan, '02' → t2" "t2" "$out"
out=$(printf '2 1 t1\n' | T_TPL="$TP" vdev_bash 'menu_pkg' 2>/dev/null | xargs)
has "menu_pkg menerima nomor dan nama" "$out" "t2"
out=$(printf '../x t2\n' | T_TPL="$TP" vdev_bash 'menu_pkg' 2>/dev/null | xargs)
eq "menu_pkg menolak nama tak aman ('../x'), menerima 't2'" "t2" "$out"

# ═════════════════════════════════════════════════════════════════
section "tpl_stage + manifest (.git/t4n-staged)"
TP="$TMP/tpl-stage"; VPD="$TMP/vp-stage"; mk_tpl "$TP" ok; mk_vp "$VPD"
mkdir -p "$VPD/srcpkgs/official"; echo official > "$VPD/srcpkgs/official/template"
for bad in '../../vp-stage/srcpkgs/official' '..' '.' '-x' '.hidden' 'a/b' ''; do
  T_TPL="$TP" T_VP="$VPD" vdev_bash 'tpl_stage "$1"' "$bad" >/dev/null 2>&1; rc=$?
  if [ $rc -ne 0 ] && [ -f "$VPD/srcpkgs/official/template" ]; then pass "tpl_stage menolak '$bad' (rc=$rc), srcpkgs utuh"; else fail "tpl_stage '$bad'" "rc=$rc"; fi
done
refuse "tpl_stage menolak template yang tidak ada" env T_TPL="$TP" T_VP="$VPD" bash -c "$(t4n_src)"'tpl_stage nope'
T_TPL="$TP" T_VP="$VPD" vdev_bash 'tpl_stage ok' >/dev/null 2>&1
check "tpl_stage 'ok' menyalin template" test -f "$VPD/srcpkgs/ok/template"
eq "manifest memuat 'ok'" "ok" "$(cat "$VPD/.git/t4n-staged")"
T_TPL="$TP" T_VP="$VPD" vdev_bash 'tpl_stage ok' >/dev/null 2>&1
eq "manifest tidak menggandakan entri" "1" "$(count_lines "$VPD/.git/t4n-staged")"

# ═════════════════════════════════════════════════════════════════
section "cmd_build: validasi SEBELUM cmd_setup (clone/bootstrap)"
TP="$TMP/tpl-b1"; mk_tpl "$TP" good
out=$(T_TPL="$TP" vdev_bash 'set -euo pipefail; cmd_setup(){ echo SETUP_DIPANGGIL; }; cmd_build paket-typo -a x86_64' 2>&1 | strip_ansi)
lacks "typo nama → cmd_setup TIDAK dipanggil" "$out" "SETUP_DIPANGGIL"
has   "typo nama → pesan 'template tidak ada'" "$out" "template tidak ada"
out=$(T_TPL="$TP" vdev_bash 'set -euo pipefail; cmd_setup(){ echo SETUP_DIPANGGIL; }; cmd_build good ../x -a x86_64' 2>&1 | strip_ansi)
lacks "satu nama tak aman di antara yang valid → setup tidak dipanggil" "$out" "SETUP_DIPANGGIL"
has   "pesan 'tidak aman'" "$out" "tidak aman"
out=$(T_TPL="$TP" vdev_bash 'set -euo pipefail; cmd_setup(){ echo SETUP_DIPANGGIL; }; cmd_build good -a x86_64' 2>&1 | strip_ansi)
has "nama valid → cmd_setup dipanggil" "$out" "SETUP_DIPANGGIL"

section "cmd_build: integrasi dengan xbps-src palsu"
TP="$TMP/tpl-b2"; VPD="$TMP/vp-b2"; mk_vp "$VPD"
mk_tpl "$TP" t1; mk_tpl "$TP" t2 'archs=noarch'; mk_tpl "$TP" t3 'archs=x86_64'
run_build() { : > "$XSRC_LOG"; T_TPL="$TP" T_VP="$VPD" vdev_bash 'cmd_build "$@"' "$@" 2>&1 | strip_ansi; return "${PIPESTATUS[0]}"; }
out=$(run_build t1 -a x86_64 aarch64); rc=$?
eq "t1 -a x86_64 aarch64 → rc 0" 0 "$rc"
eq "xbps-src: native lalu cross" $'XBPS-SRC pkg t1\nXBPS-SRC -a aarch64 pkg t1' "$(cat "$XSRC_LOG")"
check "template di-stage ke srcpkgs/t1" test -f "$VPD/srcpkgs/t1/template"
run_build t1 -a all >/dev/null
eq "-a all → 9 build" 9 "$(count_lines "$XSRC_LOG")"
run_build t1 -a 'x86_64*' >/dev/null
eq "-a 'x86_64*' → glibc + musl" $'XBPS-SRC pkg t1\nXBPS-SRC -A x86_64-musl pkg t1' "$(cat "$XSRC_LOG")"
run_build t2 -a x86_64 aarch64 i686 >/dev/null
eq "archs=noarch → SATU build untuk banyak target" $'XBPS-SRC pkg t2' "$(cat "$XSRC_LOG")"
out=$(run_build t3 -a aarch64); rc=$?
eq "arsitektur di luar archs → tidak ada build" 0 "$(count_lines "$XSRC_LOG")"
has "…dengan pesan 'tidak ada irisan arch'" "$out" "tidak ada irisan arch"
eq "…dan rc 0" 0 "$rc"
: > "$XSRC_LOG"
out=$(XSRC_FAIL=aarch64 T_TPL="$TP" T_VP="$VPD" vdev_bash 'cmd_build t1 -a x86_64 aarch64 i686' 2>&1 | strip_ansi; exit "${PIPESTATUS[0]}"); rc=$?
eq "satu arsitektur gagal → rc 1" 1 "$rc"
eq "…tetapi arsitektur lain tetap dibangun (3 percobaan)" 3 "$(count_lines "$XSRC_LOG")"
has "…dan ringkasan melaporkan kegagalan" "$out" "aarch64"

# ═════════════════════════════════════════════════════════════════
section "cmd_sync: salin, perbarui, pulihkan upstream, bersihkan (repo git sungguhan)"
TP="$TMP/tpl-sync"; VPD="$TMP/vp-sync"; mkdir -p "$VPD/srcpkgs/official" "$VPD/srcpkgs/keep" "$TP"
( cd "$VPD" && git init -q . && echo upstream > srcpkgs/official/template && echo k > srcpkgs/keep/template \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
mk_tpl "$TP" new1; mk_tpl "$TP" official 'short_desc="overlay"'; mkdir -p "$TP/bad name"; echo 'pkgname=bad' > "$TP/bad name/template"
sync() { T_TPL="$TP" T_VP="$VPD" vdev_bash 'cmd_sync' 2>&1 | strip_ansi; }
out=$(sync)
check "template baru disalin"                 test -f "$VPD/srcpkgs/new1/template"
check "overlay menimpa nama yang ada di upstream" grep -q overlay "$VPD/srcpkgs/official/template"
check "nama tidak aman dilewati"              test ! -e "$VPD/srcpkgs/bad name"
has   "…dengan peringatan"                     "$out" "tidak aman"
eq "manifest berisi new1 + official" $'new1\nofficial' "$(sort "$VPD/.git/t4n-staged")"
out=$(sync); has "sync kedua: tidak ada yang berubah (0 template)" "$out" "0 template disinkronkan"
echo 'extra=1' >> "$TP/new1/template"; out=$(sync)
check "template berubah → disalin ulang" grep -q 'extra=1' "$VPD/srcpkgs/new1/template"
rm -rf "$TP/official"; out=$(sync)
eq "official dihapus dari pkg-template → resep UPSTREAM dipulihkan" "upstream" "$(cat "$VPD/srcpkgs/official/template")"
has "…dengan pesan pemulihan" "$out" "dipulihkan"
rm -rf "$TP/new1"; out=$(sync)
check "new1 (bukan upstream) dibersihkan dari srcpkgs" test ! -e "$VPD/srcpkgs/new1"
eq "manifest kosong setelah semua dibersihkan" "0" "$(count_lines "$VPD/.git/t4n-staged")"
check "resep upstream lain tidak tersentuh" grep -qx k "$VPD/srcpkgs/keep/template"
echo 'tampered' > "$VPD/.git/t4n-staged"; mkdir -p "$VPD/srcpkgs/victim"; echo v > "$VPD/srcpkgs/victim/template"
printf '../victim\n..\n' > "$VPD/.git/t4n-staged"; sync >/dev/null
check "manifest yang dirusak tidak bisa memicu penghapusan di luar nama aman" test -f "$VPD/srcpkgs/victim/template"

# ═════════════════════════════════════════════════════════════════
section "route_tags di bawah set -e"
out=$(vdev_bash 'set -euo pipefail; tags=$(route_tags x.aarch64.xbps aarch64 "x86_64 i686") || tags=""; if [ -z "$tags" ]; then echo LANJUT_KE_WARN; fi; tags=$(route_tags x.noarch.xbps noarch "x86_64 i686"); echo "noarch=$(echo $tags)"; tags=$(route_tags x.i686.xbps i686 "x86_64 i686"); echo "i686=$tags"')
has "arch di luar archs → skrip lanjut (bukan mati)" "$out" "LANJUT_KE_WARN"
has "noarch → fanout ke semua tag yang didukung"     "$out" "noarch=x86_64 i686"
has "arch tepat → satu tag"                           "$out" "i686=i686"
eq  "route_tags selalu return 0" "0" "$(vdev_bash 'route_tags x aarch64 "x86_64" >/dev/null; echo $?')"

# ═════════════════════════════════════════════════════════════════
section "cmd_upload: gh belum login ≠ API gagal ≠ tanpa izin push"
for m in noauth apifail nowrite ok; do
  out=$(GH_MODE=$m vdev_bash 'cmd_upload tpkg < /dev/null; echo "rc=$?"' 2>&1 | strip_ansi)
  case $m in
    noauth)  has "noauth → pesan 'belum terautentikasi'" "$out" "belum terautentikasi"; has "noauth → rc=1" "$out" "rc=1"
             lacks "noauth → bukan pesan izin" "$out" "akses write" ;;
    apifail) has "apifail → 'gagal memeriksa izin'" "$out" "gagal memeriksa izin"; has "apifail → rc=1" "$out" "rc=1"
             lacks "apifail → tidak dianggap tanpa izin" "$out" "Tidak punya akses write"; has "apifail → pesan API disertakan" "$out" "404" ;;
    nowrite) has "nowrite → 'Tidak punya akses write'" "$out" "Tidak punya akses write"; has "nowrite → rc=0" "$out" "rc=0"
             lacks "nowrite → bukan pesan auth" "$out" "belum terautentikasi" ;;
  esac
done

section "cmd_upload: routing, --clobber, trigger sekali, tanpa .sig2 (Invarian 8)"
TP="$TMP/tpl-up"; VPD="$TMP/vp-up"; mk_vp "$VPD"; BP="$VPD/hostdir/binpkgs"
mk_tpl "$TP" t1 'subpackages="${pkgname}-devel"' 'archs="x86_64* aarch64*"'; mk_tpl "$TP" t2 'archs=noarch'
for f in t1-1.0_1.x86_64.xbps t1-1.0_1.aarch64-musl.xbps t1-devel-1.0_1.x86_64.xbps t1-0.9_1.x86_64.xbps \
         other-1.0_1.x86_64.xbps t1-1.0_1.i686.xbps 't1-1.0_1.x86_64~x.xbps' t2-1.0_1.noarch.xbps; do : > "$BP/$f"; done
: > "$BP/t1-1.0_1.x86_64.xbps.sig2"          # .sig2 lokal: tidak boleh pernah diunggah
: > "$GH_LOG"
out=$(GH_VIEW_RC=1 T_TPL="$TP" T_VP="$VPD" vdev_bash 'cmd_upload t1 t2 < /dev/null; echo "rc=$?"' 2>&1 | strip_ansi)
has "rc=0" "$out" "rc=0"
ups=$(grep '^release upload' "$GH_LOG")
has   "t1 x86_64 → tag x86_64"                 "$ups" "release upload x86_64 $BP/t1-1.0_1.x86_64.xbps"
has   "t1 aarch64-musl → tag aarch64-musl"     "$ups" "release upload aarch64-musl $BP/t1-1.0_1.aarch64-musl.xbps"
has   "subpackage t1-devel ikut"               "$ups" "t1-devel-1.0_1.x86_64.xbps"
lacks "versi lain (0.9_1) dilewati"            "$ups" "t1-0.9_1"
lacks "paket lain dilewati"                    "$ups" "other-1.0_1"
lacks "arch di luar archs (i686) dilewati"     "$ups" "t1-1.0_1.i686"
lacks "nama tak aman dilewati"                 "$ups" "x86_64~x"
lacks ".sig2 TIDAK pernah diunggah"            "$ups" "sig2"
has   "semua upload memakai --clobber"         "$(grep -c -- '--clobber' <<<"$ups")" "$(grep -c '' <<<"$ups")"
eq    "noarch → fanout ke 9 tag" 9 "$(grep -c 'release upload .* t2-1.0_1.noarch.xbps\|release upload .*/t2-1.0_1.noarch.xbps' <<<"$ups")"
has   "release dibuat bila belum ada (--prerelease)" "$(grep '^release create' "$GH_LOG" | head -1)" "--prerelease"
eq    "workflow di-trigger TEPAT sekali" 1 "$(grep -c '^workflow run' "$GH_LOG")"
has   "…memuat daftar tag yang tersentuh" "$(grep '^workflow run' "$GH_LOG")" "process.yml -R T4n-Labs/repo-t4nos -f tags="
has   "…termasuk x86_64 dan aarch64-musl" "$(grep '^workflow run' "$GH_LOG")" "x86_64"
out=$(T_TPL="$TP" T_VP="$TMP/vp-kosong" vdev_bash 'mkdir -p "$VP/hostdir/binpkgs"; : > "$GH_LOG"; cmd_upload t1 < /dev/null' 2>&1 | strip_ansi)
has "tanpa biner → peringatan 'tidak ada biner cocok'" "$out" "tidak ada biner cocok"
eq  "…dan tanpa trigger workflow" 0 "$(grep -c '^workflow run' "$GH_LOG")"
out=$(T_TPL="$TP" T_VP="$VPD" vdev_bash 'cmd_upload ../x < /dev/null' 2>&1 | strip_ansi)
has "nama tak aman di -u → dilewati dengan peringatan" "$out" "tidak aman"

# ═════════════════════════════════════════════════════════════════
section "git_offer: aman tanpa TTY, selalu return 0"
out=$(vdev_bash 'set -euo pipefail; git_offer; echo SELESAI_NORMAL' < /dev/null 2>&1 | strip_ansi)
has "stdin kosong (EOF) → lanjut normal" "$out" "SELESAI_NORMAL"
stubgit='git(){ echo "[git $*]"; if [ "$3" = remote ]; then echo "$ORIGIN"; fi; }; gh(){ echo "[gh $*]"; }; REPO_DIR=/nonexistent; '
out=$(printf 'y\nn\n' | ORIGIN=git@github.com:fork/repo-t4nos.git vdev_bash "${stubgit}"'set -euo pipefail; git_offer; echo "rc=$?"' 2>&1 | strip_ansi)
has   "jawab y lalu n → git push dijalankan" "$out" "[git -C /nonexistent push]"
lacks "…PR tidak dibuat"                     "$out" "gh pr create"
has   "…rc=0 setelah menolak PR"             "$out" "rc=0"
out=$(printf 'y\ny\n' | ORIGIN=git@github.com:fork/repo-t4nos.git vdev_bash "${stubgit}"'git_offer' 2>&1 | strip_ansi)
has "origin fork + y/y → gh pr create ke upstream" "$out" "[gh pr create --repo T4n-Labs/repo-t4nos --fill]"
out=$(printf 'y\ny\n' | ORIGIN=git@github.com:T4n-Labs/repo-t4nos.git vdev_bash "${stubgit}"'git_offer' 2>&1 | strip_ansi)
lacks "origin = repo resmi → tidak menawarkan PR" "$out" "gh pr create"
out=$(printf 'n\n' | vdev_bash "${stubgit}"'git_offer' 2>&1 | strip_ansi)
lacks "jawab n → tidak push" "$out" "push"
out=$(printf 'y\n\n' | ORIGIN=git@github.com:fork/repo-t4nos.git vdev_bash "${stubgit}"'git(){ if [ "$3" = push ]; then return 1; fi; echo "$ORIGIN"; }; git_offer; echo "rc=$?"' 2>&1 | strip_ansi)
has "push gagal → hanya peringatan, rc=0" "$out" "rc=0"

# ═════════════════════════════════════════════════════════════════
section "modul vdev/src: di-source tanpa side-effect; sumber kebenaran daftar tag"
cwd="$TMP/srcwd"; mkdir -p "$cwd"
for m in vdev/src/*.sh; do
  out=$(cd "$cwd" && bash -c ". \"$T4N_REPO/$m\"" 2>&1); rc=$?
  eq "source $m: rc=0 tanpa keluaran" "0|" "$rc|$out"
done
eq "tidak ada berkas dibuat saat source" "0" "$(ls -A "$cwd" | wc -l | tr -d ' ')"
eq "ALL = 9 tag berurutan" "x86_64 x86_64-musl aarch64 aarch64-musl armv6l armv6l-musl armv7l armv7l-musl i686" "$(vdev_bash 'echo "${ALL[*]}"')"

# ═════════════════════════════════════════════════════════════════
section "tools.sh: dispatcher, symlink, search"
out=$(bash vdev/tools.sh -h 2>&1 | strip_ansi); rc=$?
has "-h memuat daftar tag" "$out" "Tag : x86_64 x86_64-musl"
eq  "-h rc 0" 0 "$rc"
out=$(bash vdev/tools.sh --bogus 2>&1 | strip_ansi); rc=${PIPESTATUS[0]}
has "opsi tak dikenal → pesan" "$out" "opsi tidak dikenal"
eq  "opsi tak dikenal → rc 1" 1 "$(bash vdev/tools.sh --bogus >/dev/null 2>&1; echo $?)"
ln -s "$T4N_REPO/vdev/tools.sh" "$TMP/tools"; ln -s "$TMP/tools" "$TMP/tools2"
out=$(bash "$TMP/tools" -h 2>&1 | strip_ansi); has "lewat symlink: modul src/ tetap ditemukan" "$out" "Tag : x86_64"
out=$(bash "$TMP/tools2" -h 2>&1 | strip_ansi); has "lewat symlink bertingkat" "$out" "Tag : x86_64"
out=$(bash vdev/tools.sh search tpkg 2>&1 | strip_ansi); rc=$?
has "search tpkg → ditemukan" "$out" "tpkg"; eq "search tpkg rc 0" 0 "$rc"
out=$(bash vdev/tools.sh search TPKG 2>&1 | strip_ansi); has "search tak peka huruf besar" "$out" "tpkg"
out=$(bash vdev/tools.sh search 'package manager' 2>&1 | strip_ansi); has "search juga mencari short_desc" "$out" "tpkg"
bash vdev/tools.sh search zzz-tidak-ada-xyz >/dev/null 2>&1; eq "search tanpa hasil → rc 1" 1 "$?"
out=$(bash vdev/tools.sh search 'zzz-tidak-ada-xyz' 2>&1 | strip_ansi); has "…dengan peringatan" "$out" "tidak ada template cocok"

# ═════════════════════════════════════════════════════════════════
section "setup.sh (sandbox: id/xbps-* palsu, CONF_FILE di \$TMP; tidak menyentuh /etc)"
SB="$TMP/setupbin"; mkdir -p "$SB"
printf '#!/bin/sh\necho "${T_UID:-0}"\n' > "$SB/id"
printf '#!/bin/sh\necho "${T_XARCH:-x86_64}"\n' > "$SB/xbps-uhelper"
printf '#!/bin/sh\necho "xbps-install $*" >> "$XI_LOG"\nexit "${XI_RC:-0}"\n' > "$SB/xbps-install"
chmod +x "$SB"/*
export XI_LOG="$TMP/xi.log"
setup() { # args… ; env var: T_UID T_XARCH XI_RC T4N_* CONF_FILE
  PATH="$SB:$PATH" CONF_FILE="${CONF_FILE:-$TMP/conf/10-t4nos.conf}" sh "$T4N_REPO/setup.sh" "$@" 2>&1
}
out=$(setup -h); rc=$?; has "-h menampilkan bantuan" "$out" "Pemakaian: sudo sh setup.sh"; eq "-h rc 0" 0 "$rc"
out=$(setup help); has "help = -h" "$out" "update [opsi]"
out=$(setup bogus); rc=$?; has "perintah tak dikenal → pesan" "$out" "Perintah tidak dikenal"
setup bogus >/dev/null; eq "perintah tak dikenal → rc 1" 1 "$?"
rm -f "$TMP/conf/10-t4nos.conf"; : > "$XI_LOG"
out=$(T_UID=1000 setup); rc=$?
has "non-root → minta sudo" "$out" "Jalankan dengan sudo"; eq "non-root rc 1" 1 "$rc"
check "non-root: konfigurasi TIDAK ditulis" test ! -e "$TMP/conf/10-t4nos.conf"
out=$(T_XARCH=x86_64-musl T4N_ASSUME_YES=1 setup); rc=$?
eq "ASSUME_YES rc 0" 0 "$rc"
eq "konfigurasi ditulis ke CONF_FILE (repository=BASE/arch)" "repository=https://repo.t4nlabs.web.id/x86_64-musl" "$(cat "$TMP/conf/10-t4nos.conf")"
has "arsitektur + libc terdeteksi" "$out" "x86_64-musl (musl)"
has "fingerprint resmi ditampilkan" "$out" "63:35:0c:65:0d:a5:f1:87:52:7e:c5:e9:13:3a:d6:2a"
eq  "ASSUME_YES → xbps-install -S -y" "xbps-install -S -y" "$(cat "$XI_LOG")"
: > "$XI_LOG"; CONF_FILE="$TMP/conf2/a.conf" T4N_BASE=https://mirror.example/rel T4N_ASSUME_YES=1 T_XARCH=aarch64 setup >/dev/null
eq "T4N_BASE + CONF_FILE dihormati (dan mkdir -p direktorinya)" "repository=https://mirror.example/rel/aarch64" "$(cat "$TMP/conf2/a.conf")"
echo "isi lama" > "$TMP/conf/10-t4nos.conf"; T4N_ASSUME_YES=1 setup >/dev/null
eq "setup menimpa konfigurasi lama" "repository=https://repo.t4nlabs.web.id/x86_64" "$(cat "$TMP/conf/10-t4nos.conf")"
rm -rf "$TMP/conf3"
out=$(CONF_FILE="$TMP/conf3/x.conf" T_XARCH=i686-musl T4N_ASSUME_YES=1 setup); rc=$?
has "i686-musl → 'belum disediakan'" "$out" "belum disediakan"; eq "i686-musl rc 1" 1 "$rc"
out=$(CONF_FILE="$TMP/conf3/x.conf" T_XARCH=riscv64 T4N_ASSUME_YES=1 setup)
has "arsitektur asing → 'tidak didukung'" "$out" "tidak didukung"
check "arsitektur tak didukung: konfigurasi tidak ditulis" test ! -e "$TMP/conf3/x.conf"
for a in x86_64 x86_64-musl aarch64 aarch64-musl armv6l armv6l-musl armv7l armv7l-musl i686; do
  rm -f "$TMP/conf3/x.conf"; CONF_FILE="$TMP/conf3/x.conf" T_XARCH=$a T4N_ASSUME_YES=1 setup >/dev/null
  eq "arsitektur $a diterima" "repository=https://repo.t4nlabs.web.id/$a" "$(cat "$TMP/conf3/x.conf" 2>/dev/null)"
done
if command -v setsid >/dev/null 2>&1; then
  : > "$XI_LOG"; out=$(PATH="$SB:$PATH" CONF_FILE="$TMP/conf4/x.conf" setsid -w sh "$T4N_REPO/setup.sh" 2>&1 < /dev/null); rc=$?
  has "tanpa TTY & tanpa ASSUME_YES → berhenti dengan petunjuk" "$out" "Tidak ada tty"; eq "…rc 1" 1 "$rc"
  eq  "…xbps-install tidak dipanggil" 0 "$(count_lines "$XI_LOG")"
else echo "  (setsid tidak ada: uji 'tanpa TTY' dilewati)"; fi
rm -f "$TMP/conf/10-t4nos.conf"
out=$(setup update); rc=$?
has "update tanpa konfigurasi → 'belum dipasang'" "$out" "belum dipasang"; eq "…rc 1" 1 "$rc"
echo "repository=x" > "$TMP/conf/10-t4nos.conf"; : > "$XI_LOG"
out=$(setup update -y --foo < /dev/null); rc=$?
eq "update meneruskan opsi ke xbps-install -Su" "xbps-install -Su -y --foo" "$(cat "$XI_LOG")"; eq "update rc 0" 0 "$rc"
out=$(XI_RC=1 setup update < /dev/null); rc=$?
has "update gagal → petunjuk 'xbps-install -u xbps'" "$out" "xbps-install -u xbps"; eq "update gagal rc 1" 1 "$rc"
out=$(T_UID=1000 setup update); has "update non-root → minta sudo" "$out" "Jalankan dengan sudo"
NOX="$TMP/noxbps"; mkdir -p "$NOX"; printf '#!/bin/sh\necho 0\n' > "$NOX/id"; chmod +x "$NOX/id"
if ( PATH="/usr/bin:/bin" command -v xbps-uhelper >/dev/null 2>&1 ); then echo "  (xbps-uhelper ada di sistem: uji 'xbps tidak ada' dilewati)"
else out=$(PATH="$NOX:/usr/bin:/bin" CONF_FILE="$TMP/conf5/x" sh "$T4N_REPO/setup.sh" 2>&1); has "tanpa xbps → 'Void/T4n OS saja'" "$out" "Void/T4n OS saja"; fi

t4n_summary vdev
