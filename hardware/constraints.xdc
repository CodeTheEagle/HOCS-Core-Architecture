## HOCS Physical Constraints File (XDC)
## Target: Xilinx Kria KV260 (Zynq UltraScale+ MPSoC)
## Author: Muhammed Yusuf Çobanoğlu

# ----------------------------------------------------------------------------
# System Clock & Reset
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN H12 [get_ports clk_in]
set_property IOSTANDARD LVCMOS33 [get_ports clk_in]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk_in]

set_property PACKAGE_PIN A10 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ----------------------------------------------------------------------------
# Optical DAC Interface (SPI / Parallel) - PMOD Header A
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN D10 [get_ports {dac_data[0]}]
set_property PACKAGE_PIN D11 [get_ports {dac_data[1]}]
set_property PACKAGE_PIN C12 [get_ports {dac_data[2]}]
set_property PACKAGE_PIN B13 [get_ports {dac_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[*]}]

set_property PACKAGE_PIN B14 [get_ports dac_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_cs_n]

# ----------------------------------------------------------------------------
# ADC Readout Interface - PMOD Header B
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN A14 [get_ports {adc_data[0]}]
set_property PACKAGE_PIN A15 [get_ports {adc_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data[*]}]

set_property PACKAGE_PIN B15 [get_ports adc_clk]
set_property IOSTANDARD LVCMOS33 [get_ports adc_clk]
set_property SLEW FAST [get_ports adc_clk]

# ----------------------------------------------------------------------------
# Timing Constraints
# ----------------------------------------------------------------------------
set_false_path -from [get_clocks sys_clk_pin] -to [get_ports {dac_data[*]}]
set_max_delay -from [get_ports {adc_data[*]}] -to [get_clocks sys_clk_pin] 5.0
