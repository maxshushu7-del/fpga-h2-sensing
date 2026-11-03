`timescale 1ns/1ps
module laser_lock_top #(parameter ENABLE_ILA = 0, parameter integer LOCK_POLARITY=1, parameter integer AUTONOMOUS=0) (
    input wire clk_200m_p, input wire clk_200m_n, input wire rst_n,
    input wire signed [13:0] adc_data_in, input wire adc_valid,
    output wire adc_ready,
    output wire signed [15:0] dac_data_out, output wire dac_valid,
    input wire cfg_we, input wire [7:0] cfg_addr, input wire [31:0] cfg_wdata,
    input wire auto_servo_enable, input wire signed [15:0] auto_setpoint,
    input wire auto_error_invert, input wire auto_clear,
    output wire [31:0] cfg_rdata, output wire cfg_ready,
    output wire cfg_ack, output wire cfg_error,
    output wire clk_work_out, output wire clock_locked,
    output wire signed [31:0] ila_error,
    output wire signed [31:0] ila_control_output,
    output wire signed [47:0] ila_integral,
    output wire [7:0] status
);
    wire clk_work, clk_200MHz, rst, config_clear;
    wire signed [31:0] kp,ki,kd,k2;
    wire [15:0] output_limit;
    wire [31:0] integral_limit;
    wire servo_enable, filter_enable, error_invert;
    wire signed [15:0] adc_offset,setpoint,output_bias;
    wire [31:0] servo_period,loop_gain,actuator_scale,servo_update_count,skipped_ticks;
    wire [15:0] actuator_limit;
    wire lock_negative,enable_offset_correction,actuator_invert;
    wire auto_servo = AUTONOMOUS!=0 && auto_servo_enable;
    wire active_servo_enable = servo_enable || auto_servo;
    wire signed [15:0] effective_setpoint = auto_servo ? auto_setpoint : setpoint;
    wire effective_error_invert = error_invert ^ (AUTONOMOUS!=0 && auto_error_invert);
    wire clear = config_clear || (AUTONOMOUS!=0 && auto_clear);
    clock_manager u_clock(.clk_200m_p(clk_200m_p), .clk_200m_n(clk_200m_n),
        .rst_n(rst_n), .clk_200MHz(clk_200MHz), .clk_work(clk_work),
        .locked(clock_locked), .rst(rst));
    assign clk_work_out = clk_work;
    reg transaction_busy;
    wire busy;
    reg [31:0] sample_count;
    // ADC/filtering continue while a servo transaction runs. Configuration
    // waits for retirement and blocks input while a write request is pending.
    assign cfg_ready = !busy && !rst;
    assign adc_ready = !rst && !cfg_we && active_servo_enable;
    wire accepted = adc_valid && adc_ready;
    wire signed [15:0] adc_sample, filtered_sample;
    wire adc_sample_valid, filtered_valid, input_clipped;
    adc_interface u_adc(.clk(clk_work), .rst(rst), .clear(clear),
        .adc_data_in(adc_data_in), .adc_valid(adc_valid), .adc_ready(adc_ready),
        .offset(adc_offset), .sample_out(adc_sample),
        .sample_valid(adc_sample_valid), .input_clipped(input_clipped));
    error_filter u_filter(.clk(clk_work), .rst(rst), .clear(clear),
        .filter_enable(filter_enable), .sample_in(adc_sample),
        .sample_valid(adc_sample_valid), .filtered_out(filtered_sample),
        .filtered_valid(filtered_valid));
    wire signed [16:0] calibrated_error;
    wire calibrated_valid;
    reg filtered_adc_clip,calibrated_adc_clip;
    always @(posedge clk_work) begin
        if (rst || clear) begin
            filtered_adc_clip<=0; calibrated_adc_clip<=0;
        end else begin
            if(adc_sample_valid) filtered_adc_clip<=input_clipped;
            if(filtered_valid) calibrated_adc_clip<=filtered_adc_clip;
        end
    end
    lock_point_calibration u_calibration(.clk(clk_work),.rst(rst),.clear(clear),
        .sample_in(filtered_sample),.sample_valid(filtered_valid),.lock_offset(effective_setpoint),
        .enable_offset_correction(enable_offset_correction),.calibrated_error(calibrated_error),
        .calibrated_valid(calibrated_valid));
    wire signed [15:0] normalized_error;
    wire normalized_valid,normalized_clip,normalized_adc_clip;
    locking_error_normalizer u_normalizer(.clk(clk_work),.rst(rst),.clear(clear),
        .calibrated_error(calibrated_error),.in_valid(calibrated_valid),
        .input_clipped(calibrated_adc_clip),.loop_gain(loop_gain),.lock_negative(lock_negative),
        .error_invert(effective_error_invert),.error_signal(normalized_error),.out_valid(normalized_valid),
        .error_clipped(normalized_clip),.adc_clipped_out(normalized_adc_clip));
    (* mark_debug="true" *) wire signed [15:0] error_signal;
    wire servo_error_valid,servo_tick;
    wire [1:0] servo_flags;
    wire controller_ready;
    assign busy=transaction_busy || servo_error_valid;
    servo_scheduler u_scheduler(.clk(clk_work),.rst(rst),.clear(clear),.enable(active_servo_enable),
        .update_period(servo_period),.downstream_ready(controller_ready && !busy && !cfg_we),
        .measurement(normalized_error),.measurement_valid(normalized_valid),
        .measurement_flags({normalized_clip,normalized_adc_clip}),.servo_error(error_signal),
        .servo_valid(servo_error_valid),.servo_flags(servo_flags),.servo_tick(servo_tick),
        .update_count(servo_update_count),.skipped_ticks(skipped_ticks));
    wire signed [15:0] control_voltage;
    wire control_valid, output_clipped, anti_windup, integral_clipped;
    pi2d_controller u_controller(.clk(clk_work), .rst(rst), .clear(clear),
        .error_signal(error_signal), .in_valid(servo_error_valid), .in_ready(controller_ready),
        .kp(kp), .ki(ki), .kd(kd), .k2(k2), .output_limit(output_limit),
        .integral_limit(integral_limit), .output_bias(output_bias),
        .actuator_scale(actuator_scale),.actuator_limit(actuator_limit),.actuator_invert(actuator_invert),
        .control_voltage(control_voltage), .control_valid(control_valid),
        .integral_value(ila_integral), .output_clipped(output_clipped),
        .anti_windup(anti_windup), .integral_clipped(integral_clipped));
    wire signed [15:0] actuator_voltage;
    wire actuator_valid,actuator_clipped;
    laser_actuator_output u_actuator(.clk(clk_work),.rst(rst),.clear(clear),.enable(active_servo_enable),
        .control_in(control_voltage),.control_valid(control_valid),.output_scale(actuator_scale),
        .output_limit(actuator_limit),.polarity_invert(actuator_invert),
        .control_voltage(actuator_voltage),.output_valid(actuator_valid),.output_clipped(actuator_clipped));
    dac_interface u_dac(.clk(clk_work), .rst(rst), .clear(clear), .enable(active_servo_enable),
        .control_in(actuator_voltage), .control_valid(actuator_valid),
        .dac_data_out(dac_data_out), .dac_valid(dac_valid));
    always @(posedge clk_work) begin
        if (rst) begin transaction_busy <= 0; sample_count <= 0; end
        else begin
            if (clear || dac_valid) transaction_busy <= 0;
            else if (servo_error_valid) transaction_busy <= 1;
            if (accepted) sample_count <= sample_count + 1'b1;
        end
    end
    assign ila_error = {{16{error_signal[15]}},error_signal};
    assign ila_control_output = {{16{dac_data_out[15]}},dac_data_out};
    assign status = {servo_flags[1],servo_flags[0],integral_clipped,anti_windup,
                     output_clipped || actuator_clipped,busy,active_servo_enable,clock_locked};
    parameter_register #(.LOCK_POLARITY(LOCK_POLARITY)) u_parameters(.clk(clk_work), .rst(rst),
        .cfg_we(cfg_we), .cfg_ready(cfg_ready), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .cfg_rdata(cfg_rdata), .cfg_ack(cfg_ack), .cfg_error(cfg_error), .state_clear(config_clear),
        .kp(kp), .ki(ki), .kd(kd), .k2(k2), .output_limit(output_limit),
        .integral_limit(integral_limit), .servo_enable(servo_enable),
        .filter_enable(filter_enable), .error_invert(error_invert), .adc_offset(adc_offset),
        .setpoint(setpoint), .output_bias(output_bias), .status(status),
        .servo_period(servo_period),.loop_gain(loop_gain),.actuator_scale(actuator_scale),
        .actuator_limit(actuator_limit),.lock_negative(lock_negative),
        .enable_offset_correction(enable_offset_correction),.actuator_invert(actuator_invert),
        .last_error(error_signal), .last_output(dac_data_out),
        .integral_value(ila_integral), .sample_count(sample_count),
        .servo_update_count(servo_update_count),.skipped_ticks(skipped_ticks));
    generate if (ENABLE_ILA != 0) begin : g_ila
        // Built-in Vivado ILA IP is created by scripts/create_project.tcl.
        laser_lock_ila u_ila(.clk(clk_work), .probe0(error_signal),
            .probe1(dac_data_out), .probe2(ila_integral), .probe3(status),
            .probe4(dac_valid), .probe5(adc_ready));
    end endgenerate
endmodule
