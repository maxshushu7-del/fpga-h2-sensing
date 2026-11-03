`timescale 1ns/1ps
// TX-only 1000BASE-T RGMII physical output for AXAU15 JL2121-N040I PHY.
// Creates 125 MHz via BUFGCE_DIV from DAC MMCM raw 250 MHz output;
// parallel with DAC BUFGCE; no cascaded buffers or extra MMCM. Link MUST negotiate to 1G.
module rgmii_udp_tx(
    input wire clk250,
    input wire reset_async,
    input wire [7:0] tx_byte,
    input wire tx_en,
    output wire phy_tx_clk,
    output wire phy_tx_ctl,
    output wire [3:0] phy_txd,
    output wire phy_reset_n,
    output wire clk125,
    output wire reset125,
    output wire phy_ready_eth
);
    // The raw MMCM CLKOUT0 is already a dedicated 250MHz clock.
    // Dividing clock is left free running; the PHY remains in reset until
    // MMCM LOCKED and then for the power-on settling interval below.
    // NEVER feed a 100MHz-domain reset into BUFGCE_DIV.CLR.
    BUFGCE_DIV #(.BUFGCE_DIVIDE(2), .SIM_DEVICE("ULTRASCALE_PLUS")) u_clk_div (
        .I(clk250), .CE(1'b1), .CLR(1'b0), .O(clk125)
    );
    // Asynchronously assert on key/MMCM loss, but release on the clk125 edge.
    wire reset125_n;
    reset_sync u_reset_125 (.clk(clk125),.async_ok(!reset_async),.rst_n(reset125_n));
    assign reset125 = !reset125_n;
    reg [17:0] release_counter=0;
    reg phy_ready=0;
    // Keep PHY in hardware reset for ~1.6 ms after clock and reset recover.
    always @(posedge clk125) begin
        if (reset125) begin
            release_counter<=0;
            phy_ready<=0;
        end else if(!phy_ready) begin
            if (release_counter==18'd200000)
                phy_ready<=1;
            else release_counter<=release_counter+1'b1;
        end
    end
    // Force external PHY reset immediately if the MMCM loses lock.
    assign phy_reset_n=phy_ready && !reset_async;
    // Same-clock raw ready is used internally, not asynchronous PHY pin logic.
    assign phy_ready_eth=phy_ready;
    wire send_en=phy_ready && !reset125 && tx_en;
    genvar n;
    generate for(n=0;n<4;n=n+1) begin:g_tx
        ODDRE1 #(.IS_C_INVERTED(1'b0),.IS_D1_INVERTED(1'b0),
                 .IS_D2_INVERTED(1'b0),.SIM_DEVICE("ULTRASCALE_PLUS")) u_ddr (
            .C(clk125),.SR(reset125),
            .D1(send_en ? tx_byte[n] : 1'b0),
            .D2(send_en ? tx_byte[n+4] : 1'b0),
            .Q(phy_txd[n])
        );
    end endgenerate
    ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_ctl_ddr (
        .C(clk125),.SR(reset125),.D1(send_en),.D2(send_en),.Q(phy_tx_ctl)
    );
    ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_clk_ddr (
        .C(clk125),.SR(reset125),.D1(1'b1),.D2(1'b0),.Q(phy_tx_clk)
    );
endmodule
