# Konstanta & helper bersama. TIDAK ada side effect selain assignment.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VP="$REPO_DIR/void-packages"
TPL="$REPO_DIR/pkg-template"
GH_REPO="T4n-Labs/repo-t4nos"
ALL=(x86_64 x86_64-musl aarch64 aarch64-musl armv6l armv6l-musl armv7l armv7l-musl i686)
HOST_ARCH="$(xbps-uhelper arch 2>/dev/null || uname -m)"

B='\033[0;34m'; G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info(){ printf "${B}[INFO]${N} %s\n" "$*"; }
ok(){   printf "${G}[OK]${N} %s\n" "$*"; }
warn(){ printf "${Y}[WARN]${N} %s\n" "$*"; }
err(){  printf "${R}[ERROR]${N} %s\n" "$*" >&2; }
die(){  err "$*"; exit 1; }

need(){ command -v "$1" >/dev/null 2>&1 || die "$1 belum terinstal"; }

# charset nama asset yang aman di GitHub Releases (terverifikasi: '+' aman, '~' tidak)
name_safe(){ printf '%s' "$1" | grep -qE '^[A-Za-z0-9._+-]+$'; }

in_list(){ case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }