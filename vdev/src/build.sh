menu_arch(){
    echo "[+] Architecture"
    printf "    [1] %-14s [6] %s\n" x86_64 armv6l-musl
    printf "    [2] %-14s [7] %s\n" x86_64-musl armv7l
    printf "    [3] %-14s [8] %s\n" aarch64 armv7l-musl
    printf "    [4] %-14s [9] %s\n" aarch64-musl i686
    printf "    [5] %-14s [0] All\n" armv6l
    local ch i out=""
    read -rp "[?] Choose (pisah spasi, contoh: 1 3 6) [default: host]: " ch
    if [ -z "$ch" ]; then printf '%s\n' "$HOST_ARCH"; return; fi
    for i in $ch; do
        if [ "$i" = 0 ]; then printf '%s\n' "${ALL[@]}"; return; fi
        if [ "$i" -ge 1 ] 2>/dev/null && [ "$i" -le 9 ]; then
            out="$out ${ALL[$((i-1))]}"
        else
            case " ${ALL[*]} " in
                *" $i "*) out="$out $i" ;;
                *) warn "pilihan '$i' diabaikan" ;;
            esac
        fi
    done
    printf '%s\n' $out
}

cmd_build(){
    local pkgs=() req=() want=() r p
    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--arch) shift; while [ $# -gt 0 ] && [[ $1 != -* ]]; do req+=("$1"); shift; done ;;
            *) pkgs+=("$1"); shift ;;
        esac
    done
    if [ ${#pkgs[@]} -eq 0 ]; then
        info "Template tersedia:"; ls -1 "$TPL" | sed 's/^/    /'
        read -rp "[+] Package Name (pisah spasi): " p; pkgs=($p)
    fi
    [ ${#pkgs[@]} -gt 0 ] || die "tidak ada package"
    if [ ${#req[@]} -eq 0 ]; then mapfile -t req < <(menu_arch); fi
    for r in "${req[@]}"; do mapfile -t -O ${#want[@]} want < <(expand_archs "$r"); done
    [ ${#want[@]} -gt 0 ] || die "tidak ada arsitektur valid dipilih"

    cmd_setup
    local pkg t sup targets x f
    for pkg in "${pkgs[@]}"; do
        t="$TPL/$pkg/template"
        [ -f "$t" ] || die "template tidak ada: $t"
        name_safe "$pkg" || warn "$pkg: karakter di luar [A-Za-z0-9._+-] — nama asset berisiko di-rename GitHub"
        mapfile -t sup < <(tpl_supported "$pkg")
        targets=()
        for x in "${want[@]}"; do in_list "${sup[*]}" "$x" && targets+=("$x"); done
        [ ${#targets[@]} -gt 0 ] || { warn "$pkg: tidak ada irisan arch, skip"; continue; }
        info "$pkg support   : ${sup[*]}"
        info "$pkg dibuild   : ${targets[*]}"
        tpl_stage "$pkg"
        for x in "${targets[@]}"; do
            if tpl_is_noarch "$pkg" && [ "$x" != "${targets[0]}" ]; then
                info "$pkg noarch — cukup sekali build"; continue
            fi
            mapfile -t f < <(flags_for "$x")
            info "Building: xbps-src ${f[*]:-} pkg $pkg  ($x)"
            (cd "$VP" && ./xbps-src ${f[@]+"${f[@]}"} pkg "$pkg") || die "gagal: $pkg $x"
            ok "$pkg $x → $VP/hostdir/binpkgs/"
        done
    done
}