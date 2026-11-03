`timescale 1ns/1ps
// AD9122 16-pair LVDS word-mode transmitter for the PZ-FL4322 card.
// ADI AD9122 Rev.C: Reg03=00 => two's complement, I first, 16-bit word.
// DCI-high half: I=held servo code; DCI-low half: Q=0000 (midscale).
// FRAME stays low: the initialization sequencer must issue software FIFO reset
// (Reg18), check completion/status, and configure bypass interpolation as needed.
// This transmitter implements no DAC SPI or laser protocol and assumes no
// analog voltage/current relationship. Disabled zero code is DAC midscale.
//
// Default: PZ reference 500MHz input, VCO=1000MHz, data=500MHz, DCI=500MHz
// delayed by 125ps (22.5deg). For 250MHz use input period4.0, mult4.0,
// divide4, with the SAME rate applied to AD9122 DACCLK in the AD9516 table.
// DATA+DCI serializers use generated MMCM clocks, never fabric-gated clocks.
// Vivado derives clocks automatically at u_clock_mmcm/CLKOUT0 and CLKOUT1.
// Check with get_clocks -of_objects [get_pins <instance>/u_clock_mmcm/CLKOUT0]
// and CLKOUT1, report_clocks, and report_timing to output DDR ports. External
// DCI/data board skew and AD9122 setup=-0.05ns/hold=.65ns must be constrained.
//
// control_valid is a pulse in clk_work. The mailbox holds data through ack.
// If busy, a single pending register keeps the most recent update (not a FIFO).
// Core servo pulses need no change: 100kHz is far below mailbox throughput.
// control_ready reports immediate mailbox availability, not pending acceptance.
// clk_work, tx_enable and config_done are synchronous in the work-clock domain.
module hw_ad9122_tx #(
    parameter real INPUT_CLK_PERIOD_NS=2.0,
    parameter real MMCM_MULT_F=2.0,
    parameter integer OUTPUT_DIVIDE=2,
    parameter real DCI_DELAY_PS=125.0
) (
    input wire clk_work, input wire rst_n,
    input wire fpga_clk_p, input wire fpga_clk_n,
    input wire signed [15:0] control_in, input wire control_valid,
    input wire tx_enable, input wire config_done,
    output wire control_ready, output wire tx_clk_out,
    output wire tx_clock_locked, output wire tx_active,
    output wire [15:0] dac_data_p, output wire [15:0] dac_data_n,
    output wire dac_dci_p, output wire dac_dci_n,
    output wire dac_frame_p, output wire dac_frame_n
);
    localparam real TX_PERIOD_NS=INPUT_CLK_PERIOD_NS*OUTPUT_DIVIDE/MMCM_MULT_F;
    localparam real DCI_PHASE_DEG=360.0*(DCI_DELAY_PS/1000.0)/TX_PERIOD_NS;
    wire reference_clk,feedback_raw,feedback_clk,data_raw,data_clk,dci_raw,dci_clk;
    wire clock_locked;
    IBUFDS #(.DIFF_TERM("TRUE"),.IBUF_LOW_PWR("FALSE")) u_clock_input(
        .I(fpga_clk_p),.IB(fpga_clk_n),.O(reference_clk));
    MMCME4_BASE #(.BANDWIDTH("OPTIMIZED"),.CLKIN1_PERIOD(INPUT_CLK_PERIOD_NS),
        .DIVCLK_DIVIDE(1),.CLKFBOUT_MULT_F(MMCM_MULT_F),
        .CLKOUT0_DIVIDE_F(OUTPUT_DIVIDE),.CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(OUTPUT_DIVIDE),.CLKOUT1_PHASE(DCI_PHASE_DEG),
        .STARTUP_WAIT("FALSE")) u_clock_mmcm(
        .CLKIN1(reference_clk),.CLKFBIN(feedback_clk),.RST(!rst_n),.PWRDWN(1'b0),
        .LOCKED(clock_locked),.CLKFBOUT(feedback_raw),.CLKFBOUTB(),
        .CLKOUT0(data_raw),.CLKOUT0B(),.CLKOUT1(dci_raw),.CLKOUT1B(),
        .CLKOUT2(),.CLKOUT2B(),.CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
    BUFG u_feedback_clock(.I(feedback_raw),.O(feedback_clk));
    BUFG u_tx_clock(.I(data_raw),.O(data_clk));
    BUFG u_dci_clock(.I(dci_raw),.O(dci_clk));
    assign tx_clk_out=data_clk;
    assign tx_clock_locked=clock_locked;
    wire reset_async=!rst_n || !clock_locked;
    (* ASYNC_REG="TRUE" *) reg [2:0] work_reset_pipe;
    (* ASYNC_REG="TRUE" *) reg [2:0] tx_reset_pipe;
    (* ASYNC_REG="TRUE" *) reg [2:0] dci_reset_pipe;
    always @(posedge clk_work or posedge reset_async) begin
        if(reset_async) work_reset_pipe<=3'b111;
        else work_reset_pipe<={work_reset_pipe[1:0],1'b0};
    end
    always @(posedge data_clk or posedge reset_async) begin
        if(reset_async) tx_reset_pipe<=3'b111;
        else tx_reset_pipe<={tx_reset_pipe[1:0],1'b0};
    end
    always @(posedge dci_clk or posedge reset_async) begin
        if(reset_async) dci_reset_pipe<=3'b111;
        else dci_reset_pipe<={dci_reset_pipe[1:0],1'b0};
    end
    wire work_rst=work_reset_pipe[2];
    wire tx_rst=tx_reset_pipe[2];
    wire dci_rst=dci_reset_pipe[2];

    reg signed [15:0] mailbox_code,pending_code;
    reg mailbox_epoch,source_epoch,source_was_enabled,pending_valid,request_toggle;
    reg acknowledge_toggle;
    (* ASYNC_REG="TRUE" *) reg [2:0] acknowledge_sync;
    wire source_enabled=tx_enable && config_done;
    wire mailbox_busy=request_toggle!=acknowledge_sync[2];
    assign control_ready=source_enabled && !work_rst && !mailbox_busy;
    // mailbox_code/mailbox_epoch form a bundled CDC bus: they remain unchanged
    // until the destination's acknowledgement returns. Constrain max delay of
    // this bus to its destination capture register; never sync each data bit.
    always @(posedge clk_work or posedge reset_async) begin
        if(reset_async) begin
            acknowledge_sync<=0; request_toggle<=0;
            mailbox_code<=0; mailbox_epoch<=0; pending_code<=0; pending_valid<=0;
            source_epoch<=0; source_was_enabled<=0;
        end else if(work_rst) begin
            acknowledge_sync<=0; request_toggle<=0;
            mailbox_code<=0; mailbox_epoch<=0; pending_code<=0; pending_valid<=0;
            source_epoch<=0; source_was_enabled<=0;
        end else begin
            acknowledge_sync<={acknowledge_sync[1:0],acknowledge_toggle};
            source_was_enabled<=source_enabled;
            if(!source_enabled) begin
                pending_valid<=0;
                // Old in-flight messages cannot restore a stale code after a
                // disable/re-enable. Enable must be held for >=one work clock.
                if(source_was_enabled) source_epoch<=~source_epoch;
            end else if(!mailbox_busy) begin
                if(control_valid) begin
                    mailbox_code<=control_in; mailbox_epoch<=source_epoch;
                    request_toggle<=~request_toggle; pending_valid<=0;
                end else if(pending_valid) begin
                    mailbox_code<=pending_code; mailbox_epoch<=source_epoch;
                    request_toggle<=~request_toggle; pending_valid<=0;
                end
            end else if(control_valid) begin
                pending_code<=control_in; pending_valid<=1;
            end
        end
    end

    (* ASYNC_REG="TRUE" *) reg [2:0] request_sync,epoch_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] enable_sync,configured_sync;
    reg request_seen,capture_token;
    reg [1:0] capture_wait;
    reg signed [15:0] held_code;
    wire enabled_tx=enable_sync[1] && configured_sync[1];
    assign tx_active=enabled_tx && !tx_rst;
    always @(posedge data_clk or posedge reset_async) begin
        if(reset_async) begin
            request_sync<=0; epoch_sync<=0; enable_sync<=0; configured_sync<=0;
            acknowledge_toggle<=0; request_seen<=0; capture_token<=0;
            capture_wait<=0; held_code<=0;
        end else if(tx_rst) begin
            request_sync<=0; epoch_sync<=0; enable_sync<=0; configured_sync<=0;
            acknowledge_toggle<=0; request_seen<=0; capture_token<=0;
            capture_wait<=0; held_code<=0;
        end else begin
            request_sync<={request_sync[1:0],request_toggle};
            epoch_sync<={epoch_sync[1:0],source_epoch};
            enable_sync<={enable_sync[0],tx_enable};
            configured_sync<={configured_sync[0],config_done};
            if(!enabled_tx) held_code<=0;
            if(capture_wait!=0) begin
                capture_wait<=capture_wait-1'b1;
                if(capture_wait==1) begin
                    if(enabled_tx && mailbox_epoch==epoch_sync[2]) held_code<=mailbox_code;
                    else held_code<=0;
                    request_seen<=capture_token;
                    acknowledge_toggle<=capture_token;
                end
            end else if(request_sync[2]!=request_seen) begin
                capture_token<=request_sync[2]; capture_wait<=2;
            end
        end
    end
    wire [15:0] i_code=tx_active ? held_code : 16'h0000;
    wire [15:0] serialized_data;
    genvar bit_index;
    generate for(bit_index=0;bit_index<16;bit_index=bit_index+1) begin: g_data
        ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_data_ddr(
            .C(data_clk),.D1(i_code[bit_index]),.D2(1'b0),.SR(tx_rst),.Q(serialized_data[bit_index]));
        OBUFDS #(.IOSTANDARD("LVDS")) u_data_output(
            .I(serialized_data[bit_index]),.O(dac_data_p[bit_index]),.OB(dac_data_n[bit_index]));
    end endgenerate
    wire serialized_dci,serialized_frame;
    ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_dci_ddr(
        .C(dci_clk),.D1(1'b1),.D2(1'b0),.SR(dci_rst),.Q(serialized_dci));
    OBUFDS #(.IOSTANDARD("LVDS")) u_dci_output(
        .I(serialized_dci),.O(dac_dci_p),.OB(dac_dci_n));
    ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_frame_ddr(
        .C(data_clk),.D1(1'b0),.D2(1'b0),.SR(tx_rst),.Q(serialized_frame));
    OBUFDS #(.IOSTANDARD("LVDS")) u_frame_output(
        .I(serialized_frame),.O(dac_frame_p),.OB(dac_frame_n));
endmodule
