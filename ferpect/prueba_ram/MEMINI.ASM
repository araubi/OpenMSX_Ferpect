; MEMINI.COM - Vuelca a disco el contenido de la RAM tal como la deja el
; encendido, para ajustar <initialContent> en openMSX FERPECT.
; MSX-DOS 1/2 o Nextor. Ensamblar: pasmo MEMINI.ASM MEMINI.COM
;
; Uso:  MEMINI      vuelca la RAM del DOS (MEMINI.BIN) y despues lee, sin
;                   escribir nada, el resto de slots (MEMSLOT.BIN)
;       MEMINI N    solo MEMINI.BIN
;
; Formato: cabecera de 64 bytes y luego trozos: 8 bytes de cabecera
; ('C', tipo, segmento o slot, byte alto de la direccion, marca, 0,0,0)
; seguidos de 4096 bytes si marca = 0.
;   tipo 0 = direccion lineal de la RAM del DOS
;   tipo 1 = segmento del mapper visto en la pagina 2
;   tipo 2 = slot (ExxxSSPP) leido sin escribir
;   marca 0 = datos, 1 = todo FFh, 2 = es la RAM del DOS (ya volcada),
;         3 = no leido (pagina de una ROM de disco)

BDOS    equ     0005h
BUF0    equ     2000h           ; buffer en la pagina 0
COPA    equ     8000h           ; copia del copiador en la pagina 2
VARA    equ     8100h
BUFA    equ     9000h
MAXSEG  equ     64

        org     0100h
        jp      start
        db      "MEMINI-COM-MAGIC"

start:  ld      a,(0007h)
        cp      0B0h
        jr      nc,st1
        ld      de,m_tpa
        jp      print
st1:    ld      de,m_ban
        call    print
        ; opcion N
        ld      hl,0080h
        ld      b,(hl)
        inc     b
        jr      st3
st2:    inc     hl
        ld      a,(hl)
        and     0DFh
        cp      'N'
        jr      nz,st3
        ld      (noscan),a
st3:    djnz    st2
        ; cabecera
        in      a,(0A8h)
        ld      (h_a8),a
        ld      a,(0FFFFh)
        cpl
        ld      (h_ff),a
        ld      hl,0FCC1h
        ld      de,h_exp
        ld      bc,4
        ldir
        ld      hl,0F341h
        ld      de,h_ram
        ld      bc,4
        ldir
        ld      hl,0FB21h
        ld      de,h_drv
        ld      bc,8
        ldir
        ld      hl,(0006h)
        ld      (h_tpa),hl
        ld      (h_sp),sp
        ld      a,(0FCC1h)
        ld      hl,002Dh
        call    000Ch
        ei
        ld      (h_ver),a
        ld      b,0
        ld      c,6Fh
        call    BDOS
        ld      (h_dosa),a
        ld      a,b
        ld      (h_dosb),a
        call    detmap

; ---------------------------------------------------------------- parte 1
        call    crea
        ld      de,hdr
        ld      hl,64
        call    wr
        ld      hl,(h_segs)
        ld      a,h
        or      l
        jr      nz,mapper

        ; RAM sin mapper: 0000h-FFFFh
        xor     a
        ld      (c_kind),a
        dec     a
        ld      (c_seg),a
        xor     a
lin1:   ld      (c_hi),a
        cp      30h
        jr      c,lin2
        ld      h,a
        ld      l,0
        ld      de,BUF0
        ld      bc,1000h
        di
        ldir
        ei
        ld      de,BUF0
        jr      lin3
lin2:   ld      d,a
        ld      e,0
lin3:   call    wrchunk
        ld      a,(c_hi)
        add     a,10h
        jr      nz,lin1
        jp      fin1

mapper: ; primero el trozo que va a hacer de buffer
        xor     a
        ld      (c_kind),a
        dec     a
        ld      (c_seg),a
        ld      a,20h
        ld      (c_hi),a
        ld      de,BUF0
        call    wrchunk
        ld      a,1
        ld      (c_kind),a
        ld      hl,(h_segs)
        ld      de,MAXSEG
        or      a
        sbc     hl,de
        jr      c,map0
        ld      hl,0
map0:   add     hl,de           ; min(segs, MAXSEG)
        ld      a,l
        ld      (nseg),a
        xor     a
        ld      (c_seg),a
map1:   xor     a
map2:   ld      (c_hi),a
        or      80h
        ld      h,a
        ld      l,0
        ld      de,BUF0
        ld      bc,1000h
        di
        ld      a,(c_seg)
        out     (0FEh),a
        ldir
        ld      a,1
        out     (0FEh),a
        ei
        ld      de,BUF0
        call    wrchunk
        ld      a,(c_hi)
        add     a,10h
        cp      40h
        jr      nz,map2
        ld      a,(nseg)
        ld      b,a
        ld      a,(c_seg)
        inc     a
        ld      (c_seg),a
        cp      b
        jr      nz,map1

fin1:   call    cierra
        ld      de,m_ok1
        call    print
        ld      a,(noscan)
        or      a
        jp      nz,adios

; ---------------------------------------------------------------- parte 2
        ld      hl,name2
        ld      de,fcb+1
        ld      bc,11
        ldir
        ld      a,'S'
        ld      (hdr+3),a
        call    crea
        ld      de,hdr
        ld      hl,64
        call    wr
        ld      hl,copier
        ld      de,COPA
        ld      bc,copend-copier
        ldir
        ld      a,2
        ld      (c_kind),a
        xor     a
        ld      (s_prim),a
sc_prim:
        ld      a,(s_prim)
        ld      e,a
        ld      d,0
        ld      hl,h_exp
        add     hl,de
        ld      a,(hl)
        and     80h
        ld      (s_exp),a
        xor     a
        ld      (s_sec),a
sc_sec: ld      a,(s_sec)
        add     a,a
        add     a,a
        ld      b,a
        ld      a,(s_prim)
        or      b
        ld      b,a
        ld      a,(s_exp)
        or      b
        ld      (c_seg),a
        xor     a
        ld      (s_page),a
sc_page:
        ld      a,(s_page)
        rrca
        rrca
        ld      (c_hi),a
        ; es la RAM del DOS en esta pagina?
        ld      a,(s_page)
        ld      e,a
        ld      d,0
        ld      hl,h_ram
        add     hl,de
        ld      a,(c_seg)
        cp      (hl)
        ld      a,2
        jr      z,sc_skip
        ; pagina 1 o 2 de una ROM de disco?
        ld      a,(s_page)
        dec     a
        cp      2
        jr      nc,sc_read
        ld      hl,h_drv
        ld      b,4
sc_d1:  ld      a,(hl)
        inc     hl
        or      a
        jr      z,sc_d2
        ld      a,(c_seg)
        cp      (hl)
        ld      a,3
        jr      z,sc_skip
sc_d2:  inc     hl
        djnz    sc_d1
        jr      sc_read
sc_skip:
        ld      (c_flag),a
        ld      de,chdr
        ld      hl,8
        call    wr
        jp      sc_next
sc_read:
        ld      a,(s_page)
        cp      2
        jr      z,sc_b
        ld      iy,VARA
        ld      de,BUFA
        call    setup
        call    COPA
        ld      hl,BUFA
        jr      sc_chk
sc_b:   ld      iy,vars
        ld      de,BUF0
        call    setup
        call    copier
        ld      hl,BUF0
sc_chk: push    hl
        ld      bc,1000h
sc_c1:  ld      a,(hl)
        inc     a
        jr      nz,sc_dat
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,sc_c1
        pop     hl
        ld      a,1
        ld      (c_flag),a
        ld      de,chdr
        ld      hl,8
        call    wr
        jr      sc_c2
sc_dat: pop     de
        call    wrchunk
sc_c2:  ld      a,(c_hi)
        add     a,10h
        ld      (c_hi),a
        and     30h
        jr      nz,sc_read
sc_next:
        ld      a,(s_page)
        inc     a
        ld      (s_page),a
        cp      4
        jp      nz,sc_page
        ld      a,(s_exp)
        or      a
        jr      z,sc_np
        ld      a,(s_sec)
        inc     a
        ld      (s_sec),a
        cp      4
        jp      nz,sc_sec
sc_np:  ld      a,(s_prim)
        inc     a
        ld      (s_prim),a
        cp      4
        jp      nz,sc_prim
        call    cierra
        ld      de,m_ok2
        call    print
adios:  ld      de,m_fin
        call    print
        jp      0

; prepara las variables del copiador. IY = variables, DE = buffer
setup:  ld      a,(s_exp)
        ld      (iy+0),a
        ld      a,(s_prim)
        rrca
        rrca
        ld      (iy+1),a
        ld      a,(s_page)
        add     a,a
        ld      b,a
        ld      a,3
        call    desp
        cpl
        ld      (iy+2),a
        ld      (iy+4),a
        ld      a,(s_sec)
        call    desp
        ld      (iy+3),a
        ld      a,(s_prim)
        call    desp
        ld      (iy+5),a
        ld      (iy+6),0
        ld      a,(c_hi)
        ld      (iy+7),a
        ld      (iy+8),e
        ld      (iy+9),d
        ret
desp:    push    bc
        inc     b
        jr      shl2
shl1:   add     a,a
shl2:   djnz    shl1
        pop     bc
        ret

; Copiador: independiente de la posicion y sin pila mientras cambia slots.
copier: di
        in      a,(0A8h)
        ld      (iy+10),a
        ld      a,(iy+0)
        or      a
        jr      z,cop1
        ld      a,(iy+10)
        and     3Fh
        or      (iy+1)
        out     (0A8h),a
        ld      a,(0FFFFh)
        cpl
        ld      (iy+11),a
        and     (iy+2)
        or      (iy+3)
        ld      (0FFFFh),a
cop1:   ld      a,(iy+10)
        and     (iy+4)
        or      (iy+5)
        out     (0A8h),a
        ld      l,(iy+6)
        ld      h,(iy+7)
        ld      e,(iy+8)
        ld      d,(iy+9)
        ld      bc,1000h
        ldir
        ld      a,(iy+0)
        or      a
        jr      z,cop2
        ld      a,(iy+10)
        and     3Fh
        or      (iy+1)
        out     (0A8h),a
        ld      a,(iy+11)
        ld      (0FFFFh),a
cop2:   ld      a,(iy+10)
        out     (0A8h),a
        ei
        ret
copend:

; cuenta los segmentos del mapper de la RAM del DOS (0 = no hay mapper)
detmap: di
        ld      a,1
        call    alias
        ld      hl,0
        jr      z,dm3
        ld      a,4
dm1:    ld      (tmp),a
        call    alias
        jr      z,dm2
        ld      a,(tmp)
        add     a,a
        jr      nz,dm1
        ld      hl,256
        jr      dm3
dm2:    ld      a,(tmp)
        ld      l,a
        ld      h,0
dm3:    ld      (h_segs),hl
        ld      a,1
        out     (0FEh),a
        ei
        ret
; Z si el segmento A es el mismo que el 0. Deja todo como estaba.
alias:  ld      hl,8000h
        ld      d,a
        out     (0FEh),a
        ld      b,(hl)
        ld      a,b
        cpl
        ld      (hl),a
        ld      e,a
        xor     a
        out     (0FEh),a
        ld      c,(hl)
        ld      a,d
        out     (0FEh),a
        ld      (hl),b
        xor     a
        out     (0FEh),a
        ld      a,(hl)
        cp      b
        ret     nz
        ld      a,c
        cp      e
        ret

; ---------------------------------------------------------------- disco
crea:   ld      hl,fcb+12
        ld      b,25
cr1:    ld      (hl),0
        inc     hl
        djnz    cr1
        ld      de,fcb
        ld      c,16h
        call    BDOS
        or      a
        jr      nz,errd
        ld      hl,1
        ld      (fcb+14),hl
        ld      hl,0
        ld      (fcb+33),hl
        ld      (fcb+35),hl
        ret
cierra: ld      de,fcb
        ld      c,10h
        jp      BDOS
; escribe la cabecera del trozo (marca 0) y 4096 bytes desde DE
wrchunk:
        push    de
        xor     a
        ld      (c_flag),a
        ld      de,chdr
        ld      hl,8
        call    wr
        pop     de
        ld      hl,1000h
        call    wr
        ld      e,'.'
        ld      c,2
        jp      BDOS
; escribe HL bytes desde DE
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
        call    cierra
        jp      0
print:  ld      c,9
        jp      BDOS

m_ban:  db      "MEMINI 1.0 - volcado de la RAM",13,10,"$"
m_tpa:  db      "Falta memoria (TPA).",13,10,"$"
m_ok1:  db      13,10,"MEMINI.BIN escrito.",13,10,"$"
m_ok2:  db      13,10,"MEMSLOT.BIN escrito.",13,10,"$"
m_fin:  db      "Fin.",13,10,"$"
m_err:  db      13,10,"Error de disco (lleno o protegido).",13,10,"$"
name2:  db      "MEMSLOT BIN"
fcb:    db      0,"MEMINI  BIN"
        ds      26
noscan: db      0
tmp:    db      0
nseg:   db      0
s_prim: db      0
s_sec:  db      0
s_page: db      0
s_exp:  db      0
vars:   ds      12
chdr:   db      "C"
c_kind: db      0
c_seg:  db      0
c_hi:   db      0
c_flag: db      0
        db      0,0,0
hdr:    db      "MEMINI1",0     ; +0
h_a8:   db      0               ; +8
h_ff:   db      0               ; +9
h_exp:  ds      4               ; +10
h_ram:  ds      4               ; +14
h_drv:  ds      8               ; +18
h_tpa:  dw      0               ; +26
h_sp:   dw      0               ; +28
h_ver:  db      0               ; +30
h_dosa: db      0               ; +31
h_dosb: db      0               ; +32
h_segs: dw      0               ; +33
        ds      29
