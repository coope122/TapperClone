module clks_converter(clk, update, out_clk);
input clk;
output reg update,out_clk;
reg [21:0]count;	
reg a;
	
//controls how fast the player and the blocks update
always@(posedge clk)
	begin
		count <= count + 22'd1;
		if(count == 22'd1250000)
		begin
			update <= ~update;
			count <= 22'd0;
		end	
	end
	
//converts the board clock (50MHz) to  the VGA clock (25MHz)
always@(posedge clk)
	begin
		a <= ~a; 
		out_clk <= a;
	end

endmodule 