####################################################################################
# Constraint file for AX7325 (myb) board
# FPGA: XC7K325T-FFG900-2
# Adapted from top_kc705.xdc for SPI Flash + single VS (shift only)
####################################################################################

#-------------------------------------------------
# Clocks
#-------------------------------------------------
create_clock -name clk_p -period 5 [get_ports clk_p]

# icap_clk is now driven directly by clk_100 (MMCM output); no divider, so no
# generated clock is needed here.

#set configuration voltage
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

#-------------------------------------------------
# SPI Configuration Settings
#-------------------------------------------------
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]

#-----------------------------------
# ICAPE2 constraints
#-----------------------------------
set icap_clock [get_clocks -of_objects [get_ports ICAPE2_inst/CLK]]

#-----------------------------------
# LED LOCs (shift_low_out[0-3])
# Bank 33 (VCC1V5 1.5 volt)
#-----------------------------------
set_property PACKAGE_PIN A22 [get_ports shift_low_out[0]]
set_property IOSTANDARD LVCMOS15 [get_ports shift_low_out[0]]

set_property PACKAGE_PIN C19 [get_ports shift_low_out[1]]
set_property IOSTANDARD LVCMOS15 [get_ports shift_low_out[1]]

set_property PACKAGE_PIN B19 [get_ports shift_low_out[2]]
set_property IOSTANDARD LVCMOS15 [get_ports shift_low_out[2]]

set_property PACKAGE_PIN E18 [get_ports shift_low_out[3]]
set_property IOSTANDARD LVCMOS15 [get_ports shift_low_out[3]]

#-----------------------------------
# Differential Clock
#-----------------------------------
set_property PACKAGE_PIN AE10 [get_ports clk_p]
set_property IOSTANDARD DIFF_SSTL15 [get_ports clk_p]

set_property PACKAGE_PIN AF10 [get_ports clk_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports clk_n]

#-----------------------------------
# Push Buttons (active-low)
# key1 = Reconfig trigger, key2 = Reset (matches top.v: rst = ... | ~key2_dbnc,
# trigger edge from key1_dbnc)
# Bank 16 (VCCO 2.5V)
#-----------------------------------
set_property PACKAGE_PIN AG27 [get_ports key1]
set_property IOSTANDARD LVCMOS25 [get_ports key1]

set_property PACKAGE_PIN AG28 [get_ports key2]
set_property IOSTANDARD LVCMOS25 [get_ports key2]

#-----------------------------------
# SPI Flash Interface (N25Q128, Bank 14)
#-----------------------------------
# These are the dedicated configuration pins (CCLK via STARTUPE2, plus
# D00_MOSI / D01_DIN / D02 / D03 and the flash CS), reused as user I/O after
# boot. Pin locations verified against the AX7325 schematic.
# CCLK is not listed here - it is driven through STARTUPE2's USRCCLKO.
set_property PACKAGE_PIN U19 [get_ports flash_ce_b]
set_property IOSTANDARD LVCMOS33 [get_ports flash_ce_b]

set_property PACKAGE_PIN P24 [get_ports flash_d0]
set_property IOSTANDARD LVCMOS33 [get_ports flash_d0]

set_property PACKAGE_PIN R25 [get_ports flash_d1]
set_property IOSTANDARD LVCMOS33 [get_ports flash_d1]

set_property PACKAGE_PIN R20 [get_ports flash_d2]
set_property IOSTANDARD LVCMOS33 [get_ports flash_d2]

set_property PACKAGE_PIN R21 [get_ports flash_d3]
set_property IOSTANDARD LVCMOS33 [get_ports flash_d3]

#-----------------------------------
# Fan PWM
#-----------------------------------
set_property PACKAGE_PIN AE26 [get_ports fan_pwm]
set_property IOSTANDARD LVCMOS25 [get_ports fan_pwm]

# CCLK (B10) is a dedicated configuration pin driven by STARTUPE2 internally.
# No PACKAGE_PIN constraint needed for CCLK.

#-------------------------------------------------
# pblock_shift
#-------------------------------------------------
create_pblock pblock_shift
add_cells_to_pblock [get_pblocks pblock_shift] [get_cells -quiet [list inst_shift]]
resize_pblock pblock_shift -add {SLICE_X4Y150:SLICE_X9Y199}
resize_pblock pblock_shift -add {RAMB18_X0Y60:RAMB18_X0Y79}
resize_pblock pblock_shift -add {RAMB36_X0Y30:RAMB36_X0Y39}
set_property RESET_AFTER_RECONFIG 0 [get_pblocks pblock_shift]

#-----------------------------------
# End
#-----------------------------------
