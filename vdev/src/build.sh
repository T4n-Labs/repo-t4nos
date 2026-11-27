# Menu paket dan arsitektur. Semua tampilan ke STDERR; hanya pilihan ke STDOUT.
# Nomor paket bersifat GLOBAL lintas halaman, jadi bisa langsung diketik.

menu_pkg(){
    local per=18 cols=3
    local all=() d
    [ -d "$TPL" ] || die "folder template tidak ada: $TPL"
    for d in "$TPL"/*/; do
        [ -f "$d/template" ] || continue
        all+=("$(basename "$d")")
    done
    local total=${#all[@]}
    [ "$total" -gt 0 ] || die "tidak ada template di $TPL"

    local pages=$(( (total + per - 1) / per )) page=0
    local start count rows r c li gi colw maxlen cell ans tok sel out

    while :; do
        start=$(( page * per ))
        count=$(( total - start ))
        [ "$count" -le "$per" ] || count=$per
        rows=$(( (count + cols - 1) / cols ))

        maxlen=0
        for (( li=0; li<count; li++ )); do
            [ ${#all[$((start+li))]} -le "$maxlen" ] || maxlen=${#all[$((start+li))]}
        done
        colw=$(( maxlen + 8 ))

        printf '[+] Template: %d total — halaman %d/%d\n' \
            "$total" "$((page+1))" "$pages" >&2
        for (( r=0; r<rows; r++ )); do
            for (( c=0; c<cols; c++ )); do
                li=$(( c * rows + r ))
                [ "$li" -lt "$count" ] || continue
                gi=$(( start + li ))
                cell="[$((gi+1))] ${all[$gi]}"
                printf '%-*s' "$colw" "$cell" >&2
            done
            printf '\n' >&2
        done

        read -rp "[?] Nomor (pisah spasi) / nama paket / n p q: " ans
        case "$ans" in
            q|Q) die "dibatalkan" ;;
            n|N) page=$(( (page + 1) % pages )); continue ;;
            p|P) page=$(( (page - 1 + pages) % pages )); continue ;;
            "")  die "tidak ada package dipilih" ;;
        esac

        out=""
        for tok in $ans; do
            if [[ $tok =~ ^[0-9]+$ ]]; then
                # 10#: paksa desimal ("08"/"09" bukan oktal); panjang dibatasi cegah overflow
                if [ ${#tok} -le 6 ] && [ "$((10#$tok))" -ge 1 ] && [ "$((10#$tok))" -le "$total" ]; then
                    sel="${all[$((10#$tok - 1))]}"
                else
                    warn "nomor $tok di luar rentang 1..$total"; continue
                fi
            elif pkg_safe "$tok" && [ -f "$TPL/$tok/template" ]; then
                sel="$tok"
            else
                warn "tidak ada template: $tok"; continue
            fi
            in_list "$out" "$sel" || out="$out $sel"
        done
        if [ -n "$out" ]; then printf '%s\n' $out; return 0; fi
        warn "tidak ada pilihan valid, ulangi"
    done
}

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

    local num
    for i in $ch; do
        num=""
        if [[ "$i" =~ ^[0-9]{1,6}$ ]]; then num=$((10#$i)); fi    # 10#: "08"/"09" bukan oktal
        if { [ -n "$num" ] && [ "$num" -eq "$(( ${#ALL[@]} + 1 ))" ]; } || [ "$i" = all ]; then
            printf '%s\n' "${sup[@]}"; return 0
        fi
        if [ -n "$num" ] && [ "$num" -ge 1 ] && [ "$num" -le ${#ALL[@]} ]; then
            n="${ALL[$((num-1))]}"
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
    local pkgs=() req=() r pkg t sup want targets x f
    local okl="" badl="" noarch=0 rc=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--arch) shift; while [ $# -gt 0 ] && [[ $1 != -* ]]; do req+=("$1"); shift; done ;;
            *) pkgs+=("$1"); shift ;;
        esac
    done

    if [ ${#pkgs[@]} -eq 0 ]; then mapfile -t pkgs < <(menu_pkg); fi
    [ ${#pkgs[@]} -gt 0 ] || die "tidak ada package"

    # Validasi SEMUA nama + template dulu, SEBELUM clone/bootstrap yang berat.
    for pkg in "${pkgs[@]}"; do
        pkg_safe "$pkg" || die "nama paket tidak aman (harus [A-Za-z0-9._+-], tidak diawali '.' atau '-'): '$pkg'"
        [ -f "$TPL/$pkg/template" ] || die "template tidak ada: $TPL/$pkg/template"
    done

    cmd_setup

    for pkg in "${pkgs[@]}"; do
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
        tpl_stage "$pkg" || { err "$pkg: FIX.sh gagal — skip"; rc=1; continue; }

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