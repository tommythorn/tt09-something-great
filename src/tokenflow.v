/*
 * NCL Async Multiplier -- Tommy Thorn 20240913
 *
 * This is intended to be an NCL version on tt08-maxbw for a
 * comparison.
 *
 * Note, NCL encodes the REQ in the data itself and that can
 * be done in many ways.  By default I assume all data is
 * dual-rail encoded, but 1-of-N might be better in some cases.
 *
 * For convenience, the n-bit value DATA(v) is dual rail encoded as
 * {v,~v} (and NULL of course being just {0,0}.
 */

/* verilator lint_off LATCH */
`default_nettype none

`include "tokenflow.h"

// Muller C element
`ifdef SIM

module cgate#(parameter init = 1'd0)
   (input wire reset, input wire a, input wire b, output reg q = init);
   always @*
     if (reset)
       q = init;
     else if (a == b)
       q = #3 b;
endmodule

`else

module cgate#(parameter init = 1'd0)
   (input wire reset, input wire a, input wire b, output wire q);

   /*
    The benefit of using a maj gate for this is that the critical
    path is always within a standard cell and not subject the routing
    adventures.  It's also (likely) denser than random logic, however
    a dedicated C gate would be a bit smaller still.

    I chose C as the feedback path as it appears to be the shortest
    path to X.
     */

   sky130_fd_sc_hd__maj3_2
     maj(.X(q), .A(reset ? init : a), .B(reset ? init : b), .C(q));
endmodule

`endif

module comp_const#(parameter w = 32,
                   parameter k = 0)
   (input reset, inout wire `chan channel);

   assign channel`data = channel`ack ? 0 : {k,~k};
endmodule

module comp_sink#(parameter w = 32,
                  parameter id = "??")
   (input reset, inout wire `chan channel);

   wire [w-1:0] merged = channel`data0 | channel`data1;


   cgate cg(reset, |merged, &merged, channel`ack);

`ifdef SIM
   always @(posedge channel`ack)
     if (!reset)
       $display("%05d  %-6s: Sunk %1d (ACK %d)", $time, id, channel`data1, channel`ack);
`endif
endmodule

module comp_spy#(parameter id = "??",
                 parameter w = 32)
   (inout `chan x);

   reg `chan prev = 0;
   wire complete = &(x`data0 | x`data1);
   wire [1:0] ctl = {complete, x`ack};

   always @* if (x != prev) begin
     $display("%05d  %-6s: %s %1d", $time, id,
              ctl == 0 ? "  " :
              ctl == 2 ? "R " :
              ctl == 3 ? "RA" :
              /*     == 1*/ " A",
              x`data1);
      prev = x;
   end
endmodule

module comp_wire#(parameter w = 1)
   (input reset,
    inout `chan x,
    inout `chan y);

   assign y[2*w:1] = x[2*w:1];
   assign x[0] = y[0];
endmodule

module comp_elem#(parameter w = 1)
   (input reset,
    inout `chan x,
    inout `chan y);

   genvar i;
   generate
      for (i = 0; i < 2*w; i = i + 1)
         cgate inst(reset, x[i+1], !y`ack, y[i+1]);
   endgenerate
   cgate cg(reset, |(y`data0 | y`data1), &(y`data0 | y`data1), x`ack);
endmodule

module comp_elemV#(parameter w = 1,
                   parameter data = 0)
   (input reset,
    inout `chan x,
    inout `chan y);

   // Verilog sucks and I can't do
   // cgate#(init = ((~data >> i) & 1)) inst0(reset, x[i+1], !y`ack, y[i+1]);
   // but instead have to inverse the cgate
   wire [w-1:0] k = data;

   // XXX I think there must exist a better way to do this
   genvar i;
   generate
      for (i = 0; i < w; i = i + 1) begin
         wire t;
         cgate inst0(reset, !k[i] ^ x[i+1], !k[i] ^ !y`ack, t);
         assign y[i+1] = !k[i] ^ t;
      end

      for (i = 0; i < w; i = i + 1) begin
         wire tt;
         cgate inst1(reset, k[i] ^ x[w+i+1], k[i] ^ !y`ack, tt);
         assign y[w+i+1] = k[i] ^ tt;
      end
   endgenerate
   cgate cg(reset, |(y`data0 | y`data1), &(y`data0 | y`data1), x`ack);
endmodule

module comp_fork#(parameter w = 32)
   (input reset,
    inout `chan x,
    inout `chan y, inout `chan z);
   assign y`data0 = x`data0;
   assign z`data0 = x`data0;
   assign y`data1 = x`data1;
   assign z`data1 = x`data1;
   cgate cg(reset, y`ack, z`ack, x`ack);
endmodule

module comp_join#(parameter w = 32, parameter wy = 32)
   (input reset,
    inout `chan x, inout `chan y,
    inout [4*w:0] z);
   assign x`ack = z`ack;
   assign y`ack = z`ack;
   assign z`data0 = x`data0;
   assign z`data1 = x`data1;
   assign z[4*w:2*w+1] = {x`data0, x`data0};
endmodule

module comp_merge#(parameter w = 32)
   (input reset,
    inout `chan x, inout `chan y,
    inout `chan z);

   genvar i;
   generate
      for (i = 0; i < 2*w; i = i + 1)
        cgate inst(reset, x[i+1], y[i+1], z[i+1]);
   endgenerate
   cgate cgy(reset, |(y`data0 | y`data1), &(y`data0 | y`data1), y`ack);
   cgate cgx(reset, |(x`data0 | x`data1), &(x`data0 | x`data1), x`ack);
endmodule

module comp_mux#(parameter w = 32)
   (input reset,
    inout [2:0] ctl, inout `chan x, inout `chan y,
    inout `chan z);

   wire `chan gatedx, gatedy;

   genvar i;
   generate
      for (i = 0; i < 2*w; i = i + 1) begin
         cgate instx(reset, ctl[2] /* ctl.f */, x[i+1], gatedx[i+1]);
         cgate insty(reset, ctl[1] /* ctl.t */, y[i+1], gatedy[i+1]);
         assign z[i] = gatedx[i] | gatedy[i];
      end
   endgenerate
   cgate cgy(reset, |(y`data0 | y`data1), &(y`data0 | y`data1), y`ack);
   cgate cgx(reset, |(x`data0 | x`data1), &(x`data0 | x`data1), x`ack);
endmodule

module comp_demux#(parameter w = 32)
   (input reset,
    inout [2:0] ctl, inout `chan x,
    inout `chan y, inout `chan z);

   assign x`ack = y`ack | z`ack;
   assign ctl`ack = x`ack;

   genvar i;
   generate
      for (i = 0; i < 2*w; i = i + 1) begin
         cgate insty(reset, ctl[2] /* ctl.f */, x[i+1], y[i+1]);
         cgate instz(reset, ctl[1] /* ctl.t */, x[i+1], z[i+1]);
      end
   endgenerate
endmodule

module ncl_fa
  (input [1:0] a,
   input [1:0] b,
   input [1:0] c,
   output [1:0] s,
   output [1:0] d);

   /* XXX This is extremely unoptimized at this point, should at least
      use gen/kill */

   wire [7:0]   x;
   genvar i;
   generate
      for (i = 0; i < 8; i = i + 1) begin
         wire t;
         cgate cg1(1'd0, a[i & 1], b[i/2 & 1], t);
         cgate cg2(1'd0, t, c[i/4 & 1], x[i]);
      end
   endgenerate

   assign s[1] = |(x &  8'b10010110);  // The four cases that gives a 1
   assign s[0] = |(x & ~8'b10010110);
   assign d[1] = |(x &  8'b11101000);  // The four cases that gives a carry-out
   assign d[0] = |(x & ~8'b11101000);
endmodule


// XXX Ok, this works now, but is crazy slow: the forward propagation
// is expected, but the NULL wave is equally slow.  This could be
// fixed of course with input latches like in comp_elem.  The price of
// timing insensitity is really crazy.
module comp_add#(parameter w = 32)
   (input _reset,
    inout `chan x,
    inout `chan y,
    inout `chan z);

   // This will look like a join + computation
   assign x`ack = z`ack;
   assign y`ack = z`ack;

   wire [w:0] carry0, carry1;
   assign carry0[0] = !z`ack; // No carry-in
   assign carry1[0] = 1'd 0;

   /* XXX This is very unoptimized at this point */
   genvar i;
   generate
      for (i = 1; i < w+1; i = i + 1) begin
         ncl_fa fa({carry1[i-1],carry0[i-1]}, {x[w+i],x[i]}, {y[w+i], y[i]},
                   {z[w+i],z[i]}, {carry1[i],carry0[i]});
      end
   endgenerate
endmodule

module tb;
   parameter w = 32;
   reg       reset = 1;

   wire `chan k42;
   wire `chan c0, c1, c2, c3, c4, c5;

   comp_const#(.w(w), .k(42))          ik42(reset, k42);
   comp_elem#(.w(w))                   i2(reset, c0, c1);
   comp_add#(.w(w))                    i3(reset, k42, c1, c2);
   comp_elem#(.w(w))                   i4(reset, c2, c3);
   comp_elemV#(.w(w), .data(555))      i5(reset, c3, c4);
   comp_fork#(.w(w))                   i6(reset, c4, c5, c0);
   comp_sink#(.w(w), .id("c5"))        isink(reset, c5);


   initial begin
      $display("tb test starting");
      $dumpfile("tokenflow.vcd");
      $dumpvars();

      #20 reset = 0;

      #1000 $finish;
   end
endmodule

`ifdef testing_ncl_fa
module tb;
   wire [1:0] a, b, c;
   wire [1:0] s, d;

   ncl_fa fa(a, b, c, s, d);

   reg [3:0]  x = 0;

   assign a = x[0] ? {x[1], !x[1]} : 0;
   assign b = x[0] ? {x[2], !x[2]} : 0;
   assign c = x[0] ? {x[3], !x[3]} : 0;

   always @*
     if (0 != a && 0 != b && 0 != c && 0 != s && 0 != d)
       $display(" >> %d + %d + %d = %d", a[1], b[1], c[1], {d[1],s[1]});

   always #10 x <= x + 1;

   initial begin
      $display$("tokenflow test starting");
      $dumpfile("tokenflow.vcd");
      $dumpvars();
      $monitor("%05d  %d: %d %d %d -> %d %d", $time, x, a, b, c, s, d);

      #1000
      $finish;
   end
endmodule
`endif

`ifdef some_future

module tokenflow#(parameter w = 16)
   (input reset, inout wire `chan ou_ch);

   wire `chan3 in_ch;
   wire `chan3 ou_ch3;

   wire `chan ci0, ci1, ci2, ci3, ci4, counter_ch;

/*
     _______________________________________________________
    v                                                       \
   comp_elemV -> comp_add1 -> comp_elem -> comp_elem -> comp_fork -> in_ch
*/

`ifdef SIM
   comp_spy #("ci0", w) sii0(ci0);
   comp_spy #("ci1", w) sii1(ci1);
   comp_spy #("ci2", w) sii2(ci2);
   comp_spy #("ci3", w) sii3(ci3);
   comp_spy #("ci4", w) sii4(ci4);
   comp_spy #("out", w) sii6(ou_ch);
   comp_spy #("counter", w) sii5(counter_ch);
`endif

   comp_add1 #(w)               ii0(reset, ci0, ci1);
   comp_elem #(w)               ii1(reset, ci1, ci2);
   comp_elem #(.w(w), .data(0)) ii2(reset, ci2, ci3);
   comp_elemV #(.w(w))          ii3(reset, ci3, ci4);
   comp_fork #(w)               ii4(reset, ci4, ci0, counter_ch);

   // Replicate c to (c,c,c)
   assign in_ch`data = counter_ch`data;
   assign in_ch`data1 = counter_ch`data;
   assign in_ch`data2 = counter_ch`data;
   assign in_ch`req = counter_ch`req;
   assign counter_ch`ack = in_ch`ack;

   // Truncate the (a,b,c) triple data down to just c
   assign ou_ch`data = ou_ch3`data;
   assign ou_ch`req = ou_ch3`req;
   assign ou_ch3`ack = ou_ch`ack;

   /*
    * x = 0
    * loop:
    *   x = x + 1
    *   a = b = c = x
    *   while b != 0:
    *     if (b&1) == 1:
    *       c += a
    *     a *= 2
    *     b /= 2
    *     if (b&1) == 1:
    *       c += a
    *     a *= 2
    *     b /= 2
    *   output (c)
    *
    * add1 ci0          -> ci1
    * elem ci1          -> ci2                  w L
    * elem ci2          -> ci3                  w L
    * elemV ci3         -> ci4                  w L
    * fork ci4          -> (ci0, counter_ch)
    *
    * in = (counter, counter, counter)
    *
    * // while b != 0:
    * join in c12       -> c1
    *
    * merge c8 c1       -> c2                   3 C + 1 D
    * elem c2           -> c3                   1 C + 1 D + 3w L
    * loop_cond c3[xx]  -> c4
    * bdemux c4         -> (c5, c9)
    * elem c5           -> c6                   1 C + 1 D + 3w L
    * mulstep c6        -> c7
    * elem c7           -> c54                  1 C + 1 D + 3w L
    * mulstep c54       -> c55
    * elem c55          -> c8                   1 C + 1 D + 3w L
    *
    * fork c9           -> (ou_ch3, c10)        1 C
    * elem c10          -> c11                  1 C + 1 D
    * elemV c11         -> c12                  1 C + 1 D
    *
    * output ou_ch3
    * ===========================================================
    * ~ 15w Latches
    *
    * XXX Note, there are many ways to improve this algorithm; this
    * is just a little async example.
    *
    */

   wire `chan3 c1, c2, c3, c5, c54, c55, c6, c7, c8, c9;

   wire [3*w+2:0] tc4; // Bundled control + data
   wire `ctl c10ctl, c11ctl, c12ctl;

`ifdef SIM
   comp_spy3 #("in", w) si(in_ch);
   comp_spy3 #("out", w) so(ou_ch3);

   comp_spy3 #("c1", w)  s1(c1);
   comp_spy3 #("c2", w)  s2(c2);
   comp_spy3 #("c3", w)  s3(c3);
   comp_spy  #("c4", 3*w+1) s4(tc4);
   comp_spy3 #("c5", w)  s5(c5);
   comp_spy3 #("c6", w)  s6(c6);
   comp_spy3 #("c7", w)  s7(c7);
   comp_spy3 #("c8", w)  s8(c8);
   comp_spy3 #("c9", w)  s9(c9);
   comp_spy0 #("c10ctl") s10(c10ctl);
   comp_spy0 #("c11ctl") s11(c11ctl);
   comp_spy0 #("c12ctl") s12(c12ctl);
`endif

   // while a != 0
   comp_join0 #(.w(3*w))                i1(reset, in_ch, c12ctl, c1);

   comp_merge #(.w(3*w))                i2(reset, c8, c1, c2);
   comp_elem  #(.w(3*w), .delay(3))     i3(reset, c2, c3);
   loop_cond  #(.w(w))                  i4(reset, c3, tc4);
   comp_bdemux#(.w(3*w))                i5(reset, tc4, c9, c5);
   comp_elem  #(.w(3*w), .delay(2*w))   i6(reset, c5, c6);
   mulstep    #(.w(w))                  i7(reset, c6, c7);
   comp_elem  #(.w(3*w), .delay(2*w))   i8(reset, c7, c54);
   mulstep    #(.w(w))                  i77(reset, c54, c55);
   comp_elem  #(.w(3*w), .delay(3))     i78(reset, c55, c8);

   comp_fork0 #(.w(3*w))                i9(reset, c9, ou_ch3, c10ctl);
   comp_elem0                           i10(reset, c10ctl, c11ctl);
   comp_elemV0                          i11(reset, c11ctl, c12ctl);
endmodule
`endif
