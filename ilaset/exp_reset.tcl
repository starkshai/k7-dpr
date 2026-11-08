# Targeted experiment: does RESET_AFTER_RECONFIG cause the IPROG in partials?
# Open the left route DCP, write a control partial (property as-is), then set
# RESET_AFTER_RECONFIG=0 and write a test partial. Compare IPROG offline.
open_checkpoint Implement/Config_shift_left/top_route_design.dcp
set pb [get_pblocks pblock_shift]
puts "RESET_AFTER_RECONFIG before = [get_property RESET_AFTER_RECONFIG $pb]"
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
write_bitstream -force -cell inst_shift ilaset/exp/ctrl_reset1
set_property RESET_AFTER_RECONFIG 0 $pb
puts "RESET_AFTER_RECONFIG now = [get_property RESET_AFTER_RECONFIG $pb]"
write_bitstream -force -cell inst_shift ilaset/exp/test_reset0
puts "EXPERIMENT_DONE"
exit