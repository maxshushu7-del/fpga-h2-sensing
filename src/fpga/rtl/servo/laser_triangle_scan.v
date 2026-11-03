`timescale 1ns/1ps
// 100 MHz work-clock triangular scan (DAC CODES, NOT VOLTS).
// No sawtooth reset: every NORMAL scan update changes by <= STEP_LIMIT codes.
// Output clamps to +/- CODE_LIMIT. Config changes to narrower limits also
// slew back toward the new region (no large single-step correction).
// The separate external DAC/laser analog limit MUST be verified before hookup.
module laser_triangle_scan #(
    parameter integer CODE_LIMIT=16384,
    parameter integer STEP_LIMIT=16
)(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire [15:0] half_span,
    input wire [15:0] step_size,
    input wire [31:0] interval_clocks,
    input wire signed [15:0] center,
    output reg signed [15:0] code_out,
    output reg code_valid
);
    localparam [31:0] MIN_INTERVAL=32'd1000;
    reg [31:0] timer;
    reg active, going_up;

    wire [31:0] interval_safe = (interval_clocks<MIN_INTERVAL) ? MIN_INTERVAL : interval_clocks;
    wire signed [31:0] span_safe = (half_span>CODE_LIMIT) ? CODE_LIMIT : $signed({1'b0,half_span});
    wire signed [31:0] center_raw = $signed(center);
    wire signed [31:0] center_safe = (center_raw>CODE_LIMIT) ? CODE_LIMIT :
                                     (center_raw< -CODE_LIMIT) ? -CODE_LIMIT : center_raw;
    wire signed [31:0] raw_hi=center_safe+span_safe;
    wire signed [31:0] raw_lo=center_safe-span_safe;
    wire signed [31:0] hi=(raw_hi>CODE_LIMIT) ? CODE_LIMIT : raw_hi;
    wire signed [31:0] lo=(raw_lo< -CODE_LIMIT) ? -CODE_LIMIT : raw_lo;
    wire signed [31:0] step_safe = (step_size==0) ? 32'sd1 :
                                  (step_size>STEP_LIMIT) ? STEP_LIMIT : $signed({1'b0,step_size});
    wire signed [31:0] cur=$signed(code_out);
    wire signed [31:0] plus_step=cur+step_safe;
    wire signed [31:0] minus_step=cur-step_safe;

    always @(posedge clk) begin
        if (rst) begin
            timer<=0; active<=0; going_up<=1;
            code_out<=0; code_valid<=0;
        end else begin
            code_valid<=0;
            if (!enable) begin
                timer<=0; active<=0; going_up<=1;
                code_out<=0;
            end else if (!active) begin
                active<=1; going_up<=1; timer<=0;
                // Soft-start from DAC zero; slew into an offset range.
                // Never jump straight to a newly configured center.
                code_out<=16'sd0;
                code_valid<=1;
            end else if (timer>=interval_safe-1'b1) begin
                timer<=0;
                code_valid<=1;
                // A parameter change can move both endpoints. Recover at a
                // bounded slew rate instead of jumping to the new endpoint.
                if (cur>hi) begin
                    if(minus_step<hi) code_out<=hi[15:0];
                    else code_out<=minus_step[15:0];
                    going_up<=0;
                end else if (cur<lo) begin
                    if(plus_step>lo) code_out<=lo[15:0];
                    else code_out<=plus_step[15:0];
                    going_up<=1;
                end else if (going_up) begin
                    if(plus_step>=hi) begin code_out<=hi[15:0];going_up<=0;end
                    else code_out<=plus_step[15:0];
                end else begin
                    if(minus_step<=lo) begin code_out<=lo[15:0];going_up<=1;end
                    else code_out<=minus_step[15:0];
                end
            end else timer<=timer+1'b1;
        end
    end
endmodule
