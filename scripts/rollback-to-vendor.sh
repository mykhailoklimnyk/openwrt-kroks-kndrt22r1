#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-192.168.1.1}"
KEY="${KEY:-$HOME/.ssh/ep06_router_rsa}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP="${1:-$(ls -1d "$ROOT"/backup/*/ | sort | tail -1)}"
IMG="$BACKUP/mtd3_firmware.bin"
SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR
          -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa
          -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no)

want=$(awk '$2 ~ /mtd3_firmware.bin$/ {print $1}' "$BACKUP/SHA256SUMS")
have=$(sha256sum "$IMG" | cut -d' ' -f1)
[ -n "$want" ] && [ "$want" = "$have" ] || { echo "backup checksum mismatch: $IMG" >&2; exit 1; }

echo "uploading $IMG ($(stat -c %s "$IMG") bytes)"
scp -O "${SSH_OPTS[@]}" "$IMG" "root@$HOST:/tmp/vendor.bin"
ssh "${SSH_OPTS[@]}" "root@$HOST" "
  set -e
  [ \"\$(sha256sum /tmp/vendor.bin | cut -d' ' -f1)\" = '$want' ] || { echo 'upload corrupted'; exit 1; }
  grep -q '\"firmware\"' /proc/mtd || { echo 'no firmware partition'; exit 1; }
  echo 'writing vendor firmware to the firmware partition, the router reboots when done'
  mtd -r write /tmp/vendor.bin firmware
"
