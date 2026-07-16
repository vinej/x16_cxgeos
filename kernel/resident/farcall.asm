; ca65
; =====================================================================
; CXGEOS :: kernel/resident/farcall.asm -- calling code in a kernel bank
; =====================================================================
; Menus, dialogs and widgets live in kernel banks (docs/ui.md): several
; kilobytes of cold code with no claim to the resident budget. An ABI
; slot that lands there jumps to a five-byte resident stub, and the
; stub names its destination INLINE, after the jsr:
;
;       stub:  jsr cxb_call
;              .byte 2          ; the bank
;              .addr $A012      ; the routine, in that bank's window
;
; Inline, because there is no register to say it in: A, X and Y are all
; argument registers in this ABI, and a trampoline that borrowed one
; would eat somebody's argument. cxb_call pops the return address to
; find the data, parks A and Y in cells while it reads, and hands the
; banked routine exactly the registers the caller loaded.
;
; On the way back it restores the caller's RAM_BANK and the FLAGS:
; carry is how kernel calls refuse, and a trampoline that ate it would
; poison every contract passing through it.
;
; Nested far-calls are safe -- every parked value is dead before the
; banked routine runs, and the epilogue's cells are written only after
; any inner call has fully returned. The event IRQ never far-calls, by
; rule (docs/ui.md).
; =====================================================================

cxb_call
    sta cxb_a                   ; park the caller's A and Y; X is never
    sty cxb_y                   ; touched at all

    pla                         ; the jsr pushed (stub data - 1)
    sta CX_B_PTR
    pla
    sta CX_B_PTR+1

    ldy #1                      ; the bank...
    lda (CX_B_PTR),y
    sta cxb_bank
    iny                         ; ...and the target
    lda (CX_B_PTR),y
    sta cxb_tgt
    iny
    lda (CX_B_PTR),y
    sta cxb_tgt+1

    lda RAM_BANK                ; the caller's bank comes back whatever
    pha                         ; the banked code does with the window
    lda cxb_bank
    sta RAM_BANK

    ldy cxb_y                   ; the registers, exactly as loaded
    lda cxb_a
    jsr @go

    sta cxb_a                   ; the return trip: A, then the flags,
    php                         ; survive the bank restore
    pla
    sta cxb_f
    pla
    sta RAM_BANK
    lda cxb_f
    pha
    lda cxb_a
    plp
    rts                         ; to the ORIGINAL caller: the stub's
                                ; frame was consumed reading the data

@go
    jmp (cxb_tgt)

cxb_a    .byte 0
cxb_y    .byte 0
cxb_f    .byte 0
cxb_bank .byte 0
cxb_tgt  .word 0
