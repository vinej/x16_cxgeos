;ACME
; =====================================================================
; x16lib :: audio/rom.asm -- BANK_AUDIO API wrappers
; =====================================================================
; Gate: X16_USE_AUDIO_ROM
;
; Thin wrappers over the Commander X16 ROM audio bank. These calls keep
; the ROM driver's PSG/YM volume, pan, attenuation and patch shadows
; coherent. They are intentionally separate from X16_USE_PSG/X16_USE_YM,
; whose existing local helpers remain unchanged.
;
; Prefix convention: ar_* = audio ROM.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; BASIC-compatible FM/PSG utility and play-string calls.
; ---------------------------------------------------------------------
ar_fmfreq             ; in: A=channel, X/Y=Hz, C set=no retrigger
    jsrfar rom_bas_fmfreq, BANK_AUDIO
    rts

ar_fmnote             ; in: A=channel, X=(octave<<4)|note, Y=KF, C set=no retrigger
    jsrfar rom_bas_fmnote, BANK_AUDIO
    rts

ar_fmplaystring       ; in: A=length, X/Y=string pointer
    jsrfar rom_bas_fmplaystring, BANK_AUDIO
    rts

ar_fmvib              ; in: A=LFO speed, X=depth
    jsrfar rom_bas_fmvib, BANK_AUDIO
    rts

ar_playstring_voice   ; in: A=voice/channel for next play-string call
    jsrfar rom_bas_playstringvoice, BANK_AUDIO
    rts

ar_psgfreq            ; in: A=voice, X/Y=Hz
    jsrfar rom_bas_psgfreq, BANK_AUDIO
    rts

ar_psgnote            ; in: A=voice, X=(octave<<4)|note, Y=KF
    jsrfar rom_bas_psgnote, BANK_AUDIO
    rts

ar_psgwav             ; in: A=voice, X=waveform+duty
    jsrfar rom_bas_psgwav, BANK_AUDIO
    rts

ar_psgplaystring      ; in: A=length, X/Y=string pointer
    jsrfar rom_bas_psgplaystring, BANK_AUDIO
    rts

ar_fmchordstring      ; in: A=length, X/Y=string pointer
    jsrfar rom_bas_fmchordstring, BANK_AUDIO
    rts

ar_psgchordstring     ; in: A=length, X/Y=string pointer
    jsrfar rom_bas_psgchordstring, BANK_AUDIO
    rts

; ---------------------------------------------------------------------
; Note conversion helpers.
;   Carry set means invalid input; failed calls return X/Y = 0.
;   FM output:  X = KC, Y = KF where applicable.
;   PSG output: X = frequency low, Y = frequency high.
; ---------------------------------------------------------------------
ar_note_bas2fm        ; in: X=BASIC note, out: A=X=YM KC
    jsrfar rom_notecon_bas2fm, BANK_AUDIO
    rts

ar_note_bas2midi      ; in: X=BASIC note, out: A=X=MIDI note
    jsrfar rom_notecon_bas2midi, BANK_AUDIO
    rts

ar_note_bas2psg       ; in: X=BASIC note, Y=KF, out: X/Y=PSG freq
    jsrfar rom_notecon_bas2psg, BANK_AUDIO
    rts

ar_note_fm2bas        ; in: X=YM KC, out: A=X=BASIC note
    jsrfar rom_notecon_fm2bas, BANK_AUDIO
    rts

ar_note_fm2midi       ; in: X=YM KC, out: A=X=MIDI note
    jsrfar rom_notecon_fm2midi, BANK_AUDIO
    rts

ar_note_fm2psg        ; in: X=YM KC, Y=KF, out: X/Y=PSG freq
    jsrfar rom_notecon_fm2psg, BANK_AUDIO
    rts

ar_note_freq2bas      ; in: X/Y=Hz, out: X=BASIC note, Y=KF
    jsrfar rom_notecon_freq2bas, BANK_AUDIO
    rts

ar_note_freq2fm       ; in: X/Y=Hz, out: X=KC, Y=KF
    jsrfar rom_notecon_freq2fm, BANK_AUDIO
    rts

ar_note_freq2midi     ; in: X/Y=Hz, out: X=MIDI note, Y=KF
    jsrfar rom_notecon_freq2midi, BANK_AUDIO
    rts

ar_note_freq2psg      ; in: X/Y=Hz, out: X/Y=PSG freq
    jsrfar rom_notecon_freq2psg, BANK_AUDIO
    rts

ar_note_midi2bas      ; in: A=MIDI note, out: A=X=BASIC note
    jsrfar rom_notecon_midi2bas, BANK_AUDIO
    rts

ar_note_midi2fm       ; in: X=MIDI note, out: A=X=YM KC
    jsrfar rom_notecon_midi2fm, BANK_AUDIO
    rts

ar_note_midi2psg      ; in: X=MIDI note, Y=KF, out: X/Y=PSG freq
    jsrfar rom_notecon_midi2psg, BANK_AUDIO
    rts

ar_note_psg2bas       ; in: X/Y=PSG freq, out: X=BASIC note, Y=KF
    jsrfar rom_notecon_psg2bas, BANK_AUDIO
    rts

ar_note_psg2fm        ; in: X/Y=PSG freq, out: X=KC, Y=KF
    jsrfar rom_notecon_psg2fm, BANK_AUDIO
    rts

ar_note_psg2midi      ; in: X/Y=PSG freq, out: X=MIDI note, Y=KF
    jsrfar rom_notecon_psg2midi, BANK_AUDIO
    rts

; ---------------------------------------------------------------------
; ROM PSG API.
; ---------------------------------------------------------------------
ar_psg_init
    jsrfar rom_psg_init, BANK_AUDIO
    rts

ar_psg_playfreq       ; in: A=voice, X/Y=PSG frequency
    jsrfar rom_psg_playfreq, BANK_AUDIO
    rts

ar_psg_read           ; in: X=PSG register, C set=cooked volume; out: A=value
    jsrfar rom_psg_read, BANK_AUDIO
    rts

ar_psg_setatten       ; in: A=voice, X=attenuation
    jsrfar rom_psg_setatten, BANK_AUDIO
    rts

ar_psg_setfreq        ; in: A=voice, X/Y=PSG frequency
    jsrfar rom_psg_setfreq, BANK_AUDIO
    rts

ar_psg_setpan         ; in: A=voice, X=0 off, 1 left, 2 right, 3 both
    jsrfar rom_psg_setpan, BANK_AUDIO
    rts

ar_psg_setvol         ; in: A=voice, X=volume
    jsrfar rom_psg_setvol, BANK_AUDIO
    rts

ar_psg_write          ; in: A=value, X=PSG register
    jsrfar rom_psg_write, BANK_AUDIO
    rts

ar_psg_getatten       ; in: A=voice, out: X=attenuation
    jsrfar rom_psg_getatten, BANK_AUDIO
    rts

ar_psg_getpan         ; in: A=voice, out: X=pan
    jsrfar rom_psg_getpan, BANK_AUDIO
    rts

ar_psg_write_fast     ; in: A=value, X=PSG register; caller prepoints VERA
    jsrfar rom_psg_write_fast, BANK_AUDIO
    rts

; ---------------------------------------------------------------------
; ROM YM/FM API.
; ---------------------------------------------------------------------
ar_ym_init
    jsrfar rom_ym_init, BANK_AUDIO
    rts

ar_ym_loaddefpatches
    jsrfar rom_ym_loaddefpatches, BANK_AUDIO
    rts

ar_ym_loadpatch       ; in: A=channel; C set X=ROM patch, C clear X/Y=RAM patch
    jsrfar rom_ym_loadpatch, BANK_AUDIO
    rts

ar_ym_loadpatchlfn    ; in: A=channel, X=logical file number
    jsrfar rom_ym_loadpatchlfn, BANK_AUDIO
    rts

ar_ym_playdrum        ; in: A=channel, X=drum MIDI note
    jsrfar rom_ym_playdrum, BANK_AUDIO
    rts

ar_ym_playnote        ; in: A=channel, X=KC, Y=KF, C set=no retrigger
    jsrfar rom_ym_playnote, BANK_AUDIO
    rts

ar_ym_setatten        ; in: A=channel, X=attenuation
    jsrfar rom_ym_setatten, BANK_AUDIO
    rts

ar_ym_setdrum         ; in: A=channel, X=drum MIDI note; does not trigger
    jsrfar rom_ym_setdrum, BANK_AUDIO
    rts

ar_ym_setnote         ; in: A=channel, X=KC, Y=KF; does not trigger
    jsrfar rom_ym_setnote, BANK_AUDIO
    rts

ar_ym_setpan          ; in: A=channel, X=0 off, 1 left, 2 right, 3 both
    jsrfar rom_ym_setpan, BANK_AUDIO
    rts

ar_ym_read            ; in: X=YM register, C set=cooked TL; out: A=value
    jsrfar rom_ym_read, BANK_AUDIO
    rts

ar_ym_release         ; in: A=channel
    jsrfar rom_ym_release, BANK_AUDIO
    rts

ar_ym_trigger         ; in: A=channel, C set=no retrigger
    jsrfar rom_ym_trigger, BANK_AUDIO
    rts

ar_ym_write           ; in: A=value, X=YM register; preserves shadows
    jsrfar rom_ym_write, BANK_AUDIO
    rts

ar_ym_getatten        ; in: A=channel, out: X=attenuation
    jsrfar rom_ym_getatten, BANK_AUDIO
    rts

ar_ym_getpan          ; in: A=channel, out: X=pan
    jsrfar rom_ym_getpan, BANK_AUDIO
    rts

ar_audio_init         ; init YM, PSG, and default patches
    jsrfar rom_audio_init, BANK_AUDIO
    rts

ar_ym_get_chip_type   ; out: A=0 none, 1 OPP, 2 OPM, 3 unexpected
    jsrfar rom_ym_get_chip_type, BANK_AUDIO
    rts

; (end zone)
