// DELIBERATELY INJECTED FAULT; NOT A NATURAL BUG.
`timescale 1ns/1ps
module fir4 (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire in_valid,
    input wire signed [11:0] x_in,
    output reg out_valid,
    output reg signed [11:0] y_out
);
    reg signed [11:0] h1, h2, h3;
    wire signed [15:0] xw = {{4{1'b0}}, x_in};
    wire signed [15:0] h1w = {{4{h1[11]}}, h1};
    wire signed [15:0] h2w = {{4{h2[11]}}, h2};
    wire signed [15:0] h3w = {{4{h3[11]}}, h3};
    wire signed [15:0] mac = xw * 16'sd3 - h1w * 16'sd2
                           + h2w * 16'sd5 - h3w;
    reg signed [15:0] accumulator_q, rounded_q;
    reg s1_valid, s2_valid;

    function automatic signed [15:0] round_div8(input signed [15:0] value);
        reg signed [16:0] magnitude;
        begin
            if (value < 0) begin
                magnitude = -$signed({value[15], value});
                round_div8 = -((magnitude + 17'sd4) >>> 3);
            end else begin
                round_div8 = ($signed({value[15], value}) + 17'sd4) >>> 3;
            end
        end
    endfunction

    function automatic signed [11:0] saturate12(input signed [15:0] value);
        begin
            if (value > 16'sd2047) saturate12 = 12'sh7ff;
            else if (value < -16'sd2048) saturate12 = 12'sh800;
            else saturate12 = value[11:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst || !enable) begin
            h1 <= 0; h2 <= 0; h3 <= 0;
            accumulator_q <= 0; rounded_q <= 0;
            s1_valid <= 0; s2_valid <= 0;
            out_valid <= 0; y_out <= 0;
        end else begin
            s1_valid <= in_valid;
            s2_valid <= s1_valid;
            out_valid <= s2_valid;
            if (in_valid) begin
                accumulator_q <= mac;
                h3 <= h2; h2 <= h1; h1 <= x_in;
            end
            if (s1_valid) rounded_q <= round_div8(accumulator_q);
            if (s2_valid) y_out <= saturate12(rounded_q);
        end
    end
endmodule
