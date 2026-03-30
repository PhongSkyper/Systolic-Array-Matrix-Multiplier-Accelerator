// =============================================================================
// FILE     : gates.sv
// GROUP    : primitives
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Structural gate library — explicit primitives that map 1-to-1
//            to standard-cell library gates.
//            Using named modules (instead of raw operators) gives the
//            synthesis tool unambiguous cell targets and lets the designer
//            read gate-level critical paths directly in netlists.
//
// CONTENTS :
//   xnor_gate    — 2-input XNOR  (used by comparator for equality check)
//   and2_gate    — 2-input AND
//   and4_gate    — 4-input AND   (used to combine four XNOR bits)
//   mux2_1bit    — 1-bit 2-to-1 MUX (structural, no ternary operator)
// =============================================================================
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// xnor_gate — 2-input XNOR
// -----------------------------------------------------------------------------
module xnor_gate (
    input  logic a,
    input  logic b,
    output logic y
);
    assign y = ~(a ^ b);
endmodule

// -----------------------------------------------------------------------------
// and2_gate — 2-input AND
// -----------------------------------------------------------------------------
module and2_gate (
    input  logic a,
    input  logic b,
    output logic y
);
    assign y = a & b;
endmodule

// -----------------------------------------------------------------------------
// and4_gate — 4-input AND
// -----------------------------------------------------------------------------
module and4_gate (
    input  logic a,
    input  logic b,
    input  logic c,
    input  logic d,
    output logic y
);
    assign y = a & b & c & d;
endmodule

// -----------------------------------------------------------------------------
// mux2_1bit — 1-bit 2-to-1 MUX
//   sel=0 → y = d0 ;  sel=1 → y = d1
//   Implemented as sum-of-products to avoid ternary inference.
// -----------------------------------------------------------------------------
module mux2_1bit (
    input  logic d0,
    input  logic d1,
    input  logic sel,
    output logic y
);
    assign y = (d0 & ~sel) | (d1 & sel);
endmodule
