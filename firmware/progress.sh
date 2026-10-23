#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-/projects/ep06-board-poe-proxy/firmware}"
SRC=$(ls -d "$ROOT"/build/openwrt-* 2>/dev/null | tail -1)
[ -n "$SRC" ] || { echo "no source tree yet"; exit 0; }
cd "$SRC"

tools_total=$(ls -d tools/*/ | wc -l)
tools_done=$(ls build_dir/host/*/.built 2>/dev/null | wc -l)

tc_total=6
tc_done=$(ls build_dir/toolchain-*/*/.built build_dir/toolchain-*/*/*/.built 2>/dev/null | wc -l)

pkg_total=$(awk '
  FNR == NR { if (match($0, /^CONFIG_PACKAGE_[^=]+=[ym]$/)) { sub(/^CONFIG_PACKAGE_/, ""); sub(/=.*/, ""); sel[$0] = 1 }; next }
  /^Source-Makefile:/ { src = $2 }
  /^Package:/ && ($2 in sel) { used[src] = 1 }
  END { print length(used) }' .config tmp/.packageinfo 2>/dev/null)
pkg_total=$(( pkg_total + 1 ))
pkg_done=$(ls build_dir/target-*/*/.built build_dir/target-*/linux-*/linux-*/.image 2>/dev/null | wc -l)

img_done=$(ls bin/targets/ramips/mt7620/*kroks_kndrt22r1*sysupgrade.bin 2>/dev/null | wc -l)

[ "$tc_done" -gt 0 ] && tools_done=$tools_total
[ "$pkg_done" -gt 0 ] && { tools_done=$tools_total; tc_done=$tc_total; }

pct() { local d=$1 t=$2; [ "$t" -gt 0 ] || t=1; [ "$d" -le "$t" ] || d=$t; echo $(( d * 100 / t )); }
total=$(( ( 20 * $(pct "$tools_done" "$tools_total") + 30 * $(pct "$tc_done" "$tc_total")
          + 45 * $(pct "$pkg_done" "$pkg_total") + 5 * 100 * img_done ) / 100 ))

echo "progress ~${total}%  | tools ${tools_done}/${tools_total}  toolchain ${tc_done}/${tc_total}  kernel+packages ${pkg_done}/${pkg_total}  image ${img_done}/1"
echo "now: $(grep -E '^ make\[' "$ROOT"/build/build-*.log 2>/dev/null | tail -1 | sed 's/^ *//')"
