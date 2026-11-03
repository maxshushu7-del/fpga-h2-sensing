`timescale 1ns/1ps
// Generic NKT E15 actuator code adapter. No electrical tuning type is assumed.
// Three-stage Q16 scaling/inversion/clip pipeline, accepts one item per clock.
module laser_actuator_output (
    input wire clk, input wire rst, input wire clear, input wire enable,
    input wire signed [15:0] control_in, input wire control_valid,
    input wire [31:0] output_scale, input wire [15:0] output_limit,
    input wire polarity_invert,
    output reg signed [15:0] control_voltage, output reg output_valid,
    output reg output_clipped
);
    wire signed [31:0] scale = output_scale[31] ? 32'sh7fffffff : $signed(output_scale);
    (* use_dsp="yes" *) reg signed [47:0] product;
    reg signed [63:0] scaled_integer;
    reg invert1, valid1, valid2;
    reg [15:0] limit1,limit2;
    wire signed [47:0] directed = invert1 ? -product : product;
    wire signed [15:0] bounded;
    wire clipped;
    saturation u_limit(.value_in(scaled_integer),.limit_in(limit2),.value_out(bounded),.clipped(clipped));
    always @(posedge clk) begin
        if(rst || clear || !enable) begin
            product<=0; scaled_integer<=0; invert1<=0; valid1<=0; valid2<=0;
            limit1<=0; limit2<=0; control_voltage<=0; output_valid<=0; output_clipped<=0;
        end else begin
            valid1<=control_valid; valid2<=valid1; output_valid<=valid2;
            if(control_valid) begin
                product<=control_in*scale; invert1<=polarity_invert;
                limit1<=output_limit>32767 ? 16'd32767 : output_limit;
            end
            if(valid1) begin scaled_integer<=directed >>> 16; limit2<=limit1; end
            if(valid2) begin control_voltage<=bounded; output_clipped<=clipped; end
        end
    end
endmodule
