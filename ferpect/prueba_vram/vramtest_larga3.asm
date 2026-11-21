; Prueba larga de escritura en VRAM para MSX1 a 24, 25, 26 y 27 T
; y con el patron de War in Middle Earth (8 escrituras a 25 T y luego 46 T).
; SCREEN 2, imagen encendida, DI. Para cada separacion hace 200 pasadas de
; 1024 bytes (204.800 escrituras) con fases distintas y cuenta los bytes
; bytes perdidos, repetidos (el valor anterior) y erroneos, y pasadas con
; algun fallo.
; Sirve para saber si un VDP pierde bytes sueltos muy de vez en cuando
; (defectos alrededor del cursor en War in Middle Earth en el HB-20P).
; araubi, 2026. Licencia MIT.

CHGMOD  equ 005Fh
SETWRT  equ 0053h
SETRD   equ 0050h
CHPUT   equ 00A2h
FORCLR  equ 0F3E9h
LINL32  equ 0F3AFh

CODE    equ 0C000h          ; aqui se genera el codigo desenrollado
TABLA   equ 0D900h          ; 1024+ bytes 0,1,..,255,0,1.. para OUTI
RESUL   equ 0DE00h
conperd equ 0DF02h
pasada  equ 0DF06h
tperd   equ 0DF08h
trep    equ 0DF0Ah
terr    equ 0DF0Ch
vperd   equ 0DF10h
vrep    equ 0DF12h
verr    equ 0DF14h
NBYTES  equ 1024
NPRUEBA equ 5
NPASADA equ 200

        org 4000h
        db "AB"
        dw inicio
        ds 12,0

inicio:
        ld sp,0F380h
        ; tabla para OUTI
        ld hl,TABLA
        ld bc,1280
tab1:   ld (hl),l
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,tab1
        ; SCREEN 2 (deja IE y la imagen encendida, sprites 8x8)
        ld a,2
        call CHGMOD
        ; sprites fuera (Y=208 en el primero)
        ld hl,1B00h
        call SETWRT
        ld a,208
        out (98h),a

        ld ix,RESUL
        ld iy,plantillas
        ld b,NPRUEBA
bucle_prueba:
        push bc
        call genera
        ld hl,0
        ld (tperd),hl
        ld (trep),hl
        ld (terr),hl
        ld (conperd),hl
        xor a
        ld (pasada),a
bucle_pasada:
        ; esperar VBLANK y 950 + (p and 15)*34 + (p >> 4) vueltas de 30 T
        ei
        halt
        di
        ld a,(pasada)
        and 15
        ld b,a
        ld de,950
        ld a,(pasada)
        rrca
        rrca
        rrca
        rrca
        and 15
        add a,e
        ld e,a
        ld a,b
        or a
        jr z,espera2
espera1: ld hl,34
        add hl,de
        ex de,hl
        djnz espera1
espera2: dec de
        ld a,d
        or e
        jr nz,espera2
        ld hl,0
        call SETWRT
        di
        ld c,98h
        ld hl,TABLA
        xor a
        ld de,0
        call CODE
        call cuenta
        ld de,(vperd)
        ld hl,tperd
        call suma16
        ld de,(vrep)
        ld hl,trep
        call suma16
        ld de,(verr)
        ld hl,terr
        call suma16
        ld hl,(vperd)
        ld de,(vrep)
        ld a,h
        or l
        or d
        or e
        ld de,(verr)
        or d
        or e
        jr z,sin_perd
        ld de,(conperd)
        inc de
        ld (conperd),de
sin_perd:
        ld a,(pasada)
        inc a
        ld (pasada),a
        cp NPASADA
        jp nz,bucle_pasada
        ld hl,(tperd)
        ld (ix+0),l
        ld (ix+1),h
        ld hl,(trep)
        ld (ix+2),l
        ld (ix+3),h
        ld hl,(terr)
        ld (ix+4),l
        ld (ix+5),h
        ld hl,(conperd)
        ld (ix+6),l
        ld (ix+7),h
        ld de,8
        add ix,de
        ld de,LONG_PLANT
        add iy,de
        pop bc
        dec b
        jp nz,bucle_prueba

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
res1:   push bc
        ld a,(iy+0)
        call CHPUT
        ld a,(iy+1)
        call CHPUT
        ld a,(iy+2)
        call CHPUT
        ld hl,txt_t
        call imprime
        ld b,4
res2:   push bc
        ld l,(ix+0)
        ld h,(ix+1)
        inc ix
        inc ix
        call dec5
        pop bc
        djnz res2
        ld a,13
        call CHPUT
        ld a,10
        call CHPUT
        ld de,LONG_PLANT
        add iy,de
        pop bc
        djnz res1
        ld hl,txt_pie
        call imprime
fin:    jr fin

; --- genera NBYTES copias de la plantilla (IY+1 = longitud, IY+2.. bytes) + RET
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

; --- cuenta los bytes perdidos leyendo la VRAM despacio
; idx = valor logico; avanza con (b - idx) & 255; para al llegar a NBYTES-1
cuenta:
        ld hl,0
        ld (vperd),hl
        ld (vrep),hl
        ld (verr),hl
        call SETRD
        ex (sp),hl
        ex (sp),hl
        ld hl,0                 ; HL = idx (valor esperado)
        ld bc,0                 ; BC = posicion
cu1:    ex (sp),hl
        ex (sp),hl
        in a,(98h)
        inc bc
        sub l                   ; d = (leido - esperado) & 255
        jr z,cu_ok
        cp 0FFh
        jr z,cu_rep             ; repite el byte anterior
        cp 16
        jr nc,cu_err            ; otro valor: byte erroneo
        ; perdidos d bytes
        ld e,a
        ld d,0
        add hl,de
        push hl
        ld hl,(vperd)
        add hl,de
        ld (vperd),hl
        pop hl
        jr cu_ok
cu_rep: push hl
        ld hl,(vrep)
        inc hl
        ld (vrep),hl
        pop hl
        jr cu_ok
cu_err: push hl
        ld hl,(verr)
        inc hl
        ld (verr),hl
        pop hl
cu_ok:  inc hl
        ld a,h
        cp high NBYTES
        ret nc                  ; idx llega a 1024
        ld a,b
        cp high 1100
        jr c,cu1
        ret

; suma DE a (HL) saturando, HL = direccion
suma16: push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        add hl,de
        jr nc,su1
        ld hl,0FFFFh
su1:    ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        ret

imprime:
        ld a,(hl)
        or a
        ret z
        call CHPUT
        inc hl
        jr imprime

; numero HL en 2 cifras
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

; numero HL en 5 posiciones (con espacios delante)
dec5:   ld a,' '
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

txt_titulo:
        db "PRUEBA LARGA VRAM 3 MSX1 SCR 2",13,10
        db "200 PASADAS DE 1024 ESCRITURAS",13,10
        db "WME = 8 A 25 T Y 46 T, COMO",13,10
        db "WAR IN MIDDLE EARTH",13,10,13,10
        db "N   PERDID REPETI ERRONE PASADA",13,10,0
txt_t:  db 0
txt_pie:
        db "HAZ UNA FOTO A ESTA PANTALLA",0

; plantillas: N, longitud, bytes (todas de LONG_PLANT bytes)
LONG_PLANT equ 52
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
