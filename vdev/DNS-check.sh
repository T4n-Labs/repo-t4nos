#!/usr/bin/env bash
# Uji https://repo.t4nlabs.web.id tanpa biner xbps. Hanya GET/HEAD/POST ke domain,
# tidak mengubah apa pun. Jalankan dari mesin mana saja yang punya curl.
#
#   bash check-domain.sh                    # uji DNS, TLS, dan perilaku Worker
#   PROBE=ping.txt bash check-domain.sh     # + uji proxy 200/Range ke file uji di release
#
# Variabel (opsional): BASE WEB GH TAG PROBE
set -u

BASE="${BASE:-https://repo.t4nlabs.web.id}"
WEB="${WEB:-https://repo-web.t4nlabs.web.id/}"
GH="${GH:-https://github.com/T4n-Labs/repo-t4nos/releases}"
TAG="${TAG:-x86_64-musl}"
PROBE="${PROBE:-}"

pass=0; fail=0
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; N='\033[0m'

check() { # nama harapan dapat
    if [ "$2" = "$3" ]; then
        printf "${G}PASS${N}  %s\n" "$1"; pass=$((pass+1))
    else
        printf "${R}FAIL${N}  %s (harapan: %s, dapat: %s)\n" "$1" "$2" "$3"; fail=$((fail+1))
    fi
}
info() { printf "${Y}INFO${N}  %s\n" "$*"; }

code() { curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$@"; }
loc()  { curl -s -I --max-time 20 "$1" | tr -d '\r' | awk -F': ' 'tolower($1)=="location"{print $2}'; }

host="${BASE#*://}"; host="${host%%/*}"
zone="${host#*.}"

echo "== 1. DNS =="
if [[ $BASE == https://* ]] && command -v dig >/dev/null 2>&1; then
    ns=$(dig +short NS "$zone" | tr '\n' ' ')
    case "$ns" in *cloudflare.com*) r=cloudflare ;; *) r="${ns:-kosong}" ;; esac
    check "NS $zone di Cloudflare" cloudflare "$r"

    a=$(dig +short A "$host" | tr '\n' ' ')
    cn=$(dig +short CNAME "$host" | tr '\n' ' ')
    if [ -z "$a" ]; then r=kosong
    elif printf '%s %s' "$a" "$cn" | grep -qE '185\.199\.|github\.io'; then r=github-pages
    else r=ok; fi
    check "$host tidak mengarah ke GitHub Pages" ok "$r"
else
    info "dig tidak ada / BASE bukan https, uji DNS dilewati"
fi

echo "== 2. TLS + perilaku Worker =="
check "GET /  -> 302"                         302 "$(code "$BASE/")"
check "GET /  -> Location = website"          "$WEB" "$(loc "$BASE/")"
check "GET /$TAG -> 302"                      302 "$(code "$BASE/$TAG")"
check "GET /$TAG -> Location = halaman release" "$GH/tag/$TAG" "$(loc "$BASE/$TAG")"
check "GET /$TAG/ (slash akhir) -> 302"       302 "$(code "$BASE/$TAG/")"
check "tag tidak dikenal -> 404"              404 "$(code "$BASE/nope/file.txt")"
check "nama file tidak valid -> 404"          404 "$(code "$BASE/$TAG/a%20b")"
check "POST -> 405"                           405 "$(code -X POST "$BASE/$TAG/x")"

echo "== 3. Proxy ke release =="
rc=$(code -I "$BASE/$TAG/$TAG-repodata")
case "$rc" in
    200) info "$TAG-repodata ada (HTTP 200): repo sudah berisi paket" ;;
    404) info "$TAG-repodata belum ada (404): normal sebelum paket pertama diproses" ;;
    *)   check "HEAD $TAG-repodata -> 200 atau 404" "200|404" "$rc" ;;
esac

if [ -n "$PROBE" ]; then
    check "HEAD $PROBE -> 200"  200 "$(code -I "$BASE/$TAG/$PROBE")"
    check "GET  $PROBE -> 200"  200 "$(code "$BASE/$TAG/$PROBE")"
    check "Range 0-3 -> 206"    206 "$(code -r 0-3 "$BASE/$TAG/$PROBE")"

    via=$(curl -s --max-time 30 "$BASE/$TAG/$PROBE" | sha256sum | cut -d' ' -f1)
    direct=$(curl -sL --max-time 30 "$GH/download/$TAG/$PROBE" | sha256sum | cut -d' ' -f1)
    check "isi lewat domain = isi langsung dari GitHub" "$direct" "$via"
else
    info "PROBE kosong: uji proxy 200/Range dilewati (lihat petunjuk membuat file uji)"
fi

echo
printf "Hasil: ${G}%d lulus${N}, ${R}%d gagal${N}\n" "$pass" "$fail"
[ "$fail" -eq 0 ]