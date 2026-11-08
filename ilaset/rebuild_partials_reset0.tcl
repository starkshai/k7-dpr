# Step 1 of RESET_AFTER_RECONFIG=0 fix: regenerate the three partial bitstreams
# (no IPROG) and their SMAPx32 .bin, then print byte sizes for pr_info_myb.tcl.
set FULLSET [list \
    BITSTREAM.STARTUP.STARTUPCLK      CCLK \
    BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE \
    BITSTREAM.CONFIG.BPI_SYNC_MODE    DISABLE \
    BITSTREAM.CONFIG.PERSIST          NO \
    BITSTREAM.CONFIG.SPI_BUSWIDTH     4 \
    BITSTREAM.CONFIG.CONFIGRATE       50 \
    BITSTREAM.CONFIG.SPI_FALL_EDGE    YES ]
foreach {cfg name} {
    Config_shift_left  pblock_shift_shift_left_partial
    Config_shift_right pblock_shift_shift_right_partial
    Config_greybox     pblock_shift_greybox_partial
} {
    open_checkpoint Implement/$cfg/top_route_design.dcp
    set_property RESET_AFTER_RECONFIG 0 [get_pblocks pblock_shift]
    foreach {n v} $FULLSET { set_property $n $v [current_design] }
    set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
    write_bitstream -force -cell inst_shift Bitstreams/$name
    close_design
}
foreach p {pblock_shift_shift_left_partial pblock_shift_shift_right_partial pblock_shift_greybox_partial} {
    write_cfgmem -force -format BIN -interface SMAPx32 -disablebitswap \
        -loadbit "up 0 Bitstreams/$p.bit" Bitstreams/$p
    puts "SIZE $p = [file size Bitstreams/$p.bin]"
}
puts "PARTIALS_DONE"
exit