;ACME
; =====================================================================
; x16lib :: storage/bank.asm -- banked RAM ($A000-$BFFF window)
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; RAM_BANK ($00) selects which 8 KB bank appears at $A000-$BFFF.
; Bank 0 holds KERNAL variables; banks 1..255 are yours.
;
; Offsets are 0..8191 into the window. The bulk copies auto-advance
; across bank boundaries, so a run may start near the end of one bank
; and finish in the next.
;
; All routines here save and restore RAM_BANK, so they are safe to call
; without disturbing whatever bank the caller had mapped in.
; =====================================================================

; (zone: file scope in ca65)

BANK_WINDOW     = $A000
BANK_WINDOW_END = $C000
BANK_SIZE       = BANK_WINDOW_END - BANK_WINDOW    ; 8192

; ---------------------------------------------------------------------
; bank_set / bank_get -- the RAM bank mapped at $A000
; ---------------------------------------------------------------------
bank_set
    sta RAM_BANK
    rts

bank_get
    lda RAM_BANK
    rts

; ---------------------------------------------------------------------
; bank_peek
;   in:  A = bank, X16_P0/P1 = offset (0..8191)
;   out: A = byte
; bank_poke
;   in:  A = byte, X = bank, X16_P0/P1 = offset
; ---------------------------------------------------------------------
bank_peek
    ldx RAM_BANK
    phx
    sta RAM_BANK
    jsr bank_window_ptr
    ldy #0
    lda (X16_T0),y
    plx
    stx RAM_BANK
    rts

bank_poke
    pha                         ; [byte]
    lda RAM_BANK
    pha                         ; [byte][caller bank]
    stx RAM_BANK
    jsr bank_window_ptr
    ldy #0
    pla
    tax                         ; X = caller bank
    pla                         ; A = byte to store
    sta (X16_T0),y
    stx RAM_BANK
    rts

; Shared helpers are zone-local (a leading '.'), not cheap locals (a
; leading '@'): a cheap local only reaches from one global label to the
; next, so bank_peek could not see a helper defined after bank_poke.

; T0/T1 = BANK_WINDOW + offset. Preserves A.
bank_window_ptr
    pha
    lda X16_P0
    clc
    adc #<BANK_WINDOW
    sta X16_T0
    lda X16_P1
    adc #>BANK_WINDOW
    sta X16_T1
    pla
    rts

; ---------------------------------------------------------------------
; mem_to_bank -- copy low RAM into banked RAM
;   in:  X16_P0/P1 = source address
;        X16_P2    = destination bank
;        X16_P3/P4 = destination offset (0..8191)
;        X16_P5/P6 = byte count
;
; bank_to_mem -- the inverse
;   in:  X16_P0    = source bank
;        X16_P1/P2 = source offset
;        X16_P3/P4 = destination address
;        X16_P5/P6 = byte count
;
; Both auto-advance: a run that hits the end of a bank continues at
; offset 0 of the next. The heavy lifting is the KERNAL's MEMORY_COPY
; ($FEE7) one bank-segment at a time -- far faster than a byte loop.
; ---------------------------------------------------------------------
mem_to_bank
    lda RAM_BANK
    pha
    lda X16_P2
    sta RAM_BANK

    lda X16_P0                  ; T0/T1 = low-RAM side
    sta X16_T0
    lda X16_P1
    sta X16_T1
    lda X16_P3                  ; T2/T3 = offset within the window
    sta X16_T2
    lda X16_P4
    sta X16_T3
    lda X16_P5                  ; T4/T5 = remaining
    sta X16_T4
    lda X16_P6
    sta X16_T5

@seg_out
    jsr bank_segment                ; T6/T7 = bytes until the bank edge
    beq @out_done
    lda X16_T0                  ; source: low RAM
    sta r0L
    lda X16_T1
    sta r0H
    lda X16_T2                  ; target: window + offset
    sta r1L
    lda X16_T3
    clc
    adc #>BANK_WINDOW
    sta r1H
    lda X16_T6
    sta r2L
    lda X16_T7
    sta r2H
    jsr MEMORY_COPY
    jsr bank_advance
    bra @seg_out
@out_done
    pla
    sta RAM_BANK
    rts

bank_to_mem
    lda RAM_BANK
    pha
    lda X16_P0
    sta RAM_BANK

    lda X16_P3                  ; T0/T1 = low-RAM side
    sta X16_T0
    lda X16_P4
    sta X16_T1
    lda X16_P1                  ; T2/T3 = offset within the window
    sta X16_T2
    lda X16_P2
    sta X16_T3
    lda X16_P5
    sta X16_T4
    lda X16_P6
    sta X16_T5

@seg_in
    jsr bank_segment
    beq @in_done
    lda X16_T2                  ; source: window + offset
    sta r0L
    lda X16_T3
    clc
    adc #>BANK_WINDOW
    sta r0H
    lda X16_T0                  ; target: low RAM
    sta r1L
    lda X16_T1
    sta r1H
    lda X16_T6
    sta r2L
    lda X16_T7
    sta r2H
    jsr MEMORY_COPY
    jsr bank_advance
    bra @seg_in
@in_done
    pla
    sta RAM_BANK
    rts

; --- shared helpers --------------------------------------------------

; T6/T7 = min(remaining, space left in this bank). Z set when nothing
; remains.
bank_segment
    lda X16_T4
    ora X16_T5
    beq bank_seg_done               ; remaining == 0 (Z set for the caller)

    sec                         ; space = $2000 - offset
    lda #<BANK_SIZE
    sbc X16_T2
    sta X16_T6
    lda #>BANK_SIZE
    sbc X16_T3
    sta X16_T7

    lda X16_T5                  ; remaining < space? then take remaining
    cmp X16_T7
    bcc bank_seg_take_rem
    bne bank_seg_have
    lda X16_T4
    cmp X16_T6
    bcs bank_seg_have
bank_seg_take_rem
    lda X16_T4
    sta X16_T6
    lda X16_T5
    sta X16_T7
bank_seg_have
    lda #1                      ; Z clear: there is work to do
bank_seg_done
    rts

; consume T6/T7 bytes: advance the low-RAM pointer and the window
; offset (rolling into the next bank), shrink the remaining count.
bank_advance
    clc
    lda X16_T0
    adc X16_T6
    sta X16_T0
    lda X16_T1
    adc X16_T7
    sta X16_T1

    clc
    lda X16_T2
    adc X16_T6
    sta X16_T2
    lda X16_T3
    adc X16_T7
    sta X16_T3
    cmp #>BANK_SIZE             ; offset reached $2000: next bank
    bne bank_adv_count
    stz X16_T2
    stz X16_T3
    inc RAM_BANK
bank_adv_count
    sec
    lda X16_T4
    sbc X16_T6
    sta X16_T4
    lda X16_T5
    sbc X16_T7
    sta X16_T5
    rts

; ---------------------------------------------------------------------
; bank_copy_far -- copy banked RAM to banked RAM
;   in:  X16_P0    = source bank,      X16_P1/P2 = source offset
;        X16_P3    = destination bank, X16_P4/P5 = destination offset
;        X16_P6/P7 = byte count
;
; Only one bank fits in the $A000 window at a time, so this bounces
; through a small low-RAM buffer, MEMORY_COPY on both legs. Both sides
; auto-advance across bank boundaries. The parameter block is consumed.
; ---------------------------------------------------------------------
bank_copy_far
    lda RAM_BANK
    pha

@far_loop
    lda X16_P6
    ora X16_P7
    bne @far_more
    jmp @far_done               ; out of branch range from here
@far_more

    ; chunk = min(count, bounce size, source bank space, dest space)
    ldx #BANK_BOUNCE_SIZE
    lda X16_P7
    bne @far_src_cap            ; count >= 256: the buffer is the cap
    lda X16_P6
    cmp #BANK_BOUNCE_SIZE
    bcs @far_src_cap
    tax                         ; count < buffer: count is the cap
@far_src_cap
    ; Space to the end of a bank only matters when the offset is in the
    ; window's last page: below that, more than a full chunk remains.
    sec
    lda #<BANK_SIZE
    sbc X16_P1
    sta X16_T0
    lda #>BANK_SIZE
    sbc X16_P2
    bne @far_dst_cap            ; >= 256 bytes left in the source bank
    txa
    cmp X16_T0
    bcc @far_dst_cap
    ldx X16_T0
@far_dst_cap
    sec
    lda #<BANK_SIZE
    sbc X16_P4
    sta X16_T0
    lda #>BANK_SIZE
    sbc X16_P5
    bne @far_go
    txa
    cmp X16_T0
    bcc @far_go
    ldx X16_T0
@far_go
    stx X16_T7                  ; T7 = chunk (1..BANK_BOUNCE_SIZE)

    lda X16_P0                  ; leg 1: source bank -> bounce buffer
    sta RAM_BANK
    lda X16_P1
    sta r0L
    lda X16_P2
    clc
    adc #>BANK_WINDOW
    sta r0H
    lda #<bank_bounce
    sta r1L
    lda #>bank_bounce
    sta r1H
    stx r2L
    stz r2H
    jsr MEMORY_COPY

    lda X16_P3                  ; leg 2: bounce buffer -> destination
    sta RAM_BANK
    lda #<bank_bounce
    sta r0L
    lda #>bank_bounce
    sta r0H
    lda X16_P4
    sta r1L
    lda X16_P5
    clc
    adc #>BANK_WINDOW
    sta r1H
    lda X16_T7
    sta r2L
    stz r2H
    jsr MEMORY_COPY

    clc                         ; advance the source (bank rolls at $2000)
    lda X16_P1
    adc X16_T7
    sta X16_P1
    lda X16_P2
    adc #0
    sta X16_P2
    cmp #>BANK_SIZE
    bne @far_adv_dst
    stz X16_P1
    stz X16_P2
    inc X16_P0
@far_adv_dst
    clc
    lda X16_P4
    adc X16_T7
    sta X16_P4
    lda X16_P5
    adc #0
    sta X16_P5
    cmp #>BANK_SIZE
    bne @far_count
    stz X16_P4
    stz X16_P5
    inc X16_P3
@far_count
    sec
    lda X16_P6
    sbc X16_T7
    sta X16_P6
    lda X16_P7
    sbc #0
    sta X16_P7
    jmp @far_loop

@far_done
    pla
    sta RAM_BANK
    rts

BANK_BOUNCE_SIZE = 128
bank_bounce
    .res BANK_BOUNCE_SIZE, 0

; (end zone)
