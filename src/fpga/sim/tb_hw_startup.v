`timescale 1ns/1ps
// Independent serial-wire decoder and real-rate clock-health regression.
// No ROM mirror is used: protocol, group sizes and essential register fields
// are checked from actual CS/SCLK/SDIO transactions, including an abort/restart.
module tb_hw_startup;
    reg clk=0,rst=1,init_enable=0;
    always #5 clk=~clk;
    wire sclk,sdio,clock_cs,adc_cs,dac_cs,sequence_done;
    wire [7:0] writes_sent;
    hw_fl4322_init #(.HALF_PERIOD(2),.STARTUP_CYCLES(8),.PLL_SETTLE_CYCLES(64)) dut(
        .clk(clk),.rst(rst),.init_enable(init_enable),.spi_clk(sclk),.spi_sdio(sdio),
        .clk_cs_n(clock_cs),.adc_cs_n(adc_cs),.dac_cs_n(dac_cs),
        .sequence_done(sequence_done),.writes_sent(writes_sent));

    reg adc_clk=0,tx_clk=0,adc_run=1,tx_run=1,health_enable=0;
    always #2 if(adc_run) adc_clk=~adc_clk; else adc_clk=0;
    always #1 if(tx_run) tx_clk=~tx_clk; else tx_clk=0;
    wire clocks_ok;
    wire [9:0] adc_beats,tx_beats;
    hw_clock_health #(.TX_MIN(470),.TX_MAX(510)) health(.rst_n(!rst),.clk_work(clk),.adc_clk(adc_clk),.tx_clk(tx_clk),
        .enable(health_enable),.clocks_ok(clocks_ok),.adc_beats(adc_beats),.tx_beats(tx_beats));
    reg spi_done=0,health_done=0;
    integer f,total_spi_edges=0,completed=0,clock_writes=0,adc_writes=0,dac_writes=0,aborted=0;
    integer transaction_chip=-1,bits_captured=0,falling_edges=0,decoded_addr,decoded_data;
    integer final_spi_edges=0;
    reg transaction_active=0;
    reg [23:0] captured_word=0;
    reg clock193_seen=0,clock194_seen=0,clock19e_seen=0,adc14_seen=0,adc16_seen=0,adc17_seen=0,dac_word_seen=0;
    reg [2:0] dac_hb_seen=0;
    integer dac_fifo_reset_phase=0,dac_reset_phase=0;
    real sdio_changed_at=0.0,last_rise_at=0.0,last_fall_at=0.0,last_clock_release=0.0;
    integer selected;

    // CS mutual exclusion is checked throughout each transaction and gap.
    always @(posedge clk) begin
        #1;
        selected=(!clock_cs)+(!adc_cs)+(!dac_cs);
        if(selected>1) $fatal(1,"SPI chip selects overlap");
        if(sclk && selected!=1) $fatal(1,"SPI clock toggles without one selected device");
        if(sequence_done && (writes_sent!=86 || selected!=0 || sclk))
            $fatal(1,"SPI completion state inconsistent");
    end
    always @(sdio) begin
        if(init_enable && transaction_active && sclk)
            $fatal(1,"Mode-0 SDIO changed while SCLK was high");
        if(init_enable && transaction_active && last_rise_at!=0.0 &&
            $realtime-last_rise_at<19.999)
            $fatal(1,"SPI SDIO hold time violated");
        sdio_changed_at=$realtime;
    end
    always @(negedge clock_cs or negedge adc_cs or negedge dac_cs) begin
        #0.001;
        if(init_enable && !rst) begin
            if(transaction_active || sclk) $fatal(1,"Invalid SPI CS assertion");
            transaction_active=1; captured_word=0; bits_captured=0; falling_edges=0;
            last_rise_at=0.0; last_fall_at=0.0;
            transaction_chip=!clock_cs ? 0 : (!adc_cs ? 1 : 2);
            if(completed<54 && transaction_chip!=0) $fatal(1,"Clock startup group ordering");
            if(completed>=54 && completed<66 && transaction_chip!=1) $fatal(1,"ADC startup group ordering");
            if(completed>=66 && transaction_chip!=2) $fatal(1,"DAC startup group ordering");
            if(completed==54 && $realtime-last_clock_release<640.0)
                $fatal(1,"PLL settling wait shorter than64 work clocks");
        end
    end
    always @(posedge sclk) begin
        if(!transaction_active || !init_enable) $fatal(1,"SPI rising edge outside transaction");
        if($realtime-sdio_changed_at<19.999) $fatal(1,"SPI SDIO setup shorter than20ns");
        if(last_fall_at!=0.0 && $realtime-last_fall_at<19.999)
            $fatal(1,"SPI low half-period too short");
        captured_word={captured_word[22:0],sdio};
        bits_captured=bits_captured+1; total_spi_edges=total_spi_edges+1;
        last_rise_at=$realtime;
    end
    always @(negedge sclk) if(transaction_active && init_enable && !rst) begin
        if($realtime-last_rise_at<19.999) $fatal(1,"SPI high half-period too short");
        falling_edges=falling_edges+1; last_fall_at=$realtime;
    end
    always @(posedge clock_cs or posedge adc_cs or posedge dac_cs) begin
        #0.001;
        if(transaction_active && clock_cs && adc_cs && dac_cs) begin
            transaction_active=0;
            if(!init_enable || rst) aborted=aborted+1;
            else begin
                if(bits_captured!=(transaction_chip==2 ? 16 : 24) || falling_edges!=bits_captured)
                    $fatal(1,"SPI width/edge count chip%0d: rise%0d fall%0d",transaction_chip,bits_captured,falling_edges);
                if(sclk || $realtime-last_fall_at<19.999) $fatal(1,"SPI CS release hold failure");
                if(transaction_chip==2) begin
                    if(captured_word[15]) $fatal(1,"Unexpected DAC read instruction");
                    decoded_addr=captured_word[14:8]; decoded_data=captured_word[7:0];
                    dac_writes=dac_writes+1;
                    case(decoded_addr)
                        0: begin
                            if(dac_reset_phase==0 && decoded_data!=8'ha0) $fatal(1,"DAC software reset assert");
                            if(dac_reset_phase==1 && decoded_data!=8'h80) $fatal(1,"DAC software reset release");
                            dac_reset_phase=dac_reset_phase+1;
                        end
                        3: begin if(decoded_data!=0) $fatal(1,"DAC must use signed I-first word mode"); dac_word_seen=1; end
                        8'h1c: begin if(decoded_data!=1) $fatal(1,"DAC HB1 must bypass"); dac_hb_seen[0]=1; end
                        8'h1d: begin if(decoded_data!=1) $fatal(1,"DAC HB2 must bypass"); dac_hb_seen[1]=1; end
                        8'h1e: begin if(decoded_data!=1) $fatal(1,"DAC HB3 must bypass"); dac_hb_seen[2]=1; end
                        8'h18: begin
                            if(dac_fifo_reset_phase==0 && decoded_data!=2) $fatal(1,"DAC software FIFO reset request");
                            if(dac_fifo_reset_phase==1 && decoded_data!=0) $fatal(1,"DAC software FIFO reset release");
                            dac_fifo_reset_phase=dac_fifo_reset_phase+1;
                        end
                    endcase
                end else begin
                    if(captured_word[23]) $fatal(1,"Unexpected clock/ADC read instruction");
                    decoded_addr=captured_word[23:8]; decoded_data=captured_word[7:0];
                    if(transaction_chip==0) begin
                        clock_writes=clock_writes+1;
                        case(decoded_addr)
                            16'h0193: begin if(decoded_data!=17) $fatal(1,"Clock193 must divide/4"); clock193_seen=1; end
                            16'h019e: begin if(decoded_data!=17) $fatal(1,"Clock19e must divide/4"); clock19e_seen=1; end
                            16'h0194: begin if(decoded_data!=0) $fatal(1,"Clock194 bypass must be disabled"); clock194_seen=1; end
                        endcase
                    end else begin
                        adc_writes=adc_writes+1;
                        case(decoded_addr)
                            16'h0014: begin if(decoded_data!=5) $fatal(1,"ADC signed LVDS format"); adc14_seen=1; end
                            16'h0016: begin if(decoded_data!=0) $fatal(1,"ADC DCO default phase"); adc16_seen=1; end
                            16'h0017: begin if(decoded_data!=8'h85) $fatal(1,"ADC interleaved output profile"); adc17_seen=1; end
                        endcase
                    end
                end
                completed=completed+1;
                if(completed==54) last_clock_release=$realtime;
                if(writes_sent!=completed) $fatal(1,"SPI writes_sent mismatches decoded completion count");
            end
        end
    end
    task clear_decoder;
        begin
            completed=0;clock_writes=0;adc_writes=0;dac_writes=0;
            clock193_seen=0;clock194_seen=0;clock19e_seen=0;adc14_seen=0;adc16_seen=0;adc17_seen=0;dac_word_seen=0;
            dac_hb_seen=0;dac_fifo_reset_phase=0;dac_reset_phase=0;
            last_clock_release=0.0;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0;
        repeat(5) @(negedge clk);
        if(sclk || !clock_cs || !adc_cs || !dac_cs || sequence_done || writes_sent)
            $fatal(1,"Disabled SPI startup not idle");
        init_enable=1;
        wait(writes_sent==2);
        wait(!clock_cs); repeat(8) @(posedge sclk);
        @(negedge clk); init_enable=0;
        repeat(3) @(negedge clk);
        if(sclk || sdio || !clock_cs || !adc_cs || !dac_cs || sequence_done || writes_sent || aborted!=1)
            $fatal(1,"SPI disable did not abort/reset cleanly");
        clear_decoder;
        final_spi_edges=total_spi_edges;
        init_enable=1;
        wait(sequence_done);
        @(negedge clk);
        if(completed!=86 || clock_writes!=54 || adc_writes!=12 || dac_writes!=20 || writes_sent!=86)
            $fatal(1,"SPI complete group counts %0d/%0d/%0d total%0d",clock_writes,adc_writes,dac_writes,completed);
        if(!clock193_seen || !clock194_seen || !clock19e_seen || !adc14_seen || !adc16_seen || !adc17_seen ||
            !dac_word_seen || dac_hb_seen!=7 || dac_fifo_reset_phase!=2 || dac_reset_phase!=2)
            $fatal(1,"Required startup register coverage missing");
        final_spi_edges=total_spi_edges-final_spi_edges;
        if(final_spi_edges!=1904) $fatal(1,"86 writes must contain1904 serial data bits");
        repeat(20) @(negedge clk);
        if(completed!=86 || !sequence_done || writes_sent!=86) $fatal(1,"SPI repeat after DONE");
        spi_done=1;
        $display("SPI STARTUP PASS:86 writes,1904 data bits,54 clock/12 ADC/20 DAC; abort/restart");
    end

    integer first_adc=0,first_tx=0,stopped_adc=0,stopped_tx=0;
    initial begin
        wait(!rst);
        // Clock-health counters now release reset separately in each domain.
        // Measure a full1ms window from its work-domain enable, not from the
        // earlier asynchronous external-reset deassertion.
        wait(health.work_rst===1'b0);
        @(negedge clk); health_enable=1;
        if(health.adc_rst || health.tx_rst) $fatal(1,"Clock-health source reset release");
        repeat(100000) @(negedge clk);
        first_adc=adc_beats; first_tx=tx_beats;
        if(!clocks_ok || adc_beats<243 || adc_beats>245 || tx_beats<487 || tx_beats>489)
            $fatal(1,"Clock health real-rate mismatch adc=%0d tx=%0d ok=%b",adc_beats,tx_beats,clocks_ok);
        adc_run=0;
        repeat(100000) @(negedge clk);
        stopped_adc=adc_beats;
        if(clocks_ok || adc_beats>1 || tx_beats<487 || tx_beats>489)
            $fatal(1,"Clock health failed ADC stop adc=%0d tx=%0d",adc_beats,tx_beats);
        adc_run=1;tx_run=0;
        repeat(100000) @(negedge clk);
        stopped_tx=tx_beats;
        if(clocks_ok || tx_beats>1 || adc_beats<243 || adc_beats>245)
            $fatal(1,"Clock health failed TX stop adc=%0d tx=%0d",adc_beats,tx_beats);
        health_enable=0;
        repeat(3) @(negedge clk);
        if(clocks_ok) $fatal(1,"Clock health enable gating");
        health_done=1;
        $display("CLOCK HEALTH PASS:250MHz beats=%0d 500MHz beats=%0d stoppedADC=%0d stoppedTX=%0d",
            first_adc,first_tx,stopped_adc,stopped_tx);
    end
    initial begin #5000000; $fatal(1,"Hardware startup watchdog"); end
    initial begin
        wait(spi_done && health_done);
        f=$fopen("hw_startup_result.txt","w");
        if(!f) $fatal(1,"Cannot write startup result");
        $fwrite(f,"PASS\nDecoded writes: %0d\nClock/ADC/DAC writes: %0d/%0d/%0d\nData bits after restart: %0d\nAborted partial writes: %0d\n",
            completed,clock_writes,adc_writes,dac_writes,final_spi_edges,aborted);
        $fwrite(f,"250MHz ADC heartbeats per1ms: %0d\n500MHz TX heartbeats per1ms: %0d\nStopped ADC/TX heartbeats: %0d/%0d\n",
            first_adc,first_tx,stopped_adc,stopped_tx);
        $fwrite(f,"Mode0 wire decode; exact widths/edge counts; mutually exclusive CS; SDIO setup/hold; PLL wait;250MHz profile193=11/194=00/19e=11; ADC modes; DAC signed word/1x bypass/FIFO reset; disable abort/restart; actual3ms clock-rate and stop detection.\n");
        $fclose(f);
        $display("HARDWARE STARTUP TEST PASS");
        $finish;
    end
endmodule
