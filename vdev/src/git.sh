git_offer(){
    local ans origin
    read -rp "Git push perubahan sekarang? [y/N] " ans
    [[ ${ans,,} == y* ]] || return 0
    git -C "$REPO_DIR" push || warn "push gagal"
    origin=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")
    case "$origin" in
        *"$GH_REPO"*) ;;
        *) read -rp "Buka Pull Request ke $GH_REPO? [y/N] " ans
           [[ ${ans,,} == y* ]] && gh pr create --repo "$GH_REPO" --fill ;;
    esac
}