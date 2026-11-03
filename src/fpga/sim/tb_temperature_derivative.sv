`timescale 1ns/1ps
module tb_temperature_derivative;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,enable=0,clear_fault=0,sample_valid=0,sensor_fault=0;
    reg signed [31:0] temperature_mc=25000,setpoint_mc=26000;
    reg [31:0] kp_q16=65536,ki_q16=0,kd_q16=65536;
    reg [15:0] duty_limit=10000;
    wire [15:0] duty;wire fault;wire signed [31:0] error_mc;
    temperature_pid #(.TIMEOUT_CYCLES(100)) dut(.*);
    task sample;
        begin @(negedge clk);sample_valid=1;@(posedge clk);#1;
            @(negedge clk);sample_valid=0;end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;enable=1;
        sample();if(duty!=1000)$fatal(1,"Initial derivative must be zero");
        temperature_mc=25500;sample();if(duty!=0)$fatal(1,"D must oppose temperature rise");
        setpoint_mc=27000;sample();if(duty!=1500)$fatal(1,"Setpoint derivative kick");
        temperature_mc=24500;sample();if(duty!=3500)$fatal(1,"D sign / arithmetic");
        @(negedge clk);enable=0;@(negedge clk);
        kp_q16=0;ki_q16=65536;kd_q16=0;duty_limit=100;enable=1;
        temperature_mc=25000;setpoint_mc=25050;
        sample();if(duty!=50)$fatal(1,"Integral step");
        setpoint_mc=25100;
        sample();if(duty!=50 || dut.integral_q16!=64'sd3276800)
            $fatal(1,"Saturated integral must freeze");
        setpoint_mc=24975;
        sample();if(duty!=25)$fatal(1,"Integral reverse recovery");
        if(fault)$fatal(1,"Unexpected fault");
        $display("ALL TESTS PASSED: derivative-on-measurement, no setpoint kick and anti-windup");$finish;
    end
    initial begin #10000;$fatal(1,"Watchdog");end
endmodule
