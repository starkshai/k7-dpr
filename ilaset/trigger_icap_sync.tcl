# ============================================================================
# trigger_icap_sync.tcl - source in Vivado Hardware Manager Tcl Console
# One-shot: connect -> find ICAP ILA by probe names -> arm trigger ->
#           capture stream start (incl. sync word) -> save + print first writes
#
# Usage:
#   1. Board booted from SPI with the 14:34 pr_prom.mcs (LED shifting right)
#   2. JTAG connected (do NOT download a bitstream)
#   3. In Tcl Console:  cd <project root>  then  source ilaset/trigger_icap_sync.tcl
#   4. When prompted, press key1 (key2/reset released). Wait up to ~310 ms.
#   5. Result saved to ilaset/iladata3_sync.csv; first 20 ICAP writes printed.
# ============================================================================

if {[llength [get_hw_targets]] == 0} { open_hw_manager }
if {[llength [get_hw_servers]] == 0} { connect_hw_server }
if {[llength [get_hw_targets]] == 0} { open_hw_target }

set dev [lindex [get_hw_devices -filter {NAME =~ "*xc7k325t*"}] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev
refresh_hw_device $dev

# Locate the ICAP ILA by its probe names (hw_ila NAME is just hw_ila_N)
set ila ""
foreach i [get_hw_ilas] {
    set pn [get_hw_probes -of_objects $i]
    puts "$i probes: $pn"
    if {[lsearch -glob $pn "*icap_csib_v*"] >= 0} { set ila $i }
}
if {$ila eq ""} {
    puts "ERROR: ICAP ILA not found among: [get_hw_ilas]"
    return
}
puts "Using ILA: $ila"

# Trigger on the first ICAP write = falling edge of csib (1->0).
# NOTE: this Vivado version rejects EQ/value formats for 1-bit probes
# ("EQ 1'b0", "1'b0", "EQ1'b0" all fail); the edge code F works.
set csib [lindex [get_hw_probes -of_objects $ila -filter {NAME =~ "*icap_csib_v*"}] 0]
set_property TRIGGER_COMPARE_VALUE {F} $csib

# Capture from the first write if possible. The property name varies by
# version: TRIGGER_POSITION or CONTROL.TRIGGER_POSITION. If neither exists,
# the default mid-window position still works: each ICAP write takes ~256
# clocks (2.56 us at 100 MHz), so 8192 post-trigger samples ~= 32 words,
# and the sync word is word 12 (~3072 samples after the trigger).
set props [list_property $ila]
if {[lsearch -exact $props "CONTROL.TRIGGER_POSITION"] >= 0} {
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    puts "Trigger position set to 0 (CONTROL.TRIGGER_POSITION)"
} elseif {[lsearch -exact $props "TRIGGER_POSITION"] >= 0} {
    set_property TRIGGER_POSITION 0 $ila
    puts "Trigger position set to 0 (TRIGGER_POSITION)"
} else {
    puts "WARN: no trigger-position property; keeping default (mid-window)"
}

run_hw_ila $ila
puts "Trigger armed. Press key1 NOW (key2/reset released). Waiting..."

wait_on_hw_ila $ila

write_hw_ila_data -force ilaset/iladata3_sync.csv [current_hw_ila_data]
puts "Saved ilaset/iladata3_sync.csv"

# Print the first 20 ICAP writes with their status nibble
set d [current_hw_ila_data]
set rows [get_hw_ila_data $d]
set n 0
foreach r $rows {
    set cv ""; set iv ""; set sv ""
    foreach {k v} $r {
        if {[string match {*icap_csib_v*} $k]}  { set cv $v }
        if {[string match {*icap_i\[*}    $k]}  { set iv $v }
        if {[string match {*icap_status*} $k]}  { set sv $v }
    }
    if {$cv eq "0" || $cv eq "1'b0" || $cv eq "0'b0"} {
        puts [format "write %2d: icap_i=%s status=%s" $n $iv $sv]
        incr n
        if {$n >= 20} break
    }
}
puts "Done. Expect: word12 sync = 0xAA995566 (fix#5 OK) or 0x66AA9955 (old build)."
puts "Expect: status 9 before sync, D after sync (DALIGN=1)."
