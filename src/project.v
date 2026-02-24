/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_gregdavill_vga_demo(
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
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in};

  reg [9:0] counter;

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );
  
  reg [7:0] buffer[5];
  initial begin
    buffer[0] = 8'b11110111;
    buffer[1] = 8'b10001100;
    buffer[2] = 8'b10000000;
    buffer[3] = 8'b10000001;
    buffer[4] = 8'b01111111;
  end

  wire [9:0] moving_x = pix_x + counter;
  wire [9:0] moving_y = pix_y + counter;

  wire [9:0] inv_moving_x = pix_x - counter;
  wire [9:0] inv_moving_y = pix_y - counter;

  assign R = video_active ? {inv_moving_x[6]^moving_x[6], counter[5]+pix_y[5]^(pix_x[5])} : 2'b00;
  assign G = video_active ? {moving_x[6]^moving_y[6], pix_y[5]^(pix_x[5])} : 2'b00;
  assign B = video_active ? {moving_x[6]^inv_moving_y[6], pix_y[5]^(pix_x[5])} : 2'b00;
  
  always @(posedge vsync, negedge rst_n) begin
    if (~rst_n) begin
      counter <= 0;
    end else begin
      counter <= counter + 1;
    end
  end

  // Suppress unused signals warning
  wire _unused_ok_ = &{moving_x, pix_y};

endmodule
