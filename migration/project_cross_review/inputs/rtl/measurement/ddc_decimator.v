`timescale 1ns / 1ps

// Real ADC -> complex baseband, NCO mixing, then CIC filtering BEFORE decimation.
// Default: 250 MS/s / 250 = 1 MS/s complex. Four-stage CIC has finite passband
// droop and limited alias rejection; this is NOT a brick-wall anti-alias filter.
// For a real cosine input A*cos(w*t), desired baseband amplitude is approximately
// A/2 * (250^4 / 2^32) = A/2 * 0.909494702 at zero offset. At +/-100 kHz the CIC
// adds about -0.574 dB droop. An offset 900 kHz aliases to -100 kHz, but the CIC
// attenuates it about 76.34 dB relative to a 100 kHz tone before downsampling.
// This targeted rejection does not bound arbitrary out-of-band interferers.
// Use carrier >=1 MHz, |desired offset| <=100 kHz for the initial zoom mode.
//
// restart captures tuning_word, clears filter/NCO state, and starts a fresh
// stream. First CIC_STAGES decimated results are suppressed. The first valid
// default output is approximately 1257 ADC clocks after restart. settled rises
// with that first valid output and stays high until reset/restart.
// Integrator overflow is intentional modular CIC arithmetic, not an error.
// overflow is sticky OUTPUT SATURATION only, cleared by reset/restart.
// Keep reset/restart synchronous to clk (parent synchronizes its restart toggle).
module ddc_decimator #(
    parameter integer DECIMATION = 250,
    parameter integer CIC_STAGES = 4,
    parameter integer INPUT_WIDTH = 14,
    parameter integer OUTPUT_WIDTH = 16,
    parameter integer PHASE_WIDTH = 32,
    parameter SINE_ROM_FILE = "E:/Codex/FPGA/projects/sensor_integrated_20261018/coefficients/ddc_sine_1024.mem"
) (
    input wire clk,
    input wire rst_n,
    input wire restart,
    input wire [31:0] tuning_word,
    input wire signed [INPUT_WIDTH-1:0] sample,
    output reg signed [OUTPUT_WIDTH-1:0] sample_i,
    output reg signed [OUTPUT_WIDTH-1:0] sample_q,
    output reg sample_valid,
    output reg settled,
    output reg overflow
);
    // Conservative growth: stages*ceil(log2(R)); exactly 32 bits for R=250, N=4.
    localparam integer GROWTH = CIC_STAGES * $clog2(DECIMATION);
    localparam integer CIC_WIDTH = OUTPUT_WIDTH + GROWTH;
    localparam integer RATE_WIDTH = (DECIMATION > 1) ? $clog2(DECIMATION) : 1;
    localparam integer WARM_WIDTH = $clog2(CIC_STAGES + 2);
    localparam integer PRODUCT_WIDTH = INPUT_WIDTH + 16;
    localparam signed [CIC_WIDTH-1:0] OUT_MAX = (64'sd1 << (OUTPUT_WIDTH-1)) - 1;
    localparam signed [CIC_WIDTH-1:0] OUT_MIN = -(64'sd1 << (OUTPUT_WIDTH-1));

    (* rom_style = "block" *) reg signed [15:0] sine_rom [0:1023];
    initial begin
        $readmemh(SINE_ROM_FILE, sine_rom);
    end

    reg [PHASE_WIDTH-1:0] phase_accumulator;
    reg [PHASE_WIDTH-1:0] tuning_latched;
    wire [9:0] phase_address = phase_accumulator[PHASE_WIDTH-1 -: 10];
    wire [9:0] cosine_address = phase_address + 10'd256;
    reg signed [15:0] sine_value, cosine_value;
    reg signed [INPUT_WIDTH-1:0] sample_delayed;
    reg signed [PRODUCT_WIDTH-1:0] product_i, product_q;
    reg signed [OUTPUT_WIDTH-1:0] mixed_i, mixed_q;
    reg [2:0] mixer_valid;

    reg signed [CIC_WIDTH-1:0] integrator_i [0:CIC_STAGES-1];
    reg signed [CIC_WIDTH-1:0] integrator_q [0:CIC_STAGES-1];
    reg signed [CIC_WIDTH-1:0] comb_delay_i [0:CIC_STAGES-1];
    reg signed [CIC_WIDTH-1:0] comb_delay_q [0:CIC_STAGES-1];
    reg signed [CIC_WIDTH-1:0] comb_i [0:CIC_STAGES-1];
    reg signed [CIC_WIDTH-1:0] comb_q [0:CIC_STAGES-1];
    reg [CIC_STAGES-1:0] comb_valid;
    reg [CIC_STAGES-1:0] comb_settled;
    reg [RATE_WIDTH-1:0] rate_count;
    reg [WARM_WIDTH-1:0] warm_count;

    wire signed [CIC_WIDTH-1:0] mixed_i_extended =
        {{(CIC_WIDTH-OUTPUT_WIDTH){mixed_i[OUTPUT_WIDTH-1]}}, mixed_i};
    wire signed [CIC_WIDTH-1:0] mixed_q_extended =
        {{(CIC_WIDTH-OUTPUT_WIDTH){mixed_q[OUTPUT_WIDTH-1]}}, mixed_q};
    wire signed [CIC_WIDTH-1:0] scaled_i = $signed(comb_i[CIC_STAGES-1]) >>> GROWTH;
    wire signed [CIC_WIDTH-1:0] scaled_q = $signed(comb_q[CIC_STAGES-1]) >>> GROWTH;
    integer stage;

    always @(posedge clk) begin
        if (!rst_n || restart) begin
            phase_accumulator <= 0;
            tuning_latched <= tuning_word;
            sine_value <= 0;
            cosine_value <= 0;
            sample_delayed <= 0;
            product_i <= 0;
            product_q <= 0;
            mixed_i <= 0;
            mixed_q <= 0;
            mixer_valid <= 0;
            rate_count <= 0;
            warm_count <= 0;
            comb_valid <= 0;
            comb_settled <= 0;
            sample_i <= 0;
            sample_q <= 0;
            sample_valid <= 0;
            settled <= 0;
            overflow <= 0;
            for (stage = 0; stage < CIC_STAGES; stage = stage + 1) begin
                integrator_i[stage] <= 0;
                integrator_q[stage] <= 0;
                comb_delay_i[stage] <= 0;
                comb_delay_q[stage] <= 0;
                comb_i[stage] <= 0;
                comb_q[stage] <= 0;
            end
        end else begin
            phase_accumulator <= phase_accumulator + tuning_latched;
            sine_value <= sine_rom[phase_address];
            cosine_value <= sine_rom[cosine_address];
            sample_delayed <= sample;
            product_i <= sample_delayed * cosine_value;
            // x * exp(-j*phase): a positive input offset rotates positive I+jQ.
            product_q <= -(sample_delayed * sine_value);
            mixed_i <= $signed(product_i) >>> 15;
            mixed_q <= $signed(product_q) >>> 15;
            mixer_valid <= {mixer_valid[1:0], 1'b1};

            sample_valid <= 0;
            comb_valid[0] <= 0;
            comb_settled[0] <= 0;
            for (stage = 1; stage < CIC_STAGES; stage = stage + 1) begin
                comb_valid[stage] <= comb_valid[stage-1];
                comb_settled[stage] <= comb_settled[stage-1];
                if (comb_valid[stage-1]) begin
                    comb_i[stage] <= comb_i[stage-1] - comb_delay_i[stage];
                    comb_q[stage] <= comb_q[stage-1] - comb_delay_q[stage];
                    comb_delay_i[stage] <= comb_i[stage-1];
                    comb_delay_q[stage] <= comb_q[stage-1];
                end
            end

            if (mixer_valid[2]) begin
                integrator_i[0] <= integrator_i[0] + mixed_i_extended;
                integrator_q[0] <= integrator_q[0] + mixed_q_extended;
                // Pipelining between integrator stages adds a fixed delay only.
                for (stage = 1; stage < CIC_STAGES; stage = stage + 1) begin
                    integrator_i[stage] <= integrator_i[stage] + integrator_i[stage-1];
                    integrator_q[stage] <= integrator_q[stage] + integrator_q[stage-1];
                end
                if (rate_count == DECIMATION-1) begin
                    rate_count <= 0;
                    comb_i[0] <= integrator_i[CIC_STAGES-1] - comb_delay_i[0];
                    comb_q[0] <= integrator_q[CIC_STAGES-1] - comb_delay_q[0];
                    comb_delay_i[0] <= integrator_i[CIC_STAGES-1];
                    comb_delay_q[0] <= integrator_q[CIC_STAGES-1];
                    comb_valid[0] <= 1;
                    comb_settled[0] <= (warm_count >= CIC_STAGES);
                    if (warm_count < CIC_STAGES) warm_count <= warm_count + 1'b1;
                end else rate_count <= rate_count + 1'b1;
            end

            if (comb_valid[CIC_STAGES-1] && comb_settled[CIC_STAGES-1]) begin
                sample_valid <= 1;
                settled <= 1;
                if (scaled_i > OUT_MAX) begin
                    sample_i <= OUT_MAX[OUTPUT_WIDTH-1:0];
                    overflow <= 1;
                end else if (scaled_i < OUT_MIN) begin
                    sample_i <= OUT_MIN[OUTPUT_WIDTH-1:0];
                    overflow <= 1;
                end else sample_i <= scaled_i[OUTPUT_WIDTH-1:0];
                if (scaled_q > OUT_MAX) begin
                    sample_q <= OUT_MAX[OUTPUT_WIDTH-1:0];
                    overflow <= 1;
                end else if (scaled_q < OUT_MIN) begin
                    sample_q <= OUT_MIN[OUTPUT_WIDTH-1:0];
                    overflow <= 1;
                end else sample_q <= scaled_q[OUTPUT_WIDTH-1:0];
            end
        end
    end
endmodule
