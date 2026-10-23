#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-/work}"
IMAGES="${IMAGES:-/images}"
VERSION="${1:-${VERSION:-}}"
[ -n "$VERSION" ] || VERSION="$(curl -fsS https://downloads.openwrt.org/.versions.json | sed -n 's/.*"stable_version": *"\([^"]*\)".*/\1/p')"
SRC="$WORK/openwrt-$VERSION"
OUT="$IMAGES/$VERSION"
DTS=mt7620a_kroks_kndrt22r1.dts
JOBS="${JOBS:-$(nproc)}"

log() { echo "[$(date '+%F %T')] $*"; }

[ -n "$VERSION" ] || { echo "cannot determine OpenWrt version" >&2; exit 1; }
[ "$(id -u)" != 0 ] || { echo "OpenWrt does not build as root" >&2; exit 1; }
[ -f "$HERE/port/$DTS" ] || { echo "missing $HERE/port/$DTS" >&2; exit 1; }
free_gb=$(( $(df -Pk "$WORK" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
[ "$free_gb" -ge 25 ] || [ -d "$SRC" ] || { echo "only ${free_gb} GB free in $WORK, need ~25 GB" >&2; exit 1; }
log "building OpenWrt $VERSION in $WORK"
mkdir -p "$WORK/dl"

for old in "$WORK"/openwrt-*; do
  [ -d "$old" ] && [ "$old" != "$SRC" ] && { log "removing old tree $old"; rm -rf "$old"; }
done

if [ ! -d "$SRC/.git" ]; then
  log "cloning v$VERSION"
  git clone -q --depth 1 --branch "v$VERSION" https://github.com/openwrt/openwrt.git "$SRC"
fi
cd "$SRC"

git checkout -q -- . && git clean -fdq
ln -sfn "$WORK/dl" dl

log "feeds"
./scripts/feeds update -a >/dev/null
for f in feeds/*/; do
  [ -d "$f.git" ] && git -C "$f" checkout -q -- . && git -C "$f" clean -fdq
done
./scripts/feeds install -a >/dev/null

log "applying board port"
cp "$HERE/port/$DTS" target/linux/ramips/dts/
kver=$(sed -n 's/^KERNEL_PATCHVER:=//p' target/linux/ramips/Makefile)
for p in "$HERE"/port/patches/*.patch; do
  [ -f "$p" ] && cp "$p" "target/linux/ramips/patches-$kver/"
done
for d in "$HERE"/port/package-patches/*/; do
  [ -d "$d" ] || continue
  pkg=$(basename "$d")
  pdir=$(readlink -f "$(find package/feeds -mindepth 2 -maxdepth 2 -name "$pkg" | head -1)")
  [ -f "$pdir/Makefile" ] || { echo "package $pkg not found in feeds" >&2; exit 1; }
  mkdir -p "$pdir/patches" && cp "$d"*.patch "$pdir/patches/"
done
cat "$HERE/port/device.mk" >> target/linux/ramips/image/mt7620.mk
for f in 01_leds 02_network; do
  t=target/linux/ramips/mt7620/base-files/etc/board.d/$f
  awk -v snip="$HERE/port/$f.case" '
    !done && /^[[:space:]]*case \$board in$/ { print; while ((getline l < snip) > 0) print l; done = 1; next }
    { print }' "$t" > "$t.new"
  cat "$t.new" > "$t" && rm "$t.new"
  grep -q 'kroks,kndrt22r1' "$t" || { echo "failed to add board to $t" >&2; exit 1; }
done

rm -rf files
[ -d "$HERE/files" ] && cp -r "$HERE/files" files
for d in files/usr/sbin files/www/cgi-bin files/usr/lib/ModemManager/connection.d; do
  [ -d "$d" ] && find "$d" -type f -exec chmod 755 {} +
done

cp "$HERE/config/diffconfig" .config
make defconfig >/dev/null
grep -q '^CONFIG_TARGET_ramips_mt7620_DEVICE_kroks_kndrt22r1=y' .config \
  || { echo "device profile not selected after defconfig" >&2; exit 1; }

log "download"
make -j8 download >/dev/null
log "build ($JOBS jobs), log: $WORK/build-$VERSION.log"
if ! make -j"$JOBS" >"$WORK/build-$VERSION.log" 2>&1; then
  half=$(( JOBS / 2 > 1 ? JOBS / 2 : 1 ))
  log "build with $JOBS jobs failed, retrying with $half"
  if ! make -j"$half" >>"$WORK/build-$VERSION.log" 2>&1; then
    log "retrying single-threaded for a readable error"
    make -j1 V=s >>"$WORK/build-$VERSION.log" 2>&1 || { tail -50 "$WORK/build-$VERSION.log" >&2; exit 1; }
  fi
fi

rm -rf "$OUT" && mkdir -p "$OUT"
cp bin/targets/ramips/mt7620/*kroks_kndrt22r1* "$OUT"/
cp .config "$OUT/config.full"
git rev-parse HEAD > "$OUT/openwrt-commit"
echo "${PORT_COMMIT:-$(git -C "$HERE" rev-parse HEAD 2>/dev/null)}" > "$OUT/port-commit"
(cd "$OUT" && sha256sum *.bin > SHA256SUMS)
log "done: $OUT"
ls -l "$OUT"
