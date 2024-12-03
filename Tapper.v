module Tapper	(
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

    // Turn off all displays.
    assign    HEX0        =    7'h00;
    assign    HEX1        =    7'h00;
    assign    HEX2        =    7'h00;
    assign    HEX3        =    7'h00;

    // DONE STANDARD PORT DECLARATION ABOVE
    /* HANDLE SIGNALS FOR CIRCUIT */
    wire clk;
    wire rst;

    assign clk = CLOCK_50;
    assign rst = KEY[0];

    wire [9:0] SW_db;

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
    assign LEDR[9:0] = idx_location[9:0]; // Adjusted to fit 10 LEDs

    reg [31:0] game_clock;
    always @(posedge clk)
    begin
        if (frame_done)
        begin
            game_clock <= game_clock + 1;
            if (game_clock >= 120) // Update game state every 120 frames
            begin
                game_clock <= 0;
                // Update game state here

            end
        end
    end

    reg [9:0] player_x, player_y;
    reg [9:0] player_x_prev, player_y_prev; // Added registers for previous position
    reg [9:0] customer_x [3:0], customer_y [3:0];
    reg [9:0] score_x, score_y;
    reg [7:0] score;

    parameter
        ROW1 = 10'd92,
        ROW2 = 10'd188,
        ROW3 = 10'd284,
        ROW4 = 10'd380;

    // Declare registers to hold the previous state of keys for edge detection
    reg key2_prev, key3_prev;
    reg [31:0] move_counter;
    parameter MOVE_DELAY = 1000000; // Adjust this value to control movement speed

    always @(posedge clk or negedge rst)
    begin
        if (rst == 1'b0)
        begin
            // Initialize game state
            player_x <= 10'd512;
            player_y <= ROW1;
            player_x_prev <= 10'd512; 
            player_y_prev <= ROW1;
            score <= 8'd0;
            key2_prev <= 1'b1;
            key3_prev <= 1'b1;
            move_counter <= 0;
            // Initialize other game elements...
        end
        else
        begin
            // Store the previous position before updating
            player_x_prev <= player_x;
            player_y_prev <= player_y;

            // Update move_counter
            if (move_counter < MOVE_DELAY)
                move_counter <= move_counter + 1;
            else
                move_counter <= MOVE_DELAY;

            // Handle horizontal movement
            if (KEY[1] == 1'b0 && move_counter == MOVE_DELAY)
            begin
                if (player_x > 0)
                    player_x <= player_x - 1; // Move left
                move_counter <= 0; // Reset move_counter after moving
            end else if(KEY[1] == 1'b1 && move_counter == MOVE_DELAY) 
				begin
				//Reset player x when letting go
					player_x <= 10'd512;
				end
				
            // Vertical movement with edge detection
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

            
            key2_prev <= KEY[2];
            key3_prev <= KEY[3];

            // Update other game elements...
        end
    end

    always @(posedge clk)
    begin
        if (active_pixels)
        begin
            // Set default to read from MIF file
            the_vga_draw_frame_write_a_pixel <= 1'b0;
            the_vga_draw_frame_write_mem_address <= (y / PIXEL_VIRTUAL_SIZE) * VIRTUAL_PIXEL_WIDTH + (x / PIXEL_VIRTUAL_SIZE);

            // Check conditions and override if necessary
            if (x >= player_x && x < player_x + 20 && y >= player_y && y < player_y + 20)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h7F2B0A; // Player color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            else if (x >= player_x_prev && x < player_x_prev + 20 && y >= player_y_prev && y < player_y_prev + 20)
            begin
                the_vga_draw_frame_write_mem_data <= 24'hFFFFFF; // Background color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            else if (x >= customer_x[0] && x < customer_x[0] + 20 && y >= customer_y[0] && y < customer_y[0] + 20)
            begin
                the_vga_draw_frame_write_mem_data <= 24'h00FF00; // Customer color
                the_vga_draw_frame_write_a_pixel <= 1'b1;
            end
            // Repeat for other customers and score if necessary...
            else
            begin
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
