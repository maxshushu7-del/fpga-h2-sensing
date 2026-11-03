`timescale 1ns/1ps
// Independent PIN-LEVEL 8N1 decoder: deliberately does not use u_byte's signals.
module tb_result_uart_v2 #(
    parameter integer BAUD=1000000
);
    localparam integer CLK_HZ=100000000;
    localparam integer FFT_LOG2=12, OUT_WIDTH=29;
    // UART RTL uses floor(CLOCK_HZ / BAUD), not an ideal fractional divider.
    localparam integer BIT_CYCLES=CLK_HZ/BAUD;
    localparam integer BIT_NS=BIT_CYCLES*10;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,result_strobe=0,measurement_valid=0,fine_mode=0,low_mode=0;
    reg [31:0] frequency_hz=0,sequence_number=0;
    reg [FFT_LOG2-1:0] peak_bin=0,coarse_bin=0;
    reg signed [17:0] bin_offset_q16=0;
    reg signed [31:0] fine_offset_hz=0;
    reg [2*OUT_WIDTH:0] peak_power=0,noise_power=0;
    reg [31:0] clipped_samples=0;
    reg [7:0] result_flags=0;
    wire uart_tx;
    wire [31:0] dropped_results;
    result_uart_v2 #(.ALGORITHM_VERSION(3),.ADC_CHANNEL(1),.FFT_LOG2(FFT_LOG2),
        .OUT_WIDTH(OUT_WIDTH),.CLOCK_HZ(CLK_HZ),.BAUD_RATE(BAUD)) dut (
        .clk(clk),.rst_n(rst_n),.result_strobe(result_strobe),
        .measurement_valid(measurement_valid),.fine_mode(fine_mode),.low_mode(low_mode),
        .frequency_hz(frequency_hz),.sequence_number(sequence_number),
        .peak_bin(peak_bin),.coarse_bin(coarse_bin),.bin_offset_q16(bin_offset_q16),
        .fine_offset_hz(fine_offset_hz),.peak_power(peak_power),.noise_power(noise_power),
        .clipped_samples(clipped_samples),.result_flags(result_flags),
        .uart_tx(uart_tx),.dropped_results(dropped_results)
    );
    reg [7:0] captured [0:5][0:63];
    integer received_bytes=0,received_packets=0;
    integer serial_dump;
    string serial_dump_path="E:/Codex/FPGA/projects/adc_fft_tracking_20261014/verification/uart_v2/pin_decoded_bytes.hex";
    integer packet_slot,byte_slot,bit_number;
    reg [7:0] received_byte;
    initial begin
        if($value$plusargs("UART_HEX_PATH=%s",serial_dump_path)) begin end
        serial_dump=$fopen(serial_dump_path,"w");
        if(!serial_dump) $fatal(1,"Cannot create UART pin-decode log on E:");
        wait(rst_n);
        forever begin
            @(negedge uart_tx);
            #(BIT_NS/2);
            if(uart_tx!==1'b0) $fatal(1,"UART start bit not low at bit centre");
            received_byte=0;
            for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
                #BIT_NS;
                if(uart_tx!==1'b0 && uart_tx!==1'b1) $fatal(1,"Unknown UART data bit");
                received_byte[bit_number]=uart_tx;
            end
            #BIT_NS;
            if(uart_tx!==1'b1) $fatal(1,"UART stop bit not high at bit centre");
            packet_slot=received_bytes/64;
            byte_slot=received_bytes%64;
            if(packet_slot>=6) $fatal(1,"Unexpected extra UART packet");
            captured[packet_slot][byte_slot]=received_byte;
            $fdisplay(serial_dump,"%02x",received_byte);
            received_bytes=received_bytes+1;
            if(received_bytes%64==0) received_packets=received_packets+1;
            #(BIT_NS/2);
        end
    end

    function automatic [31:0] u32(input integer p,input integer offset);
        u32={captured[p][offset+3],captured[p][offset+2],captured[p][offset+1],captured[p][offset]};
    endfunction
    function automatic [15:0] u16(input integer p,input integer offset);
        u16={captured[p][offset+1],captured[p][offset]};
    endfunction
    function automatic [63:0] u64(input integer p,input integer offset);
        u64={u32(p,offset+4),u32(p,offset)};
    endfunction
    task automatic send_result(input integer seq,input integer valid_signal,input integer fine);
        begin
            @(negedge clk);
            sequence_number=seq;
            frequency_hz=1000000+seq*1234;
            fine_offset_hz=(seq==22) ? 2000+seq : -(2000+seq);
            bin_offset_q16=(seq==22) ? 32768 : -16384;
            coarse_bin=3+seq; peak_bin=4095-seq;
            peak_power=59'h123456789abcdef;
            noise_power=59'h0000123456789ab;
            clipped_samples=valid_signal ? 0 : seq+10;
            measurement_valid=valid_signal;
            fine_mode=(fine==1); low_mode=(fine==2);
            result_flags=valid_signal ? 8'h08 : 8'h42;
            result_strobe=1;
            @(negedge clk);result_strobe=0;
        end
    endtask
    task automatic check_packet(input integer p,input integer seq,input integer valid_signal,
        input integer fine,input integer drops);
        integer n;
        reg [7:0] check;
        begin
            check=0;
            for(n=0;n<63;n=n+1) check=check^captured[p][n];
            if(captured[p][0]!=8'ha5 || captured[p][1]!=8'h5a || captured[p][2]!=3 || captured[p][3]!=64)
                $fatal(1,"Bad protocol header/length");
            if(check!=captured[p][63]) $fatal(1,"Bad XOR checksum for packet %0d",p);
            if(captured[p][4]!=3 || captured[p][5]!=1 || captured[p][6]!=12)
                $fatal(1,"Algorithm/channel/point metadata mismatch");
            if(u32(p,8)!=seq) $fatal(1,"Expected transmitted seq%0d, got%0d",seq,u32(p,8));
            if(u32(p,12)!=250000000 || u32(p,16)!=(fine ? 1000000:250000000))
                $fatal(1,"ADC/effective sample rate mismatch");
            if(u32(p,20)!=1000000+seq*1234 || $signed(u32(p,24))!=((seq==22) ? 2000+seq : -(2000+seq)))
                $fatal(1,"Frequency/signed fine offset mismatch");
            if(u16(p,28)!=3+seq || u16(p,30)!=4095-seq || $signed(u32(p,32))!=((seq==22) ? 32768 : -16384))
                $fatal(1,"Bin/signed Q16 offset mismatch");
            if(u32(p,36)!=(valid_signal ? 0 : seq+10) || u64(p,40)!=64'h0123456789abcdef || u64(p,48)!=64'h00000123456789ab)
                $fatal(1,"Clipping/power fields mismatch");
            if(u32(p,56)!=drops) $fatal(1,"Packet dropcount mismatch: actual%0d expected%0d",u32(p,56),drops);
            if(captured[p][7]!=(valid_signal ? 8'h08:8'h42) || captured[p][60]!=valid_signal ||
                captured[p][61]!=fine || captured[p][62]!=1)
                $fatal(1,"Flags/measurement validity/fine/window mismatch");
            if(!valid_signal && captured[p][60]!=0) $fatal(1,"Invalid signal displayed as valid");
            $display("PASS pin-decoded packet%0d seq%0d valid%0d fine%0d drops%0d",p,seq,valid_signal,fine,drops);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst_n=1;
        $display("UART_TEST configured_baud=%0d bit_cycles=%0d bit_ns=%0d effective_baud=%0.6f",BAUD,BIT_CYCLES,BIT_NS,1.0*CLK_HZ/BIT_CYCLES);
        send_result(1,1,1);
        // A packet lasts >=640 bit-times; deliver new results while it is busy.
        #(20*BIT_NS);
        send_result(2,1,1);
        #(10*BIT_NS);
        send_result(3,1,0);
        #(10*BIT_NS);
        send_result(4,1,1);
        #(10*BIT_NS);
        send_result(5,1,1);
        if(dropped_results!=3) $fatal(1,"Pending replacement drops not counted correctly");
        wait(received_packets==2);
        check_packet(0,1,1,1,0);
        check_packet(1,5,1,1,3);
        // Wait beyond end of last stop bit / controller's return to idle.
        #(20*BIT_NS);
        send_result(10,0,0);
        wait(received_packets==3);
        check_packet(2,10,0,0,3);
        #(20*BIT_NS);
        if(received_packets!=3 || received_bytes!=192) $fatal(1,"Stale pending result retransmitted");
        // Corner: a new result on the first idle cycle supersedes an existing
        // pending result. Hierarchy is used ONLY to schedule this race; decoding
        // and packet assertions continue to observe the physical UART pin.
        send_result(20,1,1);
        #(20*BIT_NS);
        send_result(21,1,0);
        wait(dut.state==0 && dut.pending);
        send_result(22,1,2);
        wait(received_packets==5);
        check_packet(3,20,1,1,3);
        check_packet(4,22,1,2,4);
        #(20*BIT_NS);
        if(received_packets!=5 || received_bytes!=320 || dropped_results!=4)
            $fatal(1,"IDLE replacement lost/corrupted a result");
        $fclose(serial_dump);
        $display("PASS tb_result_uart_v2: bit-level 8N1,64bytes,little endian,positive/negative signed Q16/fine,XOR,invalidflag,busy/IDLE latest pending replacement,dropcounter,no stale queue.");
        $finish;
    end
    initial begin
        #(5000*BIT_NS);
        $fatal(1,"UART v2 timeout");
    end
endmodule
