`timescale 1ns/1ps
// Hardware clock profile: REF1=50MHz, VCO2GHz, ADC250MHz, DACCLK/FPGA250MHz.
// Inherited FL4322 local reference: clock divider1 and FPGA divider4 changed to /4 for DAC250MHz 1x.
// DAC full-scale-current registers stay at reset defaults; no voltage inferred.
module hw_fl4322_register_table(input wire [7:0] index,output reg [23:0] word,output reg [1:0] chip);
always @* begin
word=0;chip=0;case(index)
8'd0:begin chip=2'd0;word=24'h00003c;end
8'd1:begin chip=2'd0;word=24'h000018;end
8'd2:begin chip=2'd0;word=24'h000400;end
8'd3:begin chip=2'd0;word=24'h00107c;end
8'd4:begin chip=2'd0;word=24'h001102;end
8'd5:begin chip=2'd0;word=24'h001200;end
8'd6:begin chip=2'd0;word=24'h001300;end
8'd7:begin chip=2'd0;word=24'h00140a;end
8'd8:begin chip=2'd0;word=24'h001500;end
8'd9:begin chip=2'd0;word=24'h001604;end
8'd10:begin chip=2'd0;word=24'h0017b4;end
8'd11:begin chip=2'd0;word=24'h001806;end
8'd12:begin chip=2'd0;word=24'h001900;end
8'd13:begin chip=2'd0;word=24'h001a00;end
8'd14:begin chip=2'd0;word=24'h001b00;end
8'd15:begin chip=2'd0;word=24'h001c02;end
8'd16:begin chip=2'd0;word=24'h001d00;end
8'd17:begin chip=2'd0;word=24'h023201;end
8'd18:begin chip=2'd0;word=24'h00f00a;end
8'd19:begin chip=2'd0;word=24'h00f10a;end
8'd20:begin chip=2'd0;word=24'h00f200;end
8'd21:begin chip=2'd0;word=24'h00f30a;end
8'd22:begin chip=2'd0;word=24'h00f40a;end
8'd23:begin chip=2'd0;word=24'h00f50a;end
8'd24:begin chip=2'd0;word=24'h014042;end
8'd25:begin chip=2'd0;word=24'h014143;end
8'd26:begin chip=2'd0;word=24'h014243;end
8'd27:begin chip=2'd0;word=24'h014342;end
8'd28:begin chip=2'd0;word=24'h019000;end
8'd29:begin chip=2'd0;word=24'h019180;end
8'd30:begin chip=2'd0;word=24'h019200;end
8'd31:begin chip=2'd0;word=24'h019311;end
8'd32:begin chip=2'd0;word=24'h019400;end
8'd33:begin chip=2'd0;word=24'h019500;end
8'd34:begin chip=2'd0;word=24'h019600;end
8'd35:begin chip=2'd0;word=24'h019700;end
8'd36:begin chip=2'd0;word=24'h019800;end
8'd37:begin chip=2'd0;word=24'h019900;end
8'd38:begin chip=2'd0;word=24'h019a00;end
8'd39:begin chip=2'd0;word=24'h019b00;end
8'd40:begin chip=2'd0;word=24'h019c00;end
8'd41:begin chip=2'd0;word=24'h019d00;end
8'd42:begin chip=2'd0;word=24'h019e11;end
8'd43:begin chip=2'd0;word=24'h019f00;end
8'd44:begin chip=2'd0;word=24'h01a000;end
8'd45:begin chip=2'd0;word=24'h01a120;end
8'd46:begin chip=2'd0;word=24'h01a200;end
8'd47:begin chip=2'd0;word=24'h01a300;end
8'd48:begin chip=2'd0;word=24'h01e000;end
8'd49:begin chip=2'd0;word=24'h01e102;end
8'd50:begin chip=2'd0;word=24'h023000;end
8'd51:begin chip=2'd0;word=24'h023100;end
8'd52:begin chip=2'd0;word=24'h001807;end
8'd53:begin chip=2'd0;word=24'h023201;end
8'd54:begin chip=2'd1;word=24'h000503;end
8'd55:begin chip=2'd1;word=24'h000800;end
8'd56:begin chip=2'd1;word=24'h000901;end
8'd57:begin chip=2'd1;word=24'h000b00;end
8'd58:begin chip=2'd1;word=24'h000d00;end
8'd59:begin chip=2'd1;word=24'h001000;end
8'd60:begin chip=2'd1;word=24'h001405;end
8'd61:begin chip=2'd1;word=24'h001501;end
8'd62:begin chip=2'd1;word=24'h001600;end
8'd63:begin chip=2'd1;word=24'h001785;end
8'd64:begin chip=2'd1;word=24'h001800;end
8'd65:begin chip=2'd1;word=24'h00ff01;end
8'd66:begin chip=2'd2;word=24'h00a000;end
8'd67:begin chip=2'd2;word=24'h008000;end
8'd68:begin chip=2'd2;word=24'h030000;end
8'd69:begin chip=2'd2;word=24'h040000;end
8'd70:begin chip=2'd2;word=24'h050000;end
8'd71:begin chip=2'd2;word=24'h08a000;end
8'd72:begin chip=2'd2;word=24'h0a0000;end
8'd73:begin chip=2'd2;word=24'h0c0000;end
8'd74:begin chip=2'd2;word=24'h0d0000;end
8'd75:begin chip=2'd2;word=24'h100000;end
8'd76:begin chip=2'd2;word=24'h110000;end
8'd77:begin chip=2'd2;word=24'h160000;end
8'd78:begin chip=2'd2;word=24'h1be400;end
8'd79:begin chip=2'd2;word=24'h1c0100;end
8'd80:begin chip=2'd2;word=24'h1d0100;end
8'd81:begin chip=2'd2;word=24'h1e0100;end
8'd82:begin chip=2'd2;word=24'h104800;end
8'd83:begin chip=2'd2;word=24'h170500;end
8'd84:begin chip=2'd2;word=24'h180200;end
8'd85:begin chip=2'd2;word=24'h180000;end
default:begin word=0;chip=0;end
endcase
end
endmodule
