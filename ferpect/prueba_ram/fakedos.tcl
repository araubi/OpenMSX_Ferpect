set throttle off
set ::dma 0
set ::f ""
proc bdos {} {
  set c [reg C]; set de [reg DE]
  switch $c {
    22 { set n [string trim [debug read_block memory [expr {$de+1}] 8]].[debug read_block memory [expr {$de+9}] 3]
         set ::f [open $::env(OUTDIR)/$n w]; fconfigure $::f -translation binary; reg A 0 }
    26 { set ::dma $de }
    38 { puts -nonewline $::f [debug read_block memory $::dma [reg HL]]; reg A 0 }
    16 { close $::f; reg A 0 }
    2  { }
    9  { set s ""; set a $de; while {[peek $a] != 36} { append s [format %c [peek $a]]; incr a }; puts stderr "DOS: $s" }
  }
}
proc arranca {} {
  if {[catch {
  debug write ioports 0xA8 0xFF
  if {$::env(RAMSLOT) == "135"} { debug write memory 0xFFFF 0x55 }
  set f [open $::env(COM) r]; fconfigure $f -translation binary; set d [read $f]; close $f
  debug write_block memory 0x100 $d
  poke 0x0005 0xC9
  poke 0x000C 0xC9
  poke 0x0080 0
  foreach a {0xF341 0xF342 0xF343 0xF344} { poke $a $::env(RAMSLOT) }
  poke16 0x0006 0xDE00
  debug write_block memory 0x38 [binary format c* {0xF5 0xDB 0x99 0xF1 0xFB 0xC9}]
  poke 0x0000 0x76
  set g [open $::env(OUTDIR)/ref.bin w]; fconfigure $g -translation binary
  puts -nonewline $g [debug read_block $::env(RAMDBG) 0 [debug size $::env(RAMDBG)]]; close $g
  debug set_bp 0x0005 {} bdos
  debug set_bp 0x0000 {} {puts stderr "FIN [machine_info time]"; exit}
  reg SP 0xDE00
  reg PC 0x0100
  puts stderr "arranco en [machine_info time]"
  } e]} { puts stderr "ERROR $e [debug list]"; exit }
}
after time 6 arranca
after time 300 {puts stderr "TIEMPO AGOTADO"; exit}
