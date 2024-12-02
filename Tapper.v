module Tapper	(
    	//////////// ADC //////////
	//output		          		ADC_CONVST,
	//output		          		ADC_DIN,
	//input 		          		ADC_DOUT,
	//output		          		ADC_SCLK,

	//////////// Audio //////////
	//input 		          		AUD_ADCDAT,
	//inout 		          		AUD_ADCLRCK,
	//inout 		          		AUD_BCLK,
	//output		          		AUD_DACDAT,
	//inout 		          		AUD_DACLRCK,
	//output		          		AUD_XCK,

	//////////// CLOCK //////////
	//input 		          		CLOCK2_50,
	//input 		          		CLOCK3_50,
	//input 		          		CLOCK4_50,
	input 		          		CLOCK_50,

	//////////// SDRAM //////////
	//output		    [12:0]		DRAM_ADDR,
	//output		     [1:0]		DRAM_BA,
	//output		          		DRAM_CAS_N,
	//output		          		DRAM_CKE,
	//output		          		DRAM_CLK,
	//output		          		DRAM_CS_N,
	//inout 		    [15:0]		DRAM_DQ,
	//output		          		DRAM_LDQM,
	//output		          		DRAM_RAS_N,
	//output		          		DRAM_UDQM,
	//output		          		DRAM_WE_N,

	//////////// I2C for Audio and Video-In //////////
	//output		          		FPGA_I2C_SCLK,
	//inout 		          		FPGA_I2C_SDAT,

	//////////// SEG7 //////////
	output		     [6:0]		HEX0,
	output		     [6:0]		HEX1,
	output		     [6:0]		HEX2,
	output		     [6:0]		HEX3,
	//output		     [6:0]		HEX4,
	//output		     [6:0]		HEX5,

	//////////// IR //////////
	//input 		          		IRDA_RXD,
	//output		          		IRDA_TXD,

	//////////// KEY //////////
	input 		     [3:0]		KEY,

	//////////// LED //////////
	output		     [9:0]		LEDR,

	//////////// PS2 //////////
	//inout 		          		PS2_CLK,
	//inout 		          		PS2_CLK2,
	//inout 		          		PS2_DAT,
	//inout 		          		PS2_DAT2,

	//////////// SW //////////
	input 		     [9:0]		SW,

	//////////// Video-In //////////
	//input 		          		TD_CLK27,
	//input 		     [7:0]		TD_DATA,
	//input 		          		TD_HS,
	//output		          		TD_RESET_N,
	//input 		          		TD_VS,

	//////////// VGA //////////
	output		          		VGA_BLANK_N,
	output		     [7:0]		VGA_B,
	output		          		VGA_CLK,
	output		     [7:0]		VGA_G,
	output		          		VGA_HS,
	output		     [7:0]		VGA_R,
	output		          		VGA_SYNC_N,
	output		          		VGA_VS

	//////////// GPIO_0, GPIO_0 connect to GPIO Default //////////
	//inout 		    [35:0]		GPIO_0,

	//////////// GPIO_1, GPIO_1 connect to GPIO Default //////////
	//inout 		    [35:0]		GPIO_1

);

// Turn off all displays.
assign	HEX0		=	7'h00;
assign	HEX1		=	7'h00;
assign	HEX2		=	7'h00;
assign	HEX3		=	7'h00;

// DONE STANDARD PORT DECLARATION ABOVE
/* HANDLE SIGNALS FOR CIRCUIT */
wire clk;
wire rst;

assign clk = CLOCK_50;
assign rst = KEY[0];

wire [9:0]SW_db;

debounce_switches db(
.clk(clk),
.rst(rst),
.SW(SW), 
.SW_db(SW_db)
);

// VGA DRIVER
wire active_pixels; // is on when we're in the active draw space
wire frame_done;
wire [9:0]x; // current x
wire [9:0]y; // current y - 10 bits = 1024 ... a little bit more than we need

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

reg [15:0]i;
reg [7:0]S;
reg [7:0]NS;
parameter 
	START 			= 8'd0,
	// W2M is write to memory
	W2M_INIT 		= 8'd1,
	W2M_COND 		= 8'd2,
	W2M_INC 			= 8'd3,
	W2M_DONE 		= 8'd4,
	// The RFM = READ_FROM_MEMOERY reading cycles
	RFM_INIT_START = 8'd5,
	RFM_INIT_WAIT 	= 8'd6,
	RFM_DRAWING 	= 8'd7,
	ERROR 			= 8'hFF;

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
assign LEDR = idx_location;

reg [31:0] game_clock;
always @(posedge clk)
begin
    if (frame_done)
    begin
        game_clock <= game_clock + 1;
        if (game_clock >= 120) // Update game state every 60 frames
        begin
            game_clock <= 0;
            // Update game state here

        end
    end
end

reg [9:0] player_x, player_y;
reg [9:0] customer_x [3:0], customer_y [3:0];
reg [9:0] score_x, score_y;
reg [7:0] score;

parameter
	ROW1 = 10'd90,
	ROW2 = 10'd186,
	ROW3 = 10'd282,
	ROW4 = 10'd378;

always @(posedge clk or negedge rst)
begin
    if (rst == 1'b0)
    begin
        // Initialize game state
        player_x <= 10'd512;
        player_y <= ROW1;
        score <= 8'd0;
        // Initialize enemies...
    end
    else
    begin
        // Handle player movement
        if (KEY[1] == 1'b0 && game_clock % 120 == 0) player_x <= player_x - 1; // Move left
		  if (KEY[1] == 1'b1) player_x <= 10'd512; //Reset X Position
        if (KEY[2] == 1'b0) begin // Move Up
				case(player_y)
					ROW1: player_y <= ROW4;
					ROW2: player_y <= ROW1;
					ROW3: player_y <= ROW2;
					ROW4: player_y <= ROW3;
				endcase
			end
        if (KEY[3] == 1'b0) begin // Move down
				case(player_y)
					ROW1: player_y <= ROW2;
					ROW2: player_y <= ROW3;
					ROW3: player_y <= ROW4;
					ROW4: player_y <= ROW1;
				endcase
			end
        // Update enemy positions
        // Check for collisions
        // Update score
    end
end

always @(posedge clk)
begin
    if (active_pixels)
    begin
        // Set default to read from MIF file
        the_vga_draw_frame_write_a_pixel <= 1'b0;
        the_vga_draw_frame_write_mem_address <= (y/4) * VIRTUAL_PIXEL_WIDTH + (x/4);
        
        // Check conditions and override if necessary
        if (x >= player_x && x < player_x + 20 && y >= player_y && y < player_y + 20) begin
            the_vga_draw_frame_write_mem_data <= 24'h7F2B0A;
            the_vga_draw_frame_write_a_pixel <= 1'b1;
        end
        else if (x >= customer_x[0] && x < customer_x[0] + 20 && y >= customer_y[0] && y < customer_y[0] + 20) begin
            the_vga_draw_frame_write_mem_data <= 24'h00FF00;
            the_vga_draw_frame_write_a_pixel <= 1'b1;
        end
        else if (x >= customer_x[1] && x < customer_x[1] + 20 && y >= customer_y[1] && y < customer_y[1] + 20) begin
            the_vga_draw_frame_write_mem_data <= 24'h00FF00;
            the_vga_draw_frame_write_a_pixel <= 1'b1;
        end
        else if (x >= customer_x[2] && x < customer_x[2] + 20 && y >= customer_y[2] && y < customer_y[2] + 20) begin
            the_vga_draw_frame_write_mem_data <= 24'h00FF00;
            the_vga_draw_frame_write_a_pixel <= 1'b1;
        end
        else if (x >= customer_x[3] && x < customer_x[3] + 20 && y >= customer_y[3] && y < customer_y[3] + 20) begin
            the_vga_draw_frame_write_mem_data <= 24'h00FF00;
            the_vga_draw_frame_write_a_pixel <= 1'b1;
        end
        else if (x >= score_x && x < score_x + 20 && y >= score_y && y < score_y + 20) begin
            the_vga_draw_frame_write_mem_data <= 24'h00FF00;
            the_vga_draw_frame_write_a_pixel <= 1'b1;
        end
        else begin
            // Read from MIF file for uncovered pixels
            the_vga_draw_frame_write_a_pixel <= 1'b0;
        end
    end
    else
    begin
        the_vga_draw_frame_write_a_pixel <= 1'b0;
    end
end
endmodule