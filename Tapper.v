module Tapper (
    //////////// CLOCK //////////
    input                      CLOCK_50,

    //////////// KEY //////////
    input              [3:0]    KEY,

    //////////// SW //////////
    input              [9:0]    SW,

    //////////// VGA //////////
    output                    VGA_BLANK_N,
    output            [7:0]    VGA_B,
    output                    VGA_CLK,
    output            [7:0]    VGA_G,
    output                    VGA_HS,
    output            [7:0]    VGA_R,
    output                    VGA_SYNC_N,
    output                    VGA_VS,

    //////////// SEG7 //////////
    output            [6:0]    HEX0,
    output            [6:0]    HEX1,
    output            [6:0]    HEX2,
    output            [6:0]    HEX3,

    //////////// LED //////////
    output            [9:0]    LEDR
);
	 
	 wire [6:0]seg7_neg_sign;
	 wire [6:0]seg7_dig0;
	 wire [6:0]seg7_dig1;
	 wire [6:0]seg7_dig2;

	 assign HEX0 = seg7_dig0;
	 assign HEX1 = seg7_dig1;
	 assign HEX2 = seg7_dig2; // constant 0
	 assign HEX3 = seg7_neg_sign;
	 wire [9:0]input_number;
	 assign input_number = score;

    wire clk;
    wire rst;
	 
	 three_decimal_vals_w_neg display(
	 input_number,
	 seg7_neg_sign,
	 seg7_dig0,
	 seg7_dig1,
	 seg7_dig2
	 );
reg [7:0] temp;
assign LEDR[7:0] = temp;
assign LEDR[9] = game_over;
    assign clk = CLOCK_50;
    assign rst = SW[0];

    wire [9:0] SW_db;
reg [9:0] led;
    debounce_switches db(
        .clk(clk),
        .rst(rst),
        .SW(SW),
        .SW_db(SW_db)
    );

    // VGA DRIVER
    wire active_pixels; // is on when we're in the active draw space
    wire frame_done;
    wire [9:0] x; // current x
    wire [9:0] y; // current y - 10 bits = 1024 ... a little bit more than we need

    /* the 3 signals to set to write to the picture */
    reg [14:0] the_vga_draw_frame_write_mem_address;
    reg [23:0] the_vga_draw_frame_write_mem_data;
    reg the_vga_draw_frame_write_a_pixel;

    /* This is the frame driver point that you can write to the draw_frame */
    vga_frame_driver my_frame_driver(
        .clk(clk),
        .rst(rst),

        .active_pixels(active_pixels),
        .frame_done(frame_done),

        .x(x),
        .y(y),

        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_CLK(VGA_CLK),
        .VGA_HS(VGA_HS),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_VS(VGA_VS),
        .VGA_B(VGA_B),
        .VGA_G(VGA_G),
        .VGA_R(VGA_R),

        /* writes to the frame buf - you need to figure out how x and y or other details provide a translation */
        .the_vga_draw_frame_write_mem_address(the_vga_draw_frame_write_mem_address),
        .the_vga_draw_frame_write_mem_data(the_vga_draw_frame_write_mem_data),
        .the_vga_draw_frame_write_a_pixel(the_vga_draw_frame_write_a_pixel)
    );

    reg [15:0] i;
    reg [7:0] S;
    reg [7:0] NS;

    parameter
        START           = 8'd0,
        // W2M is write to memory
        W2M_INIT        = 8'd1,
        W2M_COND        = 8'd2,
        W2M_INC         = 8'd3,
        W2M_DONE        = 8'd4,
        // The RFM = READ_FROM_MEMORY reading cycles
        RFM_INIT_START  = 8'd5,
        RFM_INIT_WAIT   = 8'd6,
        RFM_DRAWING     = 8'd7,
        ERROR           = 8'hFF;

    parameter MEMORY_SIZE = 16'd19200; // 160*120 // Number of memory spots ... highly reduced since memory is slow
    parameter PIXEL_VIRTUAL_SIZE = 16'd4; // Pixels per spot - therefore 4x4 pixels are drawn per memory location

    /* ACTUAL VGA RESOLUTION */
    parameter VGA_WIDTH = 16'd640;
    parameter VGA_HEIGHT = 16'd480;

    /* Our reduced RESOLUTION 160 by 120 needs a memory of 19,200 words each 24 bits wide */
    parameter VIRTUAL_PIXEL_WIDTH = VGA_WIDTH/PIXEL_VIRTUAL_SIZE; // 160
    parameter VIRTUAL_PIXEL_HEIGHT = VGA_HEIGHT/PIXEL_VIRTUAL_SIZE; // 120

    /* idx_location stores all the locations in the */
    reg [14:0] idx_location;

    // Just so I can see the address being calculated

    reg [9:0] player_x, player_y;
    reg [9:0] player_x_prev, player_y_prev;
    reg [9:0] customer_x [3:0], customer_y [3:0], cup_x [3:0], cup_y [3:0];
	 reg [9:0] customer_x_prev [3:0], customer_y_prev [3:0], cup_x_prev [3:0], cup_y_prev [3:0];
    reg [9:0] score_x, score_y;
    reg [7:0] score;
	 reg cupThrown[3:0];
	 reg cup0count = 0;
	reg game_over = 0;
	reg game_won = 0;
	reg game_start, game_start2, game_start3;
	reg [8:0]speed;

    parameter
        ROW1 = 10'd92,
        ROW2 = 10'd188,
        ROW3 = 10'd284,
        ROW4 = 10'd380,
		  PLAYERX = 10'd400,
		  CUSMINX = 10'd60,
		  CUSMAXX = 10'd380;

    // Declare registers to hold the previous state of keys for edge detection
    reg key0_prev, key2_prev, key3_prev;
    reg [31:0] move_counter;
		reg [31:0] cup_counter;
		reg [31:0] customer_counter;
    parameter MOVE_DELAY = 2000000; // Adjust this value to control movement speed
		parameter CUP_DELAY = 1000000; // Adjust this value to control cup speed
		parameter CUSTOMER_DELAY = 2000980; //Adjust this value to control customer speed
    always @(posedge clk or negedge rst)
    begin
        if (rst == 1'b0)
        begin
            // Initialize game state
            player_x <= PLAYERX;
            player_y <= ROW1;
            player_x_prev <= PLAYERX;
            player_y_prev <= ROW1;
            score <= 8'd0;
            key2_prev <= 1'b1;
            key3_prev <= 1'b1;
            move_counter <= 0;
            cup_counter <= 0;
				score <= 0;
				game_over <= 0;
				cup0count <= 0;

				customer_x[0] <= CUSMINX;
				customer_x[1] <= CUSMINX;
				customer_x[2] <= CUSMINX;
				customer_x[3] <= CUSMINX;
				customer_y[0] <= ROW1;
				customer_y[1] <= ROW2;
				customer_y[2] <= ROW3;
				customer_y[3] <= ROW4;

				cup_x[0] <= CUSMAXX;
				cup_x[1] <= CUSMAXX;
				cup_x[2] <= CUSMAXX;
				cup_x[3] <= CUSMAXX;
				cup_y[0] <= ROW1;
				cup_y[1] <= ROW2;
				cup_y[2] <= ROW3;
				cup_y[3] <= ROW4;
				
				cupThrown[0] <= 0;
				cupThrown[1] <= 0;
				cupThrown[2] <= 0;
				cupThrown[3] <= 0;
        end
        else
        begin
            // Store the previous position before updating
				if ((game_start || game_start2 || game_start3) && !game_won && !game_over)
				begin
				player_x <= PLAYERX;
            player_y <= ROW1;
            player_x_prev <= PLAYERX;
            player_y_prev <= ROW1;
				key0_prev <= 1'b1;
            key2_prev <= 1'b1;
            key3_prev <= 1'b1;
            move_counter <= 0;
            cup_counter <= 0;
			   cup0count <= 0;
				game_over <= 0;



				customer_x[0] <= CUSMINX;
				customer_x[1] <= CUSMINX;
				customer_x[2] <= CUSMINX;
				customer_x[3] <= CUSMINX;
				customer_y[0] <= ROW1;
				customer_y[1] <= ROW2;
				customer_y[2] <= ROW3;
				customer_y[3] <= ROW4;

				cup_x[0] <= CUSMAXX;
				cup_x[1] <= CUSMAXX;
				cup_x[2] <= CUSMAXX;
				cup_x[3] <= CUSMAXX;
				cup_y[0] <= ROW1;
				cup_y[1] <= ROW2;
				cup_y[2] <= ROW3;
				cup_y[3] <= ROW4;
				
				cupThrown[0] <= 0;
				cupThrown[1] <= 0;
				cupThrown[2] <= 0;
				cupThrown[3] <= 0;
			
				
				end
				
				else if (!game_start && !game_start2 && !game_start3 && !game_won && !game_over) begin
            player_x_prev <= player_x;
            player_y_prev <= player_y;

				cup_x_prev[0] <= cup_x[0];
				cup_x_prev[1] <= cup_x[1];
				cup_x_prev[2] <= cup_x[2];
				cup_x_prev[3] <= cup_x[3];


				customer_x_prev[0] <= customer_x[0];
				customer_x_prev[1] <= customer_x[1];
				customer_x_prev[2] <= customer_x[2];
				customer_x_prev[3] <= customer_x[3];

            // Update move_counter
            if (move_counter < MOVE_DELAY)
                move_counter <= move_counter + 1;
            else
                move_counter <= MOVE_DELAY;

				if (cup_counter < CUP_DELAY)
					 cup_counter <= cup_counter + 1;
				else
					 cup_counter <= CUP_DELAY;

				if (customer_counter <= CUSTOMER_DELAY)
					 customer_counter <= customer_counter + 1;
				else
					 cup_counter <= CUSTOMER_DELAY;

            // Horizontal movement
            if (KEY[1] == 1'b0 && move_counter == MOVE_DELAY)
            begin
                if (player_x > 0)
                    player_x <= player_x - 1; // Move left
                move_counter <= 0; // Reset move_counter after moving
            end else if(KEY[1] == 1'b1 && move_counter == MOVE_DELAY)
				begin
				//Reset player x when letting go
				player_x <= PLAYERX;
				end

            if (key2_prev == 1'b1 && KEY[2] == 1'b0)
            begin
                // move up
                case (player_y)
                    ROW1: player_y <= ROW4;
                    ROW2: player_y <= ROW1;
                    ROW3: player_y <= ROW2;
                    ROW4: player_y <= ROW3;
                    default: player_y <= ROW1;
                endcase
            end

            if (key3_prev == 1'b1 && KEY[3] == 1'b0)
            begin
                // move down
                case (player_y)
                    ROW1: player_y <= ROW2;
                    ROW2: player_y <= ROW3;
                    ROW3: player_y <= ROW4;
                    ROW4: player_y <= ROW1;
                    default: player_y <= ROW1;
                endcase
            end



			if (KEY[0] == 0 && player_x == PLAYERX && key0_prev == 1) begin
			case(player_y)
			ROW1: begin
				if (cup0count > 0)
				cupThrown[0] <= 1'b1;
				else
				cup0count = 1;
				end
			ROW2: cupThrown[1] <= 1'b1;
			ROW3: cupThrown[2] <= 1'b1;
			ROW4: cupThrown[3] <= 1'b1;
			default: begin
			cupThrown[0] <= 0;
			cupThrown[1] <= 0;
			cupThrown[2] <= 0;
			cupThrown[3] <= 0;
			end
			endcase
			end
			
           
			key0_prev <= KEY[0];
         key2_prev <= KEY[2];
         key3_prev <= KEY[3];

		if (cupThrown[0] == 1'b1)
		begin
		if (cup_counter == CUP_DELAY)
	begin
	if (cup_x[0] > customer_x[0])
	cup_x[0] <= cup_x[0] - 1; // Move left
	cup_counter <= 0; // Reset cup_counter after moving
	end
	else
	cup_counter <= cup_counter + 1;

	if (cup_x[0] <= customer_x[0] + 20)
	begin
	score <= score + 1;
	cupThrown[0] <= 0;
	customer_x[0] <= CUSMINX;
	cup_x[0] <= PLAYERX;
	end
	end
	if (cupThrown[1] == 1'b1)
	begin
	if (cup_counter == CUP_DELAY)
	begin
	if (cup_x[1] > customer_x[1])
	cup_x[1] <= cup_x[1] - 1; // Move left
	cup_counter <= 0; // Reset cup_counter after moving
	end
	else
	cup_counter <= cup_counter + 1;

	if (cup_x[1] <= customer_x[1] + 20)
	begin
	score <= score + 1;
	cupThrown[1] <= 0;
	customer_x[1] <= CUSMINX;
	cup_x[1] <= PLAYERX;
	end
	end
	if (cupThrown[2] == 1'b1)
	begin
	if (cup_counter == CUP_DELAY)
	begin
	if (cup_x[2] > customer_x[2])
	cup_x[2] <= cup_x[2] - 1; // Move left
	cup_counter <= 0; // Reset cup_counter after moving
	end
	else
	cup_counter <= cup_counter + 1;

	if (cup_x[2] <= customer_x[2] + 20)
	begin
	score <= score + 1;
	cupThrown[2] <= 0;
	customer_x[2] <= CUSMINX;
	cup_x[2] <= PLAYERX;
	end
	end
	if (cupThrown[3] == 1'b1)
	begin
	if (cup_counter == CUP_DELAY)
	begin
	if (cup_x[3] > customer_x[3])
	cup_x[3] <= cup_x[3] - 1; // Move left
	cup_counter <= 0; // Reset cup_counter after moving
	end
	else
	cup_counter <= cup_counter + 1;

	if (cup_x[3] <= customer_x[3] + 20)
	begin
	score <= score + 1;
	cupThrown[3] <= 0;
	customer_x[3] <= CUSMINX;
	cup_x[3] <= PLAYERX;
	end
	end

	if(customer_counter == CUSTOMER_DELAY)
	begin
	if(customer_x[0] >= CUSMAXX)
	begin
	customer_x[0] <= CUSMINX;
	game_over = 1;
	end
	else if(random % 13 == 0)
	customer_x[0] <= customer_x[0] + 3 + speed;

	if(customer_x[1] >= CUSMAXX)
	begin
	customer_x[1] <= CUSMINX;
	game_over = 1;
	end
	else if(random % 5 == 1)
	customer_x[1] <= customer_x[1] + 2 + speed;

	if(customer_x[2] >= CUSMAXX)
	begin
	game_over = 1;
	customer_x[2] <= CUSMINX;
	end
	else if(random % 13 == 2)
	customer_x[2] <= customer_x[2] + 1 + speed;

	if(customer_x[3] >= CUSMAXX)
	begin
	game_over = 1;
	customer_x[3] <= CUSMINX;
	end
	else if(random % 5 == 3)
	customer_x[3] <= customer_x[3] + 1 + speed;

	customer_counter <= 0;


	end
	end
   end
   end

   

		always @(posedge clk)
		begin
        if (active_pixels)
        begin
            // Set default to read from MIF file
            the_vga_draw_frame_write_a_pixel <= 1'b0;
            the_vga_draw_frame_write_mem_address <= (y ) + (x );
		
		if(game_start || game_start2 || game_start3) begin
		if (x <= 35) begin
			the_vga_draw_frame_write_mem_data <= 24'h000000;
         the_vga_draw_frame_write_a_pixel <= 1'b1;
			end
		end
		if(game_start || game_start2 || game_start3) begin
		//Draw START GAME
			if ((((x >= 116 && x <= 139) || (x >= 148 && x <= 187) || (x >= 204 && x <= 219) || (x >= 236 && x <= 259) || (x >= 276 && x <= 315) || (x >= 348 && x <= 363) || (x >= 389 && x <= 402) || (x >= 420 && x <= 427) || (x >= 452 && x <= 458) || (x >= 468 && x <= 499)) && (y >= 93 && y <= 100))
				|| (((x >= 108 && x <= 115) || (x >= 164 && x <= 171) || (x >= 196 && x <= 203) || (x >= 220 && x <= 227) || (x >= 236 && x <= 243) || (x >= 260 && x <= 267) || (x >= 292 && x <= 299) || (x >= 340 && x <= 347) || (x >= 380 && x <= 388) || (x >= 403 && x <= 410) || (x >= 420 && x <= 434) || (x >= 444 && x <= 458) || (x >= 468 && x <= 475)) && (y >= 101 && y <= 108))
			   || (((x >= 116 && x <= 130) || (x >= 164 && x <= 171) || (x >= 196 && x <= 227) || (x >= 236 && x <= 259) || (x >= 292 && x <= 299) || (x >= 240 && x <= 247) || (x >= 292 && x <= 299) || (x >= 340 && x <= 347) || (x >= 356 && x <= 371) || (x >= 380 && x <= 410) || (x >= 420 && x <= 427) || (x >= 436 && x <= 443) || (x >= 452 && x <= 458) || (x >= 468 && x <= 490)) && (y >= 109 && y <= 116)) 
				|| (((x >= 132 && x <= 139) || (x >= 164 && x <= 171) || (x >= 196 && x <= 203) || (x >= 220 && x <= 227) || (x >= 236 && x <= 243) || (x >= 259 && x <= 268) || (x >= 292 && x <= 299) || (x >= 363 && x <= 371) || (x >= 340 && x <= 347) || (x >= 361 && x <= 368) || (x >= 380 && x <= 388) || (x >= 403 && x <= 410) || (x >= 420 && x <= 427) || (x >= 452 && x <= 458) || (x >= 468 && x <= 475)) && (y >= 117 && y <= 124))
				|| (((x >= 109 && x <= 132) || (x >= 164 && x <= 171)  || (x >= 196 && x <= 203) || (x >= 220 && x <= 227) || (x >= 236 && x <= 243) || (x >= 259 && x <= 268) || (x >= 292 && x <= 299) || (x >= 348 && x <= 363) || (x >= 361 && x <= 368) || (x >= 380 && x <= 388) || (x >= 403 && x <= 410) || (x >= 420 && x <= 427) || (x >= 452 && x <= 458) || (x >= 468 && x <= 499)) && (y >= 125 && y <= 132)))
			begin
			the_vga_draw_frame_write_mem_data <= 24'hFFFFFF;
			the_vga_draw_frame_write_a_pixel <= 1'b1;
			end
		//Draw KEY 0
			else if ((((x >= 265 && x <= 269) || (x >= 277 && x <= 281) || (x >= 285 && x <= 301) || (x >= 305 && x <= 309) || (x >= 317 && x <= 321) || (x >= 329 && x <= 337)) && (y >= 293 && y <= 297))
			|| (((x >= 265 && x <= 269) || (x >= 272 && x <= 276) || (x >= 285 && x <= 289) || (x >= 305 && x <= 309) || (x >= 317 && x <= 321) || (x >= 324 && x <= 328) || (x >= 338 && x <= 340)) && (y >= 298 && y <= 302))
			|| (((x >= 265 && x <= 273) || (x >= 285 && x <= 297) || (x >= 310 && x <= 316) || (x >= 324 && x <= 328) || (x >= 338 && x <= 340)) && (y >= 303 && y <= 307))
		   || (((x >= 265 && x <= 269) || (x >= 272 && x <= 276) || (x >= 285 && x <= 289) || (x >= 310 && x <= 316) || (x >= 313 && x <= 317) || (x >= 324 && x <= 328) || (x >= 338 && x <= 340)) && (y >= 308 && y <= 312))
			|| (((x >= 265 && x <= 269) || (x >= 277 && x <= 281) || (x >= 285 && x <= 301) || (x >= 310 && x <= 316) || (x >= 329 && x <= 337)) && (y >= 313 && y <= 317)))
			begin
			the_vga_draw_frame_write_mem_data <= 24'hFFFFFF;
			the_vga_draw_frame_write_a_pixel <= 1'b1;
			end
			else
			begin
			the_vga_draw_frame_write_mem_data <= 24'h000000;
			the_vga_draw_frame_write_a_pixel <= 1'b1;
			end
			if(game_start && !game_start2 && !game_start3)
			begin
				if ((x >= 319 && x <= 321) && (y >= 230 && y <= 280))
				begin
				the_vga_draw_frame_write_mem_data <= 24'hFFFFFF;
				the_vga_draw_frame_write_a_pixel <= 1'b1;
				end
				end
				  end
				  else
				  begin
						the_vga_draw_frame_write_a_pixel <= 1'b0;
				  end
			 end
		if(!game_start && !game_start2 && !game_start3 && (game_won || game_over)) begin
		if(game_won)
		begin
			the_vga_draw_frame_write_mem_data <= 24'h00FF00;
			the_vga_draw_frame_write_a_pixel <= 1'b1;
			end
		if(game_over)
		begin
			the_vga_draw_frame_write_mem_data <= 24'hFF0000;
			the_vga_draw_frame_write_a_pixel <= 1'b1;
			end
		end
		if(!game_start && !game_start2 && !game_start3 && !game_won && !game_over) begin
            // Check conditions and override if necessary
				if (x <= 40) begin
					the_vga_draw_frame_write_mem_data <= 24'h22249C;
                the_vga_draw_frame_write_a_pixel <= 1'b1;
				end
            else if (x >= player_x && x < player_x + 20 && y >= player_y && y < player_y + 40)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h7F2B0A; // Player color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            else if (x >= player_x_prev && x < player_x_prev + 20 && y >= player_y_prev && y < player_y_prev + 40)
            begin
                the_vga_draw_frame_write_a_pixel <= 1'b0;
            end
            else if (x >= customer_x[0] && x < customer_x[0] + 20 && y >= customer_y[0] && y < customer_y[0] + 20)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h00FF00; // Customer color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            else if (x >= customer_x[1] && x < customer_x[1] + 20 && y >= customer_y[1] && y < customer_y[1] + 20)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h00FF00;
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            else if (x >= customer_x[2] && x < customer_x[2] + 20 && y >= customer_y[2] && y < customer_y[2] + 20)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h00FF00;
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            else if (x >= customer_x[3] && x < customer_x[3] + 20 && y >= customer_y[3] && y < customer_y[3] + 20)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h00FF00;
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            else if (x >= cup_x[0] && x < cup_x[0] + 10 && y >= cup_y[0] && y < cup_y[0] + 10 && cupThrown[0] == 1'b1 && cup_x[0] < PLAYERX)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h7F2B0A; // Cup color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
				else if (x >= cup_x_prev[0] && x < cup_x_prev[0] + 10 && y >= cup_y[0] && y < cup_y[0] + 10 && cupThrown[0] == 1'b1)
            begin
                the_vga_draw_frame_write_a_pixel <= 1'b0;
            end
            else if (x >= cup_x[1] && x < cup_x[1] + 10 && y >= cup_y[1] && y < cup_y[1] + 10 && cupThrown[1] == 1'b1 && cup_x[1] < PLAYERX)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h7F2B0A; // Cup color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
				else if (x >= cup_x_prev[1] && x < cup_x_prev[1] + 10 && y >= cup_y[1] && y < cup_y[1] + 10 && cupThrown[1] == 1'b1)
            begin
                the_vga_draw_frame_write_a_pixel <= 1'b0;
            end
            else if (x >= cup_x[2] && x < cup_x[2] + 10 && y >= cup_y[2] && y < cup_y[2] + 10 && cupThrown[2] == 1'b1 && cup_x[2] < PLAYERX)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h7F2B0A; // Cup color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
				else if (x >= cup_x_prev[2] && x < cup_x_prev[2] + 10 && y >= cup_y[2] && y < cup_y[2] + 10 && cupThrown[2] == 1'b1)
            begin
                the_vga_draw_frame_write_a_pixel <= 1'b0;
            end
            else if (x >= cup_x[3] && x < cup_x[3] + 10 && y >= cup_y[3] && y < cup_y[3] + 10 && cupThrown[3] == 1'b1 && cup_x[3] < PLAYERX)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h7F2B0A; // Cup color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
				else if (x >= cup_x_prev[3] && x < cup_x_prev[3] + 10 && y >= cup_y[3] && y < cup_y[3] + 10 && cupThrown[3] == 1'b1)
            begin
                the_vga_draw_frame_write_a_pixel <= 1'b0;
            end
            else
            begin
                // Read from MIF file for uncovered pixels
                the_vga_draw_frame_write_a_pixel <= 1'b0;
            end
		end
		end
		

		reg [7:0] GAMESTATE;
		reg [7:0] GAMESTATENEXT;

		parameter
		GAMESTART  =  8'd0,
		GAMELVL1   =  8'd1,
		GAMESTART2 =  8'd2,
		GAMELVL2   =  8'd3,
		GAMESTART3 =  8'd4,
		GAMELVL3   =  8'd5,
		GAMEWIN    =  8'd6,
		GAMELOSS   =  8'd7;

		always @(posedge clk or negedge rst) begin
		if (!rst) begin
		GAMESTATE <= GAMESTART;
		game_start <= 1;
		temp <= 1;
		game_won <= 0;
		speed <= 0;
		end
		else
	   if(GAMESTATE == GAMESTART && KEY[0] == 0) begin
		game_start <= 0;
		speed <= 1;
		GAMESTATE <= GAMELVL1;
		end
		else if(GAMESTATE == GAMELVL1 && score == 12) begin
		temp <= 3;
		game_start2 <= 1;
		GAMESTATE <= GAMESTART2;
		end
		else if(GAMESTATE == GAMESTART2 && KEY[0] == 0) begin
		game_start2 <= 0;
		speed <= 5;
		GAMESTATE <= GAMELVL2;
		end
		else if(GAMESTATE == GAMELVL2 && score == 24) begin
		temp <= 7;
		game_start3 <= 1;
		GAMESTATE <= GAMESTART3;
		end
		else if(GAMESTATE == GAMESTART3 && KEY[0] == 0) begin
		game_start3 <= 0;
		game_start2 <= 0;
		game_start <= 0;
		speed <= 10;
		GAMESTATE <= GAMELVL3;
		end
		else if(GAMESTATE == GAMELVL3 && score == 36) begin
		GAMESTATE <= GAMEWIN;
		game_won <= 1;
		game_start3 <= 0;
		game_start2 <= 0;
		game_start <= 0;
		end
		else if (game_won) begin
		game_start3 <= 0;
		game_start2 <= 0;
		game_start <= 0;
		end
		else if (game_over) begin
		game_start3 <= 0;
		game_start2 <= 0;
		game_start <= 0;
		GAMESTATE <= GAMELOSS;
		end
		end


		always @(*) begin
		case(GAMESTATE)
		GAMESTART:  GAMESTATENEXT = GAMELVL1;
		GAMELVL1:   GAMESTATENEXT = GAMESTART2;
		GAMESTART2: GAMESTATENEXT = GAMELVL2;
		GAMELVL2:   GAMESTATENEXT = GAMESTART3;
		GAMESTART3: GAMESTATENEXT = GAMELVL3;
		GAMELVL3:   GAMESTATENEXT = GAMEWIN;
		GAMEWIN:    GAMESTATENEXT = GAMESTART;
		GAMELOSS:   GAMESTATENEXT = GAMESTART;
		endcase
		end








		reg[8:0] random;

		always @(posedge clk or negedge rst)
		begin
		if(!rst)
		random = 0;
		else
		 random = random + 1;
		end


endmodule