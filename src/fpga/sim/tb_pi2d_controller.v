`timescale 1ns/1ps
// Direct controller test: full-range 16-bit errors and mid-flight input changes.
module tb_pi2d_controller;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1,clear=0,in_valid=0;
    reg signed [15:0] error_signal=0,bias=0;
    reg signed [31:0] kp=32768,ki=16384,kd=32768,k2=98304;
    reg [15:0] limit=32767;
    reg [31:0] ilimit=2147483647;
    wire in_ready,valid,clipped,anti,iclip;
    wire signed [15:0] voltage;
    wire signed [47:0] integral;
    integer checked=0,i,f;
    reg signed [63:0] ri=0,e1=0,e2=0,e,p,di,d,d2,cand,bound,ibound,base,total;
    reg signed [63:0] expected,expected_integral;
    reg expected_anti,expected_clip,expected_iclip;
    reg signed [31:0] saved_kp,saved_ki,saved_kd,saved_k2;
    pi2d_controller dut(.clk(clk),.rst(rst),.clear(clear),.error_signal(error_signal),
        .in_valid(in_valid),.in_ready(in_ready),.kp(kp),.ki(ki),.kd(kd),.k2(k2),
        .output_limit(limit),.integral_limit(ilimit),.output_bias(bias),
        .actuator_scale(32'd65536),.actuator_limit(16'd32767),.actuator_invert(1'b0),
        .control_voltage(voltage),.control_valid(valid),.integral_value(integral),
        .output_clipped(clipped),.anti_windup(anti),.integral_clipped(iclip));
    task reset_state;
        begin
            @(negedge clk); clear=1;
            @(negedge clk); clear=0;
            ri=0; e1=0; e2=0;
        end
    endtask
    task check;
        input integer value;
        begin
            e=value;
            p=$signed(kp)*e;
            di=$signed(ki)*e;
            d=$signed(kd)*(e-e1);
            d2=$signed(k2)*(e-2*e1+e2);
            ibound=ilimit[31] ? 2147483647 : ilimit;
            ibound=ibound <<< 16;
            cand=ri+di; expected_iclip=0;
            if(cand>ibound) begin cand=ibound; expected_iclip=1; end
            if(cand< -ibound) begin cand=-ibound; expected_iclip=1; end
            bound=limit>32767 ? 32767 : limit;
            bound=bound <<< 16;
            base=$signed(bias);
            base=(base <<< 16)+p+d+d2;
            total=base+cand;
            expected_anti=(total>bound && di>0)||(total< -bound && di<0);
            if(!expected_anti) ri=cand;
            total=(base+ri) >>> 16;
            expected=total; expected_clip=0;
            if(expected>(bound >>> 16)) begin expected=bound >>> 16; expected_clip=1; end
            if(expected< -(bound >>> 16)) begin expected=-(bound >>> 16); expected_clip=1; end
            expected_integral=ri; e2=e1; e1=e;
            saved_kp=kp; saved_ki=ki; saved_kd=kd; saved_k2=k2;
            @(negedge clk); error_signal=value; in_valid=1;
            while(!in_ready) @(negedge clk);
            @(posedge clk);
            // Distracting requests during busy cannot modify this transaction.
            @(negedge clk); error_signal=123; kp=7; ki=-8; kd=9; k2=-10;
            repeat(3) @(negedge clk);
            in_valid=0;
            kp=saved_kp; ki=saved_ki; kd=saved_kd; k2=saved_k2;
            while(!valid) @(negedge clk);
            if($signed(voltage)!==expected || $signed(integral)!==expected_integral ||
                {clipped,anti,iclip}!=={expected_clip,expected_anti,expected_iclip})
                $fatal(1,"Core mismatch #%0d e=%0d u=%0d/%0d I=%0d/%0d flags=%b/%b",
                    checked,value,$signed(voltage),expected,$signed(integral),expected_integral,
                    {clipped,anti,iclip},{expected_clip,expected_anti,expected_iclip});
            checked=checked+1;
            @(negedge clk);
            if(valid) $fatal(1,"Valid should pulse once");
        end
    endtask
    initial begin #100000; $fatal(1,"Core watchdog timeout"); end
    initial begin
        repeat(3) @(negedge clk); rst=0;
        for(i=0;i<16;i=i+1) check(i%2 ? -32768 : 32767);
        check(0); check(1); check(-1);
        reset_state;
        kp=32'h80000000; ki=32'h7fffffff; kd=32'h7fffffff; k2=32'h80000000;
        for(i=0;i<16;i=i+1) check(i%2 ? -32768 : 32767);
        reset_state;
        kp=32'h80000000; ki=32'h7fffffff; kd=0; k2=0;
        check(32767); check(32767); check(-32768); check(0);
        reset_state;
        kp=0; ki=65536; kd=0; k2=0; ilimit=2; limit=1000;
        for(i=0;i<8;i=i+1) check(1);
        for(i=0;i<8;i=i+1) check(-1);
        reset_state;
        kp=65536; ki=-32768; ilimit=1000; limit=8; bias=-2;
        check(100); check(-100); check(1); check(-1);
        // Synchronous reset during an active computation cancels its output.
        @(negedge clk); error_signal=17; in_valid=1;
        @(negedge clk); in_valid=0; rst=1;
        repeat(3) @(negedge clk); rst=0;
        repeat(12) @(negedge clk);
        if(valid || voltage!==0 || integral!==0 || !in_ready) $fatal(1,"Mid-flight reset cancellation failed");
        f=$fopen("controller_result.txt","w");
        if(!f) $fatal(1,"Cannot write controller result");
        $fwrite(f,"PASS\nChecked controller vectors: %0d\n",checked);
        $fwrite(f,"Full 16-bit alternating extrema, 17-/18-bit differences, extreme signed coefficients, negative Ki, bias, hard integral limits, mid-flight coefficient/input changes, reset cancellation.\n");
        $fclose(f);
        $display("CONTROLLER TEST PASS: %0d vectors",checked);
        $finish;
    end
endmodule
