`timescale 1ns/1ps
module sat_accum_stream (
    input  logic               clk,
    input  logic               rst,
    input  logic signed [15:0] s_x,
    input  logic signed [7:0]  s_k,
    input  logic               s_valid,
    output logic               s_ready,
    output logic signed [15:0] m_y,
    output logic               m_valid,
    input  logic               m_ready
);
    logic signed [15:0] a;
    logic signed [23:0] product;
    logic signed [24:0] product_wide;
    logic signed [24:0] magnitude;
    logic signed [24:0] rounded_magnitude;
    logic signed [24:0] rounded_step;
    logic signed [25:0] total;
    logic signed [15:0] saturated;

    assign s_ready = !rst && (!m_valid || m_ready);

    always_comb begin
        product = s_x * s_k;
        product_wide = {product[23], product};
        magnitude = product[23] ? -product_wide : product_wide;
        rounded_magnitude = (magnitude + 25'sd64) >>> 7;
        rounded_step = product[23] ? -rounded_magnitude : rounded_magnitude;
        total = {{10{a[15]}}, a} + {rounded_step[24], rounded_step};
        if (total > 26'sd32767)
            saturated = 16'sh7fff;
        else if (total < -26'sd32768)
            saturated = 16'sh8000;
        else
            saturated = total[15:0];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            a <= 16'sd0;
            m_y <= 16'sd0;
            m_valid <= 1'b0;
        end else if (s_valid && s_ready) begin
            a <= saturated;
            m_y <= saturated;
            m_valid <= 1'b1;
        end else if (m_valid && m_ready) begin
            m_valid <= 1'b0;
        end
    end
endmodule
