; Prueba 2 de tiempos del MSX turbo R: codigo ejecutado desde la RAM
; (para no depender del cartucho). Temporizador del S1990 (E6h/E7h,
; 3,911 us por cuenta). 2048 operaciones por prueba, en Z80, R800 modo ROM
; y R800 modo DRAM. araubi, 2026. Licencia MIT.

CHGMOD  equ 005Fh
CHPUT   equ 00A2h
CHGCPU  equ 0180h
LINL32  equ 0F3AFh
MSXVER  equ 002Dh

CODE    equ 0C000h          ; codigo generado (hasta 4097 bytes)
BUF     equ 0D200h          ; 4096 bytes de datos
RESUL   equ 0E400h
NPRUEBA equ 10
LONG_P  equ 4               ; bytes por entrada de plantilla

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
        ld a,80h
        call mide_modo
        ld a,81h
        call mide_modo
        ld a,82h
        call mide_modo
        ld a,80h
        call CHGCPU
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
        call imprime
        jr $

; ---- las pruebas en el modo de CPU de A
mide_modo:
        call CHGCPU
        di
        ld iy,plantillas
        ld b,NPRUEBA
mm1:    push bc
        ; generar: (IY+0) = longitud (0 = rutina fija en (IY+2,IY+3))
        ld a,(iy+0)
        or a
        jr z,fija
        ld de,CODE
        ld bc,2048
gen1:   push bc
        push iy
        pop hl
        inc hl
        ld c,(iy+0)
        ld b,0
        ldir
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,gen1
        ld a,0C9h
        ld (de),a
        ld hl,CODE
        jr ejecuta
fija:   ld l,(iy+2)
        ld h,(iy+3)
        ; copiar la rutina fija (64 bytes) a CODE
        ld de,CODE
        ld bc,64
        ldir
        ld hl,CODE
ejecuta:
        push iy
        ld (destino),hl
        ld c,98h                ; por si acaso
        ld hl,BUF               ; HL en RAM para LD A,(HL)
        xor a
        out (0E6h),a            ; temporizador a 0
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
        ld de,LONG_P
        add iy,de
        pop bc
        djnz mm1
        ei
        ret

; rutinas fijas (se copian a RAM y se ejecutan alli)
r_ldir_ram:
        ld hl,BUF
        ld de,BUF+800h
        ld bc,800h
        ldir
        ret
        ds 64-($-r_ldir_ram),0
r_ldir_bios:
        ld hl,0000h
        ld de,BUF
        ld bc,800h
        ldir
        ret
        ds 64-($-r_ldir_bios),0
r_ldir_cart:
        ld hl,4000h
        ld de,BUF
        ld bc,800h
        ldir
        ret
        ds 64-($-r_ldir_cart),0

; plantillas: longitud, byte1, byte2, (relleno)  o  0,0,dirección rutina
plantillas:
        db 1, 00h, 0, 0                 ; NOP
        db 1, 7Eh, 0, 0                 ; LD A,(HL)
        db 2, 0D3h, 0A0h, 0             ; OUT (A0h),A  PSG
        db 2, 0DBh, 0A2h, 0             ; IN A,(A2h)   PSG
        db 2, 0D3h, 7Ch, 0              ; OUT (7Ch),A  OPLL
        db 2, 0D3h, 99h, 0              ; OUT (99h),A  VDP (R#0 alterna, A=0)
        db 2, 0DBh, 99h, 0              ; IN A,(99h)   VDP estado
        db 0, 0
        dw r_ldir_ram
        db 0, 0
        dw r_ldir_bios
        db 0, 0
        dw r_ldir_cart

destino: equ 0E500h

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
txt_titulo:
        db "PRUEBA 2 TURBO R (EN RAM)",13,10
        db "2048 VECES, 1 CUENTA=3,9 US",13,10
        db "          Z80 R800R R800D",13,10,0
txt_pruebas:
        db "NOP    ",0
        db "LD A,HL",0
        db "OUT A0 ",0
        db "IN A2  ",0
        db "OUT 7C ",0
        db "OUT 99 ",0
        db "IN 99  ",0
        db "LDIR RM",0
        db "LDIR BI",0
        db "LDIR CA",0
txt_pie:
        db 13,10,"HAZ UNA FOTO A ESTA PANTALLA",0

        ds 8000h-$,0FFh
