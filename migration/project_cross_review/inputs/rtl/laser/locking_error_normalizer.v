`timescale 1ns/1ps
// e = -LOCK_POLARITY * (PD-lock_offset) * loop_gain, then signed16 clip.
// +1 means a positive optical slope; actuator frequency direction is separate.
module locking_error_normalizer (
    input wire clk, input wire rst, input wire clear,
    input wire signed [16:0] calibrated_error, input wire in_valid,
    input wire input_clipped, input wire [31:0] loop_gain,
    input wire lock_negative, input wire error_invert,
    output reg signed [15:0] error_signal, output reg out_valid,
    output reg error_clipped, output reg adc_clipped_out
);
    wire signed [31:0] gain = loop_gain[31] ? 32'sh7fffffff : $signed(loop_gain);
    (* use_dsp="yes" *) reg signed [48:0] product;
    reg signed [63:0] normalized;
    reg negate1, valid1, valid2, adc_clip1, adc_clip2;
    wire signed [48:0] directed = negate1 ? -product : product;
    always @(posedge clk) begin
        if (rst || clear) begin
            product<=0; normalized<=0; negate1<=0; valid1<=0; valid2<=0;
            adc_clip1<=0; adc_clip2<=0; error_signal<=0; out_valid<=0;
            error_clipped<=0; adc_clipped_out<=0;
        end else begin
            valid1<=in_valid; valid2<=valid1; out_valid<=valid2;
            if(in_valid) begin
                product<=calibrated_error*gain;
                negate1<=!(lock_negative ^ error_invert);
                adc_clip1<=input_clipped;
            end
            if(valid1) begin normalized<=directed >>> 16; adc_clip2<=adc_clip1; end
            if(valid2) begin
                adc_clipped_out<=adc_clip2; error_clipped<=0;
                if(normalized>32767) begin error_signal<=32767; error_clipped<=1; end
                else if(normalized< -32768) begin error_signal<=-32768; error_clipped<=1; end
                else error_signal<=normalized[15:0];
            end
        end
    end
endmodule
