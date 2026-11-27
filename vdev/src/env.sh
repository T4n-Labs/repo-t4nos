# Environment build: clone, bootstrap, sync template, flag xbps-src.

cmd_setup(){
    # 1. Clone atau update void-packages
    if [ -d "$VP/.git" ]; then
        ok "void-packages sudah ada"
        if [ -f "$VP/.git/shallow" ]; then
            info "Clone shallow terdeteksi — mengambil history penuh (bisa lama)..."
            (cd "$VP" && git fetch --unshallow) || warn "unshallow gagal, lanjut dengan yang ada"
        fi
    else
        info "Clone void-packages (full history, bisa >1 GB dan lama)..."
        git clone https://github.com/void-linux/void-packages "$VP"
    fi

    # 2. Bootstrap semua 9 arsitektur
    local arch ok_count=0 fail_count=0 skip_count=0
    for arch in "${ALL[@]}"; do
        local mdir="$VP/masterdir-$arch"
        if [ -d "$mdir" ]; then
            info "masterdir-$arch sudah ada — dilewati"
            skip_count=$((skip_count+1))
            continue
        fi
        info "binary-bootstrap untuk $arch ..."
        if (cd "$VP" && ./xbps-src -A "$arch" binary-bootstrap); then
            ok "masterdir-$arch siap"
            ok_count=$((ok_count+1))
        else
            warn "masterdir-$arch gagal di-bootstrap"
            fail_count=$((fail_count+1))
        fi
    done

    # 3. Enable restricted packages
    if ! grep -q "^XBPS_ALLOW_RESTRICTED=yes" "$VP/etc/conf" 2>/dev/null; then
        mkdir -p "$VP/etc"
        echo "XBPS_ALLOW_RESTRICTED=yes" >> "$VP/etc/conf"
        ok "XBPS_ALLOW_RESTRICTED=yes diaktifkan di $VP/etc/conf"
    else
        ok "XBPS_ALLOW_RESTRICTED=yes sudah aktif"
    fi

    info "ringkasan setup: $ok_count dibuat, $skip_count sudah ada, $fail_count gagal"
    if [ "$fail_count" -gt 0 ]; then
        warn "beberapa arsitektur gagal di-bootstrap, tapi setup tetap lanjut"
    fi
}

cmd_sync(){
    [ -d "$VP/.git" ] || cmd_setup
    info "git pull void-packages..."
    (cd "$VP" && git pull --ff-only) || warn "pull gagal, lanjut dengan yang ada"
    _staged_prune
    local n=0 d name
    for d in "$TPL"/*/; do
        name=$(basename "$d"); [ -f "$d/template" ] || continue
        pkg_safe "$name" || { warn "sync: nama tidak aman, dilewati: $name"; continue; }
        if ! diff -rq "$d" "$VP/srcpkgs/$name" >/dev/null 2>&1; then
            rm -rf "${VP:?}/srcpkgs/$name"; cp -a "$d" "$VP/srcpkgs/$name"
            info "sync: $name"; n=$((n+1))
        fi
        _staged_add "$name"
    done
    ok "$n template disinkronkan"
}

cmd_update(){
    # Pastikan void-packages sudah di-setup
    if [ ! -d "$VP" ] || [ ! -x "$VP/xbps-src" ]; then
        err "update: void-packages belum di-setup. Jalankan: tools --setup"
        return 1
    fi

    info "Menjalankan xbps-src bootstrap-update di $VP ..."
    if (cd "$VP" && ./xbps-src bootstrap-update); then
        ok "bootstrap-update selesai"
    else
        warn "bootstrap-update gagal (exit $?), cek log di atas"
        return 1
    fi
}

cmd_force(){
    local pkgs=() req=() r pkg t sup want targets x f
    local okl="" badl="" noarch=0 rc=0
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--arch) shift; while [ $# -gt 0 ] && [[ $1 != -* ]]; do req+=("$1"); shift; done ;;
            *) pkgs+=("$1"); shift ;;
        esac
    done
    
    # Jika tidak ada package, tampilkan menu
    if [ ${#pkgs[@]} -eq 0 ]; then 
        mapfile -t pkgs < <(menu_pkg)
    fi
    [ ${#pkgs[@]} -gt 0 ] || die "tidak ada package"
    
    # Validasi semua nama + template dulu
    for pkg in "${pkgs[@]}"; do
        pkg_safe "$pkg" || die "nama paket tidak aman: '$pkg'"
        [ -f "$TPL/$pkg/template" ] || die "template tidak ada: $TPL/$pkg/template"
    done
    
    # Pastikan void-packages sudah di-setup
    [ -d "$VP" ] || cmd_setup
    
    # Proses setiap package
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
        info "$pkg di-force  : ${targets[*]}"
        tpl_stage "$pkg"
        
        okl=""; badl=""; noarch=0
        if tpl_is_noarch "$pkg"; then
            noarch=1
            info "$pkg noarch — satu force build untuk ${#targets[@]} tag"
        fi
        
        for x in "${targets[@]}"; do
            if [ "$noarch" = 1 ] && [ "$x" != "${targets[0]}" ]; then continue; fi
            f=()
            mapfile -t f < <(flags_for "$x")
            info "Force building: xbps-src -f ${f[*]:-} pkg $pkg ($x)"
            if (cd "$VP" && ./xbps-src -f ${f[@]+"${f[@]}"} pkg "$pkg"); then
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

cmd_clean(){
    [ -d "$VP" ] || die "void-packages belum di-setup. Jalankan: tools --setup"
    
    info "Menjalankan xbps-src clean..."
    if (cd "$VP" && ./xbps-src clean); then
        ok "clean selesai — build artifacts dibersihkan"
    else
        die "clean gagal"
    fi
}

cmd_zap(){
    [ -d "$VP" ] || die "void-packages belum di-setup. Jalankan: tools --setup"
    
    info "Menjalankan xbps-src zap..."
    if (cd "$VP" && ./xbps-src zap); then
        ok "zap selesai — masterdir dihapus"
        warn "Jalankan tools --setup untuk membuat masterdir lagi"
    else
        die "zap gagal"
    fi
}

# Daftar nama yang pernah kita salin ke $VP/srcpkgs (di dalam .git → tidak mengotori
# `git status`). Dipakai untuk membersihkan salinan template yang sudah dihapus dari
# pkg-template/. Pelacakan dimulai sejak sync/stage pertama dengan versi ini.
_staged_file(){ printf '%s\n' "$VP/.git/t4n-staged"; }
_staged_add(){
    local f; [ -d "$VP/.git" ] || return 0
    f=$(_staged_file)
    grep -qxF -- "$1" "$f" 2>/dev/null || printf '%s\n' "$1" >> "$f"
    return 0
}
_staged_prune(){
    local f keep name; f=$(_staged_file); [ -f "$f" ] || return 0
    keep=$(mktemp)
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if pkg_safe "$name" && [ ! -f "$TPL/$name/template" ]; then
            if git -C "$VP" ls-files --error-unmatch -- "srcpkgs/$name/template" >/dev/null 2>&1; then
                # ada di upstream Void: pulihkan resep resmi, buang sisa berkas kita
                git -C "$VP" checkout -- "srcpkgs/$name" \
                  && git -C "$VP" clean -fdq -- "srcpkgs/$name" \
                  && info "sync: $name tak ada lagi di pkg-template → dipulihkan dari void-packages" \
                  || warn "sync: gagal memulihkan srcpkgs/$name"
            else
                rm -rf "${VP:?}/srcpkgs/$name"
                info "sync: $name tak ada lagi di pkg-template → salinan dibersihkan"
            fi
        else
            printf '%s\n' "$name" >> "$keep"
        fi
    done < "$f"
    mv "$keep" "$f"
}

tpl_stage(){
    pkg_safe "$1" || die "tpl_stage: nama paket tidak aman: '$1'"
    [ -f "$TPL/$1/template" ] || die "tpl_stage: template tidak ada: $1"
    rm -rf "${VP:?}/srcpkgs/$1"; cp -a "$TPL/$1" "$VP/srcpkgs/$1"
    _staged_add "$1"
}

# flags_for <arsitektur-target>
#   -A = masterdir/host, -a = target cross (STRING PENUH, termasuk -musl)
flags_for(){
    local target="$1"
    in_list "${ALL[*]}" "$target" || die "flags_for: '$target' bukan arsitektur valid"

    local hb="${HOST_ARCH%-musl}" tb="${target%-musl}"
    local hl=glibc tl=glibc hm f=()
    if [[ $HOST_ARCH == *-musl ]]; then hl=musl; fi
    if [[ $target    == *-musl ]]; then tl=musl; fi
    # masterdir host dengan libc target. glibc TIDAK punya suffix.
    hm="$hb"
    if [ "$tl" = musl ]; then hm="${hb}-musl"; fi

    if [ "$target" = "$HOST_ARCH" ]; then
        :                                       # identik → native, tanpa flag
    elif [ "$tb" = "$hb" ]; then
        f+=(-A "$target")                       # base sama, libc beda
    elif [ "$tb" = i686 ] && [ "$hb" = x86_64 ] && [ "$hl" = "$tl" ]; then
        f+=(-A i686)                            # native 32-bit (cara resmi Void)
    else
        if [ "$hl" != "$tl" ]; then f+=(-A "$hm"); fi
        f+=(-a "$target")                       # PENUH: armv6l-musl, bukan armv6l
    fi

    if [ ${#f[@]} -gt 0 ]; then printf '%s\n' "${f[@]}"; fi
    return 0
}