import hashlib
import pathlib
import struct
import sys
import zlib

FIRMWARE_PARTITION = 0xEB0000
UIMAGE_MAGIC = 0x27051956
LOAD_ADDR = 0x80000000
IH_OS_LINUX, IH_ARCH_MIPS, IH_TYPE_KERNEL, IH_COMP_LZMA = 5, 5, 2, 3
BOARD = b"kndrt22r1"

failed = False

def check(ok, what):
    global failed
    failed |= not ok
    print(("  OK   " if ok else "  FAIL ") + what)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if len(args) != 1:
    sys.exit("usage: preflash-check.py [--no-backup] <...-squashfs-sysupgrade.bin>")
img_path = pathlib.Path(args[0])
img = img_path.read_bytes()
root = pathlib.Path(__file__).resolve().parent.parent

print(f"{img_path.name} ({len(img)} bytes)")
check(len(img) <= FIRMWARE_PARTITION,
      f"fits the firmware partition ({len(img)} <= {FIRMWARE_PARTITION})")

hdr = img[:64]
magic, hcrc, _, size, load, entry, dcrc, os_, arch, typ, comp = struct.unpack(">IIIIIIIBBBB", hdr[:32])
check(magic == UIMAGE_MAGIC, "legacy uImage header, as U-Boot 1.1.3 expects")
check(zlib.crc32(hdr[:4] + b"\0\0\0\0" + hdr[8:]) == hcrc, "uImage header CRC")
check(64 + size <= len(img) and zlib.crc32(img[64:64 + size]) == dcrc, "kernel data CRC")
check((os_, arch, typ) == (IH_OS_LINUX, IH_ARCH_MIPS, IH_TYPE_KERNEL), "Linux/MIPS kernel image")
check(comp == IH_COMP_LZMA, "lzma compression, same as the vendor kernel")
check(load == LOAD_ADDR and entry == LOAD_ADDR, f"load/entry {load:#x}/{entry:#x} == {LOAD_ADDR:#x}")
print(f"       kernel {size} bytes, name {hdr[32:64].split(b'\0')[0].decode(errors='replace')!r}")

tail = img[-8192:]
check(b"supported_devices" in tail and BOARD in tail,
      "sysupgrade metadata lists kndrt22r1 (old firmware will accept it)")

sums = img_path.with_name("SHA256SUMS")
if sums.exists():
    want = {l.split()[1].lstrip("*"): l.split()[0] for l in sums.read_text().splitlines() if l.strip()}
    check(want.get(img_path.name) == hashlib.sha256(img).hexdigest(), "SHA256 matches SHA256SUMS")
else:
    check(False, "SHA256SUMS next to the image")

if "--no-backup" not in sys.argv:
    backups = sorted(p for p in (root / "backup").glob("*/full-16MB.bin"))
    check(bool(backups), f"full flash backup present ({backups[-1].parent.name if backups else 'none'})")

print("\nREADY TO FLASH" if not failed else "\nDO NOT FLASH")
sys.exit(1 if failed else 0)
