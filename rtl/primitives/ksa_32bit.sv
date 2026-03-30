// =============================================================================
// FILE     : ksa_32bit.sv
// GROUP    : primitives
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : 32-bit Kogge-Stone Adder — used in the PE for final CSA merge.
//            Reverted to fully combinational architecture.
// =============================================================================
`timescale 1ns/1ps

module pg_cell (
    input  logic a,
    input  logic b,
    output logic p,
    output logic g
);
    assign p = a ^ b;
    assign g = a & b;
endmodule

module black_cell (
    input  logic p_i,
    input  logic g_i,
    input  logic p_prev,
    input  logic g_prev,
    output logic p_out,
    output logic g_out
);
    assign g_out = g_i | (p_i & g_prev);
    assign p_out = p_i & p_prev;
endmodule

module gray_cell (
    input  logic p_i,
    input  logic g_i,
    input  logic g_prev,
    output logic g_out
);
    assign g_out = g_i | (p_i & g_prev);
endmodule

module ksa_32bit (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic        cin,
    output logic [31:0] sum,
    output logic        cout
);
    logic [32:0] p0, g0;
    logic [32:0] p1, g1;
    logic [32:0] p2, g2;
    logic [32:0] p3, g3;
    logic [32:0] p4, g4;
    logic [32:0]     g5;

    genvar i;

    // Pre-processing
    assign p0[0] = 1'b1;
    assign g0[0] = cin;
    generate
        for (i = 1; i <= 32; i++) begin : PRE
            pg_cell u_pg (.a(a[i-1]), .b(b[i-1]), .p(p0[i]), .g(g0[i]));
        end
    endgenerate

    // Stage 1
    assign p1[0] = p0[0];
    assign g1[0] = g0[0];
    generate
        for (i = 1; i <= 32; i++) begin : ST1
            black_cell u_bc (
                .p_i(p0[i]), .g_i(g0[i]), .p_prev(p0[i-1]), .g_prev(g0[i-1]),
                .p_out(p1[i]), .g_out(g1[i])
            );
        end
    endgenerate

    // Stage 2
    generate
        for (i = 0; i < 2; i++) begin : ST2_PASS
            assign p2[i] = p1[i];  assign g2[i] = g1[i];
        end
        for (i = 2; i <= 32; i++) begin : ST2
            black_cell u_bc (
                .p_i(p1[i]), .g_i(g1[i]), .p_prev(p1[i-2]), .g_prev(g1[i-2]),
                .p_out(p2[i]), .g_out(g2[i])
            );
        end
    endgenerate

    // Stage 3
    generate
        for (i = 0; i < 4; i++) begin : ST3_PASS
            assign p3[i] = p2[i];  assign g3[i] = g2[i];
        end
        for (i = 4; i <= 32; i++) begin : ST3
            black_cell u_bc (
                .p_i(p2[i]), .g_i(g2[i]), .p_prev(p2[i-4]), .g_prev(g2[i-4]),
                .p_out(p3[i]), .g_out(g3[i])
            );
        end
    endgenerate

    // Stage 4
    generate
        for (i = 0; i < 8; i++) begin : ST4_PASS
            assign p4[i] = p3[i];  assign g4[i] = g3[i];
        end
        for (i = 8; i <= 32; i++) begin : ST4
            black_cell u_bc (
                .p_i(p3[i]), .g_i(g3[i]), .p_prev(p3[i-8]), .g_prev(g3[i-8]),
                .p_out(p4[i]), .g_out(g4[i])
            );
        end
    endgenerate

    // Stage 5
    generate
        for (i = 0; i < 16; i++) begin : ST5_PASS
            assign g5[i] = g4[i];
        end
        for (i = 16; i <= 32; i++) begin : ST5
            gray_cell u_gc (
                .p_i(p4[i]), .g_i(g4[i]), .g_prev(g4[i-16]),
                .g_out(g5[i])
            );
        end
    endgenerate

    // Post-processing
    generate
        for (i = 0; i < 32; i++) begin : POST
            assign sum[i] = p0[i+1] ^ g5[i];
        end
    endgenerate

    logic g_cout32;
    gray_cell u_cout (
        .p_i(p4[32]),
        .g_i(g5[32]),
        .g_prev(g5[16]),
        .g_out(g_cout32)
    );
    assign cout = g_cout32;

endmodule