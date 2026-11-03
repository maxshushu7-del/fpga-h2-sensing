`timescale 1ns/1ps
module clock_manager #(parameter CLOCK_INPUT_BUFG=0) (
    input wire clk_200m_p, input wire clk_200m_n, input wire rst_n,
    output wire clk_200MHz, output wire clk_work,
    output wire locked, output wire rst
);
    wire input_clock, feedback_clock, feedback_buffered, work_unbuffered;
    IBUFDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("FALSE")) u_ibufds (
        .I(clk_200m_p), .IB(clk_200m_n), .O(input_clock));
    // Hardware integration may need the controller MMCM in an adjacent CMT.
    // This optional GLOBAL input route permits that placement; all frequencies
    // and the original reset/100MHz controller clock behavior remain unchanged.
    wire mmcm_input_clock;
    generate if(CLOCK_INPUT_BUFG!=0) begin:g_input_global
        BUFG u_input_bufg(.I(input_clock),.O(mmcm_input_clock));
    end else begin:g_input_direct
        assign mmcm_input_clock=input_clock;
    end endgenerate
    // clk_200MHz is the reference clock, not a second controller domain.
    assign clk_200MHz = input_clock;
    // VCO = 200 MHz * 5 = 1000 MHz; working clock = VCO / 10 = 100 MHz.
    MMCME4_BASE #(.BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(5.0),
        .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(5.0), .CLKOUT0_DIVIDE_F(10.0),
        .STARTUP_WAIT("FALSE")) u_mmcm (
        .CLKIN1(mmcm_input_clock), .CLKFBIN(feedback_buffered),
        .RST(!rst_n), .PWRDWN(1'b0), .LOCKED(locked),
        .CLKFBOUT(feedback_clock), .CLKFBOUTB(),
        .CLKOUT0(work_unbuffered), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6());
    BUFG u_feedback_bufg(.I(feedback_clock), .O(feedback_buffered));
    BUFG u_work_bufg(.I(work_unbuffered), .O(clk_work));
    wire reset_async = !rst_n || !locked;
    (* ASYNC_REG = "TRUE" *) reg [2:0] reset_pipe;
    always @(posedge clk_work or posedge reset_async) begin
        if (reset_async) reset_pipe <= 3'b111;
        else reset_pipe <= {reset_pipe[1:0], 1'b0};
    end
    assign rst = reset_pipe[2];
endmodule
