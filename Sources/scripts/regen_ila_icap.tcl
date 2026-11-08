# Regenerate only ila_icap IP with original 4 probes
# Run: vivado -mode batch -source regen_ila_icap.tcl

if {![info exists part]} {
   set part "xc7k325tffg900-2"
}
if {![info exists ipDir]} {
   regexp {(.*)\/.*\.tcl} [info script] full scriptDir
   set ipDir "${scriptDir}/../ip"
}

create_project -in_memory -part $part
set_property target_language Verilog [current_project]

set ip_name ila_icap
puts "Creating IP $ip_name at $ipDir"
create_ip -dir $ipDir -name ila -vendor xilinx.com -library ip -module_name $ip_name
set_property -dict [list CONFIG.C_PROBE3_WIDTH        {1} \
                         CONFIG.C_PROBE2_WIDTH        {1} \
                         CONFIG.C_PROBE1_WIDTH        {4} \
                         CONFIG.C_PROBE0_WIDTH        {32}\
                         CONFIG.C_DATA_DEPTH          {16384} \
                         CONFIG.C_NUM_OF_PROBES       {4} \
                         CONFIG.C_TRIGOUT_EN          {true} \
                         CONFIG.C_EN_STRG_QUAL        {1} \
                         CONFIG.C_INPUT_PIPE_STAGES   {0} \
                         CONFIG.C_ADV_TRIGGER         {true} \
                         CONFIG.C_PROBE3_MU_CNT       {4} \
                         CONFIG.C_PROBE2_MU_CNT       {4} \
                         CONFIG.C_PROBE1_MU_CNT       {4} \
                         CONFIG.C_PROBE0_MU_CNT       {4} \
                         CONFIG.ALL_PROBE_SAME_MU     {false} \
                         CONFIG.C_MONITOR_TYPE        {Native} \
                         CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
                         CONFIG.C_ENABLE_ILA_AXI_MON  {false}] [get_ips $ip_name]
set_property generate_synth_checkpoint false [get_files $ip_name.xci]
generate_target {all} [get_ips $ip_name]

puts "ila_icap regenerated with 4 probes"
