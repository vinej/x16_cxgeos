; ca65
; =====================================================================
; CXGEOS :: kernel/video/ovl.inc -- the graphics port contract
; =====================================================================
; The resident kernel contains no graphics engine. It contains a PORT:
; the OVL region (kernel.cfg), whose first bytes are a fixed ENTRY
; VECTOR -- one three-byte jmp per gfx ABI slot, in slot order. The gfx
; slots in the jump table target these constants forever; which engine
; sits behind them is whatever image was last copied into the region.
;
; An ENGINE IMAGE is an OV*CODE segment (run = OVL, load = a kernel
; bank): the 13-entry vector first, then the engine and any argument
; adapters. cx_ov_boot copies mode 0's image in before anything draws;
; cx_gfx_mode (stage C) swaps images the same way. An entry an engine
; cannot honour must set carry and rts.
;
; Adding a mode N+1 = one new image in a bank + a row in the mode
; table. Nothing here, in the jump table, or in any app changes.
;
; CX_NO_OVERLAY: the test runner links everything as one flat PRG with
; no overlay region; there the port names alias the 2bpp engine
; directly and the boot copy is a no-op.
; =====================================================================

.ifndef CX_OVL_INC
CX_OVL_INC = 1

.ifndef CX_NO_OVERLAY

CX_OVL      = $9600             ; MUST match OVL's start in kernel.cfg
CX_OVL_SIZE = $0900             ; ...and its size

cxov_init    = CX_OVL + 0*3     ; the vector, in gfx slot order
cxov_clear   = CX_OVL + 1*3
cxov_pset    = CX_OVL + 2*3
cxov_read    = CX_OVL + 3*3
cxov_hline   = CX_OVL + 4*3
cxov_vline   = CX_OVL + 5*3
cxov_rect    = CX_OVL + 6*3
cxov_frame   = CX_OVL + 7*3
cxov_line    = CX_OVL + 8*3
cxov_pattern = CX_OVL + 9*3
cxov_patrect = CX_OVL + 10*3
cxov_blit    = CX_OVL + 11*3
cxov_blitm   = CX_OVL + 12*3

.else                           ; the runner: no overlay, direct engine

cxov_init    = gfx2_init
cxov_clear   = gfx2_clear
cxov_pset    = gfx2_pset
cxov_read    = gfx2_read
cxov_hline   = gfx2_hline
cxov_vline   = gfx2_vline
cxov_rect    = gfx2_rect
cxov_frame   = gfx2_frame
cxov_line    = gfx2_line
cxov_pattern = gfx2_pattern_set
cxov_patrect = gfx2_pattern_rect
cxov_blit    = gfx2_blit
cxov_blitm   = gfx2_blitm

.endif

.endif
