# JTAG-load the RESET_AFTER_RECONFIG=0 experimental partial (no IPROG).
# Decisive: does it still configure the RM (LED walks left)?
#   LED walks left  -> RESET=0 partial is a valid RM image -> proceed to full rebuild with RESET=0
#   LED frozen/unchanged -> RESET=0 partial is broken -> keep RESET=1, different fix
set bit "ilaset/exp/test_reset0.bit"
if {![file exists $bit]} { puts "ERROR: $bit not found"; return }
if {[llength [get_hw_targets]] == 0} { open_hw_manager }
if {[llength [get_hw_servers]] == 0} { connect_hw_server }
if {[llength [get_hw_targets]] == 0} { open_hw_target }
set dev [lindex [get_hw_devices -filter {NAME =~ "*xc7k325t*"}] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_device $dev
refresh_hw_device $dev
puts ">>> Loaded test_reset0.bit. Watch LEDs: walking left = valid RM; frozen = broken. <<<"