# probe_props.tcl - dump the real ILA trigger properties so the compare-value
# syntax can be discovered instead of guessed.
#
# Run from the project root in the Vivado Hardware Manager Tcl Console:
#     source ilaset/probe_props.tcl
#
# Why this exists: 'get_hw_probes X -of_objects hw_ila_3' fails with
#   ERROR: [Common 17-161] Invalid option value 'hw_ila_3' specified for 'of_objects'
# because -of_objects needs an hw_ila OBJECT, not its name string. After any
# program_hw_device the hw_ila objects are also stale and must be refreshed.

if {[llength [get_hw_devices]] == 0} { open_hw_manager; connect_hw_server; open_hw_target }
set dev [current_hw_device]
puts "device = $dev"

refresh_hw_device $dev

puts "=============================================================="
puts " ILA cores after refresh:"
foreach i [get_hw_ilas] {
    puts "   $i : [get_hw_probes -of_objects $i]"
}
puts "=============================================================="

# Find the ICAP core by probe name (hw_ila_N numbering is not stable).
set ila_icap ""
foreach i [get_hw_ilas] {
    if {[lsearch -glob [get_hw_probes -of_objects $i] "*icap_csib*"] >= 0} {
        set ila_icap $i
    }
}
if {$ila_icap eq ""} {
    puts "FATAL: ICAP ILA not found"
    return
}
puts "ICAP ILA object = $ila_icap"

foreach pn {icap_csib_v icap_status icap_rdwrb_v} {
    set p [get_hw_probes $pn -of_objects $ila_icap]
    puts "---- $pn  ($p)"
    puts "   properties: [list_property $p]"
    puts "   TRIGGER_COMPARE_VALUE now = '[get_property TRIGGER_COMPARE_VALUE $p]'"
    puts "   legal values = '[list_property_value TRIGGER_COMPARE_VALUE $p]'"
    foreach cand {{EQ1'b0} {R1'b1} {R} {N} {F}} {
        catch { set_property TRIGGER_COMPARE_VALUE $cand $p } e
        puts "   set $cand -> [expr {$e eq "" ? {OK} : "ERR: $e"}]"
    }
}
puts "=============================================================="
puts " paste ALL of the above back"
