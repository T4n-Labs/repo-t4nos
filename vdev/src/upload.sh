route_tags(){ # filename arch supported[] → tag tujuan
    local fn="$1" arch="$2" sup="$3" out=() x
    if [ "$arch" = noarch ]; then printf '%s\n' $sup; return; fi
    for x in $sup; do [ "$x" = "$arch" ] && out+=("$x"); done
    [ ${#out[@]} -gt 0 ] && printf '%s\n' "${out[@]}"
}

cmd_upload(){
    need gh
    local pkgs=("$@")
    if [ ${#pkgs[@]} -eq 0 ]; then mapfile -t pkgs < <(menu_pkg); fi
    [ ${#pkgs[@]} -gt 0 ] || die "tidak ada package"

    local can_push; can_push=$(gh api "repos/$GH_REPO" --jq '.permissions.push' 2>/dev/null || echo false)
    if [ "$can_push" != true ]; then
        warn "Tidak punya akses write ke $GH_REPO — upload & trigger dilewati."
        info "Biner akan di-build dan di-upload maintainer setelah PR di-merge."
        git_offer; return
    fi

    local touched="" pkg t v rv names fn base arch sup n up x tags
    shopt -s nullglob
    for pkg in "${pkgs[@]}"; do
        t="$TPL/$pkg/template"; [ -f "$t" ] || { warn "template hilang: $pkg"; continue; }
        v=$(tpl_field "$t" version); rv=$(tpl_field "$t" revision); rv="${rv:-1}"
        names="$pkg
$(tpl_subpkgs "$t" "$pkg")"
        sup=$(tpl_supported "$pkg" | xargs)
        up=0
        for f in "$VP"/hostdir/binpkgs/*.xbps; do
            fn=$(basename "$f"); base="${fn%.xbps}"; arch="${base##*.}"
            name_safe "$fn" || { warn "nama asset tidak aman, skip: $fn"; continue; }
            n=$(xbps-uhelper getpkgname "${base%.*}") || continue
            printf '%s\n' "$names" | grep -qxF "$n" || continue
            case "$fn" in *"-${v}_${rv}."*) ;; *) warn "versi lain, skip: $fn"; continue ;; esac
            tags=$(route_tags "$fn" "$arch" "$sup")
            [ -n "$tags" ] || { warn "$arch di luar archs: $fn"; continue; }
            for x in $tags; do
                gh release view "$x" -R "$GH_REPO" >/dev/null 2>&1 \
                  || gh release create "$x" -R "$GH_REPO" --prerelease --title "repository T4nOS for $x"
                gh release upload "$x" "$f" -R "$GH_REPO" --clobber
                ok "↑ $x/$fn"; up=$((up+1))
                in_list "$touched" "$x" || touched="$touched $x"
            done
        done
        [ "$up" -gt 0 ] || warn "$pkg: tidak ada biner cocok (build dulu?)"
    done
    if [ -n "$touched" ]; then
        info "Trigger workflow sekali untuk:$touched"
        gh workflow run process.yml -R "$GH_REPO" -f tags="$(echo $touched | xargs)"
        ok "Signing/index jalan di CI. Pantau: gh run watch -R $GH_REPO"
    fi
    git_offer
}