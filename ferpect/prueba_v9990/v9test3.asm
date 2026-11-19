; Prueba 3 de WAIT del V9990 (GFX9000) en MSX turbo R, con el R800.
; Perfil de la espera a lo largo de la linea: se sincroniza con la
; interrupcion de linea del V9990 (R#11 bit 7: todas las lineas), espera
; D (0-31, en pasos de 4 DJNZ), hace UN acceso a la VRAM (OUT o IN al
; puerto 60h) y cuenta vueltas de un bucle hasta la linea siguiente.
; Lo mismo con el puerto 00h da la referencia. Suma de 256 lineas.
; Resultado = vueltas perdidas (referencia - prueba); cada vuelta son
; unos 2 us. Modos P1 y B1 (8 bpp), con imagen.
; araubi, 2026. Licencia MIT.

CHGMOD  equ 005Fh
CHPUT   equ 00A2h
CHGCPU  equ 0180h
LINL40  equ 0F3AEh
MSXVER  equ 002Dh

V9VRAM  equ 60h
V9DATO  equ 63h
V9SEL   equ 64h
V9INT   equ 66h

RUT_OUT equ 0C000h
RUT_IN  equ 0C100h
RESUL   equ 0E000h          ; 4 perfiles x 32 x 2 bytes
TMP     equ 0E200h

        org 4000h
        db "AB"
        dw inicio
        ds 12,0

inicio:
        ld sp,0F380h
        ld a,80
        ld (LINL40),a
        xor a
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
        ; rutinas a la RAM
        ld hl,r_out
        ld de,RUT_OUT
        ld bc,64
        ldir
        ld hl,r_in
        ld de,RUT_IN
        ld bc,64
        ldir
        ld a,81h                ; R800 modo ROM
        call CHGCPU
        di
        ; interrupcion de linea en todas las lineas, posicion 0
        ld b,10
        xor a
        call v9reg
        ld b,11
        ld a,80h
        call v9reg
        ld b,12
        xor a
        call v9reg
        ld b,9
        ld a,02h                ; IEH
        call v9reg

        ld ix,RESUL
        call modo_p1_on
        call perfil_w
        call perfil_r
        call modo_b1_on
        call perfil_w
        call perfil_r

        ld b,9
        xor a
        call v9reg
        ld b,11
        xor a
        call v9reg
        ld a,0FFh
        out (V9INT),a
        ld b,8
        ld a,42h
        call v9reg
        ld a,80h
        call CHGCPU
        ei

        ld hl,txt_titulo
        call imprime
        ld c,0                  ; fila 0..15
fila:   push bc
        ld a,c
        call una_mitad
        ld hl,txt_sep
        call imprime
        pop bc
        push bc
        ld a,c
        add a,16
        call una_mitad
        call nl
        pop bc
        inc c
        ld a,c
        cp 16
        jr nz,fila
        ld hl,txt_pie
fin_texto:
        call imprime
        jr $

; imprime D=A y los 4 perfiles en la posicion A
una_mitad:
        push af
        ld l,a
        ld h,0
        call dec2
        pop af
        ld l,a
        ld h,0
        add hl,hl               ; *2
        ld de,RESUL
        add hl,de
        ld b,4
um1:    push bc
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        call dec5s
        pop hl
        ld de,64
        add hl,de
        pop bc
        djnz um1
        ret

; perfiles de escritura y lectura (32 valores en (IX))
perfil_w:
        call dir_esc
        ld iy,RUT_OUT
        jr perfil
perfil_r:
        call dir_lec
        ld iy,RUT_IN
perfil:
        ld d,1
pf1:    push de
        ld c,00h                ; referencia
        call llama
        ld (TMP),hl
        pop de
        push de
        ld c,V9VRAM
        call llama
        ex de,hl
        ld hl,(TMP)
        or a
        sbc hl,de
        ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        pop de
        ld a,d
        add a,4
        ld d,a
        cp 1+4*32
        jr nz,pf1
        ret
llama:  jp (iy)

; ---- rutinas que se copian a RAM (solo saltos relativos)
; C = puerto, D = vueltas de DJNZ de espera. Devuelve HL = vueltas.
r_out:  ld hl,0
        ld e,0
        ld a,2
        out (V9INT),a
ro1:    in a,(V9INT)
        and 2
        jr z,ro1
ro2:    ld a,2
        out (V9INT),a
        ld b,d
ro3:    djnz ro3
        out (c),a
ro4:    inc hl
        in a,(V9INT)
        and 2
        jr z,ro4
        dec e
        jr nz,ro2
        ret
r_in:   ld hl,0
        ld e,0
        ld a,2
        out (V9INT),a
ri1:    in a,(V9INT)
        and 2
        jr z,ri1
ri2:    ld a,2
        out (V9INT),a
        ld b,d
ri3:    djnz ri3
        in a,(c)
ri4:    inc hl
        in a,(V9INT)
        and 2
        jr z,ri4
        dec e
        jr nz,ri2
        ret

; ---- V9990
v9reg:  push af
        ld a,b
        out (V9SEL),a
        pop af
        out (V9DATO),a
        ret
dir_esc:
        xor a
        out (V9SEL),a
        out (V9DATO),a
        out (V9DATO),a
        ld a,04h
        out (V9DATO),a
        ret
dir_lec:
        ld a,3
        out (V9SEL),a
        xor a
        out (V9DATO),a
        out (V9DATO),a
        ld a,04h
        out (V9DATO),a
        ret
modo_p1_on:
        ld b,6
        ld a,05h
        call v9reg
        ld b,13
        ld a,04h
        call v9reg
        ld b,8
        ld a,82h
        call v9reg
        jr espera_cuadro
modo_b1_on:
        ld b,6
        ld a,86h
        call v9reg
        ld b,13
        xor a
        call v9reg
        ld b,8
        ld a,82h
        call v9reg
; esperar unos 60 ms a que el modo nuevo se vea (DISP cambia en el cuadro)
espera_cuadro:
        ld bc,0
ec1:    ex (sp),hl
        ex (sp),hl
        dec bc
        ld a,b
        or c
        jr nz,ec1
        ret

; ---- texto
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
dec2:   ld a,l
        ld b,'0'-1
d2a:    inc b
        sub 10
        jr nc,d2a
        add a,10+'0'
        push af
        ld a,b
        call CHPUT
        pop af
        jp CHPUT
; HL con signo en 6 posiciones
dec5s:  ld a,' '
        call CHPUT
        bit 7,h
        jr z,pos
        ld a,'-'
        call CHPUT
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        jr dg
pos:    ld a,' '
        call CHPUT
dg:     ld de,1000
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
        db "WAIT V9990 3 (R800): VUELTAS PERDIDAS EN 256 LINEAS SEGUN LA ESPERA D",13,10
        db "D   ESC.P1 LEE.P1 ESC.B1 LEE.B1   |  D   ESC.P1 LEE.P1 ESC.B1 LEE.B1",13,10,0
txt_sep:
        db "   |  ",0
txt_pie:
        db "HAZ UNA FOTO A ESTA PANTALLA",0

        ds 8000h-$,0FFh
