`timescale 1ns/1ps
// Fixed-period samples, millidegrees C, Q16 duty-count/mC gains.
// Ki contains sample period; Kd contains inverse sample period.
// D acts on measurement to avoid setpoint derivative kick.
module temperature_pid #(
    parameter integer TIMEOUT_CYCLES=20000000,
    parameter integer MIN_TEMP_MC=0, MAX_TEMP_MC=80000
)(
    input wire clk,rst,enable,clear_fault,sample_valid,sensor_fault,
    input wire signed [31:0] temperature_mc,setpoint_mc,
    input wire [31:0] kp_q16,ki_q16,kd_q16,
    input wire [15:0] duty_limit,
    output reg [15:0] duty,
    output reg fault,
    output reg signed [31:0] error_mc
);
    reg [31:0] age;
    reg have_previous;
    reg signed [31:0] previous_temperature;
    reg signed [63:0] integral_q16,e,p,d,step_i,next_i,u,limit_q16,delta_t;
    wire invalid_sample=temperature_mc<MIN_TEMP_MC || temperature_mc>=MAX_TEMP_MC;
    wire invalid_config=setpoint_mc<MIN_TEMP_MC || setpoint_mc>70000 ||
        kp_q16>16777216 || ki_q16>16777216 || kd_q16>16777216;
    always @(posedge clk) begin
        if(rst) begin
            age<=0;have_previous<=0;previous_temperature<=0;
            integral_q16<=0;duty<=0;fault<=0;error_mc<=0;
        end else begin
            if(!enable || sample_valid) age<=0;
            else if(age<TIMEOUT_CYCLES) age<=age+1;
            if(clear_fault && !enable) begin
                fault<=0;duty<=0;integral_q16<=0;have_previous<=0;error_mc<=0;
            end else if(sensor_fault || (sample_valid && invalid_sample) ||
                        (enable && invalid_config) ||
                        (enable && !sample_valid && age>=TIMEOUT_CYCLES-1)) begin
                fault<=1;duty<=0;integral_q16<=0;have_previous<=0;
            end else if(!enable || fault) begin
                duty<=0;integral_q16<=0;have_previous<=0;error_mc<=0;
            end else if(sample_valid) begin
                e=$signed(setpoint_mc);e=e-$signed(temperature_mc);
                p=e*$signed({1'b0,kp_q16});
                delta_t=$signed(previous_temperature);
                delta_t=delta_t-$signed(temperature_mc);
                d=have_previous ? delta_t*$signed({1'b0,kd_q16}) : 64'sd0;
                step_i=e*$signed({1'b0,ki_q16});
                next_i=integral_q16+step_i;
                limit_q16=$signed({1'b0,duty_limit})*64'sd65536;
                u=p+next_i+d;
                if(!((u>limit_q16 && step_i>0)||(u<0 && step_i<0)))
                    integral_q16<=next_i;
                else u=p+integral_q16+d;
                if(u<=0)duty<=0;
                else if(u>=limit_q16)duty<=duty_limit;
                else duty<=u>>>16;
                previous_temperature<=temperature_mc;have_previous<=1;
                error_mc<=e[31:0];
            end
        end
    end
endmodule
