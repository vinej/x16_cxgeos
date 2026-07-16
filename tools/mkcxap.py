#!/usr/bin/env python3
"""mkcxap.py -- wrap a PRG as a CXGEOS app (.CXA).

A CXAP is a 32-byte header in front of an ordinary PRG (docs/formats.md).
That is the whole trick: every one of the twelve toolchains already
emits a working PRG at $0801, so every one of them can produce a CXGEOS
app without touching a linker script. This tool prepends the header.

The entry point defaults to the address in the PRG's own BASIC stub --
the SYS line every toolchain emits -- so for the common case nothing
needs to be stated:

    python tools/mkcxap.py build/SHELL.PRG build/SHELL.CXA --name Shell

    --entry 0x0810   for a PRG with no stub
    --min-abi 1      the lowest kernel ABI the app can run on

Checked here, because the loader will refuse them at run time: the PRG
must load at $0801, the entry must land inside it, and the whole file
must fit under $8000, where the kernel image begins.
"""

import argparse
import io
import re
import sys

APP_BASE = 0x0801
APP_TOP = 0x8000     # the kernel image starts here; an app ends below it
MAGIC = b"CXAP"


def sys_entry(payload: bytes) -> int:
    """The SYS target of a standard BASIC stub, or a ValueError.

    A stub is: next-line pointer (2), line number (2), the $9E SYS
    token, ASCII digits (perhaps after spaces), a zero, then the
    end-of-program zero word. Everything that matters is the digits.
    """
    if len(payload) < 7 or payload[4] != 0x9E:
        raise ValueError("no BASIC stub: give --entry explicitly")
    m = re.match(rb" *(\d+)", payload[5:])
    if not m:
        raise ValueError("SYS with no target: give --entry explicitly")
    return int(m.group(1))


def build(prg: bytes, name: str, min_abi: int, entry: int | None) -> bytes:
    if len(prg) < 3:
        raise ValueError("not a PRG: too short to hold a load address")
    load = prg[0] | (prg[1] << 8)
    if load != APP_BASE:
        raise ValueError(f"PRG loads at ${load:04X}, apps load at ${APP_BASE:04X}")
    payload = prg[2:]
    end = APP_BASE + len(payload)
    if end > APP_TOP:
        raise ValueError(f"app ends at ${end:04X}, past the ${APP_TOP:04X} ceiling")

    if entry is None:
        entry = sys_entry(payload)
    if not (APP_BASE <= entry < end):
        raise ValueError(f"entry ${entry:04X} is outside the app (${APP_BASE:04X}-${end - 1:04X})")

    raw = name.encode("ascii")
    if len(raw) > 16:
        raise ValueError("name is stored in 16 bytes")

    hdr = io.BytesIO()
    hdr.write(MAGIC)
    hdr.write(min_abi.to_bytes(2, "little"))
    hdr.write(entry.to_bytes(2, "little"))
    hdr.write(bytes(1))                    # flags: none defined yet
    hdr.write(bytes(7))                    # reserved
    hdr.write(raw.ljust(16, b"\0"))
    assert hdr.tell() == 32
    return hdr.getvalue() + prg


def selftest() -> int:
    stub = bytes([0x0B, 0x08, 0x0A, 0x00, 0x9E]) + b"2061" + bytes(3)
    prg = bytes([0x01, 0x08]) + stub + b"\xEA" * 8

    out = build(prg, "T", 1, None)
    assert out[:4] == MAGIC
    assert out[4:6] == b"\x01\x00", "min-abi"
    assert out[6:8] == b"\x0D\x08", "SYS 2061 = $080D"
    assert out[16:18] == b"T\x00", "name"
    assert out[32:] == prg, "the PRG rides unchanged"

    out = build(prg, "T", 1, 0x0803)
    assert out[6:8] == b"\x03\x08", "--entry wins"

    for bad, why in [
        (bytes([0x00, 0x10]) + stub, "load address"),
        (bytes([0x01, 0x08]), "no stub, no --entry"),
        (bytes([0x01, 0x08]) + b"\xEA" * (APP_TOP - APP_BASE + 1), "too big"),
    ]:
        try:
            build(bad, "T", 1, None)
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted a PRG with a bad {why}")

    try:
        build(prg, "T", 1, 0x4000)
    except ValueError:
        pass
    else:
        raise AssertionError("accepted an entry outside the app")

    print("mkcxap: selftest ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("prg", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--name", default="")
    ap.add_argument("--min-abi", type=lambda s: int(s, 0), default=1)
    ap.add_argument("--entry", type=lambda s: int(s, 0), default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.prg or not args.out:
        ap.error("prg and out are required (or --selftest)")

    with open(args.prg, "rb") as f:
        prg = f.read()
    try:
        blob = build(prg, args.name, args.min_abi, args.entry)
    except ValueError as e:
        print(f"mkcxap: {args.prg}: {e}", file=sys.stderr)
        return 1
    with open(args.out, "wb") as f:
        f.write(blob)
    entry = int.from_bytes(blob[6:8], "little")
    print(f"mkcxap: {args.out}: {len(blob)} bytes, entry ${entry:04X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
