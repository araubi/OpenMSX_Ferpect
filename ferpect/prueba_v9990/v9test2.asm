; Prueba 2 de WAIT del V9990 (GFX9000), con Z80 en MSX turbo R.
; Escribe (OUT) o lee (IN) el puerto de VRAM 4096 veces con separaciones
; de N T-states (12 a 48, sin contar la espera M1: con ella, +1 o +2) y
; mide con el temporizador del S1990 cuanto tarda MAS que lo mismo en el
; puerto 00h (que nadie usa). Pantalla apagada, P1 y B1 (8 bpp).
; Resultado = cuentas de 3,911 us de mas en 4096 accesos.
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

CODE    equ 0C000h          ; bloque de 64 accesos + bucle
RESUL   equ 0E400h          ; 16 filas x 3 modos x 2 bytes
NFILAS  equ 16

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
        ld a,80h                ; Z80
        call CHGCPU
        di
        ld ix,RESUL
        ld hl,modo_p1_off
        call mide_modo
        ld hl,modo_p1_on
        call mide_modo
        ld hl,modo_b1_on
        call mide_modo
        ld b,8
        ld a,42h
        call v9reg
        ei

        ld hl,txt_titulo
        call imprime
        ld iy,txt_filas
        ld b,NFILAS
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
        ld de,NFILAS*2
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


; ---- las 16 filas con el modo que pone la rutina HL
mide_modo:
        ld (modo_rut),hl
        ld iy,plantillas
        ld b,NFILAS
mm1:    push bc
        ; referencia: la misma plantilla en el puerto 00h
        ld c,00h
        call genera
        call mide
        ld (ref),hl
        ; la prueba de verdad
        ld a,(iy+1)
        cp 0DBh
        ld hl,(modo_rut)
        call jphl
        ld a,(iy+1)
        cp 0DBh
        push af
        call nz,dir_esc
        pop af
        call z,dir_lec
        ld c,V9VRAM
        call genera
        call mide
        ld de,(ref)
        or a
        sbc hl,de
        jr nc,mm2
        ld hl,0                 ; mas rapido que la referencia: 0
mm2:    ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        ld de,12
        add iy,de
        pop bc
        djnz mm1
        ret
jphl:   jp (hl)

; mide: ejecuta CODE (4096 accesos) y da HL = cuentas del temporizador
mide:   ld d,64
        xor a
        out (0E6h),a
        call CODE
        in a,(0E6h)
        ld l,a
        in a,(0E7h)
        ld h,a
        ret

; genera en CODE: 64 x plantilla (IY+0 = longitud, IY+1.. bytes; el
; segundo byte es el puerto y se cambia por C), y luego
;   dec d / jp nz,CODE / ret   con D = 64 al entrar
genera: ld de,CODE
        ld a,64
gen1:   push af
        push iy
        pop hl
        ld a,(hl)               ; longitud
        inc hl
        push bc
        ld c,a
        ld b,0
        push de
        ldir
        pop hl
        inc hl
        pop bc
        ld (hl),c               ; puerto
        pop af
        dec a
        jr nz,gen1
        ex de,hl
        ld (hl),15h             ; dec d
        inc hl
        ld (hl),0C2h            ; jp nz,CODE
        inc hl
        ld (hl),low CODE
        inc hl
        ld (hl),high CODE
        inc hl
        ld (hl),0C9h            ; ret
        ret

modo_rut equ 0E500h
ref      equ 0E502h

; plantillas de 12 bytes: longitud, bytes (D3/DB nn = OUT/IN (nn),A, 12 T)
; relleno: 00 NOP 5 T, 23 INC HL 7 T, 06 00 LD B,0 8 T (con espera M1)
plantillas:
        db 2, 0D3h,0, 0,0,0,0,0,0,0,0,0                 ; 12
        db 3, 0D3h,0, 00h, 0,0,0,0,0,0,0,0              ; 17
        db 4, 0D3h,0, 06h,0, 0,0,0,0,0,0,0              ; 20
        db 4, 0D3h,0, 00h,23h, 0,0,0,0,0,0,0            ; 24
        db 6, 0D3h,0, 06h,0,06h,0, 0,0,0,0,0            ; 28
        db 6, 0D3h,0, 00h,23h,06h,0, 0,0,0,0,0          ; 32
        db 8, 0D3h,0, 06h,0,06h,0,23h,00h, 0,0,0        ; 40
        db 10,0D3h,0, 06h,0,06h,0,06h,0,23h,00h, 0      ; 48
        db 2, 0DBh,0, 0,0,0,0,0,0,0,0,0
        db 3, 0DBh,0, 00h, 0,0,0,0,0,0,0,0
        db 4, 0DBh,0, 06h,0, 0,0,0,0,0,0,0
        db 4, 0DBh,0, 00h,23h, 0,0,0,0,0,0,0
        db 6, 0DBh,0, 06h,0,06h,0, 0,0,0,0,0
        db 6, 0DBh,0, 00h,23h,06h,0, 0,0,0,0,0
        db 8, 0DBh,0, 06h,0,06h,0,23h,00h, 0,0,0
        db 10,0DBh,0, 06h,0,06h,0,06h,0,23h,00h, 0

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
        db "WAIT V9990 2 (Z80, 4096 ACC.)",13,10
        db "CUENTAS DE MAS (1=3,9 US)",13,10
        db "        APAG.    P1    B1",13,10,0
txt_filas:
        db "OUT 12T",0
        db "OUT 17T",0
        db "OUT 20T",0
        db "OUT 24T",0
        db "OUT 28T",0
        db "OUT 32T",0
        db "OUT 40T",0
        db "OUT 48T",0
        db "IN  12T",0
        db "IN  17T",0
        db "IN  20T",0
        db "IN  24T",0
        db "IN  28T",0
        db "IN  32T",0
        db "IN  40T",0
        db "IN  48T",0
txt_pie:
        db "HAZ UNA FOTO A ESTA PANTALLA",0

        ds 8000h-$,0FFh
