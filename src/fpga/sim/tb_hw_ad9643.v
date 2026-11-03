`timescale 1ns/1ps
// Real UNISIM IBUFDS/BUFG/IDDRE1 test, plus asynchronous mailbox/backpressure.
// 250 MHz DDR source and 100 MHz destination; no behavioural PHY replacement.
module tb_hw_ad9643;
    reg rst_n=0,config_done=0,adc_dco_p=0,clk_work=0;
    always #2 adc_dco_p=~adc_dco_p;
    always #5 clk_work=~clk_work;
    wire adc_dco_n=~adc_dco_p;
    reg [13:0] adc_data_p=14'h2000;
    wire [13:0] adc_data_n=~adc_data_p;
    reg ready0=1,ready1=1;
    wire adc_clk0,adc_clk1,valid0,valid1,rx_ready0,rx_ready1,overflow0,overflow1;
    wire rx_clock_locked0,rx_clock_locked1;
    wire signed [13:0] data0,data1;
    wire [13:0] raw_a0,raw_b0,raw_a1,raw_b1;
    wire [31:0] dropped0,dropped1;
    hw_ad9643_rx dut256(.rst_n(rst_n),.clk_work(clk_work),.config_done(config_done),
        .adc_dco_p(adc_dco_p),.adc_dco_n(adc_dco_n),.adc_data_p(adc_data_p),
        .adc_data_n(adc_data_n),.adc_ready(ready0),.adc_clk_out(adc_clk0),
        .raw_data_a(raw_a0),.raw_data_b(raw_b0),.adc_data_out(data0),
        .adc_valid(valid0),.rx_ready(rx_ready0),.rx_clock_locked(rx_clock_locked0),
        .overflow_sticky(overflow0),.dropped_count(dropped0));
    // Also verify channel B, offset-binary conversion and minimum decimation.
    hw_ad9643_rx #(.DECIMATION(1),.CHANNEL_SELECT(1),.OFFSET_BINARY(1)) dut1
        (.rst_n(rst_n),.clk_work(clk_work),.config_done(config_done),
        .adc_dco_p(adc_dco_p),.adc_dco_n(adc_dco_n),.adc_data_p(adc_data_p),
        .adc_data_n(adc_data_n),.adc_ready(ready1),.adc_clk_out(adc_clk1),
        .raw_data_a(raw_a1),.raw_data_b(raw_b1),.adc_data_out(data1),
        .adc_valid(valid1),.rx_ready(rx_ready1),.rx_clock_locked(rx_clock_locked1),
        .overflow_sticky(overflow1),.dropped_count(dropped1));

    integer pattern_index=0;
    function [13:0] channel_a_pattern;
        input integer index;
        begin case(index%8)
            0:channel_a_pattern=14'h2000; // -8192
            1:channel_a_pattern=14'h1fff; // +8191
            2:channel_a_pattern=14'h3fff; // -1
            3:channel_a_pattern=14'h0000;
            4:channel_a_pattern=14'h0001;
            5:channel_a_pattern=14'h3000;
            6:channel_a_pattern=14'h1000;
            default:channel_a_pattern=index;
        endcase end
    endfunction
    function [13:0] channel_b_pattern;
        input integer index;
        begin case(index%8)
            0:channel_b_pattern=14'h0000; // offset binary -> -8192
            1:channel_b_pattern=14'h3fff; // offset binary -> +8191
            2:channel_b_pattern=14'h1fff; // offset binary -> -1
            3:channel_b_pattern=14'h2000; // offset binary -> 0
            4:channel_b_pattern=14'h2001; // offset binary -> +1
            5:channel_b_pattern=14'h1111;
            6:channel_b_pattern=14'h2eee;
            default:channel_b_pattern=14'h1555;
        endcase end
    endfunction
    reg [13:0] previous_rise=0,previous_fall=0,expected_raw_a,expected_raw_b;
    integer phy_warmup=0,phy_checks=0;
    reg [4:0] observed_extrema_a=0,observed_extrema_b=0;
    // Build the primitive reference at the real +375ps capture-clock edges,
    // and verify that each edge is still in the intended external A/B eye.
    always @(posedge adc_clk0) begin
        expected_raw_a=previous_rise;expected_raw_b=previous_fall;
        previous_rise=adc_data_p;
        if(!rst_n || dut256.source_rst) phy_warmup=0;
        else phy_warmup=phy_warmup+1;
        if(phy_warmup>2 && adc_data_p!==channel_a_pattern(pattern_index))
            $fatal(1,"shifted rising capture edge missed channel A eye");
        #0.25;
        if(phy_warmup>2) begin
            if(raw_a0!==expected_raw_a || raw_b0!==expected_raw_b ||
               raw_a1!==expected_raw_a || raw_b1!==expected_raw_b)
                $fatal(1,"DDR A/B phase mismatch A=%h/%h B=%h/%h",raw_a0,expected_raw_a,raw_b0,expected_raw_b);
            case(raw_a0)
                14'h2000:observed_extrema_a[0]=1;
                14'h1fff:observed_extrema_a[1]=1;
                14'h3fff:observed_extrema_a[2]=1;
                14'h0000:observed_extrema_a[3]=1;
                14'h0001:observed_extrema_a[4]=1;
                default:begin end
            endcase
            case(raw_b0)
                14'h0000:observed_extrema_b[0]=1;
                14'h3fff:observed_extrema_b[1]=1;
                14'h1fff:observed_extrema_b[2]=1;
                14'h2000:observed_extrema_b[3]=1;
                14'h2001:observed_extrema_b[4]=1;
                default:begin end
            endcase
            phy_checks=phy_checks+1;
        end
    end
    always @(negedge adc_clk0) begin
        previous_fall=adc_data_p;
        if(phy_warmup>2 && adc_data_p!==channel_b_pattern(pattern_index-1))
            $fatal(1,"shifted falling capture edge missed channel B eye");
    end
    always @(posedge adc_dco_p) begin
        #0.4;adc_data_p=channel_b_pattern(pattern_index);
    end
    always @(negedge adc_dco_p) begin
        pattern_index=pattern_index+1;
        #0.4;adc_data_p=channel_a_pattern(pattern_index);
    end

    reg [13:0] queue0[0:8191],queue1[0:8191];
    integer write0=0,write1=0,read0=0,read1=0,mailbox_checks0=0,mailbox_checks1=0;
    integer source_cycle=0,last_event0=0,last_event1=0,cadence_checks0=0,cadence_checks1=0;
    integer drop_ref0=0,drop_ref1=0;
    reg req_old0=0,req_old1=0,pending_ref_valid0=0,pending_ref_valid1=0;
    reg [13:0] pending_ref0=0,pending_ref1=0,expected_publish0,expected_publish1;
    reg expected_publish_valid0,expected_publish_valid1;
    reg sample_event0,sample_event1,free0,free1,active0,active1;
    reg [13:0] selected0,selected1,old_mailbox0,old_mailbox1;
    reg held_mailbox0,held_mailbox1;
    always @(posedge adc_clk0) begin
        source_cycle=source_cycle+1;
        sample_event0=dut256.sample_event;sample_event1=dut1.sample_event;
        free0=dut256.mailbox_free;free1=dut1.mailbox_free;
        active0=dut256.config_sync2 && dut256.source_ready;
        active1=dut1.config_sync2 && dut1.source_ready;
        selected0=raw_a0;selected1={~raw_b1[13],raw_b1[12:0]};
        old_mailbox0=dut256.mailbox_data;old_mailbox1=dut1.mailbox_data;
        held_mailbox0=!free0;held_mailbox1=!free1;
        expected_publish_valid0=0;expected_publish_valid1=0;
        if(!rst_n || dut256.source_rst) begin
            write0=0;req_old0=0;pending_ref_valid0=0;drop_ref0=0;last_event0=0;
        end else if(!active0) begin pending_ref_valid0=0;last_event0=0;end
        else begin
            if(sample_event0) begin
                if(last_event0 && source_cycle-last_event0!=256) $fatal(1,"DECIMATION=256 cadence");
                last_event0=source_cycle;cadence_checks0=cadence_checks0+1;
                if(pending_ref_valid0) drop_ref0=drop_ref0+1;
            end
            if(free0 && (sample_event0 || pending_ref_valid0)) begin
                expected_publish0=sample_event0 ? selected0:pending_ref0;
                expected_publish_valid0=1;pending_ref_valid0=0;
            end else if(sample_event0) begin pending_ref0=selected0;pending_ref_valid0=1;end
        end
        if(!rst_n || dut1.source_rst) begin
            write1=0;req_old1=0;pending_ref_valid1=0;drop_ref1=0;last_event1=0;
        end else if(!active1) begin pending_ref_valid1=0;last_event1=0;end
        else begin
            if(sample_event1) begin
                if(last_event1 && source_cycle-last_event1!=1) $fatal(1,"DECIMATION=1 cadence");
                last_event1=source_cycle;cadence_checks1=cadence_checks1+1;
                if(pending_ref_valid1) drop_ref1=drop_ref1+1;
            end
            if(free1 && (sample_event1 || pending_ref_valid1)) begin
                expected_publish1=sample_event1 ? selected1:pending_ref1;
                expected_publish_valid1=1;pending_ref_valid1=0;
            end else if(sample_event1) begin pending_ref1=selected1;pending_ref_valid1=1;end
        end
        #0.3;
        if(rst_n && !dut256.source_rst) begin
            if(held_mailbox0 && dut256.mailbox_data!==old_mailbox0) $fatal(1,"busy mailbox changed at DEC256");
            if(dut256.request_toggle!==req_old0) begin
                if(!expected_publish_valid0 || dut256.mailbox_data!==expected_publish0) $fatal(1,"DEC256 published wrong/latest item");
                if(write0>=8192) $fatal(1,"queue0 capacity");
                queue0[write0]=expected_publish0;write0=write0+1;
            end else if(expected_publish_valid0) $fatal(1,"DEC256 failed to publish");
            if(dut256.dropped_count_source!==drop_ref0) $fatal(1,"DEC256 drop count incorrect");
        end
        if(rst_n && !dut1.source_rst) begin
            if(held_mailbox1 && dut1.mailbox_data!==old_mailbox1) $fatal(1,"busy mailbox changed at DEC1");
            if(dut1.request_toggle!==req_old1) begin
                if(!expected_publish_valid1 || dut1.mailbox_data!==expected_publish1) $fatal(1,"DEC1 published wrong/latest item");
                if(write1>=8192) $fatal(1,"queue1 capacity");
                queue1[write1]=expected_publish1;write1=write1+1;
            end else if(expected_publish_valid1) $fatal(1,"DEC1 failed to publish");
            if(dut1.dropped_count_source!==drop_ref1) $fatal(1,"DEC1 drop count incorrect");
        end
        req_old0=dut256.request_toggle;req_old1=dut1.request_toggle;
    end

    reg ack_old0=0,ack_old1=0,hold_valid0,hold_valid1;
    reg signed [13:0] hold_data0,hold_data1;
    integer accepted0=0,accepted1=0;
    always @(posedge clk_work) begin
        hold_valid0=valid0 && !ready0;hold_valid1=valid1 && !ready1;
        hold_data0=data0;hold_data1=data1;
        if(!rst_n || dut256.work_rst) begin read0=0;read1=0;ack_old0=0;ack_old1=0;end
        else begin
            if(valid0 && ready0) accepted0=accepted0+1;
            if(valid1 && ready1) accepted1=accepted1+1;
        end
        #0.3;
        if(rst_n && !dut256.work_rst) begin
            if(config_done && hold_valid0 && (!valid0 || data0!==hold_data0)) $fatal(1,"DEC256 violated ready/data hold");
            if(config_done && hold_valid1 && (!valid1 || data1!==hold_data1)) $fatal(1,"DEC1 violated ready/data hold");
            if(!config_done && (valid0 || valid1 || data0!==0 || data1!==0)) $fatal(1,"config gate failed");
            if(dut256.acknowledge_toggle!==ack_old0) begin
                if(read0>=write0) $fatal(1,"unexpected DEC256 acknowledgement");
                if(config_done && (!valid0 || data0!==$signed(queue0[read0]))) $fatal(1,"DEC256 CDC torn/stale value");
                read0=read0+1;mailbox_checks0=mailbox_checks0+1;
            end
            if(dut1.acknowledge_toggle!==ack_old1) begin
                if(read1>=write1) $fatal(1,"unexpected DEC1 acknowledgement");
                if(config_done && (!valid1 || data1!==$signed(queue1[read1]))) $fatal(1,"DEC1 CDC torn/stale value");
                read1=read1+1;mailbox_checks1=mailbox_checks1+1;
            end
        end
        ack_old0=dut256.acknowledge_toggle;ack_old1=dut1.acknowledge_toggle;
    end

    integer f,previous_drops0,previous_drops1;
    initial begin
        // UNISIM glbl GSR deasserts at 100ns; external reset is held longer.
        #200;rst_n=1;
        wait(rx_clock_locked0 && rx_clock_locked1);
        repeat(12) @(negedge clk_work);
        if(rx_ready0 || rx_ready1 || valid0 || valid1) $fatal(1,"capture started before config_done");
        config_done=1;
        repeat(1800) @(negedge clk_work);
        if(!rx_ready0 || !rx_ready1 || accepted0<10 || accepted1<50) $fatal(1,"receiver failed to start");
        // Default decimation should run without drops when the destination drains.
        if(overflow0 || dropped0!==0) $fatal(1,"default decimation unexpectedly overflowed");
        if(!overflow1 || dropped1==0) $fatal(1,"DEC1 latest replacement was not reported");
        ready0=0;ready1=0;
        repeat(1000) @(negedge clk_work);
        if(!valid0 || !valid1 || !overflow0 || dropped0==0) $fatal(1,"backpressure/pending overwrite missing");
        previous_drops0=dropped0;previous_drops1=dropped1;
        ready0=1;ready1=1;
        repeat(1200) @(negedge clk_work);
        if(dropped0<previous_drops0 || dropped1<previous_drops1) $fatal(1,"Gray-counter CDC moved backwards");
        // Pending traffic is discarded by the configuration gate and drained.
        ready0=0;ready1=0;
        repeat(300) @(negedge clk_work);
        config_done=0;
        repeat(30) @(negedge clk_work);
        if(rx_ready0 || rx_ready1 || valid0 || valid1) $fatal(1,"configuration disable failed");
        ready0=1;ready1=1;config_done=1;
        repeat(600) @(negedge clk_work);
        // External reset cancels the complete asynchronous transaction in both domains.
        rst_n=0;#1;
        if(valid0 || valid1 || data0!==0 || data1!==0) $fatal(1,"async reset did not cancel output");
        repeat(10) @(negedge clk_work);rst_n=1;
        wait(rx_clock_locked0 && rx_clock_locked1);
        repeat(1800) @(negedge clk_work);
        if(overflow0 || dropped0!==0 || !rx_ready0 || !rx_ready1) $fatal(1,"reset/restart default state failed");
        if(observed_extrema_a!==5'b11111 || observed_extrema_b!==5'b11111) $fatal(1,"signed/offset extrema coverage missing");
        if(cadence_checks0<50 || cadence_checks1<1000 || mailbox_checks0<30 || mailbox_checks1<100) $fatal(1,"insufficient hardware coverage");
        f=$fopen("ad9643_result.txt","w");
        if(!f) $fatal(1,"cannot write hardware result");
        $fwrite(f,"PASS: real UNISIM AD9643 Parallel Interleaved LVDS + CDC\n");
        $fwrite(f,"250MHz DDR with MMCM deskew/+375ps capture phase/100MHz core; PHY pairs=%0d; mailbox DEC256=%0d DEC1=%0d\n",phy_checks,mailbox_checks0,mailbox_checks1);
        $fwrite(f,"Cadence events DEC256=%0d DEC1=%0d; accepted DEC256=%0d DEC1=%0d\n",cadence_checks0,cadence_checks1,accepted0,accepted1);
        $fwrite(f,"Coverage: A/B edge alignment, two-complement extrema, B offset-binary conversion, config/reset/restart, DEC256/DEC1, stable ready/data, request/ack mailbox hold, latest pending selection, exact drops/Gray CDC.\n");
        $fclose(f);
        $display("AD9643 HARDWARE TEST PASS: PHY %0d, mailbox %0d/%0d",phy_checks,mailbox_checks0,mailbox_checks1);
        $finish;
    end
    initial begin #500000;$fatal(1,"AD9643 hardware watchdog timeout");end
endmodule

