; ca65
; =====================================================================
; CXRF :: kernel/audio/audio.asm -- PSG + YM audio, in bank 19
; =====================================================================
; The x16lib PSG and YM modules will not fit the resident budget (all of
; audio + sprites + PCM overflows it by 868 bytes), so they ride bank 19
; -- the audio/sprites theme bank (banks.inc) -- reached through the
; five-byte far-call stubs in kernel/resident/farcall.asm. The ABI
; exposes tone control on the VERA PSG (16 voices) and note/patch/volume
; on the YM2151 FM chip.
;
; The gates X16_USE_PSG / X16_USE_YM stay OFF in kernel.asm -- turning
; them on would pull the code into the resident image. Instead the
; module sources are .included here, inside B19CODE, so they compile
; into bank 19. (They rode bank 2 until the pre-1.0 restructure gave
; each theme its own bank; the stubs' bank byte was the whole move.)
;
; YM's note and patch calls carry a processor flag x16lib reads (carry
; clear = retrigger; carry set = the index is a ROM patch), and that flag
; cannot survive cxb_call. Two bank-side shims set it just before the
; jump.
; =====================================================================

CX_AUDIO_BANK = CX_AUD_BANK     ; bank 18 (banks.inc)

; --- the resident far-call stubs (CODE) ------------------------------
cx_do_psg_init
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr psg_init
cx_do_psg_freq
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr psg_set_freq
cx_do_psg_vol
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr psg_set_vol
cx_do_psg_wave
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr psg_set_wave
cx_do_psg_off
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr psg_note_off

cx_do_ym_init
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr ym_init
cx_do_ym_note
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr ym_note_retrig
cx_do_ym_off
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr ym_release_note
cx_do_ym_vol
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr ym_vol
cx_do_ym_patch
    jsr cxb_call
    .byte CX_AUDIO_BANK
    .addr ym_patch_rom

; --- the banked code (B19CODE) ---------------------------------------
.segment "B18CODE"

; the carry flag ym_note_bas / ym_patch read cannot pass through cxb_call,
; so set it here, on the bank side, right before the x16lib routine
ym_note_retrig
    clc                         ; retrigger the envelope on a new note
    jmp ym_note_bas
ym_patch_rom
    sec                         ; X names a ROM patch (0-162)
    jmp ym_patch

; the x16lib modules themselves, compiled into bank 19 (the gates stay
; off so x16_code.asm does not also place them in the resident image)
.include "audio/psg.asm"
.include "audio/ym.asm"

.segment "CODE"
