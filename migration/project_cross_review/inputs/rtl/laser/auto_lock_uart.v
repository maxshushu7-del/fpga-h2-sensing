`timescale 1ns/1ps
// Human-readable 115200 baud (8N1) report on AXAU15 CP2102 USB-UART TX.
// One line every 0.5 seconds. All numbers are hexadecimal; 16-bit values are
// signed two's complement ADC/DAC codes, not measured voltages.
module auto_lock_uart #(parameter integer CLOCK_HZ=100000000,
    parameter integer BAUD=115200,parameter integer PERIOD_CLOCKS=50000000) (
    input wire clk,input wire rst,
    input wire [3:0] state,input wire locked,input wire [3:0] reason,
    input wire [7:0] attempts,input wire signed [13:0] adc,
    input wire signed [15:0] dac,target,minimum,maximum,
    input wire [31:0] losses,output wire tx);
    localparam integer BAUD_DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    localparam integer LENGTH=76;
    reg [31:0] period_count;
    reg [7:0] pos;
    reg [15:0] bit_timer;
    reg [3:0] bit_count;
    reg [9:0] shift_word;
    reg [1:0] tx_state;
    reg [3:0] snap_state,snap_reason;
    reg snap_locked;
    reg [7:0] snap_attempts;
    reg [15:0] snap_adc,snap_dac,snap_target,snap_minimum,snap_maximum;
    reg [31:0] snap_losses;
    reg [7:0] next_char;
    function [7:0] to_hex(input [3:0] h);
        begin to_hex=(h<10)?(8'h30+h):(8'h41+h-10);end
    endfunction
    always @* begin
        case(pos)
            8'd0: next_char=8'h53;
            8'd1: next_char=8'h3d;
            8'd2: next_char=to_hex(snap_state[3:0]);
            8'd3: next_char=8'h20;
            8'd4: next_char=8'h4c;
            8'd5: next_char=8'h3d;
            8'd6: next_char=to_hex({3'b000,snap_locked});
            8'd7: next_char=8'h20;
            8'd8: next_char=8'h52;
            8'd9: next_char=8'h3d;
            8'd10: next_char=to_hex(snap_reason[3:0]);
            8'd11: next_char=8'h20;
            8'd12: next_char=8'h41;
            8'd13: next_char=8'h3d;
            8'd14: next_char=to_hex(snap_attempts[7:4]);
            8'd15: next_char=to_hex(snap_attempts[3:0]);
            8'd16: next_char=8'h20;
            8'd17: next_char=8'h41;
            8'd18: next_char=8'h44;
            8'd19: next_char=8'h43;
            8'd20: next_char=8'h3d;
            8'd21: next_char=to_hex(snap_adc[15:12]);
            8'd22: next_char=to_hex(snap_adc[11:8]);
            8'd23: next_char=to_hex(snap_adc[7:4]);
            8'd24: next_char=to_hex(snap_adc[3:0]);
            8'd25: next_char=8'h20;
            8'd26: next_char=8'h44;
            8'd27: next_char=8'h41;
            8'd28: next_char=8'h43;
            8'd29: next_char=8'h3d;
            8'd30: next_char=to_hex(snap_dac[15:12]);
            8'd31: next_char=to_hex(snap_dac[11:8]);
            8'd32: next_char=to_hex(snap_dac[7:4]);
            8'd33: next_char=to_hex(snap_dac[3:0]);
            8'd34: next_char=8'h20;
            8'd35: next_char=8'h53;
            8'd36: next_char=8'h45;
            8'd37: next_char=8'h54;
            8'd38: next_char=8'h3d;
            8'd39: next_char=to_hex(snap_target[15:12]);
            8'd40: next_char=to_hex(snap_target[11:8]);
            8'd41: next_char=to_hex(snap_target[7:4]);
            8'd42: next_char=to_hex(snap_target[3:0]);
            8'd43: next_char=8'h20;
            8'd44: next_char=8'h4d;
            8'd45: next_char=8'h49;
            8'd46: next_char=8'h4e;
            8'd47: next_char=8'h3d;
            8'd48: next_char=to_hex(snap_minimum[15:12]);
            8'd49: next_char=to_hex(snap_minimum[11:8]);
            8'd50: next_char=to_hex(snap_minimum[7:4]);
            8'd51: next_char=to_hex(snap_minimum[3:0]);
            8'd52: next_char=8'h20;
            8'd53: next_char=8'h4d;
            8'd54: next_char=8'h41;
            8'd55: next_char=8'h58;
            8'd56: next_char=8'h3d;
            8'd57: next_char=to_hex(snap_maximum[15:12]);
            8'd58: next_char=to_hex(snap_maximum[11:8]);
            8'd59: next_char=to_hex(snap_maximum[7:4]);
            8'd60: next_char=to_hex(snap_maximum[3:0]);
            8'd61: next_char=8'h20;
            8'd62: next_char=8'h4c;
            8'd63: next_char=8'h4f;
            8'd64: next_char=8'h53;
            8'd65: next_char=8'h3d;
            8'd66: next_char=to_hex(snap_losses[31:28]);
            8'd67: next_char=to_hex(snap_losses[27:24]);
            8'd68: next_char=to_hex(snap_losses[23:20]);
            8'd69: next_char=to_hex(snap_losses[19:16]);
            8'd70: next_char=to_hex(snap_losses[15:12]);
            8'd71: next_char=to_hex(snap_losses[11:8]);
            8'd72: next_char=to_hex(snap_losses[7:4]);
            8'd73: next_char=to_hex(snap_losses[3:0]);
            8'd74: next_char=8'h0d;
            8'd75: next_char=8'h0a;
            default: next_char=8'h20;
        endcase
    end
    // idle high; shift_word[0] is start bit, then 8 data bits and stop bit.
    assign tx=(tx_state==2)?shift_word[0]:1'b1;
    always @(posedge clk) begin
        if(rst) begin
            period_count<=0;pos<=0;bit_timer<=0;bit_count<=0;
            shift_word<=10'h3ff;tx_state<=0;
            snap_state<=0;snap_reason<=0;snap_locked<=0;snap_attempts<=0;
            snap_adc<=0;snap_dac<=0;snap_target<=0;snap_minimum<=0;snap_maximum<=0;snap_losses<=0;
        end else begin
            case(tx_state)
                0: begin
                    if(period_count>=PERIOD_CLOCKS-1) begin
                        period_count<=0;pos<=0;tx_state<=1;
                        snap_state<=state;snap_reason<=reason;snap_locked<=locked;
                        snap_attempts<=attempts;snap_adc<={{2{adc[13]}},adc};snap_dac<=dac;
                        snap_target<=target;snap_minimum<=minimum;snap_maximum<=maximum;
                        snap_losses<=losses;
                    end else period_count<=period_count+1'b1;
                end
                1: begin
                    shift_word<={1'b1,next_char,1'b0};
                    bit_timer<=0;bit_count<=0;tx_state<=2;
                end
                2: begin
                    if(bit_timer>=BAUD_DIV-1) begin
                        bit_timer<=0;
                        if(bit_count==9) begin
                            if(pos==LENGTH-1) tx_state<=0;
                            else begin pos<=pos+1'b1;tx_state<=1;end
                        end else begin
                            shift_word<={1'b1,shift_word[9:1]};
                            bit_count<=bit_count+1'b1;
                        end
                    end else bit_timer<=bit_timer+1'b1;
                end
                default: tx_state<=0;
            endcase
        end
    end
endmodule
