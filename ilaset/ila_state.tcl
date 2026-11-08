# ila_state.tcl - READ-ONLY dump of the current Hardware Manager ILA setup.
#
# Run from the project root in the Vivado Hardware Manager Tcl Console:
#     source ilaset/ila_state.tcl
#
# Nothing here WRITES a trigger value, so it works even though
# set_property TRIGGER_COMPARE_VALUE is blocked on this design. The point is
# to answer three questions:
#   1. is the core actually ARMED, or is it sitting on an old capture?
#   2. which hw_ila_N is the AXI/SPI core in the design currently on the board?
#   3. what did the GUI actually encode for the value you typed?

proc gp {obj prop} {
    if {[catch { get_property $prop $obj } v]} { return "<n/a>" }
    return $v
}

if {[llength [get_hw_devices]] == 0} { open_hw_manager; connect_hw_server; open_hw_target }
set dev [current_hw_device]
puts "device = $dev"
refresh_hw_device $dev

puts "=============================================================="
puts " hw_ila cores (the hw_ila_N numbering is NOT stable across builds)"
foreach i [get_hw_ilas] {
    puts "---- $i"
    foreach pn {STATE TRIGGER_STATUS TRIGGER_MATCH_TYPE CONTROL.TRIGGER_POSITION CONTROL.STATE SAMPLE_COUNT WINDOW_COUNT} {
        puts [format "     %-26s = %s" $pn [gp $i $pn]]
    }
    puts "     probes:"
    foreach p [get_hw_probes -of_objects $i] {
        puts [format "       %-26s width=%-3s cmp='%s'" $p [gp $p WIDTH] [gp $p TRIGGER_COMPARE_VALUE]]
    }
}

puts "=============================================================="
puts " the AXI/SPI bitstream-fetch core:"
set found 0
foreach i [get_hw_ilas] {
    set pns [get_hw_probes -of_objects $i]
    if {[lsearch -glob $pns "*m_axi_mem_araddr*"] >= 0} {
        set found 1
        puts "   core            = $i"
        puts "   state           = [gp $i STATE] / [gp $i TRIGGER_STATUS]"
        set pa [get_hw_probes m_axi_mem_araddr -of_objects $i]
        puts "   araddr probe    = $pa"
        puts "   araddr width    = [gp $pa WIDTH]"
        puts "   araddr cmp now  = '[gp $pa TRIGGER_COMPARE_VALUE]'"
        puts "   arvalid probe   = [get_hw_probes m_axi_mem_arvalid_v -of_objects $i]"
        puts "   trigger_pos     = [gp $i CONTROL.TRIGGER_POSITION]"
    }
}
if {!$found} {
    puts "   NOT FOUND - the design on the board has no m_axi_mem_araddr probe."
    puts "   That means the board is not running the expected build, or the ltx"
    puts "   associated with the device is from a different build."
    puts "   associated ltx = [gp $dev PROBES_FILE]"
}

puts "=============================================================="
puts " How to read this:"
puts "   STATE / TRIGGER_STATUS must read ARMED before you press key1."
puts "   If it reads TRIGGERED or STOPPED the GUI is showing an OLD capture"
puts "   and will never fire again until you press Run Trigger."
puts "   'araddr cmp now' shows exactly what the GUI stored for the value"
puts "   you typed - it should read 00AEAXXX (or equivalent), not B5FXXXXX."
puts "   'araddr width' should be 32; the value box needs all 8 hex digits."
puts "=============================================================="
