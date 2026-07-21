; =====================================================================
; CXGEOS :: kernel/resident/impl.inc -- ABI name -> kernel routine
; =====================================================================
; abi/cxgeos.abi names what an app may call. This names the code behind
; each one. They are kept apart on purpose: the left column is a promise
; to every app ever built, the right is the kernel's business. A routine
; can be renamed, rewritten or moved to another module by editing this
; file alone, and no app notices.
;
; Read by abi/gen_bindings.py, which builds the jump table from it and
; refuses to run if the two columns disagree -- an ABI slot with no
; routine, or a routine claiming a slot that does not exist.
;
;   <abi name> = <kernel label>
; =====================================================================

cx_version      = cx_do_version
cx_exit         = cx_do_exit

cx_gfx_init     = cx_do_gfx_init ; forces mode 0 (the graphics PORT --
cx_gfx_clear    = cxov_clear    ; kernel/video/ovl.inc): the slots target
cx_gfx_pset     = cxov_pset     ; the overlay's fixed entry vector; the
cx_gfx_read     = cxov_read     ; engine behind it is whichever image
cx_gfx_hline    = cxov_hline    ; cx_ov_boot or cx_gfx_mode copied in
cx_gfx_vline    = cxov_vline
cx_gfx_rect     = cxov_rect
cx_gfx_frame    = cxov_frame
cx_gfx_line     = cxov_line
cx_gfx_pattern  = cxov_pattern
cx_gfx_patrect  = cxov_patrect
cx_gfx_blit     = cxov_blit
cx_gfx_blitm    = cxov_blitm

; the font and toolkit slots below are GUI-only: they go through the
; gui_gate wrappers (kernel/video/engine0.asm), which refuse with carry
; outside graphics mode 0 rather than draw into another mode's picture.
cx_font_set     = font_set      ; ungated: fonts apply in mode 1 too, and
                                ; font_set only sets state + (mode 0) the
                                ; cache -- it never draws, so it is mode-safe
cx_font_style   = cx_g_font_style
cx_font_measure = cxov_measure  ; mode-aware through the port, like cx_say
cx_font_draw    = cxov_text     ; cx_say through the port's 14th entry

cx_ev_handlers  = ev_handlers
cx_ev_mainloop  = ev_mainloop
cx_ev_dispatch  = ev_dispatch
cx_ev_get       = ev_get
cx_ev_post      = ev_post
cx_ev_count     = ev_count
cx_ev_timer     = ev_timer
cx_ev_frames    = ev_frames

cx_dirty_reset  = cx_do_dirty_reset
cx_dirty_add    = cx_do_dirty_add
cx_dirty_count  = cx_do_dirty_count
cx_dirty_get    = cx_do_dirty_get

cx_app_load     = cxl_load
cx_ev_init      = ev_init
cx_menu_set     = cx_g_menu_set
cx_menu_off     = cx_g_menu_off
cx_mouse_show   = cx_do_mouse_show
cx_mouse_hide   = cx_do_mouse_hide
cx_theme_set    = cx_g_theme_set
cx_dlg_alert    = cx_g_dlg_alert
cx_wg_set       = cx_g_wg_set
cx_wg_draw      = cx_g_wg_draw
cx_menu_key     = cx_g_menu_key
cx_wg_key       = cx_g_wg_key
cx_dir_open     = cx_do_dir_open
cx_dir_next     = cx_do_dir_next
cx_dir_close    = cx_do_dir_close
cx_dos_cmd      = cx_do_dos_cmd
cx_dos_msg      = cx_do_dos_msg
cx_dlg_prompt   = cx_g_dlg_prompt
cx_clip_put     = cx_do_clip_put
cx_clip_get     = cx_do_clip_get
cx_clip_type    = cx_do_clip_type
cx_da_open      = cx_g_da_open
cx_da_close     = cx_g_da_close
cx_ev_next      = ev_next

cx_psg_init     = cx_do_psg_init
cx_psg_freq     = cx_do_psg_freq
cx_psg_vol      = cx_do_psg_vol
cx_psg_wave     = cx_do_psg_wave
cx_psg_off      = cx_do_psg_off
cx_ym_init      = cx_do_ym_init
cx_ym_note      = cx_do_ym_note
cx_ym_off       = cx_do_ym_off
cx_ym_vol       = cx_do_ym_vol
cx_ym_patch     = cx_do_ym_patch
cx_sprite_image = cx_do_sprite_image
cx_sprite_pos   = cx_do_sprite_pos
cx_sprite_size  = cx_do_sprite_size
cx_sprite_flags = cx_do_sprite_flags
cx_sprite_z     = cx_do_sprite_z
cx_pcm_ctrl     = cx_do_pcm_ctrl
cx_pcm_play     = cx_do_pcm_play
cx_pcm_stop     = cx_do_pcm_stop
cx_pcm_active   = cx_do_pcm_active
cx_joy_get      = cx_do_joy_get
cx_joy_enable   = ev_joy_enable
cx_gfx_mode     = cx_do_gfx_mode
cx_gfx_info     = cx_do_gfx_info
cx_gfx_circle   = cx_do_gfx_circle
cx_gfx_disc     = cx_do_gfx_disc
cx_gfx_flood    = cx_do_gfx_flood
cx_tile_setup   = cx_do_tile_setup
cx_tile_scroll  = cx_do_tile_scroll
cx_tile_cell    = cx_do_tile_cell
cx_tile_fill    = cx_do_tile_fill
cx_gfx_ellipse  = cx_do_gfx_ellipse
cx_gfx_fellipse = cx_do_gfx_fellipse
cx_ev_mask      = ev_set_mask
cx_file_load    = cx_do_file_load
cx_ink          = cx_do_ink
cx_vload        = cx_do_vload
cx_bload        = cx_do_bload
cx_panel        = cx_g_panel
cx_ev_raster    = ev_raster
cx_ev_stop      = ev_suspend
cx_spr_collide  = cx_do_spr_collide
cx_icon         = cx_do_icon
cx_pal_set      = cx_do_pal_set
cx_pal_load     = cx_do_pal_load
cx_menu_active  = cx_do_menu_active
cx_gfx_shape    = cx_do_gfx_shape
cx_tile_text    = cx_do_tile_text
cx_vram_stream  = cx_do_vram_stream
cx_tile_dbuf    = cx_do_tile_dbuf
cx_tile_flip    = cx_do_tile_flip
