/* =====================================================================
 * CXGEOS csdk -- friendly C wrappers over the generated ABI header
 * =====================================================================
 * The generated header (sdk/include_<compiler>/cxgeos.h) is deliberately
 * low-level: you set the parameter block by hand and call a slot number.
 * This header turns that into named cx_* functions, a typed event
 * record, the shared constants, and packed structs/macros for building
 * menus, widgets, dialogs and themes -- so C apps read clearly and no
 * one re-derives rect()/say()/marker() ever again.
 *
 * Include it AFTER the generated header:
 *
 *     #include <cbm.h>
 *     #include "sdk/include_llvm/cxgeos.h"
 *     #include "csdk/cxsdk.h"
 *
 * Header-only: every wrapper is `static`, so -Os drops the ones you do
 * not call. Targets llvm-mos (the fully-supported C toolchain); it uses
 * only the shared macro surface (cx_p, cx_call_a, cx_call_p, cx_ret,
 * cx_a/cx_x/cx_c), so it extends to the other C compilers once their
 * generated bindings can pass A.
 * ===================================================================== */

#ifndef CXSDK_H
#define CXSDK_H

#include <cbm.h>          /* cbm_k_chrout, for cx_print */

/* --- constants: event types (the record's `type`) ------------------ */
/* CX_ET_*, not CX_EV_*, so they never clash with the CX_EV_* slot names
 * the generated header defines (CX_EV_TIMER, CX_EV_GET, ...) */
#define CX_ET_NULL    0
#define CX_ET_MOVE    1
#define CX_ET_DOWN    2
#define CX_ET_UP      3
#define CX_ET_DBL     4
#define CX_ET_KEY     5
#define CX_ET_TIMER   6
#define CX_ET_MENU    7
#define CX_ET_WIDGET  8
#define CX_ET_JOY     9          /* detail = pad, x = buttons, y = changed */
#define CX_ET_TYPES   10         /* how many, for a handler table */

/* --- widget types (a record's `type`) ------------------------------- */
#define CX_WG_BUTTON  0
#define CX_WG_CHECK   1
#define CX_WG_RADIO   2
#define CX_WG_SCROLL  3
#define CX_WG_FIELD   4
#define CX_WG_LIST    5

/* --- font style flags ----------------------------------------------- */
#define CX_BOLD       1
#define CX_UNDER      2

/* --- theme role colours (palette indices, not RGB) ------------------ */
/* The live theme maps these three roles to palette entries; a cx_theme()
 * swap changes the RGB behind an index, never the index, so drawing with
 * these recolours automatically -- exactly as the kernel toolkit does. */
#define CX_PAPER      0          /* the background     (theme "paper") */
#define CX_HI         1          /* the highlight fill (theme "hi")    */
#define CX_FRAME      3          /* borders            (theme "frame") */

/* --- keys (PETSCII), as EV_KEY delivers them ------------------------ */
#define CX_K_ENTER    0x0D
#define CX_K_ESC      0x1B
#define CX_K_TAB      0x09
#define CX_K_BTAB     0x18      /* shift-TAB */
#define CX_K_DEL      0x14
#define CX_K_UP       0x91
#define CX_K_DOWN     0x11
#define CX_K_LEFT     0x9D
#define CX_K_RIGHT    0x1D
#define CX_K_SPACE    0x20

/* --- audio: PSG waveforms and panning ------------------------------- */
#define CX_WAVE_PULSE 0x00
#define CX_WAVE_SAW   0x40
#define CX_WAVE_TRI   0x80
#define CX_WAVE_NOISE 0xC0
#define CX_PAN_LEFT   0x40
#define CX_PAN_RIGHT  0x80
#define CX_PAN_BOTH   0xC0
/* pack an octave (0-7) and a note (1-12) into a cx_ym_note code */
#define CX_YM(octave, note)  (((octave) << 4) | (note))

/* --- PCM format bits (cx_pcm_ctrl); low nibble is volume 0-15 -------- */
#define CX_PCM_16BIT  0x20
#define CX_PCM_STEREO 0x10

/* --- joystick buttons (ACTIVE HIGH: pressed = 1), as cx_joy returns
 * them and as an EV_JOY's x/y words carry them. Pad 0 is the keyboard
 * joystick; 1-4 are SNES pads. ------------------------------------- */
#define CX_J_RIGHT    0x0001
#define CX_J_LEFT     0x0002
#define CX_J_DOWN     0x0004
#define CX_J_UP       0x0008
#define CX_J_START    0x0010
#define CX_J_SELECT   0x0020
#define CX_J_Y        0x0040
#define CX_J_B        0x0080
#define CX_J_R        0x1000
#define CX_J_L        0x2000
#define CX_J_X        0x4000
#define CX_J_A        0x8000

/* --- sprites -------------------------------------------------------- */
#define CX_SPR_4BPP   0x00       /* image colour depth (cx_sprite_image) */
#define CX_SPR_8BPP   0x80
#define CX_SPR_8      0          /* size codes (cx_sprite_size)          */
#define CX_SPR_16     1
#define CX_SPR_32     2
#define CX_SPR_64     3
#define CX_SPR_HIDE   0x00       /* Z-depths (cx_sprite_z / _flags)      */
#define CX_SPR_BEHIND 0x04
#define CX_SPR_MIDDLE 0x08
#define CX_SPR_FRONT  0x0C
#define CX_SPR_HFLIP  0x01
#define CX_SPR_VFLIP  0x02
/* the VRAM region the desktop reserves for app sprite images (4 KB).
 * Sprite 0 is the KERNAL mouse; apps drive sprites 1-127. */
#define CX_SPR_VRAM   0x1E000UL

/* small helpers that pack a 16-bit value into two mirror bytes */
#define CX__W(i, v)   (cx_p[i] = (unsigned char)(v), \
                       cx_p[(i) + 1] = (unsigned char)((unsigned)(v) >> 8))
#define CX__R(i)      ((unsigned)cx_p[i] | ((unsigned)cx_p[(i) + 1] << 8))

/* The wrappers are `static` in a header, so an app that calls only some
 * would draw -Wunused-function for the rest under -Wall. They are all
 * meant to be optional; -Os drops the unused ones. Silence the noise. */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"

/* =====================================================================
 * system
 * ===================================================================== */
static void     cx_exit(void)          { cx_call(CX_EXIT); }
static unsigned cx_version(void)       { return cx_ret16(CX_VERSION); }

/* =====================================================================
 * screen / graphics
 * =====================================================================
 * The same 13 drawing calls work in EVERY graphics mode -- the kernel's
 * port routes them to the current engine. What changes per mode is the
 * canvas (cx_screen_info) and the colour range. The toolkit, fonts and
 * dialogs are CX_MODE_GUI-only; cx_exit always restores the desktop. */
#define CX_MODE_GUI   0          /* 640x480, 4 colours -- the desktop  */
#define CX_MODE_BMP8  1          /* 320x240, 256 colours               */
#define CX_MODE_TILE  2          /* two tile layers + sprites (games)  */
#define CX_MODE_TEXT  3          /* 80x60 text cells, 16 colours       */

static void cx_gfx_init(void) { cx_call(CX_GFX_INIT); }  /* = mode GUI */
static void cx_clear(unsigned char color) { cx_call_a(CX_GFX_CLEAR, color); }

/* switch the graphics mode: 0 ok, nonzero unknown. VERA is reprogrammed
 * and the screen shows the new mode's canvas -- draw everything fresh.
 * In CX_MODE_BMP8, pattern/blit calls refuse (carry) and colours are
 * 0-255 (set the palette with cx_vram_write at 0x1FA00, 2 bytes/entry).
 * In CX_MODE_TEXT coordinates are cells (0-79 x 0-59): clear/rect fill
 * cells (and set the paper), frame draws a PETSCII box, hline/vline are
 * ruled lines, cx_line rules horizontally or vertically (diagonals
 * refuse), and cx_say prints mixed-case ASCII at (col, row). */
static char cx_mode(unsigned char m) { cx_call_a(CX_GFX_MODE, m); return cx_c; }

typedef struct {
    unsigned char mode;
    unsigned      w, h;          /* the canvas, in pixels  */
    unsigned char bpp;
    unsigned      stride;        /* framebuffer bytes/row  */
} cx_screen;

/* what canvas is this? (mode, size, depth, stride) */
static void cx_screen_info(cx_screen *s) {
    cx_call(CX_GFX_INFO);
    s->mode   = cx_a;
    s->w      = CX__R(0);
    s->h      = CX__R(2);
    s->bpp    = cx_p[4];
    s->stride = CX__R(5);
}

static void cx_pset(unsigned x, unsigned y, unsigned char color) {
    CX__W(0, x); CX__W(2, y);
    cx_call_a(CX_GFX_PSET, color);
}
static unsigned char cx_pget(unsigned x, unsigned y) {
    CX__W(0, x); CX__W(2, y);
    return cx_ret(CX_GFX_READ);
}
static void cx_hline(unsigned x, unsigned y, unsigned len, unsigned char color) {
    CX__W(0, x); CX__W(2, y); CX__W(4, len);
    cx_call_a(CX_GFX_HLINE, color);
}
static void cx_vline(unsigned x, unsigned y, unsigned len, unsigned char color) {
    CX__W(0, x); CX__W(2, y); CX__W(4, len);
    cx_call_a(CX_GFX_VLINE, color);
}
static void cx_rect(unsigned x, unsigned y, unsigned w, unsigned h, unsigned char color) {
    CX__W(0, x); CX__W(2, y); CX__W(4, w); CX__W(6, h);
    cx_call_a(CX_GFX_RECT, color);
}
static void cx_frame(unsigned x, unsigned y, unsigned w, unsigned h, unsigned char color) {
    CX__W(0, x); CX__W(2, y); CX__W(4, w); CX__W(6, h);
    cx_call_a(CX_GFX_FRAME, color);
}
static void cx_line(unsigned x0, unsigned y0, unsigned x1, unsigned y1, unsigned char color) {
    CX__W(0, x0); CX__W(2, y0); CX__W(4, x1); CX__W(6, y1);
    cx_call_a(CX_GFX_LINE, color);
}
/* a circle outline at (cx, cy), radius r -- drawn through the port, so
 * it works in every mode and clips where pset clips */
static void cx_circle(unsigned cxx, unsigned cy, unsigned char r, unsigned char color) {
    CX__W(0, cxx); CX__W(2, cy); cx_p[4] = r;
    cx_call_a(CX_GFX_CIRCLE, color);
}
/* a filled circle; no clipping -- keep it on screen */
static void cx_disc(unsigned cxx, unsigned cy, unsigned char r, unsigned char color) {
    CX__W(0, cxx); CX__W(2, cy); cx_p[4] = r;
    cx_call_a(CX_GFX_DISC, color);
}
/* an axis-aligned ellipse outline (rx, ry each 0-255); clips wherever
 * the mode's pset clips */
static void cx_ellipse(unsigned cxx, unsigned cy, unsigned char rx,
                       unsigned char ry, unsigned char color) {
    CX__W(0, cxx); CX__W(2, cy); cx_p[4] = rx; cx_p[5] = ry;
    cx_call_a(CX_GFX_ELLIPSE, color);
}
/* the same, filled; no clipping -- keep it on screen */
static void cx_fellipse(unsigned cxx, unsigned cy, unsigned char rx,
                        unsigned char ry, unsigned char color) {
    CX__W(0, cxx); CX__W(2, cy); cx_p[4] = rx; cx_p[5] = ry;
    cx_call_a(CX_GFX_FELLIPSE, color);
}
/* the text ink for the CURRENT mode (0.4.0): a palette index in
 * CX_MODE_BMP8, an attribute 0-15 in CX_MODE_TEXT; the GUI's text ink
 * belongs to the theme and ignores it. Mode-local state: every mode
 * switch resets it to white. */
static void cx_ink(unsigned char color) { cx_call_a(CX_INK, color); }
/* flood-fill the region containing (x, y); returns 0 done, 1 if the
 * seed stack overflowed on a very tortured region */
static char cx_flood(unsigned x, unsigned y, unsigned char color) {
    CX__W(0, x); CX__W(2, y);
    cx_call_a(CX_GFX_FLOOD, color);
    return cx_c;
}

/* =====================================================================
 * tiles (CX_MODE_TILE only) -- two 64x32 maps of 8x8 4bpp tiles
 * =====================================================================
 * Upload tile images with cx_vram_write to CX_TILE_IMG (32 bytes per
 * tile); the maps hold 2-byte cells. Everything refuses (carry) outside
 * mode 2. */
#define CX_TILE_IMG   0x00000UL  /* tile pixel data (up to 1024 tiles) */
#define CX_CELL_HF    0x0400     /* cell attribute bits                */
#define CX_CELL_VF    0x0800
#define CX_CELL(idx, pal)  (((unsigned)(idx) & 0x3FF) | ((unsigned)(pal) << 12))

/* configure a layer (0/1) for the mode's ledger and switch it on */
static char cx_tile_setup(unsigned char layer) {
    cx_call_a(CX_TILE_SETUP, layer);
    return cx_c;
}
/* hardware-scroll a layer (0-4095 each axis) */
static void cx_tile_scroll(unsigned char layer, unsigned h, unsigned v) {
    CX__W(0, h); CX__W(2, v);
    cx_call_a(CX_TILE_SCROLL, layer);
}
/* write one map cell */
static void cx_tile_cell(unsigned char layer, unsigned char col,
                         unsigned char row, unsigned cell) {
    CX__W(0, cell); cx_x = col; cx_y = row;
    cx_call_a(CX_TILE_CELL, layer);
}
/* write every cell of a layer's map */
static void cx_tile_fill(unsigned char layer, unsigned cell) {
    CX__W(0, cell);
    cx_call_a(CX_TILE_FILL, layer);
}
/* set the fill pattern. One wrapper serves every mode: Y carries the
 * packed 2-bit pair mode 0 reads, and P4/P5 carry the full bytes mode 1
 * reads -- each engine takes the one it understands. */
static void cx_pattern(const void *pat8, unsigned char bg, unsigned char fg) {
    cx_y = (unsigned char)(((bg & 3) << 2) | (fg & 3));
    cx_p[4] = bg; cx_p[5] = fg;
    cx_call_p(CX_GFX_PATTERN, pat8);
}
static void cx_patrect(unsigned x, unsigned y, unsigned w, unsigned h) {
    CX__W(0, x); CX__W(2, y); CX__W(4, w); CX__W(6, h);
    cx_call(CX_GFX_PATRECT);
}
static void cx_blit(unsigned x, unsigned y, unsigned char wbytes, unsigned char h,
                    const void *src, unsigned char op) {
    CX__W(0, x); CX__W(2, y);
    cx_p[4] = wbytes; cx_p[5] = h;
    CX__W(6, (unsigned)src);
    cx_call_a(CX_GFX_BLIT, op);
}
static void cx_blitm(unsigned x, unsigned y, unsigned char h, unsigned char cols,
                     const void *src) {
    CX__W(0, x); CX__W(2, y);
    cx_p[4] = h; cx_p[5] = cols;
    CX__W(6, (unsigned)src);
    cx_call(CX_GFX_BLITM);
}

/* =====================================================================
 * text
 * ===================================================================== */
static char cx_font(const void *cxf) {          /* 0 ok, 1 bad */
    cx_call_p(CX_FONT_SET, cxf);
    return cx_c;
}
static void cx_style(unsigned char flags) { cx_call_a(CX_FONT_STYLE, flags); }

static unsigned cx_measure(const char *s) {
    cx_call_p(CX_FONT_MEASURE, s);
    return CX__R(0);
}
/* draw s at (x, y); returns the pen x just past the text */
static unsigned cx_say(const char *s, unsigned x, unsigned y) {
    CX__W(0, x); CX__W(2, y);
    cx_call_p(CX_FONT_DRAW, s);
    return CX__R(0);
}

/* =====================================================================
 * immediate-mode widget painters
 * =====================================================================
 * These DRAW a widget by name -- a button, a checkbox, a slider, an edit
 * box -- so custom-layout code (the calculator's keypad, a status bar)
 * reads by intent instead of composing an anonymous cx_frame()+cx_say().
 * They paint only: the app hit-tests the coordinates itself (see calc).
 * They match the kernel toolkit's look pixel for pixel and use the same
 * theme role colours, so a hand-painted button sits beside a real one.
 *
 * For INTERACTIVE, kernel-managed widgets -- clicks and keyboard focus
 * dispatched as EV_WIDGET -- declare a CX_WIDGETS list and cx_wg_set it
 * instead. These painters are the draw-it-yourself alternative.
 * ===================================================================== */
#define CX_FONT_H     8          /* the system font's glyph height */
#define CX_BOX        12         /* the checkbox marker square (= WG_BOX) */
#define CX_THUMB      16         /* the slider thumb width (= WG_THUMB) */
#define CX_SLIDER_H   16         /* the slider's height */

/* a push button: a framed box with its label centred both ways */
static void cx_button(unsigned x, unsigned y, unsigned w, unsigned h,
                      const char *label) {
    unsigned tw = cx_measure(label);
    cx_rect(x, y, w, h, CX_PAPER);
    cx_frame(x, y, w, h, CX_FRAME);
    cx_say(label, x + (w - tw) / 2, y + (h - CX_FONT_H) / 2);
}

/* a checkbox: a marker box (filled when checked) and a label to its right.
 * Radio buttons share this look in the toolkit -- use it for a radio too,
 * managing the group's exclusivity yourself. */
static void cx_checkbox(unsigned x, unsigned y, const char *label,
                        unsigned char checked) {
    cx_rect(x, y, CX_BOX, CX_BOX, CX_PAPER);
    cx_frame(x, y, CX_BOX, CX_BOX, CX_FRAME);
    if (checked)
        cx_rect(x + 3, y + 3, CX_BOX - 6, CX_BOX - 6, CX_FRAME);
    cx_say(label, x + CX_BOX + 6, y + 2);
}

/* a horizontal slider: a framed trough with a thumb at value/max (0..max
 * inclusive, so a 1..10 slider passes value 0..9, max 9) */
static void cx_slider(unsigned x, unsigned y, unsigned w,
                      unsigned char value, unsigned char max) {
    unsigned travel = (w - 4) - CX_THUMB;   /* inner width less the thumb */
    unsigned tx = x + 2;
    cx_rect(x, y, w, CX_SLIDER_H, CX_PAPER);
    cx_frame(x, y, w, CX_SLIDER_H, CX_FRAME);
    if (max)
        tx += (unsigned)((unsigned long)value * travel / max);
    cx_rect(tx, y + 2, CX_THUMB, CX_SLIDER_H - 4, CX_HI);
}

/* an edit box: a framed field with its text, left-aligned and vertically
 * centred. No caret -- the app owns the text; repaint to update it. */
static void cx_edit(unsigned x, unsigned y, unsigned w, unsigned h,
                    const char *text) {
    cx_rect(x, y, w, h, CX_PAPER);
    cx_frame(x, y, w, h, CX_FRAME);
    cx_say(text, x + 4, y + (h - CX_FONT_H) / 2);
}

/* =====================================================================
 * events -- a typed record and a one-call poll
 * ===================================================================== */
typedef struct {
    unsigned char type;      /* CX_EV_*                                */
    unsigned char detail;    /* key code / widget index / menu item    */
    unsigned int  x, y;      /* mouse x/y; a widget's x = its value;   */
                             /* a menu's x = the menu index            */
    unsigned char frame;     /* the frame stamp                        */
} cx_event;

static void cx_ev_init(void) { cx_call(CX_EV_INIT); }

/* fill *ev from a raw record; carry from the ABI is what cx_ret16 hides */
static char cx__fill(cx_event *ev) {
    if (cx_c)                    /* the ABI set carry: the queue was empty */
        return 0;
    ev->type   = cx_p[0];
    ev->detail = cx_p[1];
    ev->x      = CX__R(2);
    ev->y      = CX__R(4);
    ev->frame  = cx_p[6];
    return 1;
}

/* RAW poll: fill *ev with the next event, 1 if one was waiting, 0 if not.
 * Mouse events arrive as EV_DOWN/EV_MOVE/EV_UP with ev->x/ev->y, for an
 * app that hit-tests its own pixels (the calculator). A toolkit app --
 * one that called cx_wg_set / cx_menu_set -- wants cx_next instead, which
 * routes the mouse for it; cx_poll never reaches the widget engine. */
static char cx_poll(cx_event *ev) {
    if (!cx_ret(CX_EV_COUNT))
        return 0;
    cx_call(CX_EV_GET);
    return cx__fill(ev);
}

/* TOOLKIT poll: like cx_poll, but every pending mouse event is first
 * routed through the widget/menu regions, so a click on a widget or a
 * menu surfaces as the EV_WIDGET / EV_MENU the toolkit posts. Returns 1
 * with a non-mouse event in *ev, or 0 when the queue is drained. This is
 * the loop primitive for a C app built on cx_wg_set / cx_menu_set. */
static char cx_next(cx_event *ev) {
    cx_call(CX_EV_NEXT);
    return cx__fill(ev);
}
static void cx_post(const cx_event *ev) {
    cx_p[0] = ev->type; cx_p[1] = ev->detail;
    CX__W(2, ev->x); CX__W(4, ev->y);
    cx_p[6] = ev->frame; cx_p[7] = 0;
    cx_call(CX_EV_POST);
}
static void          cx_timer(unsigned char frames) { cx_call_a(CX_EV_TIMER, frames); }
static unsigned char cx_frames(void) { return cx_ret(CX_EV_FRAMES); }
static void          cx_mainloop(void) { cx_call(CX_EV_MAINLOOP); }
static void          cx_handlers(const void *table) { cx_call_p(CX_EV_HANDLERS, table); }

/* which sources the frame tick samples (0.3.2). The mouse's SMC
 * round-trip and the keyboard's GETIN drain are KERNAL calls paid every
 * frame; mask off the ones you do not use and that time comes back.
 * cx_ev_init resets to mouse+keys; the timer (cx_timer), the pads
 * (cx_joy_enable) and PCM keep their own switches. */
#define CX_EVS_MOUSE 1
#define CX_EVS_KEYS  2
static void cx_ev_mask(unsigned char sources) { cx_call_a(CX_EV_MASK, sources); }

/* =====================================================================
 * pointer, menus, widgets
 * ===================================================================== */
static void cx_mouse_show(unsigned char sprite) { cx_call_a(CX_MOUSE_SHOW, sprite); }
static void cx_mouse_hide(void) { cx_call(CX_MOUSE_HIDE); }

static char cx_menu_set(const void *bar) {      /* 0 ok, 1 region stack full */
    cx_call_p(CX_MENU_SET, bar);
    return cx_c;
}
static void cx_menu_off(void) { cx_call(CX_MENU_OFF); }
static char cx_menu_key(unsigned char key) {    /* 1 if it was a menu key */
    cx_call_a(CX_MENU_KEY, key);
    return cx_c;
}
static void cx_wg_set(const void *list) { cx_call_p(CX_WG_SET, list); }
static void cx_wg_draw(void) { cx_call(CX_WG_DRAW); }
static char cx_wg_key(unsigned char key) {      /* 1 if it was a widget key */
    cx_call_a(CX_WG_KEY, key);
    return cx_c;
}

/* =====================================================================
 * themes and dialogs
 * ===================================================================== */
static void          cx_theme(const void *rec12) { cx_call_p(CX_THEME_SET, rec12); }
static unsigned char cx_alert(const void *desc) { /* modal; returns the button */
    cx_call_p(CX_DLG_ALERT, desc);
    return cx_a;
}
/* modal line editor; returns the length, or -1 if cancelled */
static int cx_prompt(const char *msg, char *buf, unsigned char cap) {
    CX__W(0, (unsigned)buf);
    cx_p[2] = cap;
    cx_call_p(CX_DLG_PROMPT, msg);
    return cx_c ? -1 : (int)(unsigned char)cx_a;
}

/* =====================================================================
 * audio -- the VERA PSG (16 voices) and the YM2151 FM chip
 * ===================================================================== */
/* PSG: silence every voice */
static void cx_psg_init(void) { cx_call(CX_PSG_INIT); }
/* set a voice's pitch. freq = Hz * 2.68435 (A4 = 440 Hz is 1181) */
static void cx_psg_freq(unsigned char voice, unsigned freq) {
    cx_x = voice; CX__W(0, freq);
    cx_call(CX_PSG_FREQ);
}
/* set a voice's volume (0-63) and pan (CX_PAN_LEFT/RIGHT/BOTH) */
static void cx_psg_vol(unsigned char voice, unsigned char vol, unsigned char pan) {
    cx_y = pan;
    cx_call_ax(CX_PSG_VOL, vol, voice);
}
/* set a voice's waveform (CX_WAVE_*) and pulse width / XOR (0-63) */
static void cx_psg_wave(unsigned char voice, unsigned char wave, unsigned char pw) {
    cx_y = pw;
    cx_call_ax(CX_PSG_WAVE, wave, voice);
}
/* silence a voice (keeps its panning) */
static void cx_psg_off(unsigned char voice) {
    cx_x = voice;
    cx_call(CX_PSG_OFF);
}
/* a one-call tone: a pulse wave at freq/vol on a voice, both channels.
 * The app decides how long to hold it before cx_psg_off. */
static void cx_tone(unsigned char voice, unsigned freq, unsigned char vol) {
    cx_psg_wave(voice, CX_WAVE_PULSE, 32);
    cx_psg_freq(voice, freq);
    cx_psg_vol(voice, vol, CX_PAN_BOTH);
}

/* YM2151 (FM): reset the chip and load the default patches. Call once. */
static void cx_ym_init(void) { cx_call(CX_YM_INIT); }
/* play a note on a channel (0-7); code is CX_YM(octave, note), 0 releases */
static void cx_ym_note(unsigned char chan, unsigned char code) {
    cx_call_ax(CX_YM_NOTE, chan, code);
}
/* release the note on a channel */
static void cx_ym_off(unsigned char chan) { cx_call_a(CX_YM_OFF, chan); }
/* set a channel's attenuation (0 = the patch's volume, larger = quieter) */
static void cx_ym_vol(unsigned char chan, unsigned char atten) {
    cx_call_ax(CX_YM_VOL, chan, atten);
}
/* load a ROM instrument patch (0-162) on a channel */
static void cx_ym_patch(unsigned char chan, unsigned char idx) {
    cx_call_ax(CX_YM_PATCH, chan, idx);
}

/* PCM (the 4KB FIFO, topped up each frame off the event IRQ). Needs
 * cx_ev_init running; the sample is signed bytes in low RAM. Set the
 * format/volume once with cx_pcm_ctrl (e.g. 0x0F = 8-bit mono, full
 * volume) before cx_pcm_play. */
static void cx_pcm_ctrl(unsigned char ctrl) { cx_call_a(CX_PCM_CTRL, ctrl); }
/* play `len` sample bytes from `src` at `rate` (1-128; 128 = 48 kHz) */
static void cx_pcm_play(const void *src, unsigned len, unsigned char rate) {
    CX__W(0, (unsigned)src); CX__W(2, len);
    cx_call_a(CX_PCM_PLAY, rate);
}
static void          cx_pcm_stop(void) { cx_call(CX_PCM_STOP); }
static unsigned char cx_pcm_active(void) { return cx_ret(CX_PCM_ACTIVE); }

/* =====================================================================
 * joysticks (pad 0 = the keyboard joystick, 1-4 = SNES pads)
 * ===================================================================== */
/* the pad's buttons as an active-high CX_J_* word; 0 = none (or absent).
 * After the call cx_c is 1 if the pad is not plugged in. */
static unsigned cx_joy(unsigned char pad) {
    cx_call_a(CX_JOY_GET, pad);
    return (unsigned)cx_a | ((unsigned)cx_x << 8);
}
/* scan the pads in `mask` (bit n = pad n, 0-3) every frame and post a
 * CX_ET_JOY event whenever one's state changes; 0 turns it off */
static void cx_joy_enable(unsigned char mask) { cx_call_a(CX_JOY_ENABLE, mask); }

/* =====================================================================
 * sprites (VERA hardware sprites)
 * =====================================================================
 * Sprite 0 is the mouse; drive sprites 1-127. Put image data in VRAM at
 * CX_SPR_VRAM (32-byte aligned) with cx_vram_write, point the sprite at
 * it, give it a size and position, then a Z-depth to show it. Set the
 * flags once (cx_sprite_flags) before using cx_sprite_z. */

/* point sprite s at its image (VRAM addr, 32-byte aligned; CX_SPR_4BPP/8BPP) */
static void cx_sprite_image(unsigned char s, unsigned long addr,
                            unsigned char mode) {
    cx_x = s;
    cx_p[0] = (unsigned char)addr;
    cx_p[1] = (unsigned char)(addr >> 8);
    cx_p[2] = (unsigned char)(addr >> 16);
    cx_call_a(CX_SPRITE_IMAGE, mode);
}
/* move sprite s to (x, y) */
static void cx_sprite_pos(unsigned char s, unsigned x, unsigned y) {
    cx_x = s; CX__W(0, x); CX__W(2, y);
    cx_call(CX_SPRITE_POS);
}
/* set sprite s's size (CX_SPR_8/16/32/64 each axis) and palette offset */
static void cx_sprite_size(unsigned char s, unsigned char w, unsigned char h,
                           unsigned char pal) {
    cx_x = s; cx_y = h; cx_p[0] = pal;
    cx_call_a(CX_SPRITE_SIZE, w);
}
/* set sprite s's flags: collision<<4 | Z | CX_SPR_VFLIP | CX_SPR_HFLIP.
 * A full write -- do this once before cx_sprite_z. */
static void cx_sprite_flags(unsigned char s, unsigned char flags) {
    cx_x = s; cx_call_a(CX_SPRITE_FLAGS, flags);
}
/* change only sprite s's Z-depth: CX_SPR_HIDE/BEHIND/MIDDLE/FRONT */
static void cx_sprite_z(unsigned char s, unsigned char z) {
    cx_x = s; cx_call_a(CX_SPRITE_Z, z);
}

/* =====================================================================
 * loader and desk accessories
 * ===================================================================== */
static unsigned char cx__strlen(const char *s) {
    unsigned char n = 0;
    while (s[n]) n++;
    return n;
}
/* load and run a .CXA; returns only on failure (1 not an app, 2 old) */
static unsigned char cx_launch(const char *name) {
    cx_y = cx__strlen(name);
    cx_call_p(CX_APP_LOAD, name);
    return cx_a;
}
static char cx_da_open(const char *name) {      /* 0 ok, 1 fail */
    cx_y = cx__strlen(name);
    cx_call_p(CX_DA_OPEN, name);
    return cx_c;
}
static void cx_da_close(void) { cx_call(CX_DA_CLOSE); }

/* load any file into a buffer, at most `cap` bytes (0.4.0) -- how fonts
 * and charsets come off the disk: cx_file_load a .CXF then cx_font it;
 * cx_file_load a 2KB charset then cx_vram_write it to 0x1F000. Returns
 * the byte count, or -1 with the reason in cx_a (1 not there, 2 read
 * error, 3 bigger than cap -- the first cap bytes are in). */
static int cx_file_load(const char *name, void *dst, unsigned cap) {
    cx_y = cx__strlen(name);
    CX__W(0, (unsigned)dst); CX__W(2, cap);
    cx_call_p(CX_FILE_LOAD, name);
    if (cx_c) return -1;
    return (int)CX__R(4);
}

/* =====================================================================
 * directory and DOS
 * ===================================================================== */
static char cx_dir_open(const char *pattern) {  /* 0 ok, 1 DOS error */
    cx_y = cx__strlen(pattern);
    cx_call_p(CX_DIR_OPEN, pattern);
    return cx_c;
}
static signed char cx_dir_next(char *buf17) {   /* 0 file, 1 dir, -1 end */
    CX__W(0, (unsigned)buf17);
    cx_call(CX_DIR_NEXT);
    return cx_c ? -1 : (signed char)cx_a;
}
static void          cx_dir_close(void) { cx_call(CX_DIR_CLOSE); }
static unsigned char cx_dos(const char *cmd) {  /* the status code (>=20 = error) */
    cx_y = cx__strlen(cmd);
    cx_call_p(CX_DOS_CMD, cmd);
    return cx_a;
}
static unsigned char cx_dos_msg(char *buf64) {  /* copies the last reply, returns length */
    CX__W(0, (unsigned)buf64);
    return cx_ret(CX_DOS_MSG);
}

/* =====================================================================
 * clipboard
 * ===================================================================== */
static char cx_clip_put(unsigned char type, const void *src, unsigned len) {
    CX__W(0, (unsigned)src); CX__W(2, len);
    cx_call_a(CX_CLIP_PUT, type);
    return cx_c;                 /* 0 ok, 1 too big */
}
static unsigned cx_clip_get(void *dst, unsigned cap, unsigned char *type_out) {
    CX__W(0, (unsigned)dst); CX__W(2, cap);
    cx_call(CX_CLIP_GET);
    if (type_out) *type_out = cx_a;
    return CX__R(2);             /* the length actually copied */
}
static unsigned char cx_clip_type(unsigned *len_out) {
    cx_call(CX_CLIP_TYPE);
    if (len_out) *len_out = CX__R(2);
    return cx_a;                 /* the waiting type, 0 = empty */
}

/* =====================================================================
 * dirty rectangles (advanced)
 * ===================================================================== */
static void          cx_dirty_reset(void) { cx_call(CX_DIRTY_RESET); }
static void          cx_dirty_add(unsigned x, unsigned y, unsigned w, unsigned h) {
    CX__W(0, x); CX__W(2, y); CX__W(4, w); CX__W(6, h);
    cx_call(CX_DIRTY_ADD);
}
static unsigned char cx_dirty_count(void) { return cx_ret(CX_DIRTY_COUNT); }
static void          cx_dirty_get(unsigned char i, unsigned *x0, unsigned *y0,
                                  unsigned *x1, unsigned *y1) {
    cx_call_a(CX_DIRTY_GET, i);
    if (x0) *x0 = CX__R(0);
    if (y0) *y0 = CX__R(2);
    if (x1) *x1 = CX__R(4);
    if (y1) *y1 = CX__R(6);
}

/* =====================================================================
 * utility -- not an ABI slot, but every app wants it
 * ===================================================================== */
/* CHROUT a NUL-terminated string plus a return, through the KERNAL --
 * the boot/debug marker line every app prints */
static void cx_print(const char *s) {
    while (*s)
        cbm_k_chrout((unsigned char)*s++);
    cbm_k_chrout('\r');
}

/* =====================================================================
 * picture files -- a framebuffer rectangle to/from a SEQ file
 * =====================================================================
 * cx_pic_save / cx_pic_load stream a w x h rectangle of the screen at
 * (x, y) as native framebuffer bytes (four 2-bit pixels a byte) straight
 * through VERA's auto-incrementing data port, a row at a time. This is
 * far faster than a cx_pget/cx_pset per pixel -- each of those is a full
 * ABI crossing -- so the file I/O becomes the only cost. x and w are in
 * pixels and MUST be multiples of 4; a row is at most 640 px (160 bytes).
 *
 * Interrupts are masked around the stream: the event IRQ's GETIN reads
 * the current channel (the file, once CHKIN'd) and its mouse-sprite
 * update writes VERA -- either would corrupt the transfer. A whole row is
 * read before any is written, and each row re-seeks VERA, so the file and
 * VRAM accesses never interleave. Device 8 (the SD); the framebuffer is
 * 160 bytes/row at VRAM $00000 (docs/memory-map). */
#define CX__V_ADDR_L (*(volatile unsigned char *)0x9F20)
#define CX__V_ADDR_M (*(volatile unsigned char *)0x9F21)
#define CX__V_ADDR_H (*(volatile unsigned char *)0x9F22)
#define CX__V_DATA0  (*(volatile unsigned char *)0x9F23)
#define CX__V_CTRL   (*(volatile unsigned char *)0x9F25)

static unsigned char cx__row[160];       /* one framebuffer row segment */
static char          cx__fn[28];         /* the built "name,S,x" filename */

/* the current mode's row stride and pixels-per-byte shift, cached by
 * cx_pic_save/load at entry so the picture calls work in ANY mode */
static unsigned      cx__vstride = 160;
static unsigned char cx__vshift  = 2;    /* 2bpp: 4 px/byte; 8bpp: 1 */

static void cx__vgeom(void) {
    cx_screen s;
    cx_screen_info(&s);
    cx__vstride = s.stride;
    cx__vshift  = (s.bpp == 2) ? 2 : (s.bpp == 4) ? 1 : 0;
}

/* point DATA0 at pixel (x, y) in the framebuffer, +1 auto-increment */
static void cx__vseek(unsigned x, unsigned y) {
    unsigned long off = (unsigned long)y * cx__vstride + (x >> cx__vshift);
    CX__V_CTRL   = 0;                                  /* ADDRSEL 0 -> DATA0 */
    CX__V_ADDR_L = (unsigned char)off;
    CX__V_ADDR_M = (unsigned char)(off >> 8);
    CX__V_ADDR_H = ((unsigned char)(off >> 16) & 0x0F) | 0x10;
}

/* build pre + name + suf into cx__fn (a DOS name like "S:PICT" or
 * "PICT,S,W"); names are short, the buffer holds 27 chars */
static void cx__mkname(const char *pre, const char *name, const char *suf) {
    unsigned char i = 0, j;
    for (j = 0; pre[j];  j++) cx__fn[i++] = pre[j];
    for (j = 0; name[j]; j++) cx__fn[i++] = name[j];
    for (j = 0; suf[j];  j++) cx__fn[i++] = suf[j];
    cx__fn[i] = 0;
}

/* save the w x h framebuffer rectangle at (x, y) to SEQ file `name` */
static void cx_pic_save(const char *name, unsigned x, unsigned y,
                        unsigned w, unsigned h) {
    unsigned row, bx, wb;
    cx__vgeom();
    wb = w >> cx__vshift;
    cx__mkname("S:", name, "");           /* drop any old file first */
    cx_dos(cx__fn);
    cx__mkname("", name, ",S,W");
    cbm_k_setnam(cx__fn);
    cbm_k_setlfs(3, 8, 3);
    cbm_k_open();
    __asm__ volatile ("sei" ::: "memory");
    cbm_k_chkout(3);
    for (row = 0; row < h; row++) {
        cx__vseek(x, y + row);
        for (bx = 0; bx < wb; bx++) cx__row[bx] = CX__V_DATA0;
        for (bx = 0; bx < wb; bx++) cbm_k_chrout(cx__row[bx]);
    }
    cbm_k_clrch();
    cbm_k_close(3);
    __asm__ volatile ("cli" ::: "memory");
}

/* load SEQ file `name` into the w x h rectangle at (x, y); returns the
 * number of rows restored (0 = no file / empty) */
static unsigned cx_pic_load(const char *name, unsigned x, unsigned y,
                            unsigned w, unsigned h) {
    unsigned row, bx, wb, rows = 0;
    unsigned char st = 0;
    char done = 0;
    cx__vgeom();
    wb = w >> cx__vshift;
    cx__mkname("", name, ",S,R");
    cbm_k_setnam(cx__fn);
    cbm_k_setlfs(2, 8, 2);
    cbm_k_open();
    __asm__ volatile ("sei" ::: "memory");
    cbm_k_chkin(2);
    for (row = 0; row < h && !done; row++) {
        char full;
        for (bx = 0; bx < wb; bx++) {
            cx__row[bx] = cbm_k_chrin();
            st = cbm_k_readst();
            if (st) { done = 1; break; }         /* EOF ($40) or an error */
        }
        full = (bx == wb) || (st == 0x40 && bx == wb - 1);
        if (full) {
            cx__vseek(x, y + row);
            for (bx = 0; bx < wb; bx++) CX__V_DATA0 = cx__row[bx];
            rows++;
        }
    }
    cbm_k_clrch();
    cbm_k_close(2);
    __asm__ volatile ("cli" ::: "memory");
    return rows;
}

/* copy `len` bytes from RAM `src` into VRAM at `addr`, through VERA's
 * auto-incrementing data port -- for uploading sprite images (to
 * CX_SPR_VRAM), tiles, or any raw VRAM. */
static void cx_vram_write(unsigned long addr, const void *src, unsigned len) {
    const unsigned char *p = (const unsigned char *)src;
    unsigned i;
    CX__V_CTRL   = 0;
    CX__V_ADDR_L = (unsigned char)addr;
    CX__V_ADDR_M = (unsigned char)(addr >> 8);
    CX__V_ADDR_H = ((unsigned char)(addr >> 16) & 0x0F) | 0x10;
    for (i = 0; i < len; i++)
        CX__V_DATA0 = p[i];
}

#pragma GCC diagnostic pop

/* =====================================================================
 * descriptor builders -- structs packed to the kernel's byte layouts
 * (docs/formats.md), with macros for the count-prefixed lists.
 *
 * A widget list is written back in place by the toolkit, so declare it
 * with CX_WIDGETS (mutable). Menus, dialogs and themes are read-only.
 * ===================================================================== */

/* one 16-byte widget record */
typedef struct __attribute__((packed)) {
    unsigned char type, flags;
    unsigned int  x, y, w;
    unsigned char h, val, grp;
    const void   *label;         /* string / field buffer / list-of-pointers */
    unsigned char pad[3];        /* pad[0] = WG_TOP for a list */
} cx_widget;

/* per-type widget constructors (compound literals) */
#define CX_BUTTON(x, y, w, h, lbl) \
    (cx_widget){ CX_WG_BUTTON, 0, (x), (y), (w), (h), 0, 0, (lbl), {0,0,0} }
#define CX_CHECK(x, y, w, on, lbl) \
    (cx_widget){ CX_WG_CHECK, 0, (x), (y), (w), 14, (on), 0, (lbl), {0,0,0} }
#define CX_RADIO(x, y, w, on, group, lbl) \
    (cx_widget){ CX_WG_RADIO, 0, (x), (y), (w), 14, (on), (group), (lbl), {0,0,0} }
#define CX_SCROLL(x, y, w, val, max) \
    (cx_widget){ CX_WG_SCROLL, 0, (x), (y), (w), 16, (val), (max), 0, {0,0,0} }
#define CX_FIELD(x, y, w, cap, buf) \
    (cx_widget){ CX_WG_FIELD, 0, (x), (y), (w), 16, 0, (cap), (buf), {0,0,0} }
#define CX_LIST(x, y, w, h, count, ptrs) \
    (cx_widget){ CX_WG_LIST, 0, (x), (y), (w), (h), 0, (count), (ptrs), {0,0,0} }

/* a widget list: a count byte, then the records, one packed block */
#define CX_WIDGETS(name, ...) \
    static struct __attribute__((packed)) { \
        unsigned char n; \
        cx_widget w[sizeof((cx_widget[]){ __VA_ARGS__ }) / sizeof(cx_widget)]; \
    } name = { \
        (unsigned char)(sizeof((cx_widget[]){ __VA_ARGS__ }) / sizeof(cx_widget)), \
        { __VA_ARGS__ } \
    }

/* a menu bar: a count, then (title, items) per menu */
typedef struct __attribute__((packed)) { const void *title, *items; } cx_menu_entry;
#define CX_MENU(title, items)  (cx_menu_entry){ (title), (items) }
#define CX_MENU_BAR(name, ...) \
    static const struct __attribute__((packed)) { \
        unsigned char n; \
        cx_menu_entry m[sizeof((cx_menu_entry[]){ __VA_ARGS__ }) / sizeof(cx_menu_entry)]; \
    } name = { \
        (unsigned char)(sizeof((cx_menu_entry[]){ __VA_ARGS__ }) / sizeof(cx_menu_entry)), \
        { __VA_ARGS__ } \
    }

/* one menu's drop-down: a count, then a label pointer per item */
#define CX_MENU_ITEMS(name, ...) \
    static const struct __attribute__((packed)) { \
        unsigned char n; \
        const void *label[sizeof((const void *[]){ __VA_ARGS__ }) / sizeof(const void *)]; \
    } name = { \
        (unsigned char)(sizeof((const void *[]){ __VA_ARGS__ }) / sizeof(const void *)), \
        { __VA_ARGS__ } \
    }

/* an alert/prompt descriptor: a count, the message, then button labels */
#define CX_DIALOG(name, message, ...) \
    static const struct __attribute__((packed)) { \
        unsigned char n; \
        const void *msg; \
        const void *button[sizeof((const void *[]){ __VA_ARGS__ }) / sizeof(const void *)]; \
    } name = { \
        (unsigned char)(sizeof((const void *[]){ __VA_ARGS__ }) / sizeof(const void *)), \
        (message), { __VA_ARGS__ } \
    }

/* a 12-byte theme record: four palette colours (2 bytes each), then the
 * paper / highlight / frame role indices and one reserved byte */
typedef struct __attribute__((packed)) {
    unsigned char pal[8];
    unsigned char paper, hi, frame, reserved;
} cx_theme_rec;

#endif /* CXSDK_H */
