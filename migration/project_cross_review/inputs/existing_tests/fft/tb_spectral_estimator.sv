`timescale 1ns / 1ps
module tb_spectral_estimator;
    // Production FFT outputs are 29 bits. A shorter 16-bin test keeps edge
    // cases readable while exercising the production power/sqrt word width.
    localparam integer L=4, W=29, N=1<<L, FS=16000000;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg signed [W-1:0] fft_re=0, fft_im=0;
    reg [L-1:0] fft_bin=0;
    reg fft_valid=0, fft_last=0, frame_bad=0;
    wire strobe, valid, iv;
    wire [L-1:0] peak;
    wire signed [17:0] delta;
    wire signed [31:0] hz;
    wire [2*W:0] pp, np;
    wire baseline_strobe, baseline_valid, baseline_interp;
    wire [L-1:0] baseline_peak;
    wire signed [17:0] baseline_delta;
    wire signed [31:0] baseline_hz;
    wire real_strobe, real_valid;
    integer tests=0;
    integer spectrum_re[0:N-1], spectrum_im[0:N-1];

    spectral_estimator #(.FFT_LOG2(L),.OUT_WIDTH(W),.SAMPLE_RATE_HZ(FS),
        .COMPLEX_INPUT(1),.MIN_PEAK_POWER(64'd100),.PEAK_NOISE_RATIO(16)) dut (
        .clk(clk),.rst_n(rst_n),.fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
        .fft_valid(fft_valid),.fft_last(fft_last),.frame_bad(frame_bad),
        .result_strobe(strobe),.measurement_valid(valid),.peak_bin(peak),
        .bin_offset_q16(delta),.frequency_offset_hz(hz),.peak_power(pp),
        .noise_power(np),.interp_valid(iv));
    spectral_estimator #(.FFT_LOG2(L),.OUT_WIDTH(W),.SAMPLE_RATE_HZ(FS),
        .COMPLEX_INPUT(1),.WINDOW_ENABLE(0),.MIN_PEAK_POWER(64'd100),
        .PEAK_NOISE_RATIO(16)) baseline (
        .clk(clk),.rst_n(rst_n),.fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
        .fft_valid(fft_valid),.fft_last(fft_last),.frame_bad(frame_bad),
        .result_strobe(baseline_strobe),.measurement_valid(baseline_valid),
        .peak_bin(baseline_peak),.bin_offset_q16(baseline_delta),
        .frequency_offset_hz(baseline_hz),.peak_power(),.noise_power(),
        .interp_valid(baseline_interp));
    spectral_estimator #(.FFT_LOG2(L),.OUT_WIDTH(W),.SAMPLE_RATE_HZ(FS),
        .COMPLEX_INPUT(0),.MIN_PEAK_POWER(64'd100),.PEAK_NOISE_RATIO(16)) real_dut (
        .clk(clk),.rst_n(rst_n),.fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
        .fft_valid(fft_valid),.fft_last(fft_last),.frame_bad(frame_bad),
        .result_strobe(real_strobe),.measurement_valid(real_valid),.peak_bin(),
        .bin_offset_q16(),.frequency_offset_hz(),.peak_power(),.noise_power(),
        .interp_valid());

    task clear_spectrum(input integer level);
        integer j;
        begin for(j=0;j<N;j=j+1) begin spectrum_re[j]=level; spectrum_im[j]=0; end end
    endtask
    task hann_peak(input integer center, input integer left, input integer middle,
                   input integer right);
        begin
            spectrum_re[(center+N-1)%N]=left;
            spectrum_re[center]=middle;
            spectrum_re[(center+1)%N]=right;
        end
    endtask
    task reset_all;
        begin
            @(negedge clk); rst_n=0; fft_valid=0; fft_last=0; frame_bad=0;
            repeat(4) @(negedge clk);
            rst_n=1; repeat(2) @(negedge clk);
        end
    endtask
    task send_spectrum(input integer bad, input integer malformed);
        integer j;
        begin
            frame_bad=bad;
            for(j=0;j<N;j=j+1) begin
                @(negedge clk);
                fft_valid=1; fft_bin=(malformed==3 && j==10) ? 9 : j;
                fft_re=spectrum_re[j]; fft_im=spectrum_im[j];
                fft_last=(j==N-1 && malformed!=1) || (malformed==2 && j==7);
                if(malformed==2 && j==7) j=N;
                if(malformed==4 && j%3==2) begin
                    @(negedge clk); fft_valid=0; fft_last=0;
                end
            end
            @(negedge clk); fft_valid=0; fft_last=0;
        end
    endtask
    task wait_result;
        integer cycles;
        begin
            cycles=0;
            while(!strobe && cycles<1000) begin @(negedge clk); cycles=cycles+1; end
            if(!strobe) $fatal(1,"estimator result timeout");
            #1;
        end
    endtask
    task check_result(input integer expected_bin, input integer expected_delta,
                      input integer expected_hz, input integer expected_valid,
                      input integer expected_interp);
        begin
            wait_result();
            if(peak!==expected_bin || delta!==expected_delta || hz!==expected_hz ||
               valid!==expected_valid || iv!==expected_interp)
                $fatal(1,"case %0d: bin=%0d delta=%0d hz=%0d valid=%0d interp=%0d; expected %0d %0d %0d %0d %0d",
                    tests+1,peak,delta,hz,valid,iv,expected_bin,expected_delta,
                    expected_hz,expected_valid,expected_interp);
            tests=tests+1;
            $display("PASS %0d: bin=%0d deltaQ16=%0d hz=%0d valid=%0d interp=%0d noise=%0d",
                tests,peak,delta,hz,valid,iv,np);
            @(negedge clk);
            if(strobe) $fatal(1,"result_strobe must be one clock");
        end
    endtask

    initial begin
        reset_all(); clear_spectrum(1); hann_peak(3,700,2100,1500);
        send_spectrum(0,0); check_result(3,16384,3250000,1,1);
        if(!real_valid) $fatal(1,"real positive-half tone was rejected");
        if(baseline_delta!=0 || baseline_hz!=3000000 || baseline_interp)
            $fatal(1,"rectangular baseline must use the integer bin");

        clear_spectrum(1); hann_peak(0,700,2100,1500);
        send_spectrum(0,0); check_result(0,16384,250000,1,1);

        clear_spectrum(1); hann_peak(0,1500,2100,700);
        send_spectrum(0,0); check_result(0,-16384,-250000,1,1);

        clear_spectrum(1); hann_peak(N-1,1500,2100,700);
        send_spectrum(0,0); check_result(N-1,-16384,-1250000,1,1);

        clear_spectrum(1); hann_peak(N-1,700,2100,1500);
        send_spectrum(0,0); check_result(N-1,16384,-750000,1,1);

        clear_spectrum(0); send_spectrum(0,0); check_result(0,0,0,0,0);
        clear_spectrum(20); send_spectrum(0,0); check_result(0,0,0,0,0);

        clear_spectrum(1); hann_peak(3,2100,2100,700);
        send_spectrum(0,0); check_result(2,0,2000000,1,0);

        clear_spectrum(1); hann_peak(3,700,2100,1500);
        send_spectrum(1,0); check_result(3,16384,3250000,0,0);
        frame_bad=0;

        clear_spectrum(1); hann_peak(3,700,2100,1500);
        send_spectrum(0,1); check_result(3,16384,3250000,0,0);

        clear_spectrum(1); hann_peak(3,700,2100,1500);
        send_spectrum(0,2); check_result(3,16384,3250000,0,0);

        // Signed real/imag products give exact roots 700,2100,1500.
        clear_spectrum(1);
        spectrum_re[2]=420; spectrum_im[2]=-560;
        spectrum_re[3]=1260; spectrum_im[3]=-1680;
        spectrum_re[4]=900; spectrum_im[4]=-1200;
        send_spectrum(0,0); check_result(3,16384,3250000,1,1);
        if(pp!=4410000 || np!=1) $fatal(1,"power or mean floor mismatch");

        clear_spectrum(1); spectrum_re[0]=2100;
        send_spectrum(0,0); check_result(0,0,0,1,1);
        if(real_valid) $fatal(1,"real-mode DC-only frame must not become an AC result");

        clear_spectrum(25000); hann_peak(3,70000000,210000000,150000000);
        send_spectrum(0,0); check_result(3,16384,3250000,1,1);
        if(pp!=59'd44100000000000000 || np!=59'd625000000)
            $fatal(1,"large signed FFT power/sqrt calculation overflowed");

        clear_spectrum(1); hann_peak(3,2,6,4);
        send_spectrum(0,0); check_result(3,14563,3222214,0,1);

        clear_spectrum(1); hann_peak(3,700,2100,1500);
        send_spectrum(0,3); check_result(3,16384,3250000,0,0);

        clear_spectrum(1); hann_peak(3,700,2100,1500);
        send_spectrum(0,4); check_result(3,16384,3250000,1,1);

        // A new full frame before result_strobe must reject the current result.
        clear_spectrum(1); hann_peak(3,700,2100,1500);
        send_spectrum(0,0); send_spectrum(0,0);
        check_result(3,16384,3250000,0,0);

        $display("ALL %0d SPECTRAL ESTIMATOR TESTS PASSED",tests);
        $finish;
    end
endmodule
