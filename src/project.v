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

  reg [5:0] palette[15:0];
  reg [7:0] indices[2047:0];
  initial begin
    palette[ 0] = 6'h3f;
    palette[ 1] = 6'h3e;
    palette[ 2] = 6'h3a;
    palette[ 3] = 6'h2a;
    palette[ 4] = 6'h29;
    palette[ 5] = 6'h25;
    palette[ 6] = 6'h25;
    palette[ 7] = 6'h15;
    palette[ 8] = 6'h15;
    palette[ 9] = 6'h15;
    palette[10] = 6'h01;
    palette[11] = 6'h00;
    palette[12] = 6'h00;
    palette[13] = 6'h00;
    palette[14] = 6'h00;
    palette[15] = 6'h00;
    indices[   0] = 8'hfd;  indices[   1] = 8'hff;  indices[   2] = 8'hdd;  indices[   3] = 8'hdd;  indices[   4] = 8'hfd;  indices[   5] = 8'hdf;  indices[   6] = 8'hff;  indices[   7] = 8'hff;
    indices[   8] = 8'hff;  indices[   9] = 8'hff;  indices[  10] = 8'hff;  indices[  11] = 8'hff;  indices[  12] = 8'hcc;  indices[  13] = 8'hcc;  indices[  14] = 8'h7c;  indices[  15] = 8'h66;
    indices[  16] = 8'h66;  indices[  17] = 8'h77;  indices[  18] = 8'h99;  indices[  19] = 8'hb9;  indices[  20] = 8'hff;  indices[  21] = 8'hdf;  indices[  22] = 8'hfd;  indices[  23] = 8'hff;
    indices[  24] = 8'hdf;  indices[  25] = 8'hfd;  indices[  26] = 8'hff;  indices[  27] = 8'hdf;  indices[  28] = 8'hfd;  indices[  29] = 8'hff;  indices[  30] = 8'hdf;  indices[  31] = 8'hff;
    indices[  32] = 8'hff;  indices[  33] = 8'hdf;  indices[  34] = 8'hff;  indices[  35] = 8'hfd;  indices[  36] = 8'hff;  indices[  37] = 8'hdf;  indices[  38] = 8'hff;  indices[  39] = 8'hff;
    indices[  40] = 8'hff;  indices[  41] = 8'hff;  indices[  42] = 8'hcf;  indices[  43] = 8'hbb;  indices[  44] = 8'hbb;  indices[  45] = 8'hbb;  indices[  46] = 8'h7b;  indices[  47] = 8'h66;
    indices[  48] = 8'h77;  indices[  49] = 8'h77;  indices[  50] = 8'h67;  indices[  51] = 8'h76;  indices[  52] = 8'hba;  indices[  53] = 8'hdb;  indices[  54] = 8'hdd;  indices[  55] = 8'hff;
    indices[  56] = 8'hdd;  indices[  57] = 8'hdd;  indices[  58] = 8'hdf;  indices[  59] = 8'hff;  indices[  60] = 8'hdf;  indices[  61] = 8'hff;  indices[  62] = 8'hfd;  indices[  63] = 8'hdd;
    indices[  64] = 8'hdf;  indices[  65] = 8'hdf;  indices[  66] = 8'hfd;  indices[  67] = 8'hdf;  indices[  68] = 8'hdf;  indices[  69] = 8'hde;  indices[  70] = 8'hff;  indices[  71] = 8'hff;
    indices[  72] = 8'hff;  indices[  73] = 8'hbd;  indices[  74] = 8'hbb;  indices[  75] = 8'hbb;  indices[  76] = 8'hbb;  indices[  77] = 8'hbb;  indices[  78] = 8'h7b;  indices[  79] = 8'h76;
    indices[  80] = 8'h77;  indices[  81] = 8'h77;  indices[  82] = 8'h77;  indices[  83] = 8'h77;  indices[  84] = 8'ha9;  indices[  85] = 8'h69;  indices[  86] = 8'hb6;  indices[  87] = 8'hdd;
    indices[  88] = 8'hdd;  indices[  89] = 8'hdd;  indices[  90] = 8'hfd;  indices[  91] = 8'hff;  indices[  92] = 8'hff;  indices[  93] = 8'hdf;  indices[  94] = 8'hdd;  indices[  95] = 8'hff;
    indices[  96] = 8'hfd;  indices[  97] = 8'hdd;  indices[  98] = 8'hdd;  indices[  99] = 8'hdf;  indices[ 100] = 8'hfd;  indices[ 101] = 8'hfe;  indices[ 102] = 8'hff;  indices[ 103] = 8'hff;
    indices[ 104] = 8'hbd;  indices[ 105] = 8'hbb;  indices[ 106] = 8'hbb;  indices[ 107] = 8'hbb;  indices[ 108] = 8'hbb;  indices[ 109] = 8'hbb;  indices[ 110] = 8'h9b;  indices[ 111] = 8'h77;
    indices[ 112] = 8'h77;  indices[ 113] = 8'h77;  indices[ 114] = 8'h77;  indices[ 115] = 8'h77;  indices[ 116] = 8'haa;  indices[ 117] = 8'h69;  indices[ 118] = 8'h63;  indices[ 119] = 8'h96;
    indices[ 120] = 8'hff;  indices[ 121] = 8'hdf;  indices[ 122] = 8'hfd;  indices[ 123] = 8'hdf;  indices[ 124] = 8'hdd;  indices[ 125] = 8'hdd;  indices[ 126] = 8'hdf;  indices[ 127] = 8'hdd;
    indices[ 128] = 8'hdd;  indices[ 129] = 8'hff;  indices[ 130] = 8'hfd;  indices[ 131] = 8'hff;  indices[ 132] = 8'hfd;  indices[ 133] = 8'hff;  indices[ 134] = 8'hff;  indices[ 135] = 8'hcf;
    indices[ 136] = 8'hbb;  indices[ 137] = 8'hbb;  indices[ 138] = 8'hbb;  indices[ 139] = 8'hbb;  indices[ 140] = 8'hbb;  indices[ 141] = 8'hbb;  indices[ 142] = 8'h69;  indices[ 143] = 8'h33;
    indices[ 144] = 8'h33;  indices[ 145] = 8'h33;  indices[ 146] = 8'h76;  indices[ 147] = 8'h77;  indices[ 148] = 8'haa;  indices[ 149] = 8'h69;  indices[ 150] = 8'h63;  indices[ 151] = 8'h01;
    indices[ 152] = 8'hd6;  indices[ 153] = 8'hdf;  indices[ 154] = 8'hdf;  indices[ 155] = 8'hdd;  indices[ 156] = 8'hdf;  indices[ 157] = 8'hdf;  indices[ 158] = 8'hff;  indices[ 159] = 8'hdf;
    indices[ 160] = 8'hdf;  indices[ 161] = 8'hdf;  indices[ 162] = 8'hdf;  indices[ 163] = 8'hdd;  indices[ 164] = 8'hdd;  indices[ 165] = 8'hff;  indices[ 166] = 8'hce;  indices[ 167] = 8'hbb;
    indices[ 168] = 8'hbb;  indices[ 169] = 8'hbb;  indices[ 170] = 8'hbb;  indices[ 171] = 8'hbb;  indices[ 172] = 8'h7a;  indices[ 173] = 8'h66;  indices[ 174] = 8'h44;  indices[ 175] = 8'h66;
    indices[ 176] = 8'h22;  indices[ 177] = 8'h22;  indices[ 178] = 8'h11;  indices[ 179] = 8'h73;  indices[ 180] = 8'haa;  indices[ 181] = 8'h69;  indices[ 182] = 8'h63;  indices[ 183] = 8'h01;
    indices[ 184] = 8'h10;  indices[ 185] = 8'hd6;  indices[ 186] = 8'hff;  indices[ 187] = 8'hff;  indices[ 188] = 8'hdf;  indices[ 189] = 8'hdd;  indices[ 190] = 8'hdf;  indices[ 191] = 8'hfd;
    indices[ 192] = 8'hdf;  indices[ 193] = 8'hdd;  indices[ 194] = 8'hdd;  indices[ 195] = 8'hdd;  indices[ 196] = 8'hff;  indices[ 197] = 8'hde;  indices[ 198] = 8'hbb;  indices[ 199] = 8'hbb;
    indices[ 200] = 8'hbb;  indices[ 201] = 8'hbb;  indices[ 202] = 8'haa;  indices[ 203] = 8'h67;  indices[ 204] = 8'ha7;  indices[ 205] = 8'h48;  indices[ 206] = 8'h44;  indices[ 207] = 8'h45;
    indices[ 208] = 8'h54;  indices[ 209] = 8'h44;  indices[ 210] = 8'h44;  indices[ 211] = 8'h32;  indices[ 212] = 8'h96;  indices[ 213] = 8'h69;  indices[ 214] = 8'h63;  indices[ 215] = 8'h11;
    indices[ 216] = 8'h13;  indices[ 217] = 8'h30;  indices[ 218] = 8'hdd;  indices[ 219] = 8'hfd;  indices[ 220] = 8'hdf;  indices[ 221] = 8'hdf;  indices[ 222] = 8'hfd;  indices[ 223] = 8'hff;
    indices[ 224] = 8'hdd;  indices[ 225] = 8'hdf;  indices[ 226] = 8'hff;  indices[ 227] = 8'hff;  indices[ 228] = 8'hdd;  indices[ 229] = 8'h9d;  indices[ 230] = 8'hb9;  indices[ 231] = 8'hbb;
    indices[ 232] = 8'hbb;  indices[ 233] = 8'hbb;  indices[ 234] = 8'h9a;  indices[ 235] = 8'hba;  indices[ 236] = 8'hbc;  indices[ 237] = 8'h45;  indices[ 238] = 8'h44;  indices[ 239] = 8'h48;
    indices[ 240] = 8'h54;  indices[ 241] = 8'h55;  indices[ 242] = 8'h48;  indices[ 243] = 8'h42;  indices[ 244] = 8'h32;  indices[ 245] = 8'h66;  indices[ 246] = 8'h63;  indices[ 247] = 8'h10;
    indices[ 248] = 8'h63;  indices[ 249] = 8'h66;  indices[ 250] = 8'hc7;  indices[ 251] = 8'hdf;  indices[ 252] = 8'hdd;  indices[ 253] = 8'hff;  indices[ 254] = 8'hfd;  indices[ 255] = 8'hfd;
    indices[ 256] = 8'hdd;  indices[ 257] = 8'hff;  indices[ 258] = 8'hdf;  indices[ 259] = 8'hdf;  indices[ 260] = 8'hbd;  indices[ 261] = 8'h7b;  indices[ 262] = 8'hb9;  indices[ 263] = 8'hbb;
    indices[ 264] = 8'hbb;  indices[ 265] = 8'hab;  indices[ 266] = 8'hba;  indices[ 267] = 8'hcb;  indices[ 268] = 8'hbc;  indices[ 269] = 8'h44;  indices[ 270] = 8'h44;  indices[ 271] = 8'h88;
    indices[ 272] = 8'h45;  indices[ 273] = 8'h44;  indices[ 274] = 8'h48;  indices[ 275] = 8'h52;  indices[ 276] = 8'h24;  indices[ 277] = 8'h32;  indices[ 278] = 8'h63;  indices[ 279] = 8'h01;
    indices[ 280] = 8'h00;  indices[ 281] = 8'h11;  indices[ 282] = 8'h30;  indices[ 283] = 8'hf9;  indices[ 284] = 8'hfd;  indices[ 285] = 8'hdf;  indices[ 286] = 8'hdf;  indices[ 287] = 8'hdf;
    indices[ 288] = 8'hfd;  indices[ 289] = 8'hff;  indices[ 290] = 8'hff;  indices[ 291] = 8'hdf;  indices[ 292] = 8'h7b;  indices[ 293] = 8'h7a;  indices[ 294] = 8'hb7;  indices[ 295] = 8'hbb;
    indices[ 296] = 8'hbb;  indices[ 297] = 8'haa;  indices[ 298] = 8'hbb;  indices[ 299] = 8'hcb;  indices[ 300] = 8'h9c;  indices[ 301] = 8'h54;  indices[ 302] = 8'h44;  indices[ 303] = 8'h48;
    indices[ 304] = 8'ha5;  indices[ 305] = 8'h44;  indices[ 306] = 8'h45;  indices[ 307] = 8'h52;  indices[ 308] = 8'h54;  indices[ 309] = 8'h25;  indices[ 310] = 8'h63;  indices[ 311] = 8'h33;
    indices[ 312] = 8'h00;  indices[ 313] = 8'h11;  indices[ 314] = 8'h00;  indices[ 315] = 8'h93;  indices[ 316] = 8'hdf;  indices[ 317] = 8'hdd;  indices[ 318] = 8'hdf;  indices[ 319] = 8'hdf;
    indices[ 320] = 8'hfd;  indices[ 321] = 8'hdd;  indices[ 322] = 8'hdd;  indices[ 323] = 8'hcd;  indices[ 324] = 8'h67;  indices[ 325] = 8'h9a;  indices[ 326] = 8'hb7;  indices[ 327] = 8'hbb;
    indices[ 328] = 8'hbb;  indices[ 329] = 8'hab;  indices[ 330] = 8'hbb;  indices[ 331] = 8'hcb;  indices[ 332] = 8'h5c;  indices[ 333] = 8'h44;  indices[ 334] = 8'h44;  indices[ 335] = 8'h45;
    indices[ 336] = 8'h44;  indices[ 337] = 8'h44;  indices[ 338] = 8'h48;  indices[ 339] = 8'h52;  indices[ 340] = 8'h54;  indices[ 341] = 8'h25;  indices[ 342] = 8'h66;  indices[ 343] = 8'h01;
    indices[ 344] = 8'h00;  indices[ 345] = 8'h00;  indices[ 346] = 8'h00;  indices[ 347] = 8'h10;  indices[ 348] = 8'hdb;  indices[ 349] = 8'hff;  indices[ 350] = 8'hff;  indices[ 351] = 8'hdf;
    indices[ 352] = 8'hdf;  indices[ 353] = 8'hdd;  indices[ 354] = 8'hff;  indices[ 355] = 8'h7d;  indices[ 356] = 8'h66;  indices[ 357] = 8'h9a;  indices[ 358] = 8'hb7;  indices[ 359] = 8'hbb;
    indices[ 360] = 8'hbb;  indices[ 361] = 8'hab;  indices[ 362] = 8'hbb;  indices[ 363] = 8'hcb;  indices[ 364] = 8'h5c;  indices[ 365] = 8'h84;  indices[ 366] = 8'h44;  indices[ 367] = 8'h58;
    indices[ 368] = 8'h55;  indices[ 369] = 8'h85;  indices[ 370] = 8'h48;  indices[ 371] = 8'h52;  indices[ 372] = 8'h54;  indices[ 373] = 8'h7b;  indices[ 374] = 8'h67;  indices[ 375] = 8'h13;
    indices[ 376] = 8'h00;  indices[ 377] = 8'h10;  indices[ 378] = 8'h11;  indices[ 379] = 8'h31;  indices[ 380] = 8'hd6;  indices[ 381] = 8'hdd;  indices[ 382] = 8'hfd;  indices[ 383] = 8'hfd;
    indices[ 384] = 8'hff;  indices[ 385] = 8'hdd;  indices[ 386] = 8'hfd;  indices[ 387] = 8'h68;  indices[ 388] = 8'h36;  indices[ 389] = 8'haa;  indices[ 390] = 8'hb6;  indices[ 391] = 8'hbb;
    indices[ 392] = 8'hbb;  indices[ 393] = 8'haa;  indices[ 394] = 8'hbb;  indices[ 395] = 8'hcb;  indices[ 396] = 8'h4c;  indices[ 397] = 8'hb5;  indices[ 398] = 8'hb8;  indices[ 399] = 8'hcc;
    indices[ 400] = 8'hcc;  indices[ 401] = 8'hcc;  indices[ 402] = 8'h8b;  indices[ 403] = 8'h85;  indices[ 404] = 8'h44;  indices[ 405] = 8'h55;  indices[ 406] = 8'h67;  indices[ 407] = 8'h16;
    indices[ 408] = 8'h01;  indices[ 409] = 8'h10;  indices[ 410] = 8'h11;  indices[ 411] = 8'h31;  indices[ 412] = 8'h73;  indices[ 413] = 8'hdf;  indices[ 414] = 8'hfd;  indices[ 415] = 8'hdf;
    indices[ 416] = 8'hdd;  indices[ 417] = 8'hdd;  indices[ 418] = 8'h7f;  indices[ 419] = 8'h33;  indices[ 420] = 8'h11;  indices[ 421] = 8'ha9;  indices[ 422] = 8'hb6;  indices[ 423] = 8'hbb;
    indices[ 424] = 8'hbb;  indices[ 425] = 8'ha9;  indices[ 426] = 8'hbb;  indices[ 427] = 8'hbb;  indices[ 428] = 8'h9b;  indices[ 429] = 8'hcc;  indices[ 430] = 8'hcc;  indices[ 431] = 8'hcc;
    indices[ 432] = 8'hab;  indices[ 433] = 8'hcb;  indices[ 434] = 8'hcc;  indices[ 435] = 8'hcc;  indices[ 436] = 8'h48;  indices[ 437] = 8'h24;  indices[ 438] = 8'h67;  indices[ 439] = 8'h16;
    indices[ 440] = 8'h11;  indices[ 441] = 8'h11;  indices[ 442] = 8'h01;  indices[ 443] = 8'h00;  indices[ 444] = 8'h31;  indices[ 445] = 8'hfa;  indices[ 446] = 8'hff;  indices[ 447] = 8'hfd;
    indices[ 448] = 8'hdd;  indices[ 449] = 8'hff;  indices[ 450] = 8'h1f;  indices[ 451] = 8'h10;  indices[ 452] = 8'h11;  indices[ 453] = 8'hb9;  indices[ 454] = 8'hb6;  indices[ 455] = 8'hbb;
    indices[ 456] = 8'hbb;  indices[ 457] = 8'hb9;  indices[ 458] = 8'hbb;  indices[ 459] = 8'hbb;  indices[ 460] = 8'hcc;  indices[ 461] = 8'hac;  indices[ 462] = 8'h9a;  indices[ 463] = 8'haa;
    indices[ 464] = 8'hbb;  indices[ 465] = 8'h9a;  indices[ 466] = 8'h99;  indices[ 467] = 8'hb9;  indices[ 468] = 8'h8c;  indices[ 469] = 8'h25;  indices[ 470] = 8'h67;  indices[ 471] = 8'h36;
    indices[ 472] = 8'h01;  indices[ 473] = 8'h00;  indices[ 474] = 8'h10;  indices[ 475] = 8'h31;  indices[ 476] = 8'h11;  indices[ 477] = 8'hf6;  indices[ 478] = 8'hfd;  indices[ 479] = 8'hdd;
    indices[ 480] = 8'hdf;  indices[ 481] = 8'hdd;  indices[ 482] = 8'h03;  indices[ 483] = 8'h10;  indices[ 484] = 8'h63;  indices[ 485] = 8'haa;  indices[ 486] = 8'hb6;  indices[ 487] = 8'hbb;
    indices[ 488] = 8'hab;  indices[ 489] = 8'hb9;  indices[ 490] = 8'hba;  indices[ 491] = 8'hbb;  indices[ 492] = 8'haa;  indices[ 493] = 8'hba;  indices[ 494] = 8'hcc;  indices[ 495] = 8'hcc;
    indices[ 496] = 8'hcc;  indices[ 497] = 8'hcc;  indices[ 498] = 8'hcc;  indices[ 499] = 8'h9b;  indices[ 500] = 8'h97;  indices[ 501] = 8'h7a;  indices[ 502] = 8'h67;  indices[ 503] = 8'h66;
    indices[ 504] = 8'h01;  indices[ 505] = 8'h00;  indices[ 506] = 8'h10;  indices[ 507] = 8'h63;  indices[ 508] = 8'h11;  indices[ 509] = 8'h93;  indices[ 510] = 8'hfd;  indices[ 511] = 8'hff;
    indices[ 512] = 8'hdd;  indices[ 513] = 8'hbd;  indices[ 514] = 8'h13;  indices[ 515] = 8'h31;  indices[ 516] = 8'h66;  indices[ 517] = 8'haa;  indices[ 518] = 8'hb6;  indices[ 519] = 8'hbb;
    indices[ 520] = 8'h9b;  indices[ 521] = 8'hb9;  indices[ 522] = 8'hba;  indices[ 523] = 8'haa;  indices[ 524] = 8'hcb;  indices[ 525] = 8'hcc;  indices[ 526] = 8'hcc;  indices[ 527] = 8'hcc;
    indices[ 528] = 8'hbb;  indices[ 529] = 8'hcc;  indices[ 530] = 8'hcc;  indices[ 531] = 8'hcc;  indices[ 532] = 8'h7c;  indices[ 533] = 8'h66;  indices[ 534] = 8'h66;  indices[ 535] = 8'h33;
    indices[ 536] = 8'h00;  indices[ 537] = 8'h00;  indices[ 538] = 8'h11;  indices[ 539] = 8'h16;  indices[ 540] = 8'h11;  indices[ 541] = 8'h63;  indices[ 542] = 8'hdb;  indices[ 543] = 8'hdd;
    indices[ 544] = 8'hdf;  indices[ 545] = 8'h7f;  indices[ 546] = 8'h33;  indices[ 547] = 8'h33;  indices[ 548] = 8'h66;  indices[ 549] = 8'hb9;  indices[ 550] = 8'hb6;  indices[ 551] = 8'hbb;
    indices[ 552] = 8'h9b;  indices[ 553] = 8'hb9;  indices[ 554] = 8'haa;  indices[ 555] = 8'hcc;  indices[ 556] = 8'hcc;  indices[ 557] = 8'hbb;  indices[ 558] = 8'hab;  indices[ 559] = 8'haa;
    indices[ 560] = 8'haa;  indices[ 561] = 8'hbb;  indices[ 562] = 8'hbb;  indices[ 563] = 8'hcc;  indices[ 564] = 8'hcc;  indices[ 565] = 8'h6b;  indices[ 566] = 8'h66;  indices[ 567] = 8'h33;
    indices[ 568] = 8'h00;  indices[ 569] = 8'h41;  indices[ 570] = 8'h66;  indices[ 571] = 8'h03;  indices[ 572] = 8'h11;  indices[ 573] = 8'h63;  indices[ 574] = 8'hd7;  indices[ 575] = 8'hff;
    indices[ 576] = 8'hdd;  indices[ 577] = 8'h6b;  indices[ 578] = 8'h33;  indices[ 579] = 8'h23;  indices[ 580] = 8'h32;  indices[ 581] = 8'hb9;  indices[ 582] = 8'hb6;  indices[ 583] = 8'hbb;
    indices[ 584] = 8'h9a;  indices[ 585] = 8'haa;  indices[ 586] = 8'hcb;  indices[ 587] = 8'hcc;  indices[ 588] = 8'hbb;  indices[ 589] = 8'hbb;  indices[ 590] = 8'h9a;  indices[ 591] = 8'h88;
    indices[ 592] = 8'h99;  indices[ 593] = 8'h99;  indices[ 594] = 8'haa;  indices[ 595] = 8'hbb;  indices[ 596] = 8'hcb;  indices[ 597] = 8'hcc;  indices[ 598] = 8'h67;  indices[ 599] = 8'h33;
    indices[ 600] = 8'h00;  indices[ 601] = 8'h63;  indices[ 602] = 8'h66;  indices[ 603] = 8'h46;  indices[ 604] = 8'h34;  indices[ 605] = 8'h63;  indices[ 606] = 8'hb7;  indices[ 607] = 8'hfd;
    indices[ 608] = 8'hdd;  indices[ 609] = 8'h67;  indices[ 610] = 8'h66;  indices[ 611] = 8'h23;  indices[ 612] = 8'h22;  indices[ 613] = 8'hb7;  indices[ 614] = 8'hb6;  indices[ 615] = 8'hbb;
    indices[ 616] = 8'h99;  indices[ 617] = 8'hc9;  indices[ 618] = 8'hcc;  indices[ 619] = 8'hbb;  indices[ 620] = 8'hbb;  indices[ 621] = 8'hab;  indices[ 622] = 8'h89;  indices[ 623] = 8'h88;
    indices[ 624] = 8'h88;  indices[ 625] = 8'h88;  indices[ 626] = 8'h98;  indices[ 627] = 8'h99;  indices[ 628] = 8'hba;  indices[ 629] = 8'hcc;  indices[ 630] = 8'h9c;  indices[ 631] = 8'h63;
    indices[ 632] = 8'h33;  indices[ 633] = 8'h31;  indices[ 634] = 8'h66;  indices[ 635] = 8'h33;  indices[ 636] = 8'h31;  indices[ 637] = 8'h63;  indices[ 638] = 8'h96;  indices[ 639] = 8'hdf;
    indices[ 640] = 8'hff;  indices[ 641] = 8'h67;  indices[ 642] = 8'h36;  indices[ 643] = 8'h33;  indices[ 644] = 8'h33;  indices[ 645] = 8'ha7;  indices[ 646] = 8'hb6;  indices[ 647] = 8'hbb;
    indices[ 648] = 8'h99;  indices[ 649] = 8'hcc;  indices[ 650] = 8'hbb;  indices[ 651] = 8'haa;  indices[ 652] = 8'hba;  indices[ 653] = 8'h9a;  indices[ 654] = 8'h88;  indices[ 655] = 8'h88;
    indices[ 656] = 8'h88;  indices[ 657] = 8'h88;  indices[ 658] = 8'h88;  indices[ 659] = 8'h98;  indices[ 660] = 8'ha9;  indices[ 661] = 8'hbb;  indices[ 662] = 8'hcc;  indices[ 663] = 8'h69;
    indices[ 664] = 8'h33;  indices[ 665] = 8'h00;  indices[ 666] = 8'h11;  indices[ 667] = 8'h00;  indices[ 668] = 8'h30;  indices[ 669] = 8'h33;  indices[ 670] = 8'h76;  indices[ 671] = 8'hdf;
    indices[ 672] = 8'haf;  indices[ 673] = 8'h33;  indices[ 674] = 8'h63;  indices[ 675] = 8'h36;  indices[ 676] = 8'h36;  indices[ 677] = 8'hb6;  indices[ 678] = 8'ha6;  indices[ 679] = 8'hbb;
    indices[ 680] = 8'hb9;  indices[ 681] = 8'hac;  indices[ 682] = 8'h88;  indices[ 683] = 8'h98;  indices[ 684] = 8'h9a;  indices[ 685] = 8'h88;  indices[ 686] = 8'h88;  indices[ 687] = 8'h88;
    indices[ 688] = 8'h88;  indices[ 689] = 8'h87;  indices[ 690] = 8'h88;  indices[ 691] = 8'h98;  indices[ 692] = 8'ha9;  indices[ 693] = 8'hba;  indices[ 694] = 8'hcb;  indices[ 695] = 8'h9b;
    indices[ 696] = 8'h11;  indices[ 697] = 8'h00;  indices[ 698] = 8'h00;  indices[ 699] = 8'h00;  indices[ 700] = 8'h11;  indices[ 701] = 8'h63;  indices[ 702] = 8'h66;  indices[ 703] = 8'hda;
    indices[ 704] = 8'h6f;  indices[ 705] = 8'h11;  indices[ 706] = 8'h31;  indices[ 707] = 8'h66;  indices[ 708] = 8'h36;  indices[ 709] = 8'hb6;  indices[ 710] = 8'hb7;  indices[ 711] = 8'hab;
    indices[ 712] = 8'hca;  indices[ 713] = 8'h27;  indices[ 714] = 8'h42;  indices[ 715] = 8'h74;  indices[ 716] = 8'h88;  indices[ 717] = 8'h88;  indices[ 718] = 8'h88;  indices[ 719] = 8'h78;
    indices[ 720] = 8'h77;  indices[ 721] = 8'h77;  indices[ 722] = 8'h88;  indices[ 723] = 8'h88;  indices[ 724] = 8'ha9;  indices[ 725] = 8'haa;  indices[ 726] = 8'hbb;  indices[ 727] = 8'hab;
    indices[ 728] = 8'h17;  indices[ 729] = 8'h00;  indices[ 730] = 8'h00;  indices[ 731] = 8'h00;  indices[ 732] = 8'h11;  indices[ 733] = 8'h33;  indices[ 734] = 8'h66;  indices[ 735] = 8'hd9;
    indices[ 736] = 8'h6d;  indices[ 737] = 8'h03;  indices[ 738] = 8'h01;  indices[ 739] = 8'h31;  indices[ 740] = 8'h63;  indices[ 741] = 8'ha6;  indices[ 742] = 8'hac;  indices[ 743] = 8'hab;
    indices[ 744] = 8'h8a;  indices[ 745] = 8'h24;  indices[ 746] = 8'h12;  indices[ 747] = 8'h73;  indices[ 748] = 8'h88;  indices[ 749] = 8'h88;  indices[ 750] = 8'h78;  indices[ 751] = 8'h57;
    indices[ 752] = 8'h57;  indices[ 753] = 8'h55;  indices[ 754] = 8'h87;  indices[ 755] = 8'h88;  indices[ 756] = 8'ha9;  indices[ 757] = 8'haa;  indices[ 758] = 8'haa;  indices[ 759] = 8'hab;
    indices[ 760] = 8'h69;  indices[ 761] = 8'h00;  indices[ 762] = 8'h00;  indices[ 763] = 8'h00;  indices[ 764] = 8'h11;  indices[ 765] = 8'h10;  indices[ 766] = 8'h66;  indices[ 767] = 8'hf7;
    indices[ 768] = 8'h39;  indices[ 769] = 8'h13;  indices[ 770] = 8'h11;  indices[ 771] = 8'h11;  indices[ 772] = 8'h33;  indices[ 773] = 8'h96;  indices[ 774] = 8'hbc;  indices[ 775] = 8'h9b;
    indices[ 776] = 8'h77;  indices[ 777] = 8'h66;  indices[ 778] = 8'h66;  indices[ 779] = 8'h97;  indices[ 780] = 8'hba;  indices[ 781] = 8'hcb;  indices[ 782] = 8'h9b;  indices[ 783] = 8'h58;
    indices[ 784] = 8'h55;  indices[ 785] = 8'h55;  indices[ 786] = 8'h75;  indices[ 787] = 8'h87;  indices[ 788] = 8'h98;  indices[ 789] = 8'haa;  indices[ 790] = 8'h99;  indices[ 791] = 8'hba;
    indices[ 792] = 8'h79;  indices[ 793] = 8'h03;  indices[ 794] = 8'h00;  indices[ 795] = 8'h00;  indices[ 796] = 8'h00;  indices[ 797] = 8'h10;  indices[ 798] = 8'h66;  indices[ 799] = 8'hb6;
    indices[ 800] = 8'h36;  indices[ 801] = 8'h13;  indices[ 802] = 8'h11;  indices[ 803] = 8'h10;  indices[ 804] = 8'h31;  indices[ 805] = 8'h96;  indices[ 806] = 8'hba;  indices[ 807] = 8'h79;
    indices[ 808] = 8'h67;  indices[ 809] = 8'hb6;  indices[ 810] = 8'h76;  indices[ 811] = 8'h77;  indices[ 812] = 8'h99;  indices[ 813] = 8'hba;  indices[ 814] = 8'hbc;  indices[ 815] = 8'h78;
    indices[ 816] = 8'h55;  indices[ 817] = 8'h55;  indices[ 818] = 8'h55;  indices[ 819] = 8'h88;  indices[ 820] = 8'ha9;  indices[ 821] = 8'haa;  indices[ 822] = 8'h79;  indices[ 823] = 8'ha7;
    indices[ 824] = 8'h37;  indices[ 825] = 8'h00;  indices[ 826] = 8'h00;  indices[ 827] = 8'h00;  indices[ 828] = 8'h00;  indices[ 829] = 8'h10;  indices[ 830] = 8'h66;  indices[ 831] = 8'h96;
    indices[ 832] = 8'h03;  indices[ 833] = 8'h00;  indices[ 834] = 8'h11;  indices[ 835] = 8'h10;  indices[ 836] = 8'h31;  indices[ 837] = 8'h96;  indices[ 838] = 8'h79;  indices[ 839] = 8'h87;
    indices[ 840] = 8'h66;  indices[ 841] = 8'h76;  indices[ 842] = 8'h74;  indices[ 843] = 8'h66;  indices[ 844] = 8'h77;  indices[ 845] = 8'h67;  indices[ 846] = 8'h97;  indices[ 847] = 8'h8a;
    indices[ 848] = 8'h45;  indices[ 849] = 8'h55;  indices[ 850] = 8'h75;  indices[ 851] = 8'hba;  indices[ 852] = 8'hbb;  indices[ 853] = 8'hbb;  indices[ 854] = 8'h38;  indices[ 855] = 8'h73;
    indices[ 856] = 8'h01;  indices[ 857] = 8'h00;  indices[ 858] = 8'h00;  indices[ 859] = 8'h00;  indices[ 860] = 8'h00;  indices[ 861] = 8'h10;  indices[ 862] = 8'h66;  indices[ 863] = 8'h76;
    indices[ 864] = 8'h13;  indices[ 865] = 8'h01;  indices[ 866] = 8'h00;  indices[ 867] = 8'h10;  indices[ 868] = 8'h31;  indices[ 869] = 8'h96;  indices[ 870] = 8'h77;  indices[ 871] = 8'hb7;
    indices[ 872] = 8'h99;  indices[ 873] = 8'h47;  indices[ 874] = 8'h22;  indices[ 875] = 8'h44;  indices[ 876] = 8'h87;  indices[ 877] = 8'h77;  indices[ 878] = 8'h45;  indices[ 879] = 8'hb7;
    indices[ 880] = 8'h57;  indices[ 881] = 8'h55;  indices[ 882] = 8'h87;  indices[ 883] = 8'ha9;  indices[ 884] = 8'hbb;  indices[ 885] = 8'hbc;  indices[ 886] = 8'h19;  indices[ 887] = 8'h31;
    indices[ 888] = 8'h00;  indices[ 889] = 8'h00;  indices[ 890] = 8'h00;  indices[ 891] = 8'h00;  indices[ 892] = 8'h00;  indices[ 893] = 8'h30;  indices[ 894] = 8'h66;  indices[ 895] = 8'h76;
    indices[ 896] = 8'h33;  indices[ 897] = 8'h13;  indices[ 898] = 8'h01;  indices[ 899] = 8'h10;  indices[ 900] = 8'h31;  indices[ 901] = 8'h93;  indices[ 902] = 8'h8b;  indices[ 903] = 8'h87;
    indices[ 904] = 8'h7a;  indices[ 905] = 8'h26;  indices[ 906] = 8'h11;  indices[ 907] = 8'h95;  indices[ 908] = 8'hb6;  indices[ 909] = 8'h89;  indices[ 910] = 8'h57;  indices[ 911] = 8'h94;
    indices[ 912] = 8'hab;  indices[ 913] = 8'h88;  indices[ 914] = 8'h9a;  indices[ 915] = 8'h77;  indices[ 916] = 8'h77;  indices[ 917] = 8'h98;  indices[ 918] = 8'h69;  indices[ 919] = 8'h36;
    indices[ 920] = 8'h01;  indices[ 921] = 8'h00;  indices[ 922] = 8'h00;  indices[ 923] = 8'h00;  indices[ 924] = 8'h00;  indices[ 925] = 8'h11;  indices[ 926] = 8'h11;  indices[ 927] = 8'h63;
    indices[ 928] = 8'h33;  indices[ 929] = 8'h13;  indices[ 930] = 8'h33;  indices[ 931] = 8'h11;  indices[ 932] = 8'h31;  indices[ 933] = 8'h93;  indices[ 934] = 8'h7b;  indices[ 935] = 8'h62;
    indices[ 936] = 8'h49;  indices[ 937] = 8'h25;  indices[ 938] = 8'h22;  indices[ 939] = 8'h44;  indices[ 940] = 8'ha7;  indices[ 941] = 8'h78;  indices[ 942] = 8'h78;  indices[ 943] = 8'h74;
    indices[ 944] = 8'hbb;  indices[ 945] = 8'hcc;  indices[ 946] = 8'h78;  indices[ 947] = 8'h77;  indices[ 948] = 8'h77;  indices[ 949] = 8'h66;  indices[ 950] = 8'h36;  indices[ 951] = 8'h99;
    indices[ 952] = 8'h03;  indices[ 953] = 8'h00;  indices[ 954] = 8'h00;  indices[ 955] = 8'h00;  indices[ 956] = 8'h10;  indices[ 957] = 8'h11;  indices[ 958] = 8'h01;  indices[ 959] = 8'h10;
    indices[ 960] = 8'h11;  indices[ 961] = 8'h13;  indices[ 962] = 8'h13;  indices[ 963] = 8'h11;  indices[ 964] = 8'h31;  indices[ 965] = 8'h93;  indices[ 966] = 8'h2b;  indices[ 967] = 8'h44;
    indices[ 968] = 8'h27;  indices[ 969] = 8'h24;  indices[ 970] = 8'h22;  indices[ 971] = 8'h22;  indices[ 972] = 8'h54;  indices[ 973] = 8'h77;  indices[ 974] = 8'h78;  indices[ 975] = 8'h95;
    indices[ 976] = 8'h57;  indices[ 977] = 8'hb8;  indices[ 978] = 8'h88;  indices[ 979] = 8'h99;  indices[ 980] = 8'h79;  indices[ 981] = 8'h56;  indices[ 982] = 8'h13;  indices[ 983] = 8'h77;
    indices[ 984] = 8'h19;  indices[ 985] = 8'h00;  indices[ 986] = 8'h00;  indices[ 987] = 8'h11;  indices[ 988] = 8'h11;  indices[ 989] = 8'h01;  indices[ 990] = 8'h00;  indices[ 991] = 8'h00;
    indices[ 992] = 8'h11;  indices[ 993] = 8'h11;  indices[ 994] = 8'h10;  indices[ 995] = 8'h11;  indices[ 996] = 8'h11;  indices[ 997] = 8'h93;  indices[ 998] = 8'h4b;  indices[ 999] = 8'h24;
    indices[1000] = 8'h22;  indices[1001] = 8'h23;  indices[1002] = 8'h42;  indices[1003] = 8'h44;  indices[1004] = 8'h54;  indices[1005] = 8'h55;  indices[1006] = 8'h57;  indices[1007] = 8'h86;
    indices[1008] = 8'h75;  indices[1009] = 8'hb8;  indices[1010] = 8'h97;  indices[1011] = 8'hba;  indices[1012] = 8'h79;  indices[1013] = 8'h58;  indices[1014] = 8'h32;  indices[1015] = 8'h79;
    indices[1016] = 8'h39;  indices[1017] = 8'h00;  indices[1018] = 8'h11;  indices[1019] = 8'h11;  indices[1020] = 8'h11;  indices[1021] = 8'h31;  indices[1022] = 8'h01;  indices[1023] = 8'h10;
    indices[1024] = 8'h33;  indices[1025] = 8'h11;  indices[1026] = 8'h00;  indices[1027] = 8'h10;  indices[1028] = 8'h11;  indices[1029] = 8'h93;  indices[1030] = 8'h4b;  indices[1031] = 8'h22;
    indices[1032] = 8'h22;  indices[1033] = 8'h42;  indices[1034] = 8'h22;  indices[1035] = 8'h54;  indices[1036] = 8'h55;  indices[1037] = 8'h55;  indices[1038] = 8'h44;  indices[1039] = 8'h27;
    indices[1040] = 8'h85;  indices[1041] = 8'ha8;  indices[1042] = 8'h76;  indices[1043] = 8'h98;  indices[1044] = 8'h88;  indices[1045] = 8'h79;  indices[1046] = 8'h32;  indices[1047] = 8'h66;
    indices[1048] = 8'h36;  indices[1049] = 8'h11;  indices[1050] = 8'h11;  indices[1051] = 8'h01;  indices[1052] = 8'h10;  indices[1053] = 8'h00;  indices[1054] = 8'h11;  indices[1055] = 8'h11;
    indices[1056] = 8'h33;  indices[1057] = 8'h33;  indices[1058] = 8'h33;  indices[1059] = 8'h33;  indices[1060] = 8'h33;  indices[1061] = 8'h96;  indices[1062] = 8'h4b;  indices[1063] = 8'h42;
    indices[1064] = 8'h22;  indices[1065] = 8'h61;  indices[1066] = 8'h22;  indices[1067] = 8'h54;  indices[1068] = 8'h55;  indices[1069] = 8'h45;  indices[1070] = 8'h54;  indices[1071] = 8'h24;
    indices[1072] = 8'h55;  indices[1073] = 8'h95;  indices[1074] = 8'h54;  indices[1075] = 8'h55;  indices[1076] = 8'h55;  indices[1077] = 8'h64;  indices[1078] = 8'h33;  indices[1079] = 8'h73;
    indices[1080] = 8'h13;  indices[1081] = 8'h11;  indices[1082] = 8'h00;  indices[1083] = 8'h10;  indices[1084] = 8'h10;  indices[1085] = 8'h11;  indices[1086] = 8'h11;  indices[1087] = 8'h11;
    indices[1088] = 8'h33;  indices[1089] = 8'h33;  indices[1090] = 8'h33;  indices[1091] = 8'h33;  indices[1092] = 8'h33;  indices[1093] = 8'h96;  indices[1094] = 8'h4b;  indices[1095] = 8'h24;
    indices[1096] = 8'h22;  indices[1097] = 8'h11;  indices[1098] = 8'h54;  indices[1099] = 8'h54;  indices[1100] = 8'h55;  indices[1101] = 8'h55;  indices[1102] = 8'h75;  indices[1103] = 8'h21;
    indices[1104] = 8'h55;  indices[1105] = 8'h84;  indices[1106] = 8'h44;  indices[1107] = 8'h55;  indices[1108] = 8'h55;  indices[1109] = 8'h34;  indices[1110] = 8'h31;  indices[1111] = 8'h33;
    indices[1112] = 8'h01;  indices[1113] = 8'h00;  indices[1114] = 8'h00;  indices[1115] = 8'h01;  indices[1116] = 8'h10;  indices[1117] = 8'h11;  indices[1118] = 8'h11;  indices[1119] = 8'h12;
    indices[1120] = 8'h78;  indices[1121] = 8'h98;  indices[1122] = 8'h99;  indices[1123] = 8'haa;  indices[1124] = 8'haa;  indices[1125] = 8'hba;  indices[1126] = 8'h5b;  indices[1127] = 8'h24;
    indices[1128] = 8'h22;  indices[1129] = 8'h01;  indices[1130] = 8'h42;  indices[1131] = 8'h75;  indices[1132] = 8'h88;  indices[1133] = 8'h88;  indices[1134] = 8'h25;  indices[1135] = 8'h22;
    indices[1136] = 8'h55;  indices[1137] = 8'h74;  indices[1138] = 8'h25;  indices[1139] = 8'h42;  indices[1140] = 8'h55;  indices[1141] = 8'h25;  indices[1142] = 8'h21;  indices[1143] = 8'h13;
    indices[1144] = 8'h00;  indices[1145] = 8'h00;  indices[1146] = 8'h00;  indices[1147] = 8'h00;  indices[1148] = 8'h00;  indices[1149] = 8'h00;  indices[1150] = 8'h00;  indices[1151] = 8'h10;
    indices[1152] = 8'hcc;  indices[1153] = 8'hcc;  indices[1154] = 8'hcc;  indices[1155] = 8'hcc;  indices[1156] = 8'hbc;  indices[1157] = 8'hbb;  indices[1158] = 8'h7b;  indices[1159] = 8'h22;
    indices[1160] = 8'h22;  indices[1161] = 8'h12;  indices[1162] = 8'h21;  indices[1163] = 8'h44;  indices[1164] = 8'h44;  indices[1165] = 8'h44;  indices[1166] = 8'h22;  indices[1167] = 8'h22;
    indices[1168] = 8'h44;  indices[1169] = 8'h41;  indices[1170] = 8'h48;  indices[1171] = 8'h42;  indices[1172] = 8'h44;  indices[1173] = 8'h14;  indices[1174] = 8'h22;  indices[1175] = 8'h03;
    indices[1176] = 8'h00;  indices[1177] = 8'h00;  indices[1178] = 8'h00;  indices[1179] = 8'h33;  indices[1180] = 8'h11;  indices[1181] = 8'h00;  indices[1182] = 8'h00;  indices[1183] = 8'h10;
    indices[1184] = 8'h7a;  indices[1185] = 8'h78;  indices[1186] = 8'h77;  indices[1187] = 8'h99;  indices[1188] = 8'h99;  indices[1189] = 8'h99;  indices[1190] = 8'h69;  indices[1191] = 8'h22;
    indices[1192] = 8'h22;  indices[1193] = 8'h22;  indices[1194] = 8'h21;  indices[1195] = 8'h44;  indices[1196] = 8'h44;  indices[1197] = 8'h44;  indices[1198] = 8'h22;  indices[1199] = 8'h21;
    indices[1200] = 8'h54;  indices[1201] = 8'h51;  indices[1202] = 8'h55;  indices[1203] = 8'h57;  indices[1204] = 8'h44;  indices[1205] = 8'h34;  indices[1206] = 8'h64;  indices[1207] = 8'h11;
    indices[1208] = 8'h01;  indices[1209] = 8'h00;  indices[1210] = 8'h00;  indices[1211] = 8'h44;  indices[1212] = 8'h44;  indices[1213] = 8'h34;  indices[1214] = 8'h11;  indices[1215] = 8'h30;
    indices[1216] = 8'hbc;  indices[1217] = 8'hbb;  indices[1218] = 8'hbb;  indices[1219] = 8'hbb;  indices[1220] = 8'haa;  indices[1221] = 8'haa;  indices[1222] = 8'h6a;  indices[1223] = 8'h22;
    indices[1224] = 8'h22;  indices[1225] = 8'h22;  indices[1226] = 8'h22;  indices[1227] = 8'h44;  indices[1228] = 8'h45;  indices[1229] = 8'h14;  indices[1230] = 8'h12;  indices[1231] = 8'h20;
    indices[1232] = 8'h54;  indices[1233] = 8'h42;  indices[1234] = 8'h55;  indices[1235] = 8'h55;  indices[1236] = 8'h77;  indices[1237] = 8'h47;  indices[1238] = 8'h22;  indices[1239] = 8'h01;
    indices[1240] = 8'h10;  indices[1241] = 8'h11;  indices[1242] = 8'h01;  indices[1243] = 8'h43;  indices[1244] = 8'h44;  indices[1245] = 8'h33;  indices[1246] = 8'h43;  indices[1247] = 8'h76;
    indices[1248] = 8'hbd;  indices[1249] = 8'hbb;  indices[1250] = 8'hbb;  indices[1251] = 8'haa;  indices[1252] = 8'haa;  indices[1253] = 8'haa;  indices[1254] = 8'h6a;  indices[1255] = 8'h22;
    indices[1256] = 8'h22;  indices[1257] = 8'h25;  indices[1258] = 8'h42;  indices[1259] = 8'h54;  indices[1260] = 8'h44;  indices[1261] = 8'h14;  indices[1262] = 8'h01;  indices[1263] = 8'h20;
    indices[1264] = 8'h44;  indices[1265] = 8'h12;  indices[1266] = 8'h52;  indices[1267] = 8'h55;  indices[1268] = 8'h55;  indices[1269] = 8'h25;  indices[1270] = 8'h42;  indices[1271] = 8'h77;
    indices[1272] = 8'h36;  indices[1273] = 8'h01;  indices[1274] = 8'h10;  indices[1275] = 8'h11;  indices[1276] = 8'h33;  indices[1277] = 8'h33;  indices[1278] = 8'h44;  indices[1279] = 8'h96;
    indices[1280] = 8'hbe;  indices[1281] = 8'hbb;  indices[1282] = 8'hbb;  indices[1283] = 8'haa;  indices[1284] = 8'haa;  indices[1285] = 8'haa;  indices[1286] = 8'h7a;  indices[1287] = 8'h56;
    indices[1288] = 8'h24;  indices[1289] = 8'h25;  indices[1290] = 8'h52;  indices[1291] = 8'h45;  indices[1292] = 8'h44;  indices[1293] = 8'h22;  indices[1294] = 8'h22;  indices[1295] = 8'h22;
    indices[1296] = 8'h44;  indices[1297] = 8'h44;  indices[1298] = 8'h52;  indices[1299] = 8'h55;  indices[1300] = 8'h54;  indices[1301] = 8'h45;  indices[1302] = 8'h62;  indices[1303] = 8'h77;
    indices[1304] = 8'h77;  indices[1305] = 8'h77;  indices[1306] = 8'h36;  indices[1307] = 8'h01;  indices[1308] = 8'h10;  indices[1309] = 8'h11;  indices[1310] = 8'h33;  indices[1311] = 8'hd6;
    indices[1312] = 8'hbf;  indices[1313] = 8'hbb;  indices[1314] = 8'hbb;  indices[1315] = 8'haa;  indices[1316] = 8'haa;  indices[1317] = 8'haa;  indices[1318] = 8'haa;  indices[1319] = 8'h87;
    indices[1320] = 8'h22;  indices[1321] = 8'h25;  indices[1322] = 8'h54;  indices[1323] = 8'h45;  indices[1324] = 8'h24;  indices[1325] = 8'h22;  indices[1326] = 8'h42;  indices[1327] = 8'h22;
    indices[1328] = 8'h44;  indices[1329] = 8'h55;  indices[1330] = 8'h55;  indices[1331] = 8'h55;  indices[1332] = 8'h44;  indices[1333] = 8'h44;  indices[1334] = 8'h72;  indices[1335] = 8'h77;
    indices[1336] = 8'h77;  indices[1337] = 8'h77;  indices[1338] = 8'h78;  indices[1339] = 8'h77;  indices[1340] = 8'h36;  indices[1341] = 8'h01;  indices[1342] = 8'h10;  indices[1343] = 8'hd6;
    indices[1344] = 8'hcf;  indices[1345] = 8'hbb;  indices[1346] = 8'hbb;  indices[1347] = 8'haa;  indices[1348] = 8'haa;  indices[1349] = 8'haa;  indices[1350] = 8'haa;  indices[1351] = 8'h89;
    indices[1352] = 8'h22;  indices[1353] = 8'h25;  indices[1354] = 8'h54;  indices[1355] = 8'h45;  indices[1356] = 8'h22;  indices[1357] = 8'h42;  indices[1358] = 8'h54;  indices[1359] = 8'h55;
    indices[1360] = 8'h75;  indices[1361] = 8'h88;  indices[1362] = 8'h58;  indices[1363] = 8'h55;  indices[1364] = 8'h45;  indices[1365] = 8'h24;  indices[1366] = 8'h92;  indices[1367] = 8'h79;
    indices[1368] = 8'h77;  indices[1369] = 8'h77;  indices[1370] = 8'h99;  indices[1371] = 8'h99;  indices[1372] = 8'h99;  indices[1373] = 8'h79;  indices[1374] = 8'h36;  indices[1375] = 8'hd7;
    indices[1376] = 8'hef;  indices[1377] = 8'hbb;  indices[1378] = 8'hbb;  indices[1379] = 8'hab;  indices[1380] = 8'haa;  indices[1381] = 8'haa;  indices[1382] = 8'haa;  indices[1383] = 8'h79;
    indices[1384] = 8'h21;  indices[1385] = 8'h24;  indices[1386] = 8'h54;  indices[1387] = 8'h88;  indices[1388] = 8'h24;  indices[1389] = 8'h22;  indices[1390] = 8'h54;  indices[1391] = 8'h55;
    indices[1392] = 8'h85;  indices[1393] = 8'h88;  indices[1394] = 8'h88;  indices[1395] = 8'h57;  indices[1396] = 8'h45;  indices[1397] = 8'h42;  indices[1398] = 8'h93;  indices[1399] = 8'h99;
    indices[1400] = 8'h99;  indices[1401] = 8'h79;  indices[1402] = 8'h77;  indices[1403] = 8'h97;  indices[1404] = 8'h99;  indices[1405] = 8'h99;  indices[1406] = 8'h99;  indices[1407] = 8'hfe;
    indices[1408] = 8'hff;  indices[1409] = 8'hbc;  indices[1410] = 8'hbb;  indices[1411] = 8'hbb;  indices[1412] = 8'hab;  indices[1413] = 8'haa;  indices[1414] = 8'haa;  indices[1415] = 8'h69;
    indices[1416] = 8'h22;  indices[1417] = 8'h22;  indices[1418] = 8'h52;  indices[1419] = 8'h85;  indices[1420] = 8'h7b;  indices[1421] = 8'h24;  indices[1422] = 8'h44;  indices[1423] = 8'h54;
    indices[1424] = 8'h55;  indices[1425] = 8'h85;  indices[1426] = 8'h78;  indices[1427] = 8'h55;  indices[1428] = 8'h45;  indices[1429] = 8'h44;  indices[1430] = 8'h96;  indices[1431] = 8'h99;
    indices[1432] = 8'h99;  indices[1433] = 8'h99;  indices[1434] = 8'h99;  indices[1435] = 8'h79;  indices[1436] = 8'h77;  indices[1437] = 8'h99;  indices[1438] = 8'hb9;  indices[1439] = 8'hff;
    indices[1440] = 8'hff;  indices[1441] = 8'hbd;  indices[1442] = 8'hbb;  indices[1443] = 8'hbb;  indices[1444] = 8'hbb;  indices[1445] = 8'haa;  indices[1446] = 8'h9a;  indices[1447] = 8'h37;
    indices[1448] = 8'h21;  indices[1449] = 8'h22;  indices[1450] = 8'h42;  indices[1451] = 8'h55;  indices[1452] = 8'h85;  indices[1453] = 8'h14;  indices[1454] = 8'h22;  indices[1455] = 8'h54;
    indices[1456] = 8'h55;  indices[1457] = 8'h55;  indices[1458] = 8'h88;  indices[1459] = 8'h58;  indices[1460] = 8'h45;  indices[1461] = 8'h25;  indices[1462] = 8'h99;  indices[1463] = 8'h99;
    indices[1464] = 8'h99;  indices[1465] = 8'h99;  indices[1466] = 8'h99;  indices[1467] = 8'h99;  indices[1468] = 8'h99;  indices[1469] = 8'h79;  indices[1470] = 8'hc7;  indices[1471] = 8'hef;
    indices[1472] = 8'hff;  indices[1473] = 8'hcf;  indices[1474] = 8'hbb;  indices[1475] = 8'hbb;  indices[1476] = 8'h6a;  indices[1477] = 8'h63;  indices[1478] = 8'h33;  indices[1479] = 8'h26;
    indices[1480] = 8'h21;  indices[1481] = 8'h22;  indices[1482] = 8'h42;  indices[1483] = 8'h44;  indices[1484] = 8'h42;  indices[1485] = 8'h47;  indices[1486] = 8'h12;  indices[1487] = 8'h42;
    indices[1488] = 8'h44;  indices[1489] = 8'h84;  indices[1490] = 8'h8c;  indices[1491] = 8'h88;  indices[1492] = 8'h45;  indices[1493] = 8'h65;  indices[1494] = 8'h99;  indices[1495] = 8'h99;
    indices[1496] = 8'h99;  indices[1497] = 8'h99;  indices[1498] = 8'h99;  indices[1499] = 8'h99;  indices[1500] = 8'h99;  indices[1501] = 8'h99;  indices[1502] = 8'hfa;  indices[1503] = 8'hdd;
    indices[1504] = 8'hff;  indices[1505] = 8'hdf;  indices[1506] = 8'hcc;  indices[1507] = 8'hbc;  indices[1508] = 8'h36;  indices[1509] = 8'h11;  indices[1510] = 8'h77;  indices[1511] = 8'h27;
    indices[1512] = 8'h21;  indices[1513] = 8'h22;  indices[1514] = 8'h22;  indices[1515] = 8'h44;  indices[1516] = 8'h22;  indices[1517] = 8'h42;  indices[1518] = 8'h55;  indices[1519] = 8'h55;
    indices[1520] = 8'h55;  indices[1521] = 8'ha8;  indices[1522] = 8'h88;  indices[1523] = 8'h88;  indices[1524] = 8'h55;  indices[1525] = 8'h94;  indices[1526] = 8'h99;  indices[1527] = 8'h99;
    indices[1528] = 8'h99;  indices[1529] = 8'h99;  indices[1530] = 8'h99;  indices[1531] = 8'h99;  indices[1532] = 8'h99;  indices[1533] = 8'h99;  indices[1534] = 8'hec;  indices[1535] = 8'hfe;
    indices[1536] = 8'hee;  indices[1537] = 8'hfe;  indices[1538] = 8'h7a;  indices[1539] = 8'h36;  indices[1540] = 8'h33;  indices[1541] = 8'h63;  indices[1542] = 8'hba;  indices[1543] = 8'h25;
    indices[1544] = 8'h21;  indices[1545] = 8'h22;  indices[1546] = 8'h22;  indices[1547] = 8'h22;  indices[1548] = 8'h12;  indices[1549] = 8'h22;  indices[1550] = 8'h55;  indices[1551] = 8'h55;
    indices[1552] = 8'h85;  indices[1553] = 8'h88;  indices[1554] = 8'h58;  indices[1555] = 8'h58;  indices[1556] = 8'h44;  indices[1557] = 8'ha7;  indices[1558] = 8'h99;  indices[1559] = 8'h99;
    indices[1560] = 8'h99;  indices[1561] = 8'h99;  indices[1562] = 8'h99;  indices[1563] = 8'h99;  indices[1564] = 8'h99;  indices[1565] = 8'hb9;  indices[1566] = 8'hee;  indices[1567] = 8'hee;
    indices[1568] = 8'hdf;  indices[1569] = 8'hff;  indices[1570] = 8'h3d;  indices[1571] = 8'h31;  indices[1572] = 8'h16;  indices[1573] = 8'h96;  indices[1574] = 8'hcb;  indices[1575] = 8'h24;
    indices[1576] = 8'h21;  indices[1577] = 8'h22;  indices[1578] = 8'h22;  indices[1579] = 8'h22;  indices[1580] = 8'h22;  indices[1581] = 8'h22;  indices[1582] = 8'h54;  indices[1583] = 8'h55;
    indices[1584] = 8'h85;  indices[1585] = 8'h55;  indices[1586] = 8'h85;  indices[1587] = 8'h58;  indices[1588] = 8'h72;  indices[1589] = 8'haa;  indices[1590] = 8'h9a;  indices[1591] = 8'h99;
    indices[1592] = 8'h99;  indices[1593] = 8'h99;  indices[1594] = 8'h99;  indices[1595] = 8'h99;  indices[1596] = 8'h99;  indices[1597] = 8'hfa;  indices[1598] = 8'hfe;  indices[1599] = 8'hee;
    indices[1600] = 8'hdf;  indices[1601] = 8'hdd;  indices[1602] = 8'haf;  indices[1603] = 8'h76;  indices[1604] = 8'h39;  indices[1605] = 8'h96;  indices[1606] = 8'hdd;  indices[1607] = 8'h22;
    indices[1608] = 8'h22;  indices[1609] = 8'h22;  indices[1610] = 8'h22;  indices[1611] = 8'h22;  indices[1612] = 8'h22;  indices[1613] = 8'h42;  indices[1614] = 8'h44;  indices[1615] = 8'h55;
    indices[1616] = 8'h55;  indices[1617] = 8'h55;  indices[1618] = 8'h85;  indices[1619] = 8'h48;  indices[1620] = 8'ha4;  indices[1621] = 8'haa;  indices[1622] = 8'haa;  indices[1623] = 8'h99;
    indices[1624] = 8'h99;  indices[1625] = 8'h99;  indices[1626] = 8'h99;  indices[1627] = 8'h99;  indices[1628] = 8'h99;  indices[1629] = 8'hfc;  indices[1630] = 8'hee;  indices[1631] = 8'hff;
    indices[1632] = 8'hff;  indices[1633] = 8'hdf;  indices[1634] = 8'hfd;  indices[1635] = 8'h79;  indices[1636] = 8'h69;  indices[1637] = 8'ha6;  indices[1638] = 8'hdd;  indices[1639] = 8'h22;
    indices[1640] = 8'h22;  indices[1641] = 8'h22;  indices[1642] = 8'h22;  indices[1643] = 8'h22;  indices[1644] = 8'h22;  indices[1645] = 8'h42;  indices[1646] = 8'h55;  indices[1647] = 8'h55;
    indices[1648] = 8'h55;  indices[1649] = 8'h45;  indices[1650] = 8'h55;  indices[1651] = 8'h44;  indices[1652] = 8'haa;  indices[1653] = 8'haa;  indices[1654] = 8'haa;  indices[1655] = 8'h9a;
    indices[1656] = 8'h99;  indices[1657] = 8'h99;  indices[1658] = 8'h99;  indices[1659] = 8'h99;  indices[1660] = 8'hb9;  indices[1661] = 8'hee;  indices[1662] = 8'hfe;  indices[1663] = 8'hfe;
    indices[1664] = 8'hdd;  indices[1665] = 8'hfd;  indices[1666] = 8'hdf;  indices[1667] = 8'h9d;  indices[1668] = 8'h79;  indices[1669] = 8'ha6;  indices[1670] = 8'hdd;  indices[1671] = 8'h24;
    indices[1672] = 8'h22;  indices[1673] = 8'h44;  indices[1674] = 8'h24;  indices[1675] = 8'h21;  indices[1676] = 8'h44;  indices[1677] = 8'h44;  indices[1678] = 8'h55;  indices[1679] = 8'h85;
    indices[1680] = 8'h55;  indices[1681] = 8'h45;  indices[1682] = 8'h44;  indices[1683] = 8'h82;  indices[1684] = 8'hab;  indices[1685] = 8'haa;  indices[1686] = 8'haa;  indices[1687] = 8'haa;
    indices[1688] = 8'haa;  indices[1689] = 8'h99;  indices[1690] = 8'h99;  indices[1691] = 8'h9a;  indices[1692] = 8'hfb;  indices[1693] = 8'hee;  indices[1694] = 8'hef;  indices[1695] = 8'hee;
    indices[1696] = 8'hfd;  indices[1697] = 8'hfd;  indices[1698] = 8'hfd;  indices[1699] = 8'hcf;  indices[1700] = 8'h79;  indices[1701] = 8'ha7;  indices[1702] = 8'hde;  indices[1703] = 8'h24;
    indices[1704] = 8'h22;  indices[1705] = 8'h44;  indices[1706] = 8'h44;  indices[1707] = 8'h22;  indices[1708] = 8'h42;  indices[1709] = 8'h44;  indices[1710] = 8'h55;  indices[1711] = 8'h85;
    indices[1712] = 8'h55;  indices[1713] = 8'h45;  indices[1714] = 8'h24;  indices[1715] = 8'hb6;  indices[1716] = 8'hab;  indices[1717] = 8'haa;  indices[1718] = 8'haa;  indices[1719] = 8'haa;
    indices[1720] = 8'haa;  indices[1721] = 8'h99;  indices[1722] = 8'h99;  indices[1723] = 8'hb9;  indices[1724] = 8'hfc;  indices[1725] = 8'hff;  indices[1726] = 8'hfe;  indices[1727] = 8'hee;
    indices[1728] = 8'hef;  indices[1729] = 8'hed;  indices[1730] = 8'hed;  indices[1731] = 8'hfd;  indices[1732] = 8'h9c;  indices[1733] = 8'ha7;  indices[1734] = 8'hdd;  indices[1735] = 8'h48;
    indices[1736] = 8'h42;  indices[1737] = 8'h54;  indices[1738] = 8'h45;  indices[1739] = 8'h24;  indices[1740] = 8'h42;  indices[1741] = 8'h54;  indices[1742] = 8'h55;  indices[1743] = 8'h55;
    indices[1744] = 8'h55;  indices[1745] = 8'h44;  indices[1746] = 8'h14;  indices[1747] = 8'ha6;  indices[1748] = 8'hab;  indices[1749] = 8'haa;  indices[1750] = 8'haa;  indices[1751] = 8'haa;
    indices[1752] = 8'haa;  indices[1753] = 8'h99;  indices[1754] = 8'h99;  indices[1755] = 8'hcb;  indices[1756] = 8'hee;  indices[1757] = 8'hef;  indices[1758] = 8'hff;  indices[1759] = 8'hfe;
    indices[1760] = 8'hff;  indices[1761] = 8'hef;  indices[1762] = 8'hff;  indices[1763] = 8'hff;  indices[1764] = 8'hcd;  indices[1765] = 8'h99;  indices[1766] = 8'hdd;  indices[1767] = 8'h4b;
    indices[1768] = 8'h44;  indices[1769] = 8'h55;  indices[1770] = 8'h55;  indices[1771] = 8'h45;  indices[1772] = 8'h42;  indices[1773] = 8'h54;  indices[1774] = 8'h55;  indices[1775] = 8'h85;
    indices[1776] = 8'h88;  indices[1777] = 8'h55;  indices[1778] = 8'h03;  indices[1779] = 8'h10;  indices[1780] = 8'ha6;  indices[1781] = 8'haa;  indices[1782] = 8'haa;  indices[1783] = 8'haa;
    indices[1784] = 8'haa;  indices[1785] = 8'haa;  indices[1786] = 8'hb9;  indices[1787] = 8'hec;  indices[1788] = 8'hff;  indices[1789] = 8'hef;  indices[1790] = 8'hef;  indices[1791] = 8'hef;
    indices[1792] = 8'hfd;  indices[1793] = 8'hfd;  indices[1794] = 8'hdf;  indices[1795] = 8'hef;  indices[1796] = 8'hdd;  indices[1797] = 8'hac;  indices[1798] = 8'hed;  indices[1799] = 8'h7d;
    indices[1800] = 8'h45;  indices[1801] = 8'h55;  indices[1802] = 8'h85;  indices[1803] = 8'h55;  indices[1804] = 8'h44;  indices[1805] = 8'h55;  indices[1806] = 8'h85;  indices[1807] = 8'h88;
    indices[1808] = 8'h88;  indices[1809] = 8'h68;  indices[1810] = 8'h01;  indices[1811] = 8'h00;  indices[1812] = 8'h30;  indices[1813] = 8'ha9;  indices[1814] = 8'haa;  indices[1815] = 8'haa;
    indices[1816] = 8'haa;  indices[1817] = 8'haa;  indices[1818] = 8'hdb;  indices[1819] = 8'hff;  indices[1820] = 8'hef;  indices[1821] = 8'hfe;  indices[1822] = 8'hff;  indices[1823] = 8'hfe;
    indices[1824] = 8'hdf;  indices[1825] = 8'hdf;  indices[1826] = 8'hef;  indices[1827] = 8'hfe;  indices[1828] = 8'hdf;  indices[1829] = 8'hef;  indices[1830] = 8'hed;  indices[1831] = 8'h8d;
    indices[1832] = 8'h55;  indices[1833] = 8'h55;  indices[1834] = 8'h85;  indices[1835] = 8'h58;  indices[1836] = 8'h45;  indices[1837] = 8'h55;  indices[1838] = 8'h85;  indices[1839] = 8'h88;
    indices[1840] = 8'h88;  indices[1841] = 8'h37;  indices[1842] = 8'h00;  indices[1843] = 8'h10;  indices[1844] = 8'h01;  indices[1845] = 8'h61;  indices[1846] = 8'haa;  indices[1847] = 8'haa;
    indices[1848] = 8'haa;  indices[1849] = 8'hba;  indices[1850] = 8'hee;  indices[1851] = 8'hfe;  indices[1852] = 8'hee;  indices[1853] = 8'hee;  indices[1854] = 8'hef;  indices[1855] = 8'hff;
    indices[1856] = 8'hdd;  indices[1857] = 8'hfd;  indices[1858] = 8'hee;  indices[1859] = 8'hff;  indices[1860] = 8'hdf;  indices[1861] = 8'hed;  indices[1862] = 8'hff;  indices[1863] = 8'had;
    indices[1864] = 8'h57;  indices[1865] = 8'h55;  indices[1866] = 8'h55;  indices[1867] = 8'h55;  indices[1868] = 8'h55;  indices[1869] = 8'h55;  indices[1870] = 8'h55;  indices[1871] = 8'h55;
    indices[1872] = 8'h45;  indices[1873] = 8'h32;  indices[1874] = 8'h00;  indices[1875] = 8'h01;  indices[1876] = 8'h11;  indices[1877] = 8'h00;  indices[1878] = 8'h71;  indices[1879] = 8'haa;
    indices[1880] = 8'hba;  indices[1881] = 8'hfc;  indices[1882] = 8'hff;  indices[1883] = 8'hee;  indices[1884] = 8'hef;  indices[1885] = 8'hff;  indices[1886] = 8'hfe;  indices[1887] = 8'hee;
    indices[1888] = 8'hdf;  indices[1889] = 8'hdf;  indices[1890] = 8'hff;  indices[1891] = 8'hef;  indices[1892] = 8'hff;  indices[1893] = 8'hff;  indices[1894] = 8'hff;  indices[1895] = 8'hcf;
    indices[1896] = 8'h58;  indices[1897] = 8'h55;  indices[1898] = 8'h55;  indices[1899] = 8'h55;  indices[1900] = 8'h55;  indices[1901] = 8'h55;  indices[1902] = 8'h55;  indices[1903] = 8'h45;
    indices[1904] = 8'h22;  indices[1905] = 8'h31;  indices[1906] = 8'h00;  indices[1907] = 8'h01;  indices[1908] = 8'h31;  indices[1909] = 8'h01;  indices[1910] = 8'h00;  indices[1911] = 8'ha3;
    indices[1912] = 8'heb;  indices[1913] = 8'hfe;  indices[1914] = 8'hff;  indices[1915] = 8'hef;  indices[1916] = 8'hff;  indices[1917] = 8'hee;  indices[1918] = 8'hef;  indices[1919] = 8'hff;
    indices[1920] = 8'hdf;  indices[1921] = 8'hff;  indices[1922] = 8'hef;  indices[1923] = 8'hfe;  indices[1924] = 8'hff;  indices[1925] = 8'hdf;  indices[1926] = 8'hff;  indices[1927] = 8'hff;
    indices[1928] = 8'hac;  indices[1929] = 8'h55;  indices[1930] = 8'h55;  indices[1931] = 8'h55;  indices[1932] = 8'h55;  indices[1933] = 8'h55;  indices[1934] = 8'h55;  indices[1935] = 8'h25;
    indices[1936] = 8'h22;  indices[1937] = 8'h63;  indices[1938] = 8'h00;  indices[1939] = 8'h11;  indices[1940] = 8'h11;  indices[1941] = 8'h11;  indices[1942] = 8'h00;  indices[1943] = 8'ha3;
    indices[1944] = 8'hff;  indices[1945] = 8'hff;  indices[1946] = 8'hff;  indices[1947] = 8'hff;  indices[1948] = 8'hef;  indices[1949] = 8'hee;  indices[1950] = 8'hef;  indices[1951] = 8'hdf;
    indices[1952] = 8'hfd;  indices[1953] = 8'hfd;  indices[1954] = 8'hff;  indices[1955] = 8'hef;  indices[1956] = 8'hfe;  indices[1957] = 8'hff;  indices[1958] = 8'hff;  indices[1959] = 8'hff;
    indices[1960] = 8'hdf;  indices[1961] = 8'h8c;  indices[1962] = 8'h45;  indices[1963] = 8'h55;  indices[1964] = 8'h55;  indices[1965] = 8'h55;  indices[1966] = 8'h55;  indices[1967] = 8'h24;
    indices[1968] = 8'h12;  indices[1969] = 8'h96;  indices[1970] = 8'h00;  indices[1971] = 8'h11;  indices[1972] = 8'h11;  indices[1973] = 8'h31;  indices[1974] = 8'ha6;  indices[1975] = 8'hfd;
    indices[1976] = 8'hff;  indices[1977] = 8'hff;  indices[1978] = 8'hff;  indices[1979] = 8'hff;  indices[1980] = 8'hff;  indices[1981] = 8'hff;  indices[1982] = 8'hfe;  indices[1983] = 8'hde;
    indices[1984] = 8'hfd;  indices[1985] = 8'hfd;  indices[1986] = 8'hff;  indices[1987] = 8'hff;  indices[1988] = 8'hff;  indices[1989] = 8'hdf;  indices[1990] = 8'hfe;  indices[1991] = 8'hff;
    indices[1992] = 8'hff;  indices[1993] = 8'hdd;  indices[1994] = 8'h8f;  indices[1995] = 8'h55;  indices[1996] = 8'h55;  indices[1997] = 8'h45;  indices[1998] = 8'h44;  indices[1999] = 8'h22;
    indices[2000] = 8'h11;  indices[2001] = 8'h6b;  indices[2002] = 8'h01;  indices[2003] = 8'h00;  indices[2004] = 8'h31;  indices[2005] = 8'hd6;  indices[2006] = 8'hdf;  indices[2007] = 8'hdf;
    indices[2008] = 8'hdf;  indices[2009] = 8'hff;  indices[2010] = 8'hff;  indices[2011] = 8'hff;  indices[2012] = 8'hff;  indices[2013] = 8'hff;  indices[2014] = 8'hef;  indices[2015] = 8'hff;
    indices[2016] = 8'hfd;  indices[2017] = 8'hdf;  indices[2018] = 8'hdf;  indices[2019] = 8'hff;  indices[2020] = 8'hed;  indices[2021] = 8'hfe;  indices[2022] = 8'hfe;  indices[2023] = 8'hff;
    indices[2024] = 8'hef;  indices[2025] = 8'hfd;  indices[2026] = 8'hfd;  indices[2027] = 8'hff;  indices[2028] = 8'h8b;  indices[2029] = 8'h58;  indices[2030] = 8'h45;  indices[2031] = 8'h14;
    indices[2032] = 8'h60;  indices[2033] = 8'h66;  indices[2034] = 8'h33;  indices[2035] = 8'h96;  indices[2036] = 8'hdd;  indices[2037] = 8'hdd;  indices[2038] = 8'hdd;  indices[2039] = 8'hdd;
    indices[2040] = 8'hff;  indices[2041] = 8'hff;  indices[2042] = 8'hff;  indices[2043] = 8'hff;  indices[2044] = 8'hff;  indices[2045] = 8'hff;  indices[2046] = 8'hff;  indices[2047] = 8'hfe;
  end

  // 4bpp lookup: low nibble = even x, high nibble = odd x
  wire [3:0] idx = x[0] ? indices[{y, x[5:1]}][7:4]
                        : indices[{y, x[5:1]}][3:0];
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
