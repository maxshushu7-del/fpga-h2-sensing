`timescale 1ns/1ps
// AD9643 Parallel Interleaved DDR LVDS receiver for UltraScale/UltraScale+.
// Required ADC setup: register 0x14=0x05, 0x16=0x00, 0x17=0x85 in the
// supplied FL4322 reference. Q1 is channel A, Q2 channel B for this phase.
// 0x16 bit5 must be zero: Channel Multiplexed (Even/Odd), bit5=1, is a
// different pin/data layout and is not supported by this 14-pair receiver.
// CHANNEL_SWAP permits explicit board/DCO phase correction; it is not autodetect.
// DEFAULT DECIMATION=256: 250 MHz / 256 = 976.5625 kword/s on one channel.
// This is sample selection, not a digital anti-alias filter or lossless FFT PHY.
//
// CDC is a bundled-data request/acknowledge mailbox, plus one latest pending
// source item. mailbox_data stays constant until ack_sync2 returns the request.
// Constrain mailbox_data_reg[*] -> adc_data_out_reg[*] with bounded max_delay
// and bus_skew; false-path ONLY asynchronous inputs into the first sync stages.
// Never replace this mailbox with per-bit synchronizers on the changing data.
// overflow/dropped mean overwritten selected pending items, not intentional
// decimation. Both remain sticky/counting until external reset.
module hw_ad9643_rx #(
    parameter integer DECIMATION = 256,
    parameter integer CHANNEL_SELECT = 0,
    parameter integer CHANNEL_SWAP = 0,
    parameter integer OFFSET_BINARY = 0,
    parameter DIFF_TERM = "FALSE"
) (
    input wire rst_n,
    input wire clk_work,
    input wire config_done,
    input wire adc_dco_p, input wire adc_dco_n,
    input wire [13:0] adc_data_p, input wire [13:0] adc_data_n,
    input wire adc_ready,
    output wire adc_clk_out,
    output wire [13:0] raw_data_a, output wire [13:0] raw_data_b,
    output reg signed [13:0] adc_data_out,
    output reg adc_valid,
    output wire rx_ready,
    output wire rx_clock_locked,
    output wire overflow_sticky,
    output wire [31:0] dropped_count
);
    localparam integer SELECT_PERIOD = DECIMATION < 1 ? 1 : DECIMATION;
    wire dco_ibuf,dco_feedback,dco_feedback_buffered,dco_capture_unbuffered;
    wire [13:0] input_bits, rising_word, falling_word;
    IBUFDS #(.DIFF_TERM(DIFF_TERM), .IBUF_LOW_PWR("FALSE")) u_dco_ibuf
        (.I(adc_dco_p), .IB(adc_dco_n), .O(dco_ibuf));
    // MMCM feedback compensates the global capture-clock insertion
    // delay. A direct IBUFDS->BUFG clock is not deskewed against the input data.
    // 250 MHz DCO * 4 = 1000 MHz VCO; /4 gives a 250 MHz capture clock.
    // +33.75 degrees = +375ps capture offset at 250MHz. This centers the
    // physical input eye for the current board-level setup/hold envelope.
    MMCME4_BASE #(.BANDWIDTH("OPTIMIZED"),.CLKIN1_PERIOD(4.0),
        .DIVCLK_DIVIDE(1),.CLKFBOUT_MULT_F(4.0),.CLKOUT0_DIVIDE_F(4.0),
        .CLKOUT0_PHASE(33.75),.STARTUP_WAIT("FALSE")) u_dco_mmcm
        (.CLKIN1(dco_ibuf),.CLKFBIN(dco_feedback_buffered),
         .RST(!rst_n),.PWRDWN(1'b0),.LOCKED(rx_clock_locked),
         .CLKFBOUT(dco_feedback),.CLKFBOUTB(),
         .CLKOUT0(dco_capture_unbuffered),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),
         .CLKOUT2(),.CLKOUT2B(),.CLKOUT3(),.CLKOUT3B(),
         .CLKOUT4(),.CLKOUT5(),.CLKOUT6());
    BUFG u_dco_feedback_bufg(.I(dco_feedback),.O(dco_feedback_buffered));
    BUFG u_dco_bufg(.I(dco_capture_unbuffered),.O(adc_clk_out));
    // Reset both halves of the toggle mailbox on capture-clock loss, so an
    // old acknowledgement cannot masquerade as a new request after relock.
    wire receiver_reset_async=!rst_n || !rx_clock_locked;

    (* ASYNC_REG="TRUE" *) reg [2:0] source_reset_pipe;
    (* ASYNC_REG="TRUE" *) reg [2:0] work_reset_pipe;
    always @(posedge adc_clk_out or posedge receiver_reset_async) begin
        if(receiver_reset_async) source_reset_pipe<=3'b111;
        else source_reset_pipe<={source_reset_pipe[1:0],1'b0};
    end
    always @(posedge clk_work or posedge receiver_reset_async) begin
        if(receiver_reset_async) work_reset_pipe<=3'b111;
        else work_reset_pipe<={work_reset_pipe[1:0],1'b0};
    end
    wire source_rst=source_reset_pipe[2];
    wire work_rst=work_reset_pipe[2];
    genvar bit_index;
    generate for(bit_index=0;bit_index<14;bit_index=bit_index+1) begin:g_data
        IBUFDS #(.DIFF_TERM(DIFF_TERM), .IBUF_LOW_PWR("FALSE")) u_data_ibuf
            (.I(adc_data_p[bit_index]),.IB(adc_data_n[bit_index]),.O(input_bits[bit_index]));
        // Use dedicated clock inversion, avoiding a LUT on the clock path.
        IDDRE1 #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
            .IS_C_INVERTED(1'b0),.IS_CB_INVERTED(1'b1)) u_ddr
            (.C(adc_clk_out),.CB(adc_clk_out),.D(input_bits[bit_index]),
             .R(source_rst),.Q1(rising_word[bit_index]),.Q2(falling_word[bit_index]));
    end endgenerate
    assign raw_data_a=CHANNEL_SWAP ? falling_word:rising_word;
    assign raw_data_b=CHANNEL_SWAP ? rising_word:falling_word;
    wire [13:0] selected_raw=CHANNEL_SELECT ? raw_data_b:raw_data_a;
    wire [13:0] selected_signed=OFFSET_BINARY ? {~selected_raw[13],selected_raw[12:0]}:selected_raw;

    reg request_toggle, acknowledge_toggle;
    (* ASYNC_REG="TRUE" *) reg ack_sync1,ack_sync2;
    (* ASYNC_REG="TRUE" *) reg config_sync1,config_sync2;
    always @(posedge adc_clk_out or posedge receiver_reset_async) begin
        if(receiver_reset_async) begin ack_sync1<=0;ack_sync2<=0;config_sync1<=0;config_sync2<=0;end
        else if(source_rst) begin ack_sync1<=0;ack_sync2<=0;config_sync1<=0;config_sync2<=0;end
        else begin
            ack_sync1<=acknowledge_toggle;ack_sync2<=ack_sync1;
            config_sync1<=config_done;config_sync2<=config_sync1;
        end
    end
    (* KEEP="TRUE" *) reg [13:0] mailbox_data;
    reg [13:0] pending_data;
    reg pending_valid,source_ready;
    reg [2:0] warmup_count;
    reg [31:0] decimation_count,dropped_count_source,dropped_gray_source;
    reg overflow_source;
    wire mailbox_free=(request_toggle==ack_sync2);
    wire sample_event=source_ready && (decimation_count==SELECT_PERIOD-1);
    wire drop_event=sample_event && pending_valid;
    always @(posedge adc_clk_out or posedge receiver_reset_async) begin
        if(receiver_reset_async) begin
            mailbox_data<=0;request_toggle<=0;pending_data<=0;pending_valid<=0;
            source_ready<=0;warmup_count<=0;decimation_count<=0;
            dropped_count_source<=0;dropped_gray_source<=0;overflow_source<=0;
        end else if(source_rst) begin
            mailbox_data<=0;request_toggle<=0;pending_data<=0;pending_valid<=0;
            source_ready<=0;warmup_count<=0;decimation_count<=0;
            dropped_count_source<=0;dropped_gray_source<=0;overflow_source<=0;
        end else if(!config_sync2) begin
            source_ready<=0;warmup_count<=0;decimation_count<=0;pending_valid<=0;
            // Do not change a published request/payload while it is in flight.
        end else if(!source_ready) begin
            if(warmup_count==3) source_ready<=1;
            else warmup_count<=warmup_count+1'b1;
        end else begin
            if(sample_event) decimation_count<=0;
            else decimation_count<=decimation_count+1'b1;
            if(mailbox_free) begin
                if(sample_event) begin
                    mailbox_data<=selected_signed;request_toggle<=~request_toggle;
                    pending_valid<=0;
                end else if(pending_valid) begin
                    mailbox_data<=pending_data;request_toggle<=~request_toggle;
                    pending_valid<=0;
                end
            end else if(sample_event) begin
                pending_data<=selected_signed;pending_valid<=1;
            end
            if(drop_event) begin
                overflow_source<=1;dropped_count_source<=dropped_count_source+1'b1;
                dropped_gray_source<=((dropped_count_source+1'b1)>>1)^(dropped_count_source+1'b1);
            end
        end
    end

    (* ASYNC_REG="TRUE" *) reg req_sync1,req_sync2;
    (* ASYNC_REG="TRUE" *) reg source_ready_sync1,source_ready_sync2;
    (* ASYNC_REG="TRUE" *) reg overflow_sync1,overflow_sync2;
    (* ASYNC_REG="TRUE" *) reg [31:0] drop_gray_sync1,drop_gray_sync2;
    always @(posedge clk_work or posedge receiver_reset_async) begin
        if(receiver_reset_async) begin
            req_sync1<=0;req_sync2<=0;source_ready_sync1<=0;source_ready_sync2<=0;
            overflow_sync1<=0;overflow_sync2<=0;drop_gray_sync1<=0;drop_gray_sync2<=0;
        end else if(work_rst) begin
            req_sync1<=0;req_sync2<=0;source_ready_sync1<=0;source_ready_sync2<=0;
            overflow_sync1<=0;overflow_sync2<=0;drop_gray_sync1<=0;drop_gray_sync2<=0;
        end else begin
            req_sync1<=request_toggle;req_sync2<=req_sync1;
            source_ready_sync1<=source_ready;source_ready_sync2<=source_ready_sync1;
            overflow_sync1<=overflow_source;overflow_sync2<=overflow_sync1;
            drop_gray_sync1<=dropped_gray_source;drop_gray_sync2<=drop_gray_sync1;
        end
    end
    always @(posedge clk_work or posedge receiver_reset_async) begin
        if(receiver_reset_async) begin acknowledge_toggle<=0;adc_data_out<=0;adc_valid<=0;end
        else if(work_rst) begin acknowledge_toggle<=0;adc_data_out<=0;adc_valid<=0;end
        else begin
            if(!config_done) begin adc_data_out<=0;adc_valid<=0;end
            else if(adc_valid && adc_ready) adc_valid<=0;
            if(req_sync2!=acknowledge_toggle && (!config_done || !adc_valid || adc_ready)) begin
                // Request has crossed two stages; source bus is held until ack.
                acknowledge_toggle<=req_sync2;
                if(config_done) begin adc_data_out<=$signed(mailbox_data);adc_valid<=1;end
            end
        end
    end
    assign rx_ready=config_done && source_ready_sync2 && !work_rst && rx_clock_locked;
    assign overflow_sticky=overflow_sync2;
    genvar gray_index;
    generate for(gray_index=0;gray_index<32;gray_index=gray_index+1) begin:g_decode_count
        assign dropped_count[gray_index]=^(drop_gray_sync2>>gray_index);
    end endgenerate
endmodule
