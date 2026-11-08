# ============================================================================
# read_status.tcl - source in Vivado Hardware Manager Tcl Console
# Prints the PRC status register. Run it BEFORE and AFTER pressing key1.
#
#   cd C:/wmx/FPGA/ug947-vivado-partial-reconfiguration-tutorial/myprc
#   source ilaset/read_status.tcl
#
# 0x107 = FULL, rm_id 1 (shift_right, POR)
# 0x007 = FULL, rm_id 0 (shift_left loaded)  <-- this is what a working PR gives
# 0x004 = LOAD (reconfiguration in progress)
# ============================================================================
if {[llength [get_hw_targets]] == 0} { open_hw_manager }
if {[llength [get_hw_servers]] == 0} { connect_hw_server }
if {[llength [get_hw_targets]] == 0} { open_hw_target }
set dev [lindex [get_hw_devices -filter {NAME =~ "*xc7k325t*"}] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev

source Sources/scripts/axi_lite_procs.tcl
prc_jtag_setup
puts "-------- vs_shift status --------"
prc_decode_status vs_shift
