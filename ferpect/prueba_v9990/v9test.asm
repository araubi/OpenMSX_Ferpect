; Prueba de WAIT del V9990 (GFX9000) en MSX turbo R.
; Mide con el temporizador del S1990 (E6h/E7h, 3,911 us por cuenta) cuanto
; tardan 2048 accesos a los puertos del V9990 con Z80, R800 modo ROM y
; R800 modo DRAM. Si el V9990 hace esperar al ordenador (WAIT), los
; accesos tardan mas que al puerto 00h (que nadie usa). Codigo en RAM.
; araubi, 2026. Licencia MIT.

CHGMOD  equ 005Fh
CHPUT   equ 00A2h
CHGCPU  equ 0180h
LINL32  equ 0F3AFh
MSXVER  equ 002Dh

V9VRAM  equ 60h
V9PAL   equ 61h
V9DATO  equ 63h
V9SEL   equ 64h

CODE    equ 0C000h
BUF     equ 0D000h          ; 256 bytes
RESUL   equ 0E400h
NPRUEBA equ 8

        org 4000h
        db "AB"
        dw inicio
        ds 12,0

inicio:
        ld sp,0F380h
        ld a,32
        ld (LINL32),a
        ld a,1
        call CHGMOD
        ld a,(MSXVER)
        cp 3
        jr nc,es_tr
        ld hl,txt_no_tr
        jp fin_texto
es_tr:
        ; deteccion del V9990: R#15 se lee y se escribe
        ld a,15
        out (V9SEL),a
        ld a,2Ah
        out (V9DATO),a
        ld a,4Fh
        out (V9SEL),a
        in a,(V9DATO)
        cp 2Ah
        jr z,hay_v9
        ld hl,txt_no_v9
        jp fin_texto
hay_v9:
        ld hl,BUF
        xor a
llena:  ld (hl),a
        inc a
        inc l
        jr nz,llena
        di
        ld ix,RESUL
        ld a,80h
        call mide_modo
        ld a,81h
        call mide_modo
        ld a,82h
        call mide_modo
        ld a,80h
        call CHGCPU
        ; V9990: pantalla apagada
        ld b,8
        ld a,42h
        call v9reg
        ei

        ld hl,txt_titulo
        call imprime
        ld iy,txt_pruebas
        ld b,NPRUEBA
        ld de,0
res1:   push bc
        push de
        push iy
        pop hl
        call imprime
        inc hl
        push hl
        pop iy
        pop de
        push de
        ld b,3
        ld hl,RESUL
        add hl,de
res2:   push bc
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call dec6
        pop hl
        ld de,NPRUEBA*2
        add hl,de
        pop bc
        djnz res2
        call nl
        pop de
        inc de
        inc de
        pop bc
        djnz res1
        ld hl,txt_pie
fin_texto:
        call imprime
        jr $

; escribe A en el registro B del V9990
v9reg:  push af
        ld a,b
        out (V9SEL),a
        pop af
        out (V9DATO),a
        ret

; direccion de escritura de VRAM = 40000h
dir_esc:
        xor a
        out (V9SEL),a
        out (V9DATO),a
        out (V9DATO),a
        ld a,04h
        out (V9DATO),a
        ret
; direccion de lectura de VRAM = 40000h
dir_lec:
        ld a,3
        out (V9SEL),a
        xor a
        out (V9DATO),a
        out (V9DATO),a
        ld a,04h
        out (V9DATO),a
        ret
modo_p1_off:
        ld b,6
        ld a,05h
        call v9reg
        ld b,13
        ld a,04h
        call v9reg
        ld b,8
        ld a,42h
        jp v9reg
modo_p1_on:
        call modo_p1_off
        ld b,8
        ld a,82h
        jp v9reg
modo_b1_on:
        ld b,6
        ld a,86h                ; B1: 256 px, 8 bpp
        call v9reg
        ld b,13
        xor a
        call v9reg
        ld b,8
        ld a,82h
        jp v9reg

; ---- las pruebas en el modo de CPU de A
mide_modo:
        call CHGCPU
        di
        ld iy,tabla
        ld b,NPRUEBA
mm1:    push bc
        ; preparar (rutina de IY+0) y copiar la prueba (IY+2) a RAM
        ld l,(iy+0)
        ld h,(iy+1)
        call jphl
        ld l,(iy+2)
        ld h,(iy+3)
        ld de,CODE
        ld bc,32
        ldir
        push iy
        xor a
        out (0E6h),a
        call CODE
        in a,(0E6h)
        ld l,a
        in a,(0E7h)
        ld h,a
        ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        pop iy
        ld de,4
        add iy,de
        pop bc
        djnz mm1
        ei
        ret
jphl:   jp (hl)

prep_nada:
        ret
prep_esc_off:
        call modo_p1_off
        jp dir_esc
prep_esc_p1:
        call modo_p1_on
        jp dir_esc
prep_esc_b1:
        call modo_b1_on
        jp dir_esc
prep_pal:
        call modo_p1_on
        ld b,14
        xor a
        jp v9reg                ; puntero de paleta a 0
prep_lec:
        call modo_p1_on
        jp dir_lec
prep_reg:
        call modo_p1_on
        ld a,8Fh                ; R#15 sin autoincremento
        out (V9SEL),a
        ret

; pruebas (32 bytes cada una como mucho; se copian a CODE)
t_p00:  ld c,00h
        ld d,8
        ld hl,BUF
        ld b,0
        otir
        dec d
        jr nz,$-8
        ret
t_p60:  ld c,V9VRAM
        ld d,8
        ld hl,BUF
        ld b,0
        otir
        dec d
        jr nz,$-8
        ret
t_p61:  ld c,V9PAL
        ld d,8
        ld hl,BUF
        ld b,0
        otir
        dec d
        jr nz,$-8
        ret
t_p63:  ld c,V9DATO
        ld d,8
        ld hl,BUF
        ld b,0
        otir
        dec d
        jr nz,$-8
        ret
t_in60: ld c,V9VRAM
        ld d,8
        ld hl,BUF
        ld b,0
        inir
        dec d
        jr nz,$-8
        ret

tabla:
        dw prep_nada,    t_p00          ; puerto 00h (referencia)
        dw prep_esc_off, t_p60          ; VRAM, pantalla apagada
        dw prep_esc_p1,  t_p60          ; VRAM, P1 encendido
        dw prep_esc_b1,  t_p60          ; VRAM, B1 8 bpp encendido
        dw prep_pal,     t_p61          ; paleta, P1 encendido
        dw prep_lec,     t_in60         ; leer VRAM, P1 encendido
        dw prep_reg,     t_p63          ; registro R#15, P1 encendido
        dw prep_nada,    t_p00          ; puerto 00h otra vez

nl:     ld a,13
        call CHPUT
        ld a,10
        jp CHPUT
imprime:
        ld a,(hl)
        or a
        ret z
        call CHPUT
        inc hl
        jr imprime
dec6:   ld a,' '
        call CHPUT
        ld de,10000
        call dig
        ld de,1000
        call dig
        ld de,100
        call dig
        ld de,10
        call dig
        ld a,l
        add a,'0'
        jp CHPUT
dig:    ld a,'0'-1
dig1:   inc a
        or a
        sbc hl,de
        jr nc,dig1
        add hl,de
        jp CHPUT

txt_no_tr:
        db "ESTA ROM ES PARA MSX TURBO R",0
txt_no_v9:
        db "NO ENCUENTRO EL V9990 (60h)",0
txt_titulo:
        db "PRUEBA WAIT V9990 (TURBO R)",13,10
        db "2048 ACCESOS, 1 CUENTA=3,9 US",13,10
        db "          Z80 R800R R800D",13,10,0
txt_pruebas:
        db "PTO 00 ",0
        db "VRAM NO",0
        db "VRAM P1",0
        db "VRAM B1",0
        db "PALETA ",0
        db "LEE VRA",0
        db "REG 15 ",0
        db "PTO 00 ",0
txt_pie:
        db 13,10,"HAZ UNA FOTO A ESTA PANTALLA",0

        ds 8000h-$,0FFh
