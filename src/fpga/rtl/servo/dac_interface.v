`timescale 1ns/1ps
// Retained signed parallel DAC handoff after laser_actuator_output scaling.
// No NKT E15 tuning protocol, DAC PHY, volts-per-code or current range is implied.
module dac_interface (
    input wire clk, input wire rst, input wire clear, input wire enable,
    input wire signed [15:0] control_in, input wire control_valid,
    output reg signed [15:0] dac_data_out, output reg dac_valid
);
    always @(posedge clk) begin
        if (rst || clear || !enable) begin
            dac_data_out <= 16'sd0;
            dac_valid <= 1'b0;
        end else begin
            dac_valid <= control_valid;
            if (control_valid) dac_data_out <= control_in;
        end
    end
endmodule
