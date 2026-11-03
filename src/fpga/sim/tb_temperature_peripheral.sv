`timescale 1ns/1ps
module tb_temperature_peripheral;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,cfg_we=0,sample_valid=0,sensor_fault=0;
    reg [7:0] cfg_addr=0;
    reg [31:0] cfg_wdata=0;
    reg signed [31:0] temperature_mc=25000;
    wire [31:0] cfg_rdata;
    wire cfg_error,heater_pwm,fault;
    wire [15:0] duty;
    temperature_peripheral #(.TIMEOUT_CYCLES(100)) dut(.*);
    task tick;begin @(posedge clk);#1;end endtask
    task write_reg(input [7:0] addr,input [31:0] data,input bit expect_error);
        begin
            @(negedge clk);cfg_addr=addr;cfg_wdata=data;cfg_we=1;#1;
            if(cfg_error!==expect_error)$fatal(1,"Register %h error=%b expected=%b",addr,cfg_error,expect_error);
            tick();@(negedge clk);cfg_we=0;tick();
        end
    endtask
    task sample;
        begin @(negedge clk);sample_valid=1;tick();
              @(negedge clk);sample_valid=0;tick();end
    endtask
    real t=25.0,ambient=25.0,peak=25.0;
    integer n,trace;
    task plant(input integer index,input real target);
        begin
            temperature_mc=$rtoi(t*1000.0);sample();
            if(fault || duty>32768)$fatal(1,"Thermal limit/fault");
            $fwrite(trace,"%0.1f,%0.4f,%0.1f,%0d\n",index*0.1,t,target,duty);
            t=t+0.1*(duty/65535.0-(t-ambient)/80.0);
            if(t>peak)peak=t;
        end
    endtask
    initial begin
        trace=$fopen("temperature_v6_trace.csv","w");
        if(!trace)$fatal(1,"Trace open");
        $fwrite(trace,"time_s,temperature_c,setpoint_c,duty\n");
        repeat(3)tick();@(negedge clk);rst=0;tick();
        if(duty!=0 || heater_pwm || dut.enabled)$fatal(1,"Boot output");
        write_reg(8'h5c,1,1); // disarmed / zero power limit
        write_reg(8'h9c,32768,0);
        write_reg(8'h68,40000,0);
        write_reg(8'h98,65536,0); // exercise nonzero D
        write_reg(8'hf8,32'h54454d50,0);
        write_reg(8'h5c,1,0);
        write_reg(8'h94,42,1); // configuration cannot change while enabled
        for(n=0;n<6000;n=n+1)plant(n,40.0);
        if(t<39.8 || t>40.2 || peak>43.0)$fatal(1,"Warmup T=%f peak=%f",t,peak);
        $display("PASS V6 PID warmup: T=%f peak=%f C",t,peak);
        ambient=20.0;
        for(n=6000;n<10000;n=n+1)plant(n,40.0);
        if(t<39.8 || t>40.2)$fatal(1,"Ambient disturbance");
        write_reg(8'h5c,0,0);write_reg(8'h68,30000,0);
        write_reg(8'h5c,1,1); // target change disarms
        write_reg(8'hf8,32'h54454d50,0);write_reg(8'h5c,1,0);
        for(n=10000;n<16000;n=n+1)plant(n,30.0);
        if(t<29.8 || t>30.2)$fatal(1,"New target");
        $display("PASS disturbance, target change and duty ceiling");
        repeat(101)tick();
        if(!fault || duty!=0 || heater_pwm)$fatal(1,"Timeout shutdown");
        write_reg(8'h5c,2,1); // cannot clear while enable bit still set
        write_reg(8'h5c,0,0);write_reg(8'h5c,2,0);
        write_reg(8'hf8,32'h54454d50,0);write_reg(8'h5c,1,0);
        if(duty!=0)$fatal(1,"Restart must wait for new sample");
        temperature_mc=80000;sample();
        if(!fault || duty!=0)$fatal(1,"Overtemperature");
        write_reg(8'h5c,0,0);write_reg(8'h5c,2,0);
        write_reg(8'h68,71000,1);write_reg(8'h6c,32'hffffffff,1);
        write_reg(8'hfc,0,1);
        write_reg(8'hf8,32'h54454d50,0);write_reg(8'h5c,1,0);
        temperature_mc=25000;sample();
        @(negedge clk);sensor_fault=1;#1;
        if(heater_pwm)$fatal(1,"Fault combinational gate");
        tick();if(!fault || duty!=0)$fatal(1,"Sensor fault latch");
        $display("PASS V6 configuration protection, timeout, overtemperature and sensor fault");
        $fclose(trace);
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #10000000;$fatal(1,"Watchdog");end
endmodule
