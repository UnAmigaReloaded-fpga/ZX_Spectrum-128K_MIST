#************************************************************
# THIS IS A WIZARD-GENERATED FILE.                           
#
# Version 13.1.4 Build 182 03/12/2014 SJ Full Version
#
#************************************************************

# Copyright (C) 1991-2014 Altera Corporation
# Your use of Altera Corporation's design tools, logic functions 
# and other software and tools, and its AMPP partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Altera Program License 
# Subscription Agreement, Altera MegaCore Function License 
# Agreement, or other applicable license agreement, including, 
# without limitation, that your use is for the sole purpose of 
# programming logic devices manufactured by Altera and sold by 
# Altera or its authorized distributors.  Please refer to the 
# applicable agreement for further details.



# Clock constraints

create_clock -name "CLOCK_27" -period 37.037 [get_ports {CLOCK_27}]
create_clock -name {SPI_SCK}  -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

# Clock groups
set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}]

# False paths
set_false_path -to [get_ports {VGA_*}]
set_false_path -to [get_ports {AUDIO_L}]
set_false_path -to [get_ports {AUDIO_R}]
set_false_path -to [get_ports {LED}]
set_false_path -from [get_ports {UART_RX}]

set_false_path -to {video:video|video_mixer:video_mixer|scandoubler:scandoubler|Hq2x:Hq2x|*}
set_false_path -to {sigma_delta_dac:*}
#set_false_path -to {smart_tape:tape|tape:tape|addr[*]}

set_max_delay -from {T80pa:cpu|T80:u0|*} -to {T80pa:cpu|T80:u0|*} 14
set_max_delay -from {u765:u765|*} -to {u765:u765|*} 15.0
set_max_delay -from {wd1793:fdd|*} -to {wd1793:fdd|*} 15.0
set_max_delay -from {T80pa:cpu|T80:u0|BusAck} -to {vram:vram|*} 16.0
set_max_delay -from {video:video|*} -to {T80pa:cpu|T80:u0|*} 14
