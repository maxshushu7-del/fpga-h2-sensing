`timescale 1ns/1ps
// Checks USART log starts as specified and emits readable status at 8N1.
module tb_auto_lock_uart;
 reg clk=0,rst=1;
 always #5 clk=~clk;
 wire tx;
 auto_lock_uart #(.CLOCK_HZ(1000000),.BAUD(100000),.PERIOD_CLOCKS(100)) dut(
     .clk(clk),.rst(rst),.state(4'd6),.locked(1'b1),.reason(4'd0),
     .attempts(8'h2a),.adc(14'sd45),.dac(16'sd128),.target(16'sd50),
     .minimum(16'sd10),.maximum(16'sd200),.losses(32'd3),.tx(tx));
 reg [7:0] received;
 reg [7:0] expected[0:7];
 integer i,j;
 initial begin
     expected[0]="S"; expected[1]="="; expected[2]="6";
     expected[3]=" "; expected[4]="L"; expected[5]="=";
     expected[6]="1"; expected[7]=" ";
     repeat(4) @(posedge clk);rst=0;
     for(i=0;i<8;i=i+1) begin
         @(negedge tx);
         repeat(15) @(posedge clk); // middle of first data bit at 10 clocks per UART bit
         for(j=0;j<8;j=j+1) begin
             received[j]=tx;
             repeat(10) @(posedge clk);
         end
         if(received!==expected[i]) $fatal(1,"UART byte %0d got %h expected %h",i,received,expected[i]);
         // After the loop we are in the middle of stop bit.
     end
     $display("PASS UART status format start; decoded S=6 L=1");
     $finish;
 end
 initial begin #2000000; $fatal(1,"UART watchdog");end
endmodule
