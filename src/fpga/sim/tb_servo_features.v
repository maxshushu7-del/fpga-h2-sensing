`timescale 1ns/1ps
// Independent module regressions for calibrated side-of-fringe servo features.
// Uses a 100 MHz work clock; the 100 kHz scheduler is checked cycle by cycle.
module tb_servo_features;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1;
    integer checks=0,f,i;

    reg cal_clear=0,cal_valid=0,cal_enable=1;
    reg signed [15:0] cal_sample=0,cal_offset=0;
    wire signed [16:0] cal_error;
    wire cal_out_valid;
    lock_point_calibration u_cal(.clk(clk),.rst(rst),.clear(cal_clear),
        .sample_in(cal_sample),.sample_valid(cal_valid),.lock_offset(cal_offset),
        .enable_offset_correction(cal_enable),.calibrated_error(cal_error),
        .calibrated_valid(cal_out_valid));

    reg norm_clear=0,norm_valid=0,norm_input_clip=0,norm_negative=0,norm_invert=0;
    reg signed [16:0] norm_delta=0;
    reg [31:0] norm_gain=65536;
    wire signed [15:0] norm_error;
    wire norm_out_valid,norm_clip,norm_adc_clip;
    locking_error_normalizer u_norm(.clk(clk),.rst(rst),.clear(norm_clear),
        .calibrated_error(norm_delta),.in_valid(norm_valid),.input_clipped(norm_input_clip),
        .loop_gain(norm_gain),.lock_negative(norm_negative),.error_invert(norm_invert),
        .error_signal(norm_error),.out_valid(norm_out_valid),.error_clipped(norm_clip),
        .adc_clipped_out(norm_adc_clip));

    reg sched_clear=0,sched_enable=0,sched_ready=1,sched_valid=0;
    reg [31:0] sched_period=1000;
    reg signed [15:0] sched_measurement=0;
    reg [1:0] sched_measurement_flags=0;
    wire signed [15:0] sched_error;
    wire sched_out_valid,sched_tick;
    wire [1:0] sched_flags;
    wire [31:0] sched_updates,sched_skipped;
    servo_scheduler u_scheduler(.clk(clk),.rst(rst),.clear(sched_clear),
        .enable(sched_enable),.update_period(sched_period),.downstream_ready(sched_ready),
        .measurement(sched_measurement),.measurement_valid(sched_valid),
        .measurement_flags(sched_measurement_flags),.servo_error(sched_error),
        .servo_valid(sched_out_valid),.servo_flags(sched_flags),.servo_tick(sched_tick),
        .update_count(sched_updates),.skipped_ticks(sched_skipped));

    reg act_clear=0,act_enable=1,act_valid=0,act_invert=0;
    reg signed [15:0] act_control=0;
    reg [31:0] act_scale=65536;
    reg [15:0] act_limit=32767;
    wire signed [15:0] act_voltage;
    wire act_out_valid,act_clip;
    laser_actuator_output u_act(.clk(clk),.rst(rst),.clear(act_clear),.enable(act_enable),
        .control_in(act_control),.control_valid(act_valid),.output_scale(act_scale),
        .output_limit(act_limit),.polarity_invert(act_invert),.control_voltage(act_voltage),
        .output_valid(act_out_valid),.output_clipped(act_clip));

    reg core_clear=0,core_valid=0,core_invert=0;
    reg signed [15:0] core_error=0,core_bias=0;
    reg signed [31:0] core_kp=0,core_ki=65536,core_kd=0,core_k2=0;
    reg [15:0] core_limit=1000,core_act_limit=10;
    reg [31:0] core_ilimit=32767,core_scale=131072;
    wire core_ready,core_out_valid,core_clip,core_anti,core_iclip;
    wire signed [15:0] core_voltage;
    wire signed [47:0] core_integral;
    pi2d_controller u_core(.clk(clk),.rst(rst),.clear(core_clear),
        .error_signal(core_error),.in_valid(core_valid),.in_ready(core_ready),
        .kp(core_kp),.ki(core_ki),.kd(core_kd),.k2(core_k2),.output_limit(core_limit),
        .integral_limit(core_ilimit),.output_bias(core_bias),.actuator_scale(core_scale),
        .actuator_limit(core_act_limit),.actuator_invert(core_invert),
        .control_voltage(core_voltage),.control_valid(core_out_valid),
        .integral_value(core_integral),.output_clipped(core_clip),
        .anti_windup(core_anti),.integral_clipped(core_iclip));

    // Queue-based 64-bit oracle verifies arithmetic, captured parameters,
    // flag alignment and three-clock latency with uninterrupted valid traffic.
    reg signed [63:0] norm_expected [0:127];
    reg [1:0] norm_expected_flags [0:127];
    integer norm_expected_cycle [0:127];
    integer norm_write=0,norm_read=0,norm_cycle=0,norm_checked=0;
    reg signed [63:0] norm_ref,norm_ref_gain;
    reg norm_ref_clip;
    always @(posedge clk) begin
        norm_cycle=norm_cycle+1;
        if(rst || norm_clear) begin norm_write=0; norm_read=0; end
        else begin
            if(norm_valid) begin
                norm_ref_gain=norm_gain[31] ? 2147483647 : norm_gain;
                norm_ref=$signed(norm_delta)*norm_ref_gain;
                if(!norm_negative) norm_ref=-norm_ref;
                if(norm_invert) norm_ref=-norm_ref;
                norm_ref=norm_ref >>> 16;
                norm_ref_clip=0;
                if(norm_ref>32767) begin norm_ref=32767; norm_ref_clip=1; end
                if(norm_ref< -32768) begin norm_ref=-32768; norm_ref_clip=1; end
                norm_expected[norm_write]=norm_ref;
                norm_expected_flags[norm_write]={norm_ref_clip,norm_input_clip};
                norm_expected_cycle[norm_write]=norm_cycle;
                norm_write=norm_write+1;
            end
            #1;
            if(norm_out_valid) begin
                if(norm_read>=norm_write) $fatal(1,"Normalizer unexpected valid");
                if($signed(norm_error)!==norm_expected[norm_read] ||
                    {norm_clip,norm_adc_clip}!==norm_expected_flags[norm_read] ||
                    norm_cycle-norm_expected_cycle[norm_read]!=2)
                    $fatal(1,"Normalizer #%0d: e=%0d expected=%0d flags=%b/%b latency=%0d",
                        norm_checked,$signed(norm_error),norm_expected[norm_read],
                        {norm_clip,norm_adc_clip},norm_expected_flags[norm_read],
                        norm_cycle-norm_expected_cycle[norm_read]);
                norm_read=norm_read+1; norm_checked=norm_checked+1; checks=checks+1;
            end
        end
    end
    reg signed [63:0] act_expected [0:127];
    reg act_expected_clip [0:127];
    integer act_expected_cycle [0:127];
    integer act_write=0,act_read=0,act_cycle=0,act_checked=0;
    reg signed [63:0] act_ref,act_ref_scale,act_ref_limit;
    reg act_ref_clip;
    always @(posedge clk) begin
        act_cycle=act_cycle+1;
        if(rst || act_clear || !act_enable) begin act_write=0; act_read=0; end
        else begin
            if(act_valid) begin
                act_ref_scale=act_scale[31] ? 2147483647 : act_scale;
                act_ref_limit=act_limit>32767 ? 32767 : act_limit;
                act_ref=$signed(act_control)*act_ref_scale;
                if(act_invert) act_ref=-act_ref;
                act_ref=act_ref >>> 16;
                act_ref_clip=0;
                if(act_ref>act_ref_limit) begin act_ref=act_ref_limit; act_ref_clip=1; end
                if(act_ref< -act_ref_limit) begin act_ref=-act_ref_limit; act_ref_clip=1; end
                act_expected[act_write]=act_ref;
                act_expected_clip[act_write]=act_ref_clip;
                act_expected_cycle[act_write]=act_cycle;
                act_write=act_write+1;
            end
            #1;
            if(act_out_valid) begin
                if(act_read>=act_write) $fatal(1,"Actuator unexpected valid");
                if($signed(act_voltage)!==act_expected[act_read] ||
                    act_clip!==act_expected_clip[act_read] ||
                    act_cycle-act_expected_cycle[act_read]!=2)
                    $fatal(1,"Actuator #%0d: u=%0d expected=%0d clip=%b/%b latency=%0d",
                        act_checked,$signed(act_voltage),act_expected[act_read],
                        act_clip,act_expected_clip[act_read],act_cycle-act_expected_cycle[act_read]);
                act_read=act_read+1; act_checked=act_checked+1; checks=checks+1;
            end
        end
    end

    // Independent scheduler state machine: fresh samples can be overwritten by
    // newer ones but are consumed only at an enabled tick with downstream ready.
    integer sched_ref_age=0,sched_ref_updates=0,sched_ref_skipped=0,sched_ticks_checked=0;
    reg sched_ref_fresh=0,sched_ref_tick,sched_ref_valid;
    reg signed [15:0] sched_ref_latest=0,sched_ref_output=0;
    reg [1:0] sched_ref_latest_flags=0,sched_ref_output_flags=0;
    reg [31:0] sched_ref_period;
    always @(posedge clk) begin
        sched_ref_tick=0; sched_ref_valid=0;
        if(rst || sched_clear) begin
            sched_ref_age=0; sched_ref_updates=0; sched_ref_skipped=0;
            sched_ref_fresh=0; sched_ref_latest=0; sched_ref_latest_flags=0;
        end else if(!sched_enable) begin
            sched_ref_age=0; sched_ref_fresh=0;
        end else begin
            if(sched_valid) begin
                sched_ref_latest=sched_measurement; sched_ref_latest_flags=sched_measurement_flags;
                sched_ref_fresh=1;
            end
            sched_ref_period=sched_period<64 ? 64 : sched_period;
            if(sched_ref_age==sched_ref_period-1) begin
                sched_ref_age=0; sched_ref_tick=1;
                if(sched_ref_fresh && sched_ready) begin
                    sched_ref_valid=1; sched_ref_output=sched_ref_latest;
                    sched_ref_output_flags=sched_ref_latest_flags;
                    sched_ref_fresh=0; sched_ref_updates=sched_ref_updates+1;
                end else sched_ref_skipped=sched_ref_skipped+1;
            end else sched_ref_age=sched_ref_age+1;
        end
        #1;
        if(sched_tick!==sched_ref_tick || sched_out_valid!==sched_ref_valid ||
            sched_updates!==sched_ref_updates || sched_skipped!==sched_ref_skipped)
            $fatal(1,"Scheduler age=%0d tick=%b/%b valid=%b/%b count=%0d/%0d skip=%0d/%0d",
                sched_ref_age,sched_tick,sched_ref_tick,sched_out_valid,sched_ref_valid,
                sched_updates,sched_ref_updates,sched_skipped,sched_ref_skipped);
        if(sched_out_valid && (sched_error!==sched_ref_output || sched_flags!==sched_ref_output_flags))
            $fatal(1,"Scheduler stale/incorrect sample %0d expected=%0d",$signed(sched_error),sched_ref_output);
        if(sched_tick) begin sched_ticks_checked=sched_ticks_checked+1; checks=checks+1; end
    end

    task cal_check;
        input integer sample,offset,enable,expected;
        begin
            @(negedge clk); cal_sample=sample; cal_offset=offset; cal_enable=enable; cal_valid=1;
            @(posedge clk); #1;
            if(!cal_out_valid || $signed(cal_error)!==expected)
                $fatal(1,"Calibration %0d-%0d=%0d expected=%0d",sample,offset,$signed(cal_error),expected);
            checks=checks+1;
            @(negedge clk); cal_valid=0;
            @(posedge clk); #1;
            if(cal_out_valid) $fatal(1,"Calibration valid was not a pulse");
        end
    endtask
    task normalizer_vector;
        input integer delta,negative,invert,clip;
        input [31:0] gain;
        begin
            @(negedge clk); norm_delta=delta; norm_negative=negative; norm_invert=invert;
            norm_input_clip=clip; norm_gain=gain; norm_valid=1;
        end
    endtask
    task actuator_vector;
        input integer control,invert,limit;
        input [31:0] scale;
        begin
            @(negedge clk); act_control=control; act_invert=invert;
            act_limit=limit; act_scale=scale; act_valid=1;
        end
    endtask
    task core_reset;
        begin
            @(negedge clk); core_clear=1;
            @(negedge clk); core_clear=0;
        end
    endtask
    integer core_checked=0;
    task core_check;
        input integer error,expected_u,expected_i;
        input expected_anti,expected_clip,expected_iclip;
        reg signed [63:0] expected_i_q16;
        begin
            expected_i_q16=expected_i;
            expected_i_q16=expected_i_q16 <<< 16;
            @(negedge clk); core_error=error; core_valid=1;
            while(!core_ready) @(negedge clk);
            @(negedge clk); core_valid=0;
            while(!core_out_valid) @(negedge clk);
            if($signed(core_voltage)!==expected_u || $signed(core_integral)!==expected_i_q16 ||
                {core_anti,core_clip,core_iclip}!=={expected_anti,expected_clip,expected_iclip})
                $fatal(1,"Projection anti-windup #%0d: u=%0d/%0d I=%0d/%0d flags=%b/%b",
                    core_checked,$signed(core_voltage),expected_u,$signed(core_integral),expected_i_q16,
                    {core_anti,core_clip,core_iclip},{expected_anti,expected_clip,expected_iclip});
            core_checked=core_checked+1; checks=checks+1;
            @(negedge clk);
            if(core_out_valid) $fatal(1,"Controller valid must be one clock");
        end
    endtask

    initial begin #2000000; $fatal(1,"Servo feature watchdog timeout"); end
    initial begin
        repeat(4) @(negedge clk); rst=0;
        cal_check(32767,-32768,1,65535);
        cal_check(-32768,32767,1,-65535);
        cal_check(1500,1500,1,0);
        cal_check(1487,1500,1,-13);
        cal_check(-32768,32767,0,-32768);
        cal_check(32767,-32768,0,32767);
        @(negedge clk); cal_clear=1; cal_valid=1;
        @(posedge clk); #1;
        if(cal_out_valid || cal_error!==0) $fatal(1,"Calibration clear must cancel valid");
        @(negedge clk); cal_clear=0; cal_valid=0;

        normalizer_vector(100,0,0,0,65536);
        normalizer_vector(100,1,0,1,65536);
        normalizer_vector(-100,0,0,1,65536);
        normalizer_vector(-100,1,1,0,65536);
        normalizer_vector(7,0,0,0,32768);
        normalizer_vector(-7,0,0,1,32768);
        normalizer_vector(65535,0,0,0,65536);
        normalizer_vector(-65535,0,0,1,65536);
        normalizer_vector(65535,1,0,1,65536);
        normalizer_vector(-65535,1,0,0,65536);
        normalizer_vector(123,0,0,1,0);
        normalizer_vector(1,1,0,0,32'hffffffff);
        normalizer_vector(-2,1,0,0,32'hffffffff);
        normalizer_vector(-65536,1,1,0,32'h7fffffff);
        @(negedge clk); norm_valid=0;
        repeat(4) @(negedge clk);
        if(norm_read!=norm_write || norm_out_valid) $fatal(1,"Normalizer queue did not drain");

        actuator_vector(7,0,32767,32768);
        actuator_vector(-7,0,32767,32768);
        actuator_vector(7,1,32767,32768);
        actuator_vector(-7,1,32767,32768);
        actuator_vector(100,0,15,131072);
        actuator_vector(-100,0,15,131072);
        actuator_vector(100,1,15,131072);
        actuator_vector(-100,1,15,131072);
        actuator_vector(-32768,1,65535,65536);
        actuator_vector(32767,0,65535,32'hffffffff);
        actuator_vector(-32768,0,65535,32'h7fffffff);
        actuator_vector(123,1,32767,0);
        actuator_vector(1,0,0,65536);
        actuator_vector(0,1,0,65536);
        actuator_vector(15,0,15,65536);
        actuator_vector(-15,0,15,65536);
        @(negedge clk); act_valid=0;
        repeat(4) @(negedge clk);
        if(act_read!=act_write || act_out_valid) $fatal(1,"Actuator queue did not drain");
        @(negedge clk); act_enable=0;
        @(posedge clk); #1;
        if(act_voltage!==0 || act_out_valid) $fatal(1,"Actuator disabled output");
        @(negedge clk); act_enable=1;

        // Exact 1000-cycle default cadence (10 us), never repeat a stale sample.
        @(negedge clk); sched_enable=1;
        repeat(2000) @(negedge clk);
        sched_measurement=123; sched_measurement_flags=2'b10; sched_valid=1;
        @(negedge clk); sched_valid=0;
        repeat(1999) @(negedge clk);
        // Fresh same-tick sample overrides the previously buffered sample.
        sched_measurement=10; sched_measurement_flags=2'b01; sched_valid=1;
        repeat(999) @(negedge clk);
        sched_measurement=777; sched_measurement_flags=2'b11;
        @(negedge clk); sched_valid=0;
        repeat(1000) @(negedge clk);
        // Busy tick must not consume latest sample; it survives to the next tick.
        sched_measurement=-222; sched_measurement_flags=2'b01; sched_valid=1; sched_ready=0;
        @(negedge clk); sched_valid=0;
        repeat(999) @(negedge clk);
        sched_ready=1;
        repeat(1000) @(negedge clk);
        // Runtime minimum period and disabled phase restart.
        sched_clear=1;
        @(negedge clk); sched_clear=0; sched_period=1; sched_valid=1;
        repeat(128) @(negedge clk);
        sched_valid=0; sched_enable=0;
        repeat(70) @(negedge clk);
        sched_enable=1; sched_measurement=42; sched_measurement_flags=0; sched_valid=1;
        @(negedge clk); sched_valid=0;
        repeat(63) @(negedge clk);
        sched_enable=0;

        // The controller's own limit is deliberately wide. Only actuator
        // scaling causes these saturations, so internal-only anti-windup fails.
        core_reset;
        core_check(10,0,0,1,0,0); core_check(-10,0,0,1,0,0);
        for(i=1;i<=5;i=i+1) core_check(1,i,i,0,0,0);
        core_check(1,5,5,1,0,0); core_check(-1,4,4,0,0,0);
        core_kp=-1310720;
        core_check(-1,23,3,0,0,0); // saturation decreases as I unwinds
        core_kp=0; core_invert=1; core_reset;
        for(i=1;i<=5;i=i+1) core_check(1,i,i,0,0,0);
        core_check(1,5,5,1,0,0); core_check(-1,4,4,0,0,0);
        core_kp=-1310720;
        core_check(-1,23,3,0,0,0);
        core_kp=0; core_ki=-65536; core_reset;
        core_check(-10,0,0,1,0,0); core_check(10,0,0,1,0,0);
        core_ki=65536; core_scale=0; core_reset;
        core_check(1,0,0,1,0,0); core_check(-1,0,0,1,0,0);
        core_ki=0; core_kp=65536;
        core_check(7,7,0,0,0,0);
        core_ki=65536; core_scale=65536; core_act_limit=32767;
        core_invert=0; core_limit=16; core_reset;
        core_check(100,16,0,1,1,0); core_check(-100,-16,0,1,1,0);
        core_kp=0; core_limit=1000; core_ilimit=2; core_reset;
        core_check(3,2,2,0,0,1); core_check(-5,-2,-2,0,0,1);

        repeat(4) @(negedge clk);
        f=$fopen("servo_features_result.txt","w");
        if(!f) $fatal(1,"Cannot write servo feature result");
        $fwrite(f,"PASS\nChecked feature observations: %0d\n",checks);
        $fwrite(f,"Normalizer vectors: %0d\nActuator vectors: %0d\nScheduler ticks: %0d\nController projection vectors: %0d\n",
            norm_checked,act_checked,sched_ticks_checked,core_checked);
        $fwrite(f,"Coverage: full 17-bit offset arithmetic; signed lock polarity/loop gain; three-cycle continuous-valid pipelines; 100kHz/64-cycle scheduler, freshest sample, skipped ticks and busy retention; scaling/inversion/limit; actuator-projected anti-windup, zero gain and recovery.\n");
        $fclose(f);
        $display("SERVO FEATURE TEST PASS: %0d checks, norm=%0d act=%0d ticks=%0d projection=%0d",
            checks,norm_checked,act_checked,sched_ticks_checked,core_checked);
        $finish;
    end
endmodule
