`timescale 1ns/1ps
// Review-only AXI boundary model: accepts config, stalls data, no DSP transform.
// Only tests the unmodified production wrapper's transaction bookkeeping.
module fft_core(input aclk,aresetn,input [7:0] s_axis_config_tdata,input s_axis_config_tvalid,
 output s_axis_config_tready,input [31:0] s_axis_data_tdata,input s_axis_data_tvalid,
 output s_axis_data_tready,input s_axis_data_tlast,
 output [63:0] m_axis_data_tdata,output [15:0] m_axis_data_tuser,
 output m_axis_data_tvalid,m_axis_data_tlast,input m_axis_data_tready,
 output event_frame_started,event_tlast_missing,event_tlast_unexpected,
 output event_status_channel_halt,event_data_in_channel_halt,event_data_out_channel_halt);
 reg [7:0] cycle=0;
 always @(posedge aclk) if(!aresetn) cycle<=0; else cycle<=cycle+1;
 assign s_axis_config_tready=(cycle>=3);
 assign s_axis_data_tready=cycle[0] && (cycle[3:1]!=3);
 assign m_axis_data_tdata=0; assign m_axis_data_tuser=0;
 assign m_axis_data_tvalid=0; assign m_axis_data_tlast=0;
 assign event_frame_started=0; assign event_tlast_missing=0; assign event_tlast_unexpected=0;
 assign event_status_channel_halt=0; assign event_data_in_channel_halt=0; assign event_data_out_channel_halt=0;
endmodule
module tb_fft_wrapper_boundary;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,valid=0,last=0;
 reg signed [15:0] si=0,sq=0;
 wire ready,configured,error;
 integer accepted=0,stalled=0,j;
 fft_stream_improved dut(.clk(clk),.rst_n(rst_n),.sample_i(si),.sample_q(sq),
 .sample_valid(valid),.sample_last(last),.idle_capture(1'b0),.sample_ready(ready),
 .configured(configured),.fft_re(),.fft_im(),.fft_bin(),.fft_valid(),.fft_last(),.protocol_error(error));
 always @(posedge clk) if(rst_n && valid) begin
   if(ready) accepted=accepted+1; else stalled=stalled+1;
 end
 task sample(input integer index,input integer endflag);
  begin
   @(negedge clk); si=index; sq=-index; valid=1; last=endflag;
   @(posedge clk); while(!ready) @(posedge clk);
   @(negedge clk); valid=0; last=0;
  end
 endtask
 initial begin
   repeat(5) @(negedge clk); rst_n=1;
   wait(configured);
   for(j=0;j<4096;j=j+1) sample(j,j==4095);
   repeat(3) @(negedge clk);
   if(error || accepted!=4096 || dut.input_index!=0 || stalled<1)
     $fatal(1,"Good frame failed accepted=%0d stalls=%0d index=%0d error=%0d",accepted,stalled,dut.input_index,error);
   $display("WRAPPER_BOUNDARY_PASS 4096 accepted samples; stalls=%0d; correct TLAST; index wraps to0",stalled);
   sample(0,1); // malformed TLAST on first sample: exercise rejection telemetry.
   @(negedge clk);
   if(!error) $fatal(1,"Early TLAST not detected");
   $display("WRAPPER_BOUNDARY_PASS early TLAST sets protocol_error");
   rst_n=0; repeat(3) @(negedge clk); rst_n=1; wait(configured);
   @(negedge clk); if(error || dut.input_index!=0) $fatal(1,"Reset did not clear protocol bookkeeping");
   $display("WRAPPER_BOUNDARY_PASS reset clears sticky error and reconfigures");
   $display("ALL FFT WRAPPER BOUNDARY UNIT CASES PASSED; fft_core is a non-DSP stub"); $finish;
 end
 initial begin #1000000; $fatal(1,"Timeout"); end
endmodule
