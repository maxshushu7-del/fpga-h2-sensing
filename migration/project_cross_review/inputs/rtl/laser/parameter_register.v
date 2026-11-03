`timescale 1ns/1ps
// Simple synchronous write / combinational read register interface, no AXI.
module parameter_register #(parameter integer LOCK_POLARITY=1) (
    input wire clk, input wire rst,
    input wire cfg_we, input wire cfg_ready,
    input wire [7:0] cfg_addr, input wire [31:0] cfg_wdata,
    output reg [31:0] cfg_rdata, output reg cfg_ack, output reg cfg_error,
    output wire state_clear,
    output reg signed [31:0] kp, ki, kd, k2,
    output reg [15:0] output_limit,
    output reg [31:0] integral_limit,
    output reg servo_enable, filter_enable, error_invert,
    output reg signed [15:0] adc_offset, setpoint, output_bias,
    output reg [31:0] servo_period,loop_gain,actuator_scale,
    output reg [15:0] actuator_limit,
    output reg lock_negative,enable_offset_correction,actuator_invert,
    input wire [7:0] status,
    input wire signed [15:0] last_error, last_output,
    input wire signed [47:0] integral_value,
    input wire [31:0] sample_count,
    input wire [31:0] servo_update_count,skipped_ticks
);
    wire writable = cfg_addr == 8'h00 || cfg_addr == 8'h04 ||
        cfg_addr == 8'h08 || cfg_addr == 8'h0c || cfg_addr == 8'h10 ||
        cfg_addr == 8'h14 || cfg_addr == 8'h18 || cfg_addr == 8'h1c ||
        cfg_addr == 8'h20 || cfg_addr == 8'h24 || cfg_addr == 8'h40 ||
        cfg_addr == 8'h44 || cfg_addr == 8'h48 || cfg_addr == 8'h4c ||
        cfg_addr == 8'h50 || cfg_addr == 8'h54 || cfg_addr == 8'h58;
    wire valid_value = (cfg_addr!=8'h48) || cfg_wdata==32'd1 || cfg_wdata==32'hffffffff;
    assign state_clear = cfg_we && cfg_ready && writable && valid_value && !rst;
    always @(posedge clk) begin
        if (rst) begin
            kp <= 32'sd65536; ki <= 32'sd256; kd <= 0; k2 <= 0;
            output_limit <= 16'd16384; integral_limit <= 32'd32767;
            servo_enable <= 0; filter_enable <= 0; error_invert <= 0;
            adc_offset <= 0; setpoint <= 0; output_bias <= 0;
            servo_period<=1000; loop_gain<=65536; actuator_scale<=65536;
            actuator_limit<=16384; lock_negative<=(LOCK_POLARITY<0);
            enable_offset_correction<=1; actuator_invert<=0;
            cfg_ack <= 0; cfg_error <= 0;
        end else begin
            cfg_ack <= cfg_we && cfg_ready;
            cfg_error <= cfg_we && cfg_ready && (!writable || !valid_value);
            if (cfg_we && cfg_ready && writable && valid_value) begin
                case(cfg_addr)
                    8'h00: kp <= cfg_wdata;
                    8'h04: ki <= cfg_wdata;
                    8'h08: kd <= cfg_wdata;
                    8'h0c: k2 <= cfg_wdata;
                    8'h10: output_limit <= (cfg_wdata[15:0] > 32767) ? 16'd32767 : cfg_wdata[15:0];
                    8'h14: begin
                        servo_enable <= cfg_wdata[0];
                        filter_enable <= cfg_wdata[1];
                        error_invert <= cfg_wdata[2];
                    end
                    8'h18: adc_offset <= cfg_wdata[15:0];
                    8'h1c: setpoint <= cfg_wdata[15:0];
                    8'h20: output_bias <= cfg_wdata[15:0];
                    8'h24: integral_limit <= cfg_wdata[31] ? 32'h7fffffff : cfg_wdata;
                    8'h40: servo_period<=cfg_wdata<64 ? 32'd64 : cfg_wdata;
                    8'h44: loop_gain<=cfg_wdata[31] ? 32'h7fffffff : cfg_wdata;
                    8'h48: lock_negative<=cfg_wdata==32'hffffffff;
                    8'h4c: enable_offset_correction<=cfg_wdata[0];
                    8'h50: actuator_scale<=cfg_wdata[31] ? 32'h7fffffff : cfg_wdata;
                    8'h54: actuator_limit<=cfg_wdata[15:0]>32767 ? 16'd32767 : cfg_wdata[15:0];
                    8'h58: actuator_invert<=cfg_wdata[0];
                    default: begin end
                endcase
            end
        end
    end
    always @* begin
        case(cfg_addr)
            8'h00: cfg_rdata = kp;
            8'h04: cfg_rdata = ki;
            8'h08: cfg_rdata = kd;
            8'h0c: cfg_rdata = k2;
            8'h10: cfg_rdata = {16'd0,output_limit};
            8'h14: cfg_rdata = {29'd0,error_invert,filter_enable,servo_enable};
            8'h18: cfg_rdata = {{16{adc_offset[15]}},adc_offset};
            8'h1c: cfg_rdata = {{16{setpoint[15]}},setpoint};
            8'h20: cfg_rdata = {{16{output_bias[15]}},output_bias};
            8'h24: cfg_rdata = integral_limit;
            8'h28: cfg_rdata = {24'd0,status};
            8'h2c: cfg_rdata = {{16{last_error[15]}},last_error};
            8'h30: cfg_rdata = {{16{last_output[15]}},last_output};
            8'h34: cfg_rdata = integral_value[31:0];
            8'h38: cfg_rdata = {{16{integral_value[47]}},integral_value[47:32]};
            8'h3c: cfg_rdata = sample_count;
            8'h40: cfg_rdata = servo_period;
            8'h44: cfg_rdata = loop_gain;
            8'h48: cfg_rdata = lock_negative ? 32'hffffffff : 32'd1;
            8'h4c: cfg_rdata = {31'd0,enable_offset_correction};
            8'h50: cfg_rdata = actuator_scale;
            8'h54: cfg_rdata = {16'd0,actuator_limit};
            8'h58: cfg_rdata = {31'd0,actuator_invert};
            8'h60: cfg_rdata = servo_update_count;
            8'h64: cfg_rdata = skipped_ticks;
            default: cfg_rdata = 32'd0;
        endcase
    end
endmodule
