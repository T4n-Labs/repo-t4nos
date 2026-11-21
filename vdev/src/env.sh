# Environment build: clone, bootstrap, sync template, flag xbps-src.

cmd_setup(){
    if [ -d "$VP/.git" ]; then ok "void-packages sudah ada"
    else info "Clone void-packages..."; git clone --depth 1 https://github.com/void-linux/void-packages "$VP"; fi
    if [ -d "$VP/masterdir-$HOST_ARCH" ]; then ok "masterdir-$HOST_ARCH siap"
    else info "binary-bootstrap..."; (cd "$VP" && ./xbps-src binary-bootstrap); fi
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

# native tanpa flag; i686 di x86_64 pakai -A; libc beda pakai -A host-musl; sisanya -a
flags_for(){
    local t="$1" hb="${HOST_ARCH%-musl}" tb="${t%-musl}" hl=glibc tl=glibc f=()
    [[ $HOST_ARCH == *-musl ]] && hl=musl
    [[ $t == *-musl ]] && tl=musl
    if [ "$tb" = i686 ] && [ "$hb" = x86_64 ] && [ "$hl" = "$tl" ]; then
        f+=(-A i686)
    else
        if [ "$hl" != "$tl" ]; then f+=(-A "${hb}-${tl}"); fi
        if [ "$tb" != "$hb" ]; then f+=(-a "$tb"); fi
    fi
    [ ${#f[@]} -gt 0 ] && printf '%s\n' "${f[@]}"
}