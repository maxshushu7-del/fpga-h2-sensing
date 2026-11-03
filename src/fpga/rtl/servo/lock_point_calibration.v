`timescale 1ns/1ps
// PD1/TIA lock point, in corrected/filtered ADC codes; this is not volts.
module lock_point_calibration (
    input wire clk, input wire rst, input wire clear,
    input wire signed [15:0] sample_in, input wire sample_valid,
    input wire signed [15:0] lock_offset, input wire enable_offset_correction,
    output reg signed [16:0] calibrated_error, output reg calibrated_valid
);
    wire signed [16:0] sample17 = {sample_in[15],sample_in};
    wire signed [16:0] offset17 = {lock_offset[15],lock_offset};
    always @(posedge clk) begin
        if (rst || clear) begin calibrated_error <= 0; calibrated_valid <= 0; end
        else begin
            calibrated_valid <= sample_valid;
            if(sample_valid) calibrated_error <= enable_offset_correction ? sample17-offset17 : sample17;
        end
    end
endmodule
