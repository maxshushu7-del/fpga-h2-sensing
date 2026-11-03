`timescale 1ns/1ps
// Feed full natural-order FFT output frames to the unchanged production estimator.
// This is a spectral-estimator boundary test, not an FFT or DDC test.
module tb_spectral_estimator_4096;
 localparam integer L=12,W=29,N=4096;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,fft_valid=0,fft_last=0,frame_bad=0;
 reg signed [W-1:0] fft_re=0,fft_im=0;
 reg [L-1:0] fft_bin=0;
 wire strobe,valid,iv,real_strobe,real_valid,real_iv;
 wire [L-1:0] peak,real_peak;
 wire signed [17:0] delta,real_delta;
 wire signed [31:0] hz,real_hz;
 wire [2*W:0] pp,np;
 integer spectrum[0:N-1];
 integer tests=0,frames=0,valid_beats=0;
 spectral_estimator #(.FFT_LOG2(L),.OUT_WIDTH(W),.SAMPLE_RATE_HZ(1000000),
 .COMPLEX_INPUT(1)) dut(.clk(clk),.rst_n(rst_n),.fft_re(fft_re),.fft_im(fft_im),
 .fft_bin(fft_bin),.fft_valid(fft_valid),.fft_last(fft_last),.frame_bad(frame_bad),
 .result_strobe(strobe),.measurement_valid(valid),.peak_bin(peak),.bin_offset_q16(delta),
 .frequency_offset_hz(hz),.peak_power(pp),.noise_power(np),.interp_valid(iv));
 spectral_estimator #(.FFT_LOG2(L),.OUT_WIDTH(W),.SAMPLE_RATE_HZ(250000000)) coarse(
 .clk(clk),.rst_n(rst_n),.fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
 .fft_valid(fft_valid),.fft_last(fft_last),.frame_bad(frame_bad),
 .result_strobe(real_strobe),.measurement_valid(real_valid),.peak_bin(real_peak),
 .bin_offset_q16(real_delta),.frequency_offset_hz(real_hz),.peak_power(),.noise_power(),
 .interp_valid(real_iv));
 task clear(input integer level);
  integer j; begin for(j=0;j<N;j=j+1)spectrum[j]=level; end
 endtask
 task hann(input integer center,input integer left,input integer middle,input integer right);
  begin spectrum[(center+N-1)%N]=left;spectrum[center]=middle;spectrum[(center+1)%N]=right;end
 endtask
 // malformed: 0 clean,1 missing TLAST,2 early TLAST,3 repeated bin,4 input gaps.
 task send(input integer bad,input integer malformed);
  integer j; begin
   frame_bad=bad;frames=frames+1;
   for(j=0;j<N;j=j+1)begin
    @(negedge clk);fft_valid=1;fft_bin=(malformed==3 && j==10)?9:j;
    fft_re=spectrum[j];fft_im=0;
    fft_last=(j==N-1 && malformed!=1)||(malformed==2 && j==2047);
    valid_beats=valid_beats+1;
    if(malformed==2 && j==2047)j=N;
    if(malformed==4 && j%17==16)begin @(negedge clk);fft_valid=0;fft_last=0;end
   end
   @(negedge clk);fft_valid=0;fft_last=0;frame_bad=0;
  end
 endtask
 task check(input string label,input integer eb,input integer ed,input integer eh,input integer ev,input integer ei);
  integer cycles;begin
   cycles=0;
   while(!strobe && cycles<10000)begin @(negedge clk);cycles=cycles+1;end
   if(!strobe)$fatal(1,"4096 timeout case %s",label);
   #1;
   if(peak!==eb || delta!==ed || hz!==eh || valid!==ev || iv!==ei)
    $fatal(1,"4096 %s got bin=%0d delta=%0d hz=%0d valid=%0d interp=%0d expected %0d %0d %0d %0d %0d",label,peak,delta,hz,valid,iv,eb,ed,eh,ev,ei);
   tests=tests+1;
   $display("PASS4096 %0d %s bin=%0d deltaQ16=%0d hz=%0d valid=%0d interp=%0d power=%0d noise=%0d latency=%0d",tests,label,peak,delta,hz,valid,iv,pp,np,cycles);
   @(negedge clk);if(strobe)$fatal(1,"4096 non-single-cycle strobe");
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  clear(100);hann(123,70000,210000,150000);send(0,0);check("positive fractional",123,16384,30090,1,1);
  if(real_valid!==1 || real_peak!==123 || real_hz!==7522583)$fatal(1,"4096 real coarse positive mismatch %0d",real_hz);
  clear(100);hann(N-1,150000,210000,70000);send(0,0);check("negative wrapped",N-1,-16384,-305,1,1);
  clear(100);hann(0,70000,210000,150000);send(0,0);check("DC plus quarter bin",0,16384,61,1,1);
  clear(100);hann(0,150000,210000,70000);send(0,0);check("DC minus quarter bin",0,-16384,-61,1,1);
  clear(100);hann(0,70000,210000,70000);send(0,0);check("complex DC",0,0,0,1,1);
  clear(0);spectrum[0]=210000;send(0,0);check("DC only",0,0,0,1,1);
  if(real_valid!==0)$fatal(1,"4096 real-mode DC rejection failed");
  clear(100);hann(2048,70000,210000,70000);send(0,0);check("signed Nyquist",2048,0,-500000,1,1);
  clear(100);hann(123,70000,210000,150000);send(0,1);check("missing TLAST",123,16384,30090,0,0);
  send(0,0);check("recover after missing TLAST",123,16384,30090,1,1);
  send(0,2);check("early TLAST",123,16384,30090,0,0);
  send(0,0);check("recover after early TLAST",123,16384,30090,1,1);
  send(0,3);check("bin order error",123,16384,30090,0,0);
  send(0,0);check("recover after bin error",123,16384,30090,1,1);
  send(1,0);check("frame bad",123,16384,30090,0,0);
  send(0,0);check("recover after frame bad",123,16384,30090,1,1);
  clear(0);send(0,0);check("zero invalid",0,0,0,0,0);
  clear(100);hann(123,70000,210000,150000);send(0,4);check("gapped valid recovery",123,16384,30090,1,1);
  send(0,0);send(0,0);check("overlapping frame contract error",123,16384,30090,0,0);
  send(0,0);check("recover after overlap",123,16384,30090,1,1);
  $display("ALL %0d PRODUCTION 4096 SPECTRAL CASES PASSED; frames=%0d valid_input_beats=%0d",tests,frames,valid_beats);
  $finish;
 end
endmodule
