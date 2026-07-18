; ca65
; =====================================================================
; CXGEOS :: kernel/event/event.asm -- the heartbeat
; =====================================================================
; Everything the user does arrives here first. A raster interrupt at
; scanline 0 samples the mouse, decodes its button edges, drains the
; keyboard and ticks the timer; each becomes a typed record in a queue;
; and ev_mainloop hands them to the app one at a time. That is the whole
; shape of the system: an app is a table of handlers and a call to
; ev_mainloop, exactly as a GEOS app was.
;
; Scanline 0, not the VSYNC chain, because x16lib's irq_handler has no
; per-frame user callback -- it counts frames and dispatches LINE and
; SPRCOL. irq_line_install at line 0 is the per-frame hook, and spike C
; measured what it costs: the event is in the app's hands 22-31
; scanlines later, under a millisecond.
;
; A record is 8 bytes:
;
;   0  type    EV_*
;   1  detail  the key, or the buttons that changed
;   2  x       where the pointer was, 16-bit
;   4  y
;   6  frame   the frame counter's low byte, for double-click timing
;   7  --      reserved, always 0
;
; The queue holds 16 of them. It never drops a button or a key: if it
; fills, the newest is dropped and ev_lost counts it, so the loss is
; visible rather than silent. Mouse MOVES coalesce instead -- a move
; posted while the tail is still a move overwrites it, because only the
; latest position was ever interesting, and a slow app must not make the
; pointer lag through a queue of stale positions.
;
;   ev_init      install the hook, clear the queue. Needs mouse_show
;                and gfx2_init done first.
;   ev_stop      uninstall
;   ev_count     out: A = records waiting
;   ev_get       out: X16_P0..P7 = the oldest record; carry set if none
;   ev_post      in:  X16_P0..P7 = a record. Synthetic events look
;                exactly like real ones to a handler.
;   ev_handlers  in:  A/X = a table of EV_COUNT vectors, by type
;   ev_mainloop  dispatch forever; EV_NULL is called when idle
;   ev_timer     in:  A = frames between EV_TIMERs (0 = off)
;   ev_frames    out: A = the frame counter
;
; IRQ discipline: the handler calls mouse_get, which uses the library's
; parameter block, so it brackets itself with irq_save_regs. Anything
; added here that calls into x16lib stays inside that bracket.
; =====================================================================

EV_NULL       = 0               ; the queue is empty
EV_MOUSE_MOVE = 1
EV_MOUSE_DOWN = 2
EV_MOUSE_UP   = 3
EV_DBLCLICK   = 4
EV_KEY        = 5
EV_TIMER      = 6
EV_MENU       = 7               ; posted by the menu engine: detail =
                                ; the item, P2 = the menu. Only an app
                                ; that called cx_menu_set can receive
                                ; one, so a table built before this
                                ; type existed is never read past its
                                ; end.
EV_WIDGET     = 8               ; posted by the widget toolkit: detail =
                                ; the widget index, P2 = its value. Same
                                ; contract as EV_MENU -- only an app that
                                ; called cx_wg_set is handed one.
EV_JOY        = 9               ; a joystick's buttons changed: detail =
                                ; the pad, P2/P3 = the buttons (active
                                ; high), P4/P5 = which bits changed. Same
                                ; contract again -- posted only after
                                ; cx_joy_enable, so an app that never
                                ; asked has no table entry read.
EV_COUNT      = 10              ; how many types, for the handler table

EV_MAX        = 16              ; records in the queue
EV_SIZE       = 8
EV_WRAP       = EV_MAX * EV_SIZE - 1    ; = $7F: the queue's index mask
EV_DBL        = 30              ; frames within which a second press is
                                ; a double click -- half a second
EV_KEYS       = 4               ; keys drained per frame

EV_SCANLINE   = 0               ; where the hook fires

; ---------------------------------------------------------------------
; ev_init -- clear the queue and hook scanline 0.
; ---------------------------------------------------------------------
ev_init
    php
    sei
    stz ev_head
    stz ev_tail
    stz ev_len
    stz ev_lost
    stz ev_btn
    stz ev_timer_n
    stz ev_timer_r
    lda #$FF                    ; no pointer position yet, so the first
    sta ev_mx                   ; sample always reads as a move
    sta ev_mx+1
    sta ev_my
    sta ev_my+1
    lda #<ev_null_table         ; a table that ignores everything, so
    sta CX_E_HND                ; ev_mainloop is safe before ev_handlers
    lda #>ev_null_table
    sta CX_E_HND+1
    jsr rg_reset                ; the region stack is event state: an
    plp                         ; app inherits no stale rectangles

    stz X16_P0                  ; scanline 0
    stz X16_P1
    lda #<ev_irq
    ldx #>ev_irq
    jmp irq_line_install        ; installs the CINV chain too

ev_stop
    jmp irq_line_remove

; ---------------------------------------------------------------------
; ev_handlers -- A/X = EV_COUNT vectors, indexed by type.
; ---------------------------------------------------------------------
ev_handlers
    sta CX_E_HND
    stx CX_E_HND+1
    rts

ev_frames
    jmp irq_frames

; ---------------------------------------------------------------------
; ev_timer -- A = frames between EV_TIMERs; 0 stops it.
; ---------------------------------------------------------------------
ev_timer
    php
    sei
    sta ev_timer_r
    sta ev_timer_n
    plp
    rts

; ---------------------------------------------------------------------
; the queue. head and tail are BYTE offsets already multiplied by 8, so
; walking a record is an inx and the wrap is one AND.
; ---------------------------------------------------------------------
ev_count
    lda ev_len
    rts

; ev_push -- ev_rec into the queue. Carry set if it was dropped.
; Called from the interrupt; the consumer side takes sei around its own
; touch of head/len.
ev_push
    lda ev_len
    cmp #EV_MAX
    bcs @full
    ldy ev_tail
    ldx #0
@copy
    lda ev_rec,x
    sta ev_q,y
    iny
    inx
    cpx #EV_SIZE
    bne @copy
    tya
    and #EV_WRAP
    sta ev_tail
    inc ev_len
    clc
    rts
@full
    inc ev_lost                 ; visible, not silent
    sec
    rts

; ev_push_move -- as ev_push, but a move lands on the tail if the tail
; is already a move: only the newest position matters, and a queue of
; stale ones would make the pointer lag behind the hand.
ev_push_move
    lda ev_len
    beq ev_push                 ; nothing to coalesce with
    lda ev_tail                 ; the record before the tail
    sec
    sbc #EV_SIZE
    and #EV_WRAP
    tay
    lda ev_q,y
    cmp #EV_MOUSE_MOVE
    bne ev_push
    ldx #0
@over
    lda ev_rec,x
    sta ev_q,y
    iny
    inx
    cpx #EV_SIZE
    bne @over
    clc
    rts

; ---------------------------------------------------------------------
; ev_get -- the oldest record into X16_P0..P7. Carry set if the queue
; is empty. Takes sei: the interrupt writes tail and len.
; ---------------------------------------------------------------------
ev_get
    php
    sei
    lda ev_len
    beq @empty
    ldy ev_head
    ldx #0
@copy
    lda ev_q,y
    sta X16_P0,x
    iny
    inx
    cpx #EV_SIZE
    bne @copy
    tya
    and #EV_WRAP
    sta ev_head
    dec ev_len
    plp
    clc
    rts
@empty
    plp
    sec
    rts

; ---------------------------------------------------------------------
; ev_post -- X16_P0..P7 as a record. A synthetic event goes down exactly
; the path a real one does, coalescing included -- which is what lets a
; test drive the whole system without a mouse, and lets the kernel post
; an event to itself without a special case.
; ---------------------------------------------------------------------
ev_post
    php                         ; mask around the COPY too: the IRQ's
    sei                         ; mouse pass stamps ev_rec+2..5 with the
    ldx #0                      ; live pointer every frame, and an IRQ
@copy                           ; landing mid-copy would swap a synthetic
    lda X16_P0,x                ; event's coordinates for the pointer's
    sta ev_rec,x                ; (found the hard way: a shifted build
    inx                         ; moved the IRQ phase onto menutest's
    cpx #EV_SIZE                ; synthetic MOVE and broke its hover)
    bne @copy
    lda ev_rec
    cmp #EV_MOUSE_MOVE
    beq @move
    jsr ev_push
    plp
    rts
@move
    jsr ev_push_move
    plp
    rts

; ---------------------------------------------------------------------
; ev_dispatch -- pull one record and hand it to its handler, then
; return. An empty queue dispatches EV_NULL, so an app gets its idle
; time without polling.
;
; Split from ev_mainloop so a test can dispatch exactly one event: a
; loop that never returns cannot be checked, and the dispatch is the
; part worth checking.
; ---------------------------------------------------------------------
ev_dispatch
    jsr ev_get
    bcc @have
    ldx #0                      ; EV_NULL: an all-zero record, so a
@zero                           ; handler may read x/y without caring
    stz X16_P0,x
    inx
    cpx #EV_SIZE
    bne @zero
@have
    lda X16_P0
    cmp #EV_COUNT
    bcs @done                   ; a type we do not know: drop it

    ; Mouse events belong to whoever is on top: types 1-4 walk the
    ; region stack (kernel/ui/region.asm) before the app's table is
    ; consulted. Keys and timers never route by geometry -- focus is
    ; not a rectangle.
    cmp #EV_MOUSE_MOVE
    bcc @table                  ; EV_NULL
    cmp #EV_DBLCLICK+1
    bcs @table
    jsr rg_route
    bcs @table                  ; nobody claims the point
    lda rg_vec                  ; a region does: its handler gets the
    sta @vec+1                  ; record, and the table does not
    lda rg_vec+1
    sta @vec+2
    bra @vec

@table
    lda X16_P0
    asl                         ; two bytes a vector
    tay
    lda (CX_E_HND),y
    sta @vec+1
    iny
    lda (CX_E_HND),y
    sta @vec+2
    ora @vec+1
    beq @done                   ; a null vector: this app ignores it
@vec
    jsr $FFFF                   ; patched above
@done
    rts

; ---------------------------------------------------------------------
; ev_mainloop -- dispatch forever. Never returns; a handler that wants
; out does its own thing with the stack.
; ---------------------------------------------------------------------
ev_mainloop
    jsr ev_dispatch
    bra ev_mainloop

; ---------------------------------------------------------------------
; ev_next -- the toolkit app's poll. Pull records; ROUTE every mouse
; event (types 1-4) through the region stack, exactly as ev_dispatch
; does, so a click on a widget or a menu reaches its handler and the
; handler posts EV_WIDGET / EV_MENU. Return the first NON-mouse record
; (a key, a timer, or one of those posted events) in X16_P0..P7 with
; carry clear. Carry set once the queue drains with nothing to hand
; back.
;
; It is what a C app polls in place of ev_get. ev_get is raw -- an app
; that hit-tests its own pixels (the calculator) wants that -- but a
; toolkit app needs the mouse routed, and cannot take the asm callback
; ev_dispatch hands non-mouse events to (the record lands in $22, which
; is llvm-mos's soft-stack pointer). ev_next routes the mouse for it and
; returns everything else to be polled.
; ---------------------------------------------------------------------
ev_next
    jsr ev_get
    bcs @none                   ; the queue is empty: nothing to hand back
    lda X16_P0
    cmp #EV_MOUSE_MOVE          ; below 1 (EV_NULL): hand it back, harmless
    bcc @return
    cmp #EV_DBLCLICK+1          ; 5 and up (key/timer/menu/widget): hand back
    bcs @return
    jsr rg_route                ; a mouse event: whose region holds the point?
    bcs ev_next                 ; nobody's: drop it, keep pulling
    lda rg_vec                  ; a region's: call its handler (it may post an
    sta @vec+1                  ; event), then keep pulling for a non-mouse one
    lda rg_vec+1
    sta @vec+2
@vec
    jsr $FFFF                   ; patched just above
    bra ev_next
@return
    clc
    rts
@none
    sec
    rts

ev_null_table
    .word 0, 0, 0, 0, 0, 0, 0, 0, 0 ; EV_COUNT vectors, all ignored

; =====================================================================
; the interrupt
; =====================================================================
ev_irq
    jsr irq_save_regs           ; mouse_get uses the parameter block
    jsr ev_do_mouse
    jsr ev_do_keys
    jsr ev_do_timer
    jsr ev_do_joy              ; joysticks last: they reuse ev_rec's x/y
    jsr pcm_refill              ; top up the PCM FIFO from the sample buffer
    jsr irq_restore_regs        ; (a no-op unless a sample is playing)
    rts

; --- the pointer -----------------------------------------------------
ev_do_mouse
    jsr MOUSE_SCAN              ; advance the pointer from the SMC before
                               ; reading it. The KERNAL's own VSYNC scan
                               ; does not reach us: our raster hook fires
                               ; at line 0, and the chained handler only
                               ; scans on the VSYNC flag, which is clear
                               ; then -- so without this the pointer is
                               ; configured but frozen.
    jsr mouse_get               ; P0/P1 = x, P2/P3 = y, A = buttons
    sta ev_btn_now

    lda X16_P0                  ; stamp every record with where the
    sta ev_rec+2                ; pointer is, whatever its type
    sta ev_nx
    lda X16_P1
    sta ev_rec+3
    sta ev_nx+1
    lda X16_P2
    sta ev_rec+4
    sta ev_ny
    lda X16_P3
    sta ev_rec+5
    sta ev_ny+1
    jsr irq_frames
    sta ev_rec+6
    stz ev_rec+7

    lda ev_nx                   ; moved?
    cmp ev_mx
    bne @moved
    lda ev_nx+1
    cmp ev_mx+1
    bne @moved
    lda ev_ny
    cmp ev_my
    bne @moved
    lda ev_ny+1
    cmp ev_my+1
    beq @buttons
@moved
    lda ev_mx                   ; the FIRST sample after ev_init: the
    and ev_mx+1                 ; marker is $FFFF, no real x is. The
    cmp #$FF                    ; pointer APPEARING is not the pointer
    php                         ; MOVING -- record where it is and post
    lda ev_nx                   ; nothing, or the stray MOVE lands at a
    sta ev_mx                   ; phase-dependent moment in whatever the
    lda ev_nx+1                 ; app is doing (menutest's hover check
    sta ev_mx+1                 ; caught exactly that)
    lda ev_ny
    sta ev_my
    lda ev_ny+1
    sta ev_my+1
    plp
    beq @buttons                ; first sample: seeded, silent
    lda #EV_MOUSE_MOVE
    sta ev_rec
    stz ev_rec+1
    jsr ev_push_move

@buttons
    lda ev_btn_now
    eor ev_btn
    beq @done                   ; nothing changed
    sta ev_edge

    lda ev_edge                 ; pressed = changed AND now
    and ev_btn_now
    beq @ups
    sta ev_rec+1
    and #$01                    ; only the left button double-clicks
    beq @down
    jsr irq_frames              ; soon enough after the last press?
    sec
    sbc ev_last
    cmp #EV_DBL
    bcs @down
    lda #EV_DBLCLICK
    sta ev_rec
    jsr ev_push
    lda #$FF                    ; a third press is a fresh single, not
    sta ev_last                 ; a triple
    bra @ups
@down
    lda #EV_MOUSE_DOWN
    sta ev_rec
    jsr ev_push
    jsr irq_frames
    sta ev_last

@ups
    lda ev_edge                 ; released = changed AND NOT now
    and ev_btn_now
    eor ev_edge
    beq @done
    sta ev_rec+1
    lda #EV_MOUSE_UP
    sta ev_rec
    jsr ev_push
@done
    lda ev_btn_now
    sta ev_btn
    rts

; --- the keyboard ----------------------------------------------------
; GETIN is drained rather than read once: the KERNAL buffers, and a fast
; typist beats 60 Hz. Four a frame is 240 a second.
ev_do_keys
    ldx #EV_KEYS
@key
    phx
    jsr GETIN
    plx
    cmp #0
    beq @done
    sta ev_rec+1
    lda #EV_KEY
    sta ev_rec
    lda ev_mx                   ; the pointer, for a handler that cares
    sta ev_rec+2
    lda ev_mx+1
    sta ev_rec+3
    lda ev_my
    sta ev_rec+4
    lda ev_my+1
    sta ev_rec+5
    jsr irq_frames
    sta ev_rec+6
    stz ev_rec+7
    jsr ev_push
    dex
    bne @key
@done
    rts

; --- the timer -------------------------------------------------------
ev_do_timer
    lda ev_timer_r
    beq @done                   ; off
    dec ev_timer_n
    bne @done
    lda ev_timer_r
    sta ev_timer_n              ; reload
    lda #EV_TIMER
    sta ev_rec
    stz ev_rec+1
    jsr irq_frames
    sta ev_rec+6
    stz ev_rec+7
    jsr ev_push
@done
    rts

; --- joysticks (opt-in) ----------------------------------------------
; Scanning the SNES pads costs real scanline time every frame, so the
; GUI never pays it: nothing runs until cx_joy_enable names the pads.
; The ABI's button words are ACTIVE HIGH with the filler bits gone --
; the KERNAL's raw active-low reads are inverted at this boundary, so a
; pressed button is a 1 everywhere an app looks, and an absent pad
; (raw $FF) reads as no buttons at all.

; cx_joy_enable -- A = a mask of pads (bit n = pad n, 0-3); 0 stops the
; scan. The remembered states clear, so the first scan posts a fresh
; EV_JOY for anything already held.
ev_joy_enable
    sta ev_joy_en
    ldx #7
@clr
    stz ev_joy_prev,x
    dex
    bpl @clr
    rts

; cx_joy_get -- A = pad (0 = keyboard, 1-4 = gamepads) -> A = buttons
; low (B Y SELECT START UP DOWN LEFT RIGHT), X = buttons high (A X L R
; in bits 7:4), active high; carry set if the pad is absent.
cx_do_joy_get
    jsr joy_get                 ; A/X = raw active-low, Y = $FF absent
    eor #$FF
    pha
    txa
    eor #$FF
    tax
    pla
    cpy #$FF                    ; carry set only when Y = $FF
    rts

ev_do_joy
    lda ev_joy_en
    bne @scan
    rts
@scan
    jsr joy_scan                ; fresh state; no KERNAL-IRQ assumption
    stz CX_J_I
@pad
    ldx CX_J_I
    cpx #4
    bcs @out
    lda ev_pow2,x
    and ev_joy_en
    beq @next
    txa
    jsr cx_do_joy_get           ; A/X = active-high, filler-free
    sta CX_J_CUR
    stx CX_J_CUR+1

    lda CX_J_I                ; changed since the last tick?
    asl
    tay                         ; Y = pad * 2
    lda CX_J_CUR
    eor ev_joy_prev,y
    sta CX_J_DLT
    lda CX_J_CUR+1
    eor ev_joy_prev+1,y
    sta CX_J_DLT+1
    ora CX_J_DLT
    beq @next                   ; same word: nothing to say

    lda CX_J_CUR                ; remember, then post
    sta ev_joy_prev,y
    lda CX_J_CUR+1
    sta ev_joy_prev+1,y
    lda #EV_JOY
    sta ev_rec
    lda CX_J_I
    sta ev_rec+1                ; detail = the pad
    lda CX_J_CUR
    sta ev_rec+2                ; x = the buttons now
    lda CX_J_CUR+1
    sta ev_rec+3
    lda CX_J_DLT
    sta ev_rec+4                ; y = which bits changed
    lda CX_J_DLT+1
    sta ev_rec+5
    jsr irq_frames
    sta ev_rec+6
    stz ev_rec+7
    jsr ev_push
@next
    inc CX_J_I
    bra @pad
@out
    rts

ev_joy_en   .byte 0
ev_joy_prev .res 8, 0
ev_pow2     .byte 1, 2, 4, 8

; ---------------------------------------------------------------------
ev_q       .res EV_MAX * EV_SIZE, 0
ev_rec     .res EV_SIZE, 0      ; the record being built
ev_head    .byte 0              ; byte offsets, not indices
ev_tail    .byte 0
ev_len     .byte 0
ev_lost    .byte 0              ; records the queue could not take

ev_mx      .word 0              ; where the pointer was last seen
ev_my      .word 0
ev_nx      .word 0              ; where it is now
ev_ny      .word 0
ev_btn     .byte 0              ; the buttons last seen
ev_btn_now .byte 0
ev_edge    .byte 0
ev_last    .byte 0              ; the frame of the last left press

ev_timer_n .byte 0              ; frames until the next EV_TIMER
ev_timer_r .byte 0              ; and the reload
