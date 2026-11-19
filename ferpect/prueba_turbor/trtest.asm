; Prueba de tiempos del MSX turbo R (Z80, R800 ROM, R800 DRAM)
; Mide con el temporizador del S1990 (E6h/E7h, 3,911 us por cuenta) cuanto
; tardan 2048 accesos de cada tipo, y vuelca los registros 0-15 del S1990.
; araubi, 2026. Licencia MIT.

CHGMOD  equ 005Fh
SETWRT  equ 0053h
CHPUT   equ 00A2h
CHGCPU  equ 0180h
LINL32  equ 0F3AFh
MSXVER  equ 002Dh

RESUL   equ 0D000h          ; 8 pruebas x 3 modos x 2 bytes
BUF     equ 0D100h          ; 2048 bytes para LDIR/INIR
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
        call imprime
        jr $
es_tr:
        ld ix,RESUL
        ld a,80h                ; Z80 (LED encendido)
        call mide_modo
        ld a,81h                ; R800 modo ROM
        call mide_modo
        ld a,82h                ; R800 modo DRAM
        call mide_modo
        ld a,80h
        call CHGCPU
        ei

        ld hl,txt_titulo
        call imprime
        ld iy,txt_pruebas
        ld b,NPRUEBA
        ld de,0                 ; desplazamiento en RESUL (prueba*2)
res1:   push bc
        push de
        push iy
        pop hl
        call imprime            ; nombre (8 car.)
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

        ; registros del S1990
        ld hl,txt_s1990
        call imprime
        ld c,0
reg1:   ld a,c
        out (0E4h),a
        in a,(0E5h)
        call hex2
        ld a,' '
        call CHPUT
        inc c
        ld a,c
        cp 8
        call z,nl
        ld a,c
        cp 16
        jr nz,reg1
        call nl
        ld hl,txt_pie
        call imprime
        jr $

; ---- mide las 8 pruebas en el modo de CPU de A; resultados en (IX), IX+=16
mide_modo:
        call CHGCPU
        di
        ; direccion de VRAM de escritura 8000h (libre en SCREEN 1)
        ld a,2                  ; R#14 = 2 (A14-A16)
        out (99h),a
        ld a,8Eh
        out (99h),a
        xor a
        out (99h),a
        ld a,40h                ; A0-A7 = 0, A8-A13 = 0, escribir
        out (99h),a
        ld iy,tabla_pruebas
        ld b,NPRUEBA
mm1:    push bc
        ld l,(iy+0)
        ld h,(iy+1)
        inc iy
        inc iy
        push iy
        ; poner el temporizador a 0 y ejecutar la prueba
        out (0E6h),a
        call jphl
        in a,(0E6h)
        ld l,a
        in a,(0E7h)
        ld h,a
        ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        pop iy
        pop bc
        djnz mm1
        ; dejar R#14 a 0
        xor a
        out (99h),a
        ld a,8Eh
        out (99h),a
        ei
        ret

jphl:   jp (hl)

tabla_pruebas:
        dw p_vacio, p_vram, p_stat, p_opll, p_psg, p_ram, p_rom, p_nop

; 0: bucle vacio (8 x DJNZ de 256)
p_vacio: ld c,8
pv1:    ld b,0
pv2:    djnz pv2
        dec c
        jr nz,pv1
        ret
; 1: 2048 OUT a la VRAM (OTIR al puerto 98h)
p_vram: ld c,98h
        ld hl,BUF
        ld d,8
pr1:    ld b,0
        otir
        dec d
        jr nz,pr1
        ret
; 2: 2048 IN del estado de la VDP (INIR del puerto 99h, S#0)
p_stat: ld c,99h
        ld d,8
ps1:    ld hl,BUF
        ld b,0
        inir
        dec d
        jr nz,ps1
        ret
; 3: 2048 OUT al puerto de direccion del OPLL (7Ch)
p_opll: ld c,7Ch
        ld hl,BUF
        ld d,8
po1:    ld b,0
        otir
        dec d
        jr nz,po1
        ret
; 4: 2048 OUT al puerto de direccion del PSG (A0h)
p_psg:  ld c,0A0h
        ld hl,BUF
        ld d,8
pp1:    ld b,0
        otir
        dec d
        jr nz,pp1
        ret
; 5: LDIR de 2048 bytes de RAM a RAM
p_ram:  ld hl,BUF
        ld de,BUF+800h
        ld bc,800h
        ldir
        ret
; 6: LDIR de 2048 bytes de la ROM del cartucho a RAM
p_rom:  ld hl,4000h
        ld de,BUF
        ld bc,800h
        ldir
        ret
; 7: 2048 NOP desenrollados (en RAM no: en la ROM del cartucho)
p_nop:  rept 2048
        nop
        endm
        ret

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

hex2:   push af
        rrca
        rrca
        rrca
        rrca
        call hex1
        pop af
hex1:   and 0Fh
        add a,'0'
        cp '9'+1
        jr c,hx
        add a,7
hx:     jp CHPUT

; HL en 6 posiciones (espacio + 5 cifras)
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
txt_titulo:
        db "PRUEBA TURBO R (CUENTAS E6h)",13,10
        db "2048 ACCESOS, 1 CUENTA=3,9 US",13,10
        db "          Z80 R800R R800D",13,10,0
txt_pruebas:
        db "VACIO  ",0
        db "VRAM   ",0
        db "ESTADO ",0
        db "OPLL   ",0
        db "PSG    ",0
        db "RAM    ",0
        db "ROM    ",0
        db "NOP ROM",0
txt_s1990:
        db 13,10,"REGISTROS S1990 0-15:",13,10,0
txt_pie:
        db 13,10,"HAZ UNA FOTO A ESTA PANTALLA",0

        ds 8000h-$,0FFh
