`timescale 1ns/1ps
// Signed DAC-code limiter + bounded slew in the 100MHz clk_work domain.
// The low/high bounds must be externally calibrated to physical volts.
// This module cannot protect against analog offset, gain, wiring faults,
// transmit disable / reset going to code zero, or interface incompatibility.
module laser_code_guard(
    input wire clk,input wire rst,input wire enable,
    input wire signed [15:0] target_code,
    input wire signed [15:0] min_code,max_code,
    input wire [15:0] max_step,input wire [31:0] interval_clocks,
    output reg signed [15:0] applied_code,output reg applied_valid
);
    reg [31:0] timer;
    wire [31:0] interval_safe=(interval_clocks<32'd1000)?32'd1000:interval_clocks;
    wire signed [31:0] step_safe=(max_step==0)?32'sd1:
                   (max_step>16)?32'sd16:$signed({16'b0,max_step});
    wire signed [31:0] lo=$signed(min_code),hi=$signed(max_code);
    wire signed [31:0] desired=($signed(target_code)<lo)?lo:
                           ($signed(target_code)>hi)?hi:$signed(target_code);
    wire signed [31:0] delta=desired-$signed(applied_code);
    wire signed [31:0] next_code=(delta>step_safe)?$signed(applied_code)+step_safe:
                  (delta< -step_safe)?$signed(applied_code)-step_safe:desired;
    always @(posedge clk)begin
        if(rst || !enable)begin
            applied_code<=0;applied_valid<=0;timer<=0;
        end else begin
            applied_valid<=0;
            if(timer>=interval_safe-1)begin
                timer<=0;
                applied_code<=next_code[15:0];
                applied_valid<=1;
            end else timer<=timer+1'b1;
        end
    end
endmodule
