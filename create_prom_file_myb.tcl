# Create a programming file for the SPI Flash containing the static and
# partial bitstreams for AX7325 (myb) board
#
# N25Q128: 128Mbit SPI Flash
#

# ------------------------------
# Options for the complete MCS
# ------------------------------
set final_target    "-format MCS"
set options         "-force -checksum FF -size 16"
set spi_options     "-interface SPIx4"

set static  "Config_shift_right"
set partials  { \
                    pblock_shift_shift_left_partial\
                    pblock_shift_shift_right_partial\
                    pblock_shift_greybox_partial\
              }

# Convert each partial bitfile into a bin file formatted for the ICAP port
#
foreach p $partials {
    set cmd "write_cfgmem -force -format BIN -interface SMAPx32 -disablebitswap -loadbit \"up 0 Bitstreams/$p.bit\" Bitstreams/$p"
    eval $cmd
}

# Now create the MCS with static bitstream at address 0
# and partial bitstreams at their SPI Flash offsets
# Addresses must match pr_info_myb.tcl:
#   rm_shift_left  -> 0xAEA000
#   rm_shift_right -> 0xB60000
set cmd "write_cfgmem $options $final_target $spi_options -loadbit \"up 0 Bitstreams/${static}_full.bit\" -loaddata \""
append cmd " up 00AEA000 Bitstreams/pblock_shift_shift_left_partial.bin"
append cmd " up 00B60000 Bitstreams/pblock_shift_shift_right_partial.bin"
append cmd " up 00BD6000 Bitstreams/pblock_shift_greybox_partial.bin"
append cmd "\" Bitstreams/pr_prom"

puts $cmd
eval $cmd

# Now create a report with the sizes
foreach p $partials {
    set ret [file size Bitstreams/$p.bin]
    puts "$p : $ret bytes"
}

#exit
