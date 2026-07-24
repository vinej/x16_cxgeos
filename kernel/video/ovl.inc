; ca65
; =====================================================================
; CXRF :: kernel/video/ovl.inc -- the graphics port contract
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

; cx_ov_load image indices: 0-3 are the modes (their images), 4 is OV3T,
; the tile-text dialog port swapped in over mode 2 without a mode change.
CX_OV_TILE     = 2              ; mode 2's own image (the tile refuse-port)
CX_OV_TILETEXT = 4             ; OV3T, the tile-text dialog port

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
cxov_text    = CX_OVL + 13*3    ; the 14th entry: draw a string. mode 0
                                ; points it at the CXF font, text mode at
                                ; its cell writer, the rest refuse -- so
                                ; cx_say is mode-aware through the port
cxov_measure = CX_OVL + 14*3    ; the 15th: A/X = string -> P0/P1 = its
                                ; width in the mode's own units (CXF
                                ; pixels in mode 0, 8-pixel glyphs in
                                ; mode 1, cells in mode 3) -- what lets
                                ; the toolkit lay text out in any mode
cxov_rsave   = CX_OVL + 15*3    ; save full screen rows to banked RAM,
cxov_rrest   = CX_OVL + 16*3    ; and restore them: the toolkit's
                                ; save-under, one per mode. A = first RAM
                                ; bank, P0/P1 = first row, P2 = row count
                                ; -- the vrows contract, so mode 0 is
                                ; vrows itself; mode 3 saves text cells,
                                ; the bitmap modes refuse (carry). "Rows"
                                ; are the mode's own: pixel rows in 0/1,
                                ; cell rows in 3

; One byte of ENGINE-LOCAL state rides just past the vector: the text
; ink (cx_ink). It lives in the IMAGE, so every mode entry copies the
; mode's default back in -- an ink set in one mode cannot leak into the
; next, where the same number means a different colour space (a palette
; index in mode 1, a 16-colour attribute in mode 3; mode 0's text ink
; belongs to the theme and ignores this byte).
cxov_ink     = CX_OVL + 17*3

; The toolkit's per-mode geometry rides the image right after the ink
; byte -- nine constants, the whole difference between laying the menu
; (and later the widgets and dialogs) out in mode 0's pixels or mode 3's
; cells. The frame thicknesses it also uses are "one unit" in every mode
; and stay literal. Read straight from these fixed addresses, like the
; ink; no resident copy (the budget has no room, and only the current
; image is ever resident, so its metrics are always the live ones).
cxov_m_barh    = CX_OVL + 17*3 + 1   ; bar height / dropdown top
cxov_m_rowh    = CX_OVL + 17*3 + 2   ; dropdown item row height
cxov_m_barx    = CX_OVL + 17*3 + 3   ; bar title pen start
cxov_m_airx    = CX_OVL + 17*3 + 4   ; air between bar titles
cxov_m_barty   = CX_OVL + 17*3 + 5   ; title y within the bar
cxov_m_bandpad = CX_OVL + 17*3 + 6   ; open-title band padding, each side
cxov_m_boxwpad = CX_OVL + 17*3 + 7   ; dropdown box width extra
cxov_m_itemx   = CX_OVL + 17*3 + 8   ; item label x inset
cxov_m_itemdy  = CX_OVL + 17*3 + 9   ; item label y, below the band
; dialog metrics -- the box is centred, so its origin derives from
; cx_cur_w/h and these sizes. dgw is a WORD (mode 0's box is 400 wide).
cxov_m_dgw     = CX_OVL + 17*3 + 10  ; dialog box width (word)
cxov_m_dgh     = CX_OVL + 17*3 + 12  ; dialog box height
cxov_m_dgbw    = CX_OVL + 17*3 + 13  ; dialog button width
cxov_m_dgbh    = CX_OVL + 17*3 + 14  ; dialog button height
cxov_m_dgbsp   = CX_OVL + 17*3 + 15  ; dialog button spacing (pitch)
cxov_m_dgpad   = CX_OVL + 17*3 + 16  ; dialog edge / message pad
cxov_m_dgfldy  = CX_OVL + 17*3 + 17  ; prompt field y, below the box top

.else                           ; the runner: no overlay, direct engine

cxov_init    = gfx2h_init
cxov_clear   = gfx2h_clear
cxov_pset    = gfx2h_pset
cxov_read    = gfx2h_read
cxov_hline   = gfx2h_hline
cxov_vline   = gfx2h_vline
cxov_rect    = gfx2h_rect
cxov_frame   = gfx2h_frame
cxov_line    = gfx2h_line
cxov_pattern = gfx2h_pattern_set
cxov_patrect = gfx2h_pattern_rect
cxov_blit    = gfx2h_blit
cxov_blitm   = gfx2h_blitm
cxov_text    = font_draw        ; the runner is always mode 0: the font
cxov_measure = font_measure
cxov_rsave   = vrows_save       ; mode 0's rows save/restore IS vrows
cxov_rrest   = vrows_restore
; the toolkit metrics as a real block (engine0's flat branch emits it);
; the runner links the menu but never runs it, so these need only resolve
cxov_m_barh    = cx_flatmet + 0
cxov_m_rowh    = cx_flatmet + 1
cxov_m_barx    = cx_flatmet + 2
cxov_m_airx    = cx_flatmet + 3
cxov_m_barty   = cx_flatmet + 4
cxov_m_bandpad = cx_flatmet + 5
cxov_m_boxwpad = cx_flatmet + 6
cxov_m_itemx   = cx_flatmet + 7
cxov_m_itemdy  = cx_flatmet + 8
cxov_m_dgw     = cx_flatmet + 9
cxov_m_dgh     = cx_flatmet + 11
cxov_m_dgbw    = cx_flatmet + 12
cxov_m_dgbh    = cx_flatmet + 13
cxov_m_dgbsp   = cx_flatmet + 14
cxov_m_dgpad   = cx_flatmet + 15
cxov_m_dgfldy  = cx_flatmet + 16

.endif

.endif
