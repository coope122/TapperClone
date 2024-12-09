module seven_segment_negative(i,o);

input i;
output reg [6:0]o; // a, b, c, d, e, f, g

always @(*)
begin
o[0] = 1;
o[1] = 1;
o[2] = 1;
o[3] = 1;
o[4] = 1;
o[5] = 1;
o[6] = ~i;
end


endmodule