# x16lib -- ca65 edition

A native ca65 port of the library: same layout, same X16_USE_* gates,
same macros and routine contracts as src_acme/, assembled as one
translation unit:

    ca65 --cpu 65C02 -I src_ca65 -o prog.o prog.s
    ld65 -C yourprog.cfg -o PROG.PRG prog.o

MAINTENANCE: src_acme/ is the reference implementation. Do not edit
the generated files here -- fix src_acme/, then regenerate:

    python tools\acme2ca65.py src_acme src_ca65
    (test_ca65/runner.asm + testlib.asm are converted the same way;
    see build_ca65.ps1 / the commands in tools/acme2ca65.py's header)

Three files are HAND-MAINTAINED (ca65 cannot express their ACME
features) and are skipped by the converter:

    x16.asm            the root include (.setcpu, features, includes)
    core/macros.asm    the macro layer (same as dist/templates/)
    util/math.asm      trig tables inlined as literals

PROOF: test_ca65/runner.asm assembles to a byte-identical PRG (same
SHA-256) as the ACME build and passes the same 132-test suite on the
emulator:

    .\build_ca65.ps1 -Test

-- CXRF vendoring ----------------------------------------------------

This tree is a snapshot of x16_library/src_ca65 at **v0.11.1**, re-synced
wholesale (delete + copy). Two gates CXRF's split-bank kernel relies on
were upstreamed into x16_library v0.11.1, so a plain re-sync carries them
-- nothing to re-apply by hand:

    X16_SKIP_BASE          gfx/shapes.asm -- lets the file be .included a
                           second time (extras only), so CXRF can place
                           the base shapes in bank 17 and the polygon/arc/
                           pie extras in bank 19.
    X16_BITMAP8L_NO_INIT   gfx/bitmap8l.asm -- omits gfx8l_init, so a port
                           that programs the display mode itself does not
                           pull in screen_set_mode (SCREEN module).

The 2bpp/8bpp bitmap engines are `.include`d directly into their overlay
banks by kernel/video/engine0.asm (bitmap2h.asm, gfx2h_*) and engine1.asm
(bitmap8l.asm, gfx8l_*), NOT through X16_USE_BITMAP2H / X16_USE_BITMAP8L,
so only their VERA / VERAFX helpers land in the resident image.
