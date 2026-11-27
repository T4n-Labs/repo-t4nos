#!/bin/sh
# FIX.sh — radare2: daftarkan SONAME ke common/shlibs.
# Wajib: hook pre-pkg/99-pkglint menolak build kalau entri tidak ada.
# Idempoten: entri lama milik radare2 dibuang, lalu ditulis ulang.
set -eu

# dipakai saat dijalankan manual (tanpa env dari tools.sh)
: "${T4N_PKG:=radare2}"
: "${T4N_VERSION:=$(sed -n 's/^version=//p' template)}"
: "${T4N_REVISION:=$(sed -n 's/^revision=//p' template)}"
map="${T4N_VP:-../..}/common/shlibs"
pkg="${T4N_PKG}-${T4N_VERSION}_${T4N_REVISION:-1}"

[ -f "$map" ] || { echo "FIX: tidak ada $map" >&2; exit 1; }

sed -i -E '/^(libr_[a-z0-9_]+|libsdb)\.so\.[0-9.]+[[:blank:]]+radare2-/d' "$map"
for l in core config cons util flag arch asm bin anal lang debug egg bp \
         search io socket syscall fs magic reg main muta esil; do
	printf 'libr_%s.so.%s %s\n' "$l" "$T4N_VERSION" "$pkg"
done >> "$map"
printf 'libsdb.so.2.6.2 %s\n' "$pkg" >> "$map"