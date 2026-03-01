/*
 * Copyright (c) 2024 Greg Davill
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

parameter LOGO_SIZE = 64;  // Size of the logo in pixels
parameter DISPLAY_WIDTH = 640;  // VGA display width
parameter DISPLAY_HEIGHT = 480;  // VGA display height

`define COLOR_WHITE 3'd7

module tt_um_gregdavill_vga_demo (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  reg [1:0] R;
  reg [1:0] G;
  reg [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // Configuration
  wire cfg_tile = ui_in[0];

  // TinyVGA PMOD
  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in[7:1], uio_in};

  reg [9:0] prev_y;

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  reg [9:0] logo_left;
  reg [9:0] logo_top;
  reg dir_x;
  reg dir_y;
  reg [7:0] angle;

  wire [9:0] x = pix_x - logo_left;
  wire [9:0] y = pix_y - logo_top;
  wire logo_pixels = cfg_tile || (x[9:6] == 0 && y[9:6] == 0);

  // Rotation: inverse-rotate display coords to get source coords
  wire signed [7:0] cos_val;
  wire signed [7:0] sin_val;
  sincos_rom trig (.angle(angle), .cos_out(cos_val), .sin_out(sin_val));

  wire signed [6:0] cx = $signed({1'b0, x[5:0]}) - 7'sd32;
  wire signed [6:0] cy = $signed({1'b0, y[5:0]}) - 7'sd32;
  wire signed [15:0] rx_scaled = cx * cos_val + cy * sin_val;
  wire signed [15:0] ry_scaled = cy * cos_val - cx * sin_val;
  wire signed [8:0]  rx = $signed(rx_scaled[14:6]) + 9'd32;
  wire signed [8:0]  ry = $signed(ry_scaled[14:6]) + 9'd32;
  wire rot_in_bounds = (rx[8:6] == 3'b000) && (ry[8:6] == 3'b000);

  wire [5:0] pixel_color_raw;
  wire [5:0] pixel_color = rot_in_bounds ? pixel_color_raw : 6'd0;

  bitmap_rom rom1 (
      .x(x[5:0]),
      .y(y[5:0]),
      .color(pixel_color_raw)
  );

  // RGB output logic
  always @(posedge clk) begin
    if (~rst_n) begin
      R <= 0;
      G <= 0;
      B <= 0;
    end else begin
      R <= 0;
      G <= 0;
      B <= 0;
      if (video_active && logo_pixels) begin
        R <= pixel_color[5:4];
        G <= pixel_color[3:2];
        B <= pixel_color[1:0];
      end
    end
  end

  // Bouncing logic
  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left <= 200;
      logo_top <= 200;
      dir_y <= 0;
      dir_x <= 1;
      angle <= 0;
    end else begin
      prev_y <= pix_y;
      if (pix_y == 0 && prev_y != pix_y) begin
        angle <= angle + 1;
        logo_left <= logo_left + (dir_x ? 1 : -1);
        logo_top  <= logo_top + (dir_y ? 1 : -1);
        if (logo_left - 1 == 0 && !dir_x) begin
          dir_x <= 1;
        end
        if (logo_left + 1 == DISPLAY_WIDTH - LOGO_SIZE && dir_x) begin
          dir_x <= 0;
        end
        if (logo_top - 1 == 0 && !dir_y) begin
          dir_y <= 1;
        end
        if (logo_top + 1 == DISPLAY_HEIGHT - LOGO_SIZE && dir_y) begin
          dir_y <= 0;
        end
      end
    end
  end

endmodule

`default_nettype none

/*
Video sync generator, used to drive a VGA monitor.
Timing from: https://en.wikipedia.org/wiki/Video_Graphics_Array
To use:
- Wire the hsync and vsync signals to top level outputs
- Add a 3-bit (or more) "rgb" output to the top level
*/

module vga_sync_generator (
    clk,
    reset,
    hsync,
    vsync,
    display_on,
    hpos,
    vpos
);

  input clk;
  input reset;
  output reg hsync, vsync;
  output display_on;
  output reg [9:0] hpos;
  output reg [9:0] vpos;

  // declarations for TV-simulator sync parameters
  // horizontal constants
  parameter H_DISPLAY = 640;  // horizontal display width
  parameter H_BACK = 48;  // horizontal left border (back porch)
  parameter H_FRONT = 16;  // horizontal right border (front porch)
  parameter H_SYNC = 96;  // horizontal sync width
  // vertical constants
  parameter V_DISPLAY = 480;  // vertical display height
  parameter V_TOP = 33;  // vertical top border
  parameter V_BOTTOM = 10;  // vertical bottom border
  parameter V_SYNC = 2;  // vertical sync # lines
  // derived constants
  parameter H_SYNC_START = H_DISPLAY + H_FRONT;
  parameter H_SYNC_END = H_DISPLAY + H_FRONT + H_SYNC - 1;
  parameter H_MAX = H_DISPLAY + H_BACK + H_FRONT + H_SYNC - 1;
  parameter V_SYNC_START = V_DISPLAY + V_BOTTOM;
  parameter V_SYNC_END = V_DISPLAY + V_BOTTOM + V_SYNC - 1;
  parameter V_MAX = V_DISPLAY + V_TOP + V_BOTTOM + V_SYNC - 1;

  wire hmaxxed = (hpos == H_MAX) || reset;  // set when hpos is maximum
  wire vmaxxed = (vpos == V_MAX) || reset;  // set when vpos is maximum

  // horizontal position counter
  always @(posedge clk) begin
    hsync <= (hpos >= H_SYNC_START && hpos <= H_SYNC_END);
    if (hmaxxed) hpos <= 0;
    else hpos <= hpos + 1;
  end

  // vertical position counter
  always @(posedge clk) begin
    vsync <= (vpos >= V_SYNC_START && vpos <= V_SYNC_END);
    if (hmaxxed)
      if (vmaxxed) vpos <= 0;
      else vpos <= vpos + 1;
  end

  // display_on is set when beam is in "safe" visible frame
  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

endmodule

// --------------------------------------------------------

module palette (
    input  wire [2:0] color_index,
    output wire [5:0] rrggbb
);

  reg [5:0] palette[7:0];

  initial begin
    palette[0] = 6'b001011;  // cyan
    palette[1] = 6'b110110;  // pink
    palette[2] = 6'b101101;  // green
    palette[3] = 6'b111000;  // orange
    palette[4] = 6'b110011;  // purple
    palette[5] = 6'b011111;  // yellow 
    palette[6] = 6'b110001;  // red
    palette[7] = 6'b111111;  // white
  end

  assign rrggbb = palette[color_index];

endmodule

// --------------------------------------------------------

module bitmap_rom (
    input wire [5:0] x,
    input wire [5:0] y,
    output wire [5:0] color
);

  reg [5:0] palette[7:0];
  reg [7:0] plane0[511:0];
  reg [7:0] plane1[511:0];
  reg [7:0] plane2[511:0];
  initial begin
    palette[0] = 6'h3f;
    palette[1] = 6'h3a;
    palette[2] = 6'h25;
    palette[3] = 6'h15;
    palette[4] = 6'h15;
    palette[5] = 6'h00;
    palette[6] = 6'h00;
    palette[7] = 6'h00;
    plane0[  0] = 8'h6e;  plane0[  1] = 8'hff;  plane0[  2] = 8'hff;  plane0[  3] = 8'he0;  plane0[  4] = 8'hcf;  plane0[  5] = 8'hff;  plane0[  6] = 8'hf9;  plane0[  7] = 8'hdf;
    plane0[  8] = 8'hff;  plane0[  9] = 8'hff;  plane0[ 10] = 8'hdf;  plane0[ 11] = 8'hff;  plane0[ 12] = 8'hff;  plane0[ 13] = 8'hff;  plane0[ 14] = 8'hfd;  plane0[ 15] = 8'hbf;
    plane0[ 16] = 8'h6f;  plane0[ 17] = 8'hff;  plane0[ 18] = 8'hfb;  plane0[ 19] = 8'hdf;  plane0[ 20] = 8'hff;  plane0[ 21] = 8'h7b;  plane0[ 22] = 8'hf8;  plane0[ 23] = 8'hcf;
    plane0[ 24] = 8'h6b;  plane0[ 25] = 8'hfe;  plane0[ 26] = 8'hfe;  plane0[ 27] = 8'hdf;  plane0[ 28] = 8'hff;  plane0[ 29] = 8'h7b;  plane0[ 30] = 8'hf7;  plane0[ 31] = 8'hff;
    plane0[ 32] = 8'hef;  plane0[ 33] = 8'h7f;  plane0[ 34] = 8'hff;  plane0[ 35] = 8'hef;  plane0[ 36] = 8'hff;  plane0[ 37] = 8'h3b;  plane0[ 38] = 8'hf5;  plane0[ 39] = 8'hff;
    plane0[ 40] = 8'h77;  plane0[ 41] = 8'hde;  plane0[ 42] = 8'hff;  plane0[ 43] = 8'hcf;  plane0[ 44] = 8'hff;  plane0[ 45] = 8'h3b;  plane0[ 46] = 8'hf4;  plane0[ 47] = 8'hff;
    plane0[ 48] = 8'h09;  plane0[ 49] = 8'hff;  plane0[ 50] = 8'hff;  plane0[ 51] = 8'h43;  plane0[ 52] = 8'hc0;  plane0[ 53] = 8'h39;  plane0[ 54] = 8'hf9;  plane0[ 55] = 8'hff;
    plane0[ 56] = 8'hf4;  plane0[ 57] = 8'he2;  plane0[ 58] = 8'hdf;  plane0[ 59] = 8'h02;  plane0[ 60] = 8'h00;  plane0[ 61] = 8'h3f;  plane0[ 62] = 8'hff;  plane0[ 63] = 8'hff;
    plane0[ 64] = 8'hfc;  plane0[ 65] = 8'hef;  plane0[ 66] = 8'h7f;  plane0[ 67] = 8'h02;  plane0[ 68] = 8'h00;  plane0[ 69] = 8'h3e;  plane0[ 70] = 8'ha0;  plane0[ 71] = 8'hff;
    plane0[ 72] = 8'hff;  plane0[ 73] = 8'he7;  plane0[ 74] = 8'h7f;  plane0[ 75] = 8'h00;  plane0[ 76] = 8'h02;  plane0[ 77] = 8'hf8;  plane0[ 78] = 8'h40;  plane0[ 79] = 8'hff;
    plane0[ 80] = 8'h7f;  plane0[ 81] = 8'hf7;  plane0[ 82] = 8'h7f;  plane0[ 83] = 8'h00;  plane0[ 84] = 8'h00;  plane0[ 85] = 8'h30;  plane0[ 86] = 8'h80;  plane0[ 87] = 8'hfd;
    plane0[ 88] = 8'h79;  plane0[ 89] = 8'hf7;  plane0[ 90] = 8'h7f;  plane0[ 91] = 8'h00;  plane0[ 92] = 8'h00;  plane0[ 93] = 8'h7c;  plane0[ 94] = 8'h80;  plane0[ 95] = 8'hff;
    plane0[ 96] = 8'hbb;  plane0[ 97] = 8'hff;  plane0[ 98] = 8'h7f;  plane0[ 99] = 8'h29;  plane0[100] = 8'h10;  plane0[101] = 8'h60;  plane0[102] = 8'h80;  plane0[103] = 8'hff;
    plane0[104] = 8'hf3;  plane0[105] = 8'hf8;  plane0[106] = 8'hfb;  plane0[107] = 8'h01;  plane0[108] = 8'h07;  plane0[109] = 8'h78;  plane0[110] = 8'h00;  plane0[111] = 8'hfe;
    plane0[112] = 8'h1f;  plane0[113] = 8'hf8;  plane0[114] = 8'hfb;  plane0[115] = 8'hf8;  plane0[116] = 8'h87;  plane0[117] = 8'hf8;  plane0[118] = 8'h80;  plane0[119] = 8'hfc;
    plane0[120] = 8'h9f;  plane0[121] = 8'hff;  plane0[122] = 8'hfb;  plane0[123] = 8'h0f;  plane0[124] = 8'h40;  plane0[125] = 8'hfd;  plane0[126] = 8'hc0;  plane0[127] = 8'hf4;
    plane0[128] = 8'h9f;  plane0[129] = 8'hff;  plane0[130] = 8'hf9;  plane0[131] = 8'h01;  plane0[132] = 8'h03;  plane0[133] = 8'hfc;  plane0[134] = 8'hc0;  plane0[135] = 8'hfc;
    plane0[136] = 8'hff;  plane0[137] = 8'hfe;  plane0[138] = 8'h3d;  plane0[139] = 8'hfc;  plane0[140] = 8'h3f;  plane0[141] = 8'hfc;  plane0[142] = 8'h60;  plane0[143] = 8'hec;
    plane0[144] = 8'hff;  plane0[145] = 8'hfb;  plane0[146] = 8'h1d;  plane0[147] = 8'h1f;  plane0[148] = 8'hf0;  plane0[149] = 8'hf1;  plane0[150] = 8'h7c;  plane0[151] = 8'hff;
    plane0[152] = 8'hfb;  plane0[153] = 8'hfb;  plane0[154] = 8'hc4;  plane0[155] = 8'h0f;  plane0[156] = 8'h00;  plane0[157] = 8'hc3;  plane0[158] = 8'hfb;  plane0[159] = 8'hde;
    plane0[160] = 8'hff;  plane0[161] = 8'hff;  plane0[162] = 8'hf0;  plane0[163] = 8'h07;  plane0[164] = 8'h00;  plane0[165] = 8'h8e;  plane0[166] = 8'h03;  plane0[167] = 8'hfe;
    plane0[168] = 8'hff;  plane0[169] = 8'hff;  plane0[170] = 8'h0a;  plane0[171] = 8'h00;  plane0[172] = 8'h06;  plane0[173] = 8'h5e;  plane0[174] = 8'h00;  plane0[175] = 8'hfe;
    plane0[176] = 8'he3;  plane0[177] = 8'hff;  plane0[178] = 8'hbd;  plane0[179] = 8'h80;  plane0[180] = 8'h0f;  plane0[181] = 8'hfe;  plane0[182] = 8'h00;  plane0[183] = 8'hbc;
    plane0[184] = 8'h87;  plane0[185] = 8'hef;  plane0[186] = 8'h79;  plane0[187] = 8'he0;  plane0[188] = 8'h19;  plane0[189] = 8'hfe;  plane0[190] = 8'h02;  plane0[191] = 8'hf0;
    plane0[192] = 8'h06;  plane0[193] = 8'hef;  plane0[194] = 8'h7e;  plane0[195] = 8'h97;  plane0[196] = 8'h60;  plane0[197] = 8'hcc;  plane0[198] = 8'h06;  plane0[199] = 8'hf0;
    plane0[200] = 8'h07;  plane0[201] = 8'hb7;  plane0[202] = 8'hff;  plane0[203] = 8'hac;  plane0[204] = 8'h20;  plane0[205] = 8'hee;  plane0[206] = 8'h03;  plane0[207] = 8'h70;
    plane0[208] = 8'h01;  plane0[209] = 8'h67;  plane0[210] = 8'hef;  plane0[211] = 8'h5f;  plane0[212] = 8'hc0;  plane0[213] = 8'h6f;  plane0[214] = 8'h00;  plane0[215] = 8'h70;
    plane0[216] = 8'h01;  plane0[217] = 8'hb7;  plane0[218] = 8'h70;  plane0[219] = 8'hcc;  plane0[220] = 8'h91;  plane0[221] = 8'heb;  plane0[222] = 8'h00;  plane0[223] = 8'hf8;
    plane0[224] = 8'h07;  plane0[225] = 8'h57;  plane0[226] = 8'h0b;  plane0[227] = 8'h33;  plane0[228] = 8'hd3;  plane0[229] = 8'ha3;  plane0[230] = 8'h00;  plane0[231] = 8'hc0;
    plane0[232] = 8'h37;  plane0[233] = 8'hf7;  plane0[234] = 8'hba;  plane0[235] = 8'hab;  plane0[236] = 8'he3;  plane0[237] = 8'h2f;  plane0[238] = 8'h01;  plane0[239] = 8'h00;
    plane0[240] = 8'h34;  plane0[241] = 8'hb7;  plane0[242] = 8'hfa;  plane0[243] = 8'h2c;  plane0[244] = 8'h8b;  plane0[245] = 8'hf6;  plane0[246] = 8'h00;  plane0[247] = 8'h00;
    plane0[248] = 8'h00;  plane0[249] = 8'h96;  plane0[250] = 8'h3f;  plane0[251] = 8'h18;  plane0[252] = 8'hda;  plane0[253] = 8'hb0;  plane0[254] = 8'h22;  plane0[255] = 8'h08;
    plane0[256] = 8'h07;  plane0[257] = 8'hd4;  plane0[258] = 8'h3f;  plane0[259] = 8'hc0;  plane0[260] = 8'h38;  plane0[261] = 8'hf8;  plane0[262] = 8'h07;  plane0[263] = 8'h00;
    plane0[264] = 8'hff;  plane0[265] = 8'h57;  plane0[266] = 8'h3b;  plane0[267] = 8'h80;  plane0[268] = 8'h66;  plane0[269] = 8'hfc;  plane0[270] = 8'h03;  plane0[271] = 8'h00;
    plane0[272] = 8'hff;  plane0[273] = 8'hd7;  plane0[274] = 8'h23;  plane0[275] = 8'hb0;  plane0[276] = 8'h10;  plane0[277] = 8'he8;  plane0[278] = 8'h40;  plane0[279] = 8'hcc;
    plane0[280] = 8'hc0;  plane0[281] = 8'h9f;  plane0[282] = 8'hb3;  plane0[283] = 8'he0;  plane0[284] = 8'h7c;  plane0[285] = 8'h78;  plane0[286] = 8'h00;  plane0[287] = 8'h80;
    plane0[288] = 8'h00;  plane0[289] = 8'hfe;  plane0[290] = 8'h27;  plane0[291] = 8'hf0;  plane0[292] = 8'hc4;  plane0[293] = 8'h70;  plane0[294] = 8'hc0;  plane0[295] = 8'h01;
    plane0[296] = 8'h01;  plane0[297] = 8'he0;  plane0[298] = 8'h27;  plane0[299] = 8'hb8;  plane0[300] = 8'h60;  plane0[301] = 8'h38;  plane0[302] = 8'h40;  plane0[303] = 8'h9c;
    plane0[304] = 8'hfe;  plane0[305] = 8'hff;  plane0[306] = 8'h3f;  plane0[307] = 8'h90;  plane0[308] = 8'h04;  plane0[309] = 8'h37;  plane0[310] = 8'h40;  plane0[311] = 8'hdc;
    plane0[312] = 8'hfe;  plane0[313] = 8'hff;  plane0[314] = 8'h1b;  plane0[315] = 8'h84;  plane0[316] = 8'h1c;  plane0[317] = 8'hf8;  plane0[318] = 8'h83;  plane0[319] = 8'h4f;
    plane0[320] = 8'hff;  plane0[321] = 8'h3f;  plane0[322] = 8'h1b;  plane0[323] = 8'hbe;  plane0[324] = 8'h1c;  plane0[325] = 8'h98;  plane0[326] = 8'h3f;  plane0[327] = 8'h78;
    plane0[328] = 8'hff;  plane0[329] = 8'h3f;  plane0[330] = 8'h0b;  plane0[331] = 8'hdf;  plane0[332] = 8'h01;  plane0[333] = 8'hf8;  plane0[334] = 8'h80;  plane0[335] = 8'hc3;
    plane0[336] = 8'hfd;  plane0[337] = 8'h3f;  plane0[338] = 8'h0b;  plane0[339] = 8'h0f;  plane0[340] = 8'h22;  plane0[341] = 8'h98;  plane0[342] = 8'h07;  plane0[343] = 8'h78;
    plane0[344] = 8'hff;  plane0[345] = 8'hbf;  plane0[346] = 8'h0a;  plane0[347] = 8'h0e;  plane0[348] = 8'h43;  plane0[349] = 8'h14;  plane0[350] = 8'h38;  plane0[351] = 8'hc0;
    plane0[352] = 8'hfb;  plane0[353] = 8'h3f;  plane0[354] = 8'h1e;  plane0[355] = 8'h0f;  plane0[356] = 8'h68;  plane0[357] = 8'h18;  plane0[358] = 8'h80;  plane0[359] = 8'he1;
    plane0[360] = 8'hff;  plane0[361] = 8'hdf;  plane0[362] = 8'h1e;  plane0[363] = 8'h20;  plane0[364] = 8'h88;  plane0[365] = 8'h08;  plane0[366] = 8'h00;  plane0[367] = 8'hc8;
    plane0[368] = 8'hf7;  plane0[369] = 8'hff;  plane0[370] = 8'h1e;  plane0[371] = 8'hd5;  plane0[372] = 8'h00;  plane0[373] = 8'h00;  plane0[374] = 8'h00;  plane0[375] = 8'hf0;
    plane0[376] = 8'h8f;  plane0[377] = 8'hd1;  plane0[378] = 8'hbe;  plane0[379] = 8'h07;  plane0[380] = 8'h8a;  plane0[381] = 8'h00;  plane0[382] = 8'h00;  plane0[383] = 8'he8;
    plane0[384] = 8'h7f;  plane0[385] = 8'h3f;  plane0[386] = 8'hfe;  plane0[387] = 8'h0d;  plane0[388] = 8'h60;  plane0[389] = 8'h09;  plane0[390] = 8'h00;  plane0[391] = 8'hf8;
    plane0[392] = 8'haf;  plane0[393] = 8'hd5;  plane0[394] = 8'hfe;  plane0[395] = 8'h0f;  plane0[396] = 8'h32;  plane0[397] = 8'h3f;  plane0[398] = 8'h00;  plane0[399] = 8'hfc;
    plane0[400] = 8'hf1;  plane0[401] = 8'hc6;  plane0[402] = 8'hff;  plane0[403] = 8'h0f;  plane0[404] = 8'hc0;  plane0[405] = 8'h3e;  plane0[406] = 8'h04;  plane0[407] = 8'hfc;
    plane0[408] = 8'h7f;  plane0[409] = 8'hde;  plane0[410] = 8'hff;  plane0[411] = 8'h07;  plane0[412] = 8'h80;  plane0[413] = 8'h7f;  plane0[414] = 8'hf8;  plane0[415] = 8'hfe;
    plane0[416] = 8'h7f;  plane0[417] = 8'hfe;  plane0[418] = 8'hf3;  plane0[419] = 8'h80;  plane0[420] = 8'h60;  plane0[421] = 8'hff;  plane0[422] = 8'hf7;  plane0[423] = 8'hff;
    plane0[424] = 8'h7f;  plane0[425] = 8'hbe;  plane0[426] = 8'he3;  plane0[427] = 8'h01;  plane0[428] = 8'hb0;  plane0[429] = 8'hff;  plane0[430] = 8'hff;  plane0[431] = 8'hfe;
    plane0[432] = 8'hff;  plane0[433] = 8'hbc;  plane0[434] = 8'hc1;  plane0[435] = 8'h01;  plane0[436] = 8'hf0;  plane0[437] = 8'hff;  plane0[438] = 8'h5f;  plane0[439] = 8'hff;
    plane0[440] = 8'hff;  plane0[441] = 8'h71;  plane0[442] = 8'h80;  plane0[443] = 8'h01;  plane0[444] = 8'h14;  plane0[445] = 8'hff;  plane0[446] = 8'hbf;  plane0[447] = 8'hff;
    plane0[448] = 8'hff;  plane0[449] = 8'hfb;  plane0[450] = 8'h60;  plane0[451] = 8'h21;  plane0[452] = 8'h08;  plane0[453] = 8'hfa;  plane0[454] = 8'hdf;  plane0[455] = 8'hff;
    plane0[456] = 8'hff;  plane0[457] = 8'h7f;  plane0[458] = 8'h60;  plane0[459] = 8'h30;  plane0[460] = 8'h0c;  plane0[461] = 8'hf8;  plane0[462] = 8'hff;  plane0[463] = 8'hff;
    plane0[464] = 8'hfc;  plane0[465] = 8'hff;  plane0[466] = 8'h01;  plane0[467] = 8'hc0;  plane0[468] = 8'h0c;  plane0[469] = 8'he0;  plane0[470] = 8'hfb;  plane0[471] = 8'hff;
    plane0[472] = 8'hfd;  plane0[473] = 8'h7f;  plane0[474] = 8'h00;  plane0[475] = 8'h80;  plane0[476] = 8'h0f;  plane0[477] = 8'hc2;  plane0[478] = 8'hff;  plane0[479] = 8'hff;
    plane0[480] = 8'hfd;  plane0[481] = 8'hff;  plane0[482] = 8'h02;  plane0[483] = 8'h80;  plane0[484] = 8'h0f;  plane0[485] = 8'hc0;  plane0[486] = 8'hff;  plane0[487] = 8'hff;
    plane0[488] = 8'hff;  plane0[489] = 8'hff;  plane0[490] = 8'h03;  plane0[491] = 8'h80;  plane0[492] = 8'h05;  plane0[493] = 8'hb8;  plane0[494] = 8'hff;  plane0[495] = 8'hff;
    plane0[496] = 8'hff;  plane0[497] = 8'hff;  plane0[498] = 8'h5f;  plane0[499] = 8'hc0;  plane0[500] = 8'h0c;  plane0[501] = 8'h56;  plane0[502] = 8'hff;  plane0[503] = 8'hff;
    plane0[504] = 8'hff;  plane0[505] = 8'hff;  plane0[506] = 8'hff;  plane0[507] = 8'h61;  plane0[508] = 8'h6e;  plane0[509] = 8'h00;  plane0[510] = 8'hff;  plane0[511] = 8'hff;
    plane1[  0] = 8'hff;  plane1[  1] = 8'hff;  plane1[  2] = 8'hff;  plane1[  3] = 8'hff;  plane1[  4] = 8'h0f;  plane1[  5] = 8'hff;  plane1[  6] = 8'hff;  plane1[  7] = 8'hff;
    plane1[  8] = 8'hff;  plane1[  9] = 8'hff;  plane1[ 10] = 8'h3f;  plane1[ 11] = 8'he0;  plane1[ 12] = 8'hff;  plane1[ 13] = 8'hf8;  plane1[ 14] = 8'hff;  plane1[ 15] = 8'hff;
    plane1[ 16] = 8'hff;  plane1[ 17] = 8'hff;  plane1[ 18] = 8'h07;  plane1[ 19] = 8'hc0;  plane1[ 20] = 8'hff;  plane1[ 21] = 8'hd8;  plane1[ 22] = 8'hff;  plane1[ 23] = 8'hff;
    plane1[ 24] = 8'hff;  plane1[ 25] = 8'hff;  plane1[ 26] = 8'h01;  plane1[ 27] = 8'hc0;  plane1[ 28] = 8'hff;  plane1[ 29] = 8'h68;  plane1[ 30] = 8'hff;  plane1[ 31] = 8'hff;
    plane1[ 32] = 8'hff;  plane1[ 33] = 8'hff;  plane1[ 34] = 8'h00;  plane1[ 35] = 8'h20;  plane1[ 36] = 8'hf0;  plane1[ 37] = 8'h28;  plane1[ 38] = 8'hff;  plane1[ 39] = 8'hff;
    plane1[ 40] = 8'hff;  plane1[ 41] = 8'h3f;  plane1[ 42] = 8'h00;  plane1[ 43] = 8'hfe;  plane1[ 44] = 8'h80;  plane1[ 45] = 8'h28;  plane1[ 46] = 8'hfc;  plane1[ 47] = 8'hff;
    plane1[ 48] = 8'hff;  plane1[ 49] = 8'h0f;  plane1[ 50] = 8'hc0;  plane1[ 51] = 8'hf9;  plane1[ 52] = 8'h3f;  plane1[ 53] = 8'h29;  plane1[ 54] = 8'hf0;  plane1[ 55] = 8'hff;
    plane1[ 56] = 8'hff;  plane1[ 57] = 8'h07;  plane1[ 58] = 8'h00;  plane1[ 59] = 8'hbd;  plane1[ 60] = 8'hef;  plane1[ 61] = 8'h2c;  plane1[ 62] = 8'hde;  plane1[ 63] = 8'hff;
    plane1[ 64] = 8'hff;  plane1[ 65] = 8'h09;  plane1[ 66] = 8'h80;  plane1[ 67] = 8'h3d;  plane1[ 68] = 8'hef;  plane1[ 69] = 8'h21;  plane1[ 70] = 8'h80;  plane1[ 71] = 8'hff;
    plane1[ 72] = 8'hff;  plane1[ 73] = 8'h02;  plane1[ 74] = 8'h80;  plane1[ 75] = 8'hbd;  plane1[ 76] = 8'hfd;  plane1[ 77] = 8'h27;  plane1[ 78] = 8'h00;  plane1[ 79] = 8'hff;
    plane1[ 80] = 8'hff;  plane1[ 81] = 8'h13;  plane1[ 82] = 8'h80;  plane1[ 83] = 8'hff;  plane1[ 84] = 8'hef;  plane1[ 85] = 8'h3f;  plane1[ 86] = 8'h00;  plane1[ 87] = 8'hfe;
    plane1[ 88] = 8'h7f;  plane1[ 89] = 8'h13;  plane1[ 90] = 8'h80;  plane1[ 91] = 8'hb7;  plane1[ 92] = 8'he7;  plane1[ 93] = 8'h3b;  plane1[ 94] = 8'h00;  plane1[ 95] = 8'hff;
    plane1[ 96] = 8'hbf;  plane1[ 97] = 8'h11;  plane1[ 98] = 8'h80;  plane1[ 99] = 8'hc6;  plane1[100] = 8'h6f;  plane1[101] = 8'h6f;  plane1[102] = 8'h00;  plane1[103] = 8'hfe;
    plane1[104] = 8'h3f;  plane1[105] = 8'h10;  plane1[106] = 8'h00;  plane1[107] = 8'hfc;  plane1[108] = 8'hf8;  plane1[109] = 8'h76;  plane1[110] = 8'h00;  plane1[111] = 8'hf8;
    plane1[112] = 8'h1f;  plane1[113] = 8'h10;  plane1[114] = 8'h00;  plane1[115] = 8'h07;  plane1[116] = 8'h00;  plane1[117] = 8'h75;  plane1[118] = 8'h00;  plane1[119] = 8'hfc;
    plane1[120] = 8'h0f;  plane1[121] = 8'h12;  plane1[122] = 8'h00;  plane1[123] = 8'hf0;  plane1[124] = 8'h3f;  plane1[125] = 8'hf9;  plane1[126] = 8'h80;  plane1[127] = 8'hf0;
    plane1[128] = 8'h07;  plane1[129] = 8'h13;  plane1[130] = 8'h00;  plane1[131] = 8'hfe;  plane1[132] = 8'hfc;  plane1[133] = 8'h3d;  plane1[134] = 8'h40;  plane1[135] = 8'he8;
    plane1[136] = 8'h0f;  plane1[137] = 8'h13;  plane1[138] = 8'hc0;  plane1[139] = 8'h03;  plane1[140] = 8'hc0;  plane1[141] = 8'h3b;  plane1[142] = 8'h38;  plane1[143] = 8'he8;
    plane1[144] = 8'h0b;  plane1[145] = 8'h10;  plane1[146] = 8'he0;  plane1[147] = 8'h00;  plane1[148] = 8'h00;  plane1[149] = 8'h3e;  plane1[150] = 8'hf8;  plane1[151] = 8'hd8;
    plane1[152] = 8'h3b;  plane1[153] = 8'h10;  plane1[154] = 8'h38;  plane1[155] = 8'h00;  plane1[156] = 8'h00;  plane1[157] = 8'h9c;  plane1[158] = 8'h30;  plane1[159] = 8'hd8;
    plane1[160] = 8'h1f;  plane1[161] = 8'h14;  plane1[162] = 8'h0c;  plane1[163] = 8'h00;  plane1[164] = 8'h00;  plane1[165] = 8'hb0;  plane1[166] = 8'h00;  plane1[167] = 8'hf0;
    plane1[168] = 8'h61;  plane1[169] = 8'h15;  plane1[170] = 8'h04;  plane1[171] = 8'h00;  plane1[172] = 8'h06;  plane1[173] = 8'h20;  plane1[174] = 8'h00;  plane1[175] = 8'hb8;
    plane1[176] = 8'hc3;  plane1[177] = 8'h15;  plane1[178] = 8'hc6;  plane1[179] = 8'h80;  plane1[180] = 8'h0f;  plane1[181] = 8'h00;  plane1[182] = 8'h00;  plane1[183] = 8'hb0;
    plane1[184] = 8'h03;  plane1[185] = 8'h16;  plane1[186] = 8'h04;  plane1[187] = 8'he0;  plane1[188] = 8'h1f;  plane1[189] = 8'h00;  plane1[190] = 8'h02;  plane1[191] = 8'hf0;
    plane1[192] = 8'h00;  plane1[193] = 8'h14;  plane1[194] = 8'h7e;  plane1[195] = 8'h88;  plane1[196] = 8'h7f;  plane1[197] = 8'h00;  plane1[198] = 8'h02;  plane1[199] = 8'h70;
    plane1[200] = 8'h01;  plane1[201] = 8'h84;  plane1[202] = 8'hf7;  plane1[203] = 8'h90;  plane1[204] = 8'h3f;  plane1[205] = 8'h60;  plane1[206] = 8'h01;  plane1[207] = 8'h70;
    plane1[208] = 8'h00;  plane1[209] = 8'h64;  plane1[210] = 8'hff;  plane1[211] = 8'h1f;  plane1[212] = 8'h1f;  plane1[213] = 8'h00;  plane1[214] = 8'h00;  plane1[215] = 8'h70;
    plane1[216] = 8'h00;  plane1[217] = 8'h34;  plane1[218] = 8'h88;  plane1[219] = 8'h7c;  plane1[220] = 8'h1f;  plane1[221] = 8'h04;  plane1[222] = 8'h00;  plane1[223] = 8'hf0;
    plane1[224] = 8'h00;  plane1[225] = 8'h40;  plane1[226] = 8'h46;  plane1[227] = 8'h71;  plane1[228] = 8'hc0;  plane1[229] = 8'h63;  plane1[230] = 8'h00;  plane1[231] = 8'h80;
    plane1[232] = 8'h00;  plane1[233] = 8'ha0;  plane1[234] = 8'h44;  plane1[235] = 8'he9;  plane1[236] = 8'hec;  plane1[237] = 8'h1f;  plane1[238] = 8'h00;  plane1[239] = 8'h00;
    plane1[240] = 8'h00;  plane1[241] = 8'h40;  plane1[242] = 8'h04;  plane1[243] = 8'h6f;  plane1[244] = 8'h03;  plane1[245] = 8'hce;  plane1[246] = 8'h00;  plane1[247] = 8'h00;
    plane1[248] = 8'h00;  plane1[249] = 8'h60;  plane1[250] = 8'hc0;  plane1[251] = 8'h7f;  plane1[252] = 8'h13;  plane1[253] = 8'h88;  plane1[254] = 8'h00;  plane1[255] = 8'h00;
    plane1[256] = 8'h00;  plane1[257] = 8'h20;  plane1[258] = 8'hc0;  plane1[259] = 8'h7f;  plane1[260] = 8'h31;  plane1[261] = 8'hc8;  plane1[262] = 8'h01;  plane1[263] = 8'h00;
    plane1[264] = 8'h00;  plane1[265] = 8'ha4;  plane1[266] = 8'hc8;  plane1[267] = 8'h7f;  plane1[268] = 8'hf7;  plane1[269] = 8'h8b;  plane1[270] = 8'h00;  plane1[271] = 8'h00;
    plane1[272] = 8'h00;  plane1[273] = 8'h24;  plane1[274] = 8'hf0;  plane1[275] = 8'h3f;  plane1[276] = 8'he7;  plane1[277] = 8'h07;  plane1[278] = 8'h00;  plane1[279] = 8'h00;
    plane1[280] = 8'h00;  plane1[281] = 8'h60;  plane1[282] = 8'hc0;  plane1[283] = 8'h10;  plane1[284] = 8'h9b;  plane1[285] = 8'h07;  plane1[286] = 8'h00;  plane1[287] = 8'h00;
    plane1[288] = 8'hff;  plane1[289] = 8'h21;  plane1[290] = 8'hc0;  plane1[291] = 8'h0f;  plane1[292] = 8'h2b;  plane1[293] = 8'h07;  plane1[294] = 8'h00;  plane1[295] = 8'h00;
    plane1[296] = 8'h00;  plane1[297] = 8'h20;  plane1[298] = 8'hc0;  plane1[299] = 8'h07;  plane1[300] = 8'hfb;  plane1[301] = 8'h27;  plane1[302] = 8'h80;  plane1[303] = 8'h03;
    plane1[304] = 8'h01;  plane1[305] = 8'h20;  plane1[306] = 8'hc0;  plane1[307] = 8'h07;  plane1[308] = 8'hfb;  plane1[309] = 8'h0f;  plane1[310] = 8'h80;  plane1[311] = 8'he3;
    plane1[312] = 8'h01;  plane1[313] = 8'h20;  plane1[314] = 8'he4;  plane1[315] = 8'h03;  plane1[316] = 8'he3;  plane1[317] = 8'hc7;  plane1[318] = 8'h01;  plane1[319] = 8'h70;
    plane1[320] = 8'h01;  plane1[321] = 8'he0;  plane1[322] = 8'he4;  plane1[323] = 8'h01;  plane1[324] = 8'he3;  plane1[325] = 8'ha7;  plane1[326] = 8'h1f;  plane1[327] = 8'hc0;
    plane1[328] = 8'h01;  plane1[329] = 8'h00;  plane1[330] = 8'hf4;  plane1[331] = 8'h20;  plane1[332] = 8'hfe;  plane1[333] = 8'he7;  plane1[334] = 8'h80;  plane1[335] = 8'hc1;
    plane1[336] = 8'h03;  plane1[337] = 8'h00;  plane1[338] = 8'hf4;  plane1[339] = 8'hf0;  plane1[340] = 8'he3;  plane1[341] = 8'h87;  plane1[342] = 8'h07;  plane1[343] = 8'hd8;
    plane1[344] = 8'h03;  plane1[345] = 8'h80;  plane1[346] = 8'h34;  plane1[347] = 8'hf1;  plane1[348] = 8'hc3;  plane1[349] = 8'h0b;  plane1[350] = 8'h38;  plane1[351] = 8'hc0;
    plane1[352] = 8'h07;  plane1[353] = 8'h80;  plane1[354] = 8'h60;  plane1[355] = 8'hf2;  plane1[356] = 8'hef;  plane1[357] = 8'h17;  plane1[358] = 8'h80;  plane1[359] = 8'hc1;
    plane1[360] = 8'h07;  plane1[361] = 8'h40;  plane1[362] = 8'he0;  plane1[363] = 8'hc5;  plane1[364] = 8'h8f;  plane1[365] = 8'h07;  plane1[366] = 8'h00;  plane1[367] = 8'he8;
    plane1[368] = 8'h0f;  plane1[369] = 8'h4a;  plane1[370] = 8'he0;  plane1[371] = 8'h0e;  plane1[372] = 8'h17;  plane1[373] = 8'h0f;  plane1[374] = 8'h00;  plane1[375] = 8'he0;
    plane1[376] = 8'h7f;  plane1[377] = 8'h51;  plane1[378] = 8'h40;  plane1[379] = 8'hf8;  plane1[380] = 8'h83;  plane1[381] = 8'h07;  plane1[382] = 8'h00;  plane1[383] = 8'hf0;
    plane1[384] = 8'h6f;  plane1[385] = 8'h48;  plane1[386] = 8'h00;  plane1[387] = 8'hf0;  plane1[388] = 8'he1;  plane1[389] = 8'h02;  plane1[390] = 8'h00;  plane1[391] = 8'hf0;
    plane1[392] = 8'h1f;  plane1[393] = 8'h25;  plane1[394] = 8'h00;  plane1[395] = 8'hf0;  plane1[396] = 8'hbf;  plane1[397] = 8'h02;  plane1[398] = 8'h00;  plane1[399] = 8'hf8;
    plane1[400] = 8'hdf;  plane1[401] = 8'h34;  plane1[402] = 8'h00;  plane1[403] = 8'hf0;  plane1[404] = 8'h5f;  plane1[405] = 8'h01;  plane1[406] = 8'h00;  plane1[407] = 8'hf8;
    plane1[408] = 8'h3f;  plane1[409] = 8'h36;  plane1[410] = 8'h00;  plane1[411] = 8'hf8;  plane1[412] = 8'h7f;  plane1[413] = 8'h00;  plane1[414] = 8'h00;  plane1[415] = 8'hfc;
    plane1[416] = 8'h7f;  plane1[417] = 8'h36;  plane1[418] = 8'h0c;  plane1[419] = 8'hff;  plane1[420] = 8'h1f;  plane1[421] = 8'h00;  plane1[422] = 8'h00;  plane1[423] = 8'hfe;
    plane1[424] = 8'hff;  plane1[425] = 8'h76;  plane1[426] = 8'h1c;  plane1[427] = 8'h7e;  plane1[428] = 8'h4f;  plane1[429] = 8'h00;  plane1[430] = 8'h00;  plane1[431] = 8'hff;
    plane1[432] = 8'hff;  plane1[433] = 8'h35;  plane1[434] = 8'h3e;  plane1[435] = 8'hfe;  plane1[436] = 8'h4f;  plane1[437] = 8'h00;  plane1[438] = 8'h80;  plane1[439] = 8'hff;
    plane1[440] = 8'hff;  plane1[441] = 8'hb3;  plane1[442] = 8'h7f;  plane1[443] = 8'h7e;  plane1[444] = 8'h0c;  plane1[445] = 8'h01;  plane1[446] = 8'hc0;  plane1[447] = 8'hff;
    plane1[448] = 8'hff;  plane1[449] = 8'hf7;  plane1[450] = 8'hff;  plane1[451] = 8'h3e;  plane1[452] = 8'h08;  plane1[453] = 8'h00;  plane1[454] = 8'he0;  plane1[455] = 8'hff;
    plane1[456] = 8'hff;  plane1[457] = 8'h7f;  plane1[458] = 8'hff;  plane1[459] = 8'h3f;  plane1[460] = 8'h04;  plane1[461] = 8'h08;  plane1[462] = 8'hf0;  plane1[463] = 8'hff;
    plane1[464] = 8'hff;  plane1[465] = 8'h7f;  plane1[466] = 8'hff;  plane1[467] = 8'hff;  plane1[468] = 8'h03;  plane1[469] = 8'h20;  plane1[470] = 8'hfc;  plane1[471] = 8'hff;
    plane1[472] = 8'hff;  plane1[473] = 8'hff;  plane1[474] = 8'hfe;  plane1[475] = 8'h7f;  plane1[476] = 8'h00;  plane1[477] = 8'h00;  plane1[478] = 8'hfe;  plane1[479] = 8'hff;
    plane1[480] = 8'hff;  plane1[481] = 8'hff;  plane1[482] = 8'hfd;  plane1[483] = 8'h7f;  plane1[484] = 8'h08;  plane1[485] = 8'h00;  plane1[486] = 8'hff;  plane1[487] = 8'hff;
    plane1[488] = 8'hff;  plane1[489] = 8'hff;  plane1[490] = 8'hf7;  plane1[491] = 8'h7f;  plane1[492] = 8'h04;  plane1[493] = 8'hd0;  plane1[494] = 8'hff;  plane1[495] = 8'hff;
    plane1[496] = 8'hff;  plane1[497] = 8'hff;  plane1[498] = 8'hdf;  plane1[499] = 8'h3f;  plane1[500] = 8'h08;  plane1[501] = 8'hfc;  plane1[502] = 8'hff;  plane1[503] = 8'hff;
    plane1[504] = 8'hff;  plane1[505] = 8'hff;  plane1[506] = 8'hff;  plane1[507] = 8'h18;  plane1[508] = 8'h4e;  plane1[509] = 8'hff;  plane1[510] = 8'hff;  plane1[511] = 8'hff;
    plane2[  0] = 8'hff;  plane2[  1] = 8'hff;  plane2[  2] = 8'hff;  plane2[  3] = 8'h1f;  plane2[  4] = 8'hf0;  plane2[  5] = 8'hff;  plane2[  6] = 8'hff;  plane2[  7] = 8'hff;
    plane2[  8] = 8'hff;  plane2[  9] = 8'hff;  plane2[ 10] = 8'hff;  plane2[ 11] = 8'h1f;  plane2[ 12] = 8'h00;  plane2[ 13] = 8'hff;  plane2[ 14] = 8'hff;  plane2[ 15] = 8'hff;
    plane2[ 16] = 8'hff;  plane2[ 17] = 8'hff;  plane2[ 18] = 8'hff;  plane2[ 19] = 8'h3f;  plane2[ 20] = 8'h00;  plane2[ 21] = 8'he7;  plane2[ 22] = 8'hff;  plane2[ 23] = 8'hff;
    plane2[ 24] = 8'hff;  plane2[ 25] = 8'hff;  plane2[ 26] = 8'hff;  plane2[ 27] = 8'h3f;  plane2[ 28] = 8'h00;  plane2[ 29] = 8'h87;  plane2[ 30] = 8'hff;  plane2[ 31] = 8'hff;
    plane2[ 32] = 8'hff;  plane2[ 33] = 8'hff;  plane2[ 34] = 8'hff;  plane2[ 35] = 8'h1f;  plane2[ 36] = 8'h00;  plane2[ 37] = 8'h07;  plane2[ 38] = 8'hfe;  plane2[ 39] = 8'hff;
    plane2[ 40] = 8'hff;  plane2[ 41] = 8'hff;  plane2[ 42] = 8'hff;  plane2[ 43] = 8'h01;  plane2[ 44] = 8'h00;  plane2[ 45] = 8'h07;  plane2[ 46] = 8'hf8;  plane2[ 47] = 8'hff;
    plane2[ 48] = 8'hff;  plane2[ 49] = 8'hff;  plane2[ 50] = 8'h3f;  plane2[ 51] = 8'h06;  plane2[ 52] = 8'h00;  plane2[ 53] = 8'h06;  plane2[ 54] = 8'hf0;  plane2[ 55] = 8'hff;
    plane2[ 56] = 8'hff;  plane2[ 57] = 8'hff;  plane2[ 58] = 8'hff;  plane2[ 59] = 8'h43;  plane2[ 60] = 8'h10;  plane2[ 61] = 8'h00;  plane2[ 62] = 8'he0;  plane2[ 63] = 8'hff;
    plane2[ 64] = 8'hff;  plane2[ 65] = 8'hf7;  plane2[ 66] = 8'hff;  plane2[ 67] = 8'hc3;  plane2[ 68] = 8'h10;  plane2[ 69] = 8'h00;  plane2[ 70] = 8'hc0;  plane2[ 71] = 8'hff;
    plane2[ 72] = 8'hff;  plane2[ 73] = 8'hfd;  plane2[ 74] = 8'hff;  plane2[ 75] = 8'h43;  plane2[ 76] = 8'h02;  plane2[ 77] = 8'h00;  plane2[ 78] = 8'h80;  plane2[ 79] = 8'hff;
    plane2[ 80] = 8'hff;  plane2[ 81] = 8'hec;  plane2[ 82] = 8'hff;  plane2[ 83] = 8'h01;  plane2[ 84] = 8'h10;  plane2[ 85] = 8'h00;  plane2[ 86] = 8'h00;  plane2[ 87] = 8'hff;
    plane2[ 88] = 8'hff;  plane2[ 89] = 8'hec;  plane2[ 90] = 8'hff;  plane2[ 91] = 8'h49;  plane2[ 92] = 8'h18;  plane2[ 93] = 8'h04;  plane2[ 94] = 8'h00;  plane2[ 95] = 8'hfe;
    plane2[ 96] = 8'h7f;  plane2[ 97] = 8'hec;  plane2[ 98] = 8'hff;  plane2[ 99] = 8'hf9;  plane2[100] = 8'h9f;  plane2[101] = 8'h10;  plane2[102] = 8'h00;  plane2[103] = 8'hfc;
    plane2[104] = 8'h1f;  plane2[105] = 8'hec;  plane2[106] = 8'hff;  plane2[107] = 8'hff;  plane2[108] = 8'hff;  plane2[109] = 8'h01;  plane2[110] = 8'h00;  plane2[111] = 8'hfc;
    plane2[112] = 8'h1f;  plane2[113] = 8'hec;  plane2[114] = 8'hff;  plane2[115] = 8'hff;  plane2[116] = 8'hff;  plane2[117] = 8'h03;  plane2[118] = 8'h00;  plane2[119] = 8'hf8;
    plane2[120] = 8'h0f;  plane2[121] = 8'hec;  plane2[122] = 8'hff;  plane2[123] = 8'hff;  plane2[124] = 8'hff;  plane2[125] = 8'h06;  plane2[126] = 8'h00;  plane2[127] = 8'hf8;
    plane2[128] = 8'h0f;  plane2[129] = 8'hec;  plane2[130] = 8'hff;  plane2[131] = 8'hff;  plane2[132] = 8'hff;  plane2[133] = 8'h03;  plane2[134] = 8'h00;  plane2[135] = 8'hf0;
    plane2[136] = 8'h07;  plane2[137] = 8'hec;  plane2[138] = 8'hff;  plane2[139] = 8'hff;  plane2[140] = 8'hff;  plane2[141] = 8'h07;  plane2[142] = 8'h00;  plane2[143] = 8'hf0;
    plane2[144] = 8'h07;  plane2[145] = 8'hec;  plane2[146] = 8'hff;  plane2[147] = 8'hff;  plane2[148] = 8'hff;  plane2[149] = 8'h0f;  plane2[150] = 8'h00;  plane2[151] = 8'he0;
    plane2[152] = 8'h07;  plane2[153] = 8'hec;  plane2[154] = 8'hff;  plane2[155] = 8'hff;  plane2[156] = 8'hff;  plane2[157] = 8'h3f;  plane2[158] = 8'h00;  plane2[159] = 8'he0;
    plane2[160] = 8'h03;  plane2[161] = 8'he8;  plane2[162] = 8'hff;  plane2[163] = 8'hff;  plane2[164] = 8'hff;  plane2[165] = 8'h7f;  plane2[166] = 8'h00;  plane2[167] = 8'hc0;
    plane2[168] = 8'h03;  plane2[169] = 8'he8;  plane2[170] = 8'hff;  plane2[171] = 8'hff;  plane2[172] = 8'hf9;  plane2[173] = 8'hff;  plane2[174] = 8'h00;  plane2[175] = 8'hc0;
    plane2[176] = 8'h01;  plane2[177] = 8'he8;  plane2[178] = 8'h03;  plane2[179] = 8'h7f;  plane2[180] = 8'hf0;  plane2[181] = 8'hff;  plane2[182] = 8'h01;  plane2[183] = 8'hc0;
    plane2[184] = 8'h01;  plane2[185] = 8'hf8;  plane2[186] = 8'h83;  plane2[187] = 8'h1f;  plane2[188] = 8'he0;  plane2[189] = 8'hff;  plane2[190] = 8'h01;  plane2[191] = 8'h80;
    plane2[192] = 8'h01;  plane2[193] = 8'hf8;  plane2[194] = 8'h81;  plane2[195] = 8'h7f;  plane2[196] = 8'h80;  plane2[197] = 8'hff;  plane2[198] = 8'h01;  plane2[199] = 8'h80;
    plane2[200] = 8'h00;  plane2[201] = 8'h78;  plane2[202] = 8'h08;  plane2[203] = 8'h7f;  plane2[204] = 8'hc0;  plane2[205] = 8'h9f;  plane2[206] = 8'h00;  plane2[207] = 8'h80;
    plane2[208] = 8'h00;  plane2[209] = 8'h98;  plane2[210] = 8'h00;  plane2[211] = 8'he0;  plane2[212] = 8'he0;  plane2[213] = 8'h9f;  plane2[214] = 8'h00;  plane2[215] = 8'h80;
    plane2[216] = 8'h00;  plane2[217] = 8'hc8;  plane2[218] = 8'h07;  plane2[219] = 8'h83;  plane2[220] = 8'he0;  plane2[221] = 8'h1f;  plane2[222] = 8'h00;  plane2[223] = 8'h00;
    plane2[224] = 8'h00;  plane2[225] = 8'hb8;  plane2[226] = 8'h81;  plane2[227] = 8'h8e;  plane2[228] = 8'h3f;  plane2[229] = 8'h1c;  plane2[230] = 8'h00;  plane2[231] = 8'h00;
    plane2[232] = 8'h00;  plane2[233] = 8'h18;  plane2[234] = 8'h01;  plane2[235] = 8'h16;  plane2[236] = 8'h1f;  plane2[237] = 8'hc0;  plane2[238] = 8'h00;  plane2[239] = 8'h00;
    plane2[240] = 8'h00;  plane2[241] = 8'h18;  plane2[242] = 8'h01;  plane2[243] = 8'h90;  plane2[244] = 8'hfc;  plane2[245] = 8'h01;  plane2[246] = 8'h01;  plane2[247] = 8'h00;
    plane2[248] = 8'h00;  plane2[249] = 8'h18;  plane2[250] = 8'h00;  plane2[251] = 8'h80;  plane2[252] = 8'hec;  plane2[253] = 8'h47;  plane2[254] = 8'h01;  plane2[255] = 8'h00;
    plane2[256] = 8'h00;  plane2[257] = 8'h18;  plane2[258] = 8'h00;  plane2[259] = 8'h00;  plane2[260] = 8'hce;  plane2[261] = 8'h07;  plane2[262] = 8'h00;  plane2[263] = 8'h00;
    plane2[264] = 8'h00;  plane2[265] = 8'h18;  plane2[266] = 8'h00;  plane2[267] = 8'h00;  plane2[268] = 8'h08;  plane2[269] = 8'h00;  plane2[270] = 8'h00;  plane2[271] = 8'h00;
    plane2[272] = 8'h00;  plane2[273] = 8'h18;  plane2[274] = 8'h00;  plane2[275] = 8'h00;  plane2[276] = 8'h08;  plane2[277] = 8'h00;  plane2[278] = 8'h00;  plane2[279] = 8'h00;
    plane2[280] = 8'hff;  plane2[281] = 8'h1f;  plane2[282] = 8'h00;  plane2[283] = 8'h0f;  plane2[284] = 8'h00;  plane2[285] = 8'h00;  plane2[286] = 8'h00;  plane2[287] = 8'h00;
    plane2[288] = 8'hff;  plane2[289] = 8'h1f;  plane2[290] = 8'h00;  plane2[291] = 8'h00;  plane2[292] = 8'h10;  plane2[293] = 8'h00;  plane2[294] = 8'h00;  plane2[295] = 8'h00;
    plane2[296] = 8'hff;  plane2[297] = 8'h1f;  plane2[298] = 8'h00;  plane2[299] = 8'h00;  plane2[300] = 8'h00;  plane2[301] = 8'h00;  plane2[302] = 8'h00;  plane2[303] = 8'h00;
    plane2[304] = 8'hff;  plane2[305] = 8'h1f;  plane2[306] = 8'h00;  plane2[307] = 8'h00;  plane2[308] = 8'h00;  plane2[309] = 8'h00;  plane2[310] = 8'h00;  plane2[311] = 8'h00;
    plane2[312] = 8'hff;  plane2[313] = 8'h1f;  plane2[314] = 8'h00;  plane2[315] = 8'h00;  plane2[316] = 8'h00;  plane2[317] = 8'h00;  plane2[318] = 8'h00;  plane2[319] = 8'h80;
    plane2[320] = 8'hff;  plane2[321] = 8'h1f;  plane2[322] = 8'h00;  plane2[323] = 8'h00;  plane2[324] = 8'h00;  plane2[325] = 8'h40;  plane2[326] = 8'h00;  plane2[327] = 8'h80;
    plane2[328] = 8'hff;  plane2[329] = 8'hff;  plane2[330] = 8'h00;  plane2[331] = 8'h00;  plane2[332] = 8'h00;  plane2[333] = 8'h00;  plane2[334] = 8'h7f;  plane2[335] = 8'h80;
    plane2[336] = 8'hff;  plane2[337] = 8'hff;  plane2[338] = 8'h00;  plane2[339] = 8'h00;  plane2[340] = 8'h1c;  plane2[341] = 8'h60;  plane2[342] = 8'hf8;  plane2[343] = 8'h87;
    plane2[344] = 8'hff;  plane2[345] = 8'h7f;  plane2[346] = 8'hc0;  plane2[347] = 8'h00;  plane2[348] = 8'h3c;  plane2[349] = 8'he0;  plane2[350] = 8'hc7;  plane2[351] = 8'hff;
    plane2[352] = 8'hff;  plane2[353] = 8'h7f;  plane2[354] = 8'h80;  plane2[355] = 8'h01;  plane2[356] = 8'h10;  plane2[357] = 8'he0;  plane2[358] = 8'h7f;  plane2[359] = 8'hfe;
    plane2[360] = 8'hff;  plane2[361] = 8'h3f;  plane2[362] = 8'h00;  plane2[363] = 8'h02;  plane2[364] = 8'h70;  plane2[365] = 8'hf0;  plane2[366] = 8'hff;  plane2[367] = 8'hf7;
    plane2[368] = 8'hff;  plane2[369] = 8'h01;  plane2[370] = 8'h00;  plane2[371] = 8'h00;  plane2[372] = 8'hf8;  plane2[373] = 8'hf0;  plane2[374] = 8'hff;  plane2[375] = 8'hff;
    plane2[376] = 8'hff;  plane2[377] = 8'h20;  plane2[378] = 8'h00;  plane2[379] = 8'h00;  plane2[380] = 8'h7c;  plane2[381] = 8'hf8;  plane2[382] = 8'hff;  plane2[383] = 8'hff;
    plane2[384] = 8'h1f;  plane2[385] = 8'h30;  plane2[386] = 8'h00;  plane2[387] = 8'h00;  plane2[388] = 8'h1e;  plane2[389] = 8'hfc;  plane2[390] = 8'hff;  plane2[391] = 8'hff;
    plane2[392] = 8'h1f;  plane2[393] = 8'h38;  plane2[394] = 8'h00;  plane2[395] = 8'h00;  plane2[396] = 8'h40;  plane2[397] = 8'hfc;  plane2[398] = 8'hff;  plane2[399] = 8'hff;
    plane2[400] = 8'h3f;  plane2[401] = 8'h39;  plane2[402] = 8'h00;  plane2[403] = 8'h00;  plane2[404] = 8'h20;  plane2[405] = 8'hfe;  plane2[406] = 8'hff;  plane2[407] = 8'hff;
    plane2[408] = 8'hff;  plane2[409] = 8'h39;  plane2[410] = 8'h00;  plane2[411] = 8'h00;  plane2[412] = 8'h00;  plane2[413] = 8'hff;  plane2[414] = 8'hff;  plane2[415] = 8'hff;
    plane2[416] = 8'hff;  plane2[417] = 8'h39;  plane2[418] = 8'h00;  plane2[419] = 8'h00;  plane2[420] = 8'h80;  plane2[421] = 8'hff;  plane2[422] = 8'hff;  plane2[423] = 8'hff;
    plane2[424] = 8'hff;  plane2[425] = 8'h39;  plane2[426] = 8'h00;  plane2[427] = 8'h80;  plane2[428] = 8'h80;  plane2[429] = 8'hff;  plane2[430] = 8'hff;  plane2[431] = 8'hff;
    plane2[432] = 8'hff;  plane2[433] = 8'h7b;  plane2[434] = 8'h00;  plane2[435] = 8'h00;  plane2[436] = 8'h80;  plane2[437] = 8'hff;  plane2[438] = 8'hff;  plane2[439] = 8'hff;
    plane2[440] = 8'hff;  plane2[441] = 8'h7f;  plane2[442] = 8'h00;  plane2[443] = 8'h80;  plane2[444] = 8'h03;  plane2[445] = 8'hfe;  plane2[446] = 8'hff;  plane2[447] = 8'hff;
    plane2[448] = 8'hff;  plane2[449] = 8'h7f;  plane2[450] = 8'h00;  plane2[451] = 8'hc0;  plane2[452] = 8'h07;  plane2[453] = 8'hfc;  plane2[454] = 8'hff;  plane2[455] = 8'hff;
    plane2[456] = 8'hff;  plane2[457] = 8'hff;  plane2[458] = 8'h00;  plane2[459] = 8'hc0;  plane2[460] = 8'h03;  plane2[461] = 8'hf0;  plane2[462] = 8'hff;  plane2[463] = 8'hff;
    plane2[464] = 8'hff;  plane2[465] = 8'hff;  plane2[466] = 8'h00;  plane2[467] = 8'h00;  plane2[468] = 8'h00;  plane2[469] = 8'hc0;  plane2[470] = 8'hff;  plane2[471] = 8'hff;
    plane2[472] = 8'hff;  plane2[473] = 8'hff;  plane2[474] = 8'h01;  plane2[475] = 8'h00;  plane2[476] = 8'h00;  plane2[477] = 8'h80;  plane2[478] = 8'hff;  plane2[479] = 8'hff;
    plane2[480] = 8'hff;  plane2[481] = 8'hff;  plane2[482] = 8'h03;  plane2[483] = 8'h00;  plane2[484] = 8'h00;  plane2[485] = 8'h80;  plane2[486] = 8'hff;  plane2[487] = 8'hff;
    plane2[488] = 8'hff;  plane2[489] = 8'hff;  plane2[490] = 8'h0f;  plane2[491] = 8'h00;  plane2[492] = 8'h08;  plane2[493] = 8'he0;  plane2[494] = 8'hff;  plane2[495] = 8'hff;
    plane2[496] = 8'hff;  plane2[497] = 8'hff;  plane2[498] = 8'h3f;  plane2[499] = 8'h00;  plane2[500] = 8'h04;  plane2[501] = 8'hf8;  plane2[502] = 8'hff;  plane2[503] = 8'hff;
    plane2[504] = 8'hff;  plane2[505] = 8'hff;  plane2[506] = 8'hff;  plane2[507] = 8'h07;  plane2[508] = 8'h80;  plane2[509] = 8'hff;  plane2[510] = 8'hff;  plane2[511] = 8'hff;
  end

  // 3bpp lookup: byte = {y, x[5:3]},  bit = x[2:0]
  wire [8:0] ba  = {y, x[5:3]};
  wire [2:0] idx = {plane2[ba][x[2:0]], plane1[ba][x[2:0]], plane0[ba][x[2:0]]};
  assign color = palette[idx];

endmodule

// --------------------------------------------------------

module sincos_rom (
    input wire  [7:0] angle,
    output wire signed [7:0] cos_out,
    output wire signed [7:0] sin_out
);
  // 256 entries packed as {sin[7:0], cos[7:0]}, scale = 127 (127 = 1.0)
  reg [7:0] mem[255:0];
  initial begin
    mem[  0] = 8'h7f;  mem[  1] = 8'h7f;  mem[  2] = 8'h7f;  mem[  3] = 8'h7f;
    mem[  4] = 8'h7e;  mem[  5] = 8'h7e;  mem[  6] = 8'h7e;  mem[  7] = 8'h7d;
    mem[  8] = 8'h7d;  mem[  9] = 8'h7c;  mem[ 10] = 8'h7b;  mem[ 11] = 8'h7a;
    mem[ 12] = 8'h7a;  mem[ 13] = 8'h79;  mem[ 14] = 8'h78;  mem[ 15] = 8'h76;
    mem[ 16] = 8'h75;  mem[ 17] = 8'h74;  mem[ 18] = 8'h73;  mem[ 19] = 8'h71;
    mem[ 20] = 8'h70;  mem[ 21] = 8'h6f;  mem[ 22] = 8'h6d;  mem[ 23] = 8'h6b;
    mem[ 24] = 8'h6a;  mem[ 25] = 8'h68;  mem[ 26] = 8'h66;  mem[ 27] = 8'h64;
    mem[ 28] = 8'h62;  mem[ 29] = 8'h60;  mem[ 30] = 8'h5e;  mem[ 31] = 8'h5c;
    mem[ 32] = 8'h5a;  mem[ 33] = 8'h58;  mem[ 34] = 8'h55;  mem[ 35] = 8'h53;
    mem[ 36] = 8'h51;  mem[ 37] = 8'h4e;  mem[ 38] = 8'h4c;  mem[ 39] = 8'h49;
    mem[ 40] = 8'h47;  mem[ 41] = 8'h44;  mem[ 42] = 8'h41;  mem[ 43] = 8'h3f;
    mem[ 44] = 8'h3c;  mem[ 45] = 8'h39;  mem[ 46] = 8'h36;  mem[ 47] = 8'h33;
    mem[ 48] = 8'h31;  mem[ 49] = 8'h2e;  mem[ 50] = 8'h2b;  mem[ 51] = 8'h28;
    mem[ 52] = 8'h25;  mem[ 53] = 8'h22;  mem[ 54] = 8'h1f;  mem[ 55] = 8'h1c;
    mem[ 56] = 8'h19;  mem[ 57] = 8'h16;  mem[ 58] = 8'h13;  mem[ 59] = 8'h10;
    mem[ 60] = 8'h0c;  mem[ 61] = 8'h09;  mem[ 62] = 8'h06;  mem[ 63] = 8'h03;
    mem[ 64] = 8'h00;  mem[ 65] = 8'hfd;  mem[ 66] = 8'hfa;  mem[ 67] = 8'hf7;
    mem[ 68] = 8'hf4;  mem[ 69] = 8'hf0;  mem[ 70] = 8'hed;  mem[ 71] = 8'hea;
    mem[ 72] = 8'he7;  mem[ 73] = 8'he4;  mem[ 74] = 8'he1;  mem[ 75] = 8'hde;
    mem[ 76] = 8'hdb;  mem[ 77] = 8'hd8;  mem[ 78] = 8'hd5;  mem[ 79] = 8'hd2;
    mem[ 80] = 8'hcf;  mem[ 81] = 8'hcd;  mem[ 82] = 8'hca;  mem[ 83] = 8'hc7;
    mem[ 84] = 8'hc4;  mem[ 85] = 8'hc1;  mem[ 86] = 8'hbf;  mem[ 87] = 8'hbc;
    mem[ 88] = 8'hb9;  mem[ 89] = 8'hb7;  mem[ 90] = 8'hb4;  mem[ 91] = 8'hb2;
    mem[ 92] = 8'haf;  mem[ 93] = 8'had;  mem[ 94] = 8'hab;  mem[ 95] = 8'ha8;
    mem[ 96] = 8'ha6;  mem[ 97] = 8'ha4;  mem[ 98] = 8'ha2;  mem[ 99] = 8'ha0;
    mem[100] = 8'h9e;  mem[101] = 8'h9c;  mem[102] = 8'h9a;  mem[103] = 8'h98;
    mem[104] = 8'h96;  mem[105] = 8'h95;  mem[106] = 8'h93;  mem[107] = 8'h91;
    mem[108] = 8'h90;  mem[109] = 8'h8f;  mem[110] = 8'h8d;  mem[111] = 8'h8c;
    mem[112] = 8'h8b;  mem[113] = 8'h8a;  mem[114] = 8'h88;  mem[115] = 8'h87;
    mem[116] = 8'h86;  mem[117] = 8'h86;  mem[118] = 8'h85;  mem[119] = 8'h84;
    mem[120] = 8'h83;  mem[121] = 8'h83;  mem[122] = 8'h82;  mem[123] = 8'h82;
    mem[124] = 8'h82;  mem[125] = 8'h81;  mem[126] = 8'h81;  mem[127] = 8'h81;
    mem[128] = 8'h81;  mem[129] = 8'h81;  mem[130] = 8'h81;  mem[131] = 8'h81;
    mem[132] = 8'h82;  mem[133] = 8'h82;  mem[134] = 8'h82;  mem[135] = 8'h83;
    mem[136] = 8'h83;  mem[137] = 8'h84;  mem[138] = 8'h85;  mem[139] = 8'h86;
    mem[140] = 8'h86;  mem[141] = 8'h87;  mem[142] = 8'h88;  mem[143] = 8'h8a;
    mem[144] = 8'h8b;  mem[145] = 8'h8c;  mem[146] = 8'h8d;  mem[147] = 8'h8f;
    mem[148] = 8'h90;  mem[149] = 8'h91;  mem[150] = 8'h93;  mem[151] = 8'h95;
    mem[152] = 8'h96;  mem[153] = 8'h98;  mem[154] = 8'h9a;  mem[155] = 8'h9c;
    mem[156] = 8'h9e;  mem[157] = 8'ha0;  mem[158] = 8'ha2;  mem[159] = 8'ha4;
    mem[160] = 8'ha6;  mem[161] = 8'ha8;  mem[162] = 8'hab;  mem[163] = 8'had;
    mem[164] = 8'haf;  mem[165] = 8'hb2;  mem[166] = 8'hb4;  mem[167] = 8'hb7;
    mem[168] = 8'hb9;  mem[169] = 8'hbc;  mem[170] = 8'hbf;  mem[171] = 8'hc1;
    mem[172] = 8'hc4;  mem[173] = 8'hc7;  mem[174] = 8'hca;  mem[175] = 8'hcd;
    mem[176] = 8'hcf;  mem[177] = 8'hd2;  mem[178] = 8'hd5;  mem[179] = 8'hd8;
    mem[180] = 8'hdb;  mem[181] = 8'hde;  mem[182] = 8'he1;  mem[183] = 8'he4;
    mem[184] = 8'he7;  mem[185] = 8'hea;  mem[186] = 8'hed;  mem[187] = 8'hf0;
    mem[188] = 8'hf4;  mem[189] = 8'hf7;  mem[190] = 8'hfa;  mem[191] = 8'hfd;
    mem[192] = 8'h00;  mem[193] = 8'h03;  mem[194] = 8'h06;  mem[195] = 8'h09;
    mem[196] = 8'h0c;  mem[197] = 8'h10;  mem[198] = 8'h13;  mem[199] = 8'h16;
    mem[200] = 8'h19;  mem[201] = 8'h1c;  mem[202] = 8'h1f;  mem[203] = 8'h22;
    mem[204] = 8'h25;  mem[205] = 8'h28;  mem[206] = 8'h2b;  mem[207] = 8'h2e;
    mem[208] = 8'h31;  mem[209] = 8'h33;  mem[210] = 8'h36;  mem[211] = 8'h39;
    mem[212] = 8'h3c;  mem[213] = 8'h3f;  mem[214] = 8'h41;  mem[215] = 8'h44;
    mem[216] = 8'h47;  mem[217] = 8'h49;  mem[218] = 8'h4c;  mem[219] = 8'h4e;
    mem[220] = 8'h51;  mem[221] = 8'h53;  mem[222] = 8'h55;  mem[223] = 8'h58;
    mem[224] = 8'h5a;  mem[225] = 8'h5c;  mem[226] = 8'h5e;  mem[227] = 8'h60;
    mem[228] = 8'h62;  mem[229] = 8'h64;  mem[230] = 8'h66;  mem[231] = 8'h68;
    mem[232] = 8'h6a;  mem[233] = 8'h6b;  mem[234] = 8'h6d;  mem[235] = 8'h6f;
    mem[236] = 8'h70;  mem[237] = 8'h71;  mem[238] = 8'h73;  mem[239] = 8'h74;
    mem[240] = 8'h75;  mem[241] = 8'h76;  mem[242] = 8'h78;  mem[243] = 8'h79;
    mem[244] = 8'h7a;  mem[245] = 8'h7a;  mem[246] = 8'h7b;  mem[247] = 8'h7c;
    mem[248] = 8'h7d;  mem[249] = 8'h7d;  mem[250] = 8'h7e;  mem[251] = 8'h7e;
    mem[252] = 8'h7e;  mem[253] = 8'h7f;  mem[254] = 8'h7f;  mem[255] = 8'h7f;
  end

  assign cos_out = mem[angle][7:0];
  assign sin_out = mem[angle+64][7:0];

endmodule
