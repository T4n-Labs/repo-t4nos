# Environment build: clone, bootstrap, sync template, flag xbps-src.

cmd_setup(){
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
    if [ -d "$VP/masterdir-$HOST_ARCH" ]; then
        ok "masterdir-$HOST_ARCH siap"
    else
        info "binary-bootstrap..."
        (cd "$VP" && ./xbps-src binary-bootstrap)
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