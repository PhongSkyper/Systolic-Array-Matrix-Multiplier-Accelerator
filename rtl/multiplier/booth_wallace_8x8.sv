// =============================================================================
// FILE     : booth_wallace_8x8.sv
// GROUP    : multiplier
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : 8×8 Radix-4 Modified Booth × Wallace Tree Multiplier.
//            Computes p_out[15:0] = a_in[7:0] × b_in[7:0], signed or unsigned.
//            Fully combinational — pipeline registers inserted by pe.sv.
//
// PIPELINE CUT POINTS (v4.0) :
//   Stage 1a (~2–3 ns) : Booth enc + PPG + Alignment  →  pp_reg  (in pe.sv)
//   Stage 1b (~3–4 ns) : Wallace Tree 3×FA             →  wt_reg  (in pe.sv)
//   Stage 1c (~2–3 ns) : KSA-16 final adder            →  mul_reg (in pe.sv)
//
// PORT GROUPS :
//   GROUP A — Stage 1a outputs (captured in pp_reg inside pe.sv):
//     pp_out[0..3]  four 16-bit aligned partial products
//     neg_out       16-bit neg_vect for two's-complement correction
//
//   GROUP B — Stage 1b inputs/outputs (Wallace tree only):
//     pp_in[0..3]   from pp_reg
//     neg_in        from pp_reg
//     wt_sum_out    Wallace sum  row  → wt_reg
//     wt_carry_out  Wallace carry row → wt_reg
//
//   GROUP C — Stage 1c inputs/outputs (KSA-16 only):
//     wt_sum_in     from wt_reg
//     wt_carry_in   from wt_reg
//     p_out         16-bit final product → mul_reg
//
// CONTENTS (compile order within this file) :
//   booth_encoder              — Radix-4 digit encoder
//   partial_product_generator  — 10-bit PP generator (v4.2: widened to 10b)
//   wallace_tree_compressor    — 3-stage FA 5→2 row compressor
//   ksa_16bit                  — 16-bit Kogge-Stone final adder (v3.0)
//   booth_wallace_8x8          — top module
//
// DEPENDENCIES :
//   primitives/adders.sv        (full_adder)
//   primitives/ksa_32bit.sv     (pg_cell, black_cell, gray_cell — reused)
//
// REVISION HISTORY :
//   v1.0 — Original single-stage Booth+Wallace+CSA
//   v2.0 — Pipeline cut: expose pp_out/neg_out for pp_reg in PE
//   v3.0 — Replace CSA with KSA-16 final adder
//   v4.0 — Pipeline cut between Wallace and KSA-16 (wt_reg stage)
//   v4.2 — Widen pp_raw to 10-bit; add 5th Booth window for unsigned B
// =============================================================================
`timescale 1ns/1ps

// =============================================================================
// PART 1 : BOOTH ENCODER
// =============================================================================
// Encodes a 3-bit overlapping window of multiplier B into three control
// signals that drive the Partial Product Generator.
//
// Truth table (Radix-4 Modified Booth) :
//   b+1  b  b-1 │ single  double  neg │ Value
//   ─────────────┼─────────────────────┼──────
//    0   0   0  │   0       0      0  │  0
//    0   0   1  │   1       0      0  │ +A
//    0   1   0  │   1       0      0  │ +A
//    0   1   1  │   0       1      0  │ +2A
//    1   0   0  │   0       1      1  │ -2A
//    1   0   1  │   1       0      1  │ -A
//    1   1   0  │   1       0      1  │ -A
//    1   1   1  │   0       0      1  │  0
//
// Equations :
//   single = b XOR b_minus_1
//   double = NOT(b XOR b_minus_1) AND (b_plus_1 XOR b)
//   neg    = b_plus_1
// =============================================================================
module booth_encoder (
    input  logic b_plus_1,
    input  logic b,
    input  logic b_minus_1,
    output logic single,
    output logic double,
    output logic neg
);
    logic bxb1, bp1xb;
    assign bxb1  = b ^ b_minus_1;
    assign bp1xb = b_plus_1 ^ b;
    assign single = bxb1;
    assign double = (~bxb1) & bp1xb;
    assign neg    = b_plus_1;
endmodule

// =============================================================================
// PART 2 : PARTIAL PRODUCT GENERATOR  (10-bit output, v4.2)
// =============================================================================
// WHY 10-BIT :
//   For unsigned A ≥ 128, 2A ≥ 256 overflows 9-bit signed range.
//   Fix: widen in_2a to 10 bits {sign_bit, a[7:0], 0}.
//   sign_bit = a_in[7] & is_signed  (0 for unsigned → no spurious negation).
// =============================================================================
module partial_product_generator (
    input  logic [7:0] a_in,
    input  logic       is_signed,
    input  logic       single,
    input  logic       double,
    input  logic       neg,
    output logic [9:0] pp_out
);
    logic [8:0] in_1a;
    logic [9:0] in_2a;
    logic [9:0] p_mux;
    logic       sign_bit;

    assign sign_bit = a_in[7] & is_signed;
    assign in_1a    = {sign_bit, a_in[7:0]};
    assign in_2a    = {sign_bit, a_in[7:0], 1'b0};

    // Sign-extend in_1a to 10 bits (use in_1a[8] as MSB, not zero-extend)
    assign p_mux    = ({in_1a[8], in_1a} & {10{single}}) | (in_2a & {10{double}});
    assign pp_out   = p_mux ^ {10{neg}};   // Ones complement (two's-comp +1 via neg_vect)
endmodule

// =============================================================================
// PART 3 : WALLACE TREE COMPRESSOR (3-stage, 5 rows → 2 rows)
// =============================================================================
// Reduces five 16-bit rows (4 aligned PPs + neg_vect) to two rows.
//   Stage 1 : FA-compress {pp0, pp1, pp2}       → {s1, c1}
//   Stage 2 : FA-compress {s1,  c1,  pp3}       → {s2, c2}
//   Stage 3 : FA-compress {s2,  c2,  neg_vect}  → {sum_out, carry_out}
// =============================================================================
module wallace_tree_compressor (
    input  logic [15:0] pp0, pp1, pp2, pp3,
    input  logic [15:0] neg_vect,
    output logic [15:0] sum_out,
    output logic [15:0] carry_out
);
    logic [15:0] s1, s2;
    logic [15:0] c1_raw, c2_raw, c3_raw;
    logic [16:0] c1_ext, c2_ext, c3_ext;
    logic [15:0] c1, c2;

    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : S1
            full_adder fa (.a(pp0[i]), .b(pp1[i]), .cin(pp2[i]),
                           .sum(s1[i]), .cout(c1_raw[i]));
        end
    endgenerate
    assign c1_ext = {c1_raw, 1'b0};
    assign c1     = c1_ext[15:0];

    generate
        for (i = 0; i < 16; i++) begin : S2
            full_adder fa (.a(s1[i]), .b(c1[i]), .cin(pp3[i]),
                           .sum(s2[i]), .cout(c2_raw[i]));
        end
    endgenerate
    assign c2_ext = {c2_raw, 1'b0};
    assign c2     = c2_ext[15:0];

    generate
        for (i = 0; i < 16; i++) begin : S3
            full_adder fa (.a(s2[i]), .b(c2[i]), .cin(neg_vect[i]),
                           .sum(sum_out[i]), .cout(c3_raw[i]));
        end
    endgenerate
    assign c3_ext    = {c3_raw, 1'b0};
    assign carry_out = c3_ext[15:0];
endmodule

// =============================================================================
// PART 4 : KSA-16 — 16-bit Kogge-Stone Final Adder  (v3.0)
// =============================================================================
// Replaces 4-block Carry-Select Adder (CSA) from v2.x.
// 4 prefix stages → O(log₂16) = 4 parallel prefix levels, ~2–3 ns.
//
// Cell reuse: pg_cell, black_cell, gray_cell declared in ksa_32bit.sv.
// =============================================================================
module ksa_16bit (
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic        cin,
    output logic [15:0] sum,
    output logic        cout
);
    logic [16:0] p0, g0;
    logic [16:0] p1, g1;
    logic [16:0] p2, g2;
    logic [16:0] p3, g3;
    logic [16:0]     g4;

    genvar i;

    // Pre-processing
    assign p0[0] = 1'b1;   // FIX: propagate identity
    assign g0[0] = cin;
    generate
        for (i = 1; i <= 16; i++) begin : PRE
            pg_cell u_pg (.a(a[i-1]), .b(b[i-1]), .p(p0[i]), .g(g0[i]));
        end
    endgenerate

    // Stage 1 — distance 1
    assign p1[0] = p0[0];
    assign g1[0] = g0[0];
    generate
        for (i = 1; i <= 16; i++) begin : ST1
            black_cell u_bc (
                .p_i(p0[i]),   .g_i(g0[i]),
                .p_prev(p0[i-1]), .g_prev(g0[i-1]),
                .p_out(p1[i]), .g_out(g1[i])
            );
        end
    endgenerate

    // Stage 2 — distance 2
    generate
        for (i = 0; i < 2; i++) begin : ST2_PASS
            assign p2[i] = p1[i]; assign g2[i] = g1[i];
        end
        for (i = 2; i <= 16; i++) begin : ST2
            black_cell u_bc (
                .p_i(p1[i]),   .g_i(g1[i]),
                .p_prev(p1[i-2]), .g_prev(g1[i-2]),
                .p_out(p2[i]), .g_out(g2[i])
            );
        end
    endgenerate

    // Stage 3 — distance 4
    generate
        for (i = 0; i < 4; i++) begin : ST3_PASS
            assign p3[i] = p2[i]; assign g3[i] = g2[i];
        end
        for (i = 4; i <= 16; i++) begin : ST3
            black_cell u_bc (
                .p_i(p2[i]),   .g_i(g2[i]),
                .p_prev(p2[i-4]), .g_prev(g2[i-4]),
                .p_out(p3[i]), .g_out(g3[i])
            );
        end
    endgenerate

    // Stage 4 — distance 8  (Gray cells only)
    generate
        for (i = 0; i < 8; i++) begin : ST4_PASS
            assign g4[i] = g3[i];
        end
        for (i = 8; i <= 16; i++) begin : ST4
            gray_cell u_gc (
                .p_i(p3[i]),   .g_i(g3[i]),
                .g_prev(g3[i-8]),
                .g_out(g4[i])
            );
        end
    endgenerate

    // Post-processing
    generate
        for (i = 0; i < 16; i++) begin : POST
            assign sum[i] = p0[i+1] ^ g4[i];
        end
    endgenerate

    logic g_cout16;
    gray_cell u_cout (
        .p_i(p3[16]),
        .g_i(g4[16]),
        .g_prev(g4[8]),
        .g_out(g_cout16)
    );
    assign cout = g_cout16;

endmodule

// =============================================================================
// PART 5 : BOOTH-WALLACE 8×8 TOP MODULE
// =============================================================================
module booth_wallace_8x8 (
    input  logic [7:0]  a_in,
    input  logic [7:0]  b_in,
    input  logic        is_signed,
    // Stage 1a outputs — captured in pp_reg inside pe.sv
    output logic [15:0] pp_out      [0:3],
    output logic [15:0] neg_out,
    // Stage 1b inputs/outputs — Wallace tree only
    input  logic [15:0] pp_in       [0:3],
    input  logic [15:0] neg_in,
    output logic [15:0] wt_sum_out,
    output logic [15:0] wt_carry_out,
    // Stage 1c inputs/outputs — KSA-16 only
    input  logic [15:0] wt_sum_in,
    input  logic [15:0] wt_carry_in,
    output logic [15:0] p_out
);

    // =========================================================================
    // Stage 1a — Booth Encoders + PPG + Alignment (~2–3 ns)
    // =========================================================================
    logic single[0:3], double[0:3], neg[0:3];

    booth_encoder enc0 (.b_plus_1(b_in[1]), .b(b_in[0]), .b_minus_1(1'b0),
                        .single(single[0]), .double(double[0]), .neg(neg[0]));
    booth_encoder enc1 (.b_plus_1(b_in[3]), .b(b_in[2]), .b_minus_1(b_in[1]),
                        .single(single[1]), .double(double[1]), .neg(neg[1]));
    booth_encoder enc2 (.b_plus_1(b_in[5]), .b(b_in[4]), .b_minus_1(b_in[3]),
                        .single(single[2]), .double(double[2]), .neg(neg[2]));
    booth_encoder enc3 (.b_plus_1(b_in[7]), .b(b_in[6]), .b_minus_1(b_in[5]),
                        .single(single[3]), .double(double[3]), .neg(neg[3]));

    logic [9:0] pp_raw[0:3];   // 10-bit partial products (v4.2)
    genvar k;
    generate
        for (k = 0; k < 4; k++) begin : PPG
            partial_product_generator ppg (
                .a_in(a_in), .is_signed(is_signed),
                .single(single[k]), .double(double[k]), .neg(neg[k]),
                .pp_out(pp_raw[k])
            );
        end
    endgenerate

    // Alignment to 16-bit (sign-extend from bit9)
    //   pp[0]: shift=0  → {6{bit9}, pp[9:0]}
    //   pp[1]: shift=2  → {4{bit9}, pp[9:0], 2'b0}
    //   pp[2]: shift=4  → {2{bit9}, pp[9:0], 4'b0}
    //   pp[3]: shift=6  → {pp[9:0], 6'b0}
    assign pp_out[0] = {{6{pp_raw[0][9]}}, pp_raw[0]             };
    assign pp_out[1] = {{4{pp_raw[1][9]}}, pp_raw[1],  2'b00    };
    assign pp_out[2] = {{2{pp_raw[2][9]}}, pp_raw[2],  4'b0000  };
    assign pp_out[3] = {   pp_raw[3],                  6'b000000};

    // neg_vect:
    //   bits[15:8]: 5th Booth window correction for unsigned B (b[7]=1)
    //   bits[7:0]:  two's-complement +1 correction bits per negated window
    assign neg_out = {
        a_in[7:0] & {8{b_in[7] & ~is_signed}},
        1'b0, neg[3], 1'b0, neg[2], 1'b0, neg[1], 1'b0, neg[0]
    };

    // =========================================================================
    // Stage 1b — Wallace Tree only (~3–4 ns)
    // =========================================================================
    wallace_tree_compressor u_wt (
        .pp0(pp_in[0]), .pp1(pp_in[1]),
        .pp2(pp_in[2]), .pp3(pp_in[3]),
        .neg_vect(neg_in),
        .sum_out(wt_sum_out), .carry_out(wt_carry_out)
    );

    // =========================================================================
    // Stage 1c — KSA-16 only (~2–3 ns)
    // =========================================================================
    ksa_16bit u_fa (
        .a(wt_sum_in), .b(wt_carry_in), .cin(1'b0),
        .sum(p_out), .cout()
    );

endmodule
