`timescale 1ns/1ps
// Automatic coarse sweep -> fine sweep -> falling-edge acquisition -> PID.
// All quantities here are ADC/DAC CODES (not volts or optical frequencies).
// Scan advances only after the post-slew output is at the requested code and
// a dwell interval plus four fresh ADC samples have elapsed.
// Coarse scans upward then slews back down (no sawtooth jump).
// The deepest coarse valley is selected; fine chooses maximum negative dADC/dCODE.
// This is a first-pass heuristic, NOT a guarantee of an optical resonance.
module laser_auto_search (
    input wire clk, input wire rst, input wire enable,
    input wire signed [15:0] applied_code,
    input wire signed [13:0] adc_sample, input wire adc_valid,
    input wire signed [15:0] coarse_lo, coarse_hi,
    input wire [15:0] coarse_step, fine_half, fine_step,
    input wire [31:0] dwell_clocks,
    input wire [15:0] min_depth, min_slope, lock_error_limit,
    output reg signed [15:0] requested_code,
    output reg pid_enable, output reg pid_clear,
    output reg signed [15:0] lock_code,
    output reg signed [15:0] lock_setpoint,
    output reg [4:0] state,
    output reg [7:0] fault,
    output reg signed [15:0] coarse_min_code,
    output reg signed [15:0] coarse_min_adc,
    output reg [15:0] coarse_depth,
    output reg [15:0] best_slope,
    output reg [31:0] points_tested
);
    localparam IDLE=0, C_INIT=1, C_MOVE=2, C_WAIT=3, C_EVAL=4,
               C_RETURN=5, F_INIT=6, F_MOVE=7, F_WAIT=8, F_EVAL=9,
               L_POSITION=10, L_DWELL=11, LOCKED=12, FAILED=13;
    reg signed [15:0] min_adc,max_adc, fine_lo,fine_hi, last_fine_adc;
    reg signed [15:0] last_fine_code;
    reg [31:0] timer,watchdog;
    reg signed [31:0] accumulator;
    reg [2:0] samples;
    reg have_prev,have_coarse,have_fine;
    reg [7:0] bad_error_count;
    wire signed [15:0] adc_average=accumulator >>> 2;
    wire signed [16:0] depth_now=$signed({max_adc[15],max_adc})-$signed({min_adc[15],min_adc});
    wire signed [16:0] slope_now=$signed({last_fine_adc[15],last_fine_adc})-$signed({adc_average[15],adc_average});
    wire signed [16:0] lock_error=$signed({{3{adc_sample[13]}},adc_sample})-$signed({lock_setpoint[15],lock_setpoint});
    wire signed [16:0] error_abs=(lock_error<0) ? -lock_error:lock_error;
    wire signed [31:0] coarse_stride=(coarse_step==0) ? 32'sd1 : $signed({16'd0,coarse_step});
    wire signed [31:0] fine_stride=(fine_step==0) ? 32'sd1 : $signed({16'd0,fine_step});
    wire signed [31:0] next_coarse=$signed(requested_code)+coarse_stride;
    wire signed [31:0] next_fine=$signed(requested_code)+fine_stride;
    wire [31:0] dwell_safe=(dwell_clocks<32'd1000) ? 32'd1000 : dwell_clocks;
    wire at_target=(applied_code==requested_code);
    // 25e6 cycles ~0.25 seconds at 100MHz, enough for a single scan point.
    // Ensure selected dwell is bounded below 10e6 in the wrapper.
    wire timed_out=(watchdog>=32'd25000000);
    always @(posedge clk) begin
        if(rst || !enable) begin
            requested_code<=0;pid_enable<=0;pid_clear<=0;
            lock_code<=0;lock_setpoint<=0;state<=IDLE;fault<=0;
            coarse_min_code<=0;coarse_min_adc<=0;coarse_depth<=0;
            best_slope<=0;points_tested<=0;
            min_adc<=16'sh7fff;max_adc<=-16'sh8000;
            fine_lo<=0;fine_hi<=0;last_fine_adc<=0;last_fine_code<=0;
            timer<=0;watchdog<=0;accumulator<=0;samples<=0;
            have_prev<=0;have_coarse<=0;have_fine<=0;bad_error_count<=0;
        end else begin
            pid_clear<=0;
            case(state)
                IDLE: state<=C_INIT;
                C_INIT: begin
                    pid_enable<=0;requested_code<=coarse_lo;
                    min_adc<=16'sh7fff;max_adc<=-16'sh8000;
                    coarse_min_code<=0;coarse_min_adc<=0;coarse_depth<=0;
                    best_slope<=0;fault<=0;points_tested<=0;
                    have_coarse<=0;bad_error_count<=0;
                    timer<=0;watchdog<=0;state<=C_MOVE;
                end
                C_MOVE: begin
                    timer<=0;accumulator<=0;samples<=0;
                    if(at_target) begin watchdog<=0; state<=C_WAIT; end
                    else if(timed_out)begin fault<=8'd1;state<=FAILED;end
                    else watchdog<=watchdog+1'b1;
                end
                C_WAIT: begin
                    if(!at_target)begin timer<=0;samples<=0;accumulator<=0;state<=C_MOVE;end
                    else begin
                        if(timer<dwell_safe) timer<=timer+1'b1;
                        // Take four distinct samples after the output settled.
                        if(timer>=dwell_safe && adc_valid && samples<4) begin
                            accumulator<=accumulator+$signed({{18{adc_sample[13]}},adc_sample});
                            samples<=samples+1'b1;
                        end
                        if(timer>=dwell_safe && samples==4) state<=C_EVAL;
                        else if(timed_out)begin fault<=8'd2;state<=FAILED;end
                        else watchdog<=watchdog+1'b1;
                    end
                end
                C_EVAL:begin
                    points_tested<=points_tested+1'b1;
                    if(!have_coarse || adc_average<min_adc) begin
                        min_adc<=adc_average;coarse_min_adc<=adc_average;
                        coarse_min_code<=requested_code;
                    end
                    if(!have_coarse || adc_average>max_adc)max_adc<=adc_average;
                    have_coarse<=1;
                    watchdog<=0;
                    if(next_coarse>=$signed(coarse_hi)) requested_code<=coarse_hi;
                    else requested_code<=next_coarse[15:0];
                    if(requested_code==coarse_hi) begin
                        requested_code<=coarse_lo;state<=C_RETURN;
                    end else state<=C_MOVE;
                end
                C_RETURN:begin
                    if(at_target) begin
                        if(depth_now<=0 || depth_now<$signed({1'b0,min_depth}) ||
                           coarse_min_code<=$signed(coarse_lo)+$signed({16'd0,coarse_step}) ||
                           coarse_min_code>=$signed(coarse_hi)-$signed({16'd0,coarse_step})) begin
                            fault<=8'd3;state<=FAILED;
                        end else begin
                            coarse_depth<=depth_now[15:0];state<=F_INIT;
                        end
                    end else if(timed_out)begin fault<=8'd4;state<=FAILED;end
                    else watchdog<=watchdog+1'b1;
                end
                F_INIT: begin
                    fine_lo<=($signed(coarse_min_code)-$signed({16'd0,fine_half})<$signed(coarse_lo)) ?
                               coarse_lo : $signed(coarse_min_code)-$signed({16'd0,fine_half});
                    fine_hi<=($signed(coarse_min_code)+$signed({16'd0,fine_half})>$signed(coarse_hi)) ?
                               coarse_hi : $signed(coarse_min_code)+$signed({16'd0,fine_half});
                    best_slope<=0;have_prev<=0;have_fine<=0;
                    requested_code<=($signed(coarse_min_code)-$signed({16'd0,fine_half})<$signed(coarse_lo)) ?
                               coarse_lo : $signed(coarse_min_code)-$signed({16'd0,fine_half});
                    watchdog<=0;state<=F_MOVE;
                end
                F_MOVE:begin
                    timer<=0;accumulator<=0;samples<=0;
                    if(at_target)begin watchdog<=0;state<=F_WAIT;end
                    else if(timed_out)begin fault<=8'd5;state<=FAILED;end
                    else watchdog<=watchdog+1'b1;
                end
                F_WAIT:begin
                    if(!at_target)begin timer<=0;samples<=0;accumulator<=0;state<=F_MOVE;end
                    else begin
                        if(timer<dwell_safe)timer<=timer+1'b1;
                        if(timer>=dwell_safe && adc_valid && samples<4)begin
                            accumulator<=accumulator+$signed({{18{adc_sample[13]}},adc_sample});
                            samples<=samples+1'b1;
                        end
                        if(timer>=dwell_safe && samples==4)state<=F_EVAL;
                        else if(timed_out)begin fault<=8'd6;state<=FAILED;end
                        else watchdog<=watchdog+1'b1;
                    end
                end
                F_EVAL:begin
                    points_tested<=points_tested+1'b1;
                    if(have_prev && slope_now>0 &&
                        (!have_fine || slope_now>$signed({1'b0,best_slope})))begin
                        best_slope<=slope_now[15:0];lock_code<=requested_code;
                        lock_setpoint<=adc_average;have_fine<=1;
                    end
                    last_fine_adc<=adc_average;last_fine_code<=requested_code;
                    have_prev<=1;watchdog<=0;
                    if(requested_code==fine_hi)begin
                        state<=L_POSITION;
                        // lock_code is nonblocking-updated above; LOCK POSITION
                        // uses the registered best from *previous* points.
                    end else begin
                        requested_code<=(next_fine>=$signed(fine_hi)) ? fine_hi : next_fine[15:0];
                        state<=F_MOVE;
                    end
                end
                L_POSITION:begin
                    if(!have_fine || best_slope<min_slope)begin fault<=8'd7;state<=FAILED;end
                    else begin requested_code<=lock_code;watchdog<=0;timer<=0;state<=L_DWELL;end
                end
                L_DWELL:begin
                    if(at_target)begin
                        if(timer>=dwell_safe)begin
                            pid_clear<=1;pid_enable<=1;state<=LOCKED;
                            bad_error_count<=0;timer<=0;
                        end else timer<=timer+1'b1;
                    end else begin
                        timer<=0;
                        if(timed_out)begin fault<=8'd8;state<=FAILED;end
                        else watchdog<=watchdog+1'b1;
                    end
                end
                LOCKED:begin
                    // Loss of lock: require 32 consecutive fresh large errors.
                    // Stop feedback and gently request 0. Avoid continuous
                    // uncontrolled retry with unknown actuator polarity.
                    if(adc_valid)begin
                        if(error_abs>$signed({1'b0,lock_error_limit}))begin
                            if(bad_error_count==31)begin
                                fault<=8'd9;pid_enable<=0;requested_code<=0;state<=FAILED;
                            end else bad_error_count<=bad_error_count+1'b1;
                        end else bad_error_count<=0;
                    end
                end
                FAILED:begin
                    pid_enable<=0;requested_code<=0;
                    // Sticky fault: disable/re-enable auto mode to retry.
                end
                default:begin fault<=8'd10;state<=FAILED;pid_enable<=0;end
            endcase
        end
    end
endmodule
