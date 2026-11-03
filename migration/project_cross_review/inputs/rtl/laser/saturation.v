`timescale 1ns/1ps
// Signed 64-bit integer to a symmetric 16-bit actuator range.
module saturation (
    input  wire signed [63:0] value_in,
    input  wire        [15:0] limit_in,
    output reg  signed [15:0] value_out,
    output reg               clipped
);
    wire [15:0] safe_limit = (limit_in > 16'd32767) ? 16'd32767 : limit_in;
    wire signed [63:0] upper = $signed({48'd0, safe_limit});
    wire signed [63:0] lower = -upper;
    always @* begin
        clipped = 1'b0;
        if (value_in > upper) begin
            value_out = $signed(safe_limit);
            clipped = 1'b1;
        end else if (value_in < lower) begin
            value_out = -$signed(safe_limit);
            clipped = 1'b1;
        end else begin
            value_out = value_in[15:0];
        end
    end
endmodule
