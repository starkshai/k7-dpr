# capture_icap.tcl -- ASCII only.
# Run from the project root in the Vivado Hardware Manager Tcl Console:
#     source ilaset/capture_icap.tcl
#
# Arms the ICAP ILA on a FALLING EDGE of icap_csib_v (the first ICAP write),
# waits for one key1 press, and saves the capture to ilaset/ila_icap_capture.zip
# (write_hw_ila_data always produces a ZIP; parse it with ilaset/parse_ila_zip.py).
#
# Edge triggering uses TRIGGER_MATCH_TYPE, not TRIGGER_COMPARE_VALUE -- the
# earlier attempts all failed because they tried to set a compare value.

open_hw
connect_hw_server

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev

catch {set_property PROBES_FILE {Bitstreams/config_shift_right.ltx} $dev}
catch {set_property FULL_PROBES_FILE {Bitstreams/config_shift_right.ltx} $dev}
refresh_hw_device $dev

# ---- find the ICAP core by probe name (hw_ila_N numbering is not stable)
set ila ""
set csib ""
foreach c [get_hw_ilas -of_objects $dev] {
    foreach p [get_hw_probes -of_objects $c] {
        if {[string match "*icap_csib_v*" $p]} {
            set ila $c
            set csib $p
        }
    }
}
if {$ila eq ""} {
    puts "ERROR: no ILA exposing icap_csib_v. Known cores:"
    foreach c [get_hw_ilas -of_objects $dev] {
        puts "  $c : [get_hw_probes -of_objects $c]"
    }
    return
}
puts "ICAP ILA  = $ila"
puts "csib probe = $csib"

# ---- dump the current trigger setup of every probe on this core
puts "--- trigger setup BEFORE ---"
foreach p [get_hw_probes -of_objects $ila] {
    set mt "?"
    set cv "?"
    catch {set mt [get_property TRIGGER_MATCH_TYPE $p]}
    catch {set cv [get_property TRIGGER_COMPARE_VALUE $p]}
    puts [format "  %-24s match=%-14s compare=%s" $p $mt $cv]
}

# ---- what does this Vivado accept for TRIGGER_MATCH_TYPE?
puts "--- legal TRIGGER_MATCH_TYPE values ---"
catch {puts "  [list_property_value TRIGGER_MATCH_TYPE $csib]"}

# ---- arm: falling edge on csib, trigger at sample 0
if {[catch {set_property TRIGGER_MATCH_TYPE {BASIC_EDGE} $csib} e]} {
    puts "set TRIGGER_MATCH_TYPE BASIC_EDGE failed: $e"
    puts "Cannot arm from Tcl -- use the GUI: probe icap_csib_v, edge F, position 0."
    return
}
# For BASIC_EDGE the direction is carried by the compare value; try both forms.
if {[catch {set_property TRIGGER_COMPARE_VALUE {F} $csib} e2]} {
    puts "compare {F} rejected: $e2"
    catch {set_property TRIGGER_COMPARE_VALUE {EQ1'b0} $csib} e3
    puts "compare EQ1'b0 result: $e3"
}
catch {set_property CONTROL.TRIGGER_POSITION 0 $ila}

puts "--- trigger setup AFTER ---"
set mt "?"
set cv "?"
catch {set mt [get_property TRIGGER_MATCH_TYPE $csib]}
catch {set cv [get_property TRIGGER_COMPARE_VALUE $csib]}
puts [format "  %-24s match=%-14s compare=%s" $csib $mt $cv]
catch {puts "  TRIGGER_POSITION = [get_property CONTROL.TRIGGER_POSITION $ila]"}
catch {puts "  STATE = [get_property STATE $ila]"}

puts ""
puts ">>> ARMED. Now: press key2 (reset), wait for the LED walk to return,"
puts ">>> confirm the walk, then press key1 EXACTLY ONCE."
puts ""

run_hw_ila $ila
if {[catch {wait_on_hw_ila -timeout 60 $ila} ew]} {
    puts "wait_on_hw_ila: $ew"
}
puts "STATE after wait = [get_property STATE $ila]"

set d [current_hw_ila_data]
puts "ila_data object = $d"
if {[catch {write_hw_ila_data -force ilaset/ila_icap_capture.zip $d} ew2]} {
    puts "write_hw_ila_data failed: $ew2"
    return
}
puts "saved ilaset/ila_icap_capture.zip"
puts "next: python ilaset/parse_ila_zip.py"
