# Menu arsitektur PER PAKET, difilter sesuai archs template.
# Nomor tetap: [1]..[9] mengikuti urutan ALL, [10] = all.
# Semua tampilan ke stderr; HANYA pilihan akhir ke stdout.

menu_arch(){
    local pkg="$1" sup=() i a n def ch out=""
    mapfile -t sup < <(tpl_supported "$pkg")
    [ ${#sup[@]} -gt 0 ] || die "$pkg: tidak ada arsitektur yang didukung"

    echo "[+] Architecture — $pkg" >&2
    i=1
    for a in "${ALL[@]}"; do
        if in_list "${sup[*]}" "$a"; then printf '    [%d] %s\n' "$i" "$a" >&2; fi
        i=$((i+1))
    done
    printf '    [%d] all\n' "$(( ${#ALL[@]} + 1 ))" >&2

    if in_list "${sup[*]}" "$HOST_ARCH"; then def="$HOST_ARCH"; else def="${sup[0]}"; fi
    read -rp "[?] Choose (pisah spasi, contoh: 1 3 6) [default: $def]: " ch
    if [ -z "$ch" ]; then printf '%s\n' "$def"; return 0; fi

    for i in $ch; do
        if [ "$i" = "$(( ${#ALL[@]} + 1 ))" ] || [ "$i" = all ]; then
            printf '%s\n' "${sup[@]}"; return 0
        fi
        if [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le ${#ALL[@]} ]; then
            n="${ALL[$((i-1))]}"
            if in_list "${sup[*]}" "$n"; then
                in_list "$out" "$n" || out="$out $n"
            else
                warn "[$i] $n tidak didukung $pkg"
            fi
        elif in_list "${sup[*]}" "$i"; then
            in_list "$out" "$i" || out="$out $i"
        else
            warn "pilihan '$i' diabaikan"
        fi
    done
    [ -n "$out" ] || die "tidak ada arsitektur valid dipilih"
    printf '%s\n' $out
}

build_summary(){
    local pkg="$1" okl="$2" badl="$3" nok nbad
    nok=$(printf '%s' "$okl" | wc -w)
    nbad=$(printf '%s' "$badl" | wc -w)
    printf '\n' >&2
    printf '=== %s ===\n' "$pkg" >&2
    printf "${G}[+]${N} Success : %d Archs\n" "$nok" >&2
    printf "${G}[+]${N} %s\n" "${okl:-None}" >&2
    printf "${R}[-]${N} Failed : %d Archs\n" "$nbad" >&2
    printf "${R}[-]${N} %s\n" "${badl:-None}" >&2
}

cmd_build(){
    local pkgs=() req=() p r pkg t sup want targets x f
    local okl="" badl="" noarch=0 rc=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--arch) shift; while [ $# -gt 0 ] && [[ $1 != -* ]]; do req+=("$1"); shift; done ;;
            *) pkgs+=("$1"); shift ;;
        esac
    done

    if [ ${#pkgs[@]} -eq 0 ]; then
        info "Template tersedia:"
        ls -1 "$TPL" | sed 's/^/    /' >&2
        read -rp "[+] Package Name (pisah spasi): " p
        pkgs=($p)
    fi
    [ ${#pkgs[@]} -gt 0 ] || die "tidak ada package"

    cmd_setup

    for pkg in "${pkgs[@]}"; do
        t="$TPL/$pkg/template"
        [ -f "$t" ] || die "template tidak ada: $t"
        name_safe "$pkg" || warn "$pkg: karakter di luar [A-Za-z0-9._+-] — nama asset berisiko di-rename GitHub"

        mapfile -t sup < <(tpl_supported "$pkg")
        [ ${#sup[@]} -gt 0 ] || { warn "$pkg: archs kosong setelah ekspansi, skip"; continue; }

        want=()
        if [ ${#req[@]} -gt 0 ]; then
            for r in "${req[@]}"; do
                mapfile -t -O ${#want[@]} want < <(expand_archs "$r")
            done
        else
            mapfile -t want < <(menu_arch "$pkg")
        fi

        targets=()
        for x in "${want[@]}"; do
            in_list "${sup[*]}" "$x" || continue
            in_list "${targets[*]}" "$x" || targets+=("$x")
        done
        [ ${#targets[@]} -gt 0 ] || { warn "$pkg: tidak ada irisan arch, skip"; continue; }

        info "$pkg support : ${sup[*]}"
        info "$pkg dibuild : ${targets[*]}"
        tpl_stage "$pkg"

        okl=""; badl=""; noarch=0
        if tpl_is_noarch "$pkg"; then
            noarch=1
            info "$pkg noarch — satu build untuk ${#targets[@]} tag"
        fi

        for x in "${targets[@]}"; do
            if [ "$noarch" = 1 ] && [ "$x" != "${targets[0]}" ]; then continue; fi
            f=()
            mapfile -t f < <(flags_for "$x")
            info "Building: xbps-src ${f[*]:-} pkg $pkg  ($x)"
            if (cd "$VP" && ./xbps-src ${f[@]+"${f[@]}"} pkg "$pkg"); then
                ok "$pkg $x → $VP/hostdir/binpkgs/"
                if [ "$noarch" = 1 ]; then okl="${targets[*]}"; else okl="$okl $x"; fi
            else
                err "gagal: $pkg $x — lanjut ke arsitektur berikutnya"
                if [ "$noarch" = 1 ]; then badl="${targets[*]}"; else badl="$badl $x"; fi
                rc=1
            fi
        done

        build_summary "$pkg" "${okl# }" "${badl# }"
    done

    return $rc
}