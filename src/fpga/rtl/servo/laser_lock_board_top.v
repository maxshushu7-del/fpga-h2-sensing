`timescale 1ns/1ps
// Project-level wrapper. Debug buses stay internal and feed the built-in ILA;
// exporting all debug bits as package pins would exceed this device's I/O count.
module laser_lock_board_top #(parameter ENABLE_ILA = 1, parameter integer LOCK_POLARITY=1) (
    input wire clk_200m_p, input wire clk_200m_n, input wire rst_n,
    input wire signed [13:0] adc_data_in, input wire adc_valid,
    output wire adc_ready,
    output wire signed [15:0] dac_data_out, output wire dac_valid,
    input wire cfg_we, input wire [7:0] cfg_addr, input wire [31:0] cfg_wdata,
    output wire [31:0] cfg_rdata, output wire cfg_ready,
    output wire cfg_ack, output wire cfg_error,
    output wire clk_work_out, output wire clock_locked,
    output wire [7:0] status
);
    wire signed [31:0] ila_error, ila_control_output;
    wire signed [47:0] ila_integral;
    laser_lock_top #(.ENABLE_ILA(ENABLE_ILA),.LOCK_POLARITY(LOCK_POLARITY)) u_core (
        .clk_200m_p(clk_200m_p), .clk_200m_n(clk_200m_n), .rst_n(rst_n),
        .adc_data_in(adc_data_in), .adc_valid(adc_valid), .adc_ready(adc_ready),
        .dac_data_out(dac_data_out), .dac_valid(dac_valid),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .cfg_rdata(cfg_rdata), .cfg_ready(cfg_ready), .cfg_ack(cfg_ack), .cfg_error(cfg_error),
        .clk_work_out(clk_work_out), .clock_locked(clock_locked), .status(status),
        .ila_error(ila_error), .ila_control_output(ila_control_output), .ila_integral(ila_integral));
endmodule
