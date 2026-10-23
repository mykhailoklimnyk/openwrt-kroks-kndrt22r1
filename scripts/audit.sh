#!/usr/bin/env bash
set -uo pipefail

HOST="${HOST:-192.168.1.1}"
KEY="${KEY:-$HOME/.ssh/ep06_router_rsa}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH=(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10
     -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o LogLevel=ERROR
     -o StrictHostKeyChecking=accept-new "root@$HOST")

section() { printf '\n== %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

section "OpenWrt upstream"
versions=$(curl -fsS --max-time 20 https://downloads.openwrt.org/.versions.json)
stable=$(sed -n 's/.*"stable_version": *"\([^"]*\)".*/\1/p' <<<"$versions")
oldstable=$(sed -n 's/.*"oldstable_version": *"\([^"]*\)".*/\1/p' <<<"$versions")
echo "  stable:    $stable"
echo "  oldstable: $oldstable"

section "Router $HOST"
if info=$("${SSH[@]}" '. /etc/openwrt_release; echo "$DISTRIB_ID $DISTRIB_RELEASE ($DISTRIB_REVISION)";
    uname -r; cut -d" " -f1 /proc/uptime;
    if command -v apk >/dev/null; then apk list --upgradable 2>/dev/null | wc -l;
    else opkg list-upgradable 2>/dev/null | wc -l; fi' 2>&1); then
  release=$(sed -n 1p <<<"$info"); kernel=$(sed -n 2p <<<"$info")
  uptime_d=$(( $(sed -n 3p <<<"$info" | cut -d. -f1) / 86400 )); upgradable=$(sed -n 4p <<<"$info")
  echo "  firmware:   $release"
  echo "  kernel:     $kernel"
  echo "  uptime:     ${uptime_d}d"
  echo "  upgradable: $upgradable packages (from the last 'opkg update'/'apk update', may be stale)"
  version=$(awk '{print $2}' <<<"$release")
  case "$version" in
    "$stable") echo "  OK: on current stable" ;;
    "$oldstable") warn "on oldstable, plan an upgrade to $stable" ;;
    *) warn "$version is not a supported release (stable $stable, oldstable $oldstable)" ;;
  esac
else
  warn "router unreachable over SSH: $info"
fi

section "OpenWrt security advisories (latest 5, https://openwrt.org/advisory/start)"
curl -fsS --max-time 20 https://openwrt.org/advisory/start \
  | grep -o -E '>Security Advisory [^<]+' | sed 's/^>/  /' | head -5

section "Backups"
last=$(ls -1d "$ROOT"/backup/*/ 2>/dev/null | sort | tail -1)
if [ -z "$last" ]; then
  warn "no backups, run scripts/backup-flash.sh"
else
  age=$(( ( $(date +%s) - $(stat -c %Y "$last") ) / 86400 ))
  echo "  latest: $(basename "$last") (${age}d ago)"
  [ "$age" -le 31 ] || warn "older than a month, run scripts/backup-flash.sh"
fi
