#!/bin/sh
. /lib/functions.sh
. /lib/netifd/netifd-proto.sh

IFACE=lte
FLAG=/var/run/lte-rotate

cs() { cut -d' ' -f1 /proc/uptime | tr -d .; }
secs() { echo "$(( $1 / 100 )).$(( $1 % 100 / 10 ))"; }
at() { mmcli -m 0 --command="$1" 2>&1; }
attached() { at 'AT+CGATT?' | grep -q 'CGATT: 1'; }
bearer() { mmcli -m 0 --output-keyvalue | sed -n 's/^modem.generic.bearers.value\[1\] *: *//p'; }
bfield() { echo "$1" | sed -n "s/^bearer.ipv4-config.$2 *: *//p"; }
extip() { uclient-fetch -4 -q -T 4 -O - http://speed.cloudflare.com/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p'; }

apply_bearer() {
	local kv addr prefix gw mtu dns
	kv=$(mmcli -b "$1" --output-keyvalue)
	addr=$(bfield "$kv" address); prefix=$(bfield "$kv" prefix); gw=$(bfield "$kv" gateway); mtu=$(bfield "$kv" mtu)
	[ -n "$addr" ] && [ "$addr" != "--" ] || return 1
	proto_init_update wwan0 1
	proto_add_ipv4_address "$addr" "$prefix"
	[ -n "$gw" ] && [ "$gw" != "--" ] && proto_add_ipv4_route 0.0.0.0 0 "$gw" "$addr"
	for dns in $(echo "$kv" | sed -n 's/^bearer.ipv4-config.dns.value\[[0-9]*\] *: *//p'); do proto_add_dns_server "$dns"; done
	proto_send_update "$IFACE"
	[ -n "$mtu" ] && [ "$mtu" != "--" ] && ip link set wwan0 mtu "$mtu"
	return 0
}

wait_until() {
	local n=0
	until eval "$1"; do n=$((n + 1)); [ "$n" -ge "$2" ] && return 1; done
}

rotate() {
	case "$1" in
	bearer) mmcli -b "$B" --disconnect >/dev/null 2>&1 ;;
	cgatt)  at 'AT+CGATT=0' >/dev/null; at 'AT+CGATT=1' >/dev/null ;;
	cfun4)  at 'AT+CFUN=4' >/dev/null; at 'AT+CFUN=1' >/dev/null ;;
	cfun0)  at 'AT+CFUN=0' >/dev/null; at 'AT+CFUN=1' >/dev/null ;;
	rat)    at 'AT+QCFG="nwscanmode",2,1' >/dev/null
	        wait_until attached 40
	        at 'AT+QCFG="nwscanmode",0,1' >/dev/null ;;
	*) echo "unknown method $1" >&2; exit 2 ;;
	esac
}

METHOD=${1:?method}
RUNS=${2:-3}
for run in $(seq 1 "$RUNS"); do
	B=$(bearer); old=$(extip)
	touch "$FLAG"; t0=$(cs)
	rotate "$METHOD"
	wait_until attached 60 || echo "  run $run: not attached"
	t1=$(cs)
	B=$(bearer)
	mmcli -b "$B" --connect >/dev/null 2>&1 || { sleep 1; mmcli -b "$B" --connect >/dev/null 2>&1; }
	t2=$(cs)
	apply_bearer "$B" || echo "  run $run: no bearer address"
	wait_until 'ping -c1 -W1 1.1.1.1 >/dev/null 2>&1' 15 || echo "  run $run: no traffic"
	t3=$(cs)
	rm -f "$FLAG"
	new=$(extip)
	rat=$(at 'AT+QNWINFO' | sed -n 's/.*QNWINFO: "\([^"]*\)",[^,]*,"\([^"]*\)".*/\1 \2/p')
	echo "$METHOD run $run: total $(secs $((t3 - t0)))s (attach $(secs $((t1 - t0)))s, bearer $(secs $((t2 - t1)))s, routing $(secs $((t3 - t2)))s) | $old -> $new $([ "$old" != "$new" ] && echo CHANGED || echo same) | $rat"
	sleep 3
done
