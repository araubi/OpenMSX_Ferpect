; VRAMMED3.COM - medidas de escrituras rapidas en la VRAM de MSX1 (MSX-DOS), con
; CALIBRACION: mide contra el propio VDP cuanto tarda de verdad cada rutina.
; araubi, 2026. Licencia MIT.
;
; Repite NCICLOS ciclos (unos 30 minutos). En cada ciclo:
;  T: marca (numero de ciclo y JIFFY).
;  C: calibracion. Regla = vueltas de un bucle fijo entre dos borrados
;     verticales (FRM). Para cada rutina: se espera el borrado, se ejecuta y
;     se cuentan las vueltas de la regla hasta el borrado siguiente (dos veces).
;     tiempo = (vueltas con NUL - vueltas) * cuadro / FRM.
;  M: para cada ritmo y 16 arranques (cada 20 lineas desde el borrado): llena
;     con EEh, escribe 1024 bytes 00,01,02.., relee despacio y clasifica:
;     primer fallo y numero de fallos por arranque, y totales
;     A (dato siguiente + byte sin escribir), S (corrido), B, E, O.
; Todo va a VRAMMED3.CSV (hexadecimal). Una tecla termina al acabar el ciclo.

BDOS    equ 0005h
CALSLT  equ 001Ch
EXPTBL  equ 0FCC1h
INITXT  equ 006Ch
JIFFY   equ 0FC9Eh

CODE    equ 4000h
BUF     equ 8000h
TABLA   equ 8800h
OUTB    equ 9000h
NPOS    equ 16
NCICLOS equ 55
LONG_PLANT equ 52
NCAL    equ 16
NMED    equ 16

        org 0100h

inicio:
        ld sp,(0006h)
        ld hl,TABLA
        ld bc,1024
it1:    ld (hl),l
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,it1
        ld hl,BUF+1024
        ld b,16
it2:    ld (hl),0FFh
        inc hl
        djnz it2
        ld de,txt_ini
        ld c,9
        call BDOS
        ld de,fcb
        ld c,16h
        call BDOS
        or a
        jp nz,error
        ld hl,OUTB
        ld (outp),hl
        ld hl,txt_cab
        call pon_txt
        ; cabecera: ranuras y version
        in a,(0A8h)
        call pon_hex2
        call coma
        ld a,(0FFFFh)
        call pon_hex2
        call coma
        ld hl,EXPTBL
        ld b,8
cb1:    ld a,(hl)
        push hl
        push bc
        call pon_hex2
        pop bc
        pop hl
        inc hl
        djnz cb1
        call coma
        ld hl,0F341h
        ld b,4
cb2:    ld a,(hl)
        push hl
        push bc
        call pon_hex2
        pop bc
        pop hl
        inc hl
        djnz cb2
        call coma
        ld c,0Ch
        call BDOS
        call pon_hex4
        call crlf
        call vaciar

        xor a
        ld (ciclo),a
bucle_ciclo:
        ; ---- marca
        ld a,'T'
        call pon_car
        call coma
        ld a,(ciclo)
        call pon_hex2
        call coma
        ld hl,(JIFFY)
        call pon_hex4
        call crlf
        ; ---- calibracion
        di
        call vdp_scr2
        ld hl,txt_frm
        call cab_c
        call cal_frame
        call pon_hex4
        call coma
        call cal_frame
        call pon_hex4
        call crlf
        ld hl,CODE
        ld (cvec+1),hl
        ld iy,plantillas
        ld b,NCAL+NMED
cc1:    push bc
        call genera
        push iy
        pop hl
        call cab_c
        call cal_code
        call pon_hex4
        call coma
        call cal_code
        call pon_hex4
        call crlf
        ld de,LONG_PLANT
        add iy,de
        pop bc
        djnz cc1
        ld hl,esp760
        ld (cvec+1),hl
        ld hl,txt_dly
        call cab_c
        call cal_code
        call pon_hex4
        call coma
        call cal_code
        call pon_hex4
        call crlf
        ei
        call vaciar
        ; ---- medidas
        ld iy,plant_med
        ld b,NMED
bp1:    push bc
        call genera
        ld a,'M'
        call pon_car
        call coma
        ld a,(ciclo)
        call pon_hex2
        call coma
        ld a,(iy+0)
        call pon_car
        ld a,(iy+1)
        call pon_car
        ld a,(iy+2)
        call pon_car
        ld hl,0
        ld (tA),hl
        ld (tS),hl
        ld (tB),hl
        ld (tE),hl
        ld (tO),hl
        xor a
        ld (posk),a
bpos:   call medida
        call analiza
        call coma
        ld hl,(primero)
        call pon_hex4
        ld a,':'
        call pon_car
        ld hl,(cA)
        ld de,(cS)
        add hl,de
        ld de,(cB)
        add hl,de
        ld de,(cE)
        add hl,de
        ld de,(cO)
        add hl,de
        call pon_hex4
        ld hl,(tA)
        ld de,(cA)
        add hl,de
        ld (tA),hl
        ld hl,(tS)
        ld de,(cS)
        add hl,de
        ld (tS),hl
        ld hl,(tB)
        ld de,(cB)
        add hl,de
        ld (tB),hl
        ld hl,(tE)
        ld de,(cE)
        add hl,de
        ld (tE),hl
        ld hl,(tO)
        ld de,(cO)
        add hl,de
        ld (tO),hl
        ld a,(posk)
        inc a
        ld (posk),a
        cp NPOS
        jp c,bpos
        ld ix,tA
        ld b,5
bt1:    call coma
        ld l,(ix+0)
        ld h,(ix+1)
        push bc
        call pon_hex4
        pop bc
        inc ix
        inc ix
        djnz bt1
        call crlf
        ei
        call vaciar
        ld de,LONG_PLANT
        add iy,de
        pop bc
        dec b
        jp nz,bp1
        ; ---- tecla?
        ld c,0Bh
        call BDOS
        or a
        jr nz,fin
        ld a,(ciclo)
        inc a
        ld (ciclo),a
        cp NCICLOS
        jp c,bucle_ciclo

fin:    ld hl,(outp)
        ld (hl),1Ah
        ld de,OUTB
        ld c,1Ah
        call BDOS
        ld de,fcb
        ld c,15h
        call BDOS
        ld de,fcb
        ld c,10h
        call BDOS
        call texto
        ld de,txt_fin
        ld c,9
        call BDOS
        rst 0

error:  ld de,txt_err
        ld c,9
        call BDOS
        rst 0

texto:  ld iy,(EXPTBL-1)
        ld ix,INITXT
        call CALSLT
        ei
        ret

crlf:   ld a,13
        call pon_car
        ld a,10
        jp pon_car

; "C,cc,NOM," con el nombre de 3 letras en HL
cab_c:  ld a,'C'
        call pon_car
        call coma
        ld a,(ciclo)
        call pon_hex2
        call coma
        ld b,3
ca1:    ld a,(hl)
        call pon_car
        inc hl
        djnz ca1
        jp coma

; ------------------------------------------------------- calibracion
; HL = vueltas de la regla entre dos borrados verticales
cal_frame:
        di
        in a,(99h)
cf1:    in a,(99h)
        rlca
        jr nc,cf1
        ld hl,0
cf2:    inc hl
        in a,(99h)
        rlca
        jr nc,cf2
        ret

; HL = vueltas de la regla desde que acaba la rutina (cvec) hasta el borrado
cal_code:
        di
        ld hl,0
        call setw
        in a,(99h)
cs1:    in a,(99h)
        rlca
        jr nc,cs1
        ld c,98h
        xor a
        ld de,0
        ld hl,TABLA
cvec:   call CODE
        ld hl,0
cr1:    inc hl
        in a,(99h)
        rlca
        jr nc,cr1
        ret

; el bucle de espera de las medidas, 760 vueltas
esp760: ld de,760
e71:    dec de
        ld a,d
        or e
        jr nz,e71
        ret

; ---------------------------------------------------------------- VDP
vdp_scr2:
        ld hl,regs
        ld b,0
vs1:    ld a,(hl)
        out (99h),a
        ld a,b
        or 80h
        out (99h),a
        inc hl
        inc b
        ld a,b
        cp 8
        jr c,vs1
        ; 32 sprites en Y 209, como deja la BIOS
        ld hl,1B00h
        call setw
        ld b,32
sp1:    ld a,209
        out (98h),a
        ex (sp),hl
        ex (sp),hl
        xor a
        out (98h),a
        ex (sp),hl
        ex (sp),hl
        out (98h),a
        ex (sp),hl
        ex (sp),hl
        out (98h),a
        ex (sp),hl
        ex (sp),hl
        djnz sp1
        ret

regs:   db 02h,0C0h,06h,0FFh,03h,36h,07h,0F4h

setw:   ld a,l
        out (99h),a
        ld a,h
        or 40h
        out (99h),a
        ret

setr:   ld a,l
        out (99h),a
        ld a,h
        and 3Fh
        out (99h),a
        ret

; una medida: rutina en CODE, arranque (posk) x 20 lineas
medida:
        di
        call vdp_scr2
        ld hl,0
        call setw
        ld bc,1280
        ld e,0EEh
ll1:    ld a,e
        out (98h),a
        dec bc
        ld a,b
        or c
        jr nz,ll1
        in a,(99h)
sy1:    in a,(99h)
        rlca
        jr nc,sy1
        ; esperar posk*20 lineas teoricas (152 vueltas de 30 T)
        ld a,(posk)
        ld hl,1
        ld de,152
        or a
        jr z,dl2
        ld b,a
dl1:    add hl,de
        djnz dl1
dl2:    ex de,hl
dl3:    dec de
        ld a,d
        or e
        jr nz,dl3
        ld hl,0
        call setw
        ld c,98h
        xor a
        ld de,0
        ld hl,TABLA
        call CODE
        ld hl,0
        call setr
        ex (sp),hl
        ex (sp),hl
        ld hl,BUF
        ld bc,1024
rl1:    in a,(98h)
        ld (hl),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,rl1
        ret

; ------------------------------------------------------------ analisis
analiza:
        ld hl,0
        ld (cA),hl
        ld (cS),hl
        ld (cB),hl
        ld (cE),hl
        ld (cO),hl
        ld hl,0FFFFh
        ld (primero),hl
        xor a
        ld (nev),a
        ld (despl),a
        ld hl,BUF
        ld bc,0
an1:    ld a,b
        cp 4
        ret nc
        ld a,(despl)
        add a,c
        ld d,a                  ; D = esperado
        ld a,(hl)
        cp d
        jr nz,an_fallo
an_sig: inc hl
        inc bc
        jr an1

an_fallo:
        call apunta
        ld a,(hl)
        inc hl
        ld e,(hl)               ; E = siguiente
        dec hl
        inc d                   ; D = esperado+1
        cp d
        jr nz,an_noA
        ld a,e
        cp 0EEh
        jr nz,an_noA2
        ; A: byte mal + sin escribir
        push hl
        ld hl,(cA)
        inc hl
        ld (cA),hl
        pop hl
        inc hl
        inc bc
        jr an_sig
an_noA2:
        cp d
        jr nz,an_noB
        ; B: byte mal, resto en su sitio
        push hl
        ld hl,(cB)
        inc hl
        ld (cB),hl
        pop hl
        jr an_sig
an_noB: inc d
        cp d
        jr nz,an_otro
        ; S: corrido 1
        ld a,(despl)
        inc a
        ld (despl),a
        push hl
        ld hl,(cS)
        inc hl
        ld (cS),hl
        pop hl
        jr an_sig
an_noA: cp 0EEh
        jr nz,an_noE
        push hl
        ld hl,(cE)
        inc hl
        ld (cE),hl
        pop hl
        jr an_sig
an_noE: inc d                   ; esperado+2 ?
        cp d
        jr nz,an_otro
        inc d
        ld a,e
        cp d
        jr nz,an_otro
        ; corrido 2
        ld a,(despl)
        add a,2
        ld (despl),a
        push hl
        ld hl,(cS)
        inc hl
        inc hl
        ld (cS),hl
        pop hl
        jr an_sig
an_otro:
        push hl
        ld hl,(cO)
        inc hl
        ld (cO),hl
        pop hl
        jr an_sig

; anota la posicion BC del fallo
apunta: push hl
        ld hl,(primero)
        ld a,h
        and l
        inc a
        jr nz,ap1
        ld (primero),bc
ap1:    ld a,(nev)
        cp 8
        jr nc,ap2
        inc a
        ld (nev),a
        dec a
        add a,a
        ld e,a
        ld d,0
        ld hl,eventos
        add hl,de
        ld (hl),c
        inc hl
        ld (hl),b
ap2:    pop hl
        ld a,(despl)            ; recalcula D (apunta no lo toca, pero por si)
        add a,c
        ld d,a
        ret

; ------------------------------------------------------------ salida
coma:   ld a,','
pon_car:
        push hl
        ld hl,(outp)
        ld (hl),a
        inc hl
        ld (outp),hl
        pop hl
        ret

pon_txt:
        ld a,(hl)
        or a
        ret z
        call pon_car
        inc hl
        jr pon_txt

pon_hex4:
        ld a,h
        call pon_hex2
        ld a,l
pon_hex2:
        push af
        rrca
        rrca
        rrca
        rrca
        call pon_hex1
        pop af
pon_hex1:
        and 15
        add a,'0'
        cp '9'+1
        jr c,ph1
        add a,7
ph1:    jp pon_car

; escribe los registros completos de 128 bytes y deja el resto al principio
vaciar:
        ld hl,(outp)
        ld de,OUTB
        or a
        sbc hl,de               ; HL = bytes pendientes
        ld de,OUTB
va1:    ld a,h
        or a
        jr nz,va2
        ld a,l
        cp 128
        jr c,va3
va2:    push hl
        push de
        ld c,1Ah
        call BDOS
        ld de,fcb
        ld c,15h
        call BDOS
        pop de
        ld hl,128
        add hl,de
        ex de,hl
        pop hl
        ld bc,128
        or a
        sbc hl,bc
        jr va1
va3:    ; mover el resto (L bytes desde DE) a OUTB
        ld c,l
        ld b,0
        ex de,hl
        ld de,OUTB
        ld a,c
        or a
        jr z,va4
        ldir
va4:    ld (outp),de
        ret

; ------------------------------------------------------------ plantillas
genera:
        ld de,CODE
        ld c,(iy+3)
        ld b,(iy+4)
gen1:   push bc
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ld c,(hl)
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


txt_ini:
        db "VRAMMED3: tarda unos 30 minutos y deja VRAMMED3.CSV.",13,10
        db "Una tecla = terminar al acabar el ciclo.",13,10,"$"
txt_cab:
        db "VRAMMED3 (araubi, MIT). H=A8,FFFF,EXPTBL+SLTTBL,RAMAD,VERDOS / T,ciclo,JIFFY / "
        db "C,ciclo,rutina,regla1,regla2 / M,ciclo,ritmo,16x(primer:fallos),A,S,B,E,O",13,10,"H,",0
txt_fin:
        db "Hecho: VRAMMED3.CSV",13,10,"$"
txt_err:
        db "No se puede crear VRAMMED3.CSV",13,10,"$"
txt_frm: db "FRM"
txt_dly: db "DLY"

fcb:    db 0,"VRAMMED3CSV"
        ds 25,0

outp:   dw 0
ciclo:  db 0
posk:   db 0
cA:     dw 0
cS:     dw 0
cB:     dw 0
cE:     dw 0
cO:     dw 0
tA:     dw 0
tS:     dw 0
tB:     dw 0
tE:     dw 0
tO:     dw 0
primero: dw 0
nev:    db 0
despl:  db 0
eventos: ds 16,0

; etiqueta (3), repeticiones (dw), longitud, bytes (hasta 46)
plantillas:
        db "NUL"
        dw 1
        db 1,000h    ; vacio: 1 NOP
        ds 45,0
        db "NOP"
        dw 1024
        db 1,000h
        ds 45,0
        db "INA"
        dw 1024
        db 1,03Ch    ; INC A
        ds 45,0
        db "IDE"
        dw 1024
        db 1,013h    ; INC DE
        ds 45,0
        db "LDR"
        dw 1024
        db 1,07Eh    ; LD A,(HL)
        ds 45,0
        db "LDW"
        dw 1024
        db 1,077h    ; LD (HL),A
        ds 45,0
        db "ADN"
        dw 1024
        db 2,0C6h,001h    ; ADD A,1
        ds 44,0
        db "LHL"
        dw 1024
        db 3,021h,000h,000h    ; LD HL,0
        ds 43,0
        db "JR0"
        dw 1024
        db 2,018h,000h    ; JR +0
        ds 44,0
        db "EXS"
        dw 1024
        db 1,0E3h    ; EX (SP),HL
        ds 45,0
        db "NEG"
        dw 1024
        db 2,0EDh,044h    ; NEG (dos M1)
        ds 44,0
        db "IPP"
        dw 1024
        db 2,0DBh,0A8h    ; IN A,(A8h)
        ds 44,0
        db "IVD"
        dw 1024
        db 2,0DBh,098h    ; IN A,(98h)
        ds 44,0
        db "OUN"
        dw 1024
        db 2,0D3h,098h    ; OUT (98h),A
        ds 44,0
        db "OUC"
        dw 1024
        db 2,0EDh,079h    ; OUT (C),A
        ds 44,0
        db "OTI"
        dw 1024
        db 2,0EDh,0A3h    ; OUTI
        ds 44,0
plant_med:
        db "17T"
        dw 1024
        db 3,0D3h,098h,03Ch
        ds 43,0
        db "18T"
        dw 1024
        db 2,0EDh,0A3h
        ds 44,0
        db "19T"
        dw 1024
        db 3,0EDh,079h,03Ch
        ds 43,0
        db "20T"
        dw 1024
        db 4,0D3h,098h,0C6h,001h
        ds 42,0
        db "21T"
        dw 1024
        db 3,0EDh,059h,013h
        ds 43,0
        db "22T"
        dw 1024
        db 4,0EDh,079h,0C6h,001h
        ds 42,0
        db "23T"
        dw 1024
        db 3,0EDh,0A3h,03Ch
        ds 43,0
        db "24T"
        dw 1024
        db 4,0D3h,098h,03Ch,013h
        ds 42,0
        db "25T"
        dw 1024
        db 5,0D3h,098h,03Ch,006h,000h
        ds 41,0
        db "26T"
        dw 1024
        db 4,0EDh,079h,03Ch,013h
        ds 42,0
        db "27T"
        dw 1024
        db 5,0D3h,098h,03Ch,000h,000h
        ds 41,0
        db "28T"
        dw 1024
        db 6,0D3h,098h,03Ch,021h,000h,000h
        ds 40,0
        db "29T"
        dw 1024
        db 5,0EDh,079h,0C6h,001h,013h
        ds 41,0
        db "30T"
        dw 1024
        db 5,0D3h,098h,03Ch,018h,000h
        ds 41,0
        db "BWL"
        dw 128
        db 41,0D3h,098h,0C6h,001h,0D3h,098h,0C6h,001h,0D3h,098h,0C6h,001h,0D3h,098h,0C6h,001h,0D3h,098h,0C6h,001h,0D3h,098h,0C6h,001h,0D3h,098h,0C6h,001h,0D3h,098h,03Ch,021h,000h,000h,021h,000h,000h,021h,000h,000h,000h
        ds 5,0
        db "WME"
        dw 128
        db 45,0D3h,098h,03Ch,006h,000h,0D3h,098h,03Ch,006h,000h,0D3h,098h,03Ch,006h,000h,0D3h,098h,03Ch,006h,000h,0D3h,098h,03Ch,006h,000h,0D3h,098h,03Ch,006h,000h,0D3h,098h,03Ch,006h,000h,0D3h,098h,03Ch,021h,000h,000h,021h,000h,000h,013h
        ds 1,0
fin_prog:
