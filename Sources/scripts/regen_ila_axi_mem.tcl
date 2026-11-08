# Regenerate the ila_axi_mem IP in place with 20 probes (adds MOSI + MISO).
# Run from the project root:
#   vivado -mode batch -source Sources/scripts/regen_ila_axi_mem.tcl
#
# Unlike earlier versions this does NOT call create_ip on an existing directory
# (that silently produced ila_axi_mem_1 / ila_axi_mem_2). It reads the XCI that
# design.tcl actually uses and re-customises it in place.

if {![info exists part]} {
    set part "xc7k325tffg900-2"
}
if {![info exists ipDir]} {
    regexp {(.*)\/.*\.tcl} [info script] full scriptDir
    set ipDir "${scriptDir}/../ip"
}

set xci "$ipDir/ila_axi_mem/ila_axi_mem.xci"
if {![file exists $xci]} {
    puts "ERROR: $xci not found"
    return 1
}

create_project -in_memory -part $part
set_property target_language Verilog [current_project]

read_ip $xci
set ip [get_ips ila_axi_mem]

set_property -dict [list CONFIG.C_PROBE0_WIDTH  {32} \
                         CONFIG.C_PROBE1_WIDTH  {8}  \
                         CONFIG.C_PROBE2_WIDTH  {3}  \
                         CONFIG.C_PROBE3_WIDTH  {2}  \
                         CONFIG.C_PROBE4_WIDTH  {3}  \
                         CONFIG.C_PROBE5_WIDTH  {4}  \
                         CONFIG.C_PROBE6_WIDTH  {4}  \
                         CONFIG.C_PROBE7_WIDTH  {1}  \
                         CONFIG.C_PROBE8_WIDTH  {1}  \
                         CONFIG.C_PROBE9_WIDTH  {32} \
                         CONFIG.C_PROBE10_WIDTH {2}  \
                         CONFIG.C_PROBE11_WIDTH {1}  \
                         CONFIG.C_PROBE12_WIDTH {1}  \
                         CONFIG.C_PROBE13_WIDTH {1}  \
                         CONFIG.C_PROBE14_WIDTH {4}  \
                         CONFIG.C_PROBE15_WIDTH {4}  \
                         CONFIG.C_PROBE16_WIDTH {1}  \
                         CONFIG.C_PROBE17_WIDTH {1}  \
                         CONFIG.C_PROBE18_WIDTH {1}  \
                         CONFIG.C_PROBE19_WIDTH {1}  \
                         CONFIG.C_DATA_DEPTH    {65536} \
                         CONFIG.C_NUM_OF_PROBES {20} \
                         CONFIG.C_TRIGOUT_EN    {true} \
                         CONFIG.C_MONITOR_TYPE  {Native}] $ip

catch { upgrade_ip $ip } upg
puts "upgrade_ip: $upg"

set_property generate_synth_checkpoint false [get_files ila_axi_mem.xci]
generate_target {all} $ip

puts "C_NUM_OF_PROBES now = [get_property CONFIG.C_NUM_OF_PROBES $ip]"
puts "ila_axi_mem regenerated in place with 20 probes (probe18 = flash_d0/MOSI, probe19 = flash_d1/MISO)"
