;ACME
; =====================================================================
; x16lib :: system/clock.asm -- KERNAL clock and RTC wrappers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The 24-bit timer is the classic KERNAL 60 Hz jiffy counter:
;       jsr clock_get_timer       ; A/X/Y = low/mid/high timer bytes
;       lda #lo : ldx #mid : ldy #hi
;       jsr clock_set_timer
;
; Date/time values use the X16 KERNAL r0..r3 contract:
;       r0L = year since 1900
;       r0H = month
;       r1L = day
;       r1H = hours
;       r2L = minutes
;       r2H = seconds
;       r3L = jiffies
;       r3H = weekday
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; clock_update -- update the KERNAL timer/date-time state
; ---------------------------------------------------------------------
clock_update
    jmp UDTIM

; ---------------------------------------------------------------------
; clock_get_timer -- read the 24-bit 60 Hz timer
;   out: A = bits 0-7, X = bits 8-15, Y = bits 16-23
; ---------------------------------------------------------------------
clock_get_timer
    jmp RDTIM

; ---------------------------------------------------------------------
; clock_set_timer -- set the 24-bit 60 Hz timer
;   in: A = bits 0-7, X = bits 8-15, Y = bits 16-23
; ---------------------------------------------------------------------
clock_set_timer
    jmp SETTIM

; ---------------------------------------------------------------------
; clock_get_date_time -- read the RTC date/time into r0..r3
;   out: r0L year since 1900, r0H month, r1L day, r1H hours,
;        r2L minutes, r2H seconds, r3L jiffies, r3H weekday
; ---------------------------------------------------------------------
clock_get_date_time
    jmp CLOCK_GET_DATE_TIME

; ---------------------------------------------------------------------
; clock_set_date_time -- write the RTC date/time from r0..r3
;   in:  r0L year since 1900, r0H month, r1L day, r1H hours,
;        r2L minutes, r2H seconds, r3L jiffies, r3H weekday
; ---------------------------------------------------------------------
clock_set_date_time
    jmp CLOCK_SET_DATE_TIME

; (end zone)
