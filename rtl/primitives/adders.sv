// =============================================================================
// FILE     : adders.sv
// GROUP    : primitives
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Structural adder / comparator library.
//            All units are built from full_adder cells so the synthesis
//            tool sees each carry chain explicitly — no inferred adders.
//
// CONTENTS (in compile order):
//   full_adder             — 1-bit FA primitive
//   adder_3bit_struct      — 3-bit ripple (n_cnt increment in UART FSMs)
//   adder_4bit_struct      — 4-bit ripple (s_cnt increment; CSA block)
//   adder_9bit_struct      — 9-bit ripple (baud counter in uart_top)
//   comparator_4bit_struct — 4-bit equality comparator (XNOR + AND4)
//   adder #(N)             — generic N-bit ripple (parameterised utility)
//   synchronizer           — 2-FF metastability synchronizer
//
// DEPENDENCIES : primitives/gates.sv  (xnor_gate, and4_gate)
// =============================================================================
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// full_adder — 1-bit full adder
//   sum  = a XOR b XOR cin
//   cout = (a AND b) OR (cin AND (a XOR b))
// -----------------------------------------------------------------------------
module full_adder (
    input  logic a,
    input  logic b,
    input  logic cin,
    output logic sum,
    output logic cout
);
    assign sum  = a ^ b ^ cin;
    assign cout = (a & b) | (cin & (a ^ b));
endmodule

// -----------------------------------------------------------------------------
// adder_3bit_struct — 3-bit ripple-carry adder
//   Used for n_cnt (data-bit counter, 0–7) increments in uart_rx / uart_tx.
// -----------------------------------------------------------------------------
module adder_3bit_struct (
    input  logic [2:0] a,
    input  logic [2:0] b,
    input  logic       ci,
    output logic [2:0] sum,
    output logic       co
);
    logic c0, c1;
    full_adder u0 (.a(a[0]), .b(b[0]), .cin(ci), .sum(sum[0]), .cout(c0));
    full_adder u1 (.a(a[1]), .b(b[1]), .cin(c0), .sum(sum[1]), .cout(c1));
    full_adder u2 (.a(a[2]), .b(b[2]), .cin(c1), .sum(sum[2]), .cout(co));
endmodule

// -----------------------------------------------------------------------------
// adder_4bit_struct — 4-bit ripple-carry adder
//   Used for s_cnt (sample counter, 0–15) increments in uart_rx / uart_tx,
//   and as the 4-bit building block of final_adder_16bit (carry-select).
// -----------------------------------------------------------------------------
module adder_4bit_struct (
    input  logic [3:0] a,
    input  logic [3:0] b,
    input  logic       ci,
    output logic [3:0] sum,
    output logic       co
);
    logic c0, c1, c2;
    full_adder u0 (.a(a[0]), .b(b[0]), .cin(ci), .sum(sum[0]), .cout(c0));
    full_adder u1 (.a(a[1]), .b(b[1]), .cin(c0), .sum(sum[1]), .cout(c1));
    full_adder u2 (.a(a[2]), .b(b[2]), .cin(c1), .sum(sum[2]), .cout(c2));
    full_adder u3 (.a(a[3]), .b(b[3]), .cin(c2), .sum(sum[3]), .cout(co));
endmodule

// -----------------------------------------------------------------------------
// adder_9bit_struct — 9-bit ripple-carry adder
//   Used for the 9-bit baud-rate counter in uart_top.
// -----------------------------------------------------------------------------
module adder_9bit_struct (
    input  logic [8:0] a,
    input  logic [8:0] b,
    input  logic       ci,
    output logic [8:0] sum,
    output logic       co
);
    logic c0, c1, c2, c3, c4, c5, c6, c7;
    full_adder u0 (.a(a[0]), .b(b[0]), .cin(ci), .sum(sum[0]), .cout(c0));
    full_adder u1 (.a(a[1]), .b(b[1]), .cin(c0), .sum(sum[1]), .cout(c1));
    full_adder u2 (.a(a[2]), .b(b[2]), .cin(c1), .sum(sum[2]), .cout(c2));
    full_adder u3 (.a(a[3]), .b(b[3]), .cin(c2), .sum(sum[3]), .cout(c3));
    full_adder u4 (.a(a[4]), .b(b[4]), .cin(c3), .sum(sum[4]), .cout(c4));
    full_adder u5 (.a(a[5]), .b(b[5]), .cin(c4), .sum(sum[5]), .cout(c5));
    full_adder u6 (.a(a[6]), .b(b[6]), .cin(c5), .sum(sum[6]), .cout(c6));
    full_adder u7 (.a(a[7]), .b(b[7]), .cin(c6), .sum(sum[7]), .cout(c7));
    full_adder u8 (.a(a[8]), .b(b[8]), .cin(c7), .sum(sum[8]), .cout(co));
endmodule

// -----------------------------------------------------------------------------
// comparator_4bit_struct — 4-bit equality comparator
//   Checks a[3:0] == b[3:0] using XNOR + AND4.
//   Used for FIFO status checks and baud counter terminal detection.
// -----------------------------------------------------------------------------
module comparator_4bit_struct (
    input  logic [3:0] a,
    input  logic [3:0] b,
    output logic       equal   // 1 when a == b
);
    logic eq0, eq1, eq2, eq3;
    xnor_gate u_eq0 (.a(a[0]), .b(b[0]), .y(eq0));
    xnor_gate u_eq1 (.a(a[1]), .b(b[1]), .y(eq1));
    xnor_gate u_eq2 (.a(a[2]), .b(b[2]), .y(eq2));
    xnor_gate u_eq3 (.a(a[3]), .b(b[3]), .y(eq3));
    and4_gate u_all  (.a(eq0), .b(eq1), .c(eq2), .d(eq3), .y(equal));
endmodule

// -----------------------------------------------------------------------------
// adder #(N) — generic N-bit ripple-carry adder
//   Parameterised utility adder.  Uses generate-for to instantiate N
//   full_adder cells in a ripple chain.
//   NOTE: For the 32-bit accumulation path use ksa_32bit instead —
//         this ripple adder is O(N) delay, not O(log N).
// -----------------------------------------------------------------------------
module adder #(
    parameter int N = 4
)(
    input  logic [N-1:0] a,
    input  logic [N-1:0] b,
    output logic [N-1:0] sum,
    output logic         cout
);
    logic [N:0] c;
    assign c[0] = 1'b0;
    assign cout = c[N];

    genvar i;
    generate
        for (i = 0; i < N; i++) begin : GEN_RIPPLE
            full_adder fa_i (
                .a(a[i]), .b(b[i]), .cin(c[i]),
                .sum(sum[i]), .cout(c[i+1])
            );
        end
    endgenerate
endmodule

// -----------------------------------------------------------------------------
// synchronizer — 2-FF metastability synchronizer
//   Crosses an asynchronous signal (e.g. UART RX pin) into the system
//   clock domain with 2-cycle latency.
//   Reset drives both FFs HIGH (UART idle / marking state).
// -----------------------------------------------------------------------------
module synchronizer (
    input  logic clk,
    input  logic rst_n,
    input  logic in_async,    // Asynchronous input
    output logic out_sync     // Synchronized output (2-cycle latency)
);
    logic stage1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1   <= 1'b1;   // Idle high (UART marking)
            out_sync <= 1'b1;
        end else begin
            stage1   <= in_async;
            out_sync <= stage1;
        end
    end
endmodule
