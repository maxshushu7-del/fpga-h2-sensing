`timescale 1ns/1ps
// Eight accepted-sample moving average. First sample fills the history to
// avoid a zero-padding startup transient. Bypass still maintains the history.
module error_filter (
    input wire clk, input wire rst, input wire clear,
    input wire filter_enable,
    input wire signed [15:0] sample_in, input wire sample_valid,
    output reg signed [15:0] filtered_out, output reg filtered_valid
);
    reg signed [15:0] history [0:7];
    reg [2:0] pointer;
    reg initialized;
    reg signed [18:0] running_sum;
    wire signed [18:0] new_sample = {{3{sample_in[15]}}, sample_in};
    wire signed [18:0] old_sample = {{3{history[pointer][15]}}, history[pointer]};
    wire signed [18:0] next_sum = running_sum - old_sample + new_sample;
    integer i;
    always @(posedge clk) begin
        if (rst || clear) begin
            filtered_out <= 16'sd0;
            filtered_valid <= 1'b0;
            running_sum <= 19'sd0;
            pointer <= 3'd0;
            initialized <= 1'b0;
            for (i=0; i<8; i=i+1) history[i] <= 16'sd0;
        end else begin
            filtered_valid <= sample_valid;
            if (sample_valid) begin
                if (!initialized) begin
                    for (i=0; i<8; i=i+1) history[i] <= sample_in;
                    running_sum <= new_sample <<< 3;
                    initialized <= 1'b1;
                    filtered_out <= sample_in;
                end else begin
                    history[pointer] <= sample_in;
                    pointer <= pointer + 1'b1;
                    running_sum <= next_sum;
                    if (filter_enable) filtered_out <= next_sum >>> 3;
                    else filtered_out <= sample_in;
                end
            end
        end
    end
endmodule
