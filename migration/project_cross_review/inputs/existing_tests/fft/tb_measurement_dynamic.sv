`timescale 1ns/1ps
// Continuous DDS stimulus at the original ADC/proc clocks. No shortened FFT,
// reduced decimation, replayed FFT RAM, or skipped filter samples are allowed.
// The expensive AMD behavioral FFT may pause ONLY during idle capture, using
// the existing verification-only knob; +FULL_FFT_CLOCK=1 disables that pause.
module tb_measurement_dynamic #(
    parameter integer TRACKING_ENABLE=1,
    parameter integer SIM_IDLE_FFT_PAUSE=1,
    parameter integer TRACK_RECHECK_FRAMES=2
);
    localparam integer FFT_LOG2=12, N=1<<FFT_LOG2, OUT_WIDTH=17+FFT_LOG2;
    localparam integer MAX_WAIT_CYCLES=2500000; // 25 ms at proc_clk=100 MHz.
    reg adc_clk=0, proc_clk=0, rst_n=0, enabled=0, adc_clock_enabled=1;
    always #2 if(adc_clock_enabled) adc_clk=~adc_clk;
    always #5 proc_clk=~proc_clk;
    reg signed [13:0] channel_a=0, channel_b=0;
    wire capture_active, fft_valid, fft_last, result_strobe;
    wire measurement_valid, fine_mode, low_mode, protocol_error;
    wire result_fine_mode, result_low_mode, tracking_active;
    wire [FFT_LOG2-1:0] capture_address, fft_bin, peak_bin, coarse_bin;
    wire signed [OUT_WIDTH-1:0] fft_re, fft_im;
    wire signed [17:0] bin_offset_q16;
    wire signed [31:0] fine_offset_hz;
    wire [31:0] frequency_hz, sequence_number, clipped_samples, reacquire_count;
    wire [2*OUT_WIDTH:0] peak_power, noise_power;
    reg [2*OUT_WIDTH:0] full_amplitude_power=0, weak_amplitude_power=0;
    wire [7:0] result_flags;
    integer test_case=0, full_fft_clock=0;
    integer result_count=0, valid_count=0, invalid_count=0, settled_checks=0;
    integer timeout_count=0, stopped_sequence=0, stopped_results=0, edge_reacquire=0;
    integer input_count=0, output_count=0, input_frames=0, output_frames=0;
    integer results_fd, events_fd, epoch=0, amplitude=200, output_enabled=1;
    integer last_reacquire=0, tracking_results=0, coarse_results=0;
    integer sine_lut[0:4095], lut_index, sample_product, sample_value, i;
    reg [31:0] phase_acc=0, stimulus_tuning_word=0;
    reg passed=0, previous_strobe=0, alias_guard=0;
    reg published_fine=0, published_low=0;
    integer previous_seq=0, first_reacquire=0;
    real target_hz=5000.0, last_change_ns=0.0;
    real previous_time_ns=0.0, min_interval_ns=1.0e30, max_interval_ns=0.0;
    string results_path, events_path;

    measurement_improved #(.ALGORITHM_VERSION(3),.FFT_LOG2(FFT_LOG2),
        .SIM_IDLE_FFT_PAUSE(SIM_IDLE_FFT_PAUSE),.WINDOW_ENABLE(1),.ADC_CHANNEL(1),
        .TRACKING_ENABLE(TRACKING_ENABLE),.TRACK_RECHECK_FRAMES(TRACK_RECHECK_FRAMES),
        .FRAME_GAP_CYCLES(0),.TIMEOUT_CYCLES(600000)) dut (
        .adc_clk(adc_clk),.adc_rst_n(rst_n),.channel_a(channel_a),.channel_b(channel_b),
        .proc_clk(proc_clk),.proc_rst_n(rst_n),.enabled(enabled),
        .capture_active(capture_active),.capture_address(capture_address),
        .fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
        .fft_valid(fft_valid),.fft_last(fft_last),.result_strobe(result_strobe),
        .measurement_valid(measurement_valid),.fine_mode(fine_mode),.low_mode(low_mode),
        .result_fine_mode(result_fine_mode),.result_low_mode(result_low_mode),
        .tracking_active(tracking_active),.reacquire_count(reacquire_count),
        .frequency_hz(frequency_hz),.sequence_number(sequence_number),
        .peak_bin(peak_bin),.coarse_bin(coarse_bin),.bin_offset_q16(bin_offset_q16),
        .fine_offset_hz(fine_offset_hz),.peak_power(peak_power),.noise_power(noise_power),
        .result_flags(result_flags),.clipped_samples(clipped_samples),
        .protocol_error(protocol_error));

    function integer rounded(input real value);
        rounded=value>=0 ? $rtoi(value+0.5) : $rtoi(value-0.5);
    endfunction

    // A 4096-entry Q15 sine LUT avoids millions of simulator $sin calls. The
    // 32-bit DDS phase remains continuous through frequency/amplitude steps.
    // DDS frequency quantization is <0.030 Hz, well below the RTL test tolerance.
    // The analogue stimulus keeps running when the ADC sampling clock stops.
    // With sampling enabled, #4 coincides with ADC falling edges.
    always #4 if(rst_n) begin
        phase_acc=phase_acc+stimulus_tuning_word;
        lut_index=phase_acc[31:20];
        sample_product=amplitude*sine_lut[lut_index];
        sample_value=sample_product>=0 ? (sample_product+16383)/32767 :
            -((-sample_product+16383)/32767);
        channel_a=14'sd400; // A constant on the other slot checks channel selection.
        channel_b=output_enabled ? sample_value+31 : 31;
    end

    task change_input(input real frequency, input integer new_amplitude,
                      input integer new_enabled, input string label);
        begin
            @(negedge proc_clk);
            target_hz=frequency; amplitude=new_amplitude; output_enabled=new_enabled;
            stimulus_tuning_word=rounded(frequency*4294967296.0/250000000.0);
            epoch=epoch+1; last_change_ns=$realtime;
            $display("DYNAMIC_INPUT case=%0d epoch=%0d time_ns=%0.0f label=%s target_hz=%0.3f amplitude_codes=%0d enabled=%0d",
                test_case,epoch,$realtime,label,target_hz,amplitude,output_enabled);
            $fdisplay(events_fd,"%0.0f,%0d,%s,%0.3f,%0d,%0d",
                $realtime,epoch,label,target_hz,amplitude,output_enabled);
        end
    endtask

    // Inspect complete FFT transfers before NBA; inspect published data after
    // NBA. Every publication, including invalid transition results, is logged.
    always @(posedge proc_clk) if(rst_n) begin
        if(!full_fft_clock && dut.configured && dut.state==2 &&
           (fft_valid || dut.sample_valid))
            $fatal(1,"Attempted idle FFT pause during an active transaction");
        if(dut.sample_valid && dut.sample_ready) begin
            if(^dut.stream_i===1'bx || ^dut.stream_q===1'bx)
                $fatal(1,"Unknown FFT input");
            if(dut.read_address!==input_count[FFT_LOG2-1:0])
                $fatal(1,"FFT input address order mismatch");
            input_count=input_count+1;
            if(input_count==N) begin input_count=0; input_frames=input_frames+1; end
        end
        if(fft_valid) begin
            if(fft_bin!==output_count[FFT_LOG2-1:0])
                $fatal(1,"FFT output bin order mismatch");
            if(fft_last!==(output_count==N-1))
                $fatal(1,"FFT output TLAST mismatch");
            output_count=output_count+1;
            if(output_count==N) begin output_count=0; output_frames=output_frames+1; end
        end
        if(protocol_error) $fatal(1,"FFT protocol error");
        if(dut.coarse_strobe)
            $display("DYNAMIC_COARSE case=%0d epoch=%0d target_hz=%0.3f coarse_hz=%0d coarse_bin=%0d valid=%0d state=%0d",
                test_case,epoch,target_hz,dut.coarse_hz,dut.coarse_peak,dut.coarse_valid,dut.state);
        #1;
        if(result_strobe) begin
            if(previous_strobe) $fatal(1,"Result strobe exceeded one processing clock");
            result_count=result_count+1;
            if(sequence_number!==result_count)
                $fatal(1,"Duplicate, stale or skipped sequence: got=%0d expected=%0d",
                    sequence_number,result_count);
            if(^frequency_hz===1'bx || ^result_flags===1'bx)
                $fatal(1,"Unknown result fields");
            if(result_fine_mode && result_low_mode)
                $fatal(1,"Published result asserted both filtered modes");
            if(measurement_valid) begin
                valid_count=valid_count+1;
                if(alias_guard && (frequency_hz<609500 || frequency_hz>610500))
                    $fatal(1,"Aliased low-band result incorrectly accepted after 390k -> 610k jump: hz=%0d",frequency_hz);
                if(!result_fine_mode && !result_low_mode)
                    $fatal(1,"V3 valid result did not come from a filtered frame");
                if(clipped_samples!=0) $fatal(1,"Clean stimulus unexpectedly clipped");
                if(tracking_active) tracking_results=tracking_results+1;
                else coarse_results=coarse_results+1;
            end else begin
                invalid_count=invalid_count+1;
                if(frequency_hz!=0) $fatal(1,"Invalid publication retained an old nonzero frequency");
            end
            if(result_flags[4]) begin
                timeout_count=timeout_count+1;
                if(test_case!=4 || adc_clock_enabled)
                    $fatal(1,"Running ADC stimulus unexpectedly timed out");
            end
            if(reacquire_count<last_reacquire) $fatal(1,"Reacquire counter went backwards");
            last_reacquire=reacquire_count;
            if(previous_time_ns!=0.0) begin
                if($realtime-previous_time_ns<min_interval_ns)
                    min_interval_ns=$realtime-previous_time_ns;
                if($realtime-previous_time_ns>max_interval_ns)
                    max_interval_ns=$realtime-previous_time_ns;
            end
            previous_time_ns=$realtime;
            published_fine=result_fine_mode; published_low=result_low_mode;
            previous_seq=sequence_number;
            $display("DYNAMIC_RESULT case=%0d seq=%0d time_ns=%0.0f epoch=%0d target=%0.3f enabled=%0d valid=%0d hz=%0d fine=%0d low=%0d tracking=%0d reacquire=%0d flags=%02x",
                test_case,sequence_number,$realtime,epoch,target_hz,output_enabled,
                measurement_valid,frequency_hz,result_fine_mode,result_low_mode,
                tracking_active,reacquire_count,result_flags);
            $fdisplay(results_fd,"%0.0f,%0d,%0d,%0.3f,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%02x,%0d,%0d,%0d,%0d",
                $realtime,sequence_number,epoch,target_hz,amplitude,output_enabled,
                measurement_valid,frequency_hz,result_fine_mode,result_low_mode,
                tracking_active,result_flags,reacquire_count,peak_power,noise_power,
                output_frames);
        end else if(sequence_number==previous_seq &&
                    (result_fine_mode!==published_fine || result_low_mode!==published_low))
            $fatal(1,"Published mode changed between result strobes");
        previous_strobe=result_strobe;
    end

    task wait_new_result(input integer old_sequence, input integer max_cycles);
        integer cycles;
        begin
            cycles=0;
            while((!result_strobe || sequence_number<=old_sequence) && cycles<max_cycles) begin
                @(negedge proc_clk); cycles=cycles+1;
            end
            if(cycles==max_cycles)
                $fatal(1,"No new result within %0d processing cycles",max_cycles);
        end
    endtask

    task expect_settled(input real expected_frequency, input integer required_results,
                        input integer expected_mode, input string label);
        integer deadline_cycles, consecutive, old_seq, waited;
        real error_hz, start_ns;
        begin
            deadline_cycles=MAX_WAIT_CYCLES; consecutive=0; old_seq=sequence_number;
            start_ns=$realtime;
            while(consecutive<required_results) begin
                wait_new_result(old_seq,deadline_cycles);
                old_seq=sequence_number;
                waited=$rtoi(($realtime-start_ns)/10.0);
                deadline_cycles=MAX_WAIT_CYCLES-waited;
                if(deadline_cycles<=0) $fatal(1,"Dynamic reacquisition exceeded 25 ms: %s",label);
                error_hz=frequency_hz-expected_frequency;
                if(error_hz<0.0) error_hz=-error_hz;
                if(measurement_valid && error_hz<=500.0) begin
                    if(expected_mode==1 && !result_low_mode)
                        $fatal(1,"Low-band settled result used incorrect mode: %s",label);
                    if(expected_mode==2 && !result_fine_mode)
                        $fatal(1,"High-band settled result used incorrect mode: %s",label);
                    consecutive=consecutive+1; settled_checks=settled_checks+1;
                    $display("DYNAMIC_SETTLED label=%s seq=%0d error_hz=%0.3f after_change_ms=%0.6f",
                        label,sequence_number,error_hz,($realtime-last_change_ns)/1000000.0);
                end else consecutive=0;
                @(negedge proc_clk);
            end
        end
    endtask

    task expect_off(input string label);
        integer old_seq, remaining, elapsed;
        real start_ns;
        begin
            old_seq=sequence_number; remaining=MAX_WAIT_CYCLES; start_ns=$realtime;
            begin: wait_off
                forever begin
                    wait_new_result(old_seq,remaining); old_seq=sequence_number;
                    elapsed=$rtoi(($realtime-start_ns)/10.0);
                    remaining=MAX_WAIT_CYCLES-elapsed;
                    if(!measurement_valid && frequency_hz==0) begin
                        settled_checks=settled_checks+1;
                        $display("DYNAMIC_OFF_CONFIRMED label=%s seq=%0d after_change_ms=%0.6f",
                            label,sequence_number,($realtime-last_change_ns)/1000000.0);
                        disable wait_off;
                    end
                    if(remaining<=0) $fatal(1,"Signal-off did not invalidate within 25 ms");
                    @(negedge proc_clk);
                end
            end
            @(negedge proc_clk);
        end
    endtask

    initial begin
        if($value$plusargs("CASE=%d",test_case)) begin end
        if($value$plusargs("FULL_FFT_CLOCK=%d",full_fft_clock)) begin end
        if(test_case<0 || test_case>5) $fatal(1,"Unsupported dynamic CASE");
        if((test_case==3 || test_case==4) && !TRACKING_ENABLE)
            $fatal(1,"Alias guard and tracking-edge scenarios require tracking enabled");
        if(test_case==4 && TRACK_RECHECK_FRAMES<=4)
            $fatal(1,"Edge guard test needs an independent recheck interval above4");
        if(full_fft_clock!=(SIM_IDLE_FFT_PAUSE==0))
            $fatal(1,"FULL_FFT_CLOCK plusarg disagrees with FFT clock parameter");
        results_path=$sformatf("E:/Codex/FPGA/projects/adc_fft_tracking_20261014/verification/dynamic/case%0d_tracking%0d_results.csv",test_case,TRACKING_ENABLE);
        events_path=$sformatf("E:/Codex/FPGA/projects/adc_fft_tracking_20261014/verification/dynamic/case%0d_tracking%0d_events.csv",test_case,TRACKING_ENABLE);
        results_fd=$fopen(results_path,"w"); events_fd=$fopen(events_path,"w");
        if(!results_fd || !events_fd) $fatal(1,"Cannot create dynamic result logs on E:");
        $fdisplay(results_fd,"time_ns,sequence,epoch,target_hz,amplitude_codes,input_enabled,valid,frequency_hz,result_fine_mode,result_low_mode,tracking_active,flags,reacquire_count,peak_power,noise_power,complete_fft_frames");
        $fdisplay(events_fd,"time_ns,epoch,label,target_hz,amplitude_codes,input_enabled");
        for(i=0;i<4096;i=i+1)
            sine_lut[i]=rounded(32767.0*$sin(6.2831853071795864769*i/4096.0));
        $display("DYNAMIC_POLICY case=%0d ADC=250MS/s proc=100MHz FFT=4096 decimation=250 tracking=%0d recheck=%0d full_fft_clock=%0d sine_lut=4096_Q15",
            test_case,TRACKING_ENABLE,TRACK_RECHECK_FRAMES,full_fft_clock);
        #100; @(negedge proc_clk); rst_n=1;
        repeat(30) @(negedge proc_clk);

        if(test_case==0) begin
            change_input(5000.0,200,1,"continuous_5k"); enabled=1;
            expect_settled(5000.0,3,1,"continuous_5k");
            if(TRACKING_ENABLE && tracking_results<1)
                $fatal(1,"Continuous stream did not exercise tracking reuse");
            change_input(100000.0,200,1,"step_100k");
            expect_settled(100000.0,1,1,"step_100k");
            if(TRACKING_ENABLE && reacquire_count<2)
                $fatal(1,"Continuous stream did not exercise periodic coarse search");
            change_input(390000.0,200,1,"boundary_390k");
            expect_settled(390000.0,1,1,"boundary_390k");
            change_input(500000.0,200,1,"boundary_500k");
            expect_settled(500000.0,1,2,"boundary_500k");
            change_input(1000000.0,200,1,"step_1M");
            expect_settled(1000000.0,1,2,"step_1M");
            change_input(5000000.0,200,1,"step_5M");
            expect_settled(5000000.0,1,2,"step_5M");
            change_input(25000000.0,200,1,"step_25M");
            expect_settled(25000000.0,1,2,"step_25M");
            full_amplitude_power=peak_power;
            change_input(25000000.0,20,1,"amplitude_down_10x");
            expect_settled(25000000.0,1,2,"amplitude_down_10x");
            weak_amplitude_power=peak_power;
            if(weak_amplitude_power==0 || full_amplitude_power/weak_amplitude_power<50 ||
               full_amplitude_power/weak_amplitude_power>150)
                $fatal(1,"Tenfold amplitude step did not approximately reduce power 100x");
            $display("DYNAMIC_AMPLITUDE_POWER full=%0d weak=%0d ratio=%0d",
                full_amplitude_power,weak_amplitude_power,full_amplitude_power/weak_amplitude_power);
            if(settled_checks!=10) $fatal(1,"Missing continuous/step/amplitude checks");
        end else if(test_case==1) begin
            change_input(5000000.0,200,1,"coarse_before_jump"); enabled=1;
            // Trigger the jump after raw coarse estimation selects the old
            // carrier, but before the NEW fine sample window has begun.
            wait(fine_mode && !capture_active);
            change_input(25000000.0,200,1,"jump_between_coarse_and_fine");
            first_reacquire=reacquire_count;
            expect_settled(25000000.0,2,2,"jump_between_coarse_and_fine");
            if(reacquire_count<=first_reacquire)
                $fatal(1,"Between-frame jump never forced/refreshed a coarse search");
            change_input(25000000.0,200,0,"signal_off");
            expect_off("signal_off");
            change_input(50000.0,200,1,"restore_fresh_50k");
            expect_settled(50000.0,1,1,"restore_fresh_50k");
            if(settled_checks!=4 || invalid_count<1)
                $fatal(1,"Missing coarse/fine jump or signal-off/recovery checks");
        end else if(test_case==2) begin
            change_input(5000.0,200,1,"short_continuous_5k"); enabled=1;
            expect_settled(5000.0,3,1,"short_continuous_5k");
            if(TRACKING_ENABLE && tracking_results<1)
                $fatal(1,"Short comparison did not exercise tracking");
            if(!TRACKING_ENABLE && tracking_results!=0)
                $fatal(1,"Legacy comparison unexpectedly reused a coarse center");
            change_input(5000000.0,200,1,"short_jump_5M");
            expect_settled(5000000.0,1,2,"short_jump_5M");
            if(settled_checks!=4) $fatal(1,"Missing short comparison checks");
        end else if(test_case==3) begin
            change_input(390000.0,200,1,"alias_guard_stable_390k"); enabled=1;
            expect_settled(390000.0,2,1,"alias_guard_stable_390k");
            // Ensure the next frame uses the cached low-band branch. A real
            // 610 kHz tone then aliases to 390 kHz at Fs'=1 MHz; quality/guard
            // checks alone can accept it. Independent raw verification must
            // reject that candidate before a trusted result is published.
            wait(capture_active && low_mode && dut.cycle_tracking && capture_address<32);
            change_input(610000.0,200,1,"cached_low_390k_to_610k");
            alias_guard=1; first_reacquire=reacquire_count;
            expect_settled(610000.0,2,2,"cached_low_390k_to_610k");
            if(invalid_count<1 || reacquire_count<=first_reacquire)
                $fatal(1,"Alias candidate was not rejected with fresh coarse reacquisition");
            if(settled_checks!=4) $fatal(1,"Missing alias guard recovery checks");
        end else if(test_case==4) begin
            change_input(5000000.0,200,1,"fine_continuous_5M"); enabled=1;
            expect_settled(5000000.0,1,2,"fine_continuous_5M");
            change_input(5010000.0,200,1,"within_passband_5M_to_5p01M");
            expect_settled(5010000.0,1,2,"within_passband_5M_to_5p01M");
            if(!tracking_active || reacquire_count!=1)
                $fatal(1,"Small fine-passband jump unexpectedly abandoned the validated NCO");
            // Record before publication: with gap0 the next raw search can
            // increment the live counter before expect_settled returns.
            edge_reacquire=reacquire_count;
            change_input(5095000.0,200,1,"fine_edge_5p095M");
            expect_settled(5095000.0,1,2,"fine_edge_5p095M");
            if(!tracking_active || fine_offset_hz<=80000 || fine_offset_hz>=100000)
                $fatal(1,"Fine edge stimulus did not exercise the 80k tracking-edge guard");
            expect_settled(5095000.0,1,2,"edge_recenter_next_frame");
            if(tracking_active || reacquire_count<=edge_reacquire ||
               fine_offset_hz>31000 || fine_offset_hz< -31000)
                $fatal(1,"Edge result did not force a fresh recentered coarse search");

            // Stop the ADC while the NEW posterior raw verification capture
            // is in progress. A complete saved fine candidate must not become
            // a trusted publication when the independent check never finishes.
            wait(dut.checking_result && capture_active && !fine_mode && !low_mode && capture_address>=128);
            @(negedge adc_clk); adc_clock_enabled=0;
            last_change_ns=$realtime;
            $display("DYNAMIC_ADC_STOP phase=posterior_raw_check time_ns=%0.0f address=%0d seq=%0d",
                $realtime,capture_address,sequence_number);
            expect_off("clock_loss_during_posterior_raw_check");
            if(timeout_count!=1 || !result_flags[4] || result_flags!=8'h11)
                $fatal(1,"Posterior raw clock loss did not publish exactly one timeout result");
            stopped_sequence=sequence_number; stopped_results=result_count;
            repeat(601000) @(negedge proc_clk);
            if(sequence_number!=stopped_sequence || result_count!=stopped_results ||
               timeout_count!=1 || measurement_valid || frequency_hz!=0)
                $fatal(1,"Stopped ADC repeated results or retained a trusted pending candidate");
            change_input(5000.0,200,1,"adc_clock_resume_fresh_5k");
            adc_clock_enabled=1;
            expect_settled(5000.0,1,1,"adc_clock_resume_fresh_5k");
            if(settled_checks!=6 || timeout_count!=1)
                $fatal(1,"Missing fine-passband/edge/postcheck-clock-loss checks");
        end else begin
            // Short full-clock arithmetic cross-check: the entire 4.096ms
            // filtered acquisition and all4096 fresh samples are retained.
            change_input(5000.0,200,1,"single_fullclock_5k"); enabled=1;
            expect_settled(5000.0,1,1,"single_fullclock_5k");
            if(settled_checks!=1 || frequency_hz!=5000)
                $fatal(1,"Full-clock 5k result disagrees with the idle-pause reference");
        end
        if(input_count!=0 || output_count!=0 || input_frames!=output_frames)
            $fatal(1,"Final result did not follow complete matched FFT frames");
        if(result_count<settled_checks) $fatal(1,"Result accounting mismatch");
        passed=1;
        $display("DYNAMIC_TEST_PASSED case=%0d results=%0d valid=%0d invalid=%0d checks=%0d fft_frames=%0d tracking_results=%0d reacquire=%0d timeouts=%0d min_interval_ms=%0.6f max_interval_ms=%0.6f",
            test_case,result_count,valid_count,invalid_count,settled_checks,output_frames,
            tracking_results,reacquire_count,timeout_count,min_interval_ns/1000000.0,max_interval_ns/1000000.0);
        $fclose(results_fd); $fclose(events_fd); $finish;
    end

    initial begin
        #150000000;
        $fatal(1,"Dynamic regression global timeout (150 ms)");
    end
endmodule
