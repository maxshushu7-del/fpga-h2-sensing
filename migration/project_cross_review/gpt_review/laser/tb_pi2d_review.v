`timescale 1ns/1ps
module tb_pi2d_review;
reg clk=0,rst=1,clear=0,in_valid=0;
always #5 clk=~clk;
reg signed [15:0] err=0,bias=0;
reg signed [31:0] kp=65536,ki=0,kd=0,k2=0;
reg [15:0] lim=100,alim=100;
reg [31:0] ilim=1000,scale=65536;
wire ready,valid,clip,anti,iclip;
wire signed[15:0] value;
wire signed[47:0] integral;
pi2d_controller dut(.clk(clk),.rst(rst),.clear(clear),.error_signal(err),.in_valid(in_valid),.in_ready(ready),.kp(kp),.ki(ki),.kd(kd),.k2(k2),.output_limit(lim),.integral_limit(ilim),.output_bias(bias),.actuator_scale(scale),.actuator_limit(alim),.actuator_invert(1'b0),.control_voltage(value),.control_valid(valid),.integral_value(integral),.output_clipped(clip),.anti_windup(anti),.integral_clipped(iclip));
task reset_state;
begin @(negedge clk);clear=1;in_valid=0; @(negedge clk);clear=0;end
endtask
task sample(input integer e,expected,expected_i,expected_anti);
integer n;
begin
@(negedge clk); while(!ready) @(negedge clk);
err=e;in_valid=1; @(negedge clk);in_valid=0;
n=0;while(!valid && n<20)begin @(negedge clk);n=n+1;end
if(!valid || $signed(value)!=expected || $signed(integral)!=expected_i*65536 || anti!=expected_anti) $fatal(1,"PI expected e=%0d value=%0d I=%0d anti=%0d; actual value=%0d Iq16=%0d anti=%0d",e,expected,expected_i,expected_anti,value,integral,anti);
$display("PASS PI e=%0d value=%0d Iq16=%0d anti=%0d clip=%0d iclip=%0d",e,value,integral,anti,clip,iclip);
end
endtask
integer stage,n;
initial begin
repeat(4) @(negedge clk);rst=0;
sample(50,50,0,0); sample(-50,-50,0,0);sample(101,100,0,0);sample(-101,-100,0,0);
reset_state; kp=0;ki=65536;ilim=15;
sample(10,10,10,0);sample(10,15,15,0);sample(-5,10,10,0);
reset_state;ilim=1000;lim=12;
sample(10,10,10,0);sample(10,10,10,1);sample(-10,0,0,0);
reset_state;lim=100;alim=5;
sample(10,0,0,1);
reset_state;ki=0;k2=65536;alim=100;
sample(10,10,0,0);sample(10,-10,0,0);sample(0,-10,0,0);
for(stage=1;stage<=10;stage=stage+1)begin
reset_state; @(negedge clk);err=13;in_valid=1; @(negedge clk);in_valid=0;
while(dut.state!=stage) @(negedge clk);
clear=1;@(negedge clk);clear=0;#1;
if(valid || integral!=0 || !ready) $fatal(1,"clear failed in stage %0d",stage);
for(n=0;n<15;n=n+1)begin @(negedge clk);if(valid) $fatal(1,"stale output after clear in stage %0d",stage);end
$display("PASS PI clear cancels internal stage=%0d and suppresses stale output",stage);
end
$display("PASS PI2D review numerical/antiwindup checks and clear in all 10 processing stages");$finish;
end
initial begin #100000;$fatal(1,"PI test watchdog");end
endmodule

