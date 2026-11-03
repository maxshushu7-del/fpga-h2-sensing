// -----------------------------------------------------------------------------
// sat_accum_stream : streamed saturating accumulator with Q1.7 gain
//
//   p = s_x * s_k                        (exact, 24-bit signed)
//   r = sign(p) * floor((|p|+64)/128)    (round half away from zero)
//   a = clamp16(a + r) on every accepted input (saturate immediately)
//
// Single output register stage, one input handshake per cycle.
//   s_ready = !rst && (!m_valid || m_ready)
//   accept  : m_y <= a, m_valid <= 1  (old result may be consumed in the same cycle)
//   consume : m_valid <= 0 when no input replaces it
//   rst     : a <= 0, m_y <= 0, m_valid <= 0 (cancels any pending result)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module sat_accum_stream (
    input  logic               clk,
    input  logic               rst,        // synchronous, active high
    input  logic signed [15:0] s_x,        // integer input
    input  logic signed [7:0]  s_k,        // Q1.7 gain
    input  logic               s_valid,
    output logic               s_ready,
    output logic signed [15:0] m_y,        // saturated accumulator
    output logic               m_valid,
    input  logic               m_ready
);

    // ---------------------------------------------------------------- registers
    logic signed [16:0] a_q;   // accumulator, held in -32768..32767
    logic signed [15:0] y_q;   // output register
    logic               v_q;   // output valid register

    // ------------------------------------------------------- gain product + round
    // |p| <= 32768*128 = 4194304, so 24 bits hold the product exactly.
    logic signed [23:0] p_w;
    logic        [23:0] mag_w;
    logic        [16:0] mag_r_w;   // floor((|p|+64)/128), <= 32768
    logic signed [17:0] r_w;       // r in -32767..+32768

    assign p_w     = s_x * s_k;
    assign mag_w   = p_w[23] ? (~p_w + 24'd1) : p_w;
    assign mag_r_w = (mag_w + 24'd64) >> 7;
    assign r_w     = p_w[23] ? -$signed({1'b0, mag_r_w})
                             :  $signed({1'b0, mag_r_w});

    // ------------------------------------------------------- accumulate + clamp
    logic signed [17:0] sum_w;
    logic signed [17:0] acc_w;

    assign sum_w = a_q + r_w;                     // range -65536..65535, 18 bits
    assign acc_w = (sum_w >  18'sd32767) ?  18'sd32767 :
                   (sum_w < -18'sd32768) ? -18'sd32768 : sum_w;

    // --------------------------------------------------------------- handshake
    logic accept_w;
    logic consume_w;

    assign s_ready   = ~rst && (~v_q || m_ready);
    assign accept_w  = s_valid && s_ready;
    assign consume_w = v_q && m_ready;

    assign m_y     = y_q;
    assign m_valid = v_q;

    // --------------------------------------------------------------- sequential
    always_ff @(posedge clk) begin
        if (rst) begin
            a_q <= 17'sd0;
            y_q <= 16'sd0;
            v_q <= 1'b0;
        end else if (accept_w) begin
            a_q <= acc_w[16:0];
            y_q <= acc_w[15:0];
            v_q <= 1'b1;
        end else if (consume_w) begin
            v_q <= 1'b0;               // y_q holds
        end
    end

endmodule
