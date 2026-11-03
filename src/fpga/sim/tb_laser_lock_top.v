`timescale 1ns/1ps
// Self-checking Verilog-2001 testbench. A 64-bit software-style reference
// evaluates an entire accepted sample independently of the RTL state machine.
module tb_laser_lock_top;
    reg clk_p=0;
    always #2.5 clk_p=~clk_p;
    wire clk_n=~clk_p;
    reg rst_n=0;
    reg signed [13:0] adc_data=0;
    reg adc_valid=0;
    wire adc_ready;
    wire signed [15:0] dac_data;
    wire dac_valid, clk_work, locked;
    reg cfg_we=0;
    reg [7:0] cfg_addr=0;
    reg [31:0] cfg_wdata=0;
    wire [31:0] cfg_rdata;
    wire cfg_ready,cfg_ack,cfg_error;
    wire signed [31:0] ila_error=dut.u_core.ila_error;
    wire signed [31:0] ila_output=dut.u_core.ila_control_output;
    wire signed [47:0] ila_integral=dut.u_core.ila_integral;
    wire [7:0] status;
    laser_lock_board_top #(.ENABLE_ILA(0)) dut(
        .clk_200m_p(clk_p), .clk_200m_n(clk_n), .rst_n(rst_n),
        .adc_data_in(adc_data), .adc_valid(adc_valid), .adc_ready(adc_ready),
        .dac_data_out(dac_data), .dac_valid(dac_valid),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .cfg_rdata(cfg_rdata), .cfg_ready(cfg_ready), .cfg_ack(cfg_ack), .cfg_error(cfg_error),
        .clk_work_out(clk_work), .clock_locked(locked), .status(status));

    integer checked=0,accepted=0,aborted=0;
    integer result_file,csv_file,i,j,n,seed=32'h2468ace1;
    integer last_result,measured,previous_command,tail_slew_max=0;
    real plant,disturbance,noise,early_energy=0.0,tail_energy=0.0;
    real early_rms,tail_rms;
    reg pending=0,initialized=0;
    integer ref_pointer=0;
    reg signed [63:0] hist[0:7];
    reg signed [63:0] ref_i=0,ref_e1=0,ref_e2=0;
    reg signed [63:0] corrected,filtered,e,p,delta_i,d,d2,trial,candidate,non_i,total;
    reg signed [63:0] bound,ibound,sum,expected_u,expected_i,expected_e;
    reg expected_input_clip,expected_error_clip,expected_i_clip,expected_anti,expected_clip;
    reg signed [31:0] ref_kp=65536,ref_ki=256,ref_kd=0,ref_k2=0;
    reg signed [15:0] ref_offset=0,ref_setpoint=0,ref_bias=0;
    reg [15:0] ref_limit=16384;
    reg [31:0] ref_ilimit=32767;
    reg [2:0] ref_control=0;

    task clear_model;
        begin
            if (pending) aborted=aborted+1;
            pending=0; initialized=0; ref_pointer=0;
            ref_i=0; ref_e1=0; ref_e2=0;
            for (j=0;j<8;j=j+1) hist[j]=0;
        end
    endtask
    task calculate_reference;
        begin
            if (pending) $fatal(1,"More than one sample in flight");
            corrected=$signed(adc_data);
            corrected=corrected-$signed(ref_offset);
            expected_input_clip=0;
            if (corrected>32767) begin corrected=32767; expected_input_clip=1; end
            if (corrected< -32768) begin corrected=-32768; expected_input_clip=1; end
            if (!initialized) begin
                for (j=0;j<8;j=j+1) hist[j]=corrected;
                initialized=1;
            end else begin
                hist[ref_pointer]=corrected;
                ref_pointer=(ref_pointer+1)%8;
            end
            sum=0;
            for (j=0;j<8;j=j+1) sum=sum+hist[j];
            filtered=ref_control[1] ? (sum >>> 3) : corrected;
            e=$signed(ref_setpoint);
            e=e-filtered;
            if (ref_control[2]) e=-e;
            expected_error_clip=0;
            if (e>32767) begin e=32767; expected_error_clip=1; end
            if (e< -32768) begin e=-32768; expected_error_clip=1; end
            p=$signed(ref_kp)*e;
            delta_i=$signed(ref_ki)*e;
            d=$signed(ref_kd)*(e-ref_e1);
            d2=$signed(ref_k2)*(e-2*ref_e1+ref_e2);
            ibound=ref_ilimit;
            ibound=ibound <<< 16;
            trial=ref_i+delta_i;
            candidate=trial;
            expected_i_clip=0;
            if (candidate>ibound) begin candidate=ibound; expected_i_clip=1; end
            if (candidate< -ibound) begin candidate=-ibound; expected_i_clip=1; end
            non_i=$signed(ref_bias);
            non_i=(non_i <<< 16)+p+d+d2;
            bound=ref_limit;
            bound=bound <<< 16;
            total=non_i+candidate;
            expected_anti=((total>bound)&&(delta_i>0)) || ((total< -bound)&&(delta_i<0));
            if (!expected_anti) ref_i=candidate;
            expected_i=ref_i;
            total=(non_i+ref_i) >>> 16;
            expected_clip=0;
            if (total>(bound >>> 16)) begin total=bound >>> 16; expected_clip=1; end
            if (total< -$signed({48'd0,ref_limit})) begin
                total=-$signed({48'd0,ref_limit}); expected_clip=1;
            end
            expected_u=total; expected_e=e;
            ref_e2=ref_e1; ref_e1=e;
            pending=1;
            accepted=accepted+1;
        end
    endtask
    always @(posedge clk_work) begin
        if (dut.u_core.rst) clear_model;
        else begin
            if (dac_valid) begin
                if (!pending) $fatal(1,"DAC output without accepted ADC sample");
                if ($signed(dac_data)!==expected_u || $signed(ila_integral)!==expected_i ||
                    $signed(ila_error)!==expected_e)
                    $fatal(1,"Arithmetic mismatch sample %0d: u %0d/%0d, I %0d/%0d, e %0d/%0d",
                        checked,$signed(dac_data),expected_u,$signed(ila_integral),expected_i,
                        $signed(ila_error),expected_e);
                if (status[7:3] !== {expected_error_clip,expected_input_clip,expected_i_clip,expected_anti,expected_clip})
                    $fatal(1,"Protection flags mismatch: %b",status);
                if (ila_output !== {{16{dac_data[15]}},dac_data}) $fatal(1,"Debug output mismatch");
                checked=checked+1; pending=0;
            end
            if (dut.u_core.clear) clear_model;
            else if (adc_valid && adc_ready) calculate_reference;
        end
    end

    task write_cfg;
        input [7:0] address;
        input [31:0] data;
        begin
            @(negedge clk_work); cfg_addr=address; cfg_wdata=data; cfg_we=1;
            while (!cfg_ready) @(negedge clk_work);
            @(posedge clk_work); #1;
            if (!cfg_ack || cfg_error) $fatal(1,"Configuration write failed at %h",address);
            case(address)
                8'h00: ref_kp=data;
                8'h04: ref_ki=data;
                8'h08: ref_kd=data;
                8'h0c: ref_k2=data;
                8'h10: ref_limit=data[15:0]>32767 ? 32767 : data[15:0];
                8'h14: ref_control=data[2:0];
                8'h18: ref_offset=data[15:0];
                8'h1c: ref_setpoint=data[15:0];
                8'h20: ref_bias=data[15:0];
                8'h24: ref_ilimit=data[31] ? 32'h7fffffff : data;
            endcase
            @(negedge clk_work); cfg_we=0;
        end
    endtask
    task read_check;
        input [7:0] address;
        input [31:0] expected;
        begin
            @(negedge clk_work); cfg_addr=address; #1;
            if (cfg_rdata !== expected) $fatal(1,"Register %h: %h expected %h",address,cfg_rdata,expected);
        end
    endtask
    task send_sample;
        input integer sample;
        begin
            @(negedge clk_work); adc_data=sample; adc_valid=1;
            while (!adc_ready) @(negedge clk_work);
            @(posedge clk_work);
            @(negedge clk_work); adc_valid=0;
            while (!dac_valid) @(negedge clk_work);
            last_result=$signed(dac_data);
        end
    endtask
    task gains;
        input [31:0] gp,gi,gd,g2;
        begin write_cfg(0,gp); write_cfg(4,gi); write_cfg(8,gd); write_cfg(12,g2); end
    endtask
    initial begin
        // A watchdog prevents silent hangs from being mistaken for a pass.
        #5000000;
        $fatal(1,"Simulation watchdog timeout");
    end
    initial begin
        csv_file=$fopen("closed_loop.csv","w");
        if (!csv_file) $fatal(1,"Cannot create closed_loop.csv");
        $fwrite(csv_file,"sample,adc_measurement,error,dac_output,integral_q16\n");
        #100; rst_n=1;
        wait(locked); wait(!dut.u_core.rst); repeat(4) @(negedge clk_work);
        read_check(8'h00,65536); read_check(8'h04,256); read_check(8'h14,0);
        if (adc_ready || dac_valid || dac_data!==0) $fatal(1,"Disabled startup behavior");

        // Invalid and read-only register writes acknowledge with an error.
        @(negedge clk_work); cfg_addr=8'h01; cfg_we=1; cfg_wdata=32'hdeadbeef;
        @(posedge clk_work); #1;
        if (!cfg_ack || !cfg_error) $fatal(1,"Unaligned address was accepted");
        @(negedge clk_work); cfg_we=0;
        read_check(0,65536);
        @(negedge clk_work); cfg_addr=8'h28; cfg_we=1;
        @(posedge clk_work); #1;
        if (!cfg_ack || !cfg_error) $fatal(1,"Read-only register write was accepted");
        @(negedge clk_work); cfg_we=0;

        // Signed P path and Q16 truncation, including odd negative values.
        gains(32768,0,0,0); write_cfg(8'h14,1);
        send_sample(7); send_sample(-7); send_sample(8191); send_sample(-8192); send_sample(0);
        $display("PASS: signed proportional path and endpoints");

        // Integrated moving-average model covers startup and circular wrap.
        write_cfg(8'h14,3);
        for(i=0;i<24;i=i+1) send_sample((i%2) ? -101 : 99);
        $display("PASS: moving average, startup and history wrap");

        // Offset, setpoint, inversion, and both preprocessing clipping signs.
        write_cfg(8'h18,32'hffff8000); write_cfg(8'h1c,32'hffff8000);
        send_sample(8191); send_sample(-8192);
        write_cfg(8'h14,5); send_sample(8191);
        write_cfg(8'h18,32767); write_cfg(8'h1c,32767); write_cfg(8'h14,1);
        send_sample(-8192); send_sample(8191);
        write_cfg(8'h18,0); write_cfg(8'h1c,0);

        // All four terms, output bias, and irregular valid gaps.
        gains(16384,2048,65536,32768); write_cfg(8'h20,17);
        for(i=0;i<40;i=i+1) begin
            repeat(i%5) @(negedge clk_work);
            send_sample((i%2) ? 8191 : -8192);
        end
        write_cfg(8'h20,0);
        // Expand e to full signed 16-bit extrema, exercising 17-/18-bit differences.
        write_cfg(8'h1c,32767); send_sample(-8192);
        write_cfg(8'h1c,32'hffff8000); send_sample(8191);
        // Reset between writes is intentional; the next phase alternates clipped
        // full-range errors by varying ADC offset around a zero setpoint.
        write_cfg(8'h1c,0); write_cfg(8'h18,32'hffff8000);
        gains(32'h7fffffff,32'h80000000,32'h7fffffff,32'h80000000);
        send_sample(8191); send_sample(-8192); send_sample(0);
        write_cfg(8'h18,0);
        $display("PASS: PI2D terms, signed extremes and wide arithmetic");

        // Integral hard limit with output far from saturation.
        gains(0,65536,0,0); write_cfg(8'h10,1000); write_cfg(8'h24,4);
        for(i=0;i<12;i=i+1) send_sample(-1);
        if ($signed(ila_integral)!==48'sd262144 || !status[5]) $fatal(1,"Positive integral clamp");
        for(i=0;i<16;i=i+1) send_sample(1);
        if ($signed(ila_integral)!==-48'sd262144 || !status[5]) $fatal(1,"Negative integral clamp");

        // Conditional integration: drive both rails, then reverse to recover.
        gains(65536,32768,0,0); write_cfg(8'h24,32767); write_cfg(8'h10,16);
        for(i=0;i<10;i=i+1) send_sample(-100);
        if (!status[4] || !status[3] || ila_integral!==0) $fatal(1,"Positive anti-windup");
        for(i=0;i<10;i=i+1) send_sample(100);
        if (!status[4] || !status[3] || ila_integral!==0) $fatal(1,"Negative anti-windup");
        send_sample(3);
        if (status[4] || ila_integral!==-48'sd98304) $fatal(1,"Integral recovery");
        write_cfg(8'h10,0); send_sample(100); send_sample(-100);
        if (dac_data!==0) $fatal(1,"Zero output limit");
        write_cfg(8'h10,65535); read_check(8'h10,32767);
        write_cfg(8'h24,32'hffffffff); read_check(8'h24,32'h7fffffff);
        $display("PASS: clipping, integral bounds, anti-windup and recovery");

        // Request configuration while busy. It must wait until the DAC retires.
        fork
            send_sample(123);
            begin
                wait(dut.u_core.busy);
                if(cfg_ready) $fatal(1,"Configuration ready during busy");
                write_cfg(8'h00,32768);
            end
        join
        // Disable rejects ADC and explicitly resets the output to zero.
        write_cfg(8'h14,0);
        repeat(4) @(negedge clk_work);
        if (adc_ready || dac_data!==0 || dac_valid || ila_integral!==0) $fatal(1,"Disable/clear");
        $display("PASS: configuration arbitration and disabled state");

        // Constant-cadence closed-loop abstract plant; no physical NKT claim.
        gains(32768,1024,0,0); write_cfg(8'h10,8000); write_cfg(8'h24,8000);
        write_cfg(8'h14,1);
        plant=2000.0; previous_command=0;
        for(n=0;n<1600;n=n+1) begin
            seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};
            noise=(seed & 7)-3;
            disturbance=20.0*$sin(n/120.0)+0.002*n;
            measured=$rtoi(plant+disturbance+noise);
            if (measured>8191 || measured< -8192) $fatal(1,"Plant outside ADC range");
            send_sample(measured);
            if(n<32) early_energy=early_energy+measured*measured;
            if(n>=1400) begin
                tail_energy=tail_energy+measured*measured;
                if ((last_result-previous_command)>tail_slew_max) tail_slew_max=last_result-previous_command;
                if ((previous_command-last_result)>tail_slew_max) tail_slew_max=previous_command-last_result;
            end
            $fwrite(csv_file,"%0d,%0d,%0d,%0d,%0d\n",n,measured,$signed(ila_error),last_result,$signed(ila_integral));
            plant=plant+0.20*last_result;
            previous_command=last_result;
            repeat(8) @(negedge clk_work);
        end
        repeat(4) @(negedge clk_work);
        early_rms=$sqrt(early_energy/32.0); tail_rms=$sqrt(tail_energy/200.0);
        if (tail_rms>=early_rms*0.15 || tail_rms>=15.0 || tail_slew_max>50)
            $fatal(1,"Closed-loop failed: early RMS %f tail RMS %f tail slew %0d",early_rms,tail_rms,tail_slew_max);
        if (pending || checked!=accepted-aborted) $fatal(1,"Sample accounting failed");
        result_file=$fopen("simulation_result.txt","w");
        if(!result_file) $fatal(1,"Cannot create simulation result");
        $fwrite(result_file,"PASS\nChecked samples: %0d\nAccepted samples: %0d\nAborted samples: %0d\n",checked,accepted,aborted);
        $fwrite(result_file,"Initial 32-sample RMS (ADC counts): %f\nFinal 200-sample RMS (ADC counts): %f\n",early_rms,tail_rms);
        $fwrite(result_file,"Final-window maximum output step (DAC counts): %0d\n",tail_slew_max);
        $fwrite(result_file,"Tests: reset/startup, register access, signed arithmetic, moving average, offsets, setpoint, inversion, full PI2D, integral limits, anti-windup, output limits, busy configuration, disable, abstract closed-loop convergence.\n");
        $fclose(result_file); $fclose(csv_file);
        $display("ALL TESTS PASS: %0d samples; early RMS %f; tail RMS %f; tail slew %0d",checked,early_rms,tail_rms,tail_slew_max);
        $finish;
    end
endmodule
