# x16lib -- ca65 edition

A native ca65 port of the library: same layout, same X16_USE_* gates,
same macros and routine contracts as src_acme/, assembled as one
translation unit:

    ca65 --cpu 65C02 -I src_ca65 -o prog.o prog.s
    ld65 -C yourprog.cfg -o PROG.PRG prog.o

MAINTENANCE: src_acme/ is the reference implementation. Do not edit
the generated files here -- fix src_acme/, then regenerate:

    python tools\acme2ca65.py src_acme src_ca65
    python tools\acme_doc2ca65.py
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
