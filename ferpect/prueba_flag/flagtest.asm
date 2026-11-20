; PruebaFlag MSX: cuantas veces se pierde el flag F (S#0 bit 7) al
; esperar el cuadro leyendo S#0 en bucle (IN cada N T, con la espera M1; en turbo R la E/S del VDP tarda algo mas).
; 1000 esperas por cada N; una espera que dura 1,5 cuadros o mas = cuadro
; perdido. Funciona en cualquier MSX (turbo R: pasa a Z80).
; araubi, 2026. Licencia MIT.
CHGMOD  equ 005Fh
CHPUT   equ 00A2h
CHGCPU  equ 0180h
LINL40  equ 0F3AEh
MSXVER  equ 002Dh
NESP    equ 1000
THR     equ 0E000h
MISS    equ 0E002h
MINV    equ 0E004h
SEED    equ 0E006h
LIM     equ 0E008h
RESUL   equ 0E010h
        org 4000h
        db "AB"
        dw inicio
        ds 12,0
inicio:
        ld sp,0F380h
        ld a,(MSXVER)
        cp 3
        jr c,no_tr
        ld a,80h
        call CHGCPU
no_tr:  ld a,40
        ld (LINL40),a
        xor a
        call CHGMOD
        ld hl,txt_esp
        call imprime
        ld a,(MSXVER)
        or a
        jr z,es_msx1
        di
        xor a                   ; MSX2 o mas: R#15 = 0 (leer S#0)
        out (99h),a
        ld a,8Fh
        out (99h),a
es_msx1:
        ld hl,0ACE1h
        ld (SEED),hl
        di
        ld iy,RESUL
        ld ix,bucle0
        call prueba
        ld ix,bucle1
        call prueba
        ld ix,bucle2
        call prueba
        ld ix,bucle3
        call prueba
        ld ix,bucle4
        call prueba
        ld ix,bucle5
        call prueba
        ld ix,bucle6
        call prueba
        ld ix,bucle7
        call prueba
        ei
        call cls
        ld hl,txt_tit
        call imprime
        ld hl,(MINV)
        call dec5
        ld hl,txt_tit2
        call imprime
        ld iy,RESUL
        ld ix,txt_n
        ld b,8
resl:   push bc
        push ix
        pop hl
        call imprime
        inc hl
        push hl
        pop ix
        ld l,(iy+0)
        ld h,(iy+1)
        call dec5
        ld hl,txt_de
        call imprime
        inc iy
        inc iy
        pop bc
        djnz resl
        ld hl,txt_pie
        call imprime
        jr $

cls:    ld a,12
        jp CHPUT

; IX = bucle de espera. Guarda en (IY) los cuadros perdidos en NESP esperas
prueba:
        ld b,0FFh
        call callix             ; sincronizar
        ld hl,0FFFFh
        ld b,4
pr1:    push bc
        push hl
        call rdelay
        ld b,0FFh
        call callix
        pop hl
        or a
        sbc hl,de
        add hl,de
        jr c,pr2
        ex de,hl                ; HL = minimo
pr2:    pop bc
        djnz pr1
        push iy
        pop de
        ld a,e
        cp low RESUL
        jr nz,pr3
        ld (MINV),hl
pr3:    ld d,h
        ld e,l
        srl d
        rr e
        add hl,de               ; umbral = 1,5 x minimo
        ld (THR),hl
        add hl,hl
        ld a,h
        inc a
        ld (LIM),a              ; limite = unos 3 cuadros
        ld hl,0
        ld (MISS),hl
        ld bc,NESP
pr4:    push bc
        call rdelay
        ld a,(LIM)
        ld b,a
        call callix
        ld hl,(THR)
        ex de,hl
        or a
        sbc hl,de               ; vueltas - umbral
        jr c,pr5
        ld hl,(MISS)
        inc hl
        ld (MISS),hl
pr5:    pop bc
        dec bc
        ld a,b
        or c
        jr nz,pr4
        ld hl,(MISS)
        ld (iy+0),l
        ld (iy+1),h
        inc iy
        inc iy
        ret
callix: jp (ix)

; espera al azar de 5n + 8m T (n 0..63, m 0..4), para que las lecturas
; caigan en cualquier punto respecto al momento en que se pone F
rdelay: ld hl,(SEED)
        srl h
        rr l
        jr nc,rd1
        ld a,h
        xor 0B4h
        ld h,a
rd1:    ld (SEED),hl
        ld a,l
        and 3Fh
        ld e,a
        ld d,0
        ld hl,s1end
        or a
        sbc hl,de
        jp (hl)
s1:     ds 63,0
s1end:  ld a,(SEED+1)
        and 7
        cp 5
        jr c,rd2
        sub 3
rd2:    ld e,a
        ld d,0
        ld hl,s2end
        or a
        sbc hl,de
        jp (hl)
s2:     db 7Eh,7Eh,7Eh,7Eh
s2end:  ret

; vuelta de 39 T (12+5+6+0+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle0: ld de,0
bl0:   in a,(99h)
        and a
        ret m
        inc e
        jp nz,bl0
        inc d
        ld a,d
        cp b
        ret nc
        jp bl0
; vuelta de 44 T (12+5+6+5+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle1: ld de,0
bl1:   in a,(99h)
        and a
        ret m
        nop
        inc e
        jp nz,bl1
        inc d
        ld a,d
        cp b
        ret nc
        jp bl1
; vuelta de 49 T (12+5+6+10+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle2: ld de,0
bl2:   in a,(99h)
        and a
        ret m
        nop
        nop
        inc e
        jp nz,bl2
        inc d
        ld a,d
        cp b
        ret nc
        jp bl2
; vuelta de 54 T (12+5+6+15+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle3: ld de,0
bl3:   in a,(99h)
        and a
        ret m
        nop
        nop
        nop
        inc e
        jp nz,bl3
        inc d
        ld a,d
        cp b
        ret nc
        jp bl3
; vuelta de 64 T (12+5+6+25+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle4: ld de,0
bl4:   in a,(99h)
        and a
        ret m
        nop
        nop
        nop
        nop
        nop
        inc e
        jp nz,bl4
        inc d
        ld a,d
        cp b
        ret nc
        jp bl4
; vuelta de 74 T (12+5+6+35+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle5: ld de,0
bl5:   in a,(99h)
        and a
        ret m
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        inc e
        jp nz,bl5
        inc d
        ld a,d
        cp b
        ret nc
        jp bl5
; vuelta de 94 T (12+5+6+55+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle6: ld de,0
bl6:   in a,(99h)
        and a
        ret m
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        inc e
        jp nz,bl6
        inc d
        ld a,d
        cp b
        ret nc
        jp bl6
; vuelta de 134 T (12+5+6+95+5+11). Sale con DE = vueltas;
; si D llega a B, se rinde (cuadro perdido varias veces seguidas)
bucle7: ld de,0
bl7:   in a,(99h)
        and a
        ret m
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        inc e
        jp nz,bl7
        inc d
        ld a,d
        cp b
        ret nc
        jp bl7
imprime:
        ld a,(hl)
        or a
        ret z
        call CHPUT
        inc hl
        jr imprime
dec5:   ld de,10000
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
dg1:    inc a
        or a
        sbc hl,de
        jr nc,dg1
        add hl,de
        jp CHPUT
txt_esp: db "PRUEBA FLAG F: ESPERA UNOS 4 MINUTOS...",0
txt_tit: db "PRUEBA FLAG F (S#0 BIT 7) LEYENDO EN BUCLE",13,10
         db "VUELTAS DE 39 T POR CUADRO:",0
txt_tit2: db 13,10,"CUADROS PERDIDOS CADA 1000 ESPERAS:",13,10,0
txt_n:
        db "  IN CADA  39 T: ",0
        db "  IN CADA  44 T: ",0
        db "  IN CADA  49 T: ",0
        db "  IN CADA  54 T: ",0
        db "  IN CADA  64 T: ",0
        db "  IN CADA  74 T: ",0
        db "  IN CADA  94 T: ",0
        db "  IN CADA 134 T: ",0
txt_de:  db 13,10,0
txt_pie: db 13,10,"HAZ UNA FOTO A ESTA PANTALLA",0
        ds 8000h-$,0FFh
