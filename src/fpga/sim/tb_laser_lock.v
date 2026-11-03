`timescale 1ns/1ps
// End-to-end independent fixed-point scoreboard and four noisy optical loops.
module tb_laser_lock;
    reg clk_p=0;
    always #2.5 clk_p=~clk_p;
    wire clk_n=~clk_p;
    reg rst_n=0,adc_valid=0,cfg_we=0;
    reg signed [13:0] adc_data=0;
    reg [7:0] cfg_addr=0;
    reg [31:0] cfg_wdata=0;
    wire adc_ready,dac_valid,cfg_ready,cfg_ack,cfg_error,clk_work,locked;
    wire signed [15:0] dac_data;
    wire [31:0] cfg_rdata;
    wire [7:0] status;
    laser_lock_board_top #(.ENABLE_ILA(0)) dut(
        .clk_200m_p(clk_p),.clk_200m_n(clk_n),.rst_n(rst_n),
        .adc_data_in(adc_data),.adc_valid(adc_valid),.adc_ready(adc_ready),
        .dac_data_out(dac_data),.dac_valid(dac_valid),.cfg_we(cfg_we),
        .cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_rdata(cfg_rdata),
        .cfg_ready(cfg_ready),.cfg_ack(cfg_ack),.cfg_error(cfg_error),
        .clk_work_out(clk_work),.clock_locked(locked),.status(status));

    reg stream=0;
    integer source_mode=0,constant_sample=123,noise=0;
    real laser_position=0.0,resonance=0.0,thermal=0.0,optical_slope=1.0;
    always @(negedge clk_work) begin
        adc_valid=stream;
        if(source_mode==0) adc_data=constant_sample;
        else adc_data=$rtoi(1000.0+optical_slope*(laser_position-resonance+thermal))+noise;
    end
    // Model all controller/actuator arithmetic separately from RTL state.
    reg signed [63:0] rp=65536,rki=256,rd=0,r2=0,rscale=65536;
    reg signed [63:0] rlimit=16384,ralimit=16384,rilimit=32767,rbias=0;
    reg rinvert=0;
    integer rperiod=1000,input_count=0,output_count=0;
    reg signed [63:0] ri=0,e1=0,e2=0,e,p,di,d,d2,ibound,cand,base,total,code,projected;
    reg signed [63:0] expected_output,expected_integral;
    reg pending=0,iclip,anti,clip,physical_clip;
    reg [2:0] expected_flags;
    time last_output_time=0;
    always @(posedge clk_work) begin
        if(dut.u_core.rst || dut.u_core.clear) begin
            if(dut.u_core.clear && pending) $fatal(1,"configuration cleared an active transaction");
            ri=0; e1=0; e2=0; pending=0; last_output_time=0;
        end else begin
            if(adc_valid && adc_ready) input_count=input_count+1;
            if(dut.u_core.servo_error_valid) begin
                if(pending) $fatal(1,"overlapping servo transaction");
                e=$signed(dut.u_core.error_signal);
                p=rp*e; di=rki*e; d=rd*(e-e1); d2=r2*(e-2*e1+e2);
                ibound=rilimit <<< 16; cand=ri+di; iclip=0;
                if(cand>ibound) begin cand=ibound; iclip=1; end
                if(cand< -ibound) begin cand=-ibound; iclip=1; end
                base=p+d+d2+(rbias <<< 16); total=base+cand;
                code=total >>> 16;
                if(code>rlimit) code=rlimit;
                if(code< -rlimit) code=-rlimit;
                projected=code*rscale;
                if(rinvert) projected=-projected;
                anti=((total>(rlimit <<< 16)) && di>0) ||
                     ((total< -(rlimit <<< 16)) && di<0) ||
                     ((projected>(ralimit <<< 16)) && (rinvert ? di<0 : di>0)) ||
                     ((projected< -(ralimit <<< 16)) && (rinvert ? di>0 : di<0)) ||
                     ((rscale==0) && (di!=0));
                if(!anti) ri=cand;
                total=base+ri; code=total >>> 16; clip=0;
                if(code>rlimit) begin code=rlimit; clip=1; end
                if(code< -rlimit) begin code=-rlimit; clip=1; end
                projected=code*rscale;
                if(rinvert) projected=-projected;
                expected_output=projected >>> 16; physical_clip=0;
                if(expected_output>ralimit) begin expected_output=ralimit; physical_clip=1; end
                if(expected_output< -ralimit) begin expected_output=-ralimit; physical_clip=1; end
                expected_integral=ri; expected_flags={iclip,anti,clip|physical_clip};
                e2=e1; e1=e; pending=1;
            end
            if(dac_valid) begin
                if(!pending) $fatal(1,"DAC output without accepted servo input");
                if($signed(dac_data)!==expected_output ||
                   $signed(dut.u_core.ila_integral)!==expected_integral || status[5:3]!==expected_flags)
                    $fatal(1,"scoreboard output=%0d expected=%0d I=%0d expectedI=%0d flags=%b expected=%b",
                        $signed(dac_data),expected_output,$signed(dut.u_core.ila_integral),expected_integral,
                        status[5:3],expected_flags);
                if(last_output_time!=0 && $time-last_output_time!=rperiod*10)
                    $fatal(1,"servo cadence differs from configured period");
                last_output_time=$time; pending=0; output_count=output_count+1;
            end
        end
    end
    task write_cfg;
        input [7:0] addr;
        input [31:0] value;
        begin
            @(negedge clk_work); cfg_addr=addr;cfg_wdata=value;cfg_we=1;
            while(!cfg_ready) @(negedge clk_work);
            @(posedge clk_work); #1;
            if(!cfg_ack || cfg_error) $fatal(1,"config rejected addr=%h",addr);
            case(addr)
                8'h00:rp=$signed(value); 8'h04:rki=$signed(value);
                8'h08:rd=$signed(value); 8'h0c:r2=$signed(value);
                8'h10:rlimit=value>32767 ? 32767:value;
                8'h20:rbias=$signed(value[15:0]); 8'h24:rilimit=value;
                8'h40:rperiod=value<64 ? 64:value;
                8'h50:rscale=value; 8'h54:ralimit=value>32767 ? 32767:value;
                8'h58:rinvert=value[0];
                default:begin end
            endcase
            @(negedge clk_work);cfg_we=0;
        end
    endtask
    task read_check;
        input [7:0] addr;
        input [31:0] expected_value;
        begin
            @(negedge clk_work);cfg_addr=addr;#1;
            if(cfg_rdata!==expected_value) $fatal(1,"register %h=%h expected=%h",addr,cfg_rdata,expected_value);
        end
    endtask
    integer last_command=0;
    task wait_output;
        begin
            @(negedge clk_work);
            while(!dac_valid) @(negedge clk_work);
            last_command=$signed(dac_data);
            @(negedge clk_work);
        end
    endtask
    integer case_id,n,f,metrics,i,seed=13579,tail_step,delta,previous_command;
    real early_energy,tail_energy,early_rms,tail_rms,worst_rms=0.0,observed_error;
    initial begin
        #100;rst_n=1;
        wait(locked && !dut.u_core.rst);repeat(4) @(negedge clk_work);
        read_check(8'h40,1000);read_check(8'h44,65536);read_check(8'h48,1);
        read_check(8'h4c,1);read_check(8'h50,65536);read_check(8'h14,0);
        @(negedge clk_work);cfg_addr=8'h48;cfg_wdata=0;cfg_we=1;
        @(posedge clk_work);#1;
        if(!cfg_ack || !cfg_error || cfg_rdata!==1) $fatal(1,"invalid polarity not rejected");
        @(negedge clk_work);cfg_we=0;
        // Actual actuator saturation must stop integration, also after inversion.
        write_cfg(8'h04,65536);write_cfg(8'h10,1000);
        write_cfg(8'h54,100);write_cfg(8'h50,131072);write_cfg(8'h14,1);stream=1;
        repeat(12) begin
            wait_output;
            if(last_command!=-100 || dut.u_core.ila_integral!==0 || !status[4])
                $fatal(1,"actuator anti-windup failed");
        end
        write_cfg(8'h58,1);
        repeat(8) begin wait_output;
            if(last_command!=100 || dut.u_core.ila_integral!==0) $fatal(1,"inverted anti-windup failed");
        end
        write_cfg(8'h50,0);
        repeat(8) begin wait_output;
            if(last_command!=0 || dut.u_core.ila_integral!==0) $fatal(1,"zero-scale protection failed");
        end
        wait(dut.u_core.servo_error_valid);#1;
        if(cfg_ready) $fatal(1,"configuration ready during servo transaction");
        write_cfg(8'h00,32768);stream=0;write_cfg(8'h14,0);
        write_cfg(8'h04,1024);write_cfg(8'h10,8000);write_cfg(8'h24,8000);
        write_cfg(8'h54,8000);write_cfg(8'h50,65536);write_cfg(8'h58,0);
        write_cfg(8'h1c,1000);source_mode=1;
        f=$fopen("closed_loop.csv","w");
        metrics=$fopen("closed_loop_metrics.txt","w");
        $fwrite(f,"case,slope,update,detuning,error,dac,integral_q16\n");
        for(case_id=0;case_id<4;case_id=case_id+1) begin
            optical_slope=case_id<2 ? 1.0:-1.0;
            laser_position=(case_id%2)==0 ? 1200.0:-1200.0;
            resonance=0.0;thermal=0.0;noise=0;
            write_cfg(8'h48,case_id<2 ? 32'd1:32'hffffffff);
            write_cfg(8'h14,3);stream=1;
            early_energy=0.0;tail_energy=0.0;tail_step=0;previous_command=0;
            for(n=0;n<600;n=n+1) begin
                wait_output;observed_error=$signed(dut.u_core.ila_error);
                if(status[5] || $signed(dut.u_core.ila_integral)>=524288000 ||
                   $signed(dut.u_core.ila_integral)<=-524288000) $fatal(1,"closed-loop integral saturated");
                if(n<32) early_energy=early_energy+observed_error*observed_error;
                if(n>=500) begin
                    tail_energy=tail_energy+observed_error*observed_error;
                    delta=last_command-previous_command;if(delta<0)delta=-delta;
                    if(delta>tail_step)tail_step=delta;
                end
                $fwrite(f,"%0d,%0.0f,%0d,%0.6f,%0.0f,%0d,%0d\n",case_id,optical_slope,n,
                    laser_position-resonance+thermal,observed_error,last_command,$signed(dut.u_core.ila_integral));
                previous_command=last_command;
                laser_position=laser_position+0.2*last_command;
                resonance=15.0*$sin(n/160.0)+0.003*n;thermal=0.001*n;
                seed=(seed << 1)^((seed & 32'h40000000)!=0 ? 32'h000000af:0);
                noise=(seed & 7)-3;
            end
            early_rms=$sqrt(early_energy/32.0);tail_rms=$sqrt(tail_energy/100.0);
            if(tail_rms>=8.0 || tail_rms>=early_rms*0.08 || tail_step>=64)
                $fatal(1,"case %0d convergence RMS early=%0f tail=%0f maxstep=%0d",case_id,early_rms,tail_rms,tail_step);
            if(tail_rms>worst_rms)worst_rms=tail_rms;
            $fwrite(metrics,"case=%0d slope=%0.0f initial=%0d early_RMS=%0.4f tail_RMS=%0.4f max_DAC_step=%0d\n",
                case_id,optical_slope,(case_id%2)==0 ? 1200:-1200,early_rms,tail_rms,tail_step);
            $display("LOOP PASS case=%0d tail_RMS=%0.4f maxstep=%0d",case_id,tail_rms,tail_step);
            stream=0;write_cfg(8'h14,0);
        end
        $fclose(f);$fclose(metrics);
        if(input_count<=output_count || output_count<2400 || pending) $fatal(1,"stream/update accounting failed");
        f=$fopen("simulation_result.txt","w");
        $fwrite(f,"PASS: E15 side-of-fringe servo end-to-end simulation\n");
        $fwrite(f,"ADC samples=%0d; checked DAC outputs=%0d; default update rate=100 kHz\n",input_count,output_count);
        $fwrite(f,"Four slope/offset cases; resonance drift, thermal drift, noise; worst tail RMS=%0.4f ADC codes\n",worst_rms);
        $fwrite(f,"Independent PI2D/actuator scoreboard, configuration handshake and actuator anti-windup passed\n");
        $fclose(f);$display("PASS %0d outputs, worst tail RMS=%0f",output_count,worst_rms);$finish;
    end
    initial begin #60000000;$fatal(1,"simulation watchdog");end
endmodule
