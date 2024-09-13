`ifdef SIM
`timescale 1ns / 1ns
`endif

`define ack [0]
`define req [1]
`define ctl [1:0]
`define data [w+1:2] // AKA, data0
`define chan [w+1:0]

`define chan2 [2*w+1:0]
`define data1 [2*w+1:w+2]

`define chan3 [3*w+1:0]
`define data2 [3*w+1:2*w+2]
