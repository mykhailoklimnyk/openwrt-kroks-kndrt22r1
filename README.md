# OpenWrt for Kroks KNdRt22R1 (Rt-Brd eX) with Quectel EP06-E

Current OpenWrt (25.12) for the Kroks KNdRt22R1 board, which upstream OpenWrt does not
support and whose vendor firmware is stuck on OpenWrt 19.07. The build turns the board
into a wired LTE SOCKS5 gateway: fast public-IP rotation by URL, SOCKS5 with password and
IP allowlist, ModemManager, LuCI. Wi-Fi is left out on purpose.

Українською — [нижче](#українською).

> **Flashing a custom firmware can brick the board.** Keep a full flash backup and a
> 3.3 V USB-UART adapter at hand. Images published by CI are pre-releases until someone
> has flashed and checked them on real hardware.

## Hardware

| | |
| --- | --- |
| SoC | MediaTek MT7620A, 580 MHz |
| RAM | 128 MiB |
| Flash | 32 MiB SPI NOR, Winbond W25Q256 (the vendor layout uses the first 16 MiB) |
| Ethernet | 1 × 10/100 LAN |
| Modem | mini PCIe (USB 2.0), Quectel EP06-E; modem reset on GPIO 36 (`modem1reset`) |
| LEDs | status (green), LAN (white), WLAN (yellow, shows LTE in this build), power (blue, fixed) |
| Button | reset: short press reboots, ≥ 5 s resets to defaults |
| Serial | 57600 8N1, 3.3 V |
| Boot loader | U-Boot 1.1.3 (Ralink SDK) |

## Repository layout

| Path | What |
| --- | --- |
| `firmware/port/` | the board port: device tree, device profile (`device.mk`), board.d snippets for LEDs and the switch |
| `firmware/port/patches/` | kernel patches not in OpenWrt yet (none at the moment) |
| `firmware/port/package-patches/<pkg>/` | package patches; `microsocks` relays data with `splice()` |
| `firmware/files/` | files added to the image (see [What the image adds](#what-the-image-adds)) |
| `firmware/config/diffconfig` | package selection |
| `firmware/build.sh`, `Dockerfile`, `compose.yml` | containerised build of any OpenWrt release |
| `.github/workflows/build.yml` | CI: weekly check for a new OpenWrt release, build, pre-release |
| `scripts/` | flash backup, pre-flash image check, monthly audit, rollback to the vendor firmware |

## Building

Any Docker host with ~25 GB free disk and 4+ GB RAM:

```sh
docker build -t kndrt22r1-builder firmware
REPO=$PWD VERSION=25.12.6 docker compose -f firmware/compose.yml -p openwrt-kndrt22r1 up
```

`VERSION` empty means the current OpenWrt stable release. Images land in
`firmware/images/<version>/`. The first build takes hours (toolchain), later ones minutes.
`firmware/progress.sh` estimates how far a running build is. `UID_GID` (default `1000:1000`) must own the repository checkout; `CPUS`, `JOBS`, `MEM` and
`MEMSWAP` tune the container; gcc needs 0.5–1 GB per job.

`build.sh` clones the release tag, applies the port, and fails loudly if any part no longer
fits (patch, board.d insertion, device profile), so a new release never yields a half-port.

### CI

Every Monday the workflow checks `downloads.openwrt.org/.versions.json`. If there is no
release `openwrt-<stable>` in this repository yet, it builds that version from scratch on a
GitHub runner, checks the image with `scripts/preflash-check.py`, and publishes it as a
**pre-release**. A failed build means the new OpenWrt release broke the port; GitHub mails
the repository owner. Pushes to `firmware/` are built too, without a release. Builds of other
versions: Actions → build → Run workflow.

## Installing

1. Back up the whole flash: `scripts/backup-flash.sh` (over SSH, verified with SHA-256).
2. Check the image: `python -I scripts/preflash-check.py <...>-squashfs-sysupgrade.bin`.
   It must print `READY TO FLASH`.
3. From the vendor firmware: copy the image to `/tmp/fw.bin` and run
   `sysupgrade -n /tmp/fw.bin` (`-n`: the vendor configuration is not compatible).
4. Later upgrades keep the configuration:
   `sysupgrade -T /tmp/fw.bin && sysupgrade /tmp/fw.bin`.

The first boot takes about 1.5–2 minutes. Defaults: 192.168.1.1, user `root` without a
password; set one in LuCI first.

## What the image adds

**IP rotation by URL.** `http://192.168.1.1/cgi-bin/rotate-ip?token=<token>` returns
`{"ok","changed","method","old_ip","new_ip","seconds"}`. The token is generated on first boot
in `/etc/lte-rotate.token` and kept across upgrades. HTTP status: 200 done, 403 bad token,
409 a rotation is already running, 502 failed. The same from a shell: `lte-rotate`.

How it works (`/usr/sbin/lte-rotate`): `AT+CGATT=0/1` (packet detach/attach) gets a new PDN
session and with it a new address behind the operator's CGNAT; `AT+CFUN=4/1` is the fallback,
`ifup lte` the last resort. The ModemManager bearer is reconnected and the new address handed
to netifd with `proto_send_update`, without restarting the interface. A plain bearer
reconnect is faster (2.2 s) but keeps the same IP. While a rotation runs,
`/var/run/lte-rotate` makes the ModemManager hook `10-report-down` leave the interface alone.
microsocks is stopped for the rotation: proxied connections do not survive the IP change and
would otherwise hang until the client's timeout. It is killed first because under full load a
normal stop takes ~5 s.

Measured on Kyivstar (Ukraine): 4.3 s idle, 4.5–5 s under full proxy load; new IP every time.

**SOCKS5.** microsocks on `192.168.1.1:1080`, user `lte`, a random password generated on
first boot (`uci get microsocks.config.password`). Only hosts in the firewall ipset
`socks_allow` may connect (by default `192.168.1.2`). To allow another one:

```sh
uci add_list firewall.socks_allow.entry=192.168.1.3 && uci commit firewall && fw4 reload
```

The `splice()` patch keeps proxied data in the kernel: ~40 → ~51–56 Mbit/s through the proxy,
30 % less CPU per Mbit. The ceiling of the board is ~75 Mbit/s, and the 100 Mbit LAN port
caps it at ~94 anyway.

**Modem.** ModemManager over QMI, with drivers for every EP06 USB mode (QMI, ECM, MBIM).
AT commands go through ModemManager (`mmcli -m 0 --command=...`), so scripts never fight it
for the AT port; `sms-tool` can talk to the spare port `/dev/ttyUSB3`.

**Other.** The yellow LED shows the LTE link. `speedtest` (speedtest.net client),
`prometheus-node-exporter-lua` with the ModemManager collector.

## Board quirks

- **The vendor U-Boot reads the flash with 3-byte addresses only.** Linux switches the
  32 MiB W25Q256 to 4-byte addressing, and a SoC reset does not reset the flash, so after a
  reboot U-Boot cannot read it and the board hangs (only the blue and white LEDs on). The
  device tree sets `broken-flash-reset`: the kernel returns the flash to 3-byte mode before a
  reboot. That cannot happen on a kernel crash or a watchdog reset; then only a power cycle
  helps.
- The U-Boot web failsafe could not be reached on this board; the serial console menu
  (TFTP) works.

## Recovery

- Back to the vendor firmware: `scripts/rollback-to-vendor.sh` writes `mtd3_firmware.bin`
  from the backup.
- Board does not boot: serial console at 57600 → U-Boot menu → load an image over TFTP,
  or write the backup `full-16MB.bin` with an SPI programmer.

## Upkeep

`scripts/audit.sh`, by hand once a month: OpenWrt stable vs. what the router runs, upgradable
packages, recent OpenWrt security advisories, backup age.

## License

GPL-2.0, like OpenWrt. `10-report-down` is a modified copy of the OpenWrt ModemManager hook
(CC0-1.0).

---

## Українською

Свіжа OpenWrt (25.12) для плати Kroks KNdRt22R1: офіційної підтримки немає, а заводська
прошивка застрягла на 19.07. Збірка робить з плати дротовий LTE-шлюз SOCKS5: зміна IP за
посиланням (~4–5 с), SOCKS5 з паролем і списком дозволених IP, ModemManager, LuCI. Wi-Fi
вимкнений навмисно.

- **Збірка:** будь-який хост з Docker, ~25 ГБ диска: див. [Building](#building).
  CI щотижня сам пробує зібрати новий реліз OpenWrt і викладає образ як pre-release.
- **Прошивка:** спершу повний бекап флешу (`scripts/backup-flash.sh`) і перевірка образу
  (`scripts/preflash-check.py`). З заводської прошивки: `sysupgrade -n /tmp/fw.bin`.
- **Головна особливість плати:** флеш W25Q256 і старий U-Boot. Без `broken-flash-reset` у
  device tree плата зависала після кожного перезавантаження. Тепер звичайний `reboot`
  працює; після падіння ядра чи watchdog може знадобитися перепідключити живлення.
- **Відновлення:** UART 57600 (3,3 В) → меню U-Boot → TFTP, або програматор і бекап.
