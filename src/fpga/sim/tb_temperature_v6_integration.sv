`timescale 1ns/1ps
// Real top and UNISIM clocks/ADC/DAC; FFT remains disabled in this smoke test.
module tb_temperature_v6_integration;
    reg sys_clk=0,adc_dco=0,dac_ref=0,key_reset_n=0;
    always #2.5 sys_clk=~sys_clk;
    always #2 adc_dco=~adc_dco;
    always #2 dac_ref=~dac_ref;
    reg signed [31:0] temperature=25000;
    reg temp_valid=0,temp_sensor_fault=0;
    wire heater,fault;
    laser_lock_hw_top #(.ENABLE_ILA(0),.ENABLE_VIO(0),.TEMP_TIMEOUT_CYCLES(100)) dut(
        .sys_clk_p(sys_clk),.sys_clk_n(~sys_clk),.key_reset_n(key_reset_n),
        .adc_dco_p(adc_dco),.adc_dco_n(~adc_dco),
        .adc_data_p(14'd0),.adc_data_n(14'h3fff),
        .fpga_clk_p(dac_ref),.fpga_clk_n(~dac_ref),
        .temp_temperature_mc(temperature),.temp_sample_valid(temp_valid),
        .temp_sensor_fault(temp_sensor_fault),.temp_heater_pwm(heater),.temp_fault(fault));
    reg toggle=0;reg [7:0] addr=0;reg [31:0] data=0;
    initial begin
        force dut.request_toggle=toggle;
        force dut.request_addr=addr;force dut.request_data=data;
    end
    task tick;begin @(posedge dut.clk_work);#1;end endtask
    task write_reg(input [7:0] a,input [31:0] d,input bit expected_error);
        integer n;
        begin
            @(negedge dut.clk_work);addr=a;data=d;toggle=~toggle;
            repeat(5)tick();
            if(!dut.last_cfg_ack || dut.last_cfg_error!==expected_error || dut.cfg_pending)
                $fatal(1,"VIO route %h ack=%b err=%b pending=%b",a,dut.last_cfg_ack,dut.last_cfg_error,dut.cfg_pending);
        end
    endtask
    initial begin
        #100;key_reset_n=1;
        wait(dut.hw_rst===0);repeat(5)tick();
        if(heater || dut.u_temperature.enabled || dut.temp_duty!=0)$fatal(1,"Default off");
        write_reg(8'h5c,1,1);
        write_reg(8'h9c,20000,0); // former scan decoder region
        write_reg(8'h94,655,0);
        write_reg(8'h98,65536,0);
        write_reg(8'h68,40000,0);
        write_reg(8'h6c,262144,0);
        write_reg(8'hf8,32'h54454d50,0); // former auto decoder region
        write_reg(8'h5c,1,0);
        @(negedge dut.clk_work);temp_valid=1;tick();
        @(negedge dut.clk_work);temp_valid=0;tick();
        if(fault || dut.temp_duty!=20000)$fatal(1,"Top temperature feedback");
        @(negedge dut.clk_work);addr=8'hfc;#1;
        if(dut.cfg_rdata!=25000)$fatal(1,"Temperature readback");
        write_reg(8'h9c,40000,1);
        write_reg(8'h70,1,0); // original FFT enable and readback remain routed
        @(negedge dut.clk_work);addr=8'h70;#1;
        if(dut.cfg_rdata!=1)$fatal(1,"Original FFT register");
        write_reg(8'h70,0,0);
        write_reg(8'h84,1234,0);
        if(dut.scan_half_span!=1234)$fatal(1,"Original scan register");
        write_reg(8'ha4,-32'sd1000,0);
        if(dut.safe_lo!=-1000)$fatal(1,"Original auto register");
        write_reg(8'h00,12345,0);
        @(negedge dut.clk_work);addr=8'h00;#1;
        if(dut.cfg_rdata!=12345)$fatal(1,"Original servo register");
        // Temperature writes must not alter RF SPI/DAC permissions.
        if(dut.hw_control!=0 || dut.sequence_done || dut.tx_active || dut.status[1])
            $fatal(1,"Temperature changed RF permissions");
        repeat(101)tick();
        if(!fault || heater || dut.temp_duty!=0)$fatal(1,"Top timeout shutdown");
        $display("ALL TESTS PASSED: V6 real-top VIO routing, temperature and RF isolation");$finish;
    end
    initial begin #100000;$fatal(1,"Integration watchdog");end
endmodule
