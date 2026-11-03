`timescale 1ns / 1ps
module uart_byte_tx #(
    parameter integer CLOCK_HZ = 100000000,
    parameter integer BAUD_RATE = 115200
) (
    input wire clk, input wire rst_n,
    input wire start, input wire [7:0] data,
    output reg tx, output reg busy, output reg done
);
    localparam integer BIT_CYCLES = CLOCK_HZ / BAUD_RATE;
    reg [31:0] ticks;
    reg [3:0] bit_index;
    reg [9:0] shift_bits;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tx <= 1; busy <= 0; done <= 0; ticks <= 0; bit_index <= 0; shift_bits <= 10'h3ff; end
        else begin
            done <= 0;
            if (!busy && start) begin
                shift_bits <= {1'b1, data, 1'b0};
                tx <= 0;
                busy <= 1;
                ticks <= BIT_CYCLES - 1;
                bit_index <= 0;
            end else if (busy) begin
                if (ticks != 0) ticks <= ticks - 1;
                else if (bit_index == 9) begin tx <= 1; busy <= 0; done <= 1; end
                else begin
                    tx <= shift_bits[1];
                    shift_bits <= {1'b1, shift_bits[9:1]};
                    bit_index <= bit_index + 1;
                    ticks <= BIT_CYCLES - 1;
                end
            end
        end
    end
endmodule
