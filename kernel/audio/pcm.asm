; ca65
; =====================================================================
; CXGEOS :: kernel/audio/pcm.asm -- PCM playback, refilled per frame
; =====================================================================
; x16lib's AFLOW-driven streaming refills the FIFO from its interrupt,
; and that ISR has to be resident (the resident IRQ handler calls it
; with no bank switch) -- which overflows the budget. CXGEOS refills the
; FIFO a different way: the event IRQ already fires every frame, so
; pcm_refill (called from ev_irq) tops the 4 KB FIFO up each frame from
; the app's sample buffer. At 48 kHz a frame is ~800 bytes; the FIFO
; holds five frames, so once-a-frame refilling never underruns.
;
; This is small and fully resident -- no bank, no AFLOW, no second IRQ
; source. The one requirement it puts on an app: cx_ev_init must be
; running (the refiller rides its per-frame hook). The source lives in
; low RAM ($0801-$7FFF), read through a self-modified absolute load, not
; zero page -- the refill runs in interrupt context, where a ZP scratch
; byte may belong to whatever was interrupted (x16lib's own rule).
;
; VERA audio: AUDIO_CTRL ($9F3B) bit7 = FIFO full (read) / reset (write),
; bits 5/4 = 16-bit/stereo, bits 3:0 = volume; AUDIO_RATE ($9F3C) 0 stops,
; 128 = 48 kHz; AUDIO_DATA ($9F3D) pushes a signed sample byte.
; =====================================================================

; --- ABI entry points (resident) -------------------------------------

; cx_pcm_ctrl -- A = control byte (volume 0-15 | PCM 16-bit/stereo bits)
cx_do_pcm_ctrl
    sta VERA_AUDIO_CTRL
    rts

; cx_pcm_play -- P0/P1 = sample source (low RAM), P2/P3 = byte count,
;               A = rate (1-128, 0 stops). Resets the FIFO, primes it,
;               and starts the DAC; the per-frame refiller keeps it fed.
cx_do_pcm_play
    php                         ; the refiller also runs from the IRQ, so
    sei                         ; keep this setup + prime atomic against it
    pha                         ; keep the rate

    stz pcm_active              ; quiesce any current playback
    stz VERA_AUDIO_RATE

    lda VERA_AUDIO_CTRL         ; reset the FIFO, keeping format + volume
    and #%00111111
    ora #%10000000
    sta VERA_AUDIO_CTRL

    lda X16_P0                  ; patch the source into the refiller
    sta pcm_rd+1
    lda X16_P1
    sta pcm_rd+2
    lda X16_P2                  ; and the remaining length
    sta pcm_len
    lda X16_P3
    sta pcm_len+1

    ora X16_P2                  ; nothing to play?
    beq @none
    lda #1
    sta pcm_active
    jsr pcm_refill             ; prime the FIFO before the DAC starts
    pla
    sta VERA_AUDIO_RATE        ; ...then run it
    plp
    rts
@none
    pla
    plp
    rts

; cx_pcm_stop -- silence and forget the current sample
cx_do_pcm_stop
    stz pcm_active
    stz VERA_AUDIO_RATE
    rts

; cx_pcm_active -- out: A = 1 while a sample is still playing, else 0
cx_do_pcm_active
    lda pcm_active
    rts

; --- the per-frame refiller (called from ev_irq) ---------------------
; Pushes bytes until the FIFO is full or the sample ends. Uses only A and
; the absolute VERA registers, so it is safe inside the IRQ bracket.
; pcm_rd is a global label (the self-modify target) sitting mid-routine,
; which resets ca65's cheap-local scope -- so this loop uses plain labels
pcm_refill
    lda pcm_active
    beq pcmr_done
pcmr_loop
    lda VERA_AUDIO_CTRL         ; bit 7 = FIFO full: stop topping up
    bmi pcmr_done
    lda pcm_len                 ; sample exhausted?
    ora pcm_len+1
    beq pcmr_stop
pcm_rd
    lda $FFFF                   ; operand patched by cx_do_pcm_play
    sta VERA_AUDIO_DATA
    inc pcm_rd+1               ; advance the source (self-modified)
    bne pcmr_nc
    inc pcm_rd+2
pcmr_nc
    lda pcm_len                ; 16-bit decrement of the remaining count
    bne pcmr_declo
    dec pcm_len+1
pcmr_declo
    dec pcm_len
    bra pcmr_loop
pcmr_stop
    stz pcm_active             ; ran dry: stop the DAC so it does not buzz
    stz VERA_AUDIO_RATE
pcmr_done
    rts

pcm_active .byte 0
pcm_len    .word 0
