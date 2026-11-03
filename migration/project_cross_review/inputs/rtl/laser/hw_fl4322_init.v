`timescale 1ns/1ps
// Write-only mode-0 SPI for the FL4322 ADC, DAC and clock generator.
// 100MHz work clock; 1MHz SCLK. ADC/DAC/FPGA card clocks250MHz. No NKT commands or laser electrical model.
// Requires a 50MHz REF1 to AD9516 and compatible board-side SPI translation.
// init_enable must be asserted explicitly through VIO after checking hardware.
// The sequencer reports writes SENT, not register readback or PLL lock.
module hw_fl4322_init #(
    parameter integer HALF_PERIOD=50,
    parameter integer STARTUP_CYCLES=1000000,
    parameter integer PLL_SETTLE_CYCLES=2000000
) (
    input wire clk,input wire rst,input wire init_enable,
    output reg spi_clk,output reg spi_sdio,
    output reg clk_cs_n,output reg adc_cs_n,output reg dac_cs_n,
    output reg sequence_done,output reg [7:0] writes_sent
);
    localparam IDLE=0,STARTUP=1,LOAD=2,HIGH=3,LOW=4,RELEASE=5,GAP=6,PLL_WAIT=7,DONE=8;
    reg [3:0] state;
    reg [31:0] timer;
    reg [23:0] shift_word;
    reg [5:0] bits_left;
    wire [23:0] table_word;
    wire [1:0] table_chip;
    // Generated, auditable write table: 54 clock, 12 ADC, 20 DAC writes.
    hw_fl4322_register_table u_table(.index(writes_sent),.word(table_word),.chip(table_chip));
    always @(posedge clk) begin
        if(rst || !init_enable) begin
            state<=IDLE;timer<=0;shift_word<=0;bits_left<=0;
            spi_clk<=0;spi_sdio<=0;clk_cs_n<=1;adc_cs_n<=1;dac_cs_n<=1;
            sequence_done<=0;writes_sent<=0;
        end else begin
            case(state)
                IDLE:begin timer<=0;state<=STARTUP;end
                STARTUP:if(timer>=STARTUP_CYCLES-1)begin timer<=0;state<=LOAD;end else timer<=timer+1;
                LOAD:begin
                    shift_word<=table_word;spi_sdio<=table_word[23];
                    bits_left<=table_chip==2 ? 16:24;timer<=0;
                    clk_cs_n<=table_chip!=0;adc_cs_n<=table_chip!=1;dac_cs_n<=table_chip!=2;
                    state<=HIGH;
                end
                HIGH:if(timer>=HALF_PERIOD-1)begin spi_clk<=1;timer<=0;state<=LOW;end else timer<=timer+1;
                LOW:if(timer>=HALF_PERIOD-1)begin
                    spi_clk<=0;timer<=0;
                    if(bits_left==1)state<=RELEASE;
                    else begin bits_left<=bits_left-1;shift_word<={shift_word[22:0],1'b0};spi_sdio<=shift_word[22];state<=HIGH;end
                end else timer<=timer+1;
                RELEASE:if(timer>=HALF_PERIOD-1)begin
                    clk_cs_n<=1;adc_cs_n<=1;dac_cs_n<=1;spi_sdio<=0;timer<=0;
                    writes_sent<=writes_sent+1;state<=GAP;
                end else timer<=timer+1;
                GAP:if(timer>=HALF_PERIOD-1)begin
                    timer<=0;
                    if(writes_sent==54)state<=PLL_WAIT;
                    else if(writes_sent==86)state<=DONE;
                    else state<=LOAD;
                end else timer<=timer+1;
                PLL_WAIT:if(timer>=PLL_SETTLE_CYCLES-1)begin timer<=0;state<=LOAD;end else timer<=timer+1;
                DONE:begin sequence_done<=1;spi_clk<=0;spi_sdio<=0;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
