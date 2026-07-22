/* =====================================================================
 * CXRF :: apps/beep/beep.c -- the audio example (llvm-mos)
 * =====================================================================
 * The sound example: a PSG scale on voice 0, a held YM (FM) note, and a
 * PCM blip, then a key returns to the desktop. Shows the csdk audio calls
 * -- cx_psg_* (or the cx_tone shortcut), cx_ym_*, and cx_pcm_*. The PSG
 * runs on the VERA sound generator and the YM through the ROM's FM driver
 * (both in a kernel bank); the PCM sample streams through the 4KB FIFO,
 * topped up each frame by the kernel's event IRQ. All reached through the
 * ABI like everything else.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

/* a C-major-ish scale as PSG frequency words (Hz * 2.68435): C4..C5 */
static const unsigned scale[8] = {
    703, 789, 886, 938, 1053, 1181, 1326, 1405
};

static unsigned char pcm[3000];        /* a PCM sample buffer, filled at run time */

/* spin for n frames using the event timer's frame counter */
static void wait_frames(unsigned char n) {
    unsigned char t = cx_frames();
    while ((unsigned char)(cx_frames() - t) < n)
        ;
}

int main(void) {
    unsigned char i;
    unsigned k;
    cx_event ev;

    cx_print("BEEP UP");

    cx_gfx_init();
    cx_clear(2);
    cx_say("beep -- a PSG scale, a YM note, then a PCM blip. a key exits.", 24, 200);

    cx_ev_init();                 /* the frame counter runs off its IRQ */
    cx_psg_init();
    cx_ym_init();

    for (i = 0; i < 8; i++) {     /* the PSG scale on voice 0 */
        cx_tone(0, scale[i], 50);
        wait_frames(12);
    }
    cx_psg_off(0);

    cx_ym_patch(0, 1);            /* a ROM FM patch, then a note */
    cx_ym_note(0, CX_YM(4, 1));   /* C in octave 4 */
    wait_frames(30);

    /* a PCM blip: a square wave streamed through the FIFO. The refiller
     * on the event IRQ keeps it fed; cx_pcm_active goes 0 when it ends. */
    for (k = 0; k < sizeof pcm; k++)
        pcm[k] = (k & 24) ? 55 : (unsigned char)(0 - 55);
    cx_pcm_ctrl(0x0F);            /* 8-bit mono, full volume */
    cx_pcm_play(pcm, sizeof pcm, 48);

    for (;;) {
        if (cx_poll(&ev) && ev.type == CX_ET_KEY)
            break;
    }
    cx_ym_off(0);
    cx_exit(); /* never returns */
    return 0;
}
