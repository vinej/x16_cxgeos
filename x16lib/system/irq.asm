;ACME
; =====================================================================
; x16lib :: system/irq.asm -- VSYNC counter, raster line and sprite
;                             collision interrupts
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Chains onto the KERNAL's IRQ vector (CINV, $0314) rather than taking
; the interrupt over. Our handler services its own sources and then
; jumps to whatever was there before, so the KERNAL still scans the
; keyboard, moves the mouse, blinks the cursor, and acknowledges the
; VERA VSYNC interrupt.
;
; The KERNAL only ever acknowledges VSYNC. LINE and SPRCOL must be
; acknowledged here (writing their ISR bit), or the moment the handler
; returns the same interrupt fires again and the machine livelocks.
;
; The KERNAL's stub has already pushed A/X/Y by the time it reaches
; CINV, and restores them on the way out, so a chained handler -- and
; the user callbacks below -- are free to clobber the registers.
;
; User callbacks run INSIDE the interrupt. Keep them short, and
; save/restore any VERA state you touch: CTRL (ADDRSEL/DCSEL) and the
; address of any data port you reprogram, or the interrupted code's
; VERA access lands somewhere else when it resumes.
; =====================================================================

; (zone: file scope in ca65)

irq_old_vector  .word 0
irq_frame_count .byte 0
irq_armed       .byte 0
irq_isr         .byte 0         ; ISR snapshot for the current interrupt

irq_line_vec    .word 0
irq_line_armed  .byte 0
; Sprite collision splits in two: the CAPTURE (the handler accumulates the
; colliding groups into irq_sprcol_mask; you enable VERA_IEN and read the
; mask yourself) is X16_USE_IRQ_SPRCOL; the convenience API on top of it
; (irq_sprcol_install/remove + a callback + sprite_collisions) is
; X16_USE_IRQ_SPRCOL_API. X16_USE_IRQ pulls both, for compat.
.ifdef X16_USE_IRQ_SPRCOL
irq_sprcol_mask .byte 0         ; collision groups seen since last read
.endif
.ifdef X16_USE_IRQ_SPRCOL_API
irq_sprcol_vec  .word 0
irq_sprcol_armed .byte 0
.endif

; ---------------------------------------------------------------------
; irq_handler -- services VSYNC / LINE / SPRCOL, then chains
; ---------------------------------------------------------------------
irq_handler
    lda VERA_ISR
    sta irq_isr

    and #VERA_IRQ_VSYNC
    beq @no_vsync
    inc irq_frame_count         ; the KERNAL acks VSYNC for us
@no_vsync

    lda irq_isr
    and #VERA_IRQ_LINE
    beq @no_line
    sta VERA_ISR                ; ack FIRST: nobody else will
    lda irq_line_armed
    beq @no_line
    jsr irq_call_line
@no_line

.ifdef X16_USE_IRQ_SPRCOL
    lda irq_isr
    and #VERA_IRQ_SPRCOL
    beq @no_sprcol
    sta VERA_ISR                ; ack FIRST: nobody else will
    lda irq_isr
    and #VERA_ISR_COLLISION     ; which collision groups fired (bits 7:4)
    ora irq_sprcol_mask         ; accumulate until it is read
    sta irq_sprcol_mask
.ifdef X16_USE_IRQ_SPRCOL_API
    lda irq_sprcol_armed
    beq @no_sprcol
    lda irq_isr
    and #VERA_ISR_COLLISION
    jsr irq_call_sprcol            ; A = the collision groups
.endif
@no_sprcol
.endif

.ifdef X16_USE_PCM_STREAM
    lda irq_isr
    and #VERA_IRQ_AFLOW
    beq @no_aflow
    jsr pcm_stream_isr          ; refilling the FIFO IS the acknowledge
@no_aflow
.endif

    jmp (irq_old_vector)

irq_call_line
    jmp (irq_line_vec)
.ifdef X16_USE_IRQ_SPRCOL_API
irq_call_sprcol
    jmp (irq_sprcol_vec)
.endif

; ---------------------------------------------------------------------
; irq_install -- hook CINV and start counting frames. Idempotent.
; ---------------------------------------------------------------------
irq_install
    lda irq_armed
    bne @done

    php                         ; restore the caller's I flag afterwards,
    sei                         ; rather than a blind cli
    lda CINV
    sta irq_old_vector
    lda CINV+1
    sta irq_old_vector+1
    lda #<irq_handler
    sta CINV
    lda #>irq_handler
    sta CINV+1
    stz irq_frame_count
    lda #VERA_IRQ_VSYNC
    tsb VERA_IEN                ; the KERNAL already enables it; harmless
    lda #1
    sta irq_armed
    plp
@done
    rts

; ---------------------------------------------------------------------
; irq_remove -- restore the previous handler and disable our sources
; ---------------------------------------------------------------------
irq_remove
    lda irq_armed
    beq @done
    php
    sei
    ; AFLOW must be in this mask. It cannot be acknowledged in ISR --
    ; it clears only when the FIFO refills -- and once CINV is back on
    ; the KERNAL, nothing refills: VERA holds the IRQ line asserted,
    ; the KERNAL handler acks VSYNC and returns, and the machine
    ; livelocks. Removing the hook mid-stream must take AFLOW with it.
    lda #(VERA_IRQ_LINE | VERA_IRQ_SPRCOL | VERA_IRQ_AFLOW)
    trb VERA_IEN                ; ours alone; VSYNC stays for the KERNAL
    stz irq_line_armed
.ifdef X16_USE_IRQ_SPRCOL_API
    stz irq_sprcol_armed
.endif
.ifdef X16_USE_PCM_STREAM
    stz pcm_str_active          ; the stream cannot continue unhooked
.endif
    lda irq_old_vector
    sta CINV
    lda irq_old_vector+1
    sta CINV+1
    stz irq_armed
    plp
@done
    rts

; ---------------------------------------------------------------------
; irq_line_install -- call a handler at a given scanline, every frame
;   in:  A = handler low, X = handler high
;        X16_P0/P1 = scanline (0-511; the visible display is 0-479)
;
; The handler runs inside the IRQ (registers free, keep it short). A
; raster split changes VERA display registers here and changes them
; back in a second line handler or in the VSYNC path.
; ---------------------------------------------------------------------
irq_line_install
    pha                         ; irq_install clobbers A -- and A/X are
    phx                         ; the handler this routine exists to keep
    jsr irq_install             ; make sure the CINV hook is in place
    plx
    pla
    php
    sei
    sta irq_line_vec
    stx irq_line_vec+1
    lda X16_P0
    sta VERA_IRQ_LINE_L
    lda X16_P1
    lsr                         ; scanline bit 8 -> carry
    lda #$80                    ; ...lives in IEN bit 7
    bcs @bit8_set
    trb VERA_IEN
    bra @bit8_done
@bit8_set
    tsb VERA_IEN
@bit8_done
    lda #VERA_IRQ_LINE
    sta VERA_ISR                ; drop any stale pending LINE interrupt
    lda #1
    sta irq_line_armed
    lda #VERA_IRQ_LINE
    tsb VERA_IEN
    plp
    rts

irq_line_remove
    php
    sei
    lda #VERA_IRQ_LINE
    trb VERA_IEN
    sta VERA_ISR                ; ack anything still pending
    stz irq_line_armed
    plp
    rts

; ---------------------------------------------------------------------
; The sprite-collision convenience API (X16_USE_IRQ_SPRCOL_API): enable
; the interrupt with a poll or callback handler, and read the groups. It
; sits on top of the CAPTURE above -- a program that enables VERA_IEN's
; collision bit itself and reads irq_sprcol_mask directly needs only
; X16_USE_IRQ_SPRCOL and drops all of this.
; ---------------------------------------------------------------------
.ifdef X16_USE_IRQ_SPRCOL_API
; ---------------------------------------------------------------------
; irq_sprcol_install -- enable the sprite collision interrupt
;   in:  A = handler low, X = handler high -- or A = X = 0 for polling
;
; VERA reports collisions between sprites whose collision masks (the
; top nibble of attribute byte 6, see sprite_flags) share a bit, once
; per frame at the end of rendering. The handler receives the group
; bits in A. With a null handler nothing is called, but the groups
; still accumulate for sprite_collisions below.
; ---------------------------------------------------------------------
irq_sprcol_install
    pha                         ; irq_install clobbers A
    phx
    jsr irq_install
    plx
    pla
    php
    sei
    sta irq_sprcol_vec
    stx irq_sprcol_vec+1
    ora irq_sprcol_vec+1        ; A|X == 0 -> poll-only, no callback
    beq @polling
    lda #1
@polling
    sta irq_sprcol_armed
    stz irq_sprcol_mask
    lda #VERA_IRQ_SPRCOL
    sta VERA_ISR                ; drop any stale pending collision
    tsb VERA_IEN
    plp
    rts

irq_sprcol_remove
    php
    sei
    lda #VERA_IRQ_SPRCOL
    trb VERA_IEN
    sta VERA_ISR
    stz irq_sprcol_armed
    plp
    rts

; ---------------------------------------------------------------------
; sprite_collisions -- read and clear the accumulated collision groups
;   out: A = group bits seen since the last call (ISR bits 7:4), Z set
;        if none. Requires irq_sprcol_install (a null handler is fine).
; ---------------------------------------------------------------------
sprite_collisions
    php
    sei                         ; read-and-clear must be atomic against
    lda irq_sprcol_mask         ; the accumulating interrupt handler
    stz irq_sprcol_mask
    plp                         ; ...but plp restores the CALLER's flags,
    ora #0                      ; so re-derive Z from A afterwards
    rts
.endif

; ---------------------------------------------------------------------
; irq_save_regs / irq_restore_regs -- bracket a callback that calls
; library routines.
;
; The KERNAL's virtual registers r0-r15 ($02-$21) and the library's
; X16_P0..X16_T7 block are ordinary zero page: whatever the interrupt
; cut off may be holding live values there. mem_copy loads r0-r2 and
; runs with interrupts enabled -- a callback that calls another mem_*,
; mouse_get, or anything using the parameter block would corrupt the
; interrupted copy's pointers on resume.
;
; A callback that only touches A/X/Y and its own variables needs
; nothing. One that calls into the library does:
;
;       my_handler
;           jsr irq_save_regs
;           ...anything at all...
;           jsr irq_restore_regs
;           rts
;
; One buffer, no nesting -- interrupts do not nest here either.
; Clobbers A and X.
; ---------------------------------------------------------------------
irq_save_regs
    ldx #31
@save_r
    lda r0L,x                   ; r0-r15 at $02-$21
    sta irq_zp_buf,x
    dex
    bpl @save_r
    ldx #15
@save_p
    lda X16_P0,x                ; the library's parameter/scratch block
    sta irq_zp_buf+32,x
    dex
    bpl @save_p
    rts

irq_restore_regs
    ldx #31
@rest_r
    lda irq_zp_buf,x
    sta r0L,x
    dex
    bpl @rest_r
    ldx #15
@rest_p
    lda irq_zp_buf+32,x
    sta X16_P0,x
    dex
    bpl @rest_p
    rts

irq_zp_buf .res 48, 0

; ---------------------------------------------------------------------
; irq_frames
;   out: A = the frame counter (wraps at 256)
;
; Byte subtraction wraps correctly, so deltas are valid across the wrap:
;       jsr irq_frames : sta start
;       ... work ...
;       jsr irq_frames : sec : sbc start   ; = frames elapsed
; ---------------------------------------------------------------------
irq_frames
    lda irq_frame_count
    rts

; ---------------------------------------------------------------------
; vsync_wait -- block until the next frame boundary.
;
; Frame-locked: it waits for the counter to change rather than polling
; VERA, so it cannot miss a frame or spin twice within one. Requires
; irq_install, and interrupts enabled -- it will hang otherwise. A
; program that drives its own loop from irq_frames does not need it, so
; it is behind X16_USE_IRQ_VSYNC (X16_USE_IRQ still pulls it, for compat).
; ---------------------------------------------------------------------
.ifdef X16_USE_IRQ_VSYNC
vsync_wait
    lda irq_frame_count
@wait
    cmp irq_frame_count
    beq @wait
    rts
.endif

; (end zone)
