`timescale 1ns/1ps
module tb_hw_clock_health;
    reg rst_n=0,clk_work=0,adc_clk=0,tx_clk=0,enable=0,adc_run=0,tx_run=0;
    real tx_half=2.0;
    always #5 clk_work=~clk_work;
    always #2 begin if(adc_run)adc_clk=~adc_clk;else adc_clk=0;end
    always begin #(tx_half);if(tx_run)tx_clk=~tx_clk;else tx_clk=0;end
    wire clocks_ok;
    wire [9:0] adc_beats,tx_beats;
    hw_clock_health dut(.rst_n(rst_n),.clk_work(clk_work),.adc_clk(adc_clk),.tx_clk(tx_clk),
        .enable(enable),.clocks_ok(clocks_ok),.adc_beats(adc_beats),.tx_beats(tx_beats));
    integer checks=0,f;
    task wait_window;
        begin repeat(100100)@(negedge clk_work);end
    endtask
    task assert_good;
        begin
            if(!clocks_ok || adc_beats<230 || adc_beats>260 || tx_beats<230 || tx_beats>260)
                $fatal(1,"nominal heartbeat bad A=%0d T=%0d ok=%b",adc_beats,tx_beats,clocks_ok);
            checks=checks+1;
        end
    endtask
    initial begin
        #101;rst_n=1;
        repeat(100)@(negedge clk_work);
        if(dut.adc_reset_pipe!==3'b111 || dut.tx_reset_pipe!==3'b111 || dut.adc_div!==0 || dut.tx_div!==0)
            $fatal(1,"absent clock reset was released");
        if(dut.work_reset_pipe!==0 || clocks_ok) $fatal(1,"work reset/startup gate");
        checks=checks+1;
        adc_run=1;tx_run=1;
        repeat(100)@(negedge clk_work);
        if(dut.adc_reset_pipe!==0 || dut.tx_reset_pipe!==0) $fatal(1,"source reset did not release");
        checks=checks+1;
        enable=1;wait_window;assert_good;
        adc_run=0;wait_window;
        if(clocks_ok || adc_beats>1 || tx_beats<230) $fatal(1,"missing ADC clock not detected");
        checks=checks+1;
        adc_run=1;wait_window;assert_good;
        // Reset at a non-clock-aligned time while one source clock is absent.
        adc_run=0;#1.123;rst_n=0;#0.01;
        if(clocks_ok || dut.adc_div!==0 || dut.tx_div!==0 || dut.window_count!==0)
            $fatal(1,"asynchronous reset failed");
        if(dut.adc_reset_pipe!==3'b111 || dut.tx_reset_pipe!==3'b111 || dut.work_reset_pipe!==3'b111)
            $fatal(1,"reset-pipe asynchronous assertion failed");
        checks=checks+1;
        #50.333;rst_n=1;
        repeat(100)@(negedge clk_work);
        if(dut.adc_reset_pipe!==3'b111 || dut.adc_div!==0 || dut.tx_reset_pipe!==0)
            $fatal(1,"clock-specific reset release failed");
        checks=checks+1;
        adc_run=1;wait_window;assert_good;
        // Preserve the original rate threshold: 125MHz TX must be rejected.
        tx_half=4.0;wait_window;
        if(clocks_ok || tx_beats<110 || tx_beats>135 || adc_beats<230)
            $fatal(1,"wrong TX rate not detected A=%0d T=%0d",adc_beats,tx_beats);
        checks=checks+1;
        tx_half=2.0;wait_window;assert_good;
        enable=0;repeat(10)@(negedge clk_work);
        if(clocks_ok || dut.window_count!==0 || dut.adc_count!==0 || dut.tx_count!==0)
            $fatal(1,"disabled monitor not cleared");
        checks=checks+1;
        f=$fopen("clock_health_result.txt","w");
        $fwrite(f,"PASS: clock-health domain-qualified reset and original rate equations\n");
        $fwrite(f,"Checks=%0d; 3 domains async assertion/synchronous release; absent-clock startup; 250MHz nominal; ADC stop/restart; reset with ADC stopped; 125MHz TX rejected; disable clear\n",checks);
        $fclose(f);$display("CLOCK HEALTH TEST PASS %0d checks",checks);$finish;
    end
    initial begin #8000000;$fatal(1,"clock health watchdog");end
endmodule

