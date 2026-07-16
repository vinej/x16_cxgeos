; ca65
; =====================================================================
; CXGEOS :: kernel/resident/core.asm -- the resident odds and ends
; =====================================================================
; The routines that are the kernel itself rather than one of its
; subsystems, and that the ABI's first section names.
; =====================================================================

; ---------------------------------------------------------------------
; cx_init -- bring the machine up. The header at $8008 points here, so
; a loader starts the kernel without knowing anything but the header.
;
; The screen and the font first, because everything visible needs them,
; and the event system last, because once its hook is in the machine is
; live and an interrupt can arrive.
;
; The image supplies `cx_sysfont`: the kernel does not read its font off
; the SD card, because a kernel whose font failed to load could not put
; a message on the screen to say so.
;
; Carry set if the font would not parse, which is the only thing here
; that can fail.
; ---------------------------------------------------------------------
cx_init
    jsr gfx2_init
    lda #0
    jsr gfx2_clear

    lda #<cx_sysfont
    ldx #>cx_sysfont
    jsr font_set
    bcs @nofont

    jsr ev_init
    clc
    rts
@nofont
    sec
    rts

; ---------------------------------------------------------------------
; cx_do_version -- A/X = the ABI version the kernel implements.
;
; Read from the header rather than assembled in: the header is what the
; loader checks an app against, so a kernel that reported anything else
; would be lying about the only number that matters.
; ---------------------------------------------------------------------
cx_do_version
    lda cx_hdr_version
    ldx cx_hdr_version+1
    rts

; ---------------------------------------------------------------------
; cx_do_exit -- an app is done.
;
; Phase 4 has no shell to go back to, so for now this hands the machine
; to BASIC the way a well-behaved program does: undo what the app could
; have left running, put the text screen back, and rts to the caller
; that SYSed us. When the shell exists this frees the app's banks and
; jumps there instead, and every app already built keeps working --
; which is the point of the slot being here from the start.
; ---------------------------------------------------------------------
cx_do_exit
    jsr ev_stop
    jsr mouse_hide
    lda #$80                    ; the 80x60 text screen
    jsr screen_set_mode
    rts
