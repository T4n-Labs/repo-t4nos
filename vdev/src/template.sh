# Parser template: grep/sed, TIDAK pernah di-source (template dari pihak lain).
# Bisa di-source sendiri oleh CI / Let-X: . vdev/src/template.sh

tpl_field(){
    grep -E "^[[:space:]]*$2=" "$1" 2>/dev/null | head -n1 \
      | sed -E 's/^[^=]*=//; s/#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//; s/^'\''//; s/'\''$//' || true
}

tpl_subpkgs(){
    local l; l=$(tpl_field "$1" subpackages)
    l="${l//\$\{pkgname\}/$2}"; l="${l//\$pkgname/$2}"
    printf '%s\n' $l
}

# archs: kosong/noarch/all = 9; glob x86_64* = glibc+musl; ~token = negasi.
expand_archs(){
    local line="${1//,/ }" tok a keep pos=() neg=() out=()
    if [ -z "$line" ] || [ "$line" = all ] || [ "$line" = noarch ]; then
        printf '%s\n' "${ALL[@]}"; return
    fi
    for tok in $line; do
        if [[ $tok == '~'* ]]; then neg+=("${tok#\~}"); else pos+=("$tok"); fi
    done
    for a in "${ALL[@]}"; do
        keep=0
        if [ ${#pos[@]} -eq 0 ]; then keep=1
        else for tok in "${pos[@]}"; do case "$a" in $tok) keep=1;; esac; done; fi
        if [ "$keep" = 1 ] && [ ${#neg[@]} -gt 0 ]; then
            for tok in "${neg[@]}"; do case "$a" in $tok) keep=0;; esac; done
        fi
        [ "$keep" = 1 ] && out+=("$a")
    done
    [ ${#out[@]} -gt 0 ] && printf '%s\n' "${out[@]}"
}

tpl_supported(){ expand_archs "$(tpl_field "$TPL/$1/template" archs)"; }
tpl_is_noarch(){ [ "$(tpl_field "$TPL/$1/template" archs)" = noarch ]; }