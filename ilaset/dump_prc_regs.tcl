# dump_prc_regs.tcl -- read the whole PRC bitstream table over JTAG.
#
# Run in the Vivado Tcl Console from anywhere (the script locates the project
# root from its own path):
#
#     source C:/wmx/FPGA/ug947-vivado-partial-reconfiguration-tutorial/myprc/ilaset/dump_prc_regs.tcl
#
# WHY THE SHUTDOWN/RESTART
# ------------------------
# A first read-only pass returned status = 7 (FULL) correctly but every entry
# of the trigger / RM / bitstream table read back as 0. The reference proc
# prc_show_rm_configuration in Sources/scripts/axi_lite_procs.tcl states why:
#
#     # The VSM must be in shutdown
#
# Those registers are only accessible while the VSM is shut down (status bit 7
# set). So this script follows the documented UG947 sequence:
#
#     read running state -> prc_shutdown_vsm -> read the tables
#                        -> prc_restart_vsm_no_status -> read again
#
# WHAT IT DOES TO THE BOARD
# -------------------------
# It writes the VSM control register twice (0 then 1). During the shutdown
# window the RM is decoupled, so the LEDs may go dark or freeze for a moment;
# the restart at the end puts the VSM back to FULL. This is the same pair of
# writes the Xilinx tutorial uses and it is reversible. Do not press key1 while
# the script is running.
#
# WHAT WE ARE LOOKING FOR
# -----------------------
# The PRC enters LOAD on key1 and never leaves (status stays 0x004 for >11 s
# while the whole load should take ~309 ms) with error_code = 0. The reader has
# been proven correct in simulation for all 472 bursts and the SPI/AXI/ICAP
# data proven byte-exact on hardware, so the prime remaining suspect is that
# the PRC's <bs_address, bs_size> table does not match what is in the flash.
# A bs_size larger than the real 482828 would make the PRC fetch past the end
# of the bitstream forever and never leave LOAD, without reporting an error.

# Locate the project root from this file's own path so the script works no
# matter what the Tcl Console's current directory happens to be.
set ilaset_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $ilaset_dir]

# ---------------------------------------------------------------- preflight
if {[llength [get_hw_targets -quiet]] == 0} {
    puts "ERROR: no JTAG target open. In Hardware Manager do:"
    puts "         open_hw_manager"
    puts "         connect_hw_server"
    puts "         open_hw_target"
    return
}
if {[catch {set dev [current_hw_device]}]} {
    set devs [get_hw_devices]
    if {[llength $devs] == 0} {
        puts "ERROR: target open but no device detected. Power-cycle the board"
        puts "       (it must boot from SPI flash), then re-run."
        return
    }
    set dev [lindex $devs 0]
    current_hw_device $dev
}
puts "current_hw_device = $dev"

if {[llength [get_hw_axis -quiet]] == 0} {
    puts "WARNING: no hw_axi object yet. Trying to associate the probes file"
    puts "         and refresh the device ..."
    set ltx [file join $proj_root Bitstreams config_shift_right.ltx]
    if {[file exists $ltx]} {
        catch {set_property PROBES_FILE      $ltx $dev}
        catch {set_property FULL_PROBES_FILE $ltx $dev}
        refresh_hw_device $dev
    } else {
        puts "ERROR: cannot find $ltx"
        return
    }
}
if {[llength [get_hw_axis -quiet]] == 0} {
    puts "ERROR: still no hw_axi. In the Hardware window select the device,"
    puts "       right-click -> Set Debug Probes File -> Bitstreams/config_shift_right.ltx,"
    puts "       then right-click -> Refresh Device, and re-run this script."
    return
}
puts "hw_axi = [get_hw_axis]"
puts ""

source [file join $proj_root Sources scripts axi_lite_procs.tcl]
prc_jtag_setup

# Expected values, from Sources/scripts/pr_info_myb.tcl and the flash layout
# used by create_prom_file_myb.tcl.
set EXP_LEFT_ADDR  11444224   ;# 0x00AEA000
set EXP_RIGHT_ADDR 11927552   ;# 0x00B60000
set EXP_SIZE       482828     ;# 0x00075E0C, both partial .bin files

proc hex {v} { return [format 0x%08X $v] }

proc banner {title} {
    puts "=============================================================="
    puts " $title"
    puts "=============================================================="
}

# Dump triggers, the RM table and the bitstream table.
proc dump_tables {tag} {
    puts ""
    banner "TRIGGERS / RM TABLE / BITSTREAM TABLE   ($tag)"

    puts " -- hardware triggers (which RM each trigger selects)"
    for {set i 0} {$i < 4} {incr i} {
        set v [prc_read_register vs_shift_trigger$i]
        puts [format "    trigger%d = %s  (decimal %d)" $i [hex $v] $v]
    }

    puts " -- RM table"
    for {set i 0} {$i < 4} {incr i} {
        set idx [prc_read_register vs_shift_rm_bs_index$i]
        set ctl [prc_read_register vs_shift_rm_control$i]
        puts [format "    rm%d : bs_index = %s   control = %s" $i [hex $idx] [hex $ctl]]
    }

    puts " -- bitstream table (what the fetch engine will actually read)"
    for {set i 0} {$i < 4} {incr i} {
        set id   [prc_read_register vs_shift_bs_id$i]
        set addr [prc_read_register vs_shift_bs_address$i]
        set size [prc_read_register vs_shift_bs_size$i]
        puts [format "    bs slot %d : id = %s" $i [hex $id]]
        puts [format "                  address = %s  (decimal %d)" [hex $addr] $addr]
        puts [format "                  size    = %s  (decimal %d)  = %d bursts of 1024 B" \
                  [hex $size] $size [expr {($size + 1023) / 1024}]]

        set verdict "?"
        if {$addr == $::EXP_LEFT_ADDR && $size == $::EXP_SIZE} {
            set verdict "OK  -> rm_shift_left"
        } elseif {$addr == $::EXP_RIGHT_ADDR && $size == $::EXP_SIZE} {
            set verdict "OK  -> rm_shift_right"
        } elseif {$addr == 0 && $size == 0} {
            set verdict "empty / not readable in this VSM state"
        } elseif {$size != $::EXP_SIZE} {
            set verdict "*** SIZE MISMATCH *** expected $::EXP_SIZE (0x00075E0C)"
        } else {
            set verdict "*** ADDRESS MISMATCH *** expected 0x00AEA000 or 0x00B60000"
        }
        puts "                  verdict : $verdict"
    }
}

# ------------------------------------------------------------------ step 1
banner "STEP 1. STATUS while running (nothing pressed)"
prc_decode_status vs_shift
dump_tables "running, shutdown_bit = 0"

# ------------------------------------------------------------------ step 2
puts ""
banner "STEP 2. shut the VSM down  (writes control = 0)"
prc_shutdown_vsm vs_shift
puts "status after the shutdown command:"
prc_decode_status vs_shift

# ------------------------------------------------------------------ step 3
dump_tables "SHUTDOWN, tables should now be readable"

puts ""
banner "STEP 3b. cross-check with the reference proc"
prc_show_rm_configuration vs_shift 0
prc_show_rm_configuration vs_shift 1

# ------------------------------------------------------------------ step 4
puts ""
banner "STEP 4. restart the VSM  (writes control = 1)"
prc_restart_vsm_no_status vs_shift
puts "status after the restart command:"
prc_decode_status vs_shift

# ------------------------------------------------------------------ summary
puts ""
banner "WHAT TO LOOK FOR"
puts "  * If a bs slot in the SHUTDOWN dump shows size != 482828 and a trigger"
puts "    or rm_bs_index points at that slot, the permanent LOAD is explained:"
puts "    the PRC is waiting for bytes that do not exist in the flash."
puts "  * If both slots read 0x00AEA000 / 0x00B60000 with size 482828, the table"
puts "    is fine and the fault is downstream of the fetch engine."
puts "  * rm_bs_index tells us which slot belongs to which RM, and therefore"
puts "    whether the resting rm_id of 0 means shift_left or shift_right."
puts "  * If the SHUTDOWN dump is still all zeros, the register bank is not"
puts "    readable at these addresses in this PRC build and we need the real"
puts "    map before drawing any conclusion."
puts "=============================================================="
