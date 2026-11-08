# poll_status.tcl -- ASCII only. Run from the project root in the HW Manager Tcl Console.
#     source ilaset/poll_status.tcl
#
# Reads the vs_shift status register repeatedly and prints a timestamped trace,
# so a transient LOAD (normal: the SPI load takes ~309 ms) can be told apart from
# a PRC that is permanently stuck in LOAD.
#
# USAGE: source this script FIRST, let it print the baseline, then press key2
# (reset), wait for the LED walk, then press key1 EXACTLY ONCE while the polling
# is still running. The trace shows what the PRC does across the whole load.

source Sources/scripts/axi_lite_procs.tcl
prc_jtag_setup

proc fmt_status {s} {
    set code   [expr {$s & 7}]
    set err    [expr {($s & 120) / 8}]
    set shut   [expr {($s & 128) / 128}]
    set rmid   [expr {($s & 16776960) / 256}]
    set names  {EMPTY HW_SHUTDOWN SW_SHUTDOWN CLEAR LOAD SW_STARTUP RM_RESET FULL}
    set cname  [lindex $names $code]
    if {$cname eq ""} { set cname "?" }
    return [format "code=%d(%-11s) err=%d shutdown=%d rm_id=%d" $code $cname $err $shut $rmid]
}

set t0 [clock milliseconds]
puts "baseline (do not press anything yet):"
for {set i 0} {$i < 3} {incr i} {
    set s [prc_read_register vs_shift_status]
    puts [format "  t=%7d ms  status=0x%03X  %s" [expr {[clock milliseconds]-$t0}] $s [fmt_status $s]]
}

puts ""
puts ">>> NOW: press key2 (reset), wait for the LED walk, then press key1 ONCE."
puts ">>> Polling for ~20 s ..."
puts ""

set last -1
for {set i 0} {$i < 60} {incr i} {
    if {[catch {set s [prc_read_register vs_shift_status]} e]} {
        puts "  read failed: $e"
        after 300
        continue
    }
    set el [expr {[clock milliseconds]-$t0}]
    if {$s != $last} {
        puts [format "  t=%7d ms  status=0x%03X  %s   <-- CHANGED" $el $s [fmt_status $s]]
        set last $s
    } else {
        puts [format "  t=%7d ms  status=0x%03X  %s" $el $s [fmt_status $s]]
    }
    after 300
}

puts ""
puts "interpretation:"
puts "  LOAD(4) -> FULL(7) within ~1 s of key1 : the PRC completes normally,"
puts "                                           so the fault is in the FRAME CONTENT."
puts "  LOAD(4) held for the whole 20 s        : the PRC never finishes the load;"
puts "                                           the ICAP is not draining / errored."
