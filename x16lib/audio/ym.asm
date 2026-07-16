;ACME
; =====================================================================
; x16lib :: audio/ym.asm -- YM2151 FM synthesiser
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The chip is at YM_REG ($9F40) and YM_DATA ($9F41). Note: NOT $9FE0.
;
; Two ways in, and they do not mix freely:
;
;   ym_write   writes a chip register directly. Fast, complete access to
;              everything (LFO, per-operator envelopes) -- but the ROM
;              audio driver keeps RAM shadows of volume and pan, and a
;              raw write leaves those stale.
;
;   ym_poke    goes through the ROM driver in BANK_AUDIO, keeping its
;              shadows coherent. Use this if you also use the note API.
;
; This is the AUDIOYM.TXT distinction between YM! and FMPOKE.
; =====================================================================

; (zone: file scope in ca65)

YM_TIMEOUT = 128                ; busy-wait spins before giving up
YM_BUSY    = %10000000          ; YM_DATA bit 7 while the chip is busy

; ---------------------------------------------------------------------
; ym_write -- raw register write
;   in:  A = value, X = register
;   out: carry clear on success, set if the chip stayed busy
;   Preserves A and X.
;
; The busy flag must be clear before touching YM_REG, and the chip needs
; settling time between the register select and the data write. Wrapped
; in sei so an interrupt cannot land between the two halves and leave a
; half-issued write behind.
; ---------------------------------------------------------------------
ym_write
    php
    sei

    ldy #YM_TIMEOUT
@wait
    dey
    bmi @timeout
    bit YM_DATA
    bmi @wait                   ; busy

    stx YM_REG
    nop                         ; settling time between select and data
    nop
    nop
    sta YM_DATA

    plp
    clc
    rts
@timeout
    plp
    sec
    rts

; ---------------------------------------------------------------------
; ym_busy -- out: carry set while the chip is busy
; ---------------------------------------------------------------------
ym_busy
    lda YM_DATA
    asl                         ; bit 7 into carry
    rts

; ---------------------------------------------------------------------
; ROM driver entry points. All of these live in BANK_AUDIO at $C000+,
; not in the $FFxx jump table, so they go through jsrfar.
;
; jsrfar restores the callee's processor status on the way out, so the
; carry flag survives in BOTH directions: you can pass a flag in (as
; ym_patch does) and read a result out.
;
; ***  THE CHANNEL GOES IN ym_A, NOT ym_X.  ***
; Every one of these takes the FM channel (0-7) in ym_A and its payload in
; ym_X. That is the opposite of what the register-level ym_write does, and
; the opposite of what you would guess. Getting it backwards plays a
; valid-looking note on the wrong channel rather than failing.
; ---------------------------------------------------------------------

; ym_init -- reset the chip and load the default instrument patches
;   out: carry set on failure
ym_init
    jsrfar rom_audio_init, BANK_AUDIO
    jsrfar rom_ym_loaddefpatches, BANK_AUDIO
    rts

; ym_poke -- in: A = value, X = register.  Keeps the driver's shadows
;            coherent, unlike ym_write.  Preserves A and X.
ym_poke
    jsrfar rom_ym_write, BANK_AUDIO
    rts

; ym_patch -- load an instrument
;   in:  A = channel (0-7)
;        carry set: X = ROM patch index (0-162)
;        carry clear: X/Y = address of a patch in RAM
;   out: carry set on failure
ym_patch
    jsrfar rom_ym_loadpatch, BANK_AUDIO
    rts

; ym_note -- play a raw YM2151 key code
;   in:  A = channel, X = KC (key code), Y = KF (key fraction / bend)
;        carry clear to retrigger the envelope, set to just change pitch
ym_note
    jsrfar rom_ym_playnote, BANK_AUDIO
    rts

; ym_note_bas -- play a packed note, the FMNOTE of AUDIOFM.TXT
;   in:  A = channel, X = (octave << 4) | 1..12,  X = 0 releases
;        carry clear to retrigger
;   out: carry set on failure
;
; Goes through the ROM's BASIC shim, which converts the packed note to a
; key code for us. This is the one you want for playing tunes.
ym_note_bas
    jsrfar rom_bas_fmnote, BANK_AUDIO
    rts

; ym_release_note -- in: A = channel
ym_release_note
    jsrfar rom_ym_release, BANK_AUDIO
    rts

; ym_vol -- in: A = channel, X = attenuation (0 = the patch's own volume,
;                                             larger = quieter)
ym_vol
    jsrfar rom_ym_setatten, BANK_AUDIO
    rts

; ym_pan -- in: A = channel, X = 0 off, 1 left, 2 right, 3 both
ym_pan
    jsrfar rom_ym_setpan, BANK_AUDIO
    rts

; ym_get_pan -- in: A = channel.  out: X = pan setting
; ym_get_vol -- in: A = channel.  out: X = attenuation
;
; Read the ROM driver's shadows. These only agree with the chip if you
; have been writing through ym_poke / ym_vol / ym_pan rather than the
; raw ym_write.
ym_get_pan
    jsrfar rom_ym_getpan, BANK_AUDIO
    rts

ym_get_vol
    jsrfar rom_ym_getatten, BANK_AUDIO
    rts

; ym_drum -- in: A = channel, X = drum note (25-87)
ym_drum
    jsrfar rom_ym_playdrum, BANK_AUDIO
    rts

; (end zone)
