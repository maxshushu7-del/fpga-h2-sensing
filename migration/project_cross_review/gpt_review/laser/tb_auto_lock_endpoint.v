`timescale 1ns/1ps
// Diagnostic unit test. Production SPAN=1024 and STEP=2 retained;
// only settle/averaging timing shortened. No DUT modifications or forces.
module tb_auto_lock_endpoint;
reg clk=0,rst=1,arm=0;
always #5 clk=~clk;
reg signed [13:0] adc_sample=0;
wire signed [15:0] dac_code,servo_setpoint,scan_min,scan_max,min_code,selected_code;
wire dac_valid,adc_scan_enable,servo_enable,reverse_error,servo_clear,locked,ever_locked;
wire [3:0] state,last_reason;
wire [7:0] attempts;
wire [31:0] reacquire_count,samples_seen;
auto_lock_fsm #(.SETTLE_CLOCKS(0),.AVG_LOG2(0),.NO_SAMPLE_CLOCKS(1000000)) dut(
.clk(clk),.rst(rst),.arm(arm),.dac_at_goal(1'b1),.adc_valid(arm),.adc_sample(adc_sample),
.servo_valid(1'b0),.servo_delta(16'sd0),.servo_error(16'sd0),.servo_clipped(1'b0),
.dac_code(dac_code),.dac_valid(dac_valid),.adc_scan_enable(adc_scan_enable),
.servo_enable(servo_enable),.servo_setpoint(servo_setpoint),.reverse_error(reverse_error),
.servo_clear(servo_clear),.state(state),.locked(locked),.ever_locked(ever_locked),
.last_reason(last_reason),.attempts(attempts),.scan_min(scan_min),.scan_max(scan_max),
.min_code(min_code),.selected_code(selected_code),.reacquire_count(reacquire_count),.samples_seen(samples_seen));
always @(negedge clk) adc_sample=3000-($signed(dac_code)+1024);
always @(posedge clk) if(!rst && state==2 && dac_code==1024)
 $display("FINAL_SWEEP t=%0t sample=%0d old_scan_min=%0d old_min_code=%0d old_contrast=%0d",$time,adc_sample,scan_min,min_code,$signed(scan_max)-$signed(scan_min));
integer cycles;
initial begin
repeat(5) @(negedge clk);rst=0;arm=1;
cycles=0;
while(state!=6 && last_reason==0 && cycles<20000)begin @(negedge clk);cycles=cycles+1;end
$display("RESULT state=%0d reason=%0d min_code=%0d scan_min=%0d scan_max=%0d selected_code=%0d setpoint=%0d servo_enable=%0d",state,last_reason,min_code,scan_min,scan_max,selected_code,servo_setpoint,servo_enable);
if(state==6 && min_code==1024 && servo_enable) $display("REPRODUCED: monotonic decreasing response with positive-edge minimum was accepted into LOCKING; expected RETRY_WAIT reason=1.");
else $fatal(1,"Did not reproduce endpoint omission");
$finish;
end
endmodule
