`timescale 1ns / 1ps

// The generated fft_core must use FFT_LOG2 points, 16-bit complex input,
// unscaled arithmetic, natural output order, XK_INDEX in TUSER and non-realtime
// AXI handshaking. The two output components are individually byte padded.
module fft_stream_improved #(
    parameter integer FFT_LOG2 = 12, SIM_IDLE_FFT_PAUSE=0,
    parameter integer OUT_WIDTH = 16 + FFT_LOG2 + 1
) (
    input wire clk, input wire rst_n,
    input wire signed [15:0] sample_i, sample_q,
    input wire sample_valid, sample_last, idle_capture,
    output wire sample_ready,
    output reg configured,
    output wire signed [OUT_WIDTH-1:0] fft_re, fft_im,
    output wire [FFT_LOG2-1:0] fft_bin,
    output wire fft_valid, fft_last,
    output reg protocol_error
);
    localparam integer COMPONENT_PAD = ((OUT_WIDTH + 7) / 8) * 8;
    localparam integer USER_PAD = ((FFT_LOG2 + 7) / 8) * 8;
    wire config_ready, input_ready;
    wire config_valid = rst_n && !configured;
    wire [2*COMPONENT_PAD-1:0] output_data;
    wire [USER_PAD-1:0] output_user;
    wire missing_last, unexpected_last;
    reg [FFT_LOG2-1:0] input_index;
    wire fft_model_clk;
    generate if (SIM_IDLE_FFT_PAUSE) begin: g_simulation_only
        // TESTBENCH ONLY. This branch is not instantiated by the hardware top.
        // Sampling/FSM clocks stay untouched. Negative-edge selection avoids
        // generating spurious FFT clock edges; +FULL_FFT_CLOCK=1 bypasses it.
        integer full_clock=0;
        reg clock_enable=1;
        initial if($value$plusargs("FULL_FFT_CLOCK=%d",full_clock)) begin end
        always @(negedge clk) clock_enable<=full_clock || !rst_n || !configured || !idle_capture;
        assign fft_model_clk=clk && clock_enable;
    end else begin: g_hardware_clock
        assign fft_model_clk=clk;
    end endgenerate

    assign sample_ready = configured && input_ready;
    assign fft_re = output_data[OUT_WIDTH-1:0];
    assign fft_im = output_data[COMPONENT_PAD +: OUT_WIDTH];
    assign fft_bin = output_user[FFT_LOG2-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            configured <= 1'b0;
            protocol_error <= 1'b0;
            input_index <= 0;
        end else begin
            if (config_valid && config_ready) configured <= 1'b1;
            if (sample_valid && sample_ready) begin
                if (sample_last != (&input_index)) protocol_error <= 1'b1;
                input_index <= input_index + 1'b1;
            end
            if (missing_last || unexpected_last) protocol_error <= 1'b1;
        end
    end

    fft_core u_fft (
        .aclk(fft_model_clk), .aresetn(rst_n),
        .s_axis_config_tdata(8'h01), .s_axis_config_tvalid(config_valid),
        .s_axis_config_tready(config_ready),
        .s_axis_data_tdata({sample_q, sample_i}),
        .s_axis_data_tvalid(sample_valid && configured),
        .s_axis_data_tready(input_ready), .s_axis_data_tlast(sample_last),
        .m_axis_data_tdata(output_data), .m_axis_data_tuser(output_user),
        .m_axis_data_tvalid(fft_valid), .m_axis_data_tlast(fft_last),
        .m_axis_data_tready(1'b1),
        .event_frame_started(), .event_tlast_missing(missing_last),
        .event_tlast_unexpected(unexpected_last),
        .event_status_channel_halt(), .event_data_in_channel_halt(),
        .event_data_out_channel_halt()
    );
endmodule
