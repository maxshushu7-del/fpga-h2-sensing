`timescale 1ns / 1ps
module reset_sync(input wire clk, input wire async_ok, output wire rst_n);
    (* ASYNC_REG = "TRUE" *) reg [2:0] release_pipe = 3'b000;
    always @(posedge clk or negedge async_ok)
        if (!async_ok) release_pipe <= 3'b000;
        else release_pipe <= {release_pipe[1:0], 1'b1};
    assign rst_n = release_pipe[2];
endmodule
