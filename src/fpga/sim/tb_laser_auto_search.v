`timescale 1ns/1ps
// XSim behavior-only test: synthetic resonance valley and flat/no-resonance cases.
// The DUT does not imply a calibrated DAC voltage or proven optical lock.
module tb_laser_auto_search;
    reg clk=0;always #5 clk=~clk; // 100MHz
    reg rst=1,enable=0,flat=0;
    wire signed [15:0] request,applied,lock_code,lock_setpoint,coarse_code,coarse_adc;
    wire pid_enable,pid_clear,valid;
    wire [4:0] state;
    wire [7:0] fault;
    wire [15:0] depth,slope;
    wire [31:0] points;
    reg [4:0] div=0;
    reg adc_valid=0;
    reg signed [13:0] adc_value=0;
    reg signed [15:0] last_applied=0;
    reg [31:0] changes=0;
    integer signed delta,abs_delta,loss,analog_value;
    wire signed [15:0] low=-16'sd128,high=16'sd128;
    laser_code_guard guard(.clk(clk),.rst(rst),.enable(enable),
        .target_code(request),.min_code(low),.max_code(high),
        .max_step(16'd16),.interval_clocks(32'd1000),
        .applied_code(applied),.applied_valid(valid));
    laser_auto_search dut(.clk(clk),.rst(rst),.enable(enable),
        .applied_code(applied),.adc_sample(adc_value),.adc_valid(adc_valid),
        .coarse_lo(low),.coarse_hi(high),.coarse_step(16'd16),
        .fine_half(16'd40),.fine_step(16'd4),.dwell_clocks(32'd1000),
        .min_depth(16'd200),.min_slope(16'd10),.lock_error_limit(16'd1200),
        .requested_code(request),.pid_enable(pid_enable),.pid_clear(pid_clear),
        .lock_code(lock_code),.lock_setpoint(lock_setpoint),.state(state),
        .fault(fault),.coarse_min_code(coarse_code),.coarse_min_adc(coarse_adc),
        .coarse_depth(depth),.best_slope(slope),.points_tested(points));
    always @(posedge clk)begin
        if(rst)begin div<=0;adc_valid<=0;adc_value<=0;end
        else begin
            if(div==5'd10)begin
                div<=0;adc_valid<=1;
                delta=applied-40;
                abs_delta=(delta<0)?-delta:delta;
                loss=(abs_delta<40)?(40-abs_delta)*20:0;
                analog_value=flat ? 1000 : 1000-loss;
                adc_value<=analog_value;
            end else begin div<=div+1'b1;adc_valid<=0;end
        end
        // Reset the testbench's comparison history whenever the DUT is reset
        // or disabled. Otherwise, a previous run's last sample is compared
        // with the first sample of the next run (a false GUARD SLEW FAIL).
        if (rst || !enable) begin
            last_applied <= 16'sd0;
            changes <= 32'd0;
        end else if (valid) begin
            if (applied > high || applied < low)
                $fatal(1,"GUARD RANGE FAIL");
            // The guard updates applied_code using nonblocking assignments;
            // applied_valid marks when the new output can be sampled.
            if (($signed(applied) - $signed(last_applied) > 32'sd16) ||
                ($signed(applied) - $signed(last_applied) < -32'sd16))
                $fatal(1,"GUARD SLEW FAIL %d %d",last_applied,applied);
            last_applied <= applied;
            changes <= changes + 1'b1;
        end
    end
    integer cycles;
    initial begin
        repeat(12)@(posedge clk);rst=0;
        @(negedge clk);enable=1;
        for(cycles=0;cycles<1000000;cycles=cycles+1)begin
            @(negedge clk);
            if(state==12)begin
                if(!pid_enable || fault!=0 || depth<200 || slope<10 ||
                   lock_code< -64 || lock_code>100)
                    $fatal(1,"AUTO LOCK ASSERT FAILED code=%d depth=%d slope=%d fault=%d",lock_code,depth,slope,fault);
                $display("AUTO SEARCH PASS lock_code=%0d setpoint=%0d depth=%0d slope=%0d points=%0d",lock_code,lock_setpoint,depth,slope,points);
                cycles=1000000;
            end
            if(state==13)$fatal(1,"Unexpected fault=%0d",fault);
        end
        if(state!=12)$fatal(1,"AUTO LOCK TIMEOUT state=%0d",state);
        @(negedge clk); enable=0;rst=1;flat=1;
        repeat(10)@(negedge clk);rst=0;enable=1;
        for(cycles=0;cycles<1000000;cycles=cycles+1)begin
            @(negedge clk);
            if(state==13)begin
                if(fault!=3 || pid_enable) $fatal(1,"FLAT SPECTRUM ASSERT FAILED fault=%0d",fault);
                $display("AUTO NO-RESONANCE PASS fault=%0d points=%0d",fault,points);
                cycles=1000000;
            end
        end
        if(state!=13)$fatal(1,"FLAT SPECTRUM TIMEOUT");
        $display("AUTO SEARCH TEST PASS");
        $finish;
    end
endmodule
