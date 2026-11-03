`timescale 1ns/1ps
// Snapshot crossing: 100 MHz work clock --> 125 MHz Ethernet clock.
// Handshaked coherent 320-bit data (held until destination acknowledges).
// This is a 100 Hz broadcast status channel, never host-to-FPGA control.
module udp_telemetry_bridge #(
    parameter integer CLOCK_HZ=100000000,
    parameter integer PACKET_HZ=100
)(
    input  wire clk_work,
    input  wire clk_eth,
    // Reset sources are LOCAL to their clock domain. Do not feed a work-
    // clock-synchronous reset to Ethernet flops or vice versa.
    input  wire rst_work,
    input  wire rst_eth,
    input  wire [31:0] frequency_hz,
    input  wire [31:0] fft_sequence,
    input  wire signed [15:0] laser_error,
    input  wire signed [15:0] dac_code,
    input  wire signed [31:0] temperature_mc,
    input  wire [15:0] temp_duty,
    input  wire temp_fault,
    input  wire temp_pwm,
    input  wire fft_valid,
    input  wire [7:0] auto_state,
    input  wire [7:0] auto_fault,
    input  wire [7:0] hw_status,
    input  wire fft_enabled,
    output wire [7:0] tx_byte,
    output wire tx_en
);
    localparam integer TICKS=CLOCK_HZ/PACKET_HZ;
    reg [31:0] rate_count=0;
    reg [31:0] seq=0;
    reg [31:0] uptime=0;
    reg [319:0] snapshot=0;
    reg req_toggle=0;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] ack_sync=0;
    reg ack_toggle=0;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] req_sync=0;
    reg req_seen=0;
    reg [319:0] eth_payload=0;
    reg launch=0;
    wire eth_busy;
    wire done;

    // Payload bytes, all big-endian:
    // 00..03 "FPGA"; 04 version; 05 flags; 06 state; 07 servo fault;
    // 08..11 packet seq; 12..15 FFT Hz; 16..19 FFT seq;
    // 20..21 servo error; 22..23 DAC code; 24..27 temp (mC);
    // 28..29 PID duty; 30..31 temp flags; 32..35 uptime in 10ms ticks;
    // 36..39 "TEC2" (demonstration signature).
    always @(posedge clk_work) begin
        if (rst_work) begin
            rate_count<=0;seq<=0;uptime<=0;snapshot<=0;
            req_toggle<=0;ack_sync<=0;
        end else begin
            ack_sync <= {ack_sync[1:0],ack_toggle};
            if (rate_count==TICKS-1) begin
                rate_count<=0;
                uptime<=uptime+1'b1;
                if (req_toggle==ack_sync[2]) begin
                    snapshot <= {
                        32'h46504741, 8'h01,
                        {1'b0,fft_enabled,hw_status[3],hw_status[0],
                          1'b1,1'b0,temp_fault,fft_valid},
                        auto_state, auto_fault, seq,
                        frequency_hz,fft_sequence,laser_error,dac_code,
                        temperature_mc,temp_duty,
                        {13'd0,1'b1,temp_pwm,temp_fault},
                        uptime, 32'h54454332
                    };
                    seq<=seq+1'b1;
                    req_toggle<=~req_toggle;
                end
            end else rate_count<=rate_count+1'b1;
        end
    end

    always @(posedge clk_eth) begin
        if (rst_eth) begin
            req_sync<=0;req_seen<=0;ack_toggle<=0;
            eth_payload<=0;launch<=0;
        end else begin
            req_sync<={req_sync[1:0],req_toggle};
            launch<=0;
            if ((req_sync[2]!=req_seen) && !eth_busy) begin
                eth_payload<=snapshot; // snapshot held across handshake
                req_seen<=req_sync[2];
                ack_toggle<=req_sync[2];
                launch<=1;
            end
        end
    end
    udp_ipv4_frame_tx u_udp_packet (
        .clk(clk_eth),.rst(rst_eth),.packet_start(launch),
        .payload(eth_payload),.tx_byte(tx_byte),.tx_en(tx_en),
        .busy(eth_busy),.packet_done(done)
    );
endmodule
