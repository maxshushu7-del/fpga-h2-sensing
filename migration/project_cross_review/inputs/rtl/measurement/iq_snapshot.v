`timescale 1ns/1ps
// Frozen dual-clock frame and bundled metadata. No overlapping capture/read.
// The fine frame is collected AFTER DDC filtering/settling, over real new time.
module iq_snapshot #(
    parameter integer FFT_LOG2=12,
    parameter integer DECIMATION=250,
    parameter integer ENABLE_DDC=1
) (
    input wire adc_clk, adc_rst_n,
    input wire signed [13:0] adc_sample,
    input wire proc_clk, proc_rst_n,
    input wire start, abort_capture, fine_mode, low_mode,
    input wire [31:0] tuning_word,
    output reg busy, done,
    input wire [FFT_LOG2-1:0] read_address,
    output reg signed [15:0] read_i, read_q,
    output reg signed [15:0] mean_i, mean_q,
    output reg [31:0] clipped_samples,
    output reg capture_bad,
    output wire capture_active,
    output wire [FFT_LOG2-1:0] capture_address
);
    localparam integer N=1<<FFT_LOG2;
    localparam integer SUM_WIDTH=17+FFT_LOG2;
    (* ram_style="block" *) reg signed [15:0] ram_i[0:N-1];
    (* ram_style="block" *) reg signed [15:0] ram_q[0:N-1];
    reg request_toggle, abort_toggle, fine_latched;
    reg [31:0] tune_latched;
    (* ASYNC_REG="TRUE" *) reg [1:0] request_sync, abort_sync, completed_sync;
    reg completed_toggle, abort_seen, capturing, fine_adc, ddc_restart;
    reg [31:0] tune_adc, adc_clip_count;
    reg [FFT_LOG2-1:0] wr_address;
    reg signed [SUM_WIDTH-1:0] sum_i, sum_q;
    reg bad_adc;
    reg [31:0] capture_cycles;
    wire signed [15:0] ddc_i, ddc_q;
    wire ddc_valid, ddc_settled, ddc_overflow;
    generate if (ENABLE_DDC) begin: g_ddc
        ddc_decimator #(.DECIMATION(DECIMATION)) u_ddc (
            .clk(adc_clk), .rst_n(adc_rst_n), .restart(ddc_restart),
            .tuning_word(tune_adc), .sample(adc_sample),
            .sample_i(ddc_i), .sample_q(ddc_q), .sample_valid(ddc_valid),
            .settled(ddc_settled), .overflow(ddc_overflow));
    end else begin: g_no_ddc
        assign ddc_i=0; assign ddc_q=0; assign ddc_valid=0;
        assign ddc_settled=0; assign ddc_overflow=0;
    end endgenerate
    wire raw_clipped=(adc_sample==14'sh1fff || adc_sample==14'sh2000);
    wire take_sample=capturing && !ddc_restart && (!fine_adc || (ddc_valid && ddc_settled));
    wire signed [15:0] source_i=fine_adc ? ddc_i : {{2{adc_sample[13]}},adc_sample};
    wire signed [15:0] source_q=fine_adc ? ddc_q : 16'sd0;
    assign capture_active=capturing;
    assign capture_address=wr_address;
    // This bound also terminates a stalled decimator while ADC clock is running.
    localparam integer MAX_CAPTURE_CYCLES=(N+32)*DECIMATION+4096;
    always @(posedge proc_clk or negedge proc_rst_n) begin
        if (!proc_rst_n) begin
            request_toggle<=0; abort_toggle<=0; completed_sync<=0;
            fine_latched<=0; tune_latched<=0; busy<=0; done<=0;
            mean_i<=0; mean_q<=0; clipped_samples<=0; capture_bad<=0;
        end else begin
            completed_sync<={completed_sync[0],completed_toggle};
            done<=0;
            if (abort_capture && busy) abort_toggle<=~abort_toggle;
            if (start && !busy) begin
                // Both zoom and direct low-band captures use the settled CIC.
                // low_mode has tuning_word=0 and therefore captures real LPF data.
                fine_latched<=fine_mode || low_mode; tune_latched<=tuning_word;
                request_toggle<=~request_toggle; busy<=1;
            end else if (busy && completed_sync[1]==request_toggle) begin
                busy<=0; done<=1;
                // Values were frozen before the completion toggle crossed CDC.
                mean_i<=sum_i>>>FFT_LOG2; mean_q<=sum_q>>>FFT_LOG2;
                clipped_samples<=adc_clip_count; capture_bad<=bad_adc;
            end
        end
    end
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            request_sync<=0; abort_sync<=0; completed_toggle<=0; abort_seen<=0;
            capturing<=0; fine_adc<=0; tune_adc<=0; ddc_restart<=0;
            wr_address<=0; sum_i<=0; sum_q<=0; adc_clip_count<=0;
            bad_adc<=0; capture_cycles<=0;
        end else begin
            request_sync<={request_sync[0],request_toggle};
            abort_sync<={abort_sync[0],abort_toggle};
            ddc_restart<=0;
            if (abort_sync[1]!=abort_seen) begin
                abort_seen<=abort_sync[1]; capturing<=0; bad_adc<=1;
                completed_toggle<=request_sync[1];
            end else if (!capturing && request_sync[1]!=completed_toggle) begin
                // Bundled mode/tune stay stable through this entire capture.
                fine_adc<=fine_latched; tune_adc<=tune_latched;
                ddc_restart<=1; capturing<=1; wr_address<=0;
                sum_i<=0; sum_q<=0; adc_clip_count<=0; bad_adc<=0;
                capture_cycles<=0;
            end else if (capturing) begin
                capture_cycles<=capture_cycles+1;
                if (raw_clipped) adc_clip_count<=adc_clip_count+1;
                if (fine_adc && ddc_overflow) bad_adc<=1;
                if (capture_cycles>=MAX_CAPTURE_CYCLES) begin
                    capturing<=0; bad_adc<=1; completed_toggle<=request_sync[1];
                end else if (take_sample) begin
                    sum_i<=sum_i+source_i; sum_q<=sum_q+source_q;
                    if (wr_address==N-1) begin
                        capturing<=0; completed_toggle<=request_sync[1];
                    end else wr_address<=wr_address+1;
                end
            end
        end
    end
    always @(posedge adc_clk) if (take_sample) begin
        ram_i[wr_address]<=source_i; ram_q[wr_address]<=source_q;
    end
    always @(posedge proc_clk) begin
        read_i<=ram_i[read_address]; read_q<=ram_q[read_address];
    end
endmodule
