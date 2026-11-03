`timescale 1ns/1ps
// Clock-enable scheduler in the 100 MHz working domain. No fabric clock is made.
// Latest fresh filtered measurement is selected at a tick; stale samples are not
// integrated repeatedly. An input arriving on the tick has priority.
module servo_scheduler (
    input wire clk, input wire rst, input wire clear, input wire enable,
    input wire [31:0] update_period, input wire downstream_ready,
    input wire signed [15:0] measurement, input wire measurement_valid,
    input wire [1:0] measurement_flags,
    output reg signed [15:0] servo_error, output reg servo_valid,
    output reg [1:0] servo_flags, output reg servo_tick,
    output reg [31:0] update_count, output reg [31:0] skipped_ticks
);
    wire [31:0] period = update_period<32'd64 ? 32'd64 : update_period;
    reg [31:0] counter;
    reg signed [15:0] latest;
    reg [1:0] latest_flags;
    reg fresh;
    always @(posedge clk) begin
        if(rst || clear) begin
            counter<=0; latest<=0; latest_flags<=0; fresh<=0;
            servo_error<=0; servo_valid<=0; servo_flags<=0; servo_tick<=0;
            update_count<=0; skipped_ticks<=0;
        end else begin
            servo_valid<=0; servo_tick<=0;
            if(!enable) begin counter<=0; fresh<=0; end
            else begin
                if(measurement_valid) begin
                    latest<=measurement; latest_flags<=measurement_flags; fresh<=1;
                end
                if(counter==period-1'b1) begin
                    counter<=0; servo_tick<=1;
                    if(downstream_ready && (fresh || measurement_valid)) begin
                        servo_error<=measurement_valid ? measurement : latest;
                        servo_flags<=measurement_valid ? measurement_flags : latest_flags;
                        servo_valid<=1; fresh<=0;
                        update_count<=update_count+1'b1;
                    end else skipped_ticks<=skipped_ticks+1'b1;
                end else counter<=counter+1'b1;
            end
        end
    end
endmodule
