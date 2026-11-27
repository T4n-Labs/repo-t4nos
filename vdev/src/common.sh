# Konstanta & helper bersama. TIDAK ada side effect selain assignment.
# Semua log ke STDERR — stdout dipakai untuk data (dipanggil via mapfile).
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VP="$REPO_DIR/void-packages"
TPL="$REPO_DIR/pkg-template"
GH_REPO="T4n-Labs/repo-t4nos"
ALL=(x86_64 x86_64-musl aarch64 aarch64-musl armv6l armv6l-musl armv7l armv7l-musl i686)
FIX_MUTABLE=(common/shlibs)
HOST_ARCH="$(xbps-uhelper arch 2>/dev/null || uname -m)"

B='\033[0;34m'; G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info(){ printf "${B}[INFO]${N} %s\n" "$*" >&2; }
ok(){   printf "${G}[OK]${N} %s\n"   "$*" >&2; }
warn(){ printf "${Y}[WARN]${N} %s\n" "$*" >&2; }
err(){  printf "${R}[ERROR]${N} %s\n" "$*" >&2; }
die(){  err "$*"; exit 1; }

need(){ command -v "$1" >/dev/null 2>&1 || die "$1 belum terinstal"; }

# charset nama asset yang aman di GitHub Releases (terverifikasi: '+' aman, '~' tidak)
name_safe(){ printf '%s' "$1" | grep -qE '^[A-Za-z0-9._+-]+$'; }

# Nama paket untuk operasi path (rm/cp): allowlist name_safe + tidak boleh diawali
# '.' atau '-' (menolak '.', '..', '.hidden', opsi). Regex name_safe sengaja tidak diubah.
pkg_safe(){ name_safe "$1" || return 1; case "$1" in .*|-*) return 1 ;; esac; return 0; }

in_list(){ case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }