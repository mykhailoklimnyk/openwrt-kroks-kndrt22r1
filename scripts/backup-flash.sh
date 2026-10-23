#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-192.168.1.1}"
KEY="${KEY:-$HOME/.ssh/ep06_router_rsa}"
OUT="${1:-$(dirname "$0")/../backup/$(date +%Y-%m-%d_%H%M)}"
SSH=(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10
     -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa
     -o StrictHostKeyChecking=accept-new "root@$HOST")

mkdir -p "$OUT"
cd "$OUT"

"${SSH[@]}" 'cat /proc/mtd' > mtd.txt
cat mtd.txt

for n in $(awk -F'[:" ]+' '/^mtd/ {print substr($1,4)}' mtd.txt); do
  name=$(awk -v d="mtd$n:" '$1==d {gsub(/"/,"",$4); print $4}' mtd.txt)
  f="mtd${n}_${name}.bin"
  "${SSH[@]}" "cat /dev/mtd$n" > "$f"
  remote=$("${SSH[@]}" "sha256sum /dev/mtd$n" | cut -d' ' -f1)
  local_=$(sha256sum "$f" | cut -d' ' -f1)
  [ "$remote" = "$local_" ] || { echo "CHECKSUM MISMATCH on $f" >&2; exit 1; }
  printf '%-28s %10s  %s\n' "$f" "$(stat -c %s "$f")" "ok"
done

cat mtd0_u-boot.bin mtd1_u-boot-env.bin mtd2_factory.bin mtd3_firmware.bin mtd7_memory.bin > full-16MB.bin
size=$(stat -c %s full-16MB.bin)
[ "$size" -eq 16777216 ] || echo "WARNING: full image is $size bytes, expected 16777216" >&2

"${SSH[@]}" 'sysupgrade -b - 2>/dev/null' > config-sysupgrade.tar.gz
"${SSH[@]}" 'cat /sys/firmware/fdt 2>/dev/null' > device-tree.dtb || true
"${SSH[@]}" 'cd /sys/firmware/devicetree/base 2>/dev/null && tar c .' > device-tree-base.tar || true
"${SSH[@]}" 'cat /etc/openwrt_release; echo; cat /proc/cpuinfo; echo; dmesg; echo; opkg list-installed; echo; lsusb 2>/dev/null; ls -l /dev/ttyUSB* /dev/cdc-wdm* 2>/dev/null' > sysinfo.txt

sha256sum *.bin *.tar* *.dtb > SHA256SUMS 2>/dev/null || true
echo "Backup written to $(pwd)"
