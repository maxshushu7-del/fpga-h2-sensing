`timescale 1ns / 1ps
module tb_ddc_decimator;
    localparam real FS = 250000000.0;
    localparam real PI = 3.14159265358979323846;
    localparam integer R = 250;
    localparam integer POINTS = 200;
    reg clk = 0;
    always #2 clk = ~clk;
    reg rst_n = 0, restart = 0;
    reg [31:0] tuning_word = 32'd85899346; // nearest 5 MHz at 250 MS/s
    reg signed [13:0] sample = 0;
    wire signed [15:0] sample_i, sample_q;
    wire sample_valid, settled, overflow;
    ddc_decimator dut (
        .clk(clk), .rst_n(rst_n), .restart(restart), .tuning_word(tuning_word),
        .sample(sample), .sample_i(sample_i), .sample_q(sample_q),
        .sample_valid(sample_valid), .settled(settled), .overflow(overflow)
    );

    real input_frequency = 5000000.0;
    real amplitude = 3000.0;
    integer input_index = 0;
    integer adc_cycle = 0;
    integer cycle_at_restart = 0;
    integer last_valid_cycle = -1;
    integer total_valid = 0;
    integer first_valid_latency = 0;
    integer stream_file;
    reg stimulus_active = 0;

    // Stimulus and NCO both start with sample zero on the first post-restart edge.
    always @(negedge clk) begin
        if (stimulus_active && !restart) begin
            sample = $rtoi(amplitude * $cos(2.0*PI*input_frequency*input_index/FS));
            input_index = input_index + 1;
        end else sample = 0;
    end
    always @(posedge clk) begin
        adc_cycle = adc_cycle + 1;
        if (restart || !rst_n) begin
            cycle_at_restart = adc_cycle;
            last_valid_cycle = -1;
            total_valid = 0;
        end
        #0.1;
        if (restart || !rst_n) begin
            if (sample_valid || settled || overflow) $fatal(1, "Restart did not flush status");
        end else if (sample_valid) begin
            if (!settled) $fatal(1, "Output valid before settled");
            if (overflow) $fatal(1, "Unexpected output saturation");
            if (last_valid_cycle < 0) begin
                first_valid_latency = adc_cycle - cycle_at_restart;
                if (first_valid_latency < 1000 || first_valid_latency > 1300)
                    $fatal(1, "Bad first-valid latency %0d", first_valid_latency);
            end else if (adc_cycle - last_valid_cycle != R)
                $fatal(1, "Output interval %0d, expected %0d", adc_cycle-last_valid_cycle, R);
            last_valid_cycle = adc_cycle;
            total_valid = total_valid + 1;
            $fdisplay(stream_file, "%0.0f,%0d,%0d,%0d,%0d", input_frequency,
                adc_cycle, $signed(sample_i), $signed(sample_q), settled);
        end else if (settled && total_valid == 0) $fatal(1, "Settled precedes first valid");
    end

    function automatic real expected_gain(input real offset_hz);
        real ratio;
        begin
            if (offset_hz == 0.0) ratio = 250.0;
            else ratio = $sin(PI*250.0*offset_hz/FS) / $sin(PI*offset_hz/FS);
            expected_gain = (ratio*ratio*ratio*ratio)/4294967296.0;
        end
    endfunction

    task automatic test_tone(input real offset_hz, input real demod_offset_hz,
        input real maximum_error, input integer weak_tone);
        integer k, skipped;
        real phase, corr_re, corr_im, measured, expected;
        begin
            @(negedge clk); #0.2;
            stimulus_active = 0;
            restart = 1;
            input_index = 0;
            input_frequency = 5000000.0 + offset_hz;
            tuning_word = 32'd85899346;
            @(negedge clk); #0.2;
            restart = 0;
            stimulus_active = 1;
            // Capture settling and then a full integer number of offset cycles.
            skipped = 0;
            while (skipped < 8) begin
                @(posedge clk); #0.2;
                if (sample_valid) skipped = skipped + 1;
            end
            corr_re = 0.0;
            corr_im = 0.0;
            k = 0;
            while (k < POINTS) begin
                @(posedge clk); #0.2;
                if (sample_valid) begin
                    phase = 2.0*PI*demod_offset_hz*k/(FS/R);
                    corr_re = corr_re + $signed(sample_i)*$cos(phase) + $signed(sample_q)*$sin(phase);
                    corr_im = corr_im + $signed(sample_q)*$cos(phase) - $signed(sample_i)*$sin(phase);
                    k = k + 1;
                    // An uncommitted tuning change MUST NOT alter this frame's NCO.
                    if (k == 100) tuning_word = 32'd103079215; // 6 MHz, no restart
                end
            end
            measured = $sqrt(corr_re*corr_re + corr_im*corr_im)/POINTS;
            expected = amplitude*0.5*expected_gain(offset_hz);
            if (weak_tone) begin
                if (measured > maximum_error) $fatal(1, "Out-of-band alias not rejected: %f", measured);
            end else if ((measured-expected > maximum_error) || (expected-measured > maximum_error))
                $fatal(1, "Gain/complex-sign error at %f Hz: actual=%f expected=%f", offset_hz, measured, expected);
            $display("PASS offset=%0.0f Hz, complex amplitude=%0.3f, expected=%0.3f, first-valid=%0d clocks",
                offset_hz, measured, expected, first_valid_latency);
        end
    endtask

    initial begin
        stream_file = $fopen("E:/Codex/FPGA/projects/adc_fft_tracking_20261014/verification/ddc_stream.csv", "w");
        if (!stream_file) $fatal(1, "Cannot create E-drive DDC verification stream");
        $fdisplay(stream_file, "input_hz,adc_cycle,i,q,settled");
        repeat (4) @(negedge clk);
        #0.2; rst_n = 1;
        test_tone(0.0, 0.0, 4.0, 0);
        test_tone(50000.0, 50000.0, 4.0, 0);
        test_tone(-50000.0, -50000.0, 4.0, 0);
        test_tone(100000.0, 100000.0, 4.0, 0);
        test_tone(-100000.0, -100000.0, 4.0, 0);
        test_tone(900000.0, -100000.0, 2.0, 1);
        $fclose(stream_file);
        $display("PASS tb_ddc_decimator: DC, positive/negative offsets, CIC droop, 900 kHz alias rejection, restart, settling, exact rate, held tuning.");
        $finish;
    end
    initial begin
        #3000000;
        $fatal(1, "DDC simulation timeout");
    end
endmodule
