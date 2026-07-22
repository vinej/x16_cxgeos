; ca65
; =====================================================================
; CXRF :: kernel/resident/vrows.asm -- full screen rows <-> banked RAM
; =====================================================================
; The dialog engine's save-under: menus fit the VRAM strip, dialogs do
; not, so their pixels go to banked RAM (banks 8-9 in the ledger). The
; copy MUST be resident: bank-2 code cannot stream into bank 8 through
; the same $A000 window it is executing from -- flip RAM_BANK mid-loop
; and the loop vanishes. Resident code flips it freely and puts the
; caller's bank back, the same discipline the font engine keeps.
;
;   vrows_save     A = first RAM bank, X16_P0/P1 = first row,
;                  X16_P2 = row count. Rows to $A000 up, wrapping into
;                  the next bank at $C000.
;   vrows_restore  the same, the other way.
;
; Full rows, like the menu strip: one linear run, no rectangle walk.
; 102 rows fill two banks. Borrows CX_B_PTR -- the far-call trampoline
; is done with it by the time any callee runs.
; =====================================================================

vrows_save
    ldy #0
    bra vr_go
vrows_restore
    ldy #1
vr_go
    sty vr_dir
    ldx RAM_BANK                ; the caller's bank comes back at the end
    phx
    sta RAM_BANK

    ; VRAM address = row * 160 = ((row * 5) << 5): 17 bits for row<480
    lda X16_P0
    sta X16_T0
    lda X16_P1
    sta X16_T1
    asl X16_T0
    rol X16_T1
    asl X16_T0
    rol X16_T1
    clc
    lda X16_T0
    adc X16_P0
    sta X16_T0
    lda X16_T1
    adc X16_P1
    sta X16_T1                  ; row * 5
    stz X16_T2
    .repeat 5
    asl X16_T0
    rol X16_T1
    rol X16_T2
    .endrepeat

    ; byte count = rows * 160, the same shape (rows <= 102: 16 bits)
    lda X16_P2
    sta X16_T3
    stz X16_T4
    asl X16_T3
    rol X16_T4
    asl X16_T3
    rol X16_T4
    clc
    lda X16_T3
    adc X16_P2
    sta X16_T3
    lda X16_T4
    adc #0
    sta X16_T4
    .repeat 5
    asl X16_T3
    rol X16_T4
    .endrepeat

    vera_addrsel 0
    lda X16_T0
    sta VERA_ADDR_L
    lda X16_T1
    sta VERA_ADDR_M
    lda X16_T2                  ; bit 16 in ADDR_H's low bit, and the
    ora #(VERA_INC_1 << 4)      ; auto-increment in its HIGH nibble --
    sta VERA_ADDR_H             ; raw VERA_INC_1 sets no increment, so
                                ; every byte would hit one address

    lda #<$A000                 ; the banked window, walked upward
    sta CX_B_PTR
    lda #>$A000
    sta CX_B_PTR+1

@loop
    lda vr_dir
    bne @in
    lda VERA_DATA0              ; save: the screen into the bank
    sta (CX_B_PTR)
    bra @step
@in
    lda (CX_B_PTR)              ; restore: the bank onto the screen
    sta VERA_DATA0
@step
    inc CX_B_PTR
    bne @count
    inc CX_B_PTR+1
    lda CX_B_PTR+1
    cmp #$C0                    ; off the window's end: the next bank
    bne @count
    lda #$A0
    sta CX_B_PTR+1
    inc RAM_BANK
@count
    lda X16_T3
    bne @dec
    dec X16_T4
@dec
    dec X16_T3
    lda X16_T3
    ora X16_T4
    bne @loop

    plx
    stx RAM_BANK
    rts

vr_dir .byte 0
