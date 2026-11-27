# Parser template: awk/read, TIDAK pernah di-source (template dari pihak lain).
# Bisa di-source sendiri oleh CI / Let-X: . vdev/src/template.sh
#
# KONTRAK PARSER — harus identik dengan .github/workflows/gen-json.py:
#   field  : baris pertama yang cocok ^[ \t]*KEY= ; nilai = sisa baris.
#            '#' memulai komentar HANYA di luar kutip dan di awal nilai / setelah
#            spasi atau tab (seperti shell; "https://x/#a" dan "A # B" aman).
#            Backslash meloloskan karakter berikutnya (kecuali dalam kutip tunggal).
#            Lalu trim spasi/tab/CR, lalu buang SATU pasang kutip yang membungkus.
#   archs  : koma = spasi; kosong / "noarch" (saja) = semua tag; token "all" = "*";
#            token berawalan satu atau lebih "~" = negasi (jumlah "~" tidak
#            dibedakan: ~~i686 ≡ ~i686); pola glob; tanpa token positif = semua tag.

tpl_field(){
    [ -f "$1" ] || return 0
    awk -v key="$2" '
    BEGIN { sq = "\047"; dq = "\042" }
    function clean(s,   i, n, c, q, prev, out, f, l) {
        n = length(s); q = ""; prev = " "; out = ""; i = 1
        while (i <= n) {
            c = substr(s, i, 1)
            if (c == "\\" && q != sq && i < n) {
                out = out c substr(s, i + 1, 1); prev = substr(s, i + 1, 1); i += 2; continue
            }
            if (q != "") { if (c == q) q = ""; out = out c; prev = c; i++; continue }
            if (c == sq || c == dq) { q = c; out = out c; prev = c; i++; continue }
            if (c == "#" && (prev == " " || prev == "\t")) break
            out = out c; prev = c; i++
        }
        sub(/^[ \t\r]+/, "", out); sub(/[ \t\r]+$/, "", out)
        l = length(out)
        if (l >= 2) {
            f = substr(out, 1, 1)
            if ((f == sq || f == dq) && substr(out, l, 1) == f) out = substr(out, 2, l - 2)
        }
        return out
    }
    {
        if (match($0, "^[ \t]*" key "=")) { print clean(substr($0, RLENGTH + 1)); exit }
    }' "$1"
}

tpl_subpkgs(){
    local l w ws=()
    l=$(tpl_field "$1" subpackages)
    l="${l//\$\{pkgname\}/$2}"; l="${l//\$pkgname/$2}"
    read -ra ws <<< "$l" || true                 # tanpa glob terhadap isi cwd
    for w in ${ws[@]+"${ws[@]}"}; do printf '%s\n' "$w"; done
    return 0
}

# archs: kosong/noarch = 9; all = *; glob x86_64* = glibc+musl; ~token = negasi.
expand_archs(){
    local line="${1//,/ }" tok neg_t a keep toks=() pos=() neg=() out=()
    read -ra toks <<< "$line" || true            # read -a: tanpa glob terhadap cwd
    if [ ${#toks[@]} -eq 0 ] || { [ ${#toks[@]} -eq 1 ] && [ "${toks[0]}" = noarch ]; }; then
        printf '%s\n' "${ALL[@]}"; return 0
    fi
    for tok in "${toks[@]}"; do
        if [[ $tok == '~'* ]]; then
            neg_t="$tok"
            while [[ $neg_t == '~'* ]]; do neg_t="${neg_t#\~}"; done
            if [ "$neg_t" = all ]; then neg_t='*'; fi
            if [ -n "$neg_t" ]; then neg+=("$neg_t"); fi
        else
            if [ "$tok" = all ]; then tok='*'; fi
            pos+=("$tok")
        fi
    done
    for a in "${ALL[@]}"; do
        keep=0
        if [ ${#pos[@]} -eq 0 ]; then keep=1
        else for tok in "${pos[@]}"; do case "$a" in $tok) keep=1;; esac; done; fi
        if [ "$keep" = 1 ] && [ ${#neg[@]} -gt 0 ]; then
            for tok in "${neg[@]}"; do case "$a" in $tok) keep=0;; esac; done
        fi
        if [ "$keep" = 1 ]; then out+=("$a"); fi
    done
    if [ ${#out[@]} -gt 0 ]; then printf '%s\n' "${out[@]}"; fi
    return 0
}

tpl_supported(){ expand_archs "$(tpl_field "$TPL/$1/template" archs)"; }
tpl_is_noarch(){ [ "$(tpl_field "$TPL/$1/template" archs)" = noarch ]; }
