# Tawaran push / PR. Aman tanpa TTY: EOF pada stdin = jawab "tidak".
# Selalu mengembalikan 0 — dipanggil setelah upload sukses, jangan menggagalkan exit code.
git_offer(){
    local ans="" origin
    read -rp "Git push perubahan sekarang? [y/N] " ans || ans=""
    [[ ${ans,,} == y* ]] || return 0
    git -C "$REPO_DIR" push || warn "push gagal"
    origin=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")
    case "$origin" in
        *"$GH_REPO"*) ;;
        *) ans=""
           read -rp "Buka Pull Request ke $GH_REPO? [y/N] " ans || ans=""
           if [[ ${ans,,} == y* ]]; then
               gh pr create --repo "$GH_REPO" --fill || warn "gh pr create gagal"
           fi ;;
    esac
    return 0
}
