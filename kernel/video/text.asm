; ca65
; =====================================================================
; CXGEOS :: kernel/video/text.asm -- mode 3: 80x60 text (like BASIC)
; =====================================================================
; The fourth personality behind the graphics port, and the cheapest:
; the KERNAL's own 80x60 text screen. It is a CHARACTER GRID, not a
; framebuffer, so the port's pixel calls are reinterpreted as CELL
; operations (coordinates 0-79 x 0-59, "colour" = a 16-colour text
; attribute):
;
;   cx_clear   fill the screen with a colour       (background)
;   cx_rect    fill a cell region with a colour
;   cx_frame   a one-cell colour border
;   cx_hline   a row of coloured cells
;   cx_vline   a column of coloured cells
;   cx_say     print a string at (col, row) -- routed here through the
;              port's 14th "text" entry (cxov_text); white on the
;              current background
;
; pset/read/line/pattern/blit have no grid meaning and refuse (carry).
; A fill sets the current text colour (white foreground, that colour as
; background), so a cx_say after a cx_clear/cx_rect prints on it.
;
; UNLIKE modes 1-2, this whole engine runs IN THE OVERLAY -- the port
; region is low RAM, always mapped, so the KERNAL console (resident
; video/screen.asm) can be called without a bank switch. That matters:
; the KERNAL screen routines do not preserve RAM_BANK, so running them
; from a kernel bank would corrupt the bank the code sits in (a crash to
; the monitor the first attempt earned). KERNAL text also assumes
; ADDRSEL=0 across sub-calls while the event IRQ touches VERA, so every
; op masks interrupts for its brief duration.
; =====================================================================

.ifndef CX_NO_OVERLAY

.segment "OV3CODE"

ov3_vector                      ; the 14 port entries, in slot order;
    jmp ov3_init                ; the 14th, text, is what cx_say reaches
    jmp ov3_clear
    jmp ov3_refuse              ; pset -- a cell is char+attr, not a pixel
    jmp ov3_refuse              ; read
    jmp ov3_hline
    jmp ov3_vline
    jmp ov3_rect
    jmp ov3_frame
    jmp ov3_refuse              ; line -- a diagonal has no grid meaning
    jmp ov3_refuse              ; pattern set
    jmp ov3_refuse              ; pattern rect
    jmp ov3_refuse              ; blit
    jmp ov3_refuse              ; masked blit
    jmp ov3_say                 ; text: print a string at a cell

.assert ov3_vector = CX_OVL, error, "OV3CODE must start at CX_OVL"

ov3_refuse
    sec
    rts

; ov3_init -- the KERNAL 80x60 text mode. CINT (screen_reset) does the
; FULL reinit -- VERA layers, the charset, the editor -- which
; screen_set_mode alone did not over CXGEOS's bitmap display (the text
; layer stayed dark). Then ISO so the charset is ASCII-ordered.
ov3_init
    php
    sei
    jsr screen_reset            ; CINT: default 80x60 text, layers and all
    lda #1                      ; ISO: the tile index is the ASCII code
    jsr screen_charset
    plp
    clc
    rts

; t_color -- A = colour: the KERNAL editor colour to white-on-A, so a
; fill paints that background and a later cx_say prints white over it.
t_color
    tax                         ; background = the colour
    lda #1                      ; foreground = white
    jmp screen_color

; t_run -- print t_cnt spaces at the current cursor/colour
t_run
    lda #' '
    jsr screen_chrout
    dec t_cnt
    bne t_run
    rts

; ov3_clear -- A = colour
ov3_clear
    php
    sei
    jsr t_color
    jsr screen_cls
    plp
    clc
    rts

; ov3_hline -- P0 = col, P2 = row, P4 = len, A = colour
ov3_hline
    php
    sei
    jsr t_color
    ldx X16_P2                  ; row
    ldy X16_P0                  ; col
    jsr screen_locate
    lda X16_P4                  ; len
    sta t_cnt
    jsr t_run
    plp
    clc
    rts

; ov3_vline -- P0 = col, P2 = row, P4 = len, A = colour
ov3_vline
    php
    sei
    jsr t_color
    lda X16_P4
    sta t_h
    lda X16_P2
    sta t_row
@row
    ldx t_row
    ldy X16_P0
    jsr screen_locate
    lda #' '
    jsr screen_chrout
    inc t_row
    dec t_h
    bne @row
    plp
    clc
    rts

; ov3_rect -- P0 = col, P2 = row, P4 = w, P6 = h, A = colour
ov3_rect
    php
    sei
    jsr t_color
    lda X16_P6                  ; h rows
    sta t_h
    lda X16_P2
    sta t_row
@row
    ldx t_row
    ldy X16_P0
    jsr screen_locate
    lda X16_P4                  ; w spaces
    sta t_cnt
    jsr t_run
    inc t_row
    dec t_h
    bne @row
    plp
    clc
    rts

; ov3_frame -- P0 = col, P2 = row, P4 = w, P6 = h, A = colour
; a one-cell coloured border
ov3_frame
    php
    sei
    jsr t_color
    ldx X16_P2                  ; the top edge
    ldy X16_P0
    jsr screen_locate
    lda X16_P4
    sta t_cnt
    jsr t_run
    lda X16_P2                  ; the bottom edge: row + h - 1
    clc
    adc X16_P6
    sec
    sbc #1
    tax
    ldy X16_P0
    jsr screen_locate
    lda X16_P4
    sta t_cnt
    jsr t_run
    lda X16_P6                  ; the two side columns
    sta t_h
    lda X16_P2
    sta t_row
@side
    ldx t_row
    ldy X16_P0
    jsr screen_locate
    lda #' '
    jsr screen_chrout
    ldx t_row
    lda X16_P0                  ; col + w - 1
    clc
    adc X16_P4
    sec
    sbc #1
    tay
    jsr screen_locate
    lda #' '
    jsr screen_chrout
    inc t_row
    dec t_h
    bne @side
    plp
    clc
    rts

; ov3_say -- A/X = string, P0 = col, P2 = row: print at the cell in the
; current colour (white foreground, whatever background a prior fill set)
ov3_say
    php
    sei
    sta t_str
    stx t_str+1
    ldx X16_P2                  ; row
    ldy X16_P0                  ; col
    jsr screen_locate
    lda t_str
    ldx t_str+1
    jsr screen_puts
    plp
    clc
    rts

t_cnt .byte 0
t_h   .byte 0
t_row .byte 0
t_str .word 0

.segment "CODE"

.endif
