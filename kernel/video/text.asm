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
;   cx_clear   fill the screen with a colour (remembered as the paper)
;   cx_rect    fill a cell region with a colour (also sets the paper)
;   cx_frame   a box drawn with the PETSCII frame glyphs, in the colour
;              ink on the current paper
;   cx_hline   a run of horizontal-bar glyphs (a ruled line)
;   cx_vline   a column of vertical-bar glyphs
;   cx_line    horizontal or vertical only -- routed to the two above;
;              a diagonal has no grid meaning and refuses (carry)
;   cx_say     print a string at (col, row) -- routed here through the
;              port's 14th "text" entry (cxov_text); the cx_ink
;              attribute (white until an app sets one)
;
; pset/read/pattern/blit have no grid meaning and refuse (carry).
;
; The charset is PETSCII upper/lower -- the only set that has BOTH true
; mixed-case text and the box-drawing glyphs (ISO has neither box nor
; corner glyphs; they render as accented letters). Apps still hand
; cx_say plain ASCII: the printer maps a-z/A-Z to their PETSCII codes,
; so the case on screen is the case in the string.
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

; the PETSCII box-drawing glyphs (upper/lower charset keeps them all)
T_TL = $B0                      ; 176  top-left corner
T_TR = $AE                      ; 174  top-right corner
T_BL = $AD                      ; 173  bottom-left corner
T_BR = $BD                      ; 189  bottom-right corner
T_HB = $C0                      ; 192  horizontal bar
T_VB = $DD                      ; 221  vertical bar

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
    jmp ov3_line                ; line -- horizontal/vertical only
    jmp ov3_refuse              ; pattern set
    jmp ov3_refuse              ; pattern rect
    jmp ov3_refuse              ; blit
    jmp ov3_refuse              ; masked blit
    jmp ov3_say                 ; text: print a string at a cell
    jmp ov3_measure             ; measure: one cell per character
    jmp ov3_refuse              ; rsave: text-cell save-under -- lands
    jmp ov3_refuse              ; rrest: with the menu conversion
    .byte 1                     ; cxov_ink -- cx_say's ink attribute
                                ; (0-15); every entry resets it to white

.assert ov3_vector = CX_OVL, error, "OV3CODE must start at CX_OVL"

ov3_refuse
    sec
    rts

; ov3_init -- the KERNAL 80x60 text mode. CINT (screen_reset) does the
; FULL reinit -- VERA layers, the charset, the editor -- which
; screen_set_mode alone did not over CXGEOS's bitmap display (the text
; layer stayed dark). Then the upper/lower PETSCII charset: mixed case
; AND the box glyphs (ISO has no box glyphs at all).
ov3_init
    php
    sei
    jsr screen_reset            ; CINT: default 80x60 text, layers and all
    lda #$0E                    ; the CHR$(14) control code: the editor
    jsr screen_chrout           ; leaves ISO (the X16 default) for PETSCII
                                ; upper/lower -- flag AND charset, the
                                ; exact switch BASIC uses
    lda #6                      ; CINT leaves white-on-blue: that is the
    sta t_bg                    ; paper until a clear/rect says otherwise
    plp
    clc
    rts

; t_fill -- A = colour: white ink on that paper, for the space fills
; (the paper is what shows). Remembers the paper for later ink drawing.
t_fill
    sta t_bg
    tax
    lda #1                      ; foreground = white
    jmp screen_color

; t_ink -- A = colour: that ink on the current paper, for glyph drawing
t_ink
    ldx t_bg
    jmp screen_color

; t_run -- print t_cnt copies of t_chr at the cursor; t_cnt = 0 prints none
t_run
    lda t_cnt
    beq @done
@go
    lda t_chr
    jsr screen_chrout
    dec t_cnt
    bne @go
@done
    rts

; ov3_clear -- A = colour
ov3_clear
    php
    sei
    jsr t_fill
    jsr screen_cls
    plp
    clc
    rts

; ov3_hline -- P0 = col, P2 = row, P4 = len, A = colour: a ruled line
ov3_hline
    php
    sei
    jsr t_ink
    ldx X16_P2                  ; row
    ldy X16_P0                  ; col
    jsr screen_locate
    lda X16_P4                  ; len
    sta t_cnt
    lda #T_HB
    sta t_chr
    jsr t_run
    plp
    clc
    rts

; ov3_vline -- P0 = col, P2 = row, P4 = len, A = colour
ov3_vline
    php
    sei
    jsr t_ink
    lda #T_VB
    sta t_chr
    jsr t_col
    plp
    clc
    rts

; t_col -- a column of t_chr: P0 = col, P2 = row, P4 = len
t_col
    lda X16_P4
    beq @done
    sta t_h
    lda X16_P2
    sta t_row
@row
    ldx t_row
    ldy X16_P0
    jsr screen_locate
    lda t_chr
    jsr screen_chrout
    inc t_row
    dec t_h
    bne @row
@done
    rts

; ov3_rect -- P0 = col, P2 = row, P4 = w, P6 = h, A = colour: a filled
; panel of coloured cells (spaces); the colour becomes the paper
ov3_rect
    php
    sei
    jsr t_fill
    lda X16_P6                  ; h rows
    beq @done
    sta t_h
    lda X16_P2
    sta t_row
@row
    ldx t_row
    ldy X16_P0
    jsr screen_locate
    lda X16_P4                  ; w spaces
    sta t_cnt
    lda #' '
    sta t_chr
    jsr t_run
    inc t_row
    dec t_h
    bne @row
@done
    plp
    clc
    rts

; ov3_frame -- P0 = col, P2 = row, P4 = w, P6 = h, A = colour: a box in
; the PETSCII frame glyphs. Degenerate sizes fall back honestly: h = 1
; is a ruled line, w = 1 a bar column.
ov3_frame
    php
    sei
    jsr t_ink

    lda X16_P4                  ; w < 2: a single column of bars
    cmp #2
    bcc @thin_w
    lda X16_P6                  ; h < 2: a single ruled row
    cmp #2
    bcc @thin_h

    ldx X16_P2                  ; the top edge: corner, bars, corner
    ldy X16_P0
    jsr screen_locate
    lda #T_TL
    jsr screen_chrout
    jsr t_bars                  ; w - 2 horizontal bars
    lda #T_TR
    jsr screen_chrout

    lda X16_P2                  ; the bottom edge: row + h - 1
    clc
    adc X16_P6
    sec
    sbc #1
    tax
    ldy X16_P0
    jsr screen_locate
    lda #T_BL
    jsr screen_chrout
    jsr t_bars
    lda #T_BR
    jsr screen_chrout

    lda X16_P6                  ; the sides: rows row+1 .. row+h-2
    sec
    sbc #2
    beq @sides_done
    sta t_h
    lda X16_P2
    inc a
    sta t_row
@side
    ldx t_row
    ldy X16_P0
    jsr screen_locate
    lda #T_VB
    jsr screen_chrout
    ldx t_row
    lda X16_P0                  ; col + w - 1
    clc
    adc X16_P4
    sec
    sbc #1
    tay
    jsr screen_locate
    lda #T_VB
    jsr screen_chrout
    inc t_row
    dec t_h
    bne @side
@sides_done
    plp
    clc
    rts

@thin_w                         ; w <= 1: a bar column, h tall
    lda X16_P6
    sta X16_P4
    lda #T_VB
    sta t_chr
    jsr t_col
    plp
    clc
    rts

@thin_h                         ; h <= 1 (w >= 2): one ruled row
    ldx X16_P2
    ldy X16_P0
    jsr screen_locate
    lda X16_P4
    sta t_cnt
    lda #T_HB
    sta t_chr
    jsr t_run
    plp
    clc
    rts

; t_bars -- w - 2 horizontal bars at the cursor (w >= 2 guaranteed)
t_bars
    lda X16_P4
    sec
    sbc #2
    sta t_cnt
    lda #T_HB
    sta t_chr
    jmp t_run

; ov3_line -- P0 = x0, P2 = y0, P4 = x1, P6 = y1 (cells), A = colour.
; Horizontal or vertical only: sorted into a bar run; anything diagonal
; refuses with carry, the module policy for calls a grid cannot honour.
ov3_line
    php
    sei
    pha
    lda X16_P2
    cmp X16_P6
    beq @horiz
    lda X16_P0
    cmp X16_P4
    beq @vert
    pla
    plp
    sec
    rts

@horiz                          ; one row: col = min(x0,x1), len = |dx|+1
    lda X16_P0
    cmp X16_P4
    bcc @h_ord
    lda X16_P4                  ; swap so P0 is the left end
    ldx X16_P0
    sta X16_P0
    stx X16_P4
@h_ord
    lda X16_P4
    sec
    sbc X16_P0
    inc a
    sta X16_P4                  ; hline's len
    pla
    jsr t_ink
    ldx X16_P2
    ldy X16_P0
    jsr screen_locate
    lda X16_P4
    sta t_cnt
    lda #T_HB
    sta t_chr
    jsr t_run
    plp
    clc
    rts

@vert                           ; one column: row = min(y0,y1)
    lda X16_P2
    cmp X16_P6
    bcc @v_ord
    lda X16_P6                  ; swap so P2 is the top end
    ldx X16_P2
    sta X16_P2
    stx X16_P6
@v_ord
    lda X16_P6
    sec
    sbc X16_P2
    inc a
    sta X16_P4                  ; t_col's len
    pla
    jsr t_ink
    lda #T_VB
    sta t_chr
    jsr t_col
    plp
    clc
    rts

; ov3_say -- A/X = string, P0 = col, P2 = row: print at the cell, white
; ink on the current paper. The string is ASCII; the upper/lower charset
; wants PETSCII, so letters are mapped ('a'-'z' -> $41, 'A'-'Z' -> $C1)
; and the case on screen matches the string.
ov3_say
    php
    sei
    sta t_sl                    ; park the string FIRST -- and not in the
    stx t_sh                    ; T block: screen_color scribbles X16_T0
                                ; composing its attribute nibble, which is
                                ; exactly where TPTR0 lives
    lda cxov_ink                ; the ink cx_ink set (white until it does)
    jsr t_ink
    ldx X16_P2                  ; row
    ldy X16_P0                  ; col
    jsr screen_locate
    lda t_sl                    ; NOW the zp walker screen_puts used: only
    sta X16_TPTR0               ; screen_chrout runs from here on, and the
    lda t_sh                    ; KERNAL does not know the library's zp
    sta X16_TPTR0+1
    ldy #0
@ch
    lda (X16_TPTR0),y
    beq @done
    cmp #'_'                    ; ASCII underscore is PETSCII's left
    bne @nu                     ; arrow; the underline glyph is $A4
    lda #$A4
    bra @out
@nu
    cmp #'a'
    bcc @upper
    cmp #'z'+1
    bcs @out
    sec                         ; ASCII a-z -> PETSCII $41-$5A
    sbc #$20
    bra @out
@upper
    cmp #'A'
    bcc @out
    cmp #'Z'+1
    bcs @out
    ora #$80                    ; ASCII A-Z -> PETSCII $C1-$DA
@out
    phy
    jsr screen_chrout
    ply
    iny
    bne @ch
@done
    tya                         ; the pen: col + characters printed
    clc                         ; (cols are 0-79, no high byte to carry)
    adc X16_P0
    sta X16_P0
    plp
    clc
    rts

; measure -- A/X = string -> P0/P1 = width in cells (its length)
ov3_measure
    sta X16_TPTR0
    stx X16_TPTR0+1
    ldy #0
@len
    lda (X16_TPTR0),y
    beq @done
    iny
    bne @len
@done
    sty X16_P0
    stz X16_P1
    clc
    rts

t_cnt .byte 0
t_chr .byte 0
t_h   .byte 0
t_row .byte 0
t_bg  .byte 0
t_sl  .byte 0
t_sh  .byte 0

.segment "CODE"

.endif
