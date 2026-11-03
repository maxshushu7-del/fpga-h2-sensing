`timescale 1ns/1ps
// Compile-time/demo only. No TEC200 electrical interface is claimed.
// An internal thermal first-order model driven by the PID's internal PWM.
// Sample period = 10 ms at 100 MHz; temperature units = milli Celsius.
module tec200_virtual_plant #(
    parameter integer CLK_HZ = 100000000,
    parameter integer SAMPLE_HZ = 100
)(
    input wire clk,
    input wire rst,
    input wire heater_pwm_internal,
    output reg signed [31:0] temperature_mc = 32'sd25000,
    output reg sample_valid = 1'b0
);
    localparam integer TICKS = CLK_HZ/SAMPLE_HZ;
    reg [31:0] timer = 0;
    reg [31:0] heater_count = 0;
    wire signed [31:0] cooling = (temperature_mc-32'sd25000) >>> 7;
    // No driving hardware: model influences only virtual temperature.
    wire signed [31:0] proposed = temperature_mc
                                  + $signed({1'b0,heater_count[31:12]})
                                  - cooling;
    always @(posedge clk) begin
        if (rst) begin
            timer <= 0;
            heater_count <= 0;
            temperature_mc <= 32'sd25000;
            sample_valid <= 0;
        end else begin
            sample_valid <= 0;
            if (timer == TICKS-1) begin
                timer <= 0;
                heater_count <= 0;
                sample_valid <= 1;
                if (proposed < 32'sd15000)
                    temperature_mc <= 32'sd15000;
                else if (proposed > 32'sd65000)
                    temperature_mc <= 32'sd65000;
                else
                    temperature_mc <= proposed;
            end else begin
                timer <= timer+1'b1;
                if (heater_pwm_internal) heater_count <= heater_count+1'b1;
            end
        end
    end
endmodule
