`timescale 1ns/1ps
// Digital replacement of the temperature console's PID function.
// Sensor calibration/ADC and power stage are external, not the RF ADC/DAC.
module temperature_peripheral #(
    parameter integer TIMEOUT_CYCLES=20000000
)(
    input wire clk,rst,
    input wire cfg_we,
    input wire [7:0] cfg_addr,
    input wire [31:0] cfg_wdata,
    output reg [31:0] cfg_rdata,
    output reg cfg_error,
    input wire signed [31:0] temperature_mc,
    input wire sample_valid,sensor_fault,
    output wire heater_pwm,
    output wire fault,
    output wire [15:0] duty
);
    reg enabled,armed;
    reg signed [31:0] setpoint_mc;
    reg [31:0] kp_q16,ki_q16,kd_q16;
    reg [15:0] duty_limit;
    reg signed [31:0] last_temperature;
    wire signed [31:0] error_mc;
    wire clear_fault=cfg_we && cfg_addr==8'h5c && cfg_wdata==2 && !enabled;
    always @* begin
        cfg_error=0;
        if(cfg_we)case(cfg_addr)
            8'h5c:cfg_error=(cfg_wdata>2)||
                (cfg_wdata==1 && (!armed || fault || duty_limit==0))||
                (cfg_wdata==2 && enabled);
            8'h68:cfg_error=enabled || $signed(cfg_wdata)<0 || $signed(cfg_wdata)>70000;
            8'h6c,8'h94,8'h98:cfg_error=enabled || cfg_wdata>16777216;
            8'h9c:cfg_error=enabled || cfg_wdata>65535;
            8'hf8:cfg_error=enabled || cfg_wdata!=32'h54454d50;
            default:cfg_error=1;
        endcase
    end
    always @(posedge clk) begin
        if(rst)begin
            enabled<=0;armed<=0;setpoint_mc<=40000;
            kp_q16<=262144;ki_q16<=655;kd_q16<=0;
            duty_limit<=0;last_temperature<=0;
        end else begin
            if(sample_valid)last_temperature<=temperature_mc;
            if(cfg_we && !cfg_error)case(cfg_addr)
                8'h5c:begin
                    enabled<=cfg_wdata==1;
                    if(cfg_wdata==2)armed<=0;
                end
                8'h68:begin setpoint_mc<=cfg_wdata;armed<=0;end
                8'h6c:begin kp_q16<=cfg_wdata;armed<=0;end
                8'h94:begin ki_q16<=cfg_wdata;armed<=0;end
                8'h98:begin kd_q16<=cfg_wdata;armed<=0;end
                8'h9c:begin duty_limit<=cfg_wdata[15:0];armed<=0;end
                8'hf8:armed<=1;
                default:begin end
            endcase
        end
    end
    always @* begin
        case(cfg_addr)
            8'h5c:cfg_rdata={31'd0,enabled};
            8'h68:cfg_rdata=setpoint_mc;
            8'h6c:cfg_rdata=kp_q16;
            8'h94:cfg_rdata=ki_q16;
            8'h98:cfg_rdata=kd_q16;
            8'h9c:cfg_rdata={16'd0,duty_limit};
            8'hf8:cfg_rdata={duty,13'd0,armed,fault,enabled};
            8'hfc:cfg_rdata=last_temperature;
            default:cfg_rdata=0;
        endcase
    end
    temperature_pid #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) pid(
        .clk(clk),.rst(rst),.enable(enabled),.clear_fault(clear_fault),
        .sample_valid(sample_valid && enabled),.sensor_fault(sensor_fault),
        .temperature_mc(temperature_mc),.setpoint_mc(setpoint_mc),
        .kp_q16(kp_q16),.ki_q16(ki_q16),.kd_q16(kd_q16),.duty_limit(duty_limit),
        .duty(duty),.fault(fault),.error_mc(error_mc));
    // Fault gate is independent of stored duty and PWM counter state.
    heater_pwm pwm(.clk(clk),.rst_n(!rst),
        .safety_enable(enabled && !fault && !sensor_fault),
        .duty(duty),.heater_on(heater_pwm));
endmodule
