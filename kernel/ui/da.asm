; ca65
; =====================================================================
; CXRF :: kernel/ui/da.asm -- desk accessories
; =====================================================================
; A desk accessory is a small program that opens ON TOP of the running
; app: its window floats over the host's screen, its keys are its own,
; and closing it hands everything back exactly as it was. No
; preemption anywhere -- the DA is a guest of the host's own event
; dispatcher, which is the whole GEOS trick.
;
; The file (.CXD) is a PRG that loads at $A000 and runs in BANK 9,
; opening with a fixed header the manager trusts:
;
;   $A000  "CXDA"
;   $A004  jmp on_open       draw your window's content
;   $A007  jmp on_event      one event record in P0..P7, any type
;
; cx_da_open loads it, saves the window's pixels into banks 14-15 (the
; dialog banks -- WHICH MEANS no alert/prompt while a DA is open, the
; same exclusion the dialogs already declared), draws the box, pushes
; a region over it and swaps the key vector to the DA. Mouse events
; inside the window walk the region to the DA; clicks OUTSIDE it still
; reach the host's widgets -- cooperative, not modal. cx_da_close
; (usually called by the DA itself, on its own exit key) puts the
; handlers, the region and the pixels back.
;
; The window is fixed, like the dialogs and for the same reason:
; 140,180 to 499,275 -- 96 rows, exactly what two save-under banks
; hold. The DA draws inside it and nowhere else.
;
; The manager's brains live in bank 2; the resident pieces are the two
; ABI stubs, the event stub, the loader (it switches RAM_BANK, which
; bank-2 code must never do), and the handler table (the dispatcher
; reads it under the HOST's bank, so it cannot live in a bank).
; The bank-2 side is reached by direct address, not the $A000 table --
; the table's last slot is kept for something that needs peekable
; state; this does not.
; =====================================================================

CX_DA_BANK  = 9
DA_X0       = 140
DA_Y0       = 180
DA_W        = 360
DA_H        = 96
DA_SAVEBANK = 14                ; shared with the dialogs, exclusively

; --- the resident pieces ---------------------------------------------

cx_do_da_open
    jsr cxb_call
    .byte 2
    .addr da_open
cx_do_da_close
    jsr cxb_call
    .byte 2
    .addr da_close

da_vec                          ; every DA event: key, or a click the
    jsr cxb_call                ; region routed here
    .byte CX_DA_BANK
    .addr $A007

; da_load -- A/X = name, Y = length: the .CXD into bank 9 at $A000,
; and its magic checked. Resident because it maps bank 9 into the very
; window bank-2 code executes from. Carry set = no DA arrived.
da_load
    sta da_t                    ; SETNAM wants A = length
    stx da_t+1
    tya
    ldx da_t
    ldy da_t+1
    jsr SETNAM
    lda #1
    ldx #8
    ldy #0                      ; secondary 0: load to OUR address
    jsr SETLFS
    lda RAM_BANK
    sta da_bnk
    sei
    lda #CX_DA_BANK
    sta RAM_BANK
    lda #0                      ; load, not verify
    ldx #<$A000
    ldy #>$A000
    jsr LOAD
    bcs @bad
    ldy #3                      ; "CXDA", read while bank 9 is up
@magic
    lda $A000,y
    cmp da_magic,y
    bne @bad
    dey
    bpl @magic
    lda da_bnk
    sta RAM_BANK
    cli
    clc
    rts
@bad
    lda da_bnk
    sta RAM_BANK
    cli
    sec
    rts

da_table                        ; the swap: keys are the DA's; mouse
    .addr 0, 0, 0, 0, 0         ; rides the region; the rest, nobody's
    .addr da_vec
    .addr 0, 0, 0, 0            ; TIMER/MENU/WIDGET/JOY ignored

da_magic .byte "CXDA"
da_t     .byte 0, 0
da_bnk   .byte 0

.segment "B2CODE"

; ---------------------------------------------------------------------
; da_open -- A/X = the .CXD's name, Y = its length. Carry set if the
; file would not load or is not a DA; the screen is untouched then.
; ---------------------------------------------------------------------
da_open
    pha                         ; the name, held while the flag is
    lda da_openf                ; checked -- one DA at a time
    beq @free
    pla
    sec
    rts
@free
    pla
    jsr da_load
    bcc @loaded
    rts                         ; carry says why
@loaded

    lda #<DA_Y0                 ; the pixels under the window, away
    sta X16_P0
    stz X16_P1
    lda #DA_H
    sta X16_P2
    lda #DA_SAVEBANK
    jsr vrows_save

    lda #<DA_X0                 ; the box...
    sta X16_P0
    lda #>DA_X0
    sta X16_P1
    lda #<DA_Y0
    sta X16_P2
    stz X16_P3
    lda #<DA_W
    sta X16_P4
    lda #>DA_W
    sta X16_P5
    lda #DA_H
    sta X16_P6
    stz X16_P7
    lda th_paper
    jsr cxov_rect
    lda #<DA_X0
    sta X16_P0
    lda #>DA_X0
    sta X16_P1
    lda #<DA_Y0
    sta X16_P2
    stz X16_P3
    lda #<DA_W
    sta X16_P4
    lda #>DA_W
    sta X16_P5
    lda #DA_H
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr cxov_frame

    lda #<DA_X0                 ; ...its region...
    sta X16_P0
    lda #>DA_X0
    sta X16_P1
    lda #<DA_Y0
    sta X16_P2
    stz X16_P3
    lda #<(DA_X0+DA_W-1)
    sta X16_P4
    lda #>(DA_X0+DA_W-1)
    sta X16_P5
    lda #<(DA_Y0+DA_H-1)
    sta X16_P6
    lda #>(DA_Y0+DA_H-1)
    sta X16_P7
    lda #<da_vec
    ldx #>da_vec
    jsr rg_push

    lda CX_E_HND                ; ...and the keys are its now
    sta da_oldh
    lda CX_E_HND+1
    sta da_oldh+1
    lda #<da_table
    ldx #>da_table
    jsr ev_handlers

    lda #1
    sta da_openf

    jsr cxb_call                ; the DA's own opening move
    .byte CX_DA_BANK
    .addr $A004
    clc
    rts

; ---------------------------------------------------------------------
; da_close -- handlers, region, pixels: back, in that order. Callable
; by the DA itself mid-event; nothing here touches bank 9.
; ---------------------------------------------------------------------
da_close
    lda da_openf
    beq @out
    stz da_openf
    lda da_oldh
    ldx da_oldh+1
    jsr ev_handlers
    jsr rg_pop
    lda #<DA_Y0
    sta X16_P0
    stz X16_P1
    lda #DA_H
    sta X16_P2
    lda #DA_SAVEBANK
    jsr vrows_restore
@out
    clc
    rts

da_openf .byte 0
da_oldh  .word 0

.segment "CODE"
