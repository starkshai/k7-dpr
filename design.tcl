###############################################################
###   Tcl Variables
###############################################################
#set tclParams [list <param1> <value> <param2> <value> ... <paramN> <value>]
#set tclParams [list hd.visual 1] 

#Define location for "Tcl" directory. Defaults to "./tcl_HD"
if {[file exists "./Tcl_HD"]} { 
   set tclDir  "./Tcl_HD"
} else {
   error "ERROR: No valid location found for required Tcl scripts. Set \$tclDir in design.tcl to a valid location."
}
puts "Setting TCL dir to $tclDir"

####Source required Tcl Procs
source $tclDir/design_utils.tcl
source $tclDir/log_utils.tcl
source $tclDir/synth_utils.tcl
source $tclDir/impl_utils.tcl
source $tclDir/hd_utils.tcl
source $tclDir/pr_utils.tcl

###############################################################
### Define target demo board
### Valid values are myb, kc705, vc707, vc709
### Select one only
###############################################################
set xboard        "myb"
#set xboard        "kc705"
#set xboard        "vc707"
#set xboard        "vc709"

###############################################################
### Define Part, Package, Speedgrade 
###############################################################
switch $xboard {
vc707 {
 set device       "xc7vx485t"
 set package      "ffg1761"
 set speed        "-2"
}
vc709 {
 set device       "xc7vx690t"
 set package      "ffg1761"
 set speed        "-2"
}
default {
 #myb / kc705
 set device       "xc7k325t"
 set package      "ffg900"
 set speed        "-2"
}
}
set part         $device$package$speed
check_part $part

###############################################################
###  Setup Variables
###############################################################
#set tclParams [list <param1> <value> <param2> <value> ... <paramN> <value>]

####flow control
set run.topSynth       1
set run.rmSynth        1
set run.prImpl         1
set run.greyboxImpl    1
set run.prVerify       1
set run.writeBitstream 1

####Report and DCP controls - values: 0-required min; 1-few extra; 2-all
set verbose      1
set dcpLevel     1

####Output Directories
set synthDir  "./Synth"
set implDir   "./Implement"
set dcpDir    "./Checkpoint"
set bitDir    "./Bitstreams"

####Input Directories
set srcDir     "./Sources"
set rtlDir     "$srcDir/hdl"
set ipDir      "$srcDir/ip"
set prjDir     "$srcDir/prj"
set xdcDir     "$srcDir/xdc"
set coreDir    "$srcDir/cores"
set netlistDir "$srcDir/netlist"
set scriptDir  "$srcDir/scripts"

###############################################################
### Top Definition
###############################################################
set top "top"
set static "Static"
add_module $static
set_attribute module $static moduleName    $top
set_attribute module $static top_level     1

set_attribute module $static vlog          [list $rtlDir/top/clocks.v   \
                                                 $rtlDir/top/shift_rp.v \
                                                 $rtlDir/top/top.v      \
                                                 $rtlDir/top/debouncer.v \
                                                 $rtlDir/top/spi_flash_reader.v \
                                           ]
set_attribute module $static ip            [list $ipDir/prc_1/prc.xci \
                                                 $ipDir/jtag_to_axi/jtag_to_axi.xci \
                                                 $ipDir/ila_vs_shift/ila_vs_shift.xci \
                                                 $ipDir/ila_axi_mem/ila_axi_mem.xci \
                                                 $ipDir/ila_axi_reg/ila_axi_reg.xci \
                                                 $ipDir/ila_icap/ila_icap.xci \
                                           ]
set_attribute module $static synthXDC      [list $xdcDir/${top}_$xboard.xdc]
set_attribute module $static synth         ${run.topSynth}

####################################################################
### RP Module Definitions
####################################################################
set module1 "shift"

set module1_variant1 "shift_right"
set variant $module1_variant1
add_module $variant
set_attribute module $variant moduleName   $module1
set_attribute module $variant vlog         [list $rtlDir/$variant/$variant.v]
set_attribute module $variant synth        ${run.rmSynth}

set module1_variant2 "shift_left"
set variant $module1_variant2
add_module $variant
set_attribute module $variant moduleName   $module1
set_attribute module $variant vlog         [list $rtlDir/$variant/$variant.v]
set_attribute module $variant synth        ${run.rmSynth}

set module1_inst "inst_shift"

########################################################################
### Configuration (Implementation) Definition - Replicate for each Config
########################################################################
set config "Config_${module1_variant1}"

add_implementation $config
set_attribute impl $config top                 $top
set_attribute impl $config implXDC             [list $xdcDir/${top}_$xboard.xdc]
set_attribute impl $config partitions          [list [list $static           $top          implement] \
                                                     [list $module1_variant1 $module1_inst implement] \
                                               ]
set_attribute impl $config pr.impl             1
set_attribute impl $config impl                ${run.prImpl}
set_attribute impl $config verify              ${run.prVerify}
set_attribute impl $config bitstream           ${run.writeBitstream}
set_attribute impl $config bitstream.pre       $scriptDir/update_prc_$xboard.tcl
set_attribute impl $config bitstream_settings  [list "BITSTREAM.STARTUP.STARTUPCLK      CCLK"    \
                                                     "BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE" \
                                                     "BITSTREAM.CONFIG.BPI_SYNC_MODE    DISABLE" \
                                                     "BITSTREAM.CONFIG.PERSIST          NO"      \
                                                     "BITSTREAM.GENERAL.COMPRESS        TRUE"    \
                                                     "BITSTREAM.CONFIG.SPI_BUSWIDTH     4"       \
                                                     "BITSTREAM.CONFIG.CONFIGRATE       50"      \
                                                     "BITSTREAM.CONFIG.SPI_FALL_EDGE    YES"     \
                                                      ]
set_attribute impl $config partial_bitstream_settings [list "BITSTREAM.GENERAL.COMPRESS FALSE"   \
                                                      ]

########################################################################
### Configuration (Implementation) Definition - Replicate for each Config
########################################################################
set config "Config_${module1_variant2}"

add_implementation $config
set_attribute impl $config top                 $top
set_attribute impl $config implXDC             [list $xdcDir/${top}_$xboard.xdc]
set_attribute impl $config partitions          [list [list $static           $top          import]    \
                                                     [list $module1_variant2 $module1_inst implement] \
                                               ]
set_attribute impl $config pr.impl             1
set_attribute impl $config impl                ${run.prImpl}
set_attribute impl $config verify              ${run.prVerify}
set_attribute impl $config bitstream           ${run.writeBitstream}
set_attribute impl $config bitstream_settings  [list "BITSTREAM.STARTUP.STARTUPCLK      CCLK"    \
                                                     "BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE" \
                                                     "BITSTREAM.CONFIG.BPI_SYNC_MODE    DISABLE" \
                                                     "BITSTREAM.CONFIG.PERSIST          NO"      \
                                                     "BITSTREAM.GENERAL.COMPRESS        TRUE"    \
                                                     "BITSTREAM.CONFIG.SPI_BUSWIDTH     4"       \
                                                     "BITSTREAM.CONFIG.CONFIGRATE       50"      \
                                                     "BITSTREAM.CONFIG.SPI_FALL_EDGE    YES"     \
                                                      ]
set_attribute impl $config partial_bitstream_settings [list "BITSTREAM.GENERAL.COMPRESS FALSE"   \
                                                      ]

########################################################################
### Configuration (Implementation) Definition - Replicate for each Config
########################################################################
set config "Config_greybox"

add_implementation $config
set_attribute impl $config top                 $top
set_attribute impl $config implXDC             [list $xdcDir/${top}_$xboard.xdc]
set_attribute impl $config partitions          [list [list $static           $top          import ] \
                                                     [list $module1_variant2 $module1_inst greybox] \
                                               ]
set_attribute impl $config pr.impl             1
set_attribute impl $config impl                ${run.greyboxImpl}
set_attribute impl $config verify              ${run.prVerify}
set_attribute impl $config bitstream           ${run.writeBitstream}
set_attribute impl $config bitstream_settings  [list "BITSTREAM.STARTUP.STARTUPCLK      CCLK"    \
                                                     "BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE" \
                                                     "BITSTREAM.CONFIG.BPI_SYNC_MODE    DISABLE" \
                                                     "BITSTREAM.CONFIG.PERSIST          NO"      \
                                                     "BITSTREAM.GENERAL.COMPRESS        TRUE"    \
                                                     "BITSTREAM.CONFIG.SPI_BUSWIDTH     4"       \
                                                     "BITSTREAM.CONFIG.CONFIGRATE       50"      \
                                                     "BITSTREAM.CONFIG.SPI_FALL_EDGE    YES"     \
                                                      ]
set_attribute impl $config partial_bitstream_settings [list "BITSTREAM.GENERAL.COMPRESS FALSE"   \
                                                      ]

# ===========================================================================
# Task / flow portion
# ===========================================================================
# Check if IP are need to be created/generated
if {![file exists $ipDir/prc_1/prc.xci]} {
   source $scriptDir/gen_ip_$xboard.tcl
}
# Build the designs
source $tclDir/run.tcl
#exit
