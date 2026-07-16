;ACME
; =====================================================================
; x16lib :: audio/psg.asm -- VERA PSG (16 voices)
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
; Requires X16_USE_VERA (psg_init uses vera_fill).
;
; The voices live in VRAM at $1F9C0, four bytes each:
;   0  frequency 7:0
;   1  frequency 15:8
;   2  right(7) | left(6) | volume(5:0)
;   3  waveform(7:6) | pulse width or XOR(5:0)
;
; output_frequency = 25000000/512 / 2^17 * freq_word
;   -> freq_word = Hz * 2.68435 (approximately), so A4 (440 Hz) is 1181.
;
; That VRAM range is write-only. Reads return the last value the host
; wrote, so psg_get_* only report what this program last set.
; =====================================================================

; (zone: file scope in ca65)

PSG_PAN_LEFT  = %01000000
PSG_PAN_RIGHT = %10000000
PSG_PAN_BOTH  = %11000000

PSG_WAVE_PULSE    = %00000000
PSG_WAVE_SAWTOOTH = %01000000
PSG_WAVE_TRIANGLE = %10000000
PSG_WAVE_NOISE    = %11000000

; ---------------------------------------------------------------------
; psg_voice_ptr -- point data port 0 at a voice register
;   in:  X = voice (0-15), A = byte offset within the voice (0-3)
; ---------------------------------------------------------------------
psg_voice_ptr
    sta X16_T2
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL

    txa
    asl
    asl                         ; voice * 4, never carries (max 60)
    clc
    adc X16_T2
    clc
    adc #<VRAM_PSG              ; $C0 + up to 63, may carry
    sta VERA_ADDR_L
    lda #>VRAM_PSG
    adc #0
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))
    sta VERA_ADDR_H
    rts

; ---------------------------------------------------------------------
; psg_init -- silence all 16 voices
; ---------------------------------------------------------------------
psg_init
    vera_addr 0, VRAM_PSG, VERA_INC_1
    lda #0
    ldx #(16 * VERA_PSG_VOICE_SIZE)
    ldy #0
    jmp vera_fill

; ---------------------------------------------------------------------
; psg_set_freq -- in: X = voice, X16_P0/P1 = frequency word
;
; The HIGH byte is written first, stepping the port DOWNWARD from
; offset 1. Low-byte-first leaves the voice running on new-low/old-high
; for a few cycles -- an audible click on every pitch change.
; ---------------------------------------------------------------------
psg_set_freq
    lda #1                      ; point at freq bits 15:8
    jsr psg_voice_ptr
    lda VERA_ADDR_H
    ora #VERA_ADDR_H_DECR       ; ...and walk backwards
    sta VERA_ADDR_H
    lda X16_P1
    sta VERA_DATA0              ; high byte first
    lda X16_P0
    sta VERA_DATA0              ; then low, at offset 0
    rts

; ---------------------------------------------------------------------
; psg_set_vol -- in: X = voice, A = volume (0-63), Y = pan (PSG_PAN_*)
; ---------------------------------------------------------------------
psg_set_vol
    and #$3F
    sta X16_T3
    tya
    and #PSG_PAN_BOTH
    ora X16_T3
    sta X16_T3
    lda #2
    jsr psg_voice_ptr
    lda X16_T3
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; psg_set_wave -- in: X = voice, A = waveform (PSG_WAVE_*),
;                     Y = pulse width / XOR (0-63)
; ---------------------------------------------------------------------
psg_set_wave
    and #PSG_WAVE_NOISE         ; keep bits 7:6
    sta X16_T3
    tya
    and #$3F
    ora X16_T3
    sta X16_T3
    lda #3
    jsr psg_voice_ptr
    lda X16_T3
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; psg_note_off -- in: X = voice.  Volume to zero, everything else kept.
; ---------------------------------------------------------------------
psg_note_off
    lda #2
    jsr psg_voice_ptr
    lda VERA_DATA0              ; the host-written shadow
    and #PSG_PAN_BOTH           ; keep the panning, drop the volume
    pha
    lda #2
    jsr psg_voice_ptr
    pla
    sta VERA_DATA0
    rts

; =====================================================================
; ASR envelopes -- the decay everybody hand-rolls in the frame loop
; (bounce.asm included). Per voice: attack ramps the volume to a peak,
; sustain holds it for a tick count, release ramps it back to silence.
; Drive psg_env_tick once per frame -- from vsync_wait's loop or a
; VSYNC callback (bracket library calls there with irq_save_regs).
; =====================================================================

; ---------------------------------------------------------------------
; psg_env_start -- (re)trigger a voice's envelope
;   in:  A = voice (0-15)
;        X16_P0 = peak volume (0-63)
;        X16_P1 = attack step per tick (0 = jump straight to the peak)
;        X16_P2 = sustain ticks at the peak (0 = release immediately,
;                 255 = until psg_env_release)
;        X16_P3 = release step per tick (0 = hold until psg_env_stop)
;
; Set the voice's frequency, wave and pan first (psg_set_vol's pan is
; preserved; only the volume bits are driven).
; ---------------------------------------------------------------------
psg_env_start
    and #$0F
    tax
    lda X16_P0
    and #$3F
    sta env_peak,x
    lda X16_P1
    sta env_astep,x
    lda X16_P2
    sta env_sus,x
    lda X16_P3
    sta env_rstep,x
    lda X16_P1
    beq @instant
    stz env_vol,x
    lda #1                      ; stage 1: attack
    sta env_stage,x
    rts
@instant
    lda env_peak,x
    sta env_vol,x
    lda #2                      ; straight to sustain
    sta env_stage,x
    jmp psg_env_write              ; make the jump audible immediately

; ---------------------------------------------------------------------
; psg_env_release -- in: A = voice. Enter the release phase now.
; psg_env_stop    -- in: A = voice. Silence and disarm immediately.
; ---------------------------------------------------------------------
psg_env_release
    and #$0F
    tax
    lda env_stage,x
    beq @done                   ; not playing
    lda #3
    sta env_stage,x
@done
    rts

psg_env_stop
    and #$0F
    tax
    stz env_stage,x
    stz env_vol,x
    jmp psg_env_write

; ---------------------------------------------------------------------
; psg_env_tick -- advance every armed envelope one step and write the
; changed volumes to the PSG. Call once per frame. Clobbers A/X/Y and
; the port-0 address.
; ---------------------------------------------------------------------
psg_env_tick
    ldx #15
@voice
    lda env_stage,x
    beq @next                   ; 0: idle
    cmp #2
    beq @sustain
    bcc @attack                 ; 1

    ; --- release ---
    lda env_rstep,x
    beq @next                   ; rstep 0: hold until psg_env_stop
    sta X16_T0
    lda env_vol,x
    sec
    sbc X16_T0
    bcs @rel_ok
    lda #0
@rel_ok
    sta env_vol,x
    bne @write
    stz env_stage,x             ; faded out: disarm
    bra @write

@attack
    lda env_vol,x
    clc
    adc env_astep,x
    cmp env_peak,x
    bcc @att_ok
    lda env_peak,x              ; reached (or overshot) the peak
    pha
    lda #2
    sta env_stage,x
    pla
@att_ok
    sta env_vol,x
    bra @write

@sustain
    lda env_sus,x
    cmp #255
    beq @next                   ; 255: hold until psg_env_release
    dec env_sus,x
    bne @next
    lda #3                      ; sustain over: release
    sta env_stage,x
    bra @next                   ; volume unchanged this tick

@write
    jsr psg_env_write
@next
    dex
    bpl @voice
    rts

; write voice X's env_vol to its volume bits, preserving the pan bits
; (via the host-readback shadow, like psg_note_off). Preserves X --
; psg_voice_ptr does too.
psg_env_write
    lda #2
    jsr psg_voice_ptr
    lda VERA_DATA0              ; the shadow's pan bits
    and #PSG_PAN_BOTH
    ora env_vol,x
    sta X16_T0
    lda #2
    jsr psg_voice_ptr
    lda X16_T0
    sta VERA_DATA0
    rts

env_stage .res 16, 0
env_vol   .res 16, 0
env_peak  .res 16, 0
env_astep .res 16, 0
env_sus   .res 16, 0
env_rstep .res 16, 0

; (end zone)
