; ca65
; =====================================================================
; CXGEOS :: kernel/resident/core.asm -- the resident odds and ends
; =====================================================================
; The routines that are the kernel itself rather than one of its
; subsystems, and that the ABI's first section names.
; =====================================================================

; The system font's home: the boot loader puts PXL8.CXF at $A000 in this
; bank before calling cx_init, and the font engine reads it there for as
; long as the font is live. Bank 1 is the kernel data bank -- the font is
; its first tenant, the theme record is next.
CX_SYSFONT_BANK = 1

; ---------------------------------------------------------------------
; cx_init -- bring the machine up. The header at $8008 points here, so
; a loader starts the kernel without knowing anything but the header.
;
; The font before the screen, deliberately: it is the only thing here
; that can fail, and while it is being judged the machine is still in
; text mode -- so the boot stub can print what went wrong. Once the mode
; switches there is no font to say anything with. The event system goes
; last, because once its hook is in the machine is live and an interrupt
; can arrive.
;
; Carry set if there is no CXF at CX_SYSFONT_BANK:$A000 -- the loader
; forgot it, or loaded it shifted. Leaves RAM_BANK on the kernel data
; bank.
; ---------------------------------------------------------------------
cx_init
    lda #CX_SYSFONT_BANK
    sta RAM_BANK
    lda #<CX_F_WIN
    ldx #>CX_F_WIN
    jsr font_set
    bcs @nofont

    jsr gfx2_init
    lda #0
    jsr gfx2_clear

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

    ; The 80x60 text screen. This is screen_set_mode's body, inlined:
    ; four instructions against the 121 bytes of the module it lives in,
    ; and cx_exit is the kernel's only caller of it. ADDRSEL has to be 0
    ; first -- the KERNAL's screen code assumes it -- and the macro
    ; clobbers A, which is why the mode is loaded after it rather than
    ; pushed around it.
    vera_addrsel 0
    lda #$80
    clc
    jmp SCREEN_MODE
