`timescale 1ns/1ps

// One output register; the running accumulator advances only on input transfer.
module sat_accum_stream (
    input  logic                     clk,
    input  logic                     rst,
    input  logic signed [15:0]       s_x,
    input  logic signed [7:0]        s_k,
    input  logic                     s_valid,
    output logic                     s_ready,
    output logic signed [15:0]       m_y,
    output logic                     m_valid,
    input  logic                     m_ready
);
    logic signed [15:0] accumulator;
    logic signed [23:0] product;
    logic signed [24:0] product_extended;
    logic        [24:0] magnitude;
    logic        [24:0] rounded_magnitude;
    logic signed [17:0] rounded_value;
    logic signed [17:0] next_sum;
    logic signed [15:0] next_accumulator;

    assign s_ready = !rst && (!m_valid || m_ready);

    always_comb begin
        // Widen before taking the absolute value, then round the magnitude.
        product = s_x * s_k;
        product_extended = {product[23], product};
        magnitude = product[23] ? $unsigned(-product_extended)
                                : $unsigned(product_extended);
        rounded_magnitude = (magnitude + 25'd64) >> 7;
        rounded_value = product[23] ? -$signed(rounded_magnitude[17:0])
                                     : $signed(rounded_magnitude[17:0]);
        next_sum = $signed({{2{accumulator[15]}}, accumulator}) + rounded_value;
        if (next_sum > 18'sd32767)
            next_accumulator = 16'sd32767;
        else if (next_sum < -18'sd32768)
            next_accumulator = 16'sh8000;
        else
            next_accumulator = next_sum[15:0];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            accumulator <= 16'sd0;
            m_y <= 16'sd0;
            m_valid <= 1'b0;
        end else if (s_valid && s_ready) begin
            accumulator <= next_accumulator;
            m_y <= next_accumulator;
            m_valid <= 1'b1;
        end else if (m_valid && m_ready) begin
            m_valid <= 1'b0;
        end
    end
endmodule
