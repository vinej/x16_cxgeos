; ca65
; =====================================================================
; CXRF :: kernel/video/shapes.asm -- shapes on the graphics PORT
; =====================================================================
; x16lib's engine-agnostic shapes module, bound to the graphics PORT:
; SHP_PSET/READ/HLINE point at the overlay's entry vector, and the
; bounds at the port manager's current-canvas words -- so one copy of
; the code draws correct shapes in mode 0, mode 1, and any mode that
; ever joins the port. Its calls back into the port land in the
; resident overlay window, which is always mapped.
;
; The BASE shapes (circle / disc / ellipse / fellipse / flood) ride
; bank 17 behind their own far-call stubs, as they always have.
;
; The v0.8.0 EXTRA shapes (polygon / fpolygon / arc / pie, and the
; sin/cos table they need) ride bank 19 (CX_SHPX_BANK), reached through
; ONE dispatched slot: cx_gfx_shape -- X = kind, A = colour, geometry in
; the P block. shape_dispatch, a 65C02 `jmp (tbl,X)`, routes to the right
; routine, so the whole extra family costs just 6 resident bytes. The
; SKIP_BASE guard lets x16lib's shapes.asm be .included twice -- the base
; (bank 17) and the extras (bank 19) -- without a duplicate symbol.
; =====================================================================

; We place gfx/shapes.asm (banks 17 + 19) and util/math.asm (bank 19)
; ourselves, so x16_code.asm's own X16_USE_SHAPES/MATH includes -- now pulled
; in transitively by X16_USE_SHAPES_POLY (x16lib 0.9.0) -- must stay quiet, or
; every shape symbol lands twice. These opt out of that flat include.
X16_SKIP_SHAPES = 1
X16_SKIP_MATH   = 1

.ifndef CX_NO_OVERLAY

SHP_PSET  = cxov_pset
SHP_READ  = cxov_read
SHP_HLINE = cxov_hline
SHP_W     = cx_cur_w
SHP_H     = cx_cur_h

CX_SHP_BANK = CX_GFXX_BANK      ; bank 17 (banks.inc) -- the base shapes

cx_do_gfx_circle
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_circle
cx_do_gfx_disc
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_disc
cx_do_gfx_flood
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_flood
cx_do_gfx_ellipse
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_ellipse
cx_do_gfx_fellipse
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_fellipse

; the extra shapes ride bank 19 through ONE dispatched stub (6 bytes)
cx_do_gfx_shape
    jsr cxb_call
    .byte CX_SHPX_BANK
    .addr shape_dispatch

; --- base shapes: bank 17 (SKIP_BASE off, no extras) ---
.segment "B17CODE"
.include "gfx/shapes.asm"
.segment "CODE"

; --- extra shapes + the sin/cos table + the dispatcher: bank 19 ---
.segment "B19CODE"
SKIP_BASE           = 1         ; the base shapes already live in bank 17
X16_USE_SHP_LINE    = 1         ; arc/pie join their samples with shp_line
X16_USE_SHAPES_POLY = 1
X16_USE_SHAPES_ARC  = 1
X16_USE_SHAPES_PIE  = 1
; the sin/cos table rides this bank with its callers. We include it
; ourselves (not via X16_USE_MATH) so x16_code.asm's own gated include --
; reached later, in the kernel's fine-gated build -- does not also emit it.
.include "util/math.asm"

; shape_dispatch -- X = kind (0..3), A = colour, P block = geometry.
;   0 polygon   1 fpolygon   2 arc   3 pie
shape_dispatch
    cpx #4
    bcs @done                   ; out of range: draw nothing
    pha                         ; colour survives the index math
    txa
    asl a                       ; kind*2 -> the vector table
    tax
    pla                         ; colour back in A for the shape
    jmp (shp_vec,x)             ; 65C02 jmp (abs,X)
@done
    rts
shp_vec
    .addr shape_polygon, shape_fpolygon, shape_arc, shape_pie

.include "gfx/shapes.asm"
.include "kernel/video/shphit.asm"   ; the WG_HIT polygon/pie point tests
.segment "CODE"

.else
; the runner links flat: the port names alias the 2bpp engine (ovl.inc),
; so the same binds hold and every stub IS the routine.
SHP_PSET  = cxov_pset
SHP_READ  = cxov_read
SHP_HLINE = cxov_hline
SHP_W     = cx_cur_w
SHP_H     = cx_cur_h

X16_USE_SHP_LINE    = 1
X16_USE_SHAPES_POLY = 1
X16_USE_SHAPES_ARC  = 1
X16_USE_SHAPES_PIE  = 1

cx_do_gfx_circle   = shape_circle
cx_do_gfx_disc     = shape_disc
cx_do_gfx_flood    = shape_flood
cx_do_gfx_ellipse  = shape_ellipse
cx_do_gfx_fellipse = shape_fellipse
cx_do_gfx_shape    = shape_dispatch

; the sin/cos table, ourselves (not via X16_USE_MATH, so x16_code.asm's
; own gated include stays quiet and we don't emit it twice).
.include "util/math.asm"
shape_dispatch
    cpx #4
    bcs @rdone
    pha
    txa
    asl a
    tax
    pla
    jmp (shp_vec,x)
@rdone
    rts
shp_vec
    .addr shape_polygon, shape_fpolygon, shape_arc, shape_pie

.include "gfx/shapes.asm"
.include "kernel/video/shphit.asm"   ; the WG_HIT polygon/pie point tests

.endif
