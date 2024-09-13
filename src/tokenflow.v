/* verilator lint_off LATCH */
`default_nettype none

`include "tokenflow.h"

/* This is a sad and wasteful way to slow down a signal */
`ifdef SIM

module min_delay(input wire x, output reg y);
   always @* y = #1 x;
endmodule

`else

module min_delay(input wire x, output wire y);
   // XXX need to characterize this
   (* keep *)sky130_fd_sc_hd__dlygate4sd1_1 d0(.X(y), .A(x));
endmodule

`endif

/* verilator lint_off UNOPTFLAT */
module comp_delay#(parameter delay = 10)
   (input wire reset, input x, output wire y);

   (* keep *) wire [delay:0] inv_chain;
   assign inv_chain[0] = !reset & x;

   genvar i;
   generate
      for (i = 0; i < delay; i = i + 1)
        (* keep *) min_delay min_delay_inst(inv_chain[i], inv_chain[i + 1]);
   endgenerate
   assign y = inv_chain[delay] & x;
endmodule

// Muller C element
`ifdef SIM

module cgate#(parameter init = 1'd0)
   (input wire reset, input wire a, input wire b, output reg q);
   always @*
     if (reset)
       q = init;
     else if (a == b)
       q = #1 b;
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
                   parameter k = 42)
   (input reset, inout wire `chan channel);
   comp_delay #(3) inst(reset, !channel`ack, channel`req);
   assign channel`data = k;
endmodule

module comp_sink#(parameter w = 32,
                  parameter id = "??")
   (input reset, inout wire `chan channel);

   comp_delay #(5) inst(reset, channel`req, channel`ack);

`ifdef SIM
   always @(posedge channel`ack)
     if (!reset) $display("%05d  %-6s: Sunk %1d", $time, id, channel`data);
`endif
endmodule

`ifdef SIM
module check#(parameter id = "??",
              parameter w = 32)
   (inout `chan x);

   reg `chan prev = 0;

   /*
    * Handshake transition checking.  The normal expect sequence:
    * 00 - idle
    * 10 - request (R)
    * 11 - acknowledged request (AR)
    * 01 - trailing acknowledged (A)
    * 00 - idle
    *
    * Anything else is normally an illegal transition
    *
    *
    * [TBD: for simulation we may allow instant consumers
    * (idle <-> RA) and/or instant producers (R <-> A)]
    *
    * Furthermore, data must be held stable while a the receiver is acknowledging (sampling) it
    */
   always @* if (x != prev) begin
      if (x`ctl != prev`ctl)
        case (prev`ctl)
          0: if (x`ctl == 3)      $display("%05d  %-6s: Violation!!  Idle 00 -> RA Sim only!", $time, id);
             else if (x`ctl != 2) $display("%05d  %-6s: Violation!!  Idle 00 -> %02b", $time, id, x`ctl);
          2: if (x`ctl != 3)      $display("%05d  %-6s: Violation!!  R    10 -> %02b", $time, id, x`ctl);
          3: if (x`ctl == 0)      $display("%05d  %-6s: Violation!!  RA   11 -> Idle 00 Sim only!", $time, id);
             else if (x`ctl != 1) $display("%05d  %-6s: Violation!!  RA   11 -> %02b", $time, id, x`ctl);
          1: if (x`ctl != 0)      $display("%05d  %-6s: Violation!!   A   01 -> %02b", $time, id, x`ctl);
        endcase

      if (x`ack && prev`data != x`data)
        $display("%05d  %-6s: Violation!!  %02b -> %02b and data %1d -> %1d", $time, id,
                 prev`ctl, x`ctl,
                 prev`data, x`data);
      prev = x;
   end
endmodule

module comp_spy#(parameter id = "??",
                 parameter w = 32)
   (inout `chan x);

   check#(id, w) chk(x);

   reg `chan prev = 0;
   always @* if (x != prev) begin
     $display("%05d  %-6s: %s %1d", $time, id,
              x`ctl == 0 ? "  " :
              x`ctl == 2 ? "R " :
              x`ctl == 3 ? "RA" :
              /*     == 1*/ " A",
              x`data);
      prev = x;
   end
endmodule

module comp_spy3#(parameter id = "??",
                  parameter w = 32)
   (inout `chan3 x);

   check#(.id(id), .w(3*w)) chk(x);

   reg `chan prev = 0;

   always @* if (x != prev) begin
     $display("%05d  %-6s: %s %1d %1d %1d", $time, id,
              x`ctl == 0 ? "  " :
              x`ctl == 2 ? "R " :
              x`ctl == 3 ? "RA" :
              /*     == 1*/ " A",
              x`data2, x`data1, x`data);
      prev = x;
   end
endmodule

module comp_spy0#(parameter id = "??")
   (inout `ctl x);

   wire dummy = 0;

   check#(id, 1) chk({dummy, x}); // Verilog doesn't handle empty ranges

   reg `ctl prev = 0;

   always @* if (x != prev) begin
     $display("%05d  %-6s: %s", $time, id,
              x`ctl == 0 ? "  " :
              x`ctl == 2 ? "R " :
              x`ctl == 3 ? "RA" :
              /*     == 1*/ " A");
      prev = x;
   end
endmodule
`endif

module comp_elem#(parameter w = 100,
                  parameter valid = 1'd0,
                  parameter data = 0,
                  parameter delay = 2)
   (input reset,
    inout `chan x,
    inout `chan y);

   (* keep *) reg [w-1:0] ydata;

   // Being explicit here to try to flesh out a yosys complaint about
   // conflicting drivers for x`ack

   wire   x_ack;

   cgate#(valid) cg_elem(reset, !y`ack, x`req, x_ack);

   assign x`ack = x_ack;

   wire   delayed_yreq;
   comp_delay #(delay) d0_elem(reset, x_ack, delayed_yreq);

   assign y`req = delayed_yreq & x_ack;
   assign y`data = ydata;

   always @* if (reset)
     ydata = data;
   else if (x_ack)
     ydata = x`data;
endmodule

// Stupid Verilog
module comp_elem0#(parameter valid = 1'd0,
                   parameter delay = 1)
   (input reset,
    inout `ctl x,
    inout `ctl y);

   wire delayed_yreq;

   cgate#(valid) cg(reset, !y`ack, x`req, x`ack);
   comp_delay #(delay) d0(reset, x`ack, delayed_yreq);
   assign y`req = delayed_yreq & x`ack;
endmodule

module comp_elemV#(parameter w = 1,
                  parameter data = 0,
                  parameter delay = 1)
   (input reset,
    inout `chan x,
    inout `chan y);

   comp_elem #(.valid(1'd1), .w(w), .data(data), .delay(delay)) i (reset, x, y);
endmodule

module comp_elemV0#(parameter delay = 1)
   (input reset,
    inout `ctl x,
    inout `ctl y);

   comp_elem0 #(.valid(1'd1), .delay(delay)) i (reset, x, y);
endmodule

module comp_fork#(parameter w = 32)
   (input reset,
    inout `chan x,
    inout `chan y, inout `chan z);
   assign y`data = x`data;
   assign z`data = x`data;
   assign y`req = x`req;
   assign z`req = x`req;
   cgate c(reset, y`ack, z`ack, x`ack);
endmodule

// we need comp_fork0 because Verilog is stupid and can't handle emptiness
module comp_fork0#(parameter w = 32)
   (input reset,
    inout `chan x,
    inout `chan y, inout `ctl z);
   assign y`data = x`data;
   assign y`req = x`req;
   assign z`req = x`req;
   cgate c(reset, y`ack, z`ack, x`ack);
endmodule

module comp_join#(parameter w = 32, parameter wy = 32)
   (input reset,
    inout `chan x, inout [wy+1:0] y,
    inout [wy+w+1:0] z);
   assign x`ack = z`ack;
   assign y`ack = z`ack;
   assign z[wy+w+1:2] = {y[wy+1:0], x`data};
   cgate c(reset, x`req, y`req, z`req);
endmodule

// See fork0 for why we need join0
module comp_join0#(parameter w = 32)
   (input reset,
    inout `chan x, inout `ctl y,
    inout `chan z);
   assign x`ack = z`ack;
   assign y`ack = z`ack;
   assign z`data = x`data;
   cgate c(reset, x`req, y`req, z`req);
endmodule

// XXX Merge is trick.  As best I can tell, the book verion is wrong
// as the mux being guided directly by x`req (or conversely y`req)
// means that data can change as soon as the input request is dropped
// while the consumer is still sampling (z`ack).
//
// The fix seems to be a driving the mux from a C gate of x`req,
// !y`req.  However this leads to a small race/gitch as the C gate is
// slower than the OR gate driving z`req.

// Also?:
//   If the mux (z`data) is slower than the request
// (z`req) + acknowledgement (z`ack) then the receiver can latch the
// wrong data.  We thus have to delay the request by an amount that
// exceeds the data delay
module comp_merge#(parameter w = 32)
   (input reset,
    inout `chan x, inout `chan y,
    inout `chan z);

   wire xactive;
   cgate cg1(reset, x`req, !y`req, xactive);
   cgate cg2(reset, z`ack, x`req, x`ack);
   cgate cg3(reset, z`ack, y`req, y`ack);
// assign z`req = x`req | y`req; // RACY
   assign z`req = xactive ? x`req : y`req;

// assign z`data = x`req ? x`data : y`data; // GLITCHY!
   assign z`data = xactive ? x`data : y`data;

`ifdef SIM
   always @*
     if (x`req & !x`ack & y`req & !y`ack)
       $display("%05d  merge on two active channels!! %d vs %d", $time,
                x`ctl, y`ctl);
`endif
/*
   always @*
     if (z`req)
       $display("%05d  merge on %1d %1d", $time, x, y);
*/
endmodule

module comp_mux#(parameter w = 32)
   (input reset,
    inout [2:0] ctl, inout `chan x, inout `chan y,
    inout `chan z);
   wire xreq_gated, yreq_gated;
   cgate cg0(reset, x`req, ctl`req & !ctl[2], xreq_gated);
   cgate cg1(reset, y`req, ctl`req & ctl[2], yreq_gated);
   cgate cg2(reset, z`ack, xreq_gated, x`ack);
   cgate cg3(reset, z`ack, yreq_gated, y`ack);
   assign z`req = xreq_gated | yreq_gated;
   assign z`data = ctl[2] ? y`data : x`data;
   assign ctl`ack = z`ack;
endmodule

module comp_demux#(parameter w = 32)
   (input reset,
    inout [2:0] ctl, inout `chan x,
    inout `chan y, inout `chan z);

   assign x`ack = y`ack | z`ack;
   assign ctl`ack = x`ack;

   cgate cg0(reset, x`req, ctl`req & !ctl[2], y`req);
   cgate cg1(reset, x`req, ctl`req & ctl[2], z`req);

   assign y`data = x`data;
   assign z`data = x`data;
endmodule

// comp_bdebug is like demux except the control comes bundled with
// data and doesn't have its own handshake (this is cheaper)
module comp_bdemux#(parameter w = 32)
   (input _reset,
    inout [w+2:0] ctlx,
    inout `chan y, inout `chan z);

   assign ctlx`ack = y`ack | z`ack;

   assign y`req = ctlx`req & !ctlx[w+2];
   assign z`req = ctlx`req &  ctlx[w+2];
   assign y`data = ctlx`data;
   assign z`data = ctlx`data;
endmodule

module comp_add1#(parameter w = 32)
   (input _reset,
    inout `chan x,
    inout `chan y);

   assign x`ack = y`ack;
   assign y`req = x`req;
   assign y`data = x`data + 1;
endmodule

module comp_isnonzero#(parameter w = 32)
   (input _reset,
    inout `chan x,
    inout [2:0] y);

   assign x`ack = y`ack;
   assign y`req = x`req;
   assign y[2]  = x`data != 0;
endmodule

module comp_bundled_isnz#(parameter w = 32)
   (input _reset,
    inout `chan x,
    inout [w+2:0] y);

   assign x`ack = y`ack;
   assign y`req = x`req;
   assign y[w+2:2]  = {x`data != 0,x`data};
endmodule

// Multiplication step (XXX doesn't take advantage of skipping add)
//
// if (b&1) == 1:
//   c += a
// a *= 2
// b /= 2
module mulstep#(parameter w = 32)
   (input _reset,
    inout `chan3 abc,
    inout `chan3 new_abc);
   wire [w-1:0] a = abc`data2;
   wire [w-1:0] b = abc`data1;
   wire [w-1:0] c = abc`data;
   wire [w-1:0] new_c = c + ((b & 1) == 1 ? a : 0);
   assign abc`ack = new_abc`ack;
   assign new_abc[3*w+1:2] = {a << 1, b >> 1, new_c};
   assign new_abc`req = abc`req;
endmodule


module loop_cond#(parameter w = 32)
   (input _reset,
    inout `chan3 abc,
    inout [3*w+2:0] tabc);
   wire [w-1:0] a = abc`data2;
   wire [w-1:0] b = abc`data1;
   wire [w-1:0] c = abc`data;
   wire         t = b != 0;
   assign abc`ack = tabc`ack;
   assign tabc[3*w+2:2] = {t, a, b, c};
   assign tabc`req = abc`req;
endmodule


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
