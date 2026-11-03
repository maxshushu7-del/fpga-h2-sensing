`timescale 1ns/1ps
// Digital boundary unit tests; default SPAN=1024 / STEP=2 / MIN_CONTRAST=24.
// SETTLE_CLOCKS=0 and AVG_LOG2=0 shorten the repeated identical point samples.
// LEGACY_RTL records and checks the unfixed behavior as a control.
module endpoint_case #(parameter FALLING=1, LEGACY=0)(output reg done=0);
reg clk=0,rst=1,arm=0;
always #5 clk=~clk;
reg signed [13:0] adc_sample=0;
wire signed [15:0] dac_code,scan_min,scan_max,min_code,selected_code;
wire servo_enable;
wire [3:0] state,last_reason;
auto_lock_fsm #(.SETTLE_CLOCKS(0),.AVG_LOG2(0)) dut(
.clk(clk),.rst(rst),.arm(arm),.dac_at_goal(1'b1),.adc_valid(arm),.adc_sample(adc_sample),
.servo_valid(1'b0),.servo_delta(16'sd0),.servo_error(16'sd0),.servo_clipped(1'b0),
.dac_code(dac_code),.servo_enable(servo_enable),.state(state),.last_reason(last_reason),
.scan_min(scan_min),.scan_max(scan_max),.min_code(min_code),.selected_code(selected_code));
always @(negedge clk) adc_sample=FALLING ? 3000-($signed(dac_code)+1024) : 952+($signed(dac_code)+1024);
integer cycles;
initial begin
repeat(5) @(negedge clk);rst=0;arm=1;
cycles=0;
while(state!=6 && last_reason==0 && cycles<20000)begin @(negedge clk);cycles=cycles+1;end
$display("ENDPOINT falling=%0d legacy=%0d state=%0d reason=%0d min_code=%0d min=%0d max=%0d selected=%0d servo_enable=%0d",FALLING,LEGACY,state,last_reason,min_code,scan_min,scan_max,selected_code,servo_enable);
if(LEGACY && FALLING)begin
 if(state!==6 || min_code!==16'sd1024 || !servo_enable) $fatal(1,"legacy control did not reproduce known falling-endpoint defect");
 $display("PASS LEGACY_COUNTEREXAMPLE: falling endpoint minimum enters LOCKING");
end else begin
 if(state!==7 || last_reason!==1 || servo_enable || min_code!==(FALLING ? 16'sd1024 : -16'sd1024)) $fatal(1,"endpoint minimum should be rejected");
 $display("PASS ENDPOINT_REJECTION falling=%0d",FALLING);
end
done=1;
end
endmodule

module final_max_case #(parameter LEGACY=0)(output reg done=0);
reg clk=0,rst=1,arm=0;
always #5 clk=~clk;
reg signed [13:0] adc_sample=0;
wire signed [15:0] dac_code,scan_min,scan_max,min_code;
wire [3:0] state,last_reason;
auto_lock_fsm #(.SETTLE_CLOCKS(0),.AVG_LOG2(0)) dut(
.clk(clk),.rst(rst),.arm(arm),.dac_at_goal(1'b1),.adc_valid(arm),.adc_sample(adc_sample),
.servo_valid(1'b0),.servo_delta(16'sd0),.servo_error(16'sd0),.servo_clipped(1'b0),
.dac_code(dac_code),.state(state),.last_reason(last_reason),.scan_min(scan_min),.scan_max(scan_max),.min_code(min_code));
always @(negedge clk) adc_sample=($signed(dac_code)==1024) ? 1090 : ($signed(dac_code)==0 ? 990 : 1000);
integer cycles;
initial begin
repeat(5) @(negedge clk);rst=0;arm=1;
cycles=0;
while(state!=3 && state!=7 && cycles<10000)begin @(negedge clk);cycles=cycles+1;end
$display("FINAL_MAX legacy=%0d state=%0d reason=%0d min_code=%0d min=%0d max=%0d half=%0d",LEGACY,state,last_reason,min_code,scan_min,scan_max,dut.half_level);
if(LEGACY)begin
 if(state!==7 || last_reason!==1) $fatal(1,"legacy final-max control did not show stale contrast rejection");
 $display("PASS LEGACY_COUNTEREXAMPLE: final maximum omitted from contrast decision");
end else begin
 if(state!==3 || last_reason!==0 || min_code!==0 || scan_min!==990 || scan_max!==1090 || dut.half_level!==1040) $fatal(1,"final maximum must contribute to contrast and half-level before FIND_WAIT");
 $display("PASS FINAL_MAX: updated contrast=100 accepted; half_level=(990+1090)/2=1040");
end
done=1;
end
endmodule

module tb_auto_lock_candidate_endpoints;
`ifdef LEGACY_RTL
localparam LEGACY=1;
`else
localparam LEGACY=0;
`endif
wire done_fall,done_rise,done_max;
endpoint_case #(.FALLING(1),.LEGACY(LEGACY)) falling(done_fall);
endpoint_case #(.FALLING(0),.LEGACY(LEGACY)) rising(done_rise);
final_max_case #(.LEGACY(LEGACY)) maximum(done_max);
initial begin wait(done_fall && done_rise && done_max);$display("PASS ENDPOINT_SUITE legacy=%0d production SPAN=1024 STEP=2",LEGACY);$finish;end
initial begin #500000;$fatal(1,"endpoint suite watchdog");end
endmodule
