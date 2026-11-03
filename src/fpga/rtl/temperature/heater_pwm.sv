`timescale 1ns/1ps
// PWM frequency = clk frequency / 65536. 100% duty is supported.
// safety_enable should include rst_n, enable and !fault at integration.
module heater_pwm(
    input wire clk, input wire rst_n, input wire safety_enable,
    input wire [15:0] duty,
    output wire heater_on
);
    reg [15:0] counter;
    always @(posedge clk)
        if (!rst_n) counter <= 0;
        else counter <= counter + 1'b1;
    assign heater_on = rst_n && safety_enable &&
                       ((duty == 16'hffff) || (counter < duty));
endmodule
