;ACME
; =====================================================================
; x16lib :: storage/ringbuffer.asm -- an 8 KB FIFO ring in a HIRAM bank
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; A first-in-first-out queue whose 8 KB of storage is one whole banked-RAM
; bank ($A000-$BFFF). Tell it which bank to own with ring_init, then put
; and get bytes or words. The head, tail and fill counters live in low
; RAM; only the queued data sits in the bank. There are no over/underflow
; guards -- the capacity is 8191 bytes; check ring_isfull / ring_isempty.
;
;       lda #6 : jsr ring_init       ; take bank 6 for the queue
;       lda #'H' : jsr ring_put
;       lda #<300 : ldx #>300 : jsr ring_putw
;       jsr ring_get                 ; A = 'H'  (FIFO order)
;       jsr ring_getw                ; A/X = 300
;
; Every routine saves and restores RAM_BANK. The small 256-byte ring that
; needs no bank is rb_* in util/buffers.asm.
; =====================================================================

; (zone: file scope in ca65)

RING_CAP = 8192                 ; the bank window is 8192 bytes (0..8191)

ring_bank .byte 0              ; the HIRAM bank the queue owns
ring_fill .byte 0, 0          ; bytes currently queued
ring_head .byte 0, 0          ; where the next put goes
ring_tail .byte 0, 0          ; one before where the next get comes from

; ---------------------------------------------------------------------
; ring_init -- claim a bank and empty the queue.
;   in: A = HIRAM bank number
; ---------------------------------------------------------------------
ring_init
    sta ring_bank
    stz ring_fill
    stz ring_fill+1
    stz ring_head
    stz ring_head+1
    lda #<(RING_CAP-1)          ; tail starts at the top; the first get's
    sta ring_tail               ; inc_tail wraps it to 0, where head began
    lda #>(RING_CAP-1)
    sta ring_tail+1
    rts

; ---------------------------------------------------------------------
; ring_put -- enqueue one byte.  in: A = byte
; ---------------------------------------------------------------------
ring_put
    sta X16_T2
    lda RAM_BANK
    sta X16_T3
    lda ring_bank
    sta RAM_BANK
    jsr ringbuffer_rhptr
    lda X16_T2
    sta (X16_T0)                ; buffer[head] = value
    lda X16_T3
    sta RAM_BANK
    jsr ringbuffer_inchead
    jsr ringbuffer_fillinc
    rts

; ---------------------------------------------------------------------
; ring_putw -- enqueue one word (low byte first).
;   in: A = low, X = high
; ---------------------------------------------------------------------
ring_putw
    sta X16_T2
    stx X16_T4
    lda RAM_BANK
    sta X16_T3
    lda ring_bank
    sta RAM_BANK
    jsr ringbuffer_rhptr
    lda X16_T2
    sta (X16_T0)                ; buffer[head] = low
    jsr ringbuffer_inchead
    jsr ringbuffer_rhptr
    lda X16_T4
    sta (X16_T0)                ; buffer[head] = high
    lda X16_T3
    sta RAM_BANK
    jsr ringbuffer_inchead
    jsr ringbuffer_fillinc
    jsr ringbuffer_fillinc
    rts

; ---------------------------------------------------------------------
; ring_get -- dequeue one byte.  out: A = byte
; ---------------------------------------------------------------------
ring_get
    jsr ringbuffer_filldec
    jsr ringbuffer_inctail
    lda RAM_BANK
    sta X16_T3
    lda ring_bank
    sta RAM_BANK
    jsr ringbuffer_rtptr
    lda (X16_T0)
    tay
    lda X16_T3
    sta RAM_BANK
    tya
    rts

; ---------------------------------------------------------------------
; ring_getw -- dequeue one word.  out: A = low, X = high
; ---------------------------------------------------------------------
ring_getw
    jsr ringbuffer_filldec
    jsr ringbuffer_filldec
    lda RAM_BANK
    sta X16_T3
    lda ring_bank
    sta RAM_BANK
    jsr ringbuffer_inctail
    jsr ringbuffer_rtptr
    lda (X16_T0)
    sta X16_T2                  ; low
    jsr ringbuffer_inctail
    jsr ringbuffer_rtptr
    lda (X16_T0)
    sta X16_T4                  ; high
    lda X16_T3
    sta RAM_BANK
    lda X16_T2
    ldx X16_T4
    rts

; ---------------------------------------------------------------------
; ring_size -- out: A = low, X = high  (bytes queued = fill)
; ---------------------------------------------------------------------
ring_size
    lda ring_fill
    ldx ring_fill+1
    rts

; ---------------------------------------------------------------------
; ring_free -- out: A = low, X = high  (bytes free = RING_CAP - fill)
; ---------------------------------------------------------------------
ring_free
    sec
    lda #<RING_CAP
    sbc ring_fill
    pha
    lda #>RING_CAP
    sbc ring_fill+1
    tax
    pla
    rts

; ---------------------------------------------------------------------
; ring_isempty -- out: carry set if empty (fill == 0)
; ---------------------------------------------------------------------
ring_isempty
    lda ring_fill
    ora ring_fill+1
    bne ringbuffer_notempty
    sec
    rts
ringbuffer_notempty
    clc
    rts

; ---------------------------------------------------------------------
; ring_isfull -- out: carry set if less than 2 bytes remain (fill >= 8191)
; ---------------------------------------------------------------------
ring_isfull
    lda ring_fill+1
    cmp #>(RING_CAP-1)          ; $1F
    bcc ringbuffer_notfull
    bne ringbuffer_full
    lda ring_fill
    cmp #<(RING_CAP-1)          ; $FF
    bcc ringbuffer_notfull
ringbuffer_full
    sec
    rts
ringbuffer_notfull
    clc
    rts

; --- helpers (zone-local) --------------------------------------------
; T0/T1 = $A000 + ring_head
ringbuffer_rhptr
    lda ring_head
    sta X16_T0
    lda ring_head+1
    clc
    adc #$A0
    sta X16_T1
    rts

; T0/T1 = $A000 + ring_tail
ringbuffer_rtptr
    lda ring_tail
    sta X16_T0
    lda ring_tail+1
    clc
    adc #$A0
    sta X16_T1
    rts

; head++, wrapping to 0 when it reaches RING_CAP (8192)
ringbuffer_inchead
    inc ring_head
    bne ringbuffer_inchead_hi
    inc ring_head+1
ringbuffer_inchead_hi
    lda ring_head+1
    cmp #>RING_CAP              ; $20
    bne ringbuffer_inchead_done
    stz ring_head
    stz ring_head+1
ringbuffer_inchead_done
    rts

; tail++, wrapping to 0 when it reaches RING_CAP
ringbuffer_inctail
    inc ring_tail
    bne ringbuffer_inctail_hi
    inc ring_tail+1
ringbuffer_inctail_hi
    lda ring_tail+1
    cmp #>RING_CAP
    bne ringbuffer_inctail_done
    stz ring_tail
    stz ring_tail+1
ringbuffer_inctail_done
    rts

; fill++ / fill-- (16-bit)
ringbuffer_fillinc
    inc ring_fill
    bne ringbuffer_fillinc_done
    inc ring_fill+1
ringbuffer_fillinc_done
    rts

ringbuffer_filldec
    lda ring_fill
    bne ringbuffer_filldec_lo
    dec ring_fill+1
ringbuffer_filldec_lo
    dec ring_fill
    rts

; (end zone)
