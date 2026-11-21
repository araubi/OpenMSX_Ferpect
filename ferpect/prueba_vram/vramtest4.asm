; Prueba VRAM 4 para MSX1: ensena el primer fallo de una pasada.
; SCREEN 2, imagen encendida, DI. Para cada separacion (24, 25, WME, 26, 27 T)
; y dos fases (0 y 7) llena la VRAM con EEh, escribe 1024 bytes 0,1,2,..
; y los relee con la BIOS. Muestra la posicion del primer byte distinto,
; cuantos bytes no coinciden y los 6 bytes leidos desde dos antes del fallo.
; araubi, 2026. Licencia MIT.

CHGMOD  equ 005Fh
SETWRT  equ 0053h
FILVRM  equ 0056h
LDIRMV  equ 0059h
CHPUT   equ 00A2h
FORCLR  equ 0F3E9h
LINL32  equ 0F3AFh

CODE    equ 0C000h
BUF     equ 0E000h
RESUL   equ 0DA00h          ; 10 x 12 bytes: pos(2) cuenta(2) 6 bytes, fase
NPRUEBA equ 5
LONG_PLANT equ 52

        org 4000h
        db "AB"
        dw inicio
        ds 12,0

inicio:
        ld sp,0F380h
        ld a,2
        call CHGMOD
        ld ix,RESUL
        ld iy,plantillas
        ld b,NPRUEBA
bp1:    push bc
        call genera
        ld a,0
        call pasada
        ld a,7
        call pasada
        ld de,LONG_PLANT
        add iy,de
        pop bc
        djnz bp1

        ei
        ld a,32
        ld (LINL32),a
        ld a,15
        ld (FORCLR),a
        ld a,1
        call CHGMOD
        ld hl,txt_titulo
        call imprime
        ld ix,RESUL
        ld iy,plantillas
        ld b,NPRUEBA
r1:     push bc
        call linea
        call linea
        ld de,LONG_PLANT
        add iy,de
        pop bc
        djnz r1
        ld hl,txt_pie
        call imprime
fin:    jr fin

linea:  ld a,(iy+0)
        call CHPUT
        ld a,(iy+1)
        call CHPUT
        ld a,(iy+2)
        call CHPUT
        ld a,(ix+10)
        add a,'0'
        call CHPUT
        ld a,' '
        call CHPUT
        ld a,(ix+1)
        call hex2
        ld a,(ix+0)
        call hex2
        ld a,' '
        call CHPUT
        ld a,(ix+3)
        call hex2
        ld a,(ix+2)
        call hex2
        ld a,' '
        call CHPUT
        ld b,6
        push ix
        pop hl
        inc hl
        inc hl
        inc hl
        inc hl
l1:     ld a,(hl)
        push hl
        push bc
        call hex2
        pop bc
        pop hl
        inc hl
        djnz l1
        ld a,13
        call CHPUT
        ld a,10
        call CHPUT
        ld de,12
        add ix,de
        ret

hex2:   push af
        rrca
        rrca
        rrca
        rrca
        call hex1
        pop af
hex1:   and 15
        add a,'0'
        cp '9'+1
        jr c,hx1
        add a,7
hx1:    jp CHPUT

; una pasada con fase A
pasada: ld (ix+10),a
        ld (fase),a
        ld hl,0
        ld bc,1280
        ld a,0EEh
        call FILVRM
        ei
        halt
        di
        ld a,(fase)
        ld b,a
        ld de,950
        or a
        jr z,e2
e1:     ld hl,34
        add hl,de
        ex de,hl
        djnz e1
e2:     dec de
        ld a,d
        or e
        jr nz,e2
        ld hl,0
        call SETWRT
        di
        ld c,98h
        xor a
        ld de,0
        call CODE
        ld hl,0
        ld de,BUF
        ld bc,1024
        call LDIRMV
        di
        ; buscar el primer fallo y contar
        ld hl,BUF
        ld bc,0                 ; indice
        ld de,0                 ; fallos
        ld (ix+0),0FFh
        ld (ix+1),0FFh
bu1:    ld a,(hl)
        cp c
        jr z,bu2
        inc de
        ld a,(ix+1)
        cp 0FFh
        jr nz,bu2
        ld (ix+0),c
        ld (ix+1),b
bu2:    inc hl
        inc bc
        ld a,b
        cp 4
        jr c,bu1
        ld (ix+2),e
        ld (ix+3),d
        ; 6 bytes desde el fallo - 2
        ld l,(ix+0)
        ld h,(ix+1)
        ld a,h
        cp 0FFh
        jr nz,bu3
        ld hl,2
bu3:    dec hl
        dec hl
        ld a,h
        cp 4
        jr c,bu4
        ld hl,0
bu4:    ld de,BUF
        add hl,de
        push ix
        pop de
        inc de
        inc de
        inc de
        inc de
        ld bc,6
        ldir
        ld de,12
        add ix,de
        ret

genera:
        ld de,CODE
        ld c,(iy+3)
        ld b,(iy+4)             ; BC = repeticiones
gen1:   push bc
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ld c,(hl)               ; longitud
        ld b,0
        inc hl
        ldir
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,gen1
        ld a,0C9h
        ld (de),a
        ret

imprime:
        ld a,(hl)
        or a
        ret z
        call CHPUT
        inc hl
        jr imprime

fase    equ 0DF00h

txt_titulo:
        db "PRUEBA VRAM 4: PRIMER FALLO",13,10
        db "N+FASE POS  FALLOS BYTES -2..+3",13,10
        db "HEX. EE = SIN ESCRIBIR",13,10,13,10,0
txt_pie:
        db 13,10,"HAZ UNA FOTO A ESTA PANTALLA",0

; etiqueta (3 letras), repeticiones (dw), longitud, bytes (hasta 46)
plantillas:
        db "24T"
        dw 1024
        db 4, 0D3h,98h,3Ch,13h
        ds 42,0
        db "25T"
        dw 1024
        db 5, 0D3h,98h,3Ch,06h,00h
        ds 41,0
        db "WME"                ; como War in Middle Earth: 8 a 25 T y 46 T
        dw 128
        db 45
        db 0D3h,98h,3Ch,06h,00h, 0D3h,98h,3Ch,06h,00h, 0D3h,98h,3Ch,06h,00h
        db 0D3h,98h,3Ch,06h,00h, 0D3h,98h,3Ch,06h,00h, 0D3h,98h,3Ch,06h,00h
        db 0D3h,98h,3Ch,06h,00h
        db 0D3h,98h,3Ch, 21h,00h,00h, 21h,00h,00h, 13h
        ds 1,0
        db "26T"
        dw 1024
        db 5, 0EDh,79h,3Ch,06h,00h      ; OUT (C),A / INC A / LD B,0
        ds 41,0
        db "27T"
        dw 1024
        db 5, 0D3h,98h,3Ch,00h,00h
        ds 41,0

        ds 8000h-$,0FFh
