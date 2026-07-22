/* =====================================================================
 * CXRF :: apps/tiles8/tiles8.c -- the 8bpp tile + streaming + flip demo
 * =====================================================================
 * The payoff of the mode-2 remap: a tile game at 8bpp (256 colours a
 * tile), its tileset STREAMED from banked RAM, drawn tear-free with the
 * double buffer. It shows the whole warehouse -> stage -> screen flow:
 *
 *   build a 4-tile 8bpp set in bank 20        (the warehouse)
 *   cx_tile_load(0x00000, 20, 4, 8)           (bank -> VRAM tileset)
 *   cx_tile_setup(0, 8)                        (the layer at 8bpp)
 *   cx_tile_dbuf(0, 1); ... cx_tile_flip(0)    (tear-free double buffer)
 *
 * cx_tile_flip waits for vblank, so the event system must be running
 * (cx_ev_init) first. The animation fills the hidden map with a new tile
 * each frame and flips -- the screen cycles colour, tear-free.
 *
 * It self-drives (no input) so it runs headless in the boot smoke and can
 * be captured to a gif. After the animation it reads VERA + VRAM back and
 * prints TILES8 OK / TILES8 FAIL, then exits to the shell.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

/* VERA layer-0 registers, to read back the 8bpp config and the flip */
#define L0_CONFIG   (*(volatile unsigned char *)0x9F2D)
#define L0_MAPBASE  (*(volatile unsigned char *)0x9F2E)

/* the banked-RAM window and its bank register -- the "warehouse" */
#define RAM_BANK    (*(volatile unsigned char *)0x00)
static volatile unsigned char *const BANKWIN =
    (volatile unsigned char *)0xA000;

/* read one byte from VRAM (17-bit address) through data port 0 */
static unsigned char vread(unsigned long a) {
    CX__V_CTRL   = 0;
    CX__V_ADDR_L = (unsigned char)a;
    CX__V_ADDR_M = (unsigned char)(a >> 8);
    CX__V_ADDR_H = ((unsigned char)(a >> 16) & 0x0F) | 0x10;
    return CX__V_DATA0;
}

static void hold(unsigned char f) {
    unsigned char t = cx_frames();
    while ((unsigned char)(cx_frames() - t) < f)
        ;
}

/* pixel value of tile `t`, pixel `p` (row = p>>3, col = p&7) -- an 8bpp
 * index into VERA's default palette (1 white, 2 red, 5 green, 6 blue,
 * 7 yellow, 14 light blue). Tile 0's pixel 0 is 1, which the self-test
 * reads back out of VRAM to prove the stream landed. */
static unsigned char tilepix(unsigned char t, unsigned char p) {
    unsigned char row = p >> 3, col = p & 7;
    switch (t) {
    case 0:  return ((row ^ col) & 1) ? 6 : 1;   /* blue/white checker */
    case 1:  return 2;                           /* solid red          */
    case 2:  return (row & 1) ? 5 : 7;           /* green/yellow bars   */
    default: return 14;                          /* solid light blue    */
    }
}

int main(void) {
    unsigned char i, f, ok = 1, mb0;
    unsigned p;

    cx_print("TILES8 UP");
    cx_mode(CX_MODE_TILE);

    /* the event system runs the frame counter cx_frames()/hold() read and
     * cx_tile_flip waits on -- start it before either is used. */
    cx_ev_init();
    cx_ev_mask(CX_EVS_KEYS);

    /* --- the warehouse: build a 4-tile 8bpp set (256 B) in bank 20 --- */
    RAM_BANK = 20;
    for (i = 0; i < 4; i++)
        for (p = 0; p < 64; p++)
            BANKWIN[i * 64 + p] = tilepix(i, (unsigned char)p);

    /* --- stage it: bank 20 -> VRAM tileset $00000 (4 tiles, 8bpp) --- */
    cx_tile_load(0x00000UL, 20, 4, 8);

    /* --- the 8bpp layer, carpeted with tile 0 --- */
    cx_tile_setup(0, 8);
    cx_tile_fill(0, CX_CELL(0, 0));
    hold(30);                              /* [gif] the static 8bpp world */

    /* --- double-buffered animation: a new solid tile each frame --- */
    cx_tile_dbuf(0, 1);                     /* draw to the hidden map */
    for (f = 0; f < 48; f++) {
        cx_tile_fill(0, CX_CELL(f & 3, 0));/* the whole hidden map = tile f&3 */
        cx_tile_flip(0);                   /* present it, tear-free, at vblank */
    }

    /* --- self-test --- */
    if (L0_CONFIG != 0x13) ok = 0;         /* 64x32, 8x8, 8bpp */
    if (vread(0x00000UL) != tilepix(0, 0)) ok = 0;  /* the stream landed */
    mb0 = L0_MAPBASE;                      /* a flip must swap the shown map */
    cx_tile_flip(0);
    if (L0_MAPBASE == mb0) ok = 0;

    cx_tile_dbuf(0, 0);                     /* back to single-buffered */
    cx_print(ok ? "TILES8 OK" : "TILES8 FAIL");
    hold(20);
    cx_exit();
    return 0;
}
