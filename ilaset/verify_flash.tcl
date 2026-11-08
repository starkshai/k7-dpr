# ============================================================================
# verify_flash.tcl - source in Vivado Hardware Manager Tcl Console
#
# ZERO-REBUILD confirmation step. Reads the whole SPI flash back over JTAG
# (indirect programming bridge) and compares it against Bitstreams/pr_prom.mcs
# WITHOUT erasing or programming. Goal: prove the flash bytes at and after
# 0xB2B544 (bitstream word 66897, where the fabric-side read dies) are
# physically intact. If VERIFY passes, the failure is concurrent-access
# contention, not corrupted flash data.
#
#   cd C:/wmx/FPGA/ug947-vivado-partial-reconfiguration-tutorial/myprc
#   source ilaset/verify_flash.tcl
#
# Takes a few minutes for a 16 MB device. ASCII only on purpose.
# ============================================================================

set mcs "Bitstreams/pr_prom.mcs"
if {![file exists $mcs]} { puts "ERROR: $mcs not found"; return }

if {[llength [get_hw_targets]] == 0} { open_hw_manager }
if {[llength [get_hw_servers]] == 0} { connect_hw_server }
if {[llength [get_hw_targets]] == 0} { open_hw_target }

set dev [lindex [get_hw_devices -filter {NAME =~ "*xc7k325t*"}] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev
refresh_hw_device $dev

# MT25QL128 (formerly N25Q128): the actual flash on this board. Pick it from
# the device-compatible list (a wrong vendor part uses wrong read commands).
set devPart [get_property PART $dev]
set compat [get_cfgmem_parts -of [get_parts $devPart]]
set part ""
foreach want {mt25ql128-spi-x1_x2_x4 mt25qu128-spi-x1_x2_x4} {
    foreach p $compat {
        if {$p eq $want} { set part $p; break }
    }
    if {$part ne ""} { break }
}
if {$part eq ""} {
    puts "ERROR: mt25ql128 not in compatible list for $devPart. Compatible 128Mb parts:"
    foreach p $compat { if {[string match *128*spi* $p]} { puts "  $p" } }
    return
}
puts "selected cfgmem part: $part"

# Attach a fresh cfgmem object to the device.
catch {delete_hw_cfgmem [get_hw_cfgmem -of_objects $dev -quiet]}
set cfg [create_hw_cfgmem -hw_device $dev $part]

set_property PROGRAM.FILE       $mcs        $cfg
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfg
# Read-only: never erase, never blank-check, never program. VERIFY only.
set_property PROGRAM.ERASE        0 $cfg
set_property PROGRAM.BLANK_CHECK  0 $cfg
set_property PROGRAM.CFG_PROGRAM  0 $cfg
set_property PROGRAM.VERIFY       1 $cfg

puts "Running verify-only (program_hw_cfgmem with VERIFY=1) against $mcs ..."
puts "(this reads the entire flash back; please wait)"
if {[catch {program_hw_cfgmem $cfg} result]} {
    puts "VERIFY returned an error:"
    puts $result
} else {
    puts ""
    puts ">>> verify finished. <<<"
    puts $result
}
puts ""
puts "INTERPRETATION:"
puts "  PASS / no mismatch  -> flash bytes intact incl. 0xB2B544 -> contention, not bad data"
puts "  mismatch near 0xB2B544 -> flash data itself is wrong -> revisit MCS build/burn"
puts ""
puts "NOTE: after this, do a FULL power cycle before any further SPI capture"
puts "      (JTAG indirect leaves the flash in x4/continuous-read mode)."
