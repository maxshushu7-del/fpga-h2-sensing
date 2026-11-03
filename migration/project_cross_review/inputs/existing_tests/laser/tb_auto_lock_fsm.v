`timescale 1ns/1ps
// Stand-alone functional simulation: resonance acquisition, lock, loss/recovery,
// missing resonance. Accelerated timing only; not an AD9122 analog-output model.
module tb_auto_lock_fsm;
 reg clk=0,rst=1,arm=0,adc_valid=0,servo_valid=0,servo_clipped=0;
 reg signed [13:0] adc_sample=0;
 reg signed [15:0] servo_delta=0,servo_error=0;
 wire signed [15:0] dac_code,servo_setpoint,scan_min,scan_max,min_code,selected_code;
 wire dac_valid,adc_scan_enable,servo_enable,reverse_error,servo_clear,locked,ever_locked;
 wire [3:0] state,last_reason;
 wire [7:0] attempts;
 wire [31:0] reacquire_count,samples_seen;
 always #5 clk=~clk;
 reg flat=0,loss=0;
 integer n=0,d,x;
 auto_lock_fsm #(.SPAN(20),.STEP(1),.SETTLE_CLOCKS(2),.AVG_LOG2(1),
     .MIN_CONTRAST(24),.LOCK_TOL(32),.LOSS_TOL(100),
     .STABLE_SAMPLES(3),.LOST_SAMPLES(4),
     .NO_SAMPLE_CLOCKS(30000),.LOCK_TIMEOUT_CLOCKS(10000),.RETRY_CLOCKS(10)) dut (
     .clk(clk),.rst(rst),.arm(arm),.dac_at_goal(1'b1),.adc_valid(adc_valid),.adc_sample(adc_sample),
     .servo_valid(servo_valid),.servo_delta(servo_delta),.servo_error(servo_error),
     .servo_clipped(servo_clipped),.dac_code(dac_code),.dac_valid(dac_valid),
     .adc_scan_enable(adc_scan_enable),.servo_enable(servo_enable),
     .servo_setpoint(servo_setpoint),.reverse_error(reverse_error),
     .servo_clear(servo_clear),.state(state),.locked(locked),
     .ever_locked(ever_locked),.last_reason(last_reason),.attempts(attempts),
     .scan_min(scan_min),.scan_max(scan_max),.min_code(min_code),
     .selected_code(selected_code),.reacquire_count(reacquire_count),
     .samples_seen(samples_seen));
 always @(negedge clk) begin
     adc_valid = arm && (n%3==0);
     if(adc_valid) begin
         d=$signed(dac_code)-3;
         adc_sample=flat ? 14'sd2000 : 2000 - (700*9)/(9+d*d);
     end
     servo_valid=servo_enable && (n%3==0);
     servo_error=loss ? 16'sd500 : 16'sd0;
     n=n+1;
 end
 integer timeout;
 initial begin
     repeat(6) @(posedge clk);rst=0;arm=1;
     timeout=0;
     while(!locked && timeout<4000)begin @(posedge clk);timeout=timeout+1;end
     if(!locked) $fatal(1,"AUTO: did not acquire dip");
     if(!reverse_error || !(scan_min<scan_max) || selected_code>=min_code)
         $fatal(1,"AUTO: wrong chosen slope: min%0d max%0d loc%0d selected%0d",scan_min,scan_max,min_code,selected_code);
     $display("AUTOSCAN acquired setpoint=%0d code=%0d contrast=%0d",servo_setpoint,selected_code,scan_max-scan_min);
     loss=1;
     timeout=0;
     while(reacquire_count==0 && timeout<1000)begin @(posedge clk);timeout=timeout+1;end
     if(reacquire_count==0 || locked) $fatal(1,"AUTO: did not detect loss");
     loss=0;
     $display("AUTO lost and restarted, reason=%0d",last_reason);
     // Confirm re-acquisition with the same scanning path.
     timeout=0;
     while(!locked && timeout<4000)begin @(posedge clk);timeout=timeout+1;end
     if(!locked || attempts<2) $fatal(1,"AUTO: no re-acquisition");
     // Flat light response on following start must be rejected.
     @(negedge clk);arm=0;flat=1;
     repeat(4) @(posedge clk);
     @(negedge clk);arm=1;
     timeout=0;
     while(last_reason!=1 && timeout<4000)begin @(posedge clk);timeout=timeout+1;end
     if(last_reason!=1 || locked) $fatal(1,"AUTO: flat optical signal misidentified as resonance");
     $display("PASS AUTO_FSM auto-acquire, loss/reacquire, flat-signal rejection");
     $finish;
 end
endmodule
