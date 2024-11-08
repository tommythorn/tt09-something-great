<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

A RISC-V ALU with inputs sub:1 ashr:1 funct3:3 w:1 op1:64 op2:64 and
outputs result:64 eq:1 lt:1 ltu:1 are connected with long shift
registers such that operands can be shifted in on `tdi` on every
positive clock edge.  On the cycle *after* the last data input bit,
asserting `sample` for one cycle and on the subsequent cycles the
result and the three condition codes will be shifted out on `tdo`.

## How to test

Here will be a little python script to exercise the design.

## External hardware

Nothing more than the bringup board
