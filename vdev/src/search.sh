# Cari template berdasarkan pkgname atau short_desc.
# Substring, case-insensitive. Template hanya dibaca grep/sed, tidak di-source.

cmd_search(){
    local q
    if [ $# -gt 0 ]; then
        q="$*"
    else
        read -rp "[+] Cari (nama paket atau deskripsi): " q
    fi
    [ -n "$q" ] || die "query kosong"
    [ -d "$TPL" ] || die "folder template tidak ada: $TPL"

    local needle="${q,,}" d t name desc hits=()
    for d in "$TPL"/*/; do
        t="$d/template"; [ -f "$t" ] || continue
        name=$(tpl_field "$t" pkgname)
        desc=$(tpl_field "$t" short_desc)
        if [[ "${name,,}" == *"$needle"* || "${desc,,}" == *"$needle"* ]]; then
            hits+=("$d")
        fi
    done

    if [ ${#hits[@]} -eq 0 ]; then
        warn "tidak ada template cocok dengan: $q"
        return 1
    fi

    local -a F=(pkgname version revision homepage maintainer distributor)
    local -a L=("package name" version revision homepage maintainer distributor)
    local W=20 i v p

    # lebar kolom nilai = nilai terpanjang, supaya border kanan sejajar
    for d in "${hits[@]}"; do
        t="$d/template"
        for i in "${!F[@]}"; do
            v=$(tpl_field "$t" "${F[$i]}"); [ -n "$v" ] || v="-"
            [ ${#v} -le "$W" ] || W=${#v}
        done
        p="${d#"$REPO_DIR"/}template"
        [ ${#p} -le "$W" ] || W=${#p}
    done

    local border=$(( W + 19 )) top bottom
    top=$(printf '%*s' "$border" '' | tr ' ' '_')
    bottom=$(printf '%*s' "$border" '' | tr ' ' '-')

    info "${#hits[@]} template cocok dengan: $q"
    for d in "${hits[@]}"; do
        t="$d/template"
        p="${d#"$REPO_DIR"/}template"
        printf '%s\n' "$top"
        for i in "${!F[@]}"; do
            v=$(tpl_field "$t" "${F[$i]}"); [ -n "$v" ] || v="-"
            printf '| %-12s : %-*s |\n' "${L[$i]}" "$W" "$v"
        done
        printf '| %-12s : %-*s |\n' "PATH" "$W" "$p"
        printf '%s\n' "$bottom"
    done
}