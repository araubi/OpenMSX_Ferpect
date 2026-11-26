; VRAMINI.COM - Vuelca a disco la VRAM tal como esta al ejecutarlo, para ver
; que queda del encendido en las zonas que la BIOS y el DOS no escriben.
; MSX-DOS 1/2 o Nextor. Ensamblar: pasmo VRAMINI.ASM VRAMINI.COM
; Solo lee. Archivo VRAMINI.BIN: cabecera de 32 bytes ("VRAMINI1", version de
; MSX, R#0-R#7 segun la BIOS, KB volcados) y luego la VRAM en crudo:
; 16 KB en MSX1, 128 KB en MSX2 o superior.
BDOS    equ     0005h
BUF     equ     2000h

        org     0100h
        ld      de,m_ban
        call    print
        ld      a,(0FCC1h)
        ld      hl,002Dh
        call    000Ch           ; RDSLT: version de MSX
        ld      (h_ver),a
        ld      a,(0FCC1h)
        ld      hl,0006h
        call    000Ch           ; puerto de lectura del VDP
        ei
        ld      (prd),a
        inc     a
        ld      (pwr),a
        ld      hl,0F3DFh
        ld      de,h_reg
        ld      bc,8
        ldir
        ld      a,(h_ver)
        or      a
        ld      a,4             ; 4 trozos de 4 KB
        jr      z,v1
        ld      a,32
v1:     ld      (ntro),a
        add     a,a
        add     a,a
        ld      (h_kb),a
        ld      de,fcb
        ld      c,16h
        call    BDOS
        or      a
        jp      nz,errd
        ld      hl,1
        ld      (fcb+14),hl
        dec     hl
        ld      (fcb+33),hl
        ld      (fcb+35),hl
        ld      de,hdr
        ld      hl,32
        call    wr
        xor     a
        ld      (tro),a
bucle:  ld      a,(tro)         ; trozo n: direccion n*1000h
        ld      b,a
        di
        ld      a,(h_ver)
        or      a
        jr      z,b1
        ld      a,b             ; R#14 = bits 16-14 de la direccion
        rrca
        rrca
        and     7
        call    outc
        ld      a,80h+14
        call    outc
b1:     xor     a
        call    outc
        ld      a,b
        and     3
        add     a,a
        add     a,a
        add     a,a
        add     a,a             ; bits 13-12
        call    outc
        ei
        ld      hl,BUF
        ld      de,1000h
        ld      a,(prd)
        ld      c,a
b2:     ini                     ; 16+ ciclos mas el bucle: sobra tiempo
        nop
        nop
        dec     de
        ld      a,d
        or      e
        jr      nz,b2
        ld      de,BUF
        ld      hl,1000h
        call    wr
        ld      e,'.'
        ld      c,2
        call    BDOS
        ld      a,(ntro)
        ld      b,a
        ld      a,(tro)
        inc     a
        ld      (tro),a
        cp      b
        jr      nz,bucle
        ld      a,(h_ver)
        or      a
        jr      z,fin
        di
        xor     a               ; deja R#14 a 0
        call    outc
        ld      a,80h+14
        call    outc
        ei
fin:    ld      de,fcb
        ld      c,10h
        call    BDOS
        ld      de,m_ok
        call    print
        jp      0
outc:   push    bc
        ld      c,a
        ld      a,(pwr)
        ld      b,a
        ld      a,c
        ld      c,b
        out     (c),a
        pop     bc
        ret
wr:     push    hl
        ld      c,1Ah
        call    BDOS
        pop     hl
        ld      de,fcb
        ld      c,26h
        call    BDOS
        or      a
        ret     z
errd:   ld      de,m_err
        call    print
        ld      de,fcb
        ld      c,10h
        call    BDOS
        jp      0
print:  ld      c,9
        jp      BDOS
m_ban:  db      "VRAMINI 1.0 - volcado de la VRAM",13,10,"$"
m_ok:   db      13,10,"VRAMINI.BIN escrito.",13,10,"$"
m_err:  db      13,10,"Error de disco.",13,10,"$"
prd:    db      98h
pwr:    db      99h
tro:    db      0
ntro:   db      4
fcb:    db      0,"VRAMINI BIN"
        ds      26
hdr:    db      "VRAMINI1"
h_ver:  db      0
h_reg:  ds      8
h_kb:   db      0
        ds      14
