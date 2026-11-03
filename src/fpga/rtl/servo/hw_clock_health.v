`timescale 1ns/1ps
// Clock-presence/rate monitor. A heartbeat changes every 1024 source edges.
// No changing binary bus crosses clock domains. Source clocks may be absent.
module hw_clock_health #(parameter integer TX_MIN=230,parameter integer TX_MAX=260) (
    input wire rst_n,input wire clk_work,input wire adc_clk,input wire tx_clk,input wire enable,
    output reg clocks_ok,output reg [9:0] adc_beats,output reg [9:0] tx_beats
);
    // Each counter domain receives its own reset release. An absent clock keeps
    // that domain in reset; external assertion is asynchronous in all domains.
    (* ASYNC_REG="TRUE" *) reg [2:0] adc_reset_pipe=3'b111;
    (* ASYNC_REG="TRUE" *) reg [2:0] tx_reset_pipe=3'b111;
    (* ASYNC_REG="TRUE" *) reg [2:0] work_reset_pipe=3'b111;
    always @(posedge adc_clk or negedge rst_n) begin
        if(!rst_n) adc_reset_pipe<=3'b111;
        else adc_reset_pipe<={adc_reset_pipe[1:0],1'b0};
    end
    always @(posedge tx_clk or negedge rst_n) begin
        if(!rst_n) tx_reset_pipe<=3'b111;
        else tx_reset_pipe<={tx_reset_pipe[1:0],1'b0};
    end
    always @(posedge clk_work or negedge rst_n) begin
        if(!rst_n) work_reset_pipe<=3'b111;
        else work_reset_pipe<={work_reset_pipe[1:0],1'b0};
    end
    wire adc_rst=adc_reset_pipe[2];
    wire tx_rst=tx_reset_pipe[2];
    wire work_rst=work_reset_pipe[2];
    reg [9:0] adc_div=0,tx_div=0;
    reg adc_toggle=0,tx_toggle=0;
    always @(posedge adc_clk or posedge adc_rst) begin
        if(adc_rst)begin adc_div<=0;adc_toggle<=0;end
        else begin adc_div<=adc_div+1'b1;if(adc_div==1023)adc_toggle<=~adc_toggle;end
    end
    always @(posedge tx_clk or posedge tx_rst) begin
        if(tx_rst)begin tx_div<=0;tx_toggle<=0;end
        else begin tx_div<=tx_div+1'b1;if(tx_div==1023)tx_toggle<=~tx_toggle;end
    end
    (* ASYNC_REG="TRUE" *) reg [2:0] adc_sync=0,tx_sync=0;
    reg adc_seen=0,tx_seen=0;
    reg [16:0] window_count=0;
    reg [9:0] adc_count=0,tx_count=0;
    always @(posedge clk_work or posedge work_rst) begin
        if(work_rst)begin
            adc_sync<=0;tx_sync<=0;adc_seen<=0;tx_seen<=0;window_count<=0;
            adc_count<=0;tx_count<=0;adc_beats<=0;tx_beats<=0;clocks_ok<=0;
        end else begin
            adc_sync<={adc_sync[1:0],adc_toggle};tx_sync<={tx_sync[1:0],tx_toggle};
            adc_seen<=adc_sync[2];tx_seen<=tx_sync[2];
            if(!enable)begin window_count<=0;adc_count<=0;tx_count<=0;clocks_ok<=0;end
            else if(window_count==99999)begin
                window_count<=0;adc_beats<=adc_count;tx_beats<=tx_count;
                clocks_ok<=adc_count>=230 && adc_count<=260 && tx_count>=TX_MIN && tx_count<=TX_MAX;
                adc_count<=0;tx_count<=0;
            end else begin
                window_count<=window_count+1'b1;
                if(adc_sync[2]!=adc_seen)adc_count<=adc_count+1'b1;
                if(tx_sync[2]!=tx_seen)tx_count<=tx_count+1'b1;
            end
        end
    end
endmodule
