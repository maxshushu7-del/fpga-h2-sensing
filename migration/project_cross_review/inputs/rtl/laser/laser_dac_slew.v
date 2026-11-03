`timescale 1ns/1ps
// Limit HOW FAST DAC codes may change. Does not limit actual voltage!
// Runs at 100 MHz; max one DAC code every SLEW_PERIOD clocks.
module laser_dac_slew #(parameter integer SLEW_PERIOD=1000) (
    input wire clk,input wire rst,input wire enable,
    input wire signed [15:0] goal_code,
    output reg signed [15:0] output_code,
    output reg output_valid,
    output wire goal_reached
);
    reg [31:0] interval_count;
    assign goal_reached=(output_code==goal_code);
    always @(posedge clk) begin
        if(rst || !enable) begin
            interval_count<=0;output_code<=0;output_valid<=0;
        end else begin
            output_valid<=0;
            if(output_code==goal_code) interval_count<=0;
            else if(interval_count>=SLEW_PERIOD-1) begin
                interval_count<=0;
                if(output_code<goal_code) output_code<=output_code+16'sd1;
                else output_code<=output_code-16'sd1;
                output_valid<=1;
            end else interval_count<=interval_count+1'b1;
        end
    end
endmodule
