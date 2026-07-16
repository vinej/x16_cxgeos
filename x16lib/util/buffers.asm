;ACME
; =====================================================================
; x16lib :: util/buffers.asm -- byte ring buffer and byte stack
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The two structures an input queue and an audio refiller keep
; reinventing. One static instance of each, 256 bytes of storage,
; 8-bit indices so wrap-around is free. Capacity is 255 (a count byte
; distinguishes full from empty).
;
; Single-producer/single-consumer safe across an interrupt boundary is
; NOT promised: put and get both touch the count. If one side runs in
; an IRQ, wrap the other side's call in php/sei/plp.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; rb_init  -- empty the ring buffer
; rb_put   -- in: A = byte.  carry set = full, byte not stored
; rb_get   -- out: A = byte. carry set = empty
; rb_count -- out: A = bytes queued (Z reflects it)
; rb_put/rb_get preserve X and Y.
; ---------------------------------------------------------------------
rb_init
    stz rb_head
    stz rb_tail
    stz rb_len
    rts

rb_put
    pha
    lda rb_len
    cmp #255
    bcs @full
    pla
    phx
    ldx rb_head
    sta rb_data,x
    inc rb_head
    inc rb_len
    plx
    clc
    rts
@full
    pla
    sec
    rts

rb_get
    lda rb_len
    beq @empty
    phx
    ldx rb_tail
    lda rb_data,x
    inc rb_tail
    dec rb_len
    plx
    clc
    rts
@empty
    sec
    rts

rb_count
    lda rb_len
    rts

; ---------------------------------------------------------------------
; stk_init  -- empty the stack
; stk_push  -- in: A = byte.  carry set = full (255 deep)
; stk_pop   -- out: A = byte. carry set = empty
; stk_depth -- out: A = bytes stacked
; stk_push/stk_pop preserve X and Y.
; ---------------------------------------------------------------------
stk_init
    stz stk_sp
    rts

stk_push
    pha
    lda stk_sp
    cmp #255
    bcs @full
    pla
    phx
    ldx stk_sp
    sta stk_data,x
    inc stk_sp
    plx
    clc
    rts
@full
    pla
    sec
    rts

stk_pop
    lda stk_sp
    beq @empty
    phx
    dec stk_sp
    ldx stk_sp
    lda stk_data,x
    plx
    clc
    rts
@empty
    sec
    rts

stk_depth
    lda stk_sp
    rts

rb_head  .byte 0
rb_tail  .byte 0
rb_len   .byte 0
rb_data  .res 256, 0
stk_sp   .byte 0
stk_data .res 256, 0

; (end zone)
