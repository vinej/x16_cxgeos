#!/usr/bin/env python3
"""icongen.py -- build the CXGEOS icon sheet from ASCII art.

An icon is 24x24, 2bpp (four shades), the same pixel format the graphics
port draws in: mode 0 blits it straight to the framebuffer; mode 1 expands
each 2-bit index through a four-colour map, the way its text does. So one
icon definition serves both bitmap modes.

Each glyph below is 24 rows of 24 chars:
    ' ' = 0 (background)   '.' = 1 (light)   ':' = 2 (mid)   '#' = 3 (ink)

Packed MSB-first, four pixels per byte (the leftmost pixel is bits 7:6),
6 bytes per row, 24 rows = 144 bytes per icon. The sheet is the icons in
ID order, concatenated, written to fonts/icons.bin (incbin'd into the
kernel's widget bank).

    python tools/icongen.py            # -> fonts/icons.bin
    python tools/icongen.py --selftest

The IDs are the contract the kernel and the filer share (kernel/ui/icon.asm
ICON_*, apps/filer maps a file's kind -- and known demo names -- to one):
    0 up   1 folder   2 app   3 font   4 accessory   5 data   6 image   7 disk
    8 calc 9 paint 10 game 11 text 12 sound 13 sprite 14 tile 15 term
    16 gears 17 globe
"""

import sys
from pathlib import Path

W = H = 24
ROWBYTES = W // 4            # 6
ICONBYTES = ROWBYTES * H     # 144

# --- the art. 24 rows x 24 cols each. -------------------------------------
ICONS = {}

ICONS["up"] = """


           ##
          ####
         ##::##
        ##::::##
       ##::::::##
      ##::::::::##
     ##::::::::::##
    ##::::::::::::##
   #####::::::#####
      ##::::::##
      ##::::::##
      ##::::::##
      ##::::::##
      ##::::::##
      ##::::::##
      ########






"""

ICONS["folder"] = """


    #######
   #.......##
   #.........#########
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
   #..................#
    ####################





"""

ICONS["app"] = """

   ################
   #..............##
   #..............#.#
   #..............#..#
   #..............####
   #....######....#....
   #....#....#....#....
   #....#....#.......#
   #....#....#....... #
   #....######.......
   #................. #
   #....######.......
   #....#....#....... #
   #....#....#.......
   #....#....#....... #
   #....######.......
   #................. #
   #.................
   #################.




"""

ICONS["font"] = """


   ################
   #..............#
   #......##......#
   #.....####.....#
   #.....#..#.....#
   #....##..##....#
   #....#....#....#
   #....#....#....#
   #...##....##...#
   #...########...#
   #...#......#...#
   #..##......##..#
   #..#........#..#
   #.###......###.#
   #..............#
   #..............#
   ################





"""

ICONS["accessory"] = """


        ######
      ##......##
     #..........#
    #.....##.....#
   #......##......#
   #......##......#
   #......##......#
  #.......##.......#
  #.......##.......#
  #.......#########
  #................#
  #................#
   #..............#
   #..............#
    #............#
     #..........#
      ##......##
        ######




"""

ICONS["data"] = """

   ############
   #..........###
   #..........#.#
   #..........#..#
   #..........####
   #..............#
   #...########...#
   #..............#
   #...########...#
   #..............#
   #...########...#
   #..............#
   #...########...#
   #..............#
   #...########...#
   #..............#
   #..............#
   ################





"""

ICONS["image"] = """

   ################
   #..............#
   #....####......#
   #...#....#.....#
   #...#....#.....#
   #....####......#
   #..............#
   #..............#
   #.......##.....#
   #......####....#
   #.....##::##...#
   #....##::::##..#
   #...##::::::##.#
   #..##::::::::##
   #.##::::::::::#
   ################







"""

ICONS["disk"] = """

   ################
   #..######....#.#
   #..#....#....#..#
   #..#....#....####
   #..#....#.......#
   #..#....#.......#
   #..######.......#
   #...............#
   #...............#
   #..############.#
   #..#..........#.#
   #..#..........#.#
   #..#..........#.#
   #..#..........#.#
   #..#..........#.#
   #..############.#
   #...............#
   ################





"""

ICONS["calc"] = """


   ################
   #..............#
   #.############.#
   #.#..........#.#
   #.############.#
   #..............#
   #.##.##.##.##..#
   #.##.##.##.##..#
   #..............#
   #.##.##.##.##..#
   #.##.##.##.##..#
   #..............#
   #.##.##.##.##..#
   #.##.##.##.##..#
   #..............#
   ################


"""

ICONS["paint"] = """


       ########
     ##........##
    #...####.....#
   #...######.##..#
   #...######.####.#
   #...####...####.#
   #.........####..#
   #..####........#
   #.######...##..#
   #.######..####.#
   #.######..####.#
    #........####.#
    ##.........#.#
     ###......##
       ######


"""

ICONS["game"] = """



           ##
          ####
          ####
           ##
           ##
           ##
           ##
        ##########
       #::::::::::#
      #::::::::::::#
      #::::::::::::#
       #::::::::::#
        ##########



"""

ICONS["text"] = """


   ##############
   #............#
   #.#######....#
   #.#####......#
   #.########...#
   #.#####......#
   #............#
   #.#######....#
   #.######.....#
   #.########...#
   #.#####......#
   #.#######....#
   #............#
   ##############


"""

ICONS["sound"] = """



          ##
         ###
        ####
       #####
    #######::   ..
    #######::   ..
    #######::   ..
       #####
        ####
         ###
          ##



"""

ICONS["sprite"] = """



       #        #
        #      #
       ##########
      ###.####.###
     ##############
     #.############.
     #.#        #.#
        ###  ###
       ##      ##
      ##        ##



"""

ICONS["tile"] = """

   ################
   #....#....#....#
   #....#....#....#
   #....#....#....#
   ################
   #....#....#....#
   #....#....#....#
   #....#....#....#
   ################
   #....#....#....#
   #....#....#....#
   #....#....#....#
   ################

"""

ICONS["term"] = """


   ################
   #..............#
   #.############.#
   #.#..........#.#
   #.#.#........#.#
   #.#..#.......#.#
   #.#.#........#.#
   #.#....###...#.#
   #.#..........#.#
   #.############.#
   #.....####.....#
   #...########...#
   ################


"""

ICONS["gears"] = """


        ##  ##
       ########
     ###......###
    ##..######..##
    #..##....##..#
    ##.#..##..#.##
    #..#.####.#..#
    ##.#..##..#.##
    #..##....##..#
    ##..######..##
     ###......###
       ########
        ##  ##


"""

ICONS["globe"] = """


        ######
      ##..##..##
     #..#..#..#.#
    #..#...#...#.#
    #.#....#....#.
    ##############
    #.#....#....#.
    #..#...#...#.#
     #..#..#..#.#
      ##..##..##
        ######


"""

IDS = ["up", "folder", "app", "font", "accessory", "data", "image", "disk",
       "calc", "paint", "game", "text", "sound", "sprite", "tile", "term",
       "gears", "globe"]
PIX = {" ": 0, ".": 1, ":": 2, "#": 3}


def grid(art):
    # The `"""` opener contributes one leading empty line; drop it, then the
    # rest are the icon's rows top to bottom (blank rows kept -- they place
    # the drawing vertically). Pad/clip to exactly H rows and W cols.
    lines = art.split("\n")
    if lines and lines[0] == "":
        lines = lines[1:]
    rows = lines[:H] + [""] * max(0, H - len(lines))
    for r in lines[H:]:
        if r.strip():
            raise ValueError("icon art overflows 24 rows")
    out = []
    for r in rows[:H]:
        r = (r + " " * W)[:W]
        out.append([PIX[c] for c in r])
    return out


def pack(art):
    g = grid(art)
    b = bytearray()
    for row in g:
        for x0 in range(0, W, 4):
            p = row[x0:x0 + 4]
            b.append((p[0] << 6) | (p[1] << 4) | (p[2] << 2) | p[3])
    assert len(b) == ICONBYTES
    return bytes(b)


def build():
    sheet = bytearray()
    for name in IDS:
        sheet += pack(ICONS[name])
    return bytes(sheet)


def selftest():
    sheet = build()
    assert len(sheet) == ICONBYTES * len(IDS), len(sheet)
    for i, name in enumerate(IDS):
        icon = sheet[i * ICONBYTES:(i + 1) * ICONBYTES]
        assert len(icon) == ICONBYTES
        assert any(b != 0 for b in icon), f"{name} is blank (no ink)"
        assert any(b == 0 for b in icon), f"{name} has no background"
    # packing is MSB-first: a leading '#' in a row lands in bits 7:6
    row = pack("#" + "\n" * 23)          # one '#' at (0,0), rest blank
    assert (row[0] >> 6) == 3 and (row[0] & 0x3F) == 0, "MSB-first packing"
    print(f"icongen: selftest OK ({len(IDS)} icons, {len(sheet)} bytes)")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    out = Path(__file__).resolve().parent.parent / "fonts" / "icons.bin"
    out.write_bytes(build())
    print(f"icongen: {len(IDS)} icons -> {out} ({ICONBYTES * len(IDS)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
