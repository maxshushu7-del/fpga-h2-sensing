`timescale 1ns/1ps
// Fixed 64-byte packet. Version3 algorithm emits protocol3: byte61 bit1=low_mode,
// bit0=fine_mode. Legacy algorithms keep protocol2; see host/monitor_v2.py.
// Measurement is NEVER gated by UART. One latest-result pending slot; replaced
// pending packets increment dropped_results. No unbounded FIFO or stale queue.
module result_uart_v2 #(
    parameter integer ALGORITHM_VERSION=1, ADC_CHANNEL=1, FFT_LOG2=12,
    parameter integer OUT_WIDTH=29, ADC_SAMPLE_RATE_HZ=250000000,
    parameter integer DECIMATION=250, WINDOW_ENABLE=1,
    parameter integer CLOCK_HZ=100000000, BAUD_RATE=115200
) (
    input wire clk,rst_n,result_strobe,measurement_valid,fine_mode,low_mode,
    input wire [31:0] frequency_hz,sequence_number,
    input wire [FFT_LOG2-1:0] peak_bin,coarse_bin,
    input wire signed [17:0] bin_offset_q16,
    input wire signed [31:0] fine_offset_hz,
    input wire [2*OUT_WIDTH:0] peak_power,noise_power,
    input wire [31:0] clipped_samples,
    input wire [7:0] result_flags,
    output wire uart_tx,
    output reg [31:0] dropped_results
);
    reg [503:0] payload;
    reg [7:0] checksum;
    reg pending;
    wire [31:0] packet_drop_count=dropped_results+((result_strobe && pending) ? 32'd1 : 32'd0);
    integer k;
    always @* begin
        payload=0;
        payload[0+:16]=16'h5aa5; payload[16+:8]=(ALGORITHM_VERSION==3 ? 3 : 2); payload[24+:8]=64;
        payload[32+:8]=ALGORITHM_VERSION; payload[40+:8]=ADC_CHANNEL;
        payload[48+:8]=FFT_LOG2; payload[56+:8]=result_flags;
        payload[64+:32]=sequence_number; payload[96+:32]=ADC_SAMPLE_RATE_HZ;
        payload[128+:32]=(fine_mode || (ALGORITHM_VERSION==3 && low_mode)) ? ADC_SAMPLE_RATE_HZ/DECIMATION : ADC_SAMPLE_RATE_HZ;
        payload[160+:32]=frequency_hz; payload[192+:32]=fine_offset_hz;
        payload[224+:16]=coarse_bin; payload[240+:16]=peak_bin;
        payload[256+:32]={{14{bin_offset_q16[17]}},bin_offset_q16};
        payload[288+:32]=clipped_samples;
        payload[320+:64]={{(63-2*OUT_WIDTH){1'b0}},peak_power};
        payload[384+:64]={{(63-2*OUT_WIDTH){1'b0}},noise_power};
        payload[448+:32]=packet_drop_count;
        payload[480+:8]={7'd0,measurement_valid};
        payload[488+:8]={6'd0,(ALGORITHM_VERSION==3 && low_mode),fine_mode}; payload[496+:8]=WINDOW_ENABLE;
        checksum=0;
        for(k=0;k<63;k=k+1) checksum=checksum^payload[k*8+:8];
    end
    reg [511:0] packet,pending_packet;
    reg [5:0] byte_index;
    reg [1:0] state;
    reg byte_start;
    wire byte_busy,byte_done;
    localparam IDLE=0,ISSUE=1,WAIT_BYTE=2;
    uart_byte_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD_RATE(BAUD_RATE)) u_byte (
        .clk(clk),.rst_n(rst_n),.start(byte_start),.data(packet[byte_index*8+:8]),
        .tx(uart_tx),.busy(byte_busy),.done(byte_done));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; pending<=0; packet<=0; pending_packet<=0;
            byte_index<=0; byte_start<=0; dropped_results<=0;
        end else begin
            byte_start<=0;
            if(result_strobe) begin
                pending_packet<={checksum,payload}; pending<=1;
                if(pending && state!=IDLE) dropped_results<=dropped_results+1;
            end
            case(state)
                IDLE: if(result_strobe) begin
                    if(pending) dropped_results<=dropped_results+1;
                    packet<={checksum,payload}; pending<=0; byte_index<=0; state<=ISSUE;
                end else if(pending) begin
                    packet<=pending_packet; pending<=0; byte_index<=0; state<=ISSUE;
                end
                ISSUE: if(!byte_busy) begin byte_start<=1; state<=WAIT_BYTE; end
                WAIT_BYTE: if(byte_done) begin
                    if(byte_index==63) state<=IDLE;
                    else begin byte_index<=byte_index+1; state<=ISSUE; end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
