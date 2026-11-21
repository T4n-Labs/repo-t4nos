#!/usr/bin/env bash
# Proses satu tag: inventory → rencana → verifikasi → index+sign → upload → prune (TERAKHIR).
# Job ini memegang SIGN_KEY: DILARANG membaca/men-source template apa pun.
set -euo pipefail
: "${TAG:?}"; : "${SIGN_KEY:?}"; : "${GH_REPO:?}"
SIGNEDBY="${SIGNEDBY:-T4n Labs}"

WORK="$(mktemp -d)"; KEY="$WORK/key.pem"
trap 'rm -rf "$WORK"' EXIT
printf '%s\n' "$SIGN_KEY" > "$KEY"; chmod 600 "$KEY"

# ── kalibrasi semantik `xbps-uhelper cmpver` ──
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

# ── inventory ──
rid=$(gh api "repos/$GH_REPO/releases/tags/$TAG" --jq .id)
gh api --paginate "repos/$GH_REPO/releases/$rid/assets" --jq '.[].name' > "$WORK/assets"
has_repodata=no
if grep -qxF "$TAG-repodata" "$WORK/assets"; then has_repodata=yes; fi

: > "$WORK/xbps"
while IFS= read -r fn; do
  case "$fn" in *.xbps) ;; *) continue ;; esac
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

# ── rencana ──
: > "$WORK/keep"; : > "$WORK/prune"
for name in $(cut -f1 "$WORK/xbps" | sort -u); do
  best=""
  while IFS=$'\t' read -r n pv fn; do
    [ "$n" = "$name" ] || continue
    if [ -z "$best" ] || ver_gt "$pv" "$best"; then best="$pv"; fi
  done < "$WORK/xbps"
  chosen=""
  for f in $(awk -F'\t' -v n="$name" -v pv="$best" '$1==n && $2==pv {print $3}' "$WORK/xbps"); do
    case "$f" in *".$TAG.xbps") chosen="$f"; break ;; esac
  done
  if [ -z "$chosen" ]; then
    chosen=$(awk -F'\t' -v n="$name" -v pv="$best" '$1==n && $2==pv {print $3; exit}' "$WORK/xbps")
  fi
  printf '%s\n' "$chosen" >> "$WORK/keep"
  awk -F'\t' -v n="$name" '$1==n {print $3}' "$WORK/xbps" \
    | grep -vxF "$chosen" >> "$WORK/prune" || true
done

: > "$WORK/unsigned"
while IFS= read -r fn; do
  grep -qxF "$fn.sig2" "$WORK/assets" || printf '%s\n' "$fn" >> "$WORK/unsigned"
done < "$WORK/keep"

echo "==> $TAG: keep=$(wc -l < "$WORK/keep") unsigned=$(wc -l < "$WORK/unsigned") prune=$(wc -l < "$WORK/prune")"

if [ ! -s "$WORK/unsigned" ] && [ ! -s "$WORK/prune" ] && [ "$has_repodata" = yes ]; then
  echo "==> $TAG: tidak ada yang perlu diproses"; exit 0
fi

if [ ! -s "$WORK/keep" ]; then
  while IFS= read -r fn; do
    gh release delete-asset "$TAG" "$fn" -y || true
    if grep -qxF "$fn.sig2" "$WORK/assets"; then
      gh release delete-asset "$TAG" "$fn.sig2" -y || true
    fi
  done < "$WORK/prune"
  if [ "$has_repodata" = yes ]; then
    gh release delete-asset "$TAG" "$TAG-repodata" -y || true
  fi
  echo "::warning::$TAG: kini kosong (repodata dihapus)"
  exit 0
fi

# ── unduh ──
mkdir -p "$WORK/repo"
while IFS= read -r fn; do
  gh release download "$TAG" -p "$fn" -D "$WORK/repo" --clobber
done < "$WORK/keep"

# ── verifikasi nama ──
: > "$WORK/verified"
while IFS= read -r fn; do
  f="$WORK/repo/$fn"
  if ! bsdtar -xOf "$f" props.plist > "$WORK/props.plist" 2>/dev/null; then
    echo "::error::$TAG: props.plist tidak terbaca: $fn"
    rm -f "$f"; continue
  fi
  want=$(python3 - "$WORK/props.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
print(f"{d.get('pkgver','')}.{d.get('architecture','')}.xbps")
PY
)
  if [ "$fn" != "$want" ]; then
    echo "::error::$TAG: nama asset '$fn' != isi paket '$want' — DITOLAK"
    rm -f "$f"; continue
  fi
  printf '%s\n' "$fn" >> "$WORK/verified"
done < "$WORK/keep"

if [ ! -s "$WORK/verified" ]; then
  echo "::error::$TAG: tidak ada paket lolos verifikasi"; exit 1
fi
if [ -s "$WORK/unsigned" ]; then
  grep -xF -f "$WORK/verified" "$WORK/unsigned" > "$WORK/unsigned.ok" || true
  mv "$WORK/unsigned.ok" "$WORK/unsigned"
fi

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

# ── prune PALING TERAKHIR ──
while IFS= read -r fn; do
  echo "  prune: $fn"
  gh release delete-asset "$TAG" "$fn" -y || true
  if grep -qxF "$fn.sig2" "$WORK/assets"; then
    gh release delete-asset "$TAG" "$fn.sig2" -y || true
  fi
done < "$WORK/prune"

echo "✓ $TAG selesai ($(wc -l < "$WORK/verified") paket terindeks)"