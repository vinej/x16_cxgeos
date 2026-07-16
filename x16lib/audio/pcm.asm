;ACME
; =====================================================================
; x16lib :: audio/pcm.asm -- VERA PCM audio (4 KB FIFO)
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; AUDIO_CTRL ($9F3B): bit 7 read = FIFO full, bit 6 read = FIFO empty,
;   bit 5 = 16-bit, bit 4 = stereo, bits 3:0 = volume (0-15).
;   Writing a 1 to bit 7 resets the FIFO.
; AUDIO_RATE ($9F3C): 0 stops playback, 128 = 48828 Hz. Above 128 is
;   invalid.
; AUDIO_DATA ($9F3D): each write pushes one byte. Writes are silently
;   dropped when the FIFO is full.
;
; Samples are two's-complement signed.
;
; Set the rate to 0, prime the FIFO, then set the real rate. Starting
; playback on an empty FIFO underruns immediately.
; =====================================================================

; (zone: file scope in ca65)

PCM_FIFO_FULL   = %10000000
PCM_FIFO_EMPTY  = %01000000
PCM_FIFO_RESET  = %10000000     ; on write
PCM_16BIT       = %00100000
PCM_STEREO      = %00010000

; ---------------------------------------------------------------------
; pcm_ctrl  -- in: A = control byte (volume | stereo | 16-bit | reset)
; pcm_rate  -- in: A = sample rate (0 stops, 128 is full speed)
; pcm_reset -- clear the FIFO, keeping the current format and volume
; ---------------------------------------------------------------------
pcm_ctrl
    sta VERA_AUDIO_CTRL
    rts

pcm_rate
    cmp #129
    bcc @ok
    lda #128                    ; anything above 128 is invalid
@ok
    sta VERA_AUDIO_RATE
    rts

pcm_reset
    lda VERA_AUDIO_CTRL
    and #(PCM_16BIT | PCM_STEREO | $0F)
    ora #PCM_FIFO_RESET
    sta VERA_AUDIO_CTRL
    rts

; ---------------------------------------------------------------------
; pcm_full  -- out: carry set if the FIFO cannot take another byte
; pcm_empty -- out: carry set if the FIFO has run dry
; ---------------------------------------------------------------------
pcm_full
    lda VERA_AUDIO_CTRL
    asl                         ; bit 7 into carry
    rts

pcm_empty
    lda VERA_AUDIO_CTRL
    and #PCM_FIFO_EMPTY
    cmp #PCM_FIFO_EMPTY         ; carry set when the bit is set
    rts

; ---------------------------------------------------------------------
; pcm_put -- in: A = sample byte.  Dropped by the hardware if full.
; ---------------------------------------------------------------------
pcm_put
    sta VERA_AUDIO_DATA
    rts

; ---------------------------------------------------------------------
; pcm_write -- push a block into the FIFO
;   in:  X16_P0/P1 = source address, X16_P2/P3 = byte count
;
; Does not throttle: intended for priming an empty FIFO with up to 4 KB.
; Bytes written past a full FIFO are discarded by the hardware, so pace
; a longer stream yourself with pcm_full.
; ---------------------------------------------------------------------
pcm_write
    ldy #0
@loop
    lda X16_P2
    ora X16_P3
    beq @done                   ; count exhausted

    lda (X16_P0),y
    sta VERA_AUDIO_DATA

    inc X16_P0                  ; advance the source pointer
    bne @dec
    inc X16_P1
@dec
    lda X16_P2                  ; 16-bit decrement of the count
    bne @dec_low
    dec X16_P3
@dec_low
    dec X16_P2
    bra @loop
@done
    rts

; =====================================================================
; AFLOW-driven streaming (X16_USE_PCM_STREAM, which implies X16_USE_IRQ)
;
; pcm_write primes a FIFO; it cannot PLAY anything longer than the
; FIFO's 4 KB. Streaming works the way the hardware intends: VERA
; raises AFLOW whenever the FIFO drops below 1/4 full, and the
; interrupt refills it from the sample buffer. AFLOW has no ISR
; acknowledge -- it clears only when the FIFO rises back over 1/4, and
; when the data runs out the refiller must disable it in IEN or the
; interrupt storms forever.
;
; The source pointer is kept inside an absolute lda (self-modified),
; not in zero page: the refill runs in interrupt context, where every
; zero-page scratch byte may belong to whatever code was interrupted.
; =====================================================================
.ifdef X16_USE_PCM_STREAM

pcm_str_rem    .res 3, 0       ; bytes still to feed (24-bit)
pcm_str_active .byte 0
pcm_str_loop   .byte 0          ; caller-owned: nonzero = wrap to the
                                ; start when the data runs out; set or
                                ; clear it BEFORE pcm_stream_start*
pcm_str_mode   .byte 0          ; 0 = low RAM source, 1 = banked RAM
pcm_str_bank   .byte 0          ; the bank currently being read (mode 1)
pcm_str_rsrc   .word 0          ; rewind snapshot: source address...
pcm_str_rbank  .byte 0          ; ...bank...
pcm_str_rlen   .res 3, 0       ; ...and byte count
pcm_str_svbk   .byte 0          ; the interrupted code's RAM_BANK

; ---------------------------------------------------------------------
; pcm_stream_start -- play a sample buffer through the FIFO
;   in:  X16_P0/P1 = sample data (low RAM)
;        X16_P2/P3 = byte count
;        A         = sample rate (1-128; 128 = 48828 Hz)
;
; Set the format and volume first with pcm_ctrl, and pcm_str_loop if
; the sample should repeat. The FIFO is primed here in one go, THEN
; the rate starts playback, so it cannot underrun at t=0. Requires
; interrupts enabled; installs the CINV hook itself.
; ---------------------------------------------------------------------
pcm_stream_start
    pha
    jsr pcm_stream_stop         ; quiesce a previous stream

    stz pcm_str_mode
    lda X16_P0                  ; patch the source into the refiller
    sta pcm_src+1
    sta pcm_str_rsrc
    lda X16_P1
    sta pcm_src+2
    sta pcm_str_rsrc+1
    lda X16_P2
    sta pcm_str_rem
    sta pcm_str_rlen
    lda X16_P3
    sta pcm_str_rem+1
    sta pcm_str_rlen+1
    stz pcm_str_rem+2
    stz pcm_str_rlen+2
    ora X16_P2
    bne pcm_start_common
    pla                         ; zero bytes: nothing to play
    rts

; ---------------------------------------------------------------------
; pcm_stream_start_bank -- play a sample living in banked RAM
;   in:  X16_P0/P1 = offset within the bank window (0-8191)
;        X16_P2/P3/P4 = byte count (24 bits: whole songs)
;        X16_P5    = the bank the sample starts in
;        A         = sample rate (1-128)
;
; The refiller maps banks in as it goes (rolling $C000 back to $A000,
; bank + 1) and always restores the interrupted code's RAM_BANK, so
; the main program never notices.
; ---------------------------------------------------------------------
pcm_stream_start_bank
    pha
    jsr pcm_stream_stop

    lda #1
    sta pcm_str_mode
    lda X16_P0                  ; window address = $A000 + offset
    sta pcm_src+1
    sta pcm_str_rsrc
    lda X16_P1
    clc
    adc #$A0
    sta pcm_src+2
    sta pcm_str_rsrc+1
    lda X16_P5
    sta pcm_str_bank
    sta pcm_str_rbank
    lda X16_P2
    sta pcm_str_rem
    sta pcm_str_rlen
    lda X16_P3
    sta pcm_str_rem+1
    sta pcm_str_rlen+1
    lda X16_P4
    sta pcm_str_rem+2
    sta pcm_str_rlen+2
    ora X16_P2
    ora X16_P3
    bne pcm_start_common
    pla
    rts

; the shared tail: hook, prime, arm AFLOW if data remains, set the rate
pcm_start_common
    jsr irq_install
    lda #1
    sta pcm_str_active
    jsr pcm_stream_fill         ; prime the FIFO before playback starts

    lda pcm_str_active          ; anything left to stream?
    beq @go                     ; no: it all fit in the FIFO
    php
    sei
    lda #VERA_IRQ_AFLOW
    tsb VERA_IEN
    plp
@go
    pla
    jmp pcm_rate                ; ...and start the DAC

; ---------------------------------------------------------------------
; pcm_stream_stop -- stop refilling. What is already queued in the
; FIFO keeps playing; call pcm_reset/pcm_rate(0) for immediate silence.
; (pcm_str_loop is caller-owned and survives; a looping stream stops
; all the same -- the loop flag only matters when the data runs out.)
; ---------------------------------------------------------------------
pcm_stream_stop
    php
    sei
    lda #VERA_IRQ_AFLOW
    trb VERA_IEN
    stz pcm_str_active
    plp
    rts

; ---------------------------------------------------------------------
; pcm_stream_active -- out: A = 1 while data remains, 0 when the whole
;                      buffer has been handed to the FIFO (Z mirrors A)
;                      A looping stream stays active until stopped.
; ---------------------------------------------------------------------
pcm_stream_active
    lda pcm_str_active
    rts

; ---------------------------------------------------------------------
; pcm_stream_isr -- the AFLOW service, called from irq_handler.
; pcm_stream_fill -- push bytes until the FIFO is full or the data is
;                    gone; also used to prime. Clobbers A/X/Y (fine in
;                    the IRQ; the KERNAL stub restores them).
; ---------------------------------------------------------------------
pcm_stream_isr
    lda pcm_str_active
    bne pcm_stream_fill
    lda #VERA_IRQ_AFLOW         ; stray AFLOW with no stream: mute it
    trb VERA_IEN
    rts

pcm_stream_fill
    lda pcm_str_mode
    beq psf_loop
    lda RAM_BANK                ; banked source: map it in, and put the
    sta pcm_str_svbk            ; interrupted code's bank back on exit
    lda pcm_str_bank
    sta RAM_BANK
psf_loop
    lda pcm_str_rem
    ora pcm_str_rem+1
    ora pcm_str_rem+2
    beq psf_exhausted
    bit VERA_AUDIO_CTRL         ; bit 7: FIFO full
    bpl psf_feed
    jmp psf_full                   ; out of branch range from here
psf_feed
pcm_src
    lda $FFFF                   ; operand = current source (self-modified)
    sta VERA_AUDIO_DATA

    inc pcm_src+1                  ; advance the source
    bne psf_dec
    inc pcm_src+2
    lda pcm_str_mode
    beq psf_dec
    lda pcm_src+2                  ; banked: roll $C000 -> $A000, bank + 1
    cmp #$C0
    bne psf_dec
    lda #$A0
    sta pcm_src+2
    inc pcm_str_bank
    lda pcm_str_bank
    sta RAM_BANK
psf_dec
    lda pcm_str_rem             ; 24-bit decrement
    bne psf_dec0
    lda pcm_str_rem+1
    bne psf_dec1
    dec pcm_str_rem+2
psf_dec1
    dec pcm_str_rem+1
psf_dec0
    dec pcm_str_rem
    bra psf_loop

psf_exhausted
    lda pcm_str_loop
    beq psf_stop_refill
    lda pcm_str_rlen            ; an empty snapshot cannot loop
    ora pcm_str_rlen+1
    ora pcm_str_rlen+2
    beq psf_stop_refill
    lda pcm_str_rsrc            ; rewind to the start...
    sta pcm_src+1
    lda pcm_str_rsrc+1
    sta pcm_src+2
    lda pcm_str_rlen
    sta pcm_str_rem
    lda pcm_str_rlen+1
    sta pcm_str_rem+1
    lda pcm_str_rlen+2
    sta pcm_str_rem+2
    lda pcm_str_mode
    bne psf_rewind_bank
    jmp psf_loop                   ; psf_loop is out of branch range from here
psf_rewind_bank
    lda pcm_str_rbank           ; ...including the starting bank
    sta pcm_str_bank
    sta RAM_BANK
    jmp psf_loop

psf_stop_refill
    lda #VERA_IRQ_AFLOW         ; out of data: stop the refill interrupt
    trb VERA_IEN                ; (leaving it enabled would storm: AFLOW
    stz pcm_str_active          ; only clears by refilling the FIFO)
psf_full
    lda pcm_str_mode
    beq psf_out
    lda pcm_str_svbk            ; the interrupted code's bank goes back
    sta RAM_BANK
psf_out
    rts

.endif

; (end zone)
