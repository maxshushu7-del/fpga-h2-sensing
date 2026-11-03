// -----------------------------------------------------------------------------
// sat_accum_stream
//
// Streaming integer accumulator with Q1.7 scaling and per-step saturation.
//
//   On every accepted input (s_valid && s_ready):
//       p = s_x * s_k                      (integer product, exact)
//       r = sign(p) * floor((|p| + 64) / 128)
//           -> round-half-away-from-zero division by 128, zero maps to zero
//       a = clamp16(a + r)                 (-32768 .. 32767, saturates per step)
//       m_y <= a, m_valid <= 1
//
//   The output is a single register stage.  A back-pressured result is held
//   (m_valid/m_y stable) and s_ready drops.  A result may be consumed in the
//   same cycle a replacement is accepted.
//
//   Reset is synchronous, active high, and clears a, m_y and m_valid.
//   No external IP is used.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module sat_accum_stream (
    input  logic                clk,
    input  logic                rst,
    input  logic signed [15:0]  s_x,
    input  logic signed [7:0]   s_k,
    input  logic                s_valid,
    output logic                s_ready,
    output logic signed [15:0]  m_y,
    output logic                m_valid,
    input  logic                m_ready
);

    // ------------------------------------------------------------------
    // Input side: exact product and round-half-away Q1.7 rescale.
    // |p| <= 4194304, so a 24-bit signed product is exact.
    // |r| <= 32768, so a 17-bit signed value is enough.
    // ------------------------------------------------------------------
    logic signed [23:0] prod;
    logic        [23:0] mag;
    logic        [24:0] mag_rnd;
    logic        [15:0] r_mag;
    logic signed [17:0] r;

    assign prod    = s_x * s_k;                       // exact signed product
    assign mag     = prod[23] ? (~prod + 24'd1) : prod; // |p|
    assign mag_rnd = {1'b0, mag} + 25'd64;             // |p| + 64
    assign r_mag   = mag_rnd[22:7];                    // floor((|p|+64)/128), <= 32768
    assign r       = prod[23] ? -$signed({1'b0, r_mag})
                              :  $signed({1'b0, r_mag});

    // ------------------------------------------------------------------
    // Accumulator with per-step saturation.
    // sum fits in 20 signed bits: 32767 + 32768 = 65535.
    // ------------------------------------------------------------------
    logic signed [15:0] a;
    logic signed [19:0] a_ext;
    logic signed [19:0] r_ext;
    logic signed [19:0] sum;
    logic signed [15:0] a_next;

    assign a_ext  = {{4{a[15]}}, a};
    assign r_ext  = {{2{r[17]}}, r};
    assign sum    = a_ext + r_ext;
    assign a_next = (sum >  20'sd32767) ? 16'sh7FFF :
                    (sum < -20'sd32768) ? 16'sh8000 :
                                          sum[15:0];

    // ------------------------------------------------------------------
    // Handshake.  s_ready is purely combinational and is low during reset.
    // ------------------------------------------------------------------
    logic s_accept;
    logic m_fire;

    assign s_ready  = !rst && (!m_valid || m_ready);
    assign s_accept = s_valid && s_ready;
    assign m_fire   = m_valid && m_ready;

    // ------------------------------------------------------------------
    // State and single output register.
    // Accept wins over a same-cycle consume so the replacement result is
    // written immediately (m_valid stays asserted in that case).
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            a       <= 16'sd0;
            m_y     <= 16'sd0;
            m_valid <= 1'b0;
        end else if (s_accept) begin
            a       <= a_next;
            m_y     <= a_next;
            m_valid <= 1'b1;
        end else if (m_fire) begin
            m_valid <= 1'b0;
        end
    end

endmodule
