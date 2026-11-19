; Prueba de velocidad de escritura en VRAM para MSX1 (TMS9918/9928/9929)
; SCREEN 2, imagen encendida, DI. Para cada separacion N (17..32 T, con la
; espera M1 del MSX) escribe 1024 bytes 0,1,2,... desde 0000h y luego los
; lee despacio y cuenta cuantos se han perdido. 4 pasadas con distinta fase.
; araubi, 2026. Licencia MIT.

CHGMOD  equ 005Fh
SETWRT  equ 0053h
SETRD   equ 0050h
CHPUT   equ 00A2h
FORCLR  equ 0F3E9h
LINL32  equ 0F3AFh

CODE    equ 0C000h          ; aqui se genera el codigo desenrollado
TABLA   equ 0D900h          ; 1024+ bytes 0,1,..,255,0,1.. para OUTI
RESUL   equ 0DE00h          ; 16 pruebas x 4 pasadas x 2 bytes
NBYTES  equ 1024
NPRUEBA equ 16
NPASADA equ 4

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
        call genera             ; genera el codigo de la prueba (IY)
        ld c,0                  ; pasada
bucle_pasada:
        push bc
        ; esperar VBLANK y luego ~28500 T (fin del borde inferior y superior,
        ; en PAL) mas c*~1000 T, para escribir con la imagen dibujandose
        ei
        halt
        di
        ld de,950               ; 950 vueltas x 30 T
        ld a,c
        or a
        jr z,espera2
espera1: ld hl,34
        add hl,de
        ex de,hl
        dec c
        jr nz,espera1
espera2: dec de                 ; 7+5+5+13 = 30 T por vuelta
        ld a,d
        or e
        jr nz,espera2
sin_espera:
        ld hl,0
        call SETWRT             ; deja C/A como sea; ponemos lo nuestro
        di
        ld c,98h
        ld hl,TABLA             ; para OUTI; L=0 para OUT (C),L
        xor a                   ; A=0 y acarreo a 0 (RET C no salta)
        ld de,0
        call CODE
        call cuenta             ; HL = perdidos
        ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        pop bc
        inc c
        ld a,c
        cp NPASADA
        jr nz,bucle_pasada
        ld de,LONG_PLANT
        add iy,de
        pop bc
        djnz bucle_prueba

        ; resultados en SCREEN 1
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
        ld a,(iy+0)             ; N
        ld l,a
        ld h,0
        call dec2
        ld hl,txt_t
        call imprime
        ld b,NPASADA
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
        ld bc,NBYTES
gen1:   push bc
        push iy
        pop hl
        inc hl
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
        call SETRD
        ex (sp),hl
        ex (sp),hl
        in a,(98h)              ; primer byte (deberia ser 0)
        ld e,a
        ld d,0                  ; DE = idx
        ld bc,0                 ; BC = posicion
cue1:   ex (sp),hl
        ex (sp),hl
        in a,(98h)
        inc bc
        sub e                   ; paso = (b - idx) & 255
        jr nz,cue2
        ld a,0                  ; paso 0: no deberia pasar; contar como 1
        inc a
cue2:   add a,e
        ld e,a
        jr nc,cue3
        inc d
cue3:   ; ajuste: si paso hizo idx > NBYTES-1, no importa; paramos
        ld a,d
        cp high (NBYTES-1)
        jr c,cue4
        ld a,e
        cp low (NBYTES-1)
        jr nc,cue_fin
cue4:   ld a,b
        cp high 1100
        jr c,cue1
cue_fin:
        ; perdidos = idx - posicion
        ex de,hl
        or a
        sbc hl,bc
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
        db "PRUEBA VRAM MSX1 PAL (SCREEN 2)",13,10
        db "BYTES PERDIDOS DE 1024",13,10
        db "N = T ENTRE ESCRITURAS",13,10
        db "PASADA:  1    2    3    4",13,10,0
txt_t:  db "T: ",0
txt_pie:
        db "HAZ UNA FOTO A ESTA PANTALLA",0

; plantillas: N, longitud, bytes (todas de LONG_PLANT bytes)
LONG_PLANT equ 8
plantillas:
        db 17,3, 0D3h,98h,3Ch, 0,0,0                 ; OUT (98h),A / INC A
        db 18,2, 0EDh,0A3h, 0,0,0,0                  ; OUTI
        db 19,3, 0EDh,79h,3Ch, 0,0,0                 ; OUT (C),A / INC A
        db 20,4, 0D3h,98h,0C6h,01h, 0,0              ; OUT (98h),A / ADD A,1
        db 21,3, 0EDh,69h,23h, 0,0,0                 ; OUT (C),L / INC HL
        db 22,4, 0D3h,98h,3Ch,00h, 0,0               ; + NOP
        db 23,4, 0D3h,98h,3Ch,0D8h, 0,0              ; + RET C (no salta)
        db 24,4, 0D3h,98h,3Ch,13h, 0,0               ; + INC DE
        db 25,5, 0D3h,98h,3Ch,06h,00h, 0             ; + LD B,0
        db 26,5, 0D3h,98h,0C6h,01h,0D8h, 0           ; ADD A,1 + RET C
        db 27,5, 0D3h,98h,3Ch,00h,00h, 0             ; + NOP NOP
        db 28,6, 0D3h,98h,3Ch,21h,00h,00h            ; + LD HL,0
        db 29,5, 0D3h,98h,3Ch,00h,13h, 0             ; + NOP INC DE
        db 30,6, 0D3h,98h,3Ch,00h,06h,00h            ; + NOP LD B,0
        db 31,5, 0D3h,98h,3Ch,13h,13h, 0             ; + INC DE INC DE
        db 32,6, 0D3h,98h,3Ch,13h,06h,00h            ; + INC DE LD B,0

        ds 8000h-$,0FFh
