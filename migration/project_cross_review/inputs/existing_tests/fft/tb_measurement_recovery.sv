`timescale 1ns/1ps
// Automatic v3 chain + AMD FFT model; pause only the idle FFT model in simulation.
// Deliberately changes frequency between frames and across ADC-clock loss to
// prove that neither old RAM nor a held old peak becomes a fresh valid result.
module tb_measurement_recovery;
    localparam integer FFT_LOG2=12, N=1<<FFT_LOG2, OUT_WIDTH=17+FFT_LOG2;
    localparam integer TIMEOUT_CYCLES=600000;
    reg adc_clk=0, proc_clk=0, rst_n=0, enabled=0, adc_clock_enabled=1;
    always #2 if(adc_clock_enabled) adc_clk=~adc_clk;
    always #5 proc_clk=~proc_clk;
    reg signed [13:0] channel_a=0, channel_b=0;
    wire capture_active, fft_valid, fft_last, result_strobe;
    wire measurement_valid, fine_mode, low_mode, protocol_error;
    wire [FFT_LOG2-1:0] capture_address, fft_bin, peak_bin, coarse_bin;
    wire signed [OUT_WIDTH-1:0] fft_re, fft_im;
    wire signed [17:0] bin_offset_q16;
    wire signed [31:0] fine_offset_hz;
    wire [31:0] frequency_hz, sequence_number, clipped_samples;
    wire [2*OUT_WIDTH:0] peak_power, noise_power;
    wire [7:0] result_flags;
    integer sample_number=0, result_count=0, timeout_count=0;
    integer input_count=0, output_count=0, input_frames=0, output_frames=0;
    integer results_fd;
    real target_hz=5000.0, phase;
    reg passed=0;

    measurement_improved #(.ALGORITHM_VERSION(3),.FFT_LOG2(FFT_LOG2),.SIM_IDLE_FFT_PAUSE(1),
        .WINDOW_ENABLE(1),.ADC_CHANNEL(1),.FRAME_GAP_CYCLES(500),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut (
        .adc_clk(adc_clk),.adc_rst_n(rst_n),.channel_a(channel_a),.channel_b(channel_b),
        .proc_clk(proc_clk),.proc_rst_n(rst_n),.enabled(enabled),
        .capture_active(capture_active),.capture_address(capture_address),
        .fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
        .fft_valid(fft_valid),.fft_last(fft_last),.result_strobe(result_strobe),
        .measurement_valid(measurement_valid),.fine_mode(fine_mode),.low_mode(low_mode),
        .frequency_hz(frequency_hz),.sequence_number(sequence_number),
        .peak_bin(peak_bin),.coarse_bin(coarse_bin),.bin_offset_q16(bin_offset_q16),
        .fine_offset_hz(fine_offset_hz),.peak_power(peak_power),.noise_power(noise_power),
        .result_flags(result_flags),.clipped_samples(clipped_samples),
        .protocol_error(protocol_error));

    function integer rounded(input real value);
        rounded=value>=0 ? $rtoi(value+0.5) : $rtoi(value-0.5);
    endfunction
    always @(negedge adc_clk) if(rst_n) begin
        phase=6.2831853071795864769*target_hz*sample_number/250000000.0;
        channel_a=14'sd400;
        channel_b=rounded(200.0*$sin(phase)+31.0);
        sample_number=sample_number+1;
    end

    // Inspect input/output transfers only on clock edges, before NBA updates.
    always @(posedge proc_clk) if(rst_n) begin
        if(dut.sample_valid && dut.sample_ready) begin
            if(^dut.stream_i===1'bx || ^dut.stream_q===1'bx)
                $fatal(1,"Unknown FFT input after capture/recovery");
            if(dut.read_address!==input_count[FFT_LOG2-1:0])
                $fatal(1,"Input address out of sequence");
            input_count=input_count+1;
            if(input_count==N) begin input_count=0; input_frames=input_frames+1; end
        end
        if(fft_valid) begin
            if(fft_bin!==output_count[FFT_LOG2-1:0])
                $fatal(1,"FFT bin out of sequence");
            if(fft_last!==(output_count==N-1))
                $fatal(1,"FFT TLAST mismatch");
            output_count=output_count+1;
            if(output_count==N) begin output_count=0; output_frames=output_frames+1; end
        end
        if(protocol_error) $fatal(1,"FFT protocol error");
        #1;
        if(result_strobe) begin
            result_count=result_count+1;
            if(sequence_number!==result_count)
                $fatal(1,"Stale, duplicate, or skipped sequence: %0d expected %0d",
                    sequence_number,result_count);
            if(result_flags[4]) timeout_count=timeout_count+1;
            $display("RECOVERY_RESULT seq=%0d valid=%0d hz=%0d target=%0.0f flags=%02x input_frames=%0d output_frames=%0d",
                sequence_number,measurement_valid,frequency_hz,target_hz,
                result_flags,input_frames,output_frames);
            $fdisplay(results_fd,"%0t,%0d,%0d,%0d,%0.0f,%02x,%0d,%0d",
                $time,sequence_number,measurement_valid,frequency_hz,target_hz,
                result_flags,input_frames,output_frames);
        end
    end

    task expect_result(input integer expected_sequence, input integer expected_valid,
                       input real expected_frequency, input integer expected_timeout);
        integer cycles;
        real difference;
        begin
            cycles=0;
            while((!result_strobe || sequence_number!=expected_sequence) && cycles<2500000) begin
                @(negedge proc_clk); cycles=cycles+1;
            end
            if(cycles==2500000) $fatal(1,"Waited too long for sequence %0d",expected_sequence);
            if(measurement_valid!==expected_valid)
                $fatal(1,"Result %0d valid=%0d expected=%0d",expected_sequence,measurement_valid,expected_valid);
            if(result_flags[4]!==expected_timeout)
                $fatal(1,"Result %0d timeout flag wrong: %02x",expected_sequence,result_flags);
            if(expected_valid) begin
                difference=frequency_hz-expected_frequency;
                if(difference<0) difference=-difference;
                if(difference>500.0)
                    $fatal(1,"Result %0d frequency %0d differs from fresh input %0.0f",
                        expected_sequence,frequency_hz,expected_frequency);
                if(clipped_samples!=0 || (!fine_mode && !low_mode))
                    $fatal(1,"Unexpected clipping or fine-mode flag");
            end else if(frequency_hz!=0)
                $fatal(1,"Timeout published old frequency as nonzero output");
            @(negedge proc_clk);
            if(result_strobe) $fatal(1,"Result strobe was longer than one clock");
        end
    endtask

    initial begin
        results_fd=$fopen("E:/Codex/FPGA/projects/adc_fft_tracking_20261014/verification/recovery/results.csv","w");
        if(!results_fd) $fatal(1,"Cannot open recovery result log on E:");
        $fdisplay(results_fd,"time_ps,sequence,valid,frequency_hz,target_hz,flags,input_frames,output_frames");
        #100; @(negedge proc_clk); rst_n=1;
        repeat(30) @(negedge proc_clk); enabled=1;

        expect_result(1,1,5000.0,0);
        target_hz=1000000.0;
        expect_result(2,1,1000000.0,0);

        // The third raw coarse FFT completes, then stop partway through the
        // third LOW-RATE capture. Never let partial low RAM become a fresh FFT.
        target_hz=100000.0;
        wait(capture_active && low_mode && capture_address>=256);
        @(negedge adc_clk); adc_clock_enabled=0;
        $display("ADC_CLOCK_STOPPED at %0t capture_address=%0d",$time,capture_address);
        expect_result(3,0,0.0,1);
        if(timeout_count!=1 || input_frames!=5 || output_frames!=5)
            $fatal(1,"Stalled capture leaked into FFT or timeout count wrong");

        // Stay stopped for another timeout period: exactly ONE invalid result,
        // no continuous retries and no held old peak published as a new result.
        repeat(TIMEOUT_CYCLES+1000) @(negedge proc_clk);
        if(sequence_number!=3 || result_count!=3 || timeout_count!=1 || measurement_valid || frequency_hz!=0)
            $fatal(1,"Clock-off recovery state repeated results or retained a trusted old result");

        target_hz=50000.0; sample_number=0;
        adc_clock_enabled=1;
        $display("ADC_CLOCK_RESTARTED at %0t fresh_target=50kHz",$time);
        expect_result(4,1,50000.0,0);
        if(input_frames!=7 || output_frames!=7)
            $fatal(1,"Recovery did not use a complete newly captured FFT frame");
        target_hz=25000000.0;
        expect_result(5,1,25000000.0,0);
        if(result_count!=5 || timeout_count!=1 || input_frames!=9 || output_frames!=9)
            $fatal(1,"Continuous recovery-frame accounting mismatch");
        passed=1;
        $display("RECOVERY_TEST_PASSED results=5 valid=4 timeout=1 complete_fft_frames=9");
        $fclose(results_fd); $finish;
    end

    initial begin
        #40000000;
        $fatal(1,"Recovery regression global timeout");
    end
endmodule
