`timescale 1ns/1ps
// V4 ONLY Ethernet UDP physical top for AXAU15 + PZ-FL4322 + JL2121 PHY.
// Reuses V3 servo/FFT/PID and Ethernet UDP CDC structure; UART transmitter removed.
// Temperature is VIRTUAL: no TEC200 heater, sensor, or physical analog signal
// connected to any FPGA pin. UDP transmits read-only status at 100 packets/s.
module laser_lock_hw_udp_only_top #(
    parameter ENABLE_ILA=1,
    parameter ENABLE_VIO=1,
    parameter integer TEMP_TIMEOUT_CYCLES=20000000
)(
    input wire sys_clk_p,input wire sys_clk_n,input wire key_reset_n,
    input wire adc_dco_p,input wire adc_dco_n,
    input wire [13:0] adc_data_p,input wire [13:0] adc_data_n,
    input wire fpga_clk_p,input wire fpga_clk_n,
    output wire [15:0] dac_data_p,output wire [15:0] dac_data_n,
    output wire dac_dci_p,output wire dac_dci_n,
    output wire dac_frame_p,output wire dac_frame_n,
    output wire spi_clk,output wire spi_sdio,
    output wire clk_cs_n,output wire adc_cs_n,output wire dac_cs_n,
    output wire led_ready,output wire led_servo,
    output wire phy_reset_n,output wire phy_tx_clk,
    output wire phy_tx_ctl,output wire [3:0] phy_txd
);
    // The physical board exposes ONLY RGMII PHY TX, never an FPGA UART TX.
    wire clk_work,clk250,tx_locked,hw_rst;
    wire [31:0] frequency_hz,fft_sequence;
    wire signed [15:0] laser_error,dac_code;
    wire [15:0] temperature_duty;
    wire temp_fault_internal,temp_pwm_internal,fft_valid,fft_enabled;
    wire [7:0] auto_state,auto_fault,hw_status;
    wire signed [31:0] virtual_temperature;
    wire virtual_sample_valid;

    tec200_virtual_plant u_thermal_demo (
        .clk(clk_work),.rst(hw_rst),
        .heater_pwm_internal(temp_pwm_internal),
        .temperature_mc(virtual_temperature),
        .sample_valid(virtual_sample_valid)
    );

    laser_lock_hw_top #(
        .ENABLE_ILA(ENABLE_ILA),.ENABLE_VIO(ENABLE_VIO),
        .TEMP_TIMEOUT_CYCLES(TEMP_TIMEOUT_CYCLES)
    ) u_integrated (
        .sys_clk_p(sys_clk_p),.sys_clk_n(sys_clk_n),.key_reset_n(key_reset_n),
        .adc_dco_p(adc_dco_p),.adc_dco_n(adc_dco_n),
        .adc_data_p(adc_data_p),.adc_data_n(adc_data_n),
        .fpga_clk_p(fpga_clk_p),.fpga_clk_n(fpga_clk_n),
        .dac_data_p(dac_data_p),.dac_data_n(dac_data_n),
        .dac_dci_p(dac_dci_p),.dac_dci_n(dac_dci_n),
        .dac_frame_p(dac_frame_p),.dac_frame_n(dac_frame_n),
        .spi_clk(spi_clk),.spi_sdio(spi_sdio),
        .clk_cs_n(clk_cs_n),.adc_cs_n(adc_cs_n),.dac_cs_n(dac_cs_n),
        .led_ready(led_ready),.led_servo(led_servo),
        // All sensor data are synthesized virtual temperatures; output stays INTERNAL.
        .temp_temperature_mc(virtual_temperature),
        .temp_sample_valid(virtual_sample_valid),
        .temp_sensor_fault(1'b0),
        .temp_heater_pwm(temp_pwm_internal),.temp_fault(temp_fault_internal),
        .udp_clk_work(clk_work),.udp_clk_250(clk250),
        .udp_tx_clock_locked(tx_locked),.udp_reset(hw_rst),
        .udp_frequency_hz(frequency_hz),.udp_fft_sequence(fft_sequence),
        .udp_laser_error(laser_error),.udp_dac_code(dac_code),
        .udp_temp_duty(temperature_duty),.udp_temp_fault(temp_fault_internal),
        .udp_temp_pwm(),.udp_fft_valid(fft_valid),
        .udp_auto_state(auto_state),.udp_auto_fault(auto_fault),
        .udp_hw_status(hw_status),.udp_fft_enable(fft_enabled)
    );

    wire clk_eth,reset_eth,phy_ready_eth;
    wire [7:0] udp_byte;
    wire udp_byte_valid;
    rgmii_udp_tx u_rgmii (
        .clk250(clk250),
        // The 250MHz MMCM and the active-low reset button are the only
        // asynchronous reset sources; hw_rst belongs to the 100MHz domain.
        .reset_async(!tx_locked || !key_reset_n),
        .tx_byte(udp_byte),.tx_en(udp_byte_valid),
        .phy_tx_clk(phy_tx_clk),.phy_tx_ctl(phy_tx_ctl),
        .phy_txd(phy_txd),.phy_reset_n(phy_reset_n),
        .clk125(clk_eth),.reset125(reset_eth),.phy_ready_eth(phy_ready_eth)
    );
    udp_telemetry_bridge #(.CLOCK_HZ(100000000),.PACKET_HZ(100)) u_udp (
        .clk_work(clk_work),.clk_eth(clk_eth),
        .rst_work(hw_rst),.rst_eth(reset_eth || !phy_ready_eth),
        .frequency_hz(frequency_hz),.fft_sequence(fft_sequence),
        .laser_error(laser_error),.dac_code(dac_code),
        .temperature_mc(virtual_temperature),.temp_duty(temperature_duty),
        .temp_fault(temp_fault_internal),.temp_pwm(temp_pwm_internal),
        .fft_valid(fft_valid),.auto_state(auto_state),
        .auto_fault(auto_fault),.hw_status(hw_status),
        .fft_enabled(fft_enabled),
        .tx_byte(udp_byte),.tx_en(udp_byte_valid)
    );
endmodule
