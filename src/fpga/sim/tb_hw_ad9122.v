`timescale 1ns/1ps
// Real UltraScale+ MMCM/ODDRE1 models test both 500MHz and 250MHz word mode.
module tb_hw_ad9122;
    wire done500,done250;
    wire [31:0] checks500,checks250;
    tb_hw_ad9122_case #(.INPUT_PERIOD_NS(2.0),.MULT_F(2.0),.DIVIDE(2),.DCI_DELAY_PS(125.0)) c500(
        .done(done500),.checked(checks500));
    tb_hw_ad9122_case #(.INPUT_PERIOD_NS(4.0),.MULT_F(4.0),.DIVIDE(4),.DCI_DELAY_PS(875.0)) c250(
        .done(done250),.checked(checks250));
    integer f;
    initial begin #1000000; $fatal(1,"AD9122 transmitter watchdog"); end
    initial begin
        wait(done500 && done250);
        f=$fopen("hw_ad9122_result.txt","w");
        if(!f) $fatal(1,"Cannot write AD9122 result");
        $fwrite(f,"PASS\n500MHz DDR observations: %0d\n250MHz DDR observations: %0d\n",checks500,checks250);
        $fwrite(f,"Real MMCM lock/relock; DCI delay500MHz=125ps/250MHz=875ps; receiver observations100ps/650ps afterDCI; I high/Q low two's-complement framing; signed limits; CDC hold/rapid latest-value updates; configuration gating; disable/re-enable; reset with outstanding transfer.\n");
        $fclose(f);
        $display("AD9122 TX TEST PASS: 500MHz=%0d, 250MHz=%0d",checks500,checks250);
        $finish;
    end
endmodule

module tb_hw_ad9122_case #(
    parameter real INPUT_PERIOD_NS=2.0,
    parameter real MULT_F=2.0,
    parameter integer DIVIDE=2,
    parameter real DCI_DELAY_PS=125.0
) (output reg done=0,output reg [31:0] checked=0);
    reg work_clk=0,reference_clk=0,rst_n=0;
    always #5 work_clk=~work_clk;
    always #(INPUT_PERIOD_NS/2.0) reference_clk=~reference_clk;
    reg signed [15:0] control=0;
    reg valid=0,enable=0,configured=0;
    wire ready,tx_clk,locked,active;
    wire [15:0] data_p,data_n;
    wire dci_p,dci_n,frame_p,frame_n;
    hw_ad9122_tx #(.INPUT_CLK_PERIOD_NS(INPUT_PERIOD_NS),.MMCM_MULT_F(MULT_F),
        .OUTPUT_DIVIDE(DIVIDE),.DCI_DELAY_PS(DCI_DELAY_PS)) dut(
        .clk_work(work_clk),.rst_n(rst_n),.fpga_clk_p(reference_clk),.fpga_clk_n(~reference_clk),
        .control_in(control),.control_valid(valid),.tx_enable(enable),.config_done(configured),
        .control_ready(ready),.tx_clk_out(tx_clk),.tx_clock_locked(locked),.tx_active(active),
        .dac_data_p(data_p),.dac_data_n(data_n),.dac_dci_p(dci_p),.dac_dci_n(dci_n),
        .dac_frame_p(frame_p),.dac_frame_n(frame_n));
    real data_edge=0.0,dci_edge=0.0,phase=0.0,last_dci_rise=0.0;
    integer observed_periods=0,i;
    reg monitor=0;
    reg [15:0] received_i;
    always @(posedge tx_clk) data_edge=$realtime;
    always @(posedge dci_p) begin
        dci_edge=$realtime;
        if(monitor && rst_n && locked) begin
            phase=dci_edge-data_edge;
            // ODDRE1/OBUFDS propagation is shared by data/DCI. Check physical
            // DCI against its dedicated generated MMCM clock independently.
            if(last_dci_rise!=0.0 &&
                (($realtime-last_dci_rise)<INPUT_PERIOD_NS-0.010 ||
                 ($realtime-last_dci_rise)>INPUT_PERIOD_NS+0.010))
                $fatal(1,"AD9122 input period%f: DCI frequency error",INPUT_PERIOD_NS);
            last_dci_rise=$realtime; observed_periods=observed_periods+1;
            // Observe the AD9122 input after its DCI edge, inside the receiving
            // window. At250MHz/.875ns, next DATA change is1.125ns afterDCI.
            #0.100;
            if(data_n!==~data_p || dci_n!==0 || frame_p!==0 || frame_n!==1)
                $fatal(1,"AD9122 differential/FRAME error");
            case(data_p)
                16'h0000,16'h5555,16'haaaa,16'h1234,16'hfedc,16'h8000,16'h7fff,
                16'h00ff,16'hff00,16'h0f0f,16'hf0f0: checked=checked+1;
                default: $fatal(1,"AD9122 CDC torn/unpublished code %h",data_p);
            endcase
            received_i=data_p;
            #0.550;
            if(monitor && rst_n && locked && data_p!==received_i)
                $fatal(1,"AD9122 I changed before650ps receiving-window boundary");
        end
    end
    always @(negedge dci_p) if(monitor && rst_n && locked) begin
        #0.100;
        if(data_p!==16'h0000 || data_n!==16'hffff || dci_n!==1)
            $fatal(1,"AD9122 Q half must be two's-complement zero: %h",data_p);
        checked=checked+1;
        #0.550;
        if(monitor && rst_n && locked && data_p!==16'h0000)
            $fatal(1,"AD9122 Q changed before650ps receiving-window boundary");
    end
    // MMCM simulation outputs are checked before ODDR propagation.
    always @(posedge dut.dci_clk) if(monitor && locked) begin
        if(($realtime-data_edge)<DCI_DELAY_PS/1000.0-0.010 ||
            ($realtime-data_edge)>DCI_DELAY_PS/1000.0+0.010)
            $fatal(1,"AD9122 DCI phase: %f ns expected%f ns",$realtime-data_edge,DCI_DELAY_PS/1000.0);
    end
    task send_code;
        input [15:0] value;
        begin
            @(negedge work_clk); control=value; valid=1;
            @(negedge work_clk); valid=0;
        end
    endtask
    task wait_code;
        input [15:0] expected;
        integer timeout;
        reg found;
        begin
            timeout=0; found=0;
            while(!found && timeout<1000) begin
                @(posedge dci_p); #0.100;
                found=(data_p===expected); timeout=timeout+1;
            end
            if(!found) $fatal(1,"AD9122 period%f code%h not applied (last%h)",INPUT_PERIOD_NS,expected,data_p);
        end
    endtask
    task hold_code;
        input [15:0] expected;
        begin
            repeat(32) begin
                @(posedge dci_p); #0.100;
                if(data_p!==expected) $fatal(1,"AD9122 held code changed: %h expected%h",data_p,expected);
            end
        end
    endtask
    initial begin
        #50; rst_n=1;
        wait(locked); repeat(10) @(negedge work_clk);
        monitor=1;
        send_code(16'h5555); hold_code(0);
        enable=1;
        send_code(16'haaaa); hold_code(0); // incomplete SPI configuration
        @(negedge work_clk); configured=1;
        repeat(20) @(negedge work_clk); hold_code(0);
        send_code(16'h5555); wait_code(16'h5555); hold_code(16'h5555);
        send_code(16'h8000); wait_code(16'h8000); hold_code(16'h8000);
        send_code(16'h7fff); wait_code(16'h7fff);
        send_code(16'hfedc); wait_code(16'hfedc);
        send_code(16'h00ff); wait_code(16'h00ff);
        send_code(16'hff00); wait_code(16'hff00);
        // Continuous 100MHz publications exceed mailbox throughput. Pending
        // latest-value policy may skip updates but cannot tear any 16-bit word.
        @(negedge work_clk); valid=1;
        for(i=0;i<40;i=i+1) begin
            control=i[0] ? 16'haaaa : 16'h5555;
            @(negedge work_clk);
        end
        control=16'h1234;
        @(negedge work_clk); valid=0;
        wait_code(16'h1234); hold_code(16'h1234);
        @(negedge work_clk); enable=0;
        repeat(20) @(negedge work_clk); hold_code(0);
        send_code(16'hf0f0); hold_code(0);
        @(negedge work_clk); enable=1;
        repeat(20) @(negedge work_clk); hold_code(0); // no stale restoration
        send_code(16'h0f0f); wait_code(16'h0f0f);
        @(negedge work_clk); configured=0;
        repeat(20) @(negedge work_clk); hold_code(0);
        @(negedge work_clk); configured=1;
        repeat(20) @(negedge work_clk); hold_code(0);
        send_code(16'hf0f0); wait_code(16'hf0f0);
        // Asynchronous reset cancels outstanding CDC messages and serializer.
        @(negedge work_clk); control=16'haaaa; valid=1;
        @(negedge work_clk); valid=0; monitor=0; rst_n=0;
        #5;
        if(data_p!==0 || dci_p!==0 || frame_p!==0 || active)
            $fatal(1,"AD9122 asynchronous safe reset failed");
        #50; rst_n=1;
        wait(locked); repeat(20) @(negedge work_clk);
        last_dci_rise=0.0; monitor=1;
        hold_code(0);
        send_code(16'h5555); wait_code(16'h5555); hold_code(16'h5555);
        if(observed_periods<100) $fatal(1,"Too few AD9122 clock observations");
        monitor=0; done=1;
        $display("AD9122 word-mode period=%f ns DCI=%fps PASS observations=%0d",INPUT_PERIOD_NS,DCI_DELAY_PS,checked);
    end
endmodule
