`timescale 1ns/1ps
// Review-only estimator unit test. Production N=4096, W=29, fine Fs=1MHz.
// Synthetic spectra only: does not claim FFT, DDC or optical verification.
module tb_estimator_production;
  localparam N=4096, L=12, W=29;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, fft_valid=0, fft_last=0, frame_bad=0;
  reg signed [W-1:0] re=0, im=0;
  reg [L-1:0] bin=0;
  wire strobe, valid, interp;
  wire [L-1:0] peak;
  wire signed [17:0] delta;
  wire signed [31:0] hz;
  integer cases=0;
  spectral_estimator #(.FFT_LOG2(L),.OUT_WIDTH(W),.SAMPLE_RATE_HZ(1000000),.COMPLEX_INPUT(1)) dut(
    .clk(clk),.rst_n(rst_n),.fft_re(re),.fft_im(im),.fft_bin(bin),
    .fft_valid(fft_valid),.fft_last(fft_last),.frame_bad(frame_bad),
    .result_strobe(strobe),.measurement_valid(valid),.peak_bin(peak),
    .bin_offset_q16(delta),.frequency_offset_hz(hz),.peak_power(),.noise_power(),.interp_valid(interp));
  task send(input integer center,input integer left,input integer mid,input integer right,input integer malformed);
    integer j;
    begin
      for(j=0;j<N;j=j+1) begin
        @(negedge clk); fft_valid=1; bin=j; im=0;
        re=(j==(center+N-1)%N) ? left : (j==center ? mid : (j==(center+1)%N ? right : 1));
        fft_last=(j==N-1) || (malformed && j==25);
        if(malformed && j==25) j=N;
      end
      @(negedge clk); fft_valid=0; fft_last=0;
    end
  endtask
  task check(input integer expected_peak,input integer expected_delta,input integer expected_hz,input integer expected_valid);
    integer cycles;
    begin
      cycles=0;
      while(!strobe && cycles<20000) begin @(negedge clk); cycles=cycles+1; end
      if(!strobe) $fatal(1,"Timeout");
      if(peak!==expected_peak || delta!==expected_delta || hz!==expected_hz || valid!==expected_valid)
        $fatal(1,"actual peak=%0d delta=%0d hz=%0d valid=%0d expected %0d %0d %0d %0d",peak,delta,hz,valid,expected_peak,expected_delta,expected_hz,expected_valid);
      cases=cases+1;
      $display("PRODUCTION_ESTIMATOR_PASS case=%0d peak=%0d delta=%0d hz=%0d valid=%0d",cases,peak,delta,hz,valid);
      @(negedge clk);
      if(strobe) $fatal(1,"Repeated strobe");
    end
  endtask
  initial begin
    repeat(5) @(negedge clk); rst_n=1;
    send(0,70000,210000,150000,0); check(0,16384,61,1);
    send(0,150000,210000,70000,0); check(0,-16384,-61,1);
    send(4095,150000,210000,70000,0); check(4095,-16384,-305,1);
    send(10,70000,210000,150000,1); check(10,16384,2502,0);
    send(100,150000,210000,70000,0); check(100,-16384,24353,1);
    $display("ALL %0d PRODUCTION-WIDTH 4096-BIN ESTIMATOR UNIT CASES PASSED",cases); $finish;
  end
  initial begin #10000000; $fatal(1,"Global timeout"); end
endmodule
