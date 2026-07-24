/* =====================================================================
 * CXRF :: apps/tiletext/tiletext.c -- the mode-2 text-overlay self-test
 * =====================================================================
 * Proves cx_tile_text: in tile mode, flip layer 1 to a 1bpp TEXT layer,
 * draw over the still-visible game world, then flip back -- and the
 * game's layer-1 map, its scroll, and its layer registers come back
 * EXACTLY as the game left them.
 *
 * It also proves the OV3T dialog port: while the overlay is up, it draws
 * a box with cx_rect / cx_frame / cx_say -- the SAME port calls a desktop
 * dialog uses -- which cx_tile_text routed to OV3T, so they land on the
 * text cells over the game world.
 *
 * It self-drives (no input) so it runs headless in the boot smoke and can
 * be captured to a gif: world+HUD, then the dialog over it, then the HUD
 * restored. After the round-trip it reads VERA and VRAM back and prints
 * TILETEXT OK / TILETEXT FAIL, then exits to the shell.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

/* VERA layer-1 config registers, to read back what cx_tile_text put them
 * to after the overlay is dismissed (they must be the game's values). */
#define L1_CONFIG    (*(volatile unsigned char *)0x9F34)
#define L1_MAPBASE   (*(volatile unsigned char *)0x9F35)
#define L1_TILEBASE  (*(volatile unsigned char *)0x9F36)
#define L1_HSCROLL_L (*(volatile unsigned char *)0x9F37)
#define L1_VSCROLL_L (*(volatile unsigned char *)0x9F39)

/* read one byte from VRAM (17-bit address) through data port 0 */
static unsigned char vread(unsigned long a) {
    CX__V_CTRL   = 0;
    CX__V_ADDR_L = (unsigned char)a;
    CX__V_ADDR_M = (unsigned char)(a >> 8);
    CX__V_ADDR_H = ((unsigned char)(a >> 16) & 0x0F) | 0x10;
    return CX__V_DATA0;
}

/* spin for `f` frames, so a captured gif has time on each state */
static void hold(unsigned char f) {
    unsigned char t = cx_frames();
    while ((unsigned char)(cx_frames() - t) < f)
        ;
}

static unsigned char tile[32];

/* a one-button alert, to prove the kernel's MODAL dialog runs on tiles */
CX_DIALOG(paused, "Resume the game?", "OK");

int main(void) {
    unsigned char x, i, ok = 1;
    unsigned char hud_before, alert_ret;
    cx_event k;

    cx_print("TILETEXT UP");

    cx_mode(CX_MODE_TILE, 0);

    /* one 4bpp tile at index 0: a 4x4 blue/white checker, so the world
     * reads as a grid the overlay floats over */
    for (i = 0; i < 32; i++) {
        unsigned char row = i >> 2, col = i & 3;   /* col 0-3 = px pairs */
        unsigned char a = ((row >> 2) ^ (col >> 1)) & 1;
        tile[i] = a ? 0x66 : 0x11;                 /* blue vs white */
    }
    cx_vram_write(CX_TILE_IMG, tile, 32);

    /* layer 0: the world -- a plain checker carpet */
    cx_tile_setup(0, 4);
    cx_tile_fill(0, CX_CELL(0, 0));

    /* layer 1: a game HUD map with a recognizable pattern (a run of
     * palette offsets across the top row) and a non-zero scroll -- the
     * exact state the round-trip must preserve */
    cx_tile_setup(1, 4);
    cx_tile_fill(1, CX_CELL(0, 1));
    for (x = 0; x < 20; x++)
        cx_tile_cell(1, x, 0, CX_CELL(0, x & 0x0F));
    cx_tile_scroll(1, 24, 8);

    cx_ev_init();
    cx_ev_mask(CX_EVS_KEYS);

    hold(45);                              /* [gif] the world + HUD */

    /* the HUD cell (col 5,row 0) high byte carries palette 5 */
    hud_before = vread(0x11000UL + 5 * 2 + 1);   /* layer-1 map (remapped) */

    /* --- raise the text overlay on layer 1 --- */
    cx_tile_text(1, 1);
    /* clear the text map to TRANSPARENT cells (colour 0 lets layer 0 show
     * through), so the world stays visible around the dialog */
    cx_tile_fill(1, 0x20);                 /* space, fg 0 / bg 0 = clear */
    /* draw a dialog box THROUGH THE PORT. cx_tile_text handed the port to
     * OV3T, so the same cx_rect / cx_frame / cx_say a desktop dialog draws
     * with now land on these text cells -- in CELL units (40x30). */
    cx_ink(1);                             /* white text ink */
    cx_rect(11, 11, 18, 7, 6);             /* a blue paper panel */
    cx_frame(11, 11, 18, 7, 1);            /* a white frame around it */
    cx_say("GAME PAUSED", 15, 13);         /* upper-case title */
    cx_say("dialog on tiles", 13, 15);     /* lower-case message */
    hold(70);                              /* [gif] the dialog over the world */

    /* the kernel's own MODAL dialog, on the very same overlay: post a
     * RETURN so the modal loop dismisses itself, and confirm cx_alert both
     * renders (menu_gate lets it through on tiles now) and returns the
     * button. Headless this proves the whole cx_alert path on mode 2. */
    k.type = CX_ET_KEY; k.detail = 0x0D;   /* RETURN picks button 0 */
    k.x = 0; k.y = 0; k.frame = 0;
    cx_post(&k);
    alert_ret = cx_alert(&paused);         /* draws, dispatches RETURN, returns 0 */

    /* --- dismiss it: the HUD must come straight back --- */
    cx_tile_text(1, 0);
    hold(45);                              /* [gif] HUD restored, untouched */

    /* the layer-1 registers must be the game's again */
    if (L1_CONFIG    != 0x12) ok = 0;      /* 64x32, 8x8, 4bpp */
    if (L1_MAPBASE   != 0x88) ok = 0;      /* $11000 (remapped) */
    if (L1_TILEBASE  != 0x00) ok = 0;      /* tiles at $00000 */
    if (L1_HSCROLL_L != 24)   ok = 0;      /* the scroll we set */
    if (L1_VSCROLL_L != 8)    ok = 0;
    /* and the HUD map in VRAM must be byte-for-byte what it was */
    if (hud_before != 0x50)   ok = 0;      /* palette 5 really was there */
    if (vread(0x11000UL + 5 * 2 + 1) != hud_before) ok = 0;
    if (alert_ret != 0)       ok = 0;      /* the modal alert ran and RETURN
                                            * picked button 0 */
    /* the $1F000 charset must be PETSCII upper/lower (screen-code order), the
     * set ov3t_say and the T3_* box glyphs assume: screen code $41 = 'A', not
     * a graphic. ov2_init loads it with SCREEN_SET_CHARSET(3); CHR$(14) alone
     * leaves upper/GRAPHICS there and every upper-case letter draws as a tile
     * graphic. Check the 'A' glyph's first two rows -- $18,$3C for the letter,
     * something filled/other for a graphic. */
    if (vread(0x1F000UL + 0x41 * 8) != 0x18) ok = 0;
    if (vread(0x1F000UL + 0x41 * 8 + 1) != 0x3C) ok = 0;

    if (ok) cx_print("TILETEXT OK");
    else    cx_print("TILETEXT FAIL");

    cx_exit();                             /* never returns */
    return 0;
}
