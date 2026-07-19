#!/usr/bin/env python3
"""mapreport.py -- the memory budget, read back from the linker.

ld65 already enforces the hard ceilings (a region that overflows fails
the link), but it enforces them silently until the day it refuses. This
tool reads build/CXKERNEL.map after every kernel build and prints what
the budget actually looks like: per region, what is used, what is free,
and how close the image is to the next wall -- so "resident overflowed
by 16 bytes" becomes a trend line instead of a surprise.

    python tools/mapreport.py                 # reads build/CXKERNEL.map
    python tools/mapreport.py path/to/a.map
    python tools/mapreport.py --selftest

Exit status: 1 if a region is over budget or a pinned address moved
(RESIDENT must start where kernel.cfg promises), else 0. Warnings
(>= 85% full, or under the free-byte floor) print but do not fail --
the point is to see the wall coming, not to hit a different wall.

The region table below MIRRORS kernel/kernel.cfg. Change them together,
in the same commit, or this report lies.
"""

import re
import sys

# --- the ledger this tool asserts (mirror of kernel/kernel.cfg) --------

JTAB_START = 0x8010
JTAB_SIZE = 0x0195          # the slot reserve: JTAB_SIZE // 3 = 135 slots
                            # ($81A5-$81A8 is the build word, banks.inc)
RESIDENT_START = 0x81A9     # pinned: the byte after the slot reserve
RESIDENT_SIZE = 0x1457
OVL_START = 0x9600
OVL_SIZE = 0x0900           # one engine image at a time lives here

BANK_SIZE = 0x2000

# region name -> (capacity, [segments whose LOAD lands there])
# Optional segments simply don't appear in the map until they exist.
REGIONS = [
    ("JTAB",     JTAB_SIZE,     ["JUMPTAB"]),
    ("RESIDENT", RESIDENT_SIZE, ["CODE", "RODATA", "DATA", "BSS"]),
    ("BANK2",    BANK_SIZE,     ["B2CODE"]),
    ("BANK3",    BANK_SIZE,     ["OV0CODE"]),
    ("BANK4",    BANK_SIZE,     ["OV1CODE"]),
    ("BANK5",    BANK_SIZE,     ["B5CODE", "OV2CODE", "OV3CODE"]),
    ("BANK16",   BANK_SIZE,     ["B16SIG", "B16CODE"]),
    ("BANK17",   BANK_SIZE,     ["B17SIG", "B17CODE"]),
    ("BANK18",   BANK_SIZE,     ["B18SIG", "B18CODE"]),
    ("BANK19",   BANK_SIZE,     ["B19SIG", "B19CODE"]),
]

# every engine image must fit the window it runs in
OVL_IMAGES = ["OV0CODE", "OV1CODE", "OV2CODE", "OV3CODE"]

WARN_PCT = 85               # a region this full is worth a look
WARN_FREE = 256             # ...as is one with less than this to give
FAIL_FREE_RESIDENT = 64     # the hard floor. P5 set this at 128; the
                            # sprite-collision feature (cx_spr_collide +
                            # the EVS_SPRCOL arming) then spent ~46 B of
                            # that headroom. INTERIM 64 until the planned
                            # x16_library granularity reclaim (unused IRQ/
                            # VERA/SCREEN/INPUT code, ~110-160 B) restores
                            # the margin -- then this goes back to 128.


def parse_map(text: str) -> dict:
    """Segment name -> (start, size) from an ld65 map's Segment list."""
    m = re.search(r"^Segment list:\s*$", text, re.M)
    if not m:
        raise ValueError("no 'Segment list:' section -- not an ld65 map?")
    segs = {}
    for line in text[m.end():].splitlines():
        row = re.match(r"^(\w+)\s+([0-9A-Fa-f]{6})\s+([0-9A-Fa-f]{6})\s+([0-9A-Fa-f]{6})", line)
        if row:
            segs[row.group(1)] = (int(row.group(2), 16), int(row.group(4), 16))
        elif segs and line.strip() == "":
            break
    if not segs:
        raise ValueError("Segment list held no rows")
    return segs


def report(segs: dict, out=sys.stdout) -> int:
    """Print the budget table; return the exit status."""
    status = 0
    print(f"      {'region':<9} {'used':>6} {'free':>6}  full", file=out)
    for name, cap, members in REGIONS:
        present = [s for s in members if s in segs]
        if not present:
            continue
        used = sum(segs[s][1] for s in present)
        free = cap - used
        pct = 100 * used // cap
        flags = []
        if free < 0:
            flags.append("OVER BUDGET")
            status = 1
        elif pct >= WARN_PCT or free < WARN_FREE:
            flags.append("tight")
        if name == "JTAB":
            slots = used // 3
            room = (cap // 3) - slots
            flags.append(f"{slots} slots, {room} in reserve")
        print(f"      {name:<9} {used:>6} {free:>6}  {pct:>3}%  {' '.join(flags)}", file=out)
        if name == "RESIDENT":
            start = segs[present[0]][0]
            if start != RESIDENT_START:
                print(f"      RESIDENT starts at ${start:04X}, kernel.cfg promises "
                      f"${RESIDENT_START:04X} -- the pin moved", file=out)
                status = 1
            if 0 <= free < FAIL_FREE_RESIDENT:
                print(f"      RESIDENT free fell under the {FAIL_FREE_RESIDENT}-byte floor", file=out)
                status = 1
    for img in OVL_IMAGES:
        if img in segs and segs[img][1] > OVL_SIZE:
            print(f"      {img} is {segs[img][1]} bytes -- past the "
                  f"{OVL_SIZE}-byte overlay window", file=out)
            status = 1
    biggest = max((segs[i][1] for i in OVL_IMAGES if i in segs), default=0)
    print(f"      OVL       {biggest:>6} {OVL_SIZE - biggest:>6}  {100 * biggest // OVL_SIZE:>3}%  "
          f"(largest engine image vs the window)", file=out)
    return status


SELFTEST_MAP = """\
Modules list:
-------------
CXKERNEL.o:
    CODE              Offs=000000  Size=00148C  Align=00001  Fill=0000


Segment list:
-------------
Name                   Start     End    Size  Align
----------------------------------------------------
LOADADDR              007FFF  008000  000002  00001
JUMPHDR               008000  00800F  000010  00001
JUMPTAB               008010  00812C  00011D  00001
CODE                  0081A9  00951C  001373  00001
OV0CODE               009600  009EB3  0008B4  00001
OV1CODE               009600  009CFA  0006FB  00001
OV2CODE               009600  009661  000062  00001
OV3CODE               009600  0098FF  000300  00001
B2CODE                00A000  00BB3B  001B3C  00001
B5CODE                00A000  00B300  001301  00001


Exports list by name:
---------------------
"""


def selftest() -> int:
    import io
    segs = parse_map(SELFTEST_MAP)
    assert segs["CODE"] == (0x81A9, 0x1373), segs["CODE"]
    assert segs["B2CODE"][1] == 0x1B3C
    assert segs["JUMPTAB"][1] == 0x011D
    sink = io.StringIO()
    assert report(segs, sink) == 0, sink.getvalue()
    text = sink.getvalue()
    assert "95 slots, 40 in reserve" in text, text
    assert re.search(r"RESIDENT\s+4979\s+228", text), text  # 0x1373 / 0x1457-0x1373
    assert re.search(r"BANK5\s+5731\s+2461", text), text
    # an overflowed bank must fail
    fat = dict(segs)
    fat["B2CODE"] = (0xA000, 0x2001)
    assert report(fat, io.StringIO()) == 1
    # a moved resident pin must fail
    moved = dict(segs)
    moved["CODE"] = (0x8200, 0x1000)
    assert report(moved, io.StringIO()) == 1
    # a resident image under the free-byte floor must fail
    tight = dict(segs)
    tight["CODE"] = (0x81A9, 0x1457 - 50)   # 50 free < FAIL_FREE_RESIDENT
    assert report(tight, io.StringIO()) == 1
    print("mapreport: selftest OK")
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    path = argv[0] if argv else "build/CXKERNEL.map"
    try:
        with open(path, encoding="ascii", errors="replace") as f:
            segs = parse_map(f.read())
    except OSError as e:
        print(f"mapreport: {e}", file=sys.stderr)
        return 1
    return report(segs)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
