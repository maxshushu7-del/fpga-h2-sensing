`timescale 1ns/1ps
module tb_fir4;
    reg clk=0, rst=1, enable=0, in_valid=0;
    reg signed [11:0] x_in=0;
    wire out_valid;
    wire signed [11:0] y_out;
    fir4 dut(.*);
    always #5 clk = ~clk;
    string input_path, trace_path, actual_path, status_path;
    integer input_fd, trace_fd, actual_fd, status_fd, fields;
    integer cycle_n, reset_n, enable_n, valid_n, x_n, expected_valid, expected_y, sample_id;
    integer cycles=0, checks=0, errors=0, expected_count=0, actual_count=0;
    integer valid_errors=0, value_errors=0, reset_errors=0;

    initial begin
        input_path="stimulus.txt";
        trace_path="cycles.csv";
        actual_path="actual.csv";
        status_path="status.txt";
        input_fd=$fopen(input_path,"r"); trace_fd=$fopen(trace_path,"w");
        actual_fd=$fopen(actual_path,"w"); status_fd=$fopen(status_path,"w");
        if (!input_fd || !trace_fd || !actual_fd || !status_fd) $fatal(1,"File open failed");
        $fdisplay(trace_fd,"cycle,rst,enable,in_valid,x,expected_valid,out_valid,expected_y,y,sample_id");
        $fdisplay(actual_fd,"sample_id,y");
        while (!$feof(input_fd)) begin
            fields=$fscanf(input_fd,"%d %d %d %d %d %d %d %d\n",
                           cycle_n,reset_n,enable_n,valid_n,x_n,expected_valid,expected_y,sample_id);
            if (fields==8) begin
                if(cycle_n!=cycles) $fatal(1,"Nonconsecutive stimulus cycle");
                @(negedge clk);
                rst=reset_n; enable=enable_n; in_valid=valid_n; x_in=x_n;
                @(posedge clk); #1;
                checks=checks+1;
                if(out_valid !== expected_valid[0]) begin
                    errors=errors+1; valid_errors=valid_errors+1;
                    if(errors<=5) $display("MISMATCH valid cycle=%0d expected=%0d actual=%b",cycle_n,expected_valid,out_valid);
                end
                if(expected_valid) begin
                    expected_count=expected_count+1; checks=checks+1;
                    if(out_valid===1'b1 && $signed(y_out) !== expected_y) begin
                        errors=errors+1; value_errors=value_errors+1;
                        if(errors<=5) $display("MISMATCH value cycle=%0d sample_id=%0d expected=%0d actual=%0d",cycle_n,sample_id,expected_y,$signed(y_out));
                    end
                end
                if(reset_n || !enable_n) begin
                    checks=checks+1;
                    if(y_out !== 12'sd0) begin errors=errors+1; reset_errors=reset_errors+1; end
                end
                if(out_valid===1'b1) begin
                    actual_count=actual_count+1;
                    if(expected_valid) $fdisplay(actual_fd,"%0d,%0d",sample_id,$signed(y_out));
                    else $fdisplay(actual_fd,"unexpected_cycle_%0d,%0d",cycle_n,$signed(y_out));
                end
                $fdisplay(trace_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%b,%0d,%0d,%0d",
                           cycle_n,reset_n,enable_n,valid_n,x_n,expected_valid,out_valid,expected_y,$signed(y_out),sample_id);
                cycles=cycles+1;
            end else if(fields!=-1) $fatal(1,"Malformed stimulus");
        end
        if(cycles==0 || expected_count==0) $fatal(1,"Empty scenario");
        $fdisplay(status_fd,"COMPLETED=1");
        $fdisplay(status_fd,"CYCLES=%0d",cycles);
        $fdisplay(status_fd,"CHECKS=%0d",checks);
        $fdisplay(status_fd,"EXPECTED_OUTPUTS=%0d",expected_count);
        $fdisplay(status_fd,"ACTUAL_OUTPUTS=%0d",actual_count);
        $fdisplay(status_fd,"ERRORS=%0d",errors);
        $fdisplay(status_fd,"VALID_ERRORS=%0d",valid_errors);
        $fdisplay(status_fd,"VALUE_ERRORS=%0d",value_errors);
        $fdisplay(status_fd,"RESET_ERRORS=%0d",reset_errors);
        $fclose(input_fd); $fclose(trace_fd); $fclose(actual_fd); $fclose(status_fd);
        $display("FIR_TRIAL_COMPLETED cycles=%0d checks=%0d outputs=%0d errors=%0d",cycles,checks,actual_count,errors);
        if(errors) $fatal(1,"FIR checks rejected this implementation");
        $display("FIR_TRIAL_PASS");
        $finish;
    end
endmodule
