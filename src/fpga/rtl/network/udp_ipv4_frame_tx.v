`timescale 1ns/1ps
// Minimal TRANSMIT-ONLY Ethernet II + IPv4 + UDP frame serializer.
// 125 MHz, one byte per clock, output Ethernet preamble, frame, CRC32/FCS,
// and 12 byte IFG. No receive logic, ARP, DHCP, flow control or link training.
// Destination is broadcast Ethernet/IP, so ARP is intentionally not required.
// UDP checksum zero is legal for IPv4. IPv4 header checksum is generated.
// 40-byte payload, UDP length=48, IPv4 length=68, L2 frame=82 bytes.
module udp_ipv4_frame_tx #(
    parameter [47:0] SRC_MAC = 48'h021566000001,
    parameter [31:0] SRC_IP = 32'hC0A8010A,
    parameter [31:0] DST_IP = 32'hC0A801FF,
    parameter [15:0] SRC_PORT = 16'd5000,
    parameter [15:0] DST_PORT = 16'd5001
)(
    input  wire clk,
    input  wire rst,
    input  wire packet_start,
    input  wire [319:0] payload,
    output reg  [7:0] tx_byte = 8'h00,
    output reg tx_en = 1'b0,
    output wire busy,
    output reg packet_done = 1'b0
);
    localparam [2:0] S_IDLE=0, S_PREAMBLE=1, S_FRAME=2, S_FCS=3, S_IFG=4;
    reg [2:0] state = S_IDLE;
    reg [6:0] count = 0;
    reg [319:0] stored_payload = 0;
    reg [31:0] crc = 32'hFFFFFFFF;
    reg [31:0] fcs = 0;
    assign busy = (state != S_IDLE);

    function [31:0] crc32_byte;
        input [31:0] c;
        input [7:0] b;
        reg [31:0] t;
        integer k;
        begin
            t = c ^ {24'h0,b};
            for (k=0;k<8;k=k+1)
                if (t[0]) t = (t >> 1) ^ 32'hEDB88320;
                else      t = (t >> 1);
            crc32_byte = t;
        end
    endfunction

    // Fold 32-bit sum into 16 bits, then one's complement.
    function [15:0] ip_header_sum;
        input [31:0] src;
        input [31:0] dst;
        reg [31:0] s;
        begin
            s = 32'h4500 + 32'h0044 + 32'h0000 + 32'h4000 + 32'h4011
                + {16'h0,src[31:16]} + {16'h0,src[15:0]}
                + {16'h0,dst[31:16]} + {16'h0,dst[15:0]};
            s = {16'd0,s[15:0]} + {16'd0,s[31:16]};
            s = {16'd0,s[15:0]} + {16'd0,s[31:16]};
            ip_header_sum = ~s[15:0];
        end
    endfunction
    localparam [15:0] IP_CHECKSUM=ip_header_sum(SRC_IP,DST_IP);

    function [7:0] eth_byte;
        input [6:0] idx;
        input [319:0] pl;
        begin
            case (idx)
                7'd0,7'd1,7'd2,7'd3,7'd4,7'd5: eth_byte=8'hFF;
                7'd6:  eth_byte=SRC_MAC[47:40];
                7'd7:  eth_byte=SRC_MAC[39:32];
                7'd8:  eth_byte=SRC_MAC[31:24];
                7'd9:  eth_byte=SRC_MAC[23:16];
                7'd10: eth_byte=SRC_MAC[15:8];
                7'd11: eth_byte=SRC_MAC[7:0];
                7'd12: eth_byte=8'h08;
                7'd13: eth_byte=8'h00;
                7'd14: eth_byte=8'h45;
                7'd15: eth_byte=8'h00;
                7'd16: eth_byte=8'h00;
                7'd17: eth_byte=8'h44;
                7'd18: eth_byte=8'h00;
                7'd19: eth_byte=8'h00;
                7'd20: eth_byte=8'h40;
                7'd21: eth_byte=8'h00;
                7'd22: eth_byte=8'h40;
                7'd23: eth_byte=8'h11;
                7'd24: eth_byte=IP_CHECKSUM[15:8];
                7'd25: eth_byte=IP_CHECKSUM[7:0];
                7'd26: eth_byte=SRC_IP[31:24];
                7'd27: eth_byte=SRC_IP[23:16];
                7'd28: eth_byte=SRC_IP[15:8];
                7'd29: eth_byte=SRC_IP[7:0];
                7'd30: eth_byte=DST_IP[31:24];
                7'd31: eth_byte=DST_IP[23:16];
                7'd32: eth_byte=DST_IP[15:8];
                7'd33: eth_byte=DST_IP[7:0];
                7'd34: eth_byte=SRC_PORT[15:8];
                7'd35: eth_byte=SRC_PORT[7:0];
                7'd36: eth_byte=DST_PORT[15:8];
                7'd37: eth_byte=DST_PORT[7:0];
                7'd38: eth_byte=8'h00;
                7'd39: eth_byte=8'h30;
                7'd40: eth_byte=8'h00; // UDP checksum omitted for IPv4
                7'd41: eth_byte=8'h00;
                default: eth_byte=pl[319-((idx-7'd42)*8) -: 8];
            endcase
        end
    endfunction
    wire [7:0] current_data = eth_byte(count,stored_payload);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            count <= 0;
            stored_payload <= 0;
            crc <= 32'hFFFFFFFF;
            fcs <= 0;
            tx_en <= 0;
            tx_byte <= 0;
            packet_done <= 0;
        end else begin
            tx_byte <= 0;
            tx_en <= 0;
            packet_done <= 0;
            case (state)
                S_IDLE: begin
                    count <= 0;
                    if (packet_start) begin
                        stored_payload <= payload;
                        crc <= 32'hFFFFFFFF;
                        state <= S_PREAMBLE;
                    end
                end
                S_PREAMBLE: begin
                    tx_en <= 1;
                    tx_byte <= count==7'd7 ? 8'hD5 : 8'h55;
                    if (count==7'd7) begin
                        count <= 0;
                        state <= S_FRAME;
                    end else count <= count+1'b1;
                end
                S_FRAME: begin
                    tx_en <= 1;
                    tx_byte <= current_data;
                    crc <= crc32_byte(crc,current_data);
                    if (count==7'd81) begin
                        fcs <= ~crc32_byte(crc,current_data);
                        count <= 0;
                        state <= S_FCS;
                    end else count <= count+1'b1;
                end
                S_FCS: begin
                    tx_en <= 1;
                    case(count)
                        7'd0:tx_byte<=fcs[7:0];
                        7'd1:tx_byte<=fcs[15:8];
                        7'd2:tx_byte<=fcs[23:16];
                        default:tx_byte<=fcs[31:24];
                    endcase
                    if (count==7'd3) begin
                        count<=0;
                        state<=S_IFG;
                        packet_done<=1;
                    end else count<=count+1'b1;
                end
                S_IFG: begin
                    if (count==7'd11) begin
                        count<=0;
                        state<=S_IDLE;
                    end else count<=count+1'b1;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
