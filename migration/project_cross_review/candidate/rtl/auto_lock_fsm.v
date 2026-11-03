`timescale 1ns/1ps
// Autonomous dip search -> left half-height slope -> PI2D -> re-acquisition.
// Work clock is 100 MHz. All output values are DAC CODES, NOT VOLTS.
// Real laser tuning range, bandwidth and safe electrical level must be verified.
module auto_lock_fsm #(
    parameter integer SPAN = 1024,             // signed DAC codes about zero
    parameter integer STEP = 2,                // fine-scan resolution
    parameter integer SETTLE_CLOCKS = 200000,  // 2 ms per point at 100 MHz
    parameter integer AVG_LOG2 = 2,            // four ADC samples per point
    parameter integer MIN_CONTRAST = 24,       // ADC codes
    parameter integer LOCK_TOL = 32,          // absolute PD error codes
    parameter integer LOSS_TOL = 192,
    parameter integer STABLE_SAMPLES = 64,
    parameter integer LOST_SAMPLES = 256,
    parameter integer NO_SAMPLE_CLOCKS = 20000000,
    parameter integer LOCK_TIMEOUT_CLOCKS = 300000000,
    parameter integer RETRY_CLOCKS = 100000000
)(
    input wire clk, input wire rst, input wire arm, input wire dac_at_goal,
    input wire adc_valid, input wire signed [13:0] adc_sample,
    input wire servo_valid, input wire signed [15:0] servo_delta,
    input wire signed [15:0] servo_error,
    input wire servo_clipped,
    output reg signed [15:0] dac_code, output reg dac_valid,
    output wire adc_scan_enable, output wire servo_enable,
    output reg signed [15:0] servo_setpoint, output reg reverse_error,
    output reg servo_clear,
    output reg [3:0] state,
    output reg locked, output reg ever_locked,
    output reg [3:0] last_reason,
    output reg [7:0] attempts,
    output reg signed [15:0] scan_min, scan_max,
    output reg signed [15:0] min_code, selected_code,
    output reg [31:0] reacquire_count,
    output reg [31:0] samples_seen
);
    localparam [3:0] IDLE=0, SWEEP_WAIT=1, SWEEP_AVG=2,
        FIND_WAIT=3, FIND_AVG=4, ALIGN_WAIT=5, LOCKING=6,
        RETRY_WAIT=7;
    reg signed [15:0] scan_code, best_code, best_level;
    reg signed [15:0] half_level;
    reg [16:0] best_diff;
    reg signed [31:0] sum_samples;
    reg [AVG_LOG2:0] sample_number;
    reg [31:0] timer, adc_watchdog, stable_count, bad_count;
    reg [31:0] lock_timer;
    reg [31:0] backoff_timer;
    wire signed [31:0] sample_expanded = {{18{adc_sample[13]}},adc_sample};
    wire signed [31:0] average = (sum_samples + sample_expanded) >>> AVG_LOG2;
    wire signed [16:0] contrast = $signed({scan_max[15],scan_max}) - $signed({scan_min[15],scan_min});
    // Include the current final point before qualifying the complete sweep.
    wire signed [15:0] sweep_min_next = average < $signed(scan_min) ? average[15:0] : scan_min;
    wire signed [15:0] sweep_max_next = average > $signed(scan_max) ? average[15:0] : scan_max;
    wire signed [15:0] sweep_min_code_next = average < $signed(scan_min) ? scan_code : min_code;
    wire signed [16:0] sweep_contrast_next =
        $signed({sweep_max_next[15],sweep_max_next}) - $signed({sweep_min_next[15],sweep_min_next});
    wire signed [16:0] sweep_half_sum_next =
        $signed({sweep_min_next[15],sweep_min_next}) + $signed({sweep_max_next[15],sweep_max_next});
    wire signed [16:0] difference = average[16:0] - $signed({half_level[15],half_level});
    wire [16:0] abs_difference = difference[16] ? -difference : difference;
    wire signed [16:0] err17 = $signed({servo_error[15],servo_error});
    wire [16:0] abs_error = err17[16] ? -err17 : err17;
    wire signed [17:0] summed_code = $signed({{2{selected_code[15]}},selected_code}) +
                                      $signed({{2{servo_delta[15]}},servo_delta});
    wire signed [15:0] bounded_servo_code =
        summed_code > SPAN ? SPAN :
        summed_code < -SPAN ? -SPAN : summed_code[15:0];
    assign adc_scan_enable = arm && (state!=IDLE);
    assign servo_enable = arm && (state==LOCKING);

    always @(posedge clk) begin
        if (rst || !arm) begin
            state<=IDLE;dac_code<=0;dac_valid<=0;
            servo_setpoint<=0;reverse_error<=0;servo_clear<=1;
            locked<=0;ever_locked<=0;last_reason<=0;attempts<=0;
            scan_min<=32767;scan_max<=-32768;min_code<=0;selected_code<=0;
            reacquire_count<=0;samples_seen<=0;
            scan_code<=0;best_code<=0;best_level<=0;half_level<=0;
            best_diff<=17'h1ffff;sum_samples<=0;sample_number<=0;
            timer<=0;adc_watchdog<=0;stable_count<=0;bad_count<=0;
            lock_timer<=0;backoff_timer<=0;
        end else begin
            dac_valid<=0;
            servo_clear<=0;
            if (adc_valid) begin
                samples_seen<=samples_seen+1'b1;
                adc_watchdog<=0;
            end else if(adc_watchdog<NO_SAMPLE_CLOCKS) adc_watchdog<=adc_watchdog+1'b1;
            if (adc_watchdog>=NO_SAMPLE_CLOCKS && state!=RETRY_WAIT && state!=IDLE) begin
                last_reason<=4'd2; // No ADC data
                reacquire_count<=reacquire_count+1'b1;
                locked<=0;servo_clear<=1;
                dac_code<=0;dac_valid<=1;state<=RETRY_WAIT;backoff_timer<=0;
            end else case (state)
                IDLE: begin
                    // Scan starts only after external physical-output ARM.
                    attempts<=attempts+1'b1;
                    scan_min<=32767;scan_max<=-32768;min_code<=0;
                    scan_code<=-SPAN;dac_code<=-SPAN;dac_valid<=1;
                    sum_samples<=0;sample_number<=0;timer<=0;
                    locked<=0;servo_clear<=1;state<=SWEEP_WAIT;
                end
                SWEEP_WAIT: begin
                    if(!dac_at_goal) timer<=0;
                    else if(timer>=SETTLE_CLOCKS) begin
                        timer<=0;sum_samples<=0;sample_number<=0;state<=SWEEP_AVG;
                    end else timer<=timer+1'b1;
                end
                SWEEP_AVG: if(adc_valid) begin
                    if(sample_number==(1<<AVG_LOG2)-1) begin
                        if(average < $signed(scan_min)) begin
                            scan_min<=average[15:0];min_code<=scan_code;
                        end
                        if(average > $signed(scan_max)) scan_max<=average[15:0];
                        if(scan_code >= SPAN) begin
                            // Require a dip rather than mistaking noise for a resonance.
                            if(sweep_contrast_next<MIN_CONTRAST || sweep_min_code_next<=-SPAN || sweep_min_code_next>=SPAN) begin
                                last_reason<=4'd1;reacquire_count<=reacquire_count+1'b1;
                                dac_code<=0;dac_valid<=1;state<=RETRY_WAIT;backoff_timer<=0;
                            end else begin
                                half_level<=sweep_half_sum_next >>> 1;
                                best_diff<=17'h1ffff;
                                best_code<=-SPAN;best_level<=0;
                                scan_code<=-SPAN;dac_code<=-SPAN;dac_valid<=1;
                                timer<=0;state<=FIND_WAIT;
                            end
                        end else begin
                            scan_code<=scan_code+STEP;dac_code<=scan_code+STEP;
                            dac_valid<=1;timer<=0;state<=SWEEP_WAIT;
                        end
                    end else begin
                        sum_samples<=sum_samples+sample_expanded;
                        sample_number<=sample_number+1'b1;
                    end
                end
                FIND_WAIT: begin
                    if(!dac_at_goal) timer<=0;
                    else if(timer>=SETTLE_CLOCKS) begin
                        timer<=0;sum_samples<=0;sample_number<=0;state<=FIND_AVG;
                    end else timer<=timer+1'b1;
                end
                FIND_AVG: if(adc_valid) begin
                    if(sample_number==(1<<AVG_LOG2)-1) begin
                        if(abs_difference<best_diff) begin
                            best_diff<=abs_difference;
                            best_code<=scan_code;best_level<=average[15:0];
                        end
                        if(scan_code>=min_code) begin
                            if(best_diff > (contrast>>>2)) begin
                                last_reason<=4'd3;reacquire_count<=reacquire_count+1'b1;
                                dac_code<=0;dac_valid<=1;state<=RETRY_WAIT;backoff_timer<=0;
                            end else begin
                                selected_code<=best_code;servo_setpoint<=best_level;
                                // Scanning upward into a transmission dip has negative optical slope;
                                // original normalizer applies -error, so invert it once here.
                                reverse_error<=1;
                                dac_code<=best_code;dac_valid<=1;
                                timer<=0;state<=ALIGN_WAIT;
                            end
                        end else begin
                            scan_code<=scan_code+STEP;dac_code<=scan_code+STEP;
                            dac_valid<=1;timer<=0;state<=FIND_WAIT;
                        end
                    end else begin
                        sum_samples<=sum_samples+sample_expanded;
                        sample_number<=sample_number+1'b1;
                    end
                end
                ALIGN_WAIT: begin
                    if(!dac_at_goal) timer<=0;
                    else if(timer>=SETTLE_CLOCKS) begin
                        servo_clear<=1;stable_count<=0;bad_count<=0;
                        lock_timer<=0;locked<=0;state<=LOCKING;
                    end else timer<=timer+1'b1;
                end
                LOCKING: begin
                    if(lock_timer<LOCK_TIMEOUT_CLOCKS) lock_timer<=lock_timer+1'b1;
                    if(servo_valid) begin
                        dac_code<=bounded_servo_code;dac_valid<=1;
                        if(servo_clipped || abs_error>LOSS_TOL ||
                           (locked && abs_error>LOCK_TOL) ||
                           summed_code>SPAN || summed_code< -SPAN) begin
                            stable_count<=0;
                            if(bad_count<LOST_SAMPLES) bad_count<=bad_count+1'b1;
                        end else begin
                            bad_count<=0;
                            if(abs_error<=LOCK_TOL) begin
                                if(stable_count<STABLE_SAMPLES) stable_count<=stable_count+1'b1;
                                if(stable_count>=STABLE_SAMPLES-1) begin
                                    locked<=1;ever_locked<=1;
                                end
                            end else stable_count<=0;
                        end
                    end
                    if(bad_count>=LOST_SAMPLES || (!locked && lock_timer>=LOCK_TIMEOUT_CLOCKS)) begin
                        last_reason<= bad_count>=LOST_SAMPLES ? 4'd4 : 4'd5;
                        locked<=0;servo_clear<=1;
                        reacquire_count<=reacquire_count+1'b1;
                        dac_code<=0;dac_valid<=1;state<=RETRY_WAIT;backoff_timer<=0;
                    end
                end
                RETRY_WAIT: begin
                    if(backoff_timer>=RETRY_CLOCKS) begin
                        attempts<=attempts+1'b1;
                        scan_min<=32767;scan_max<=-32768;min_code<=0;
                        scan_code<=-SPAN;dac_code<=-SPAN;dac_valid<=1;
                        sum_samples<=0;sample_number<=0;timer<=0;
                        state<=SWEEP_WAIT;
                    end else backoff_timer<=backoff_timer+1'b1;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
