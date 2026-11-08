# Step 2 of RESET_AFTER_RECONFIG=0 fix: regenerate the STATIC full bitstream with
# the PRC bitstream table updated to the new (smaller) partial sizes, then the MCS.
# Run AFTER pr_info_myb.tcl sizes have been updated to the new .bin byte sizes.
open_checkpoint Implement/Config_shift_right/top_route_design.dcp
set_property RESET_AFTER_RECONFIG 0 [get_pblocks pblock_shift]
set_property BITSTREAM.STARTUP.STARTUPCLK      CCLK      [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE   [current_design]
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE    DISABLE   [current_design]
set_property BITSTREAM.CONFIG.PERSIST          NO        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS        TRUE      [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH     4         [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE       50        [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE    YES       [current_design]

# Apply the PRC bitstream address/size table from pr_info_myb.tcl (new sizes).
if {[catch {source Sources/scripts/update_prc_myb.tcl} e]} {
    puts "UPDATE_PRC_FAILED: $e"
    exit 1
}
write_bitstream -force ./Bitstreams/Config_shift_right_full -no_partial_bitfile
write_debug_probes -force Bitstreams/config_shift_right.ltx
close_design

source create_prom_file_myb.tcl
puts "STATIC_AND_MCS_DONE"
exit