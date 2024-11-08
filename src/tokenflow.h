/*
 * NCL Async Multiplier -- Tommy Thorn 20240913
 *
 * This is intended to be an NCL version of tt08-maxbw for a
 * comparison.
 *
 * Note, NCL encodes the REQ in the data itself and that can
 * be done in many ways.  By default I assume all data is
 * dual-rail encoded, but 1-of-N might be better in some cases.
 */

`ifdef SIM
`timescale 1ns / 1ns
`endif

`define ack [0]
`define data [2*w:1]
`define chan [2*w:0]

// Splitting the dual-rail encoded values with the lower bits being
// the "0"s, eg. the complement of value and the higher the "1"s, thus
// the true value.
`define data_neg [w:1]
`define data_pos [2*w:w+1]

// Triple payload channels
`define chan3 [6*w:0]
`define data1 [4*w:2*w+1]
`define data2 [6*w:4*w+1]

// Ctl is a control-only channel; it only carries a valid bit and acknowledge
`define ctl [1:0]
