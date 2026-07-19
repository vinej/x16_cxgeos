;ACME
; =====================================================================
; x16lib :: x16_code.asm -- the library routines
; =====================================================================
; Source this EXACTLY ONCE, at the point in your program where you want
; the library's machine code to sit (normally after your own code).
;
; ACME has no linker, so unused routines cannot be stripped for you.
; Instead, pick the modules you need by defining X16_USE_* before
; sourcing this file -- or define X16_USE_ALL to pull in everything.
;
;       X16_USE_VERA = 1
;       .include "x16_code.asm"
;
; or from the build script:  acme -DX16_USE_ALL=1 ...
;
; These gates must be resolvable on the FIRST pass, so always define
; them ahead of this !source, never after it.
; ---------------------------------------------------------------------
; Module            Provides
;   X16_USE_VERA      vera_set_addr0/1, vera_fill, vera_copy, vera_has_fx
;   X16_USE_SCREEN    screen_set_mode/get_mode/reset/cls/chrout/color/
;                     border, screen_locate, screen_get_cursor,
;                     screen_charset, screen_puts
;   X16_USE_PALETTE   pal_set, pal_load
;   X16_USE_TILE      layer_on/off, layer_set_config/mapbase/tilebase,
;                     layer_scroll_x/y, tile_setptr, tile_put, tile_get
;   X16_USE_SPRITE    sprites_on/off, sprite_pos, sprite_get_pos,
;                     sprite_image, sprite_flags, sprite_z, sprite_size,
;                     sprite_init_all
;   X16_USE_BITMAP    gfx_init, gfx_clear, gfx_read, gfx_pset,
;                     gfx_pattern_set, gfx_pattern_rect, gfx_blit,
;                     gfx_blitm (colour-key), gfx_hline,
;                     gfx_vline, gfx_rect, gfx_frame, gfx_line,
;                     gfx_char, gfx_text (circle/disc/flood are in
;                     X16_USE_SHAPES now, shared with gfx2)
;   X16_USE_BITMAP2   gfx2_init, gfx2_clear, gfx2_setptr, gfx2_pset,
;                     gfx2_read, gfx2_hline, gfx2_vline, gfx2_rect,
;                     gfx2_frame, gfx2_line, gfx2_pattern_set,
;                     gfx2_pattern_rect, gfx2_blit, gfx2_blitm
;                     (640x480@2bpp; pulls in VERA and VERAFX)
;   X16_USE_SHAPES    shape_circle, shape_disc, shape_ellipse,
;                     shape_fellipse, shape_flood -- engine-
;                     agnostic: they draw through SHP_PSET/SHP_READ/
;                     SHP_HLINE (+ SHP_W/SHP_H bounds), which default to
;                     the 2bpp module; predefine them to bind any engine
;   X16_USE_VERAFX    all of the below, as it always has been
;     _MULT           fx_mult
;     _FILL           fx_fill, fx_clear
;     _COPY           fx_copy
;     _TRANSP         fx_transp_on/off
;     _AFFINE         fx_affine_on/ray/span (rotozoom sampling)
;     _LINE           fx_line
;     _TRI            fx_triangle
;                     fx_off comes with any of them. The parts exist
;                     because the whole is 2.5 KB and a program that
;                     wants one fast fill should not carry a rotozoom
;                     sampler to get it: BITMAP2 asks for _FILL alone
;                     and is 2,162 bytes lighter for it.
;   X16_USE_IRQ       irq_install, irq_remove, irq_frames, vsync_wait,
;                     irq_line_install/remove, irq_sprcol_install/
;                     remove, sprite_collisions
;   X16_USE_PSG       psg_init, psg_set_freq/vol/wave, psg_note_off,
;                     psg_env_start/release/stop/tick (ASR envelopes)
;   X16_USE_YM        ym_write, ym_busy, ym_init, ym_poke, ym_patch,
;                     ym_note, ym_note_bas, ym_release_note, ym_vol,
;                     ym_pan, ym_drum, ym_get_pan, ym_get_vol
;   X16_USE_PCM       pcm_ctrl, pcm_rate, pcm_reset, pcm_full/empty,
;                     pcm_put, pcm_write
;   X16_USE_PCM_STREAM  pcm_stream_start/stop/active (AFLOW-driven;
;                     pulls in PCM and IRQ)
;   X16_USE_INPUT     joy_scan, joy_get, mouse_show/hide/get,
;                     key_get, key_wait, key_peek
;   X16_USE_BANK      bank_set/get, bank_peek/poke, mem_to_bank,
;                     bank_to_mem, bank_copy_far
;   X16_USE_BANKALLOC bank_alloc_init, bank_alloc, bank_free,
;                     bank_reserve
;   X16_USE_MEM       mem_fill, mem_copy, mem_crc, mem_decompress
;                     (KERNAL block ops; they stream to/from VERA too)
;   X16_USE_LOAD      fs_setname, fs_load, fs_save, fs_vload
;   X16_USE_DOS       dos_cmd, dos_status, dos_delete, dos_rename,
;                     dos_mkdir, dos_rmdir, dos_chdir
;   X16_USE_BMX       bmx_load, bmx_save (the X16's native bitmap
;                     format: header + palette + pixels)
;   X16_USE_MATH      rnd_seed/rnd8/rnd16, sin8/cos8 (+u), atan2, lerp8
;   X16_USE_CLIP      clip_set, clip_line (Cohen-Sutherland, feeds
;                     gfx_line/fx_line's parameter block)
;   X16_USE_BUFFERS   rb_init/put/get/count, stk_init/push/pop/depth
;   X16_USE_ADPCM     adpcm_init, adpcm_nibble, adpcm_block (IMA 4:1)
;   X16_USE_ZX0       zx0_decompress (tighter than the ROM's LZSA2)
;   X16_USE_TSC       tsc_decompress (TSCrunch: faster unpack)
;   X16_USE_FIXED     umul16, mul88
;   X16_USE_COLLIDE   collide8, collide16
;   X16_USE_BITS      catnib, hinib, lonib, bit_set/clr/put/test
;   X16_USE_NUMBER    u16_to_dec, u16_to_hex, dec_to_u16
;   X16_USE_INT16     i16_add/sub/neg/abs/mul/divmod/divmod_s,
;                     i16_cmps/cmpu, i16_shl/shr/asr, i16_sqrt,
;                     i16_to_dec/dec_s, +i16_const   (needs NUMBER)
;   X16_USE_INT32     i32_add/sub/neg/abs/mul/divmod, i32_cmps/cmpu,
;                     i32_shl/shr/asr, i32_from_u16/s16, i32_to_s16,
;                     i32_to_dec, +i32_const
;   X16_USE_FLOAT     f_load/store, f_add/sub/mul/div, f_rsub/rdiv,
;                     f_pow, f_cmp, f_sqrt, f_ln, f_exp, f_sin, f_cos,
;                     f_tan, f_atan, f_from_s16/u8/str, f_to_s16/str
; =====================================================================

; Gates are set with !ifndef so that asking for a module twice -- say via
; X16_USE_ALL and again through a dependency -- is not a redefinition
; error, and so an explicit X16_USE_* in your program still works.
.ifdef X16_USE_ALL
    .ifndef X16_USE_VERA
    X16_USE_VERA    = 1
.endif
    .ifndef X16_USE_SCREEN
    X16_USE_SCREEN  = 1
.endif
    .ifndef X16_USE_PALETTE
    X16_USE_PALETTE = 1
.endif
    .ifndef X16_USE_TILE
    X16_USE_TILE    = 1
.endif
    .ifndef X16_USE_SPRITE
    X16_USE_SPRITE  = 1
.endif
    .ifndef X16_USE_BITMAP
    X16_USE_BITMAP  = 1
.endif
    .ifndef X16_USE_BITMAP2
    X16_USE_BITMAP2 = 1
.endif
    .ifndef X16_USE_VERAFX
    X16_USE_VERAFX  = 1
.endif
    .ifndef X16_USE_IRQ
    X16_USE_IRQ     = 1
.endif
    .ifndef X16_USE_PSG
    X16_USE_PSG     = 1
.endif
    .ifndef X16_USE_YM
    X16_USE_YM      = 1
.endif
    .ifndef X16_USE_PCM
    X16_USE_PCM     = 1
.endif
    .ifndef X16_USE_PCM_STREAM
    X16_USE_PCM_STREAM = 1
.endif
    .ifndef X16_USE_INPUT
    X16_USE_INPUT   = 1
.endif
    .ifndef X16_USE_BANK
    X16_USE_BANK    = 1
.endif
    .ifndef X16_USE_BANKALLOC
    X16_USE_BANKALLOC = 1
.endif
    .ifndef X16_USE_MEM
    X16_USE_MEM     = 1
.endif
    .ifndef X16_USE_LOAD
    X16_USE_LOAD    = 1
.endif
    .ifndef X16_USE_DOS
    X16_USE_DOS     = 1
.endif
    .ifndef X16_USE_BMX
    X16_USE_BMX     = 1
.endif
    .ifndef X16_USE_MATH
    X16_USE_MATH    = 1
.endif
    .ifndef X16_USE_CLIP
    X16_USE_CLIP    = 1
.endif
    .ifndef X16_USE_BUFFERS
    X16_USE_BUFFERS = 1
.endif
    .ifndef X16_USE_ADPCM
    X16_USE_ADPCM   = 1
.endif
    .ifndef X16_USE_ZX0
    X16_USE_ZX0     = 1
.endif
    .ifndef X16_USE_TSC
    X16_USE_TSC     = 1
.endif
    .ifndef X16_USE_FIXED
    X16_USE_FIXED   = 1
.endif
    .ifndef X16_USE_COLLIDE
    X16_USE_COLLIDE = 1
.endif
    .ifndef X16_USE_BITS
    X16_USE_BITS    = 1
.endif
    .ifndef X16_USE_NUMBER
    X16_USE_NUMBER  = 1
.endif
    .ifndef X16_USE_INT16
    X16_USE_INT16   = 1
.endif
    .ifndef X16_USE_INT32
    X16_USE_INT32   = 1
.endif
    .ifndef X16_USE_FLOAT
    X16_USE_FLOAT   = 1
.endif
.endif

; --- dependencies ----------------------------------------------------
; sprite_init_all, psg_init, gfx_clear and gfx_hline all call vera_fill.
; gfx_init calls screen_set_mode. The PCM streamer's AFLOW service runs
; inside irq_handler, so it needs the IRQ module (and PCM itself).
.ifdef X16_USE_SPRITE
.ifndef X16_USE_VERA
X16_USE_VERA = 1
.endif
.endif
.ifdef X16_USE_PSG
.ifndef X16_USE_VERA
X16_USE_VERA = 1
.endif
.endif
.ifdef X16_USE_INT16
.ifndef X16_USE_NUMBER
X16_USE_NUMBER = 1
.endif
.endif
.ifdef X16_USE_BITMAP
    .ifndef X16_USE_VERA
    X16_USE_VERA   = 1
.endif
    .ifndef X16_USE_SCREEN
    X16_USE_SCREEN = 1
.endif
.endif
.ifdef X16_USE_SHAPES
    .ifndef SHP_PSET
        .ifndef X16_USE_BITMAP2
        X16_USE_BITMAP2 = 1
.endif
.endif
.endif
.ifdef X16_USE_BITMAP2
    .ifndef X16_USE_VERA
    X16_USE_VERA        = 1
.endif
    .ifndef X16_USE_VERAFX_FILL
    X16_USE_VERAFX_FILL = 1
.endif
.endif

; --- VERAFX's parts --------------------------------------------------
; X16_USE_VERAFX still means all of it, so nothing that exists breaks.
; The sub-gates are for programs that want one part and not 2.5 KB of
; the others: gfx2 asks for FILL alone and saves 2,162 bytes by it.
; Every part leaves FX through fx_off, so _ANY carries it.
.ifdef X16_USE_VERAFX
    .ifndef X16_USE_VERAFX_MULT
    X16_USE_VERAFX_MULT   = 1
.endif
    .ifndef X16_USE_VERAFX_FILL
    X16_USE_VERAFX_FILL   = 1
.endif
    .ifndef X16_USE_VERAFX_COPY
    X16_USE_VERAFX_COPY   = 1
.endif
    .ifndef X16_USE_VERAFX_TRANSP
    X16_USE_VERAFX_TRANSP = 1
.endif
    .ifndef X16_USE_VERAFX_AFFINE
    X16_USE_VERAFX_AFFINE = 1
.endif
    .ifndef X16_USE_VERAFX_LINE
    X16_USE_VERAFX_LINE   = 1
.endif
    .ifndef X16_USE_VERAFX_TRI
    X16_USE_VERAFX_TRI    = 1
.endif
.endif
.ifdef X16_USE_VERAFX_MULT
.ifndef X16_USE_VERAFX_ANY
X16_USE_VERAFX_ANY = 1
.endif
.endif
.ifdef X16_USE_VERAFX_FILL
.ifndef X16_USE_VERAFX_ANY
X16_USE_VERAFX_ANY = 1
.endif
.endif
.ifdef X16_USE_VERAFX_COPY
.ifndef X16_USE_VERAFX_ANY
X16_USE_VERAFX_ANY = 1
.endif
.endif
.ifdef X16_USE_VERAFX_TRANSP
.ifndef X16_USE_VERAFX_ANY
X16_USE_VERAFX_ANY = 1
.endif
.endif
.ifdef X16_USE_VERAFX_AFFINE
.ifndef X16_USE_VERAFX_ANY
X16_USE_VERAFX_ANY = 1
.endif
.endif
.ifdef X16_USE_VERAFX_LINE
.ifndef X16_USE_VERAFX_ANY
X16_USE_VERAFX_ANY = 1
.endif
.endif
.ifdef X16_USE_VERAFX_TRI
.ifndef X16_USE_VERAFX_ANY
X16_USE_VERAFX_ANY = 1
.endif
.endif
.ifdef X16_USE_PCM_STREAM
    .ifndef X16_USE_PCM
    X16_USE_PCM = 1
.endif
    .ifndef X16_USE_IRQ
    X16_USE_IRQ = 1
.endif
.endif

; --- split modules ---------------------------------------------------
; Same shape as VERAFX above: the umbrella gate still means the whole
; module, so nothing that exists breaks; a program that wants the core
; and not a rarely-used extra sets the _CORE gate and leaves the extra
; out. _ANY sources the file.
;   VERA   core = set_addr/fill/has_fx;   _COPY   = vera_copy
;   IRQ    core = install/line/frames/handler; _VSYNC = vsync_wait;
;          _SPRCOL = collision capture (handler accumulate + mask);
;          _SPRCOL_API = install/remove/sprite_collisions/callback
;   INPUT  core = mouse/joy/key_get;      _KEYWAIT = key_wait/key_peek
;   SCREEN core = set_mode/reset/cls/chrout/color/locate;
;          _EXTRA = get_mode/border/get_cursor/charset/puts
.ifdef X16_USE_VERA
    .ifndef X16_USE_VERA_CORE
    X16_USE_VERA_CORE = 1
.endif
    .ifndef X16_USE_VERA_COPY
    X16_USE_VERA_COPY = 1
.endif
.endif
.ifdef X16_USE_VERA_CORE
.ifndef X16_USE_VERA_ANY
X16_USE_VERA_ANY = 1
.endif
.endif
.ifdef X16_USE_VERA_COPY
.ifndef X16_USE_VERA_ANY
X16_USE_VERA_ANY = 1
.endif
.endif
.ifdef X16_USE_IRQ
    .ifndef X16_USE_IRQ_CORE
    X16_USE_IRQ_CORE       = 1
.endif
    .ifndef X16_USE_IRQ_VSYNC
    X16_USE_IRQ_VSYNC      = 1
.endif
    .ifndef X16_USE_IRQ_SPRCOL
    X16_USE_IRQ_SPRCOL     = 1
.endif
    .ifndef X16_USE_IRQ_SPRCOL_API
    X16_USE_IRQ_SPRCOL_API = 1
.endif
.endif
.ifdef X16_USE_IRQ_SPRCOL_API
.ifndef X16_USE_IRQ_SPRCOL
X16_USE_IRQ_SPRCOL = 1
.endif
.endif
.ifdef X16_USE_IRQ_CORE
.ifndef X16_USE_IRQ_ANY
X16_USE_IRQ_ANY = 1
.endif
.endif
.ifdef X16_USE_IRQ_VSYNC
.ifndef X16_USE_IRQ_ANY
X16_USE_IRQ_ANY = 1
.endif
.endif
.ifdef X16_USE_IRQ_SPRCOL
.ifndef X16_USE_IRQ_ANY
X16_USE_IRQ_ANY = 1
.endif
.endif
.ifdef X16_USE_INPUT
    .ifndef X16_USE_INPUT_CORE
    X16_USE_INPUT_CORE    = 1
.endif
    .ifndef X16_USE_INPUT_KEYWAIT
    X16_USE_INPUT_KEYWAIT = 1
.endif
.endif
.ifdef X16_USE_INPUT_CORE
.ifndef X16_USE_INPUT_ANY
X16_USE_INPUT_ANY = 1
.endif
.endif
.ifdef X16_USE_INPUT_KEYWAIT
.ifndef X16_USE_INPUT_ANY
X16_USE_INPUT_ANY = 1
.endif
.endif
.ifdef X16_USE_SCREEN
    .ifndef X16_USE_SCREEN_CORE
    X16_USE_SCREEN_CORE  = 1
.endif
    .ifndef X16_USE_SCREEN_EXTRA
    X16_USE_SCREEN_EXTRA = 1
.endif
.endif
.ifdef X16_USE_SCREEN_CORE
.ifndef X16_USE_SCREEN_ANY
X16_USE_SCREEN_ANY = 1
.endif
.endif
.ifdef X16_USE_SCREEN_EXTRA
.ifndef X16_USE_SCREEN_ANY
X16_USE_SCREEN_ANY = 1
.endif
.endif

; --- modules ---------------------------------------------------------
.ifdef X16_USE_VERA_ANY
.include "video/vera.asm"
.endif
.ifdef X16_USE_SCREEN_ANY
.include "video/screen.asm"
.endif
.ifdef X16_USE_PALETTE
.include "video/palette.asm"
.endif
.ifdef X16_USE_TILE
.include "video/tile.asm"
.endif
.ifdef X16_USE_SPRITE
.include "sprite/sprite.asm"
.endif
.ifdef X16_USE_BITMAP
.include "gfx/bitmap.asm"
.endif
.ifdef X16_USE_BITMAP2
.include "gfx/bitmap2.asm"
.endif
.ifdef X16_USE_SHAPES
.include "gfx/shapes.asm"
.endif
.ifdef X16_USE_VERAFX_ANY
.include "gfx/verafx.asm"
.endif
.ifdef X16_USE_IRQ_ANY
.include "system/irq.asm"
.endif
.ifdef X16_USE_PSG
.include "audio/psg.asm"
.endif
.ifdef X16_USE_YM
.include "audio/ym.asm"
.endif
.ifdef X16_USE_PCM
.include "audio/pcm.asm"
.endif
.ifdef X16_USE_INPUT_ANY
.include "input/input.asm"
.endif
.ifdef X16_USE_BANK
.include "storage/bank.asm"
.endif
.ifdef X16_USE_BANKALLOC
.include "storage/bankalloc.asm"
.endif
.ifdef X16_USE_MEM
.include "storage/mem.asm"
.endif
.ifdef X16_USE_LOAD
.include "storage/load.asm"
.endif
.ifdef X16_USE_DOS
.include "storage/dos.asm"
.endif
.ifdef X16_USE_BMX
.include "storage/bmx.asm"
.endif
.ifdef X16_USE_MATH
.include "util/math.asm"
.endif
.ifdef X16_USE_CLIP
.include "util/clip.asm"
.endif
.ifdef X16_USE_BUFFERS
.include "util/buffers.asm"
.endif
.ifdef X16_USE_ADPCM
.include "audio/adpcm.asm"
.endif
.ifdef X16_USE_ZX0
.include "util/zx0.asm"
.endif
.ifdef X16_USE_TSC
.include "util/tscrunch.asm"
.endif
.ifdef X16_USE_FIXED
.include "util/fixed.asm"
.endif
.ifdef X16_USE_COLLIDE
.include "util/collide.asm"
.endif
.ifdef X16_USE_BITS
.include "util/bits.asm"
.endif
.ifdef X16_USE_NUMBER
.include "util/number.asm"
.endif
.ifdef X16_USE_INT16
.include "util/int16.asm"
.endif
.ifdef X16_USE_INT32
.include "util/int32.asm"
.endif
.ifdef X16_USE_FLOAT
.include "util/float.asm"
.endif
