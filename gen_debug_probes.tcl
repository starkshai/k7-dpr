# Generate debug probes file for ILA
# Run after bitstream generation

# Open the implemented design
open_checkpoint Implement/Config_shift_right/top_route_design.dcp

# Generate debug probes file
write_debug_probes -force Bitstreams/config_shift_right.ltx

puts "Debug probes file generated: Bitstreams/config_shift_right.ltx"
