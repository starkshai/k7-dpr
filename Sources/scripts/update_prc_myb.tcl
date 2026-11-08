global ipDir
regexp {(.*)\/.*\.tcl} [info script] full scriptDir
if {![info exists ipDir]} {
   set ipDir "${scriptDir}/../ip"
}
add_files $ipDir/prc_1/prc.xci
set config [get_property CONFIG.ALL_PARAMS [get_ips prc]]

# Load the PRC's API
source [get_property REPOSITORY [get_ipdefs *prc:1.3]]/xilinx/prc_v1_3/tcl/api.tcl -notrace

# This script defines the bitstream addresses and sizes
source $scriptDir/pr_info_myb.tcl -notrace

set descriptor [prc_v1_3::netlist::get_descriptor $config "i_prc/U0"]

prc_v1_3::netlist::set_rm_bs_address     descriptor vs_shift rm_shift_left $rm_shift_left_address
prc_v1_3::netlist::set_rm_bs_size        descriptor vs_shift rm_shift_left $rm_shift_left_size

prc_v1_3::netlist::set_rm_bs_address     descriptor vs_shift rm_shift_right $rm_shift_right_address
prc_v1_3::netlist::set_rm_bs_size        descriptor vs_shift rm_shift_right $rm_shift_right_size

prc_v1_3::netlist::apply_descriptor descriptor
