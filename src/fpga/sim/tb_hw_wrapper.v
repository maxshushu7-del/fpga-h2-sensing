`timescale 1ns/1ps
// Real UNISIM integration regression: unchanged core + physical hardware top.
// Peripheral SPI is checked separately by tb_hw_startup; this test bypasses
// only sequence_done and drives the same internal wires normally owned by VIO.
module tb_hw_wrapper;
    reg sys_clk=0,adc_dco=0,dac_reference=0,key_reset_n=0;
    always #2.5 sys_clk=~sys_clk;
    always #2 adc_dco=~adc_dco;
    always #2 dac_reference=~dac_reference;
    reg [13:0] adc_word=14'd123;
    // Rising DCO captures A=123, falling DCO captures B=-321. Each word is
    // stable 600ps before the corresponding sampling edge.
    initial begin
        #1.4; adc_word=14'd123;
        forever begin #2 adc_word=-14'sd321; #2 adc_word=14'd123; end
    end
    wire [15:0] dac_p,dac_n;
    wire dci_p,dci_n,frame_p,frame_n,sclk,sdio,clock_cs,adc_cs,dac_cs,ready_led,servo_led;
    laser_lock_hw_top #(.ENABLE_ILA(0),.ENABLE_VIO(0)) dut(
        .sys_clk_p(sys_clk),.sys_clk_n(~sys_clk),.key_reset_n(key_reset_n),
        .adc_dco_p(adc_dco),.adc_dco_n(~adc_dco),.adc_data_p(adc_word),.adc_data_n(~adc_word),
        .fpga_clk_p(dac_reference),.fpga_clk_n(~dac_reference),
        .dac_data_p(dac_p),.dac_data_n(dac_n),.dac_dci_p(dci_p),.dac_dci_n(dci_n),
        .dac_frame_p(frame_p),.dac_frame_n(frame_n),.spi_clk(sclk),.spi_sdio(sdio),
        .clk_cs_n(clock_cs),.adc_cs_n(adc_cs),.dac_cs_n(dac_cs),
        .led_ready(ready_led),.led_servo(servo_led));

    reg tb_request=0;
    reg [7:0] tb_addr=0;
    reg [31:0] tb_data=0;
    reg [1:0] tb_control=0;
    reg check_pads=0,expect_zero=1;
    reg [15:0] published[0:1023];
    integer published_count=0,physical_i_checks=0,physical_q_checks=0,adc_checks=0;
    integer nonzero_observations=0,request_checks=0,f,i,found;
    real last_adc_dco_rise=0.0,last_dac_data_rise=0.0;
    integer adc_phase_checks=0,dac_phase_checks=0;
    always @(posedge adc_dco) last_adc_dco_rise=$realtime;
    always @(posedge dut.tx_clk) last_dac_data_rise=$realtime;
    always @(posedge dut.adc_clk) if(check_pads && key_reset_n && dut.u_rx.rx_clock_locked) begin
        if(($realtime-last_adc_dco_rise)<0.365 || ($realtime-last_adc_dco_rise)>0.385)
            $fatal(1,"Wrapper ADC MMCM capture phase expected375ps: %f ns",$realtime-last_adc_dco_rise);
        adc_phase_checks=adc_phase_checks+1;
    end
    always @(posedge dut.u_tx.dci_clk) if(check_pads && key_reset_n && dut.tx_locked) begin
        if(($realtime-last_dac_data_rise)<0.865 || ($realtime-last_dac_data_rise)>0.885)
            $fatal(1,"Wrapper DAC DCI phase expected875ps: %f ns",$realtime-last_dac_data_rise);
        dac_phase_checks=dac_phase_checks+1;
    end
    initial begin
        force dut.request_toggle=tb_request;
        force dut.request_addr=tb_addr;
        force dut.request_data=tb_data;
        force dut.hw_control=tb_control;
        force dut.sequence_done=1'b1;
    end
    initial begin #5000000; $fatal(1,"Hardware wrapper watchdog at 5ms"); end

    // Record full words published by the 100MHz core. Physical I words must
    // come from this history: independent of the serializer's held register.
    always @(posedge dut.clk_work) begin
        if(!key_reset_n || dut.u_core.rst) published_count=0;
        else if(dut.dac_valid) begin
            if(published_count>=1024) $fatal(1,"Published-word history overflow");
            published[published_count]=dut.dac_command;
            published_count=published_count+1;
        end
        if(key_reset_n && !dut.u_core.rst && dut.adc_valid && dut.adc_ready) begin
            if(dut.adc_sample!==14'd123) $fatal(1,"ADC interface selected/tore wrong channel: %h",dut.adc_sample);
            adc_checks=adc_checks+1;
        end
    end
    always @(posedge dci_p) if(check_pads && key_reset_n && dut.tx_locked) begin
        #0.010;
        if(dac_n!==~dac_p || dci_n!==0 || frame_p!==0 || frame_n!==1)
            $fatal(1,"Wrapper DAC differential/FRAME mismatch");
        if(expect_zero && dac_p!==16'h0000) $fatal(1,"DAC output must be gated zero: %h",dac_p);
        if(dac_p!==16'h0000) begin
            found=0;
            for(i=0;i<published_count;i=i+1) if(published[i]===dac_p)found=1;
            if(!found) $fatal(1,"Physical I word %h never published by the core",dac_p);
            nonzero_observations=nonzero_observations+1;
        end
        physical_i_checks=physical_i_checks+1;
    end
    always @(negedge dci_p) if(check_pads && key_reset_n && dut.tx_locked) begin
        #0.010;
        if(dac_p!==16'h0000 || dac_n!==16'hffff || dci_n!==1)
            $fatal(1,"Physical DAC Q must be complete zero word: %h",dac_p);
        physical_q_checks=physical_q_checks+1;
    end

    task read_register;
        input [7:0] address;
        input [31:0] expected;
        begin
            wait(!dut.cfg_pending); @(negedge dut.clk_work); tb_addr=address; #1;
            if(dut.cfg_rdata!==expected) $fatal(1,"Read %h=%h expected%h",address,dut.cfg_rdata,expected);
        end
    endtask
    task write_register;
        input [7:0] address;
        input [31:0] value;
        input expected_error;
        input check_clear;
        integer timeout;
        begin
            wait(!dut.cfg_pending); @(negedge dut.clk_work);
            tb_addr=address;tb_data=value;tb_request=~tb_request;
            timeout=0;
            while(!dut.cfg_pending && timeout<20) begin @(negedge dut.clk_work);timeout=timeout+1;end
            if(!dut.cfg_pending) $fatal(1,"VIO toggle did not generate pending request");
            if(dut.last_cfg_ack || dut.last_cfg_error) $fatal(1,"New VIO request did not clear sticky result");
            if(check_clear) begin
                // Permit the two-stage DAC enable synchronizer and one ODDR
                // edge to drain. Check before any new 100kHz servo update.
                repeat(6) @(posedge dci_p);
                #0.010;
                if(dac_p!==0) $fatal(1,"Configuration write retained stale physical I=%h",dac_p);
            end
            timeout=0;
            while((dut.cfg_pending || !dut.last_cfg_ack) && timeout<4096) begin
                @(negedge dut.clk_work);timeout=timeout+1;
            end
            if(timeout>=4096) $fatal(1,"Configuration completion timeout at %h",address);
            if(dut.last_cfg_error!==expected_error) $fatal(1,"Configuration error result at %h",address);
            repeat(8) @(negedge dut.clk_work);
            if(!dut.last_cfg_ack || dut.last_cfg_error!==expected_error || dut.cfg_pending)
                $fatal(1,"Configuration sticky acknowledgment/error unstable");
            request_checks=request_checks+1;
        end
    endtask
    task require_code;
        input [15:0] code;
        integer timeout;
        reg matched;
        begin
            timeout=0;matched=0;
            while(!matched && timeout<20000) begin
                @(posedge dci_p);#0.010;matched=(dac_p===code);timeout=timeout+1;
            end
            if(!matched)$fatal(1,"Physical DAC never reached %h, last%h",code,dac_p);
        end
    endtask
    initial begin
        #100;key_reset_n=1;
        wait(dut.core_locked && dut.tx_locked && !dut.hw_rst);
        check_pads=1;
        if(dut.status[1] || dut.hw_control!==0 || servo_led) $fatal(1,"Unsafe startup defaults");
        wait(ready_led);
        if($realtime<1000000) $fatal(1,"Clock health passed before real 1ms observation");
        if(!dut.clocks_ok || dut.adc_beats<230 || dut.tx_beats<230)
            $fatal(1,"Real-rate clocks failed health validation");
        read_register(8'h40,1000); // Combinational read needs no request toggle.
        if(tb_request!==0 || dut.cfg_pending || dut.last_cfg_ack) $fatal(1,"Read generated a write");
        read_register(8'h14,0);read_register(8'h00,65536);

        // First prove a running core cannot leak commands without permission.
        write_register(8'h14,1,0,0);
        repeat(2500) @(negedge dut.clk_work);
        if(published_count<2 || nonzero_observations!=0) $fatal(1,"DAC permission gate/core publications");
        @(negedge dut.clk_work);tb_control=2;expect_zero=0;
        wait(servo_led);
        repeat(3000) @(negedge dut.clk_work);
        if(nonzero_observations<10 || adc_checks<10) $fatal(1,"Integrated ADC/core/DAC path inactive");

        // Kp=0 clears the existing core and immediately drains physical gating.
        // Ki remains its default: the equation itself is not changed.
        write_register(8'h00,0,0,1);
        read_register(8'h00,0);
        // A deterministic bias establishes a distinct nonzero published word.
        write_register(8'h04,0,0,1);
        write_register(8'h20,16'h1357,0,1);
        require_code(16'h1357);
        write_register(8'h14,0,0,1);
        expect_zero=1;
        repeat(40) @(negedge dut.clk_work);
        if(dut.dac_command!==0 || dut.status[1] || servo_led) $fatal(1,"Core disable retained previous code");
        read_register(8'h14,0);
        write_register(8'h7c,32'hdeadbeef,1,0);
        read_register(8'h20,16'h1357);
        write_register(8'h48,0,1,0); // Invalid polarity value must be visible.
        read_register(8'h48,1);
        write_register(8'h20,0,0,1); // Successful next request clears error.

        // Re-enable with a known command, reset while a real output is active,
        // and verify key reset, both MMCMs and every default configuration.
        write_register(8'h20,16'h2468,0,1);
        write_register(8'h14,1,0,1);expect_zero=0;
        require_code(16'h2468);
        check_pads=0;
        @(negedge dut.clk_work);key_reset_n=0;tb_control=0;
        #5;
        if(dac_p!==0 || dci_p!==0 || frame_p!==0) $fatal(1,"KEY1 asynchronous DAC reset failed");
        #100;key_reset_n=1;
        wait(dut.core_locked && dut.tx_locked && !dut.hw_rst);
        expect_zero=1;check_pads=1;
        wait(ready_led);
        read_register(8'h00,65536);read_register(8'h04,256);
        read_register(8'h14,0);read_register(8'h20,0);read_register(8'h40,1000);
        if(dut.last_cfg_ack || dut.last_cfg_error || dut.cfg_pending || servo_led || dut.dac_command!==0)
            $fatal(1,"KEY1 reset did not restore controller/bridge defaults");
        repeat(64) @(posedge dci_p);
        f=$fopen("hw_wrapper_result.txt","w");
        if(!f)$fatal(1,"Cannot write wrapper result");
        if(adc_phase_checks<100 || dac_phase_checks<100) $fatal(1,"Insufficient actual phase observations");
        $fwrite(f,"PASS\nReal UNISIM integrated wrapper: board200MHz ADC250MHz DAC250MHz; core100MHz; 1ms clock health and reset/relock.\n");
        $fwrite(f,"Measured MMCM phase checks: ADCcapture375ps=%0d DACDCI875ps=%0d\n",adc_phase_checks,dac_phase_checks);
        $fwrite(f,"ADC accepted checks: %0d\nPhysical I checks: %0d\nPhysical Q checks: %0d\nNonzero coherent I observations: %0d\nVIO request checks: %0d\n",adc_checks,physical_i_checks,physical_q_checks,nonzero_observations,request_checks);
        $fwrite(f,"Default-off permissions; combinational register read; toggle/pending/ack/error bridge; configuration clear gating; core disable clears stale code; invalid write visible; KEY1 defaults. SPI sequence_done alone bypassed: serial transactions have their separate regression.\n");
        $fclose(f);
        $display("HARDWARE WRAPPER PASS: ADC=%0d I=%0d Q=%0d requests=%0d",adc_checks,physical_i_checks,physical_q_checks,request_checks);
        $finish;
    end
endmodule
