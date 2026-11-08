# Write the static full bitstream and debug probes from the latest route DCP
# Run: vivado -mode batch -source write_static_bitstream.tcl

open_checkpoint Implement/Config_shift_right/top_route_design.dcp

# Apply the same bitstream settings as design.tcl
set_property BITSTREAM.STARTUP.STARTUPCLK      CCLK      [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE   [current_design]
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE    DISABLE   [current_design]
set_property BITSTREAM.CONFIG.PERSIST          NO        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS        TRUE      [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH     4         [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE       50        [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE    YES       [current_design]

write_bitstream -force ./Bitstreams/Config_shift_right_full -no_partial_bitfile
write_debug_probes -force Bitstreams/config_shift_right.ltx

puts "Static full bitstream and debug probes regenerated."
exit
