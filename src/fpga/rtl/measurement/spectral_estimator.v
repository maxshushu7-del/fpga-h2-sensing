`timescale 1ns / 1ps

// One complete natural-order spectrum at a time. Do not supply the next frame
// until result_strobe: post-processing reads the same power RAM. Every frame
// produces a strobe, including rejected frames; measurement_valid is separate.
// The thresholds are configurable bench heuristics, NOT a calibrated detector.
// In complex mode all bins are eligible, including zero and negative/wrapped
// frequency. MIN_BIN/MAX_BIN only constrain the positive-half real-mode search.
module spectral_estimator #(
    parameter integer FFT_LOG2 = 12,
    parameter integer OUT_WIDTH = 16 + FFT_LOG2 + 1,
    parameter integer SAMPLE_RATE_HZ = 250000000,
    parameter integer COMPLEX_INPUT = 0,
    parameter integer MIN_BIN = 1,
    parameter integer MAX_BIN = (1 << (FFT_LOG2-1)) - 1,
    parameter integer WINDOW_ENABLE = 1,
    parameter [63:0] MIN_PEAK_POWER = (64'd1 << (2*FFT_LOG2)),
    parameter integer PEAK_NOISE_RATIO = 32
) (
    input wire clk, input wire rst_n,
    input wire signed [OUT_WIDTH-1:0] fft_re, fft_im,
    input wire [FFT_LOG2-1:0] fft_bin,
    input wire fft_valid, fft_last,
    input wire frame_bad,
    output reg result_strobe,
    output reg measurement_valid,
    output reg [FFT_LOG2-1:0] peak_bin,
    output reg signed [17:0] bin_offset_q16,
    output reg signed [31:0] frequency_offset_hz,
    output reg [2*OUT_WIDTH:0] peak_power,
    output reg [2*OUT_WIDTH:0] noise_power,
    output reg interp_valid
);
    localparam integer N = 1 << FFT_LOG2;
    localparam integer PW = 2*OUT_WIDTH + 1;
    localparam integer SUM_W = PW + FFT_LOG2;
    localparam integer ROOT_W = (PW + 1) / 2;
    localparam integer SQ_W = 2*ROOT_W;
    localparam integer DIV_W = SUM_W;
    localparam [4:0] COLLECT=0, SCAN_WAIT=1, SCAN_USE=2,
        DIV_NOISE=3, NEIGHBOR_REQ=4, NEIGHBOR_WAIT=5, NEIGHBOR_USE=6,
        SQRT_RUN=7, INTERP_PREP=8, DIV_INTERP=9, FREQ_PREP=10,
        FREQ_ROUND=11, EMIT=12;

    reg [4:0] state;
    (* ram_style = "block" *) reg [PW-1:0] power_ram [0:N-1];
    reg [FFT_LOG2-1:0] ram_read_address;
    reg [PW-1:0] ram_q;
    always @(posedge clk) ram_q <= power_ram[ram_read_address];

    // Signed products are pipelined before the power sum and frame collector.
    reg signed [OUT_WIDTH-1:0] re_q, im_q;
    reg [2*OUT_WIDTH-1:0] re_sq, im_sq;
    reg [PW-1:0] power_q;
    reg [FFT_LOG2-1:0] bin_1, bin_2, bin_3;
    reg valid_1, valid_2, valid_3, last_1, last_2, last_3;
    reg bad_1, bad_2, bad_3;

    // No asynchronous-reset sensitivity on the memory port: reset the control
    // state, never the array. A valid full frame overwrites every RAM entry.
    always @(posedge clk)
        if (rst_n && state == COLLECT && valid_3)
            power_ram[bin_3] <= power_q;

    reg frame_error;
    reg [FFT_LOG2-1:0] expected_bin;
    reg [PW-1:0] best_power;
    reg [FFT_LOG2-1:0] best_bin;
    reg [FFT_LOG2-1:0] scan_index;
    reg [SUM_W-1:0] noise_sum;
    reg [FFT_LOG2:0] noise_count;
    reg [PW-1:0] noise_average;

    // Restoring serial divider, reused for the floor average and Q16 offset.
    reg [DIV_W-1:0] div_source, div_quotient;
    reg [DIV_W:0] div_remainder, div_denominator;
    integer div_steps;
    wire [DIV_W:0] div_trial = {div_remainder[DIV_W-1:0], div_source[DIV_W-1]};
    wire div_ge = div_trial >= div_denominator;
    wire [DIV_W-1:0] div_next_quotient = {div_quotient[DIV_W-2:0], div_ge};

    // Restoring radix-four square root: one result bit per clock.
    reg [SQ_W-1:0] sqrt_source;
    reg [ROOT_W+1:0] sqrt_remainder;
    reg [ROOT_W-1:0] sqrt_root;
    integer sqrt_steps;
    wire [ROOT_W+1:0] sqrt_shift =
        {sqrt_remainder[ROOT_W-1:0], sqrt_source[SQ_W-1:SQ_W-2]};
    wire [ROOT_W+1:0] sqrt_trial = {sqrt_root, 2'b01};
    wire sqrt_ge = sqrt_shift >= sqrt_trial;
    wire [ROOT_W-1:0] sqrt_next_root = {sqrt_root[ROOT_W-2:0], sqrt_ge};
    reg [1:0] neighbor_number;
    reg [ROOT_W-1:0] amplitude_left, amplitude_center, amplitude_right;
    reg [PW-1:0] power_left, power_center, power_right;
    reg signed [17:0] delta_q16;
    reg delta_valid, delta_negative;
    wire [ROOT_W-1:0] amplitude_difference =
        amplitude_right >= amplitude_left ? amplitude_right-amplitude_left :
                                            amplitude_left-amplitude_right;
    wire [ROOT_W+1:0] amplitude_denominator =
        {2'b00, amplitude_left} + {1'b0, amplitude_center, 1'b0} +
        {2'b00, amplitude_right};

    wire [FFT_LOG2-1:0] distance_from_peak = scan_index - best_bin;
    wire near_peak = (distance_from_peak <= 2) || (distance_from_peak >= N-2);
    wire scan_eligible = COMPLEX_INPUT ||
        ((scan_index >= MIN_BIN) && (scan_index <= MAX_BIN));
    wire input_eligible = COMPLEX_INPUT ||
        ((bin_3 >= MIN_BIN) && (bin_3 <= MAX_BIN));
    wire real_neighbors_allowed = (best_bin > 0) && (best_bin < (N/2)-1);
    wire [PW+31:0] noise_threshold = noise_average * PEAK_NOISE_RATIO;
    reg signed [FFT_LOG2+16:0] signed_bin_q16;
    reg signed [63:0] frequency_product;
    localparam [63:0] ROUND_HZ = 64'd1 << (FFT_LOG2+15);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            re_q<=0; im_q<=0; re_sq<=0; im_sq<=0; power_q<=0;
            bin_1<=0; bin_2<=0; bin_3<=0;
            valid_1<=0; valid_2<=0; valid_3<=0;
            last_1<=0; last_2<=0; last_3<=0;
            bad_1<=0; bad_2<=0; bad_3<=0;
            state<=COLLECT; frame_error<=0; expected_bin<=0;
            best_power<=0; best_bin<=0; scan_index<=0; ram_read_address<=0;
            noise_sum<=0; noise_count<=0; noise_average<=0;
            div_source<=0; div_quotient<=0; div_remainder<=0;
            div_denominator<=1; div_steps<=0;
            sqrt_source<=0; sqrt_root<=0; sqrt_remainder<=0; sqrt_steps<=0;
            neighbor_number<=0; amplitude_left<=0; amplitude_center<=0;
            amplitude_right<=0; power_left<=0; power_center<=0; power_right<=0;
            delta_q16<=0; delta_valid<=0; delta_negative<=0;
            signed_bin_q16<=0; frequency_product<=0;
            result_strobe<=0; measurement_valid<=0; peak_bin<=0;
            bin_offset_q16<=0; frequency_offset_hz<=0;
            peak_power<=0; noise_power<=0; interp_valid<=0;
        end else begin
            result_strobe <= 1'b0;
            valid_1<=fft_valid; valid_2<=valid_1; valid_3<=valid_2;
            last_1<=fft_last; last_2<=last_1; last_3<=last_2;
            bad_1<=frame_bad; bad_2<=bad_1; bad_3<=bad_2;
            if (fft_valid) begin re_q<=fft_re; im_q<=fft_im; bin_1<=fft_bin; end
            if (valid_1) begin
                re_sq<=re_q*re_q; im_sq<=im_q*im_q; bin_2<=bin_1;
            end
            if (valid_2) begin
                power_q<={1'b0,re_sq}+{1'b0,im_sq}; bin_3<=bin_2;
            end

            // Receiving a new spectrum during post-processing is a contract
            // violation, never silently mark the current result trustworthy.
            if (valid_3 && state != COLLECT) frame_error <= 1'b1;

            case (state)
                COLLECT: if (valid_3) begin
                    if (bad_3 || bin_3 != expected_bin ||
                        last_3 != (&bin_3)) frame_error <= 1'b1;
                    expected_bin <= bin_3 + 1'b1;
                    if (input_eligible && power_q > best_power) begin
                        best_power <= power_q; best_bin <= bin_3;
                    end
                    if (last_3 || (&bin_3)) begin
                        // Finish malformed TLAST frames too, returning invalid.
                        scan_index<=0; ram_read_address<=0;
                        noise_sum<=0; noise_count<=0; noise_average<=0;
                        delta_q16<=0; delta_valid<=0;
                        state<=SCAN_WAIT;
                    end
                end
                SCAN_WAIT: state <= SCAN_USE;
                SCAN_USE: begin
                    if (scan_eligible && !near_peak) begin
                        noise_sum <= noise_sum + ram_q;
                        noise_count <= noise_count + 1'b1;
                    end
                    if (&scan_index) begin
                        // A final-bin contribution is included explicitly:
                        // nonblocking accumulator writes take effect next cycle.
                        div_source <= noise_sum +
                            ((scan_eligible && !near_peak) ? ram_q : {PW{1'b0}});
                        div_denominator <= noise_count +
                            ((scan_eligible && !near_peak) ? 1'b1 : 1'b0);
                        div_quotient<=0; div_remainder<=0; div_steps<=DIV_W;
                        state<=DIV_NOISE;
                    end else begin
                        scan_index<=scan_index+1'b1;
                        ram_read_address<=scan_index+1'b1;
                        state<=SCAN_WAIT;
                    end
                end
                DIV_NOISE: begin
                    if (div_denominator == 0) begin
                        noise_average<=0; frame_error<=1'b1;
                        neighbor_number<=0; state<=NEIGHBOR_REQ;
                    end else begin
                        div_source<=div_source<<1;
                        div_remainder<=div_ge ? div_trial-div_denominator : div_trial;
                        div_quotient<=div_next_quotient;
                        div_steps<=div_steps-1;
                        if (div_steps == 1) begin
                            noise_average<=div_next_quotient[PW-1:0];
                            neighbor_number<=0; state<=NEIGHBOR_REQ;
                        end
                    end
                end
                NEIGHBOR_REQ: begin
                    case (neighbor_number)
                        0: ram_read_address<=best_bin-1'b1;
                        1: ram_read_address<=best_bin;
                        default: ram_read_address<=best_bin+1'b1;
                    endcase
                    state<=NEIGHBOR_WAIT;
                end
                NEIGHBOR_WAIT: state<=NEIGHBOR_USE;
                NEIGHBOR_USE: begin
                    case (neighbor_number)
                        0: power_left<=ram_q;
                        1: power_center<=ram_q;
                        default: power_right<=ram_q;
                    endcase
                    sqrt_source<={{(SQ_W-PW){1'b0}},ram_q};
                    sqrt_root<=0; sqrt_remainder<=0; sqrt_steps<=ROOT_W;
                    state<=SQRT_RUN;
                end
                SQRT_RUN: begin
                    sqrt_source<=sqrt_source<<2;
                    sqrt_remainder<=sqrt_ge ? sqrt_shift-sqrt_trial : sqrt_shift;
                    sqrt_root<=sqrt_next_root;
                    sqrt_steps<=sqrt_steps-1;
                    if (sqrt_steps == 1) begin
                        case (neighbor_number)
                            0: amplitude_left<=sqrt_next_root;
                            1: amplitude_center<=sqrt_next_root;
                            default: amplitude_right<=sqrt_next_root;
                        endcase
                        if (neighbor_number == 2) state<=INTERP_PREP;
                        else begin neighbor_number<=neighbor_number+1'b1; state<=NEIGHBOR_REQ; end
                    end
                end
                INTERP_PREP: begin
                    // Hann amplitude interpolation, delta=2*(R-L)/(L+2C+R).
                    // Disable for the rectangular baseline and unsuitable or
                    // boundary neighbors; the integer estimate remains usable.
                    if (WINDOW_ENABLE && (COMPLEX_INPUT || real_neighbors_allowed) &&
                        power_center > power_left && power_center > power_right &&
                        amplitude_denominator != 0) begin
                        div_source<={{(DIV_W-ROOT_W-17){1'b0}},amplitude_difference,17'b0};
                        div_denominator<=amplitude_denominator;
                        div_remainder<=0; div_quotient<=0; div_steps<=DIV_W;
                        delta_negative<=amplitude_left>amplitude_right;
                        state<=DIV_INTERP;
                    end else state<=FREQ_PREP;
                end
                DIV_INTERP: begin
                    div_source<=div_source<<1;
                    div_remainder<=div_ge ? div_trial-div_denominator : div_trial;
                    div_quotient<=div_next_quotient; div_steps<=div_steps-1;
                    if (div_steps == 1) begin
                        if (div_next_quotient <= 32768) begin
                            delta_q16<=delta_negative ? -$signed({1'b0,div_next_quotient[16:0]}) :
                                                       $signed({1'b0,div_next_quotient[16:0]});
                            delta_valid<=1'b1;
                        end
                        state<=FREQ_PREP;
                    end
                end
                FREQ_PREP: begin
                    if (COMPLEX_INPUT && best_bin[FFT_LOG2-1])
                        signed_bin_q16 <= $signed({1'b1,best_bin,16'b0}) + delta_q16;
                    else signed_bin_q16 <= $signed({1'b0,best_bin,16'b0}) + delta_q16;
                    state<=FREQ_ROUND;
                end
                FREQ_ROUND: begin
                    frequency_product <= signed_bin_q16 * $signed({1'b0,SAMPLE_RATE_HZ[31:0]});
                    state<=EMIT;
                end
                EMIT: begin
                    result_strobe<=1'b1;
                    measurement_valid<=!frame_error && !valid_3 && (best_power >= MIN_PEAK_POWER) &&
                        ({32'd0,best_power} >= noise_threshold);
                    peak_bin<=best_bin; peak_power<=best_power; noise_power<=noise_average;
                    bin_offset_q16<=delta_q16; interp_valid<=delta_valid && !frame_error && !valid_3;
                    if (frequency_product < 0)
                        frequency_offset_hz <= -(((-frequency_product)+ROUND_HZ) >> (FFT_LOG2+16));
                    else frequency_offset_hz <= (frequency_product+ROUND_HZ) >> (FFT_LOG2+16);
                    expected_bin<=0; best_power<=0; best_bin<=0; frame_error<=0;
                    state<=COLLECT;
                end
                default: begin state<=COLLECT; frame_error<=1'b1; end
            endcase
        end
    end
endmodule
