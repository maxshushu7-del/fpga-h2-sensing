# AXAU15 UG pages 9,25-28,36-37; FL4322 net assignment inherited from local AXAU15 kicker.xdc.
# 1.8V FMC BANK64/65. CARD SPI LEVEL TRANSLATION MUST BE VERIFIED BEFORE INIT.
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
# SYS_CLK_P
set_property PACKAGE_PIN T24 [get_ports {sys_clk_p}]
set_property IOSTANDARD LVDS [get_ports {sys_clk_p}]
# SYS_CLK_N
set_property PACKAGE_PIN U24 [get_ports {sys_clk_n}]
set_property IOSTANDARD LVDS [get_ports {sys_clk_n}]
# KEY1
set_property PACKAGE_PIN N26 [get_ports {key_reset_n}]
set_property IOSTANDARD LVCMOS18 [get_ports {key_reset_n}]
# LED1
set_property PACKAGE_PIN W21 [get_ports {led_ready}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_ready}]
# LED2
set_property PACKAGE_PIN AC16 [get_ports {led_servo}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_servo}]
# FMC_CLK0_P
set_property PACKAGE_PIN T25 [get_ports {adc_data_p[0]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[0]}]
# FMC_CLK0_N
set_property PACKAGE_PIN U25 [get_ports {adc_data_n[0]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[0]}]
# FMC_CLK1_P
set_property PACKAGE_PIN AB21 [get_ports {adc_data_p[1]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[1]}]
# FMC_CLK1_N
set_property PACKAGE_PIN AC21 [get_ports {adc_data_n[1]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[1]}]
# FMC_LA06_P
set_property PACKAGE_PIN N23 [get_ports {adc_data_p[2]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[2]}]
# FMC_LA06_N
set_property PACKAGE_PIN P23 [get_ports {adc_data_n[2]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[2]}]
# FMC_LA02_P
set_property PACKAGE_PIN N24 [get_ports {adc_data_p[3]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[3]}]
# FMC_LA02_N
set_property PACKAGE_PIN P24 [get_ports {adc_data_n[3]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[3]}]
# FMC_LA01_CC_P
set_property PACKAGE_PIN V24 [get_ports {adc_data_p[4]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[4]}]
# FMC_LA01_CC_N
set_property PACKAGE_PIN W24 [get_ports {adc_data_n[4]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[4]}]
# FMC_LA03_P
set_property PACKAGE_PIN N21 [get_ports {adc_data_p[5]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[5]}]
# FMC_LA03_N
set_property PACKAGE_PIN N22 [get_ports {adc_data_n[5]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[5]}]
# FMC_LA04_P
set_property PACKAGE_PIN R25 [get_ports {adc_data_p[6]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[6]}]
# FMC_LA04_N
set_property PACKAGE_PIN R26 [get_ports {adc_data_n[6]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[6]}]
# FMC_LA05_P
set_property PACKAGE_PIN P25 [get_ports {adc_data_p[7]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[7]}]
# FMC_LA05_N
set_property PACKAGE_PIN P26 [get_ports {adc_data_n[7]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[7]}]
# FMC_LA08_P
set_property PACKAGE_PIN R20 [get_ports {adc_data_p[8]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[8]}]
# FMC_LA08_N
set_property PACKAGE_PIN R21 [get_ports {adc_data_n[8]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[8]}]
# FMC_LA07_P
set_property PACKAGE_PIN P20 [get_ports {adc_data_p[9]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[9]}]
# FMC_LA07_N
set_property PACKAGE_PIN P21 [get_ports {adc_data_n[9]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[9]}]
# FMC_LA10_P
set_property PACKAGE_PIN W25 [get_ports {adc_data_p[10]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[10]}]
# FMC_LA10_N
set_property PACKAGE_PIN W26 [get_ports {adc_data_n[10]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[10]}]
# FMC_LA12_P
set_property PACKAGE_PIN R22 [get_ports {adc_data_p[11]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[11]}]
# FMC_LA12_N
set_property PACKAGE_PIN R23 [get_ports {adc_data_n[11]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[11]}]
# FMC_LA11_P
set_property PACKAGE_PIN T22 [get_ports {adc_data_p[12]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[12]}]
# FMC_LA11_N
set_property PACKAGE_PIN T23 [get_ports {adc_data_n[12]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[12]}]
# FMC_LA09_P
set_property PACKAGE_PIN N19 [get_ports {adc_data_p[13]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_p[13]}]
# FMC_LA09_N
set_property PACKAGE_PIN P19 [get_ports {adc_data_n[13]}]
set_property IOSTANDARD LVDS [get_ports {adc_data_n[13]}]
# FMC_LA00_CC_P
set_property PACKAGE_PIN V23 [get_ports {adc_dco_p}]
set_property IOSTANDARD LVDS [get_ports {adc_dco_p}]
# FMC_LA00_CC_N
set_property PACKAGE_PIN W23 [get_ports {adc_dco_n}]
set_property IOSTANDARD LVDS [get_ports {adc_dco_n}]
# FMC_LA18_CC_P
set_property PACKAGE_PIN AD20 [get_ports {fpga_clk_p}]
set_property IOSTANDARD LVDS [get_ports {fpga_clk_p}]
# FMC_LA18_CC_N
set_property PACKAGE_PIN AE20 [get_ports {fpga_clk_n}]
set_property IOSTANDARD LVDS [get_ports {fpga_clk_n}]
# FMC_LA33_P
set_property PACKAGE_PIN AB25 [get_ports {dac_data_p[0]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[0]}]
# FMC_LA33_N
set_property PACKAGE_PIN AB26 [get_ports {dac_data_n[0]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[0]}]
# FMC_LA31_P
set_property PACKAGE_PIN AD24 [get_ports {dac_data_p[1]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[1]}]
# FMC_LA31_N
set_property PACKAGE_PIN AD25 [get_ports {dac_data_n[1]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[1]}]
# FMC_LA29_P
set_property PACKAGE_PIN AE25 [get_ports {dac_data_p[2]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[2]}]
# FMC_LA29_N
set_property PACKAGE_PIN AE26 [get_ports {dac_data_n[2]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[2]}]
# FMC_LA32_P
set_property PACKAGE_PIN AC26 [get_ports {dac_data_p[3]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[3]}]
# FMC_LA32_N
set_property PACKAGE_PIN AD26 [get_ports {dac_data_n[3]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[3]}]
# FMC_LA30_P
set_property PACKAGE_PIN AF24 [get_ports {dac_data_p[4]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[4]}]
# FMC_LA30_N
set_property PACKAGE_PIN AF25 [get_ports {dac_data_n[4]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[4]}]
# FMC_LA28_P
set_property PACKAGE_PIN AF18 [get_ports {dac_data_p[5]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[5]}]
# FMC_LA28_N
set_property PACKAGE_PIN AF19 [get_ports {dac_data_n[5]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[5]}]
# FMC_LA24_P
set_property PACKAGE_PIN AC18 [get_ports {dac_data_p[6]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[6]}]
# FMC_LA24_N
set_property PACKAGE_PIN AD18 [get_ports {dac_data_n[6]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[6]}]
# FMC_LA21_P
set_property PACKAGE_PIN Y17 [get_ports {dac_data_p[7]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[7]}]
# FMC_LA21_N
set_property PACKAGE_PIN AA17 [get_ports {dac_data_n[7]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[7]}]
# FMC_LA27_P
set_property PACKAGE_PIN AA19 [get_ports {dac_data_p[8]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[8]}]
# FMC_LA27_N
set_property PACKAGE_PIN AB19 [get_ports {dac_data_n[8]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[8]}]
# FMC_LA25_P
set_property PACKAGE_PIN AA22 [get_ports {dac_data_p[9]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[9]}]
# FMC_LA25_N
set_property PACKAGE_PIN AB22 [get_ports {dac_data_n[9]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[9]}]
# FMC_LA26_P
set_property PACKAGE_PIN Y20 [get_ports {dac_data_p[10]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[10]}]
# FMC_LA26_N
set_property PACKAGE_PIN Y21 [get_ports {dac_data_n[10]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[10]}]
# FMC_LA22_P
set_property PACKAGE_PIN AB17 [get_ports {dac_data_p[11]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[11]}]
# FMC_LA22_N
set_property PACKAGE_PIN AC17 [get_ports {dac_data_n[11]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[11]}]
# FMC_LA23_P
set_property PACKAGE_PIN AA20 [get_ports {dac_data_p[12]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[12]}]
# FMC_LA23_N
set_property PACKAGE_PIN AB20 [get_ports {dac_data_n[12]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[12]}]
# FMC_LA16_P
set_property PACKAGE_PIN U21 [get_ports {dac_data_p[13]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[13]}]
# FMC_LA16_N
set_property PACKAGE_PIN U22 [get_ports {dac_data_n[13]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[13]}]
# FMC_LA19_P
set_property PACKAGE_PIN AE22 [get_ports {dac_data_p[14]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[14]}]
# FMC_LA19_N
set_property PACKAGE_PIN AF22 [get_ports {dac_data_n[14]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[14]}]
# FMC_LA13_P
set_property PACKAGE_PIN T20 [get_ports {dac_data_p[15]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_p[15]}]
# FMC_LA13_N
set_property PACKAGE_PIN U20 [get_ports {dac_data_n[15]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[15]}]
# FMC_LA14_P
set_property PACKAGE_PIN U19 [get_ports {dac_frame_p}]
set_property IOSTANDARD LVDS [get_ports {dac_frame_p}]
# FMC_LA14_N
set_property PACKAGE_PIN V19 [get_ports {dac_frame_n}]
set_property IOSTANDARD LVDS [get_ports {dac_frame_n}]
# FMC_LA17_CC_P
set_property PACKAGE_PIN AC19 [get_ports {dac_dci_p}]
set_property IOSTANDARD LVDS [get_ports {dac_dci_p}]
# FMC_LA17_CC_N
set_property PACKAGE_PIN AD19 [get_ports {dac_dci_n}]
set_property IOSTANDARD LVDS [get_ports {dac_dci_n}]
# FMC_LA20_N
set_property PACKAGE_PIN AF17 [get_ports {spi_clk}]
set_property IOSTANDARD LVCMOS18 [get_ports {spi_clk}]
# FMC_LA20_P
set_property PACKAGE_PIN AE17 [get_ports {spi_sdio}]
set_property IOSTANDARD LVCMOS18 [get_ports {spi_sdio}]
# FMC_SDA
set_property PACKAGE_PIN U26 [get_ports {clk_cs_n}]
set_property IOSTANDARD LVCMOS18 [get_ports {clk_cs_n}]
# FMC_LA15_P
set_property PACKAGE_PIN V21 [get_ports {adc_cs_n}]
set_property IOSTANDARD LVCMOS18 [get_ports {adc_cs_n}]
# FMC_LA15_N
set_property PACKAGE_PIN V22 [get_ports {dac_cs_n}]
set_property IOSTANDARD LVCMOS18 [get_ports {dac_cs_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {adc_dco_p adc_data_p[*] fpga_clk_p}]
create_clock -name sys_ref -period 5.000 [get_ports sys_clk_p]
create_clock -name adc_dco -period 4.000 -waveform {0.000 2.000} [get_ports adc_dco_p]
create_clock -name dac_ref -period 4.000 -waveform {0.000 2.000} [get_ports fpga_clk_p]
set_false_path -from [get_ports key_reset_n]

# DCO capture needs bank65 direct MMCM; the system reference is globally
# buffered so its100MHz controller MMCM can use the unused bank66 CMT.
set_property LOC MMCM_X0Y2 [get_cells u_integrated/u_core/u_clock/u_mmcm]
set_property LOC MMCM_X0Y1 [get_cells u_integrated/u_rx/u_dco_mmcm]
# UltraScale+ same-column dedicated global route to the adjacent CMT (UG949).
# This retains dedicated clock routing; no general-fabric clock waiver is used.
set_property CLOCK_DEDICATED_ROUTE SAME_CMT_COLUMN [get_nets u_integrated/u_core/u_clock/mmcm_input_clock]
