# ============================================================================
# diag_pr.tcl - source in Vivado Hardware Manager Tcl Console
#
# Arms two ILA cores, then you press key1 ONCE. Both capture the same event.
#
#   ICAP ILA : icap_csib_v == 0  -> the first ICAP write of the load.
#              One word takes ~256 clocks (2.56 us) so the 16384-sample
#              window (164 us) covers roughly the first 64 words: preamble,
#              sync word (word 12) and the first packets, with icap_status.
#   VS ILA   : vs_shift_rm_reset_v == 1 -> rm_reset is pulsed by the PRC at
#              the END of every reconfiguration (RESET_REQUIRED = high), so
#              this fires at the moment the load finishes and the window then
#              shows whether rm_reset is left stuck high (which would hold the
#              RM's BRAM output and freeze the LED) and what axis_status does.
#
# This Vivado rejects bare edge codes ("F", "N") for TRIGGER_COMPARE_VALUE and
# wants the EQ<width>'<radix><value> form, so the script prints the legal
# values for each probe and tries candidates until one is accepted.
#
#   cd C:/wmx/FPGA/ug947-vivado-partial-reconfiguration-tutorial/myprc
#   source ilaset/diag_pr.tcl
#
# Output: ilaset/pr_icap.csv and ilaset/pr_vs_after.csv
# (write_hw_ila_data produces a zip containing waveform.csv; parsed offline.)
# ============================================================================

if {[llength [get_hw_targets]] == 0} { open_hw_manager }
if {[llength [get_hw_servers]] == 0} { connect_hw_server }
if {[llength [get_hw_targets]] == 0} { open_hw_target }
set dev [lindex [get_hw_devices -filter {NAME =~ "*xc7k325t*"}] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev
set ltx "ilaset/ltx_fix6_1703.ltx"
if {![file exists $ltx]} { set ltx "Bitstreams/config_shift_right.ltx" }
if {[file exists $ltx]} {
    set_property PROBES_FILE      $ltx $dev
    set_property FULL_PROBES_FILE $ltx $dev
}
refresh_hw_device $dev

set ila_vs ""; set ila_icap ""
foreach i [get_hw_ilas] {
    set pn [get_hw_probes -of_objects $i]
    if {[lsearch -glob $pn "*rm_decouple*"] >= 0} { set ila_vs   $i }
    if {[lsearch -glob $pn "*icap_csib*"]   >= 0} { set ila_icap $i }
}
puts "VS ILA   = $ila_vs"
puts "ICAP ILA = $ila_icap"
if {$ila_vs eq "" || $ila_icap eq ""} { puts "ERROR: ILA not found"; return }

# ---------------------------------------------------------------------------
# Apply the first compare value the tool accepts, and report what it allows.
# ---------------------------------------------------------------------------
proc set_compare {probe cands} {
    set legal {}
    catch { set legal [list_property_value TRIGGER_COMPARE_VALUE $probe] }
    puts "  legal values for $probe:"
    puts "    $legal"
    foreach c $cands {
        if {[catch { set_property TRIGGER_COMPARE_VALUE $c $probe } err]} {
            puts "    rejected: $c"
        } else {
            puts "    ACCEPTED: $c"
            return 1
        }
    }
    # Last resort: take a legal value that means the same thing.
    foreach v $legal {
        if {[string match {*EQ*} $v]} {
            catch { set_property TRIGGER_COMPARE_VALUE $v $probe }
            puts "    fallback: $v"
            return 1
        }
    }
    puts "    FAILED to set any compare value"
    return 0
}

proc save_capture {ila outfile} {
    set d ""
    catch { set d [get_hw_ila_data -of_objects $ila] }
    if {[llength $d] == 0} { set d [current_hw_ila_data] }
    set d [lindex $d end]
    catch { current_hw_ila_data $d }
    write_hw_ila_data -force $outfile $d
    puts "  saved $outfile  (object $d)"
}

set csib [lindex [get_hw_probes -of_objects $ila_icap -filter {NAME =~ "*icap_csib_v*"}]  0]
set rres [lindex [get_hw_probes -of_objects $ila_vs   -filter {NAME =~ "*rm_reset_v*"}]   0]
puts "csib probe     = $csib"
puts "rm_reset probe = $rres"

# Clear stale conditions first: a compare value left over from an older build
# will never match and the core will sit armed forever.
catch { set_property TRIGGER_COMPARE_VALUE {} [get_hw_probes -of_objects $ila_icap] }
catch { set_property TRIGGER_COMPARE_VALUE {} [get_hw_probes -of_objects $ila_vs]   }

puts "---- arming ICAP ILA on csib == 0 ----"
set ok1 [set_compare $csib [list {EQ1'b0} {F1'b1} {F}]]
puts "---- arming VS ILA on rm_reset == 1 ----"
set ok2 [set_compare $rres [list {EQ1'b1} {R1'b1} {R}]]
if {!$ok1 || !$ok2} { puts "ERROR: could not arm triggers"; return }

foreach i [list $ila_icap $ila_vs] {
    set props [list_property $i]
    if {[lsearch -exact $props "CONTROL.TRIGGER_POSITION"] >= 0} {
        set_property CONTROL.TRIGGER_POSITION 0 $i
        puts "  $i trigger position 0 (CONTROL.TRIGGER_POSITION)"
    } elseif {[lsearch -exact $props "TRIGGER_POSITION"] >= 0} {
        set_property TRIGGER_POSITION 0 $i
        puts "  $i trigger position 0 (TRIGGER_POSITION)"
    }
}

run_hw_ila $ila_icap
run_hw_ila $ila_vs
puts ""
puts ">>> Both ILAs armed. Press key1 ONCE now, then wait ~2 seconds. <<<"
puts ""

if {[catch { wait_on_hw_ila -timeout 120 $ila_icap } e1]} {
    puts "ICAP ILA did not trigger: $e1"
} else {
    save_capture $ila_icap ilaset/pr_icap.csv
}
if {[catch { wait_on_hw_ila -timeout 120 $ila_vs } e2]} {
    puts "VS ILA did not trigger (rm_reset never pulsed): $e2"
} else {
    save_capture $ila_vs ilaset/pr_vs_after.csv
}
puts "==== done ===="
