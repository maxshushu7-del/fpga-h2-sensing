`timescale 1ns/1ps
module tb_measurement_improved #(
    parameter integer ALGORITHM_VERSION=1, FFT_LOG2=12, WINDOW_ENABLE=1
);
    localparam integer N=1<<FFT_LOG2, OUT_WIDTH=17+FFT_LOG2;
    reg adc_clk=0,proc_clk=0,rst_n=0,enabled=0,adc_clock_enabled=1;
    always #2 if(adc_clock_enabled) adc_clk=~adc_clk;
    always #5 proc_clk=~proc_clk;
    reg signed [13:0] channel_a=0,channel_b=0;
    wire capture_active,fft_valid,fft_last,result_strobe,measurement_valid,fine_mode,low_mode,protocol_error;
    wire [FFT_LOG2-1:0] capture_address,fft_bin,peak_bin,coarse_bin;
    wire signed [OUT_WIDTH-1:0] fft_re,fft_im;
    wire signed [17:0] bin_offset_q16;
    wire signed [31:0] fine_offset_hz;
    wire [31:0] frequency_hz,sequence_number,clipped_samples;
    wire [2*OUT_WIDTH:0] peak_power,noise_power;
    wire [7:0] result_flags;
    measurement_improved #(.ALGORITHM_VERSION(ALGORITHM_VERSION),.FFT_LOG2(FFT_LOG2),
        .WINDOW_ENABLE(WINDOW_ENABLE),.ADC_CHANNEL(1),.FRAME_GAP_CYCLES(2000),.SIM_IDLE_FFT_PAUSE(1),
        .TIMEOUT_CYCLES(600000)) dut (
        .adc_clk(adc_clk),.adc_rst_n(rst_n),.channel_a(channel_a),.channel_b(channel_b),
        .proc_clk(proc_clk),.proc_rst_n(rst_n),.enabled(enabled),.capture_active(capture_active),
        .capture_address(capture_address),.fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
        .fft_valid(fft_valid),.fft_last(fft_last),.result_strobe(result_strobe),
        .measurement_valid(measurement_valid),.fine_mode(fine_mode),.low_mode(low_mode),.frequency_hz(frequency_hz),
        .sequence_number(sequence_number),.peak_bin(peak_bin),.coarse_bin(coarse_bin),
        .bin_offset_q16(bin_offset_q16),.fine_offset_hz(fine_offset_hz),.peak_power(peak_power),
        .noise_power(noise_power),.result_flags(result_flags),.clipped_samples(clipped_samples),
        .protocol_error(protocol_error));
    integer mode=0,errors=0,results=0,output_count=0,input_count=0;
    integer sample_number=0,value_b,seed=32'h19a35,noise;
    reg passed=0;
    real target_hz=5000000.0,amplitude=200.0,phase,error_hz,tolerance=500.0;
    integer spectrum_fd;
    string spectrum_path;
    // Simulation-only acceleration, NOT an RTL clock gate. Pause the expensive
    // AMD behavioral FFT model ONLY while no FFT transaction is in flight.
    // ADC/proc clocks, CIC, watchdog and all4096 freshly captured samples keep
    // running at their original rates. +FULL_FFT_CLOCK=1 restores the unmodified
    // model clock for cross-checks. Always retain at least one full-clock test.
    integer full_fft_clock=0;
    function integer rounded(input real x); rounded=x>=0 ? $rtoi(x+0.5) : $rtoi(x-0.5); endfunction
    function integer clipped(input integer x); clipped=x>8191 ? 8191 : (x< -8192 ? -8192 : x); endfunction
    task fail(input string reason);
        begin errors++; $display("FAIL: %s",reason); end
    endtask
    always @(negedge adc_clk) if(rst_n) begin
        channel_a=14'sd400; // no tone on the other slot; channel selection matters.
        phase=6.2831853071795864769*target_hz*sample_number/250000000.0;
        seed=(seed*1664525+1013904223);
        noise=((seed>>16)&15)-7;
        if(mode==2) value_b=31;
        else if(mode==3) value_b=31+noise;
        else value_b=rounded(amplitude*$sin(phase)+31.0);
        channel_b=clipped(value_b); sample_number++;
    end
    always @(posedge proc_clk) if(rst_n) begin
        if(!full_fft_clock && dut.configured && dut.state==2 && (fft_valid || dut.sample_valid))
            fail("Attempted to pause an active FFT transaction");
        if(dut.sample_valid && dut.sample_ready) begin
            if(^dut.stream_i===1'bx || ^dut.stream_q===1'bx) fail("Unknown FFT input");
            if(dut.read_address!==input_count[FFT_LOG2-1:0]) fail("Input order / handshake");
            input_count++;
            if(input_count==N) input_count=0;
        end
        if(fft_valid) begin
            if(fft_bin!==output_count[FFT_LOG2-1:0]) fail("FFT bin order");
            if(fft_last!==(output_count==N-1)) fail("FFT TLAST alignment");
            if(spectrum_fd) $fdisplay(spectrum_fd,"%0d,%0d,%0d,%0d,%0d",fine_mode,low_mode,fft_bin,fft_re,fft_im);
            output_count++;
            if(output_count==N) output_count=0;
        end
        if(protocol_error) fail("FFT protocol error");
        if(result_strobe) begin
            results++;
            $display("RTL_RESULT version=%0d n=%0d window=%0d mode=%0d target=%0.3f valid=%0d hz=%0d coarse=%0d peak=%0d delta=%0d fine_hz=%0d power=%0d noise=%0d flags=%02x",
                ALGORITHM_VERSION,N,WINDOW_ENABLE,mode,target_hz,measurement_valid,frequency_hz,
                coarse_bin,peak_bin,bin_offset_q16,fine_offset_hz,peak_power,noise_power,result_flags);
            if(mode==2 || mode==3 || mode==4 || mode==8 ||
               (ALGORITHM_VERSION!=3 && (mode==5 || mode==6 || mode==7))) begin
                if(measurement_valid || frequency_hz!=0) fail("Rejected input emitted trusted frequency");
                if(mode==4 && clipped_samples==0) fail("Clipping flag missing");
            end else begin
                if(!measurement_valid) fail("Clean in-band tone rejected");
                error_hz=frequency_hz-target_hz;
                if(error_hz<0) error_hz=-error_hz;
                if(error_hz>tolerance) fail("Frequency exceeds test tolerance");
                if(ALGORITHM_VERSION==2 && !fine_mode) fail("Zoom result lacks fine frame");
                if(ALGORITHM_VERSION==3 && !fine_mode && !low_mode) fail("Automatic result lacks filtered frame");
                if(ALGORITHM_VERSION==3 && target_hz<350000.0 && !low_mode) fail("Low tone took wrong rate");
                if(ALGORITHM_VERSION==3 && target_hz>500000.0 && !fine_mode) fail("High tone took wrong rate");
            end
            if(sequence_number!=results) fail("Stale/duplicate result sequence");
            if(spectrum_fd) $fclose(spectrum_fd);
            passed=(errors==0);
            $display("TEST_DONE passed=%0d errors=%0d results=%0d",passed,errors,results);
            $finish;
        end
    end
    initial begin
        if($value$plusargs("FULL_FFT_CLOCK=%d",full_fft_clock)) begin end
        $display("SIM_CLOCK_POLICY full_fft_clock=%0d; only idle FFT model may pause, ADC/proc/CIC always full clock",full_fft_clock);
        if($value$plusargs("MODE=%d",mode)) begin end
        if($value$plusargs("FREQ=%f",target_hz)) begin end
        if($value$plusargs("AMPLITUDE=%f",amplitude)) begin end
        if($value$plusargs("TOLERANCE=%f",tolerance)) begin end
        if(mode==1) target_hz=6600000.0;
        if(mode==4) amplitude=12000.0;
        if(mode==5) target_hz=100000.0;
        if(mode==6) target_hz=50000.0;
        if(mode==7) target_hz=5000.0;
        if(WINDOW_ENABLE==0) tolerance=250000000.0/N/2.0+500.0;
        if($value$plusargs("SPECTRUM=%s",spectrum_path)) begin
            spectrum_fd=$fopen(spectrum_path,"w");
            if(!spectrum_fd) fail("Cannot open E-drive spectrum log");
            else $fdisplay(spectrum_fd,"fine_mode,low_mode,bin,fft_re,fft_im");
        end
        #100; @(negedge proc_clk); rst_n=1;
        repeat(30) @(negedge proc_clk); enabled=1;
        #7900000; fail("Simulation timeout"); $finish;
    end
endmodule
