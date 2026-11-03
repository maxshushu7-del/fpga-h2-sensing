`timescale 1ns/1ps
// PD1/TIA input from an AD9643BCPZ-250 (14-bit, up to 250 MSPS, LVDS).
// This is the already-deserialized/resampled abstraction, in the 100 MHz clk
// domain. The 250 MHz LVDS PHY, ADC SPI and CDC/decimator are future adapters.
module adc_interface (
    input wire clk, input wire rst, input wire clear,
    input wire signed [13:0] adc_data_in,
    input wire adc_valid, input wire adc_ready,
    input wire signed [15:0] offset,
    output reg signed [15:0] sample_out,
    output reg sample_valid, output reg input_clipped
);
    wire signed [16:0] raw_extended = {{3{adc_data_in[13]}}, adc_data_in};
    wire signed [16:0] offset_extended = {offset[15], offset};
    wire signed [16:0] corrected = raw_extended - offset_extended;
    always @(posedge clk) begin
        if (rst || clear) begin
            sample_out <= 16'sd0;
            sample_valid <= 1'b0;
            input_clipped <= 1'b0;
        end else begin
            sample_valid <= adc_valid && adc_ready;
            if (adc_valid && adc_ready) begin
                input_clipped <= 1'b0;
                if (corrected > 17'sd32767) begin
                    sample_out <= 16'sd32767;
                    input_clipped <= 1'b1;
                end else if (corrected < -17'sd32768) begin
                    sample_out <= -16'sd32768;
                    input_clipped <= 1'b1;
                end else sample_out <= corrected[15:0];
            end
        end
    end
endmodule
