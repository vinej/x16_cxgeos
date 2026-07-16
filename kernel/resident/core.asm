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
; switches there is no font to say anything with.
;
; The event system is NOT started here. Events belong to whichever app
; is running: the loader stops them before every handoff, and an app
; that wants them calls cx_ev_init itself, then cx_ev_handlers. A
; kernel that hooked the raster before any app existed would just be
; sampling a mouse for nobody.
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
; cx_do_exit -- an app is done, so the shell comes back.
;
; "Back" means reloaded: the app owns all of $0801-$9EFF while it runs,
; so the shell it replaced is gone and cx_exit fetches SHELL.CXA off
; the disk again, through the same cxl_load every launch uses. Nothing
; returns to the caller -- an app ends here or not at all -- which is
; why the stack can simply be discarded.
;
; The text screen goes up BEFORE the load is attempted: if the disk has
; no shell, the complaint below needs a mode it can be read in, and by
; then there is no app left to object to losing the framebuffer. (The
; mode set is screen_set_mode's body inlined -- four instructions
; against the 121-byte module that was its only other content. ADDRSEL
; must be 0 first; the KERNAL's screen code assumes it.)
; ---------------------------------------------------------------------
cx_do_exit
    jsr ev_stop
    jsr mouse_hide
    vera_addrsel 0
    lda #$80
    clc
    jsr SCREEN_MODE

    ldx #$FF                    ; whoever called this is not coming back
    txs
    lda #<cxl_shell
    ldx #>cxl_shell
    ldy #CXL_SHELL_LEN
    jsr cxl_load                ; returns only on failure

    ldx #0                      ; no shell: say so where it can be read,
@msg                            ; and stop -- there is nothing to run
    lda cxl_noshell,x
    beq @halt
    jsr CHROUT
    inx
    bra @msg
@halt
    bra @halt
