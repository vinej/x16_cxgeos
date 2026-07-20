; ca65
; =====================================================================
; CXGEOS asmsdk (ca65) -- friendly macros over the generated ABI
; =====================================================================
; The generated include (sdk/include_ca65/cxgeos.inc) is deliberately
; low-level: it gives you the slot ADDRESSES, and you hand-load the
; X16_P0..P7 parameter block before every jsr. This layer is the
; assembler parallel of csdk/cxsdk.h: named one-line macros, the shared
; constants, and descriptor builders for widgets, menus, dialogs, panels
; and themes -- so an asm app reads by intent, not by register.
;
; Include it AFTER x16.asm (the macros use X16_P0..P7):
;
;     .include "x16.asm"
;     .include "asmsdk/ca65/cxgeos.inc"
;
; THREE tiers, no name clashes:
;   cx_*   (lower)  the ABI slot ADDRESSES  -- generated, pulled in below
;   CX_*   (UPPER)  the shared CONSTANTS    -- defined here
;   cxm_*  (lower)  the friendly MACROS      -- defined here ("m" = macro)
;
; A wrapper expands to exactly the lda/sta you would have written by hand
; (a constant zero high byte becomes stz), so it costs not one extra byte
; -- pure readability. Verified byte-identical against hand code.
;
; MAINTAINER GOTCHA: a macro parameter must NEVER be named `x`, `y` or
; `a`. Inside a nested macro call ca65 re-parses the substituted token and
; reads a bare `x`/`y` as the index register ("Unexpected trailing garbage
; characters"). Coordinate params are x0/y0/xc/yc/rx/ry, never a register
; letter.
; =====================================================================

.ifndef CXGEOS_ASMSDK
CXGEOS_ASMSDK = 1

; the slot addresses (cx_version = $8010, ...). This is the ONE place the
; generated equates are pulled in; converted apps include only this file.
.include "sdk/include_ca65/cxgeos.inc"

; =====================================================================
; constants  (mirror csdk/cxsdk.h; CX_* never clashes with the lower-case
; cx_* slot addresses)
; =====================================================================

; --- graphics modes (cxm_gfx_mode) ---
CX_MODE_GUI   = 0             ; 640x480, 4 colours -- the desktop
CX_MODE_BMP8  = 1             ; 320x240, 256 colours
CX_MODE_TILE  = 2             ; two tile layers + sprites (games)
CX_MODE_TEXT  = 3             ; 80x60 text cells, 16 colours

; --- event types (an event record's byte 0 / P0) ---
CX_ET_NULL    = 0
CX_ET_MOVE    = 1
CX_ET_DOWN    = 2
CX_ET_UP      = 3
CX_ET_DBL     = 4
CX_ET_KEY     = 5
CX_ET_TIMER   = 6
CX_ET_MENU    = 7
CX_ET_WIDGET  = 8
CX_ET_JOY     = 9
CX_ET_COUNT   = 10           ; handler tables are ALWAYS this many vectors

; --- widget types (a record's WG_TYPE) ---
CX_WG_BUTTON  = 0
CX_WG_CHECK   = 1
CX_WG_RADIO   = 2
CX_WG_SCROLL  = 3
CX_WG_FIELD   = 4
CX_WG_LIST    = 5
CX_WG_ICON    = 6            ; a 24x24 icon tile; WG_VAL = the icon id
CX_WG_HIT     = 7            ; an invisible hit region the app draws itself
CX_WG_SIZE    = 16          ; one widget record is exactly this many bytes

; --- CX_WG_HIT shapes (WG_VAL) and triggers (WG_GRP) ---
CX_WH_RECT    = 0
CX_WH_CIRCLE  = 1           ; inscribed in the box; box <= 510 wide/tall
CX_WH_ELLIPSE = 2
CX_WH_CLICK   = %001
CX_WH_RELEASE = %010
CX_WH_HOVER   = %100

; --- built-in icon ids (cxm_icon / a CX_WG_ICON record's WG_VAL) ---
CX_ICON_UP        = 0
CX_ICON_FOLDER    = 1
CX_ICON_APP       = 2
CX_ICON_FONT      = 3
CX_ICON_ACCESSORY = 4
CX_ICON_DATA      = 5
CX_ICON_IMAGE     = 6
CX_ICON_DISK      = 7

; --- font style flags (cxm_font_style) ---
CX_BOLD       = 1
CX_UNDER      = 2

; --- theme role colours (palette indices, not RGB) ---
CX_PAPER      = 0           ; the background     (theme "paper")
CX_HI         = 1           ; the highlight fill (theme "hi")
CX_FRAME      = 3           ; borders            (theme "frame")

; --- keys (PETSCII), as EV_KEY delivers them ---
CX_K_ENTER    = $0D
CX_K_ESC      = $1B
CX_K_TAB      = $09
CX_K_BTAB     = $18         ; shift-TAB
CX_K_DEL      = $14
CX_K_UP       = $91
CX_K_DOWN     = $11
CX_K_LEFT     = $9D
CX_K_RIGHT    = $1D
CX_K_SPACE    = $20

; --- audio: PSG waveforms and panning ---
CX_WAVE_PULSE = $00
CX_WAVE_SAW   = $40
CX_WAVE_TRI   = $80
CX_WAVE_NOISE = $C0
CX_PAN_LEFT   = $40
CX_PAN_RIGHT  = $80
CX_PAN_BOTH   = $C0

; --- PCM format bits (cxm_pcm_ctrl); low nibble is volume 0-15 ---
CX_PCM_16BIT  = $20
CX_PCM_STEREO = $10

; --- joystick buttons (ACTIVE HIGH: pressed = 1) ---
CX_J_RIGHT    = $0001
CX_J_LEFT     = $0002
CX_J_DOWN     = $0004
CX_J_UP       = $0008
CX_J_START    = $0010
CX_J_SELECT   = $0020
CX_J_Y        = $0040
CX_J_B        = $0080
CX_J_R        = $1000
CX_J_L        = $2000
CX_J_X        = $4000
CX_J_A        = $8000

; --- sprites ---
CX_SPR_4BPP   = $00         ; image colour depth (cxm_sprite_image)
CX_SPR_8BPP   = $80
CX_SPR_8      = 0           ; size codes (cxm_sprite_size)
CX_SPR_16     = 1
CX_SPR_32     = 2
CX_SPR_64     = 3
CX_SPR_HIDE   = $00         ; Z-depths (cxm_sprite_z / _flags)
CX_SPR_BEHIND = $04
CX_SPR_MIDDLE = $08
CX_SPR_FRONT  = $0C
CX_SPR_HFLIP  = $01
CX_SPR_VFLIP  = $02
CX_SPR_VRAM   = $1E000      ; the 4KB VRAM region for app sprite images

; --- tiles (CX_MODE_TILE) ---
CX_TILE_IMG   = $00000      ; tile pixel data (up to 1024 tiles)
CX_CELL_HF    = $0400       ; cell attribute bits
CX_CELL_VF    = $0800

; --- immediate widget-painter metrics (match the kernel toolkit) ---
CX_FONT_H     = 8           ; the system font's glyph height
CX_BOX        = 12          ; the checkbox marker square (= WG_BOX)
CX_THUMB      = 16          ; the slider thumb width (= WG_THUMB)
CX_SLIDER_H   = 16          ; the slider's height

; --- event source mask (cxm_ev_mask) ---
CX_EVS_MOUSE  = 1
CX_EVS_KEYS   = 2
CX_EVS_SPRCOL = 4

; pack an octave (0-7) and a note (1-12) into a cxm_ym_note code
.define CX_YM(octave, note)   ((((octave) & 7) << 4) | ((note) & $0F))
; pack a tile index (0-1023) and palette (0-15) into a cell word
.define CX_CELL(idx, pal)     (((idx) & $3FF) | ((pal) << 12))

; =====================================================================
; internal: store a 16-bit value into a P-block word
; =====================================================================
; _cx_pw addr, v -- for a constant whose high byte is 0 it emits `stz`,
; exactly as hand code does, so the expansion is byte-for-byte identical.
.macro _cx_pw addr, v
    lda #<(v)
    sta addr
    .if .const(v)
        .if (>(v)) = 0
            stz addr+1
        .else
            lda #>(v)
            sta addr+1
        .endif
    .else
        lda #>(v)
        sta addr+1
    .endif
.endmacro

; =====================================================================
; system
; =====================================================================
.macro cxm_version                          ; -> A/X = ABI version
    jsr cx_version
.endmacro
.macro cxm_exit                             ; never returns: back to the shell
    jmp cx_exit
.endmacro

; =====================================================================
; screen / graphics -- the same calls in every mode (the port routes them)
; =====================================================================
.macro cxm_gfx_init                         ; = mode GUI, fresh desktop canvas
    jsr cx_gfx_init
.endmacro
.macro cxm_gfx_clear col                        ; fill the canvas with a colour
    lda #(col)
    jsr cx_gfx_clear
.endmacro
.macro cxm_gfx_mode m                           ; switch mode -> carry set if unknown
    lda #(m)
    jsr cx_gfx_mode
.endmacro
.macro cxm_gfx_info                         ; -> A=mode, P0/1=w, P2/3=h, P4=bpp, P5/6=stride
    jsr cx_gfx_info
.endmacro
.macro cxm_gfx_pset x0, y0, col
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    lda #(col)
    jsr cx_gfx_pset
.endmacro
.macro cxm_gfx_read x0, y0                       ; -> A = colour, $FF off screen
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    jsr cx_gfx_read
.endmacro
.macro cxm_gfx_hline x0, y0, len, col
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    _cx_pw X16_P4, len
    lda #(col)
    jsr cx_gfx_hline
.endmacro
.macro cxm_gfx_vline x0, y0, len, col
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    _cx_pw X16_P4, len
    lda #(col)
    jsr cx_gfx_vline
.endmacro
.macro cxm_gfx_rect x0, y0, w0, h0, col
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    _cx_pw X16_P4, w0
    _cx_pw X16_P6, h0
    lda #(col)
    jsr cx_gfx_rect
.endmacro
.macro cxm_gfx_frame x0, y0, w0, h0, col
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    _cx_pw X16_P4, w0
    _cx_pw X16_P6, h0
    lda #(col)
    jsr cx_gfx_frame
.endmacro
.macro cxm_gfx_line x0, y0, x1, y1, col
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    _cx_pw X16_P4, x1
    _cx_pw X16_P6, y1
    lda #(col)
    jsr cx_gfx_line
.endmacro
.macro cxm_gfx_pattern pat, bg, fg              ; A/X = 8x8 pattern, Y = (bg<<2)|fg
    ldy #((((bg) & 3) << 2) | ((fg) & 3))
    lda #<(pat)
    ldx #>(pat)
    jsr cx_gfx_pattern
.endmacro
.macro cxm_gfx_patrect x0, y0, w0, h0
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    _cx_pw X16_P4, w0
    _cx_pw X16_P6, h0
    jsr cx_gfx_patrect
.endmacro
.macro cxm_gfx_blit x0, y0, wbytes, h0, src, op
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    lda #(wbytes)
    sta X16_P4
    lda #(h0)
    sta X16_P5
    _cx_pw X16_P6, src
    lda #(op)
    jsr cx_gfx_blit
.endmacro
.macro cxm_gfx_blitm x0, y0, h0, cols, src
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    lda #(h0)
    sta X16_P4
    lda #(cols)
    sta X16_P5
    _cx_pw X16_P6, src
    jsr cx_gfx_blitm
.endmacro

; --- shapes (every mode) ---
.macro cxm_gfx_circle xc, yc, rad, col
    _cx_pw X16_P0, xc
    _cx_pw X16_P2, yc
    lda #(rad)
    sta X16_P4
    lda #(col)
    jsr cx_gfx_circle
.endmacro
.macro cxm_gfx_disc xc, yc, rad, col
    _cx_pw X16_P0, xc
    _cx_pw X16_P2, yc
    lda #(rad)
    sta X16_P4
    lda #(col)
    jsr cx_gfx_disc
.endmacro
.macro cxm_gfx_ellipse xc, yc, rx, ry, col
    _cx_pw X16_P0, xc
    _cx_pw X16_P2, yc
    lda #(rx)
    sta X16_P4
    lda #(ry)
    sta X16_P5
    lda #(col)
    jsr cx_gfx_ellipse
.endmacro
.macro cxm_gfx_fellipse xc, yc, rx, ry, col
    _cx_pw X16_P0, xc
    _cx_pw X16_P2, yc
    lda #(rx)
    sta X16_P4
    lda #(ry)
    sta X16_P5
    lda #(col)
    jsr cx_gfx_fellipse
.endmacro
.macro cxm_gfx_flood x0, y0, col                 ; -> carry set if the seed stack overflowed
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    lda #(col)
    jsr cx_gfx_flood
.endmacro
.macro cxm_gfx_shape kind, xc, yc, rad, p5, p6, col                ; one dispatched slot; kind 0 polygon, 1 fpolygon, 2 arc, 3 pie. polygon: p5 = sides, p6 = rotation; arc/pie: p5 = start, p6 = end
    ldx #(kind)
    _cx_pw X16_P0, xc
    _cx_pw X16_P2, yc
    lda #(rad)
    sta X16_P4
    lda #(p5)
    sta X16_P5
    lda #(p6)
    sta X16_P6
    lda #(col)
    jsr cx_gfx_shape
.endmacro
.macro cxm_icon id, x0, y0                   ; a built-in 24x24 icon (modes 0/1)
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    lda #(id)
    jsr cx_icon
.endmacro

; --- palette ---
.macro cxm_pal_set index, rgb               ; one entry; rgb is 12-bit $0RGB
    ldy #>(rgb)
    ldx #(index)
    lda #<(rgb)
    jsr cx_pal_set
.endmacro
.macro cxm_pal_load src, first, count        ; bulk-load entries from RAM
    _cx_pw X16_P0, src
    ldx #(count)
    lda #(first)
    jsr cx_pal_load
.endmacro

; =====================================================================
; text
; =====================================================================
.macro cxm_font_set cxf                          ; adopt a .CXF -> carry set if bad
    lda #<(cxf)
    ldx #>(cxf)
    jsr cx_font_set
.endmacro
.macro cxm_font_style flags                       ; CX_BOLD | CX_UNDER
    lda #(flags)
    jsr cx_font_style
.endmacro
.macro cxm_font_measure str                       ; -> P0/1 = pixel width
    lda #<(str)
    ldx #>(str)
    jsr cx_font_measure
.endmacro
.macro cxm_say str, x0, y0                    ; draw at (x0,y0) -> P0/1 = pen x
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    lda #<(str)
    ldx #>(str)
    jsr cx_font_draw
.endmacro
.macro cxm_font_draw str, x0, y0              ; the 1:1 slot name; = cxm_say
    cxm_say str, x0, y0
.endmacro
.macro cxm_ink col                           ; text ink for the CURRENT mode
    lda #(col)
    jsr cx_ink
.endmacro

; =====================================================================
; tiles (CX_MODE_TILE)
; =====================================================================
.macro cxm_tile_setup layer                  ; -> carry set outside mode 2
    lda #(layer)
    jsr cx_tile_setup
.endmacro
.macro cxm_tile_scroll layer, hscroll, vscroll
    _cx_pw X16_P0, hscroll
    _cx_pw X16_P2, vscroll
    lda #(layer)
    jsr cx_tile_scroll
.endmacro
.macro cxm_tile_cell layer, column, row, cell
    _cx_pw X16_P0, cell
    ldx #(column)
    ldy #(row)
    lda #(layer)
    jsr cx_tile_cell
.endmacro
.macro cxm_tile_fill layer, cell
    _cx_pw X16_P0, cell
    lda #(layer)
    jsr cx_tile_fill
.endmacro

; =====================================================================
; events -- a handler table is ALWAYS CX_ET_COUNT vectors
; =====================================================================
.macro cxm_ev_init                           ; clear the queue, hook the raster
    jsr cx_ev_init
.endmacro
.macro cxm_ev_handlers tbl                       ; A/X = CX_ET_COUNT vectors
    lda #<(tbl)
    ldx #>(tbl)
    jsr cx_ev_handlers
.endmacro
.macro cxm_ev_mainloop                          ; never returns
    jmp cx_ev_mainloop
.endmacro
.macro cxm_ev_dispatch                          ; dispatch one event and return
    jsr cx_ev_dispatch
.endmacro
.macro cxm_ev_get                            ; -> P0..P7 = a record; carry if none
    jsr cx_ev_get
.endmacro
.macro cxm_ev_next                           ; like ev_get, but routes mouse to the toolkit
    jsr cx_ev_next
.endmacro
.macro cxm_ev_post                           ; P0..P7 = a record (fill it first)
    jsr cx_ev_post
.endmacro
.macro cxm_ev_count                          ; -> A = records waiting
    jsr cx_ev_count
.endmacro
.macro cxm_ev_timer frames                       ; A = frames between EV_TIMERs (0 = off)
    lda #(frames)
    jsr cx_ev_timer
.endmacro
.macro cxm_ev_frames                            ; -> A = the frame counter
    jsr cx_ev_frames
.endmacro
.macro cxm_ev_mask sources                     ; which sources the frame tick samples
    lda #(sources)
    jsr cx_ev_mask
.endmacro
.macro cxm_ev_raster hdlr                      ; A/X = a per-frame raster handler, or 0 to remove
    lda #<(hdlr)
    ldx #>(hdlr)
    jsr cx_ev_raster
.endmacro
.macro cxm_ev_stop                           ; return the raster line to the game's handler
    jsr cx_ev_stop
.endmacro

; =====================================================================
; dirty rectangles
; =====================================================================
.macro cxm_dirty_reset
    jsr cx_dirty_reset
.endmacro
.macro cxm_dirty_add x0, y0, w0, h0
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    _cx_pw X16_P4, w0
    _cx_pw X16_P6, h0
    jsr cx_dirty_add
.endmacro
.macro cxm_dirty_count                        ; -> A = rects
    jsr cx_dirty_count
.endmacro
.macro cxm_dirty_get idx                       ; A=index -> P0/1=x0,P2/3=y0,P4/5=x1,P6/7=y1
    lda #(idx)
    jsr cx_dirty_get
.endmacro

; =====================================================================
; pointer, menus, widgets
; =====================================================================
.macro cxm_mouse_show ptr                      ; A = pointer number (1 = arrow), $FF = show as-is
    lda #(ptr)
    jsr cx_mouse_show
.endmacro
.macro cxm_mouse_hide
    jsr cx_mouse_hide
.endmacro
.macro cxm_menu_set bar                         ; A/X = a menu bar -> carry = region stack full
    lda #<(bar)
    ldx #>(bar)
    jsr cx_menu_set
.endmacro
.macro cxm_menu_off
    jsr cx_menu_off
.endmacro
.macro cxm_menu_key key                         ; drive the menu bar -> carry = it was a menu key
    lda #(key)
    jsr cx_menu_key
.endmacro
.macro cxm_menu_active                          ; -> A = 1 if a menu is open (mouse or kbd), Z set if none
    jsr cx_menu_active
.endmacro
.macro cxm_wg_set lst                            ; A/X = a widget list; draws + routes it
    lda #<(lst)
    ldx #>(lst)
    jsr cx_wg_set
.endmacro
.macro cxm_wg_draw                             ; redraw the current widget list
    jsr cx_wg_draw
.endmacro
.macro cxm_wg_key key                           ; drive widget focus -> carry = it was a widget key
    lda #(key)
    jsr cx_wg_key
.endmacro

; =====================================================================
; themes and dialogs
; =====================================================================
.macro cxm_theme_set rec                            ; A/X = a 12-byte theme record
    lda #<(rec)
    ldx #>(rec)
    jsr cx_theme_set
.endmacro
.macro cxm_dlg_alert desc                           ; A/X = a dialog descriptor -> A = the button
    lda #<(desc)
    ldx #>(desc)
    jsr cx_dlg_alert
.endmacro
.macro cxm_dlg_prompt msg, buf, cap                 ; modal editor -> A = length, carry = cancelled
    _cx_pw X16_P0, buf
    lda #(cap)
    sta X16_P2
    lda #<(msg)
    ldx #>(msg)
    jsr cx_dlg_prompt
.endmacro
.macro cxm_panel desc                           ; A/X = a panel descriptor -> A = the button
    lda #<(desc)
    ldx #>(desc)
    jsr cx_panel
.endmacro

; =====================================================================
; audio -- the VERA PSG (16 voices) and the YM2151 FM chip
; =====================================================================
.macro cxm_psg_init
    jsr cx_psg_init
.endmacro
.macro cxm_psg_freq voice, freq                 ; X = voice, P0/1 = frequency word
    _cx_pw X16_P0, freq
    ldx #(voice)
    jsr cx_psg_freq
.endmacro
.macro cxm_psg_vol voice, vol, pan              ; X = voice, A = vol (0-63), Y = pan
    ldy #(pan)
    ldx #(voice)
    lda #(vol)
    jsr cx_psg_vol
.endmacro
.macro cxm_psg_wave voice, wave, pw             ; X = voice, A = waveform, Y = pulse width
    ldy #(pw)
    ldx #(voice)
    lda #(wave)
    jsr cx_psg_wave
.endmacro
.macro cxm_psg_off voice                         ; X = voice; silence, keep panning
    ldx #(voice)
    jsr cx_psg_off
.endmacro
.macro cxm_ym_init
    jsr cx_ym_init
.endmacro
.macro cxm_ym_note chan, code                    ; A = channel, X = CX_YM(octave, note); 0 releases
    ldx #(code)
    lda #(chan)
    jsr cx_ym_note
.endmacro
.macro cxm_ym_off chan
    lda #(chan)
    jsr cx_ym_off
.endmacro
.macro cxm_ym_vol chan, atten                    ; A = channel, X = attenuation
    ldx #(atten)
    lda #(chan)
    jsr cx_ym_vol
.endmacro
.macro cxm_ym_patch chan, idx                    ; A = channel, X = ROM patch index (0-162)
    ldx #(idx)
    lda #(chan)
    jsr cx_ym_patch
.endmacro

; --- PCM (the 4KB FIFO, refilled off the event IRQ) ---
.macro cxm_pcm_ctrl ctrl                          ; volume 0-15 | CX_PCM_16BIT | CX_PCM_STEREO
    lda #(ctrl)
    jsr cx_pcm_ctrl
.endmacro
.macro cxm_pcm_play src, len, rate                ; P0/1 = source, P2/3 = bytes, A = rate (1-128)
    _cx_pw X16_P0, src
    _cx_pw X16_P2, len
    lda #(rate)
    jsr cx_pcm_play
.endmacro
.macro cxm_pcm_stop
    jsr cx_pcm_stop
.endmacro
.macro cxm_pcm_active                            ; -> A = 1 while a sample still plays
    jsr cx_pcm_active
.endmacro

; =====================================================================
; joysticks (pad 0 = keyboard joystick, 1-4 = SNES pads)
; =====================================================================
.macro cxm_joy_get pad                                ; A = pad -> A/X = buttons, carry = absent
    lda #(pad)
    jsr cx_joy_get
.endmacro
.macro cxm_joy_enable mask                         ; scan pads in mask each frame, post EV_JOY
    lda #(mask)
    jsr cx_joy_enable
.endmacro

; =====================================================================
; sprites (VERA hardware sprites; 0 is the mouse, drive 1-127)
; =====================================================================
.macro cxm_sprite_image spr, addr, mode           ; point sprite at its VRAM image
    lda #<(addr)
    sta X16_P0
    lda #>(addr)
    sta X16_P1
    lda #^(addr)
    sta X16_P2
    ldx #(spr)
    lda #(mode)
    jsr cx_sprite_image
.endmacro
.macro cxm_sprite_pos spr, x0, y0
    _cx_pw X16_P0, x0
    _cx_pw X16_P2, y0
    ldx #(spr)
    jsr cx_sprite_pos
.endmacro
.macro cxm_sprite_size spr, wcode, hcode, pal      ; size codes CX_SPR_8/16/32/64
    lda #(pal)
    sta X16_P0
    ldx #(spr)
    ldy #(hcode)
    lda #(wcode)
    jsr cx_sprite_size
.endmacro
.macro cxm_sprite_flags spr, flags                 ; full write: collision<<4 | Z | flips
    ldx #(spr)
    lda #(flags)
    jsr cx_sprite_flags
.endmacro
.macro cxm_sprite_z spr, z                         ; Z-depth only (CX_SPR_HIDE/BEHIND/MIDDLE/FRONT)
    ldx #(spr)
    lda #(z)
    jsr cx_sprite_z
.endmacro
.macro cxm_spr_collide                            ; -> A = collision groups since last call
    jsr cx_spr_collide
.endmacro

; =====================================================================
; loader and desk accessories
; =====================================================================
.macro cxm_app_load name, len                        ; load+run a .CXA -> returns only on failure (A=reason)
    ldy #(len)
    lda #<(name)
    ldx #>(name)
    jsr cx_app_load
.endmacro
.macro cxm_da_open name, len                        ; open a .CXD over the running app -> carry = fail
    ldy #(len)
    lda #<(name)
    ldx #>(name)
    jsr cx_da_open
.endmacro
.macro cxm_da_close
    jsr cx_da_close
.endmacro
.macro cxm_file_load name, len, dst, cap            ; -> carry set/A=reason, else P4/5 = bytes read
    _cx_pw X16_P0, dst
    _cx_pw X16_P2, cap
    ldy #(len)
    lda #<(name)
    ldx #>(name)
    jsr cx_file_load
.endmacro
.macro cxm_vload name, len, vaddr, vbank, raw       ; a file straight into VRAM
    _cx_pw X16_P0, vaddr
    lda #(vbank)
    sta X16_P2
    lda #(raw)
    sta X16_P3
    ldy #(len)
    lda #<(name)
    ldx #>(name)
    jsr cx_vload
.endmacro
.macro cxm_bload name, len, bank, addr, raw         ; a file into banked RAM (bank 20+)
    lda #(bank)
    sta X16_P0
    lda #<(addr)
    sta X16_P1
    lda #>(addr)
    sta X16_P2
    lda #(raw)
    sta X16_P3
    ldy #(len)
    lda #<(name)
    ldx #>(name)
    jsr cx_bload
.endmacro

; =====================================================================
; directory and DOS
; =====================================================================
.macro cxm_dir_open pat, len                         ; open the directory channel -> carry = DOS error
    ldy #(len)
    lda #<(pat)
    ldx #>(pat)
    jsr cx_dir_open
.endmacro
.macro cxm_dir_next buf                               ; P0/1 = a >=17-byte buffer -> A=0 file/1 dir, carry=done
    _cx_pw X16_P0, buf
    jsr cx_dir_next
.endmacro
.macro cxm_dir_close
    jsr cx_dir_close
.endmacro
.macro cxm_dos_cmd cmd, len                               ; A/X = a CMDR-DOS command -> A = status (>=20 = error)
    ldy #(len)
    lda #<(cmd)
    ldx #>(cmd)
    jsr cx_dos_cmd
.endmacro
.macro cxm_dos_msg buf                                ; P0/1 = a >=64-byte buffer -> A = reply length
    _cx_pw X16_P0, buf
    jsr cx_dos_msg
.endmacro

; =====================================================================
; clipboard
; =====================================================================
.macro cxm_clip_put type, src, len                    ; A = type, P0/1 = src, P2/3 = len -> carry = too big
    _cx_pw X16_P0, src
    _cx_pw X16_P2, len
    lda #(type)
    jsr cx_clip_put
.endmacro
.macro cxm_clip_get dst, cap                          ; P0/1 = dst, P2/3 = cap -> A = type, P2/3 = length copied
    _cx_pw X16_P0, dst
    _cx_pw X16_P2, cap
    jsr cx_clip_get
.endmacro
.macro cxm_clip_type                                 ; -> A = the type waiting (0 = empty), P2/3 = length
    jsr cx_clip_type
.endmacro

; =====================================================================
; descriptor builders -- the byte layouts of docs/formats.md, named so a
; miscounted record is impossible
; =====================================================================

; --- one 16-byte widget record, per type ---
.macro cxm_wg_button x0, y0, w0, h0, label
    .byte CX_WG_BUTTON, 0
    .word (x0), (y0), (w0)
    .byte (h0), 0, 0
    .addr (label)
    .byte 0, 0, 0
.endmacro
.macro cxm_wg_check x0, y0, w0, h0, on, label       ; on = 1 checked
    .byte CX_WG_CHECK, 0
    .word (x0), (y0), (w0)
    .byte (h0), (on), 0
    .addr (label)
    .byte 0, 0, 0
.endmacro
.macro cxm_wg_radio x0, y0, w0, h0, on, group, label
    .byte CX_WG_RADIO, 0
    .word (x0), (y0), (w0)
    .byte (h0), (on), (group)
    .addr (label)
    .byte 0, 0, 0
.endmacro
.macro cxm_wg_scroll x0, y0, w0, h0, val, max        ; value 0..max inclusive
    .byte CX_WG_SCROLL, 0
    .word (x0), (y0), (w0)
    .byte (h0), (val), (max)
    .addr 0
    .byte 0, 0, 0
.endmacro
.macro cxm_wg_field x0, y0, w0, h0, cap, buf         ; buf = a NUL-terminated edit buffer
    .byte CX_WG_FIELD, 0
    .word (x0), (y0), (w0)
    .byte (h0), 0, (cap)
    .addr (buf)
    .byte 0, 0, 0
.endmacro
.macro cxm_wg_list x0, y0, w0, h0, count, ptrs        ; ptrs = a list of string pointers
    .byte CX_WG_LIST, 0
    .word (x0), (y0), (w0)
    .byte (h0), 0, (count)
    .addr (ptrs)
    .byte 0, 0, 0
.endmacro
.macro cxm_wg_icon x0, y0, w0, h0, id, label          ; a 24x24 icon; id = CX_ICON_*
    .byte CX_WG_ICON, 0
    .word (x0), (y0), (w0)
    .byte (h0), (id), 0
    .addr (label)
    .byte 0, 0, 0
.endmacro
.macro cxm_wg_hit x0, y0, w0, h0, shape, trig         ; an invisible hit region the app draws
    .byte CX_WG_HIT, 0
    .word (x0), (y0), (w0)
    .byte (h0), (shape), (trig)
    .addr 0
    .byte 0, 0, 0
.endmacro

; --- a widget list's leading count, COMPUTED from the record span ---
; put `first:` at the list head and `last:` after the records:
;     widgets:  cxm_wcount widgets, widgets_end
;               cxm_wg_button ...
;     widgets_end:
.macro cxm_wcount first, last
    .byte (last - first - 1) / CX_WG_SIZE
.endmacro

; --- a menu bar: a count, then (title, items) per menu ---
.macro cxm_menu_bar nmenus
    .byte (nmenus)
.endmacro
.macro cxm_menu title, items
    .addr (title), (items)
.endmacro
; --- one menu's drop-down: a count, then a label per item ---
.macro cxm_items nitems
    .byte (nitems)
.endmacro
.macro cxm_item label
    .addr (label)
.endmacro

; --- an alert descriptor: a button count, the message, then buttons ---
.macro cxm_dialog nbuttons, msg
    .byte (nbuttons)
    .addr (msg)
.endmacro
; the button labels follow with cxm_item

; --- a modal panel header: box, title, widget list, then a button count ---
.macro cxm_panel_hdr x0, y0, w0, h0, title, wlist, nbuttons
    .word (x0), (y0), (w0)
    .byte (h0)
    .addr (title)
    .addr (wlist)
    .byte (nbuttons)
.endmacro
; the button labels follow with cxm_item

; --- a 12-byte theme record: four palette colours ($0RGB each), then the
; paper / highlight / frame role indices (and a reserved 0). Pass the built
; record to cxm_theme_set to install it. ---
.macro cxm_theme_rec c0, c1, c2, c3, paper, hi, frame
    .byte <(c0), >(c0)
    .byte <(c1), >(c1)
    .byte <(c2), >(c2)
    .byte <(c3), >(c3)
    .byte (paper), (hi), (frame), 0
.endmacro

.endif ; CXGEOS_ASMSDK
