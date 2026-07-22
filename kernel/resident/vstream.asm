; ca65
; =====================================================================
; CXRF :: kernel/resident/vstream.asm -- banked RAM -> VRAM streaming
; =====================================================================
; cx_vram_stream copies bytes from banked RAM into VRAM, rolling RAM_BANK
; across the 8 KB window as it goes -- the "warehouse -> stage" move an
; 8bpp tile game makes each level (docs/remap.md). It is the reciprocal
; of cx_vload (SD -> VRAM); the source is a bank instead of a file.
;
; It is RESIDENT, like the clipboard byte-mover, because it flips RAM_BANK
; to walk the source banks and bank-resident code would unmap itself
; mid-copy (the vrows_save lesson). The caller's RAM_BANK is restored.
;
;   in:  P0/P1 = VRAM destination (low 16 bits)
;        P2    = VRAM destination bit 16 (0 = $00000-$0FFFF, 1 = $10000+)
;        P3    = first source bank (data starts at that bank's $A000)
;        P4/P5 = byte count (rolls into P3+1, P3+2 ... every 8 KB)
;   out: carry clear; VERA data port 0 left at the byte past the copy.
; =====================================================================

cx_do_vram_stream
    lda #VERA_CTRL_ADDRSEL      ; select data port 0
    trb VERA_CTRL
    lda X16_P0                  ; the VRAM destination + auto-increment 1
    sta VERA_ADDR_L
    lda X16_P1
    sta VERA_ADDR_M
    lda X16_P2
    and #1                      ; bit 16 only
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H

    lda RAM_BANK                ; the caller's bank comes back on exit
    sta vs_savebank
    lda X16_P3
    sta RAM_BANK
    stz CX_VS_PTR               ; the source walks the window from $A000
    lda #$A0
    sta CX_VS_PTR+1

    lda X16_P4                  ; count 0: nothing to do
    sta vs_cnt
    lda X16_P5
    sta vs_cnt+1
    ora vs_cnt
    beq @done

@loop
    lda (CX_VS_PTR)             ; one byte, window -> port
    sta VERA_DATA0
    inc CX_VS_PTR
    bne @dec
    inc CX_VS_PTR+1            ; low byte wrapped: check the window edge
    lda CX_VS_PTR+1
    cmp #$C0                    ; past $BFFF?
    bcc @dec
    lda #$A0                    ; wrap to $A000 in the next bank
    sta CX_VS_PTR+1
    inc RAM_BANK
@dec
    lda vs_cnt                  ; count-- (16-bit)
    bne @declo
    dec vs_cnt+1
@declo
    dec vs_cnt
    lda vs_cnt
    ora vs_cnt+1
    bne @loop

@done
    lda vs_savebank
    sta RAM_BANK
    clc
    rts

vs_savebank .byte 0
vs_cnt      .word 0
