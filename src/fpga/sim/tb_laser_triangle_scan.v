`timescale 1ns/1ps
// XSim: set tb_laser_triangle_scan as simulation top, Run All.
module tb_laser_triangle_scan;
    reg clk=0,rst=1,enable=0;
    always #5 clk=~clk; // 100 MHz
    reg [15:0] span=16'd32,step=16'd8;
    reg [31:0] interval=32'd1000;
    reg signed [15:0] center=0;
    wire signed [15:0] code;
    wire valid;
    integer errors=0,updates=0;
    integer last_code=0,delta,at_hi=0,at_lo=0,down_steps=0,up_steps=0;
    reg previous_valid=0;
    laser_triangle_scan dut(.clk(clk),.rst(rst),.enable(enable),
        .half_span(span),.step_size(step),.interval_clocks(interval),
        .center(center),.code_out(code),.code_valid(valid));
    always @(posedge clk) begin
        #1;
        if (rst || !enable) begin previous_valid=0;end
        else if (valid) begin
            if(previous_valid) begin
                delta=$signed(code)-last_code;
                if(delta>8 || delta< -8) begin
                    $display("ERROR: discontinuity previous=%0d now=%0d",last_code,$signed(code));
                    errors=errors+1;
                end
                if(delta>0) up_steps=up_steps+1;
                if(delta<0) down_steps=down_steps+1;
            end
            last_code=$signed(code);
            previous_valid=1;
            updates=updates+1;
            if(code==32)at_hi=1;
            if(code==-32)at_lo=1;
            if($signed(code)>16384 || $signed(code)<-16384)errors=errors+1;
        end
    end
    initial begin
        repeat(6) @(negedge clk);
        rst=0;enable=1;
        repeat(36000) @(negedge clk);
        if (!at_hi || !at_lo || !up_steps || !down_steps) begin
            $display("ERROR: both ascending/descending full triangle not observed"); errors=errors+1;
        end
        // Shrink limits while active. The first new sample must not jump.
        span=8;
        repeat(7000) @(negedge clk);
        if($signed(code)>8 || $signed(code)< -8)begin
            $display("ERROR: new span not achieved");errors=errors+1;
        end
        // Grow again, then exercise the permitted center offset.
        span=24;center=16'sd12;
        repeat(12000) @(negedge clk);
        if($signed(code)>36 || $signed(code)<-12)begin
            $display("ERROR: centered span violated");errors=errors+1;
        end
        enable=0;
        repeat(5) @(negedge clk);
        if(code!==0 || valid!==0)begin
            $display("ERROR: disabled scanner is not idle");errors=errors+1;
        end
        if(updates<20) begin $display("ERROR: no output activity");errors=errors+1;end
        if(errors) $fatal(1,"TRIANGLE SCAN FAIL errors=%0d updates=%0d",errors,updates);
        $display("TRIANGLE SCAN PASS updates=%0d up=%0d down=%0d",updates,up_steps,down_steps);
        $finish;
    end
endmodule
