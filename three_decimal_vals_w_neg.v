module three_decimal_vals_w_neg (
input [7:0]val,
output [6:0]seg7_neg_sign,
output [6:0]seg7_dig0,
output [6:0]seg7_dig1,
output [6:0]seg7_dig2
);

reg [3:0] result_one_digit;
reg [3:0] result_ten_digit;
reg [3:0] result_hundred_digit;
reg result_is_negative;
//reg [7:0] result;
reg [7:0]twos_comp;
/* convert the binary value into 4 signals */

always @(*)
begin
	//	result = {{3{val[5]}}, val};
	  result_is_negative = 0;
	  twos_comp = val;
	  
	  if (val[7] == 1) begin
		result_is_negative = 1;
		twos_comp = ~val + 1'b1;
	  end
	  
	  result_one_digit = twos_comp % 10;
	  result_ten_digit = (twos_comp / 10) % 10;
	  result_hundred_digit = twos_comp / 100;
end

/* instantiate the modules for each of the seven seg decoders including the negative one */
seven_segment seven1s (result_one_digit[3:0], seg7_dig0);
seven_segment seven10s (result_ten_digit[3:0], seg7_dig1);
seven_segment seven100s (result_hundred_digit[3:0], seg7_dig2); 
seven_segment_negative negBit (result_is_negative, seg7_neg_sign);

endmodule