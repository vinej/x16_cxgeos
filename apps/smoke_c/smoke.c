/* =====================================================================
 * CXRF :: apps/smoke_c/smoke.c -- the portable C SDK smoke test
 * =====================================================================
 * One compiler-agnostic C app that drives the kernel through csdk. It is
 * built by EVERY supported C compiler (llvm-mos, cc65, ...) from this one
 * source: csdk sits above the shared cx_call_* surface, so only the
 * generated header underneath it changes. Prints a start marker, makes a
 * spread of calls (byte arg, pointer arg, word args, a returning call),
 * prints an OK marker if it survived, and exits to the shell. Headless:
 * the boot smoke greps stdout for "SMOKE C OK".
 * ===================================================================== */
#if defined(__clang__)
#include "sdk/include_llvm/cxrf.h"    /* llvm-mos */
#elif defined(CX_OSCAR64)
#include "sdk/include_oscar64/cxrf.h" /* oscar64 (-dCX_OSCAR64) */
#elif defined(CX_KICKC)
#include "sdk/include_kickc/cxrf.h"   /* KickC (-DCX_KICKC) */
#elif defined(__VBCC__)
#include <stdio.h>                      /* putchar -> CHROUT on the +x16 target */
#include "sdk/include_vbcc/cxrf.h"    /* vbcc (links cxrun.s) */
#else
#include "sdk/include_cc65/cxrf.h"    /* cc65 (__CC65__) */
#endif
#include "csdk/cxsdk.h"

/* CHROUT one byte through the KERNAL. <cbm.h> compilers use cbm_k_chrout;
 * oscar64/kickc reach $FFD2 with their own inline asm. */
static void cx_chrout(unsigned char c)
{
#if defined(CX_HAVE_CBM)
    cbm_k_chrout(c);
#elif defined(CX_OSCAR64)
    __asm {
        lda c
        jsr 0xffd2
    }
#elif defined(CX_KICKC)
    asm {
        lda c
        jsr $ffd2
    }
#elif defined(__VBCC__)
    putchar(c);                         /* the +x16 target routes it to CHROUT */
#endif
}

/* The headless markers as EXPLICIT ASCII bytes, not string literals: cc65
 * translates C literals to PETSCII at compile time (so 'S' emits $D3), and
 * the boot smoke greps for ASCII. A byte array is emitted verbatim by every
 * compiler, so the marker reaches -echo the same on all of them.
 *   "SMOKE C UP\r"                    "SMOKE C OK\r" */
static const unsigned char M_UP[] = {
    0x53,0x4D,0x4F,0x4B,0x45,0x20,0x43,0x20,0x55,0x50,0x0D,0 };
static const unsigned char M_OK[] = {
    0x53,0x4D,0x4F,0x4B,0x45,0x20,0x43,0x20,0x4F,0x4B,0x0D,0 };

static void mark(const unsigned char *b)
{
    while (*b) cx_chrout(*b++);
}

int main(void)
{
    mark(M_UP);                         /* load + run worked */

    cx_gfx_init();                      /* a no-arg call */
    cx_clear(0);                        /* a byte arg (A) */
    cx_say("hi from C, through the jump table", 24, 200);  /* pointer + words */
    cx_frame(20, 20, 300, 160, 3);      /* four words + a byte */
    cx_circle(160, 120, 40, 3);         /* the shape call */
    cx_p[0] = (unsigned char)cx_version();  /* a call that returns in A/X */

    mark(M_OK);                         /* survived every call -> the pass line */
    cx_exit();                          /* back to the shell (never returns) */
    return 0;
}
