#!/usr/bin/env bash
# Proses satu tag: inventory → rencana → verifikasi → index+sign → upload → prune (TERAKHIR).
# Job ini memegang SIGN_KEY: DILARANG membaca/men-source template apa pun.
#
# Rencana (urutan penting):
#   1. Untuk tiap nama paket, telusuri kandidat dari versi tertinggi ke terendah.
#      - kandidat yang .sig2-nya ada DAN tidak lebih tua dari .xbps = "tepercaya"
#        (sudah pernah diverifikasi + ditandatangani CI) → langsung dipilih;
#      - selain itu (belum punya .sig2, atau .xbps lebih baru dari .sig2 karena
#        di-upload ulang dengan nama sama) → diunduh dan diverifikasi props.plist;
#        yang gagal DITOLAK dan DIBIARKAN (tidak dihapus), penelusuran lanjut ke
#        versi di bawahnya.
#   2. prune = kandidat di bawah versi terpilih, HANYA untuk nama yang punya versi
#      lolos verifikasi. Versi lama yang valid tidak pernah dihapus karena versi
#      baru gagal verifikasi.
#   3. Index + sign → upload repodata + .sig2 baru DULU → baru prune (Invarian 4).
set -euo pipefail
export LC_ALL=C
: "${TAG:?}"; : "${SIGN_KEY:?}"; : "${GH_REPO:?}"
SIGNEDBY="${SIGNEDBY:-T4n Labs}"

WORK="$(mktemp -d)"; KEY="$WORK/key.pem"
trap 'rm -rf "$WORK"' EXIT
printf '%s\n' "$SIGN_KEY" > "$KEY"; chmod 600 "$KEY"

# ── kalibrasi semantik `xbps-uhelper cmpver` (stdout vs exit code) ──
# Daripada mengasumsikan konvensi, pelajari signature "lebih besar" dari dua
# probe yang jawabannya sudah diketahui.
set +e
gt_out=$(xbps-uhelper cmpver 2.0_1 1.0_1 2>/dev/null); gt_rc=$?
lt_out=$(xbps-uhelper cmpver 1.0_1 2.0_1 2>/dev/null); lt_rc=$?
set -e
if [ "$gt_out/$gt_rc" = "$lt_out/$lt_rc" ]; then
  echo "ERROR: cmpver tidak membedakan versi — pruning dibatalkan demi keamanan"; exit 1
fi
ver_gt() {
  local o r
  set +e; o=$(xbps-uhelper cmpver "$1" "$2" 2>/dev/null); r=$?; set -e
  [ "$o/$r" = "$gt_out/$gt_rc" ]
}

# ── inventory (paginated: aman untuk >100 asset) — nama + updated_at ──
rid=$(gh api "repos/$GH_REPO/releases/tags/$TAG" --jq .id)
gh api --paginate "repos/$GH_REPO/releases/$rid/assets" \
  --jq '.[] | [.name, .updated_at] | @tsv' > "$WORK/assets.tsv"
cut -f1 "$WORK/assets.tsv" > "$WORK/assets"
declare -A ts=()
while IFS=$'\t' read -r n t; do
  [[ "$n" =~ ^[A-Za-z0-9._+-]+$ ]] || continue     # kunci array hanya nama aman
  ts["$n"]="$t"
done < "$WORK/assets.tsv"
has_repodata=no
if grep -qxF "$TAG-repodata" "$WORK/assets"; then has_repodata=yes; fi

# .sig2 "segar": ada, dan TIDAK lebih tua dari .xbps-nya (timestamp ISO-8601 UTC,
# urut leksikografis). .xbps yang di-upload ulang (--clobber) lebih baru dari
# .sig2 lamanya → tanda tangan basi → harus ditandatangani ulang.
fresh_sig() {
  local x="${ts["$1"]:-}" s="${ts["$1.sig2"]:-}"
  [ -n "$x" ] && [ -n "$s" ] && ! [[ "$s" < "$x" ]]
}

: > "$WORK/xbps"
while IFS= read -r fn; do
  case "$fn" in *.xbps) ;; *) continue ;; esac
  # '+' terbukti aman (nama asset utuh, URL raw & %2B sama-sama 200)
  if ! printf '%s' "$fn" | grep -qE '^[A-Za-z0-9._+-]+$'; then
    echo "::error::$TAG: nama asset di luar [A-Za-z0-9._+-] dilewati: $fn"; continue
  fi
  base="${fn%.xbps}"; arch="${base##*.}"; pkgver="${base%.*}"
  if [ "$arch" != "$TAG" ] && [ "$arch" != noarch ]; then
    echo "::error::$TAG: arch '$arch' bukan tag ini, dilewati: $fn"; continue
  fi
  if ! name=$(xbps-uhelper getpkgname "$pkgver"); then
    echo "::error::getpkgname gagal: $fn"; continue
  fi
  printf '%s\t%s\t%s\n' "$name" "$pkgver" "$fn" >> "$WORK/xbps"
done < "$WORK/assets"

# .sig2 yatim: pasangan .xbps-nya sudah tidak ada di release. Dihapus PALING
# TERAKHIR (bersama prune), tidak pernah memengaruhi indeks.
: > "$WORK/orphans"
while IFS= read -r fn; do
  case "$fn" in *.xbps.sig2) ;; *) continue ;; esac
  grep -qxF "${fn%.sig2}" "$WORK/assets" || printf '%s\n' "$fn" >> "$WORK/orphans"
done < "$WORK/assets"

delete_orphans() {
  local fn
  while IFS= read -r fn; do
    echo "  hapus .sig2 yatim: $fn"
    gh release delete-asset "$TAG" "$fn" -y || true
  done < "$WORK/orphans"
}

# ── tag tanpa satu pun .xbps: jangan tinggalkan indeks/.sig2 yatim ──
if [ ! -s "$WORK/xbps" ]; then
  if [ -s "$WORK/orphans" ] || [ "$has_repodata" = yes ]; then
    delete_orphans
    if [ "$has_repodata" = yes ]; then
      gh release delete-asset "$TAG" "$TAG-repodata" -y || true
      echo "::warning::$TAG: kini kosong (repodata dihapus)"
    fi
  else
    echo "==> $TAG: kosong, tidak ada yang dilakukan"
  fi
  exit 0
fi

# kandidat satu nama paket, urut versi menurun; pkgver sama → arch-spesifik dulu
sorted_candidates() {
  local name="$1" n pv fn i best cnt picked=0
  local -a pvs=() fns=()
  local -A used=()
  while IFS=$'\t' read -r n pv fn; do
    [ "$n" = "$name" ] || continue
    pvs+=("$pv"); fns+=("$fn")
  done < "$WORK/xbps"
  cnt=${#fns[@]}
  while [ "$picked" -lt "$cnt" ]; do
    best=-1
    for ((i = 0; i < cnt; i++)); do
      [ -z "${used[$i]:-}" ] || continue
      if [ "$best" -lt 0 ]; then best=$i; continue; fi
      if ver_gt "${pvs[$i]}" "${pvs[$best]}"; then
        best=$i
      elif [ "${pvs[$i]}" = "${pvs[$best]}" ] \
           && [[ "${fns[$i]}" == *".$TAG.xbps" ]] && [[ "${fns[$best]}" != *".$TAG.xbps" ]]; then
        best=$i
      fi
    done
    used[$best]=1; picked=$((picked + 1))
    printf '%s\n' "${fns[$best]}"
  done
}

mkdir -p "$WORK/repo"
download_one() { gh release download "$TAG" -p "$1" -D "$WORK/repo" --clobber; }

# ── verifikasi nama: asset harus persis <pkgver>.<architecture>.xbps ──
# GitHub me-rename karakter tertentu (terbukti: '~' → '.'). Hasil rename bisa
# lolos charset check, tapi bikin client 404. Baca props.plist = parsing data,
# bukan eksekusi kode — tetap aman untuk job pemegang secret.
verify_one() {
  local fn="$1" f="$WORK/repo/$1" want
  if ! bsdtar -xOf "$f" props.plist > "$WORK/props.plist" 2>/dev/null; then
    echo "::error::$TAG: props.plist tidak terbaca (bukan paket xbps valid?): $fn"
    rm -f "$f"; return 1
  fi
  want=$(python3 - "$WORK/props.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
print(f"{d.get('pkgver','')}.{d.get('architecture','')}.xbps")
PY
)
  if [ "$fn" != "$want" ]; then
    echo "::error::$TAG: nama asset '$fn' != isi paket '$want' (GitHub rename?) — DITOLAK"
    rm -f "$f"; return 1
  fi
  return 0
}

# ── rencana + verifikasi kandidat yang belum tepercaya ──
: > "$WORK/chosen"      # satu .xbps per nama paket
: > "$WORK/prune_map"   # <terpilih>\t<kandidat di bawahnya>
: > "$WORK/rejected"
for name in $(cut -f1 "$WORK/xbps" | sort -u); do
  mapfile -t cands < <(sorted_candidates "$name")
  pick=""; idx=-1
  for i in "${!cands[@]}"; do
    fn="${cands[$i]}"
    if fresh_sig "$fn"; then pick="$fn"; idx=$i; break; fi
    download_one "$fn"
    if verify_one "$fn"; then pick="$fn"; idx=$i; break; fi
    printf '%s\n' "$fn" >> "$WORK/rejected"
  done
  if [ -z "$pick" ]; then
    echo "::warning::$TAG: $name: tidak ada versi lolos verifikasi — semua berkas dibiarkan (tidak ada prune)"
    continue
  fi
  printf '%s\n' "$pick" >> "$WORK/chosen"
  for ((j = idx + 1; j < ${#cands[@]}; j++)); do
    printf '%s\t%s\n' "$pick" "${cands[$j]}" >> "$WORK/prune_map"
  done
done

if [ ! -s "$WORK/chosen" ]; then
  echo "::error::$TAG: tidak ada paket lolos verifikasi"; exit 1
fi

# unsigned = terpilih yang .sig2-nya belum ada ATAU sudah basi (.xbps lebih baru)
: > "$WORK/unsigned"
while IFS= read -r fn; do
  fresh_sig "$fn" || printf '%s\n' "$fn" >> "$WORK/unsigned"
done < "$WORK/chosen"

# repodata lebih tua dari .xbps terpilih mana pun → indeks basi
repodata_stale=no
if [ "$has_repodata" = yes ]; then
  while IFS= read -r fn; do
    if [[ "${ts["$TAG-repodata"]:-}" < "${ts["$fn"]:-}" ]]; then repodata_stale=yes; break; fi
  done < "$WORK/chosen"
fi

echo "==> $TAG: pilih=$(wc -l < "$WORK/chosen") unsigned=$(wc -l < "$WORK/unsigned") prune=$(cut -f2 "$WORK/prune_map" | sort -u | wc -l) ditolak=$(wc -l < "$WORK/rejected") yatim=$(wc -l < "$WORK/orphans")"

if [ ! -s "$WORK/unsigned" ] && [ ! -s "$WORK/prune_map" ] \
   && [ "$has_repodata" = yes ] && [ "$repodata_stale" = no ]; then
  delete_orphans
  echo "==> $TAG: tidak ada yang perlu diproses"; exit 0
fi

# ── unduh sisa yang dipilih (yang tepercaya belum diunduh) lalu verifikasi ──
: > "$WORK/verified"
while IFS= read -r fn; do
  if [ ! -f "$WORK/repo/$fn" ]; then
    download_one "$fn"
    if ! verify_one "$fn"; then
      # .sig2-nya segar tapi isinya kini tak lolos verifikasi: anomali. Berhenti
      # sebelum mengubah apa pun (tidak ada upload, tidak ada prune).
      echo "::error::$TAG: berkas tepercaya gagal verifikasi ulang: $fn — dihentikan tanpa perubahan"
      exit 1
    fi
  fi
  printf '%s\n' "$fn" >> "$WORK/verified"
done < "$WORK/chosen"

export XBPS_ARCH="$TAG"
mapfile -t pkgs < <(sed "s|^|$WORK/repo/|" "$WORK/verified" | sort)

echo "  [1/3] index"
xbps-rindex -a "${pkgs[@]}"
echo "  [2/3] sign repodata"
xbps-rindex --privkey "$KEY" --sign --signedby "$SIGNEDBY" "$WORK/repo"
echo "  [3/3] sign paket unsigned"
if [ -s "$WORK/unsigned" ]; then
  mapfile -t uns < <(sed "s|^|$WORK/repo/|" "$WORK/unsigned")
  xbps-rindex --privkey "$KEY" --sign-pkg "${uns[@]}"
fi
[ -f "$WORK/repo/$TAG-repodata" ] || { echo "ERROR: repodata tidak terbentuk"; exit 1; }

# ── upload repodata + sig2 baru DULU ──
up=("$WORK/repo/$TAG-repodata")
while IFS= read -r fn; do
  [ -f "$WORK/repo/$fn.sig2" ] || { echo "ERROR: $fn.sig2 tidak terbentuk"; exit 1; }
  up+=("$WORK/repo/$fn.sig2")
done < "$WORK/unsigned"
gh release upload "$TAG" "${up[@]}" --clobber

# ── prune PALING TERAKHIR: client tak pernah lihat indeks nunjuk file hilang ──
# Hanya kandidat di bawah versi yang SUDAH terverifikasi dan terindeks.
cut -f2 "$WORK/prune_map" | sort -u > "$WORK/prune"
while IFS= read -r fn; do
  echo "  prune: $fn"
  gh release delete-asset "$TAG" "$fn" -y || true
  if grep -qxF "$fn.sig2" "$WORK/assets"; then
    gh release delete-asset "$TAG" "$fn.sig2" -y || true
  fi
done < "$WORK/prune"
delete_orphans

echo "✓ $TAG selesai ($(wc -l < "$WORK/verified") paket terindeks)"
