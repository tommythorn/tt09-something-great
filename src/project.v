/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, rst_n, 1'b0};

   wire tdi = ui_in[0];
   wire sample = ui_in[1];
   assign uo_out[0] = tdo;

   parameter XLEN = 64;

   reg            tdo;
   reg            sub;
   reg            ashr;
   reg [ 2:0]     funct3;
   reg            w;
   reg [XLEN-1:0] op1;
   reg [XLEN-1:0] op2;
   reg            _drop;

   reg [XLEN-1:0] result;
   reg            eq;
   reg            lt;
   reg            ltu;

   wire[XLEN-1:0] result_w;
   wire           eq_w;
   wire           lt_w;
   wire           ltu_w;

   alu #(XLEN) (sub, ashr, funct3, w, op1, op2,
                result_w, eq_w, lt_w, ltu_w);

   always @(posedge clk) begin
      {_drop, op2, op1, w, funct3, ashr, sub} <= {op2, op1, w, funct3, ashr, sub, tdi};
      {tdo, ltu, lt, eq, result} <= {ltu, lt, eq, result, 1'b0};
      if (sample)
        {ltu, lt, eq, result} <= {ltu_w, lt_w, eq_w, result_w};
   end
endmodule
