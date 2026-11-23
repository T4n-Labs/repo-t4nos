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
    local n=0 d name
    for d in "$TPL"/*/; do
        name=$(basename "$d"); [ -f "$d/template" ] || continue
        if ! diff -rq "$d" "$VP/srcpkgs/$name" >/dev/null 2>&1; then
            rm -rf "$VP/srcpkgs/$name"; cp -a "$d" "$VP/srcpkgs/$name"
            info "sync: $name"; n=$((n+1))
        fi
    done
    ok "$n template disinkronkan"
}

tpl_stage(){ rm -rf "$VP/srcpkgs/$1"; cp -a "$TPL/$1" "$VP/srcpkgs/$1"; }

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