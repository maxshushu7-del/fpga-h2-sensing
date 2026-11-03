`timescale 1ns/1ps
// Multi-cycle fixed-point PI2D. Coefficients: signed 32-bit, 16 fraction bits.
// Integral stores accumulated Ki*e, in signed 48-bit DAC-count Q16 units.
// All state and coefficients advance only on in_valid && in_ready.
module pi2d_controller (
    input wire clk, input wire rst, input wire clear,
    input wire signed [15:0] error_signal,
    input wire in_valid, output wire in_ready,
    input wire signed [31:0] kp, ki, kd, k2,
    input wire [15:0] output_limit,
    input wire [31:0] integral_limit,
    input wire signed [15:0] output_bias,
    input wire [31:0] actuator_scale, input wire [15:0] actuator_limit,
    input wire actuator_invert,
    output reg signed [15:0] control_voltage,
    output reg control_valid,
    output wire signed [47:0] integral_value,
    output reg output_clipped, output reg anti_windup,
    output reg integral_clipped
);
    localparam IDLE=4'd0, MULTIPLY=4'd1, INTEGRATE=4'd2,
               PAIRS=4'd3, NON_I=4'd4, CANDIDATE=4'd5,
               CLIP_CANDIDATE=4'd6, PROJECT=4'd7, DECIDE=4'd8,
               FINAL_SUM=4'd9, OUTPUT=4'd10;
    reg [3:0] state;
    reg signed [15:0] previous_error, older_error, e_hold;
    reg signed [16:0] d_hold;
    reg signed [17:0] d2_hold;
    reg signed [31:0] kp_hold, ki_hold, kd_hold, k2_hold;
    reg [15:0] limit_hold;
    reg [31:0] integral_limit_hold;
    reg signed [15:0] bias_hold;
    reg signed [31:0] scale_hold;
    reg [15:0] actuator_limit_hold;
    reg actuator_invert_hold;
    reg signed [15:0] candidate_code;
    (* use_dsp="yes" *) reg signed [47:0] projected_candidate;
    (* use_dsp = "yes" *) reg signed [47:0] p_product, i_product;
    (* use_dsp = "yes" *) reg signed [48:0] d_product;
    (* use_dsp = "yes" *) reg signed [49:0] d2_product;
    (* mark_debug = "true" *) reg signed [47:0] integral_state;
    reg signed [47:0] i_candidate, i_selected;
    reg signed [63:0] pair_pd, pair_d2_bias, non_i_sum;
    reg signed [63:0] candidate_sum, final_sum;
    reg int_clip_pending, anti_pending;

    wire signed [16:0] e17 = {error_signal[15], error_signal};
    wire signed [16:0] previous17 = {previous_error[15], previous_error};
    wire signed [17:0] e18 = {{2{error_signal[15]}}, error_signal};
    wire signed [17:0] previous18 = {{2{previous_error[15]}}, previous_error};
    wire signed [17:0] older18 = {{2{older_error[15]}}, older_error};
    wire signed [63:0] p64 = {{16{p_product[47]}}, p_product};
    wire signed [63:0] i_delta64 = {{16{i_product[47]}}, i_product};
    wire signed [63:0] d64 = {{15{d_product[48]}}, d_product};
    wire signed [63:0] d2_64 = {{14{d2_product[49]}}, d2_product};
    wire signed [63:0] integral64 = {{16{integral_state[47]}}, integral_state};
    wire signed [63:0] i_trial = integral64 + i_delta64;
    wire signed [63:0] integral_bound = $signed({17'd0, integral_limit_hold[30:0],16'd0});
    wire signed [63:0] actuator_bound = $signed({32'd0, limit_hold, 16'd0});
    wire signed [63:0] bias_q16 = $signed({{48{bias_hold[15]}},bias_hold}) <<< 16;
    wire signed [47:0] physical_candidate = actuator_invert_hold ? -projected_candidate : projected_candidate;
    wire signed [63:0] physical_delta = actuator_invert_hold ? -i_delta64 : i_delta64;
    wire signed [47:0] physical_bound = $signed({16'd0,actuator_limit_hold,16'd0});
    wire reject_integral = ((candidate_sum > actuator_bound) && (i_delta64 > 0)) ||
        ((candidate_sum < -actuator_bound) && (i_delta64 < 0)) ||
        ((physical_candidate > physical_bound) && (physical_delta > 0)) ||
        ((physical_candidate < -physical_bound) && (physical_delta < 0)) ||
        ((scale_hold==0) && (i_delta64!=0));
    wire signed [15:0] candidate_bounded;
    wire unused_candidate_clip;
    saturation u_candidate_limit(.value_in(candidate_sum >>> 16),.limit_in(limit_hold),
        .value_out(candidate_bounded),.clipped(unused_candidate_clip));
    wire signed [63:0] quantized = final_sum >>> 16;
    wire signed [15:0] clipped_voltage;
    wire final_clipped;
    saturation u_saturation(.value_in(quantized), .limit_in(limit_hold),
                            .value_out(clipped_voltage), .clipped(final_clipped));
    assign in_ready = (state == IDLE) && !rst && !clear;
    assign integral_value = integral_state;

    always @(posedge clk) begin
        if (rst || clear) begin
            state <= IDLE;
            previous_error <= 0; older_error <= 0; e_hold <= 0;
            d_hold <= 0; d2_hold <= 0;
            kp_hold <= 0; ki_hold <= 0; kd_hold <= 0; k2_hold <= 0;
            limit_hold <= 0; integral_limit_hold <= 0; bias_hold <= 0;
            scale_hold<=0; actuator_limit_hold<=0; actuator_invert_hold<=0;
            candidate_code<=0; projected_candidate<=0;
            p_product <= 0; i_product <= 0; d_product <= 0; d2_product <= 0;
            integral_state <= 0; i_candidate <= 0; i_selected <= 0;
            pair_pd <= 0; pair_d2_bias <= 0; non_i_sum <= 0;
            candidate_sum <= 0; final_sum <= 0;
            control_voltage <= 0; control_valid <= 0;
            output_clipped <= 0; anti_windup <= 0; integral_clipped <= 0;
            int_clip_pending <= 0; anti_pending <= 0;
        end else begin
            control_valid <= 1'b0;
            case (state)
                IDLE: if (in_valid) begin
                    e_hold <= error_signal;
                    d_hold <= e17 - previous17;
                    d2_hold <= e18 - (previous18 <<< 1) + older18;
                    older_error <= previous_error;
                    previous_error <= error_signal;
                    kp_hold <= kp; ki_hold <= ki; kd_hold <= kd; k2_hold <= k2;
                    limit_hold <= (output_limit > 32767) ? 16'd32767 : output_limit;
                    integral_limit_hold <= integral_limit[31] ? 32'h7fffffff : integral_limit;
                    bias_hold <= output_bias;
                    scale_hold<=actuator_scale[31] ? 32'sh7fffffff : $signed(actuator_scale);
                    actuator_limit_hold<=actuator_limit>32767 ? 16'd32767 : actuator_limit;
                    actuator_invert_hold<=actuator_invert;
                    state <= MULTIPLY;
                end
                MULTIPLY: begin
                    p_product <= kp_hold * e_hold;
                    i_product <= ki_hold * e_hold;
                    d_product <= kd_hold * d_hold;
                    d2_product <= k2_hold * d2_hold;
                    state <= INTEGRATE;
                end
                INTEGRATE: begin
                    int_clip_pending <= 1'b0;
                    if (i_trial > integral_bound) begin
                        i_candidate <= integral_bound[47:0];
                        int_clip_pending <= 1'b1;
                    end else if (i_trial < -integral_bound) begin
                        i_candidate <= -integral_bound;
                        int_clip_pending <= 1'b1;
                    end else i_candidate <= i_trial[47:0];
                    state <= PAIRS;
                end
                PAIRS: begin
                    pair_pd <= p64 + d64;
                    pair_d2_bias <= d2_64 + bias_q16;
                    state <= NON_I;
                end
                NON_I: begin
                    non_i_sum <= pair_pd + pair_d2_bias;
                    state <= CANDIDATE;
                end
                CANDIDATE: begin
                    candidate_sum <= non_i_sum + $signed({{16{i_candidate[47]}},i_candidate});
                    state <= CLIP_CANDIDATE;
                end
                CLIP_CANDIDATE: begin candidate_code<=candidate_bounded; state<=PROJECT; end
                PROJECT: begin projected_candidate<=candidate_code*scale_hold; state<=DECIDE; end
                DECIDE: begin
                    anti_pending <= reject_integral;
                    if (reject_integral) i_selected <= integral_state;
                    else i_selected <= i_candidate;
                    state <= FINAL_SUM;
                end
                FINAL_SUM: begin
                    final_sum <= non_i_sum + $signed({{16{i_selected[47]}},i_selected});
                    integral_state <= i_selected;
                    state <= OUTPUT;
                end
                OUTPUT: begin
                    control_voltage <= clipped_voltage;
                    control_valid <= 1'b1;
                    output_clipped <= final_clipped;
                    anti_windup <= anti_pending;
                    integral_clipped <= int_clip_pending;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
