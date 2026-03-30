// =============================================================================
// FILE     : pe.sv
// GROUP    : systolic
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Processing Element (PE) — the MAC unit in the systolic array.
//            Each PE computes one element of the output matrix:
//              C[r][c] += A[r][k] × B[k][c]   for k = 0 .. N-1
//
// PIPELINE (4 stages, CSA Architecture) :
//   Stage 1a : Booth enc + PPG + Alignment        → pp_reg
//   Stage 1b : Wallace Tree 3×FA                  → wt_reg
//   Stage 1c : KSA-16 final adder                 → mul_reg
//   Stage 2  : Carry-Save Accumulator (CSA loop)  → sum_reg & carry_reg
//
//   Output Merge: c_out = KSA_32(sum_reg, carry_reg)  [Combinational]
//
//   TOTAL_CYCLES = 3*N + 3  (N=8 → 27 cycles)
// =============================================================================
`timescale 1ns/1ps

module pe #(
    parameter int IN_WIDTH  = 8,
    parameter int ACC_WIDTH = 32
)(
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic clear,
    input  logic is_signed,
    input  logic [IN_WIDTH-1:0]  a_in,
    input  logic [IN_WIDTH-1:0]  b_in,
    output logic [IN_WIDTH-1:0]  a_out,
    output logic [IN_WIDTH-1:0]  b_out,
    output logic [ACC_WIDTH-1:0] c_out
);
    localparam int MUL_WIDTH = 2 * IN_WIDTH;

    // =========================================================================
    // Stage 1a — Booth Encode + PPG + Alignment
    // =========================================================================
    logic [MUL_WIDTH-1:0] pp_comb  [0:3];
    logic [MUL_WIDTH-1:0] neg_comb;
    logic [MUL_WIDTH-1:0] pp_reg   [0:3];
    logic [MUL_WIDTH-1:0] neg_reg;

    logic [MUL_WIDTH-1:0] wt_sum_comb;
    logic [MUL_WIDTH-1:0] wt_carry_comb;
    logic [MUL_WIDTH-1:0] p_out_1c;

    logic [MUL_WIDTH-1:0] wt_sum_reg;
    logic [MUL_WIDTH-1:0] wt_carry_reg;

    booth_wallace_8x8 u_mul (
        .a_in          (a_in),
        .b_in          (b_in),
        .is_signed     (is_signed),
        .pp_out        (pp_comb),
        .neg_out       (neg_comb),
        .pp_in         (pp_reg),
        .neg_in        (neg_reg),
        .wt_sum_out    (wt_sum_comb),
        .wt_carry_out  (wt_carry_comb),
        .wt_sum_in     (wt_sum_reg),
        .wt_carry_in   (wt_carry_reg),
        .p_out         (p_out_1c)
    );

    genvar g;
    generate
        for (g = 0; g < 4; g++) begin : PP_REG
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)      pp_reg[g] <= '0;
                else if (clear)  pp_reg[g] <= '0;
                else if (en)     pp_reg[g] <= pp_comb[g];
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      neg_reg <= '0;
        else if (clear)  neg_reg <= '0;
        else if (en)     neg_reg <= neg_comb;
    end

    // =========================================================================
    // Stage 1b — Wallace Tree only
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)     begin wt_sum_reg <= '0; wt_carry_reg <= '0; end
        else if (clear) begin wt_sum_reg <= '0; wt_carry_reg <= '0; end
        else if (en)    begin wt_sum_reg <= wt_sum_comb; wt_carry_reg <= wt_carry_comb; end
    end

    // =========================================================================
    // Stage 1c — KSA-16 final adder only
    // =========================================================================
    logic [ACC_WIDTH-1:0] mul_ext;
    logic [ACC_WIDTH-1:0] mul_reg;

    assign mul_ext = is_signed
        ? {{(ACC_WIDTH-MUL_WIDTH){p_out_1c[MUL_WIDTH-1]}}, p_out_1c}
        : {{(ACC_WIDTH-MUL_WIDTH){1'b0}},                  p_out_1c};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      mul_reg <= '0;
        else if (clear)  mul_reg <= '0;
        else if (en)     mul_reg <= mul_ext;
    end

    // =========================================================================
    // Stage 2 — Carry-Save Accumulator (CSA) Loop
    // =========================================================================
    logic [ACC_WIDTH-1:0] sum_reg, sum_next;
    logic [ACC_WIDTH-1:0] carry_reg, carry_next;
    logic [ACC_WIDTH-1:0] carry_raw;

    // 32 parallel Full Adders for the accumulator loop (O(1) delay)
    genvar i;
    generate
        for (i = 0; i < ACC_WIDTH; i++) begin : CSA_LOOP
            full_adder u_fa (
                .a   (sum_reg[i]),
                .b   (carry_reg[i]),
                .cin (mul_reg[i]),
                .sum (sum_next[i]),
                .cout(carry_raw[i])
            );
        end
    endgenerate

    // Shift carry left by 1 for the next accumulation cycle
    assign carry_next = {carry_raw[ACC_WIDTH-2:0], 1'b0};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_reg   <= '0;
            carry_reg <= '0;
        end else if (clear) begin
            sum_reg   <= '0;
            carry_reg <= '0;
        end else if (en) begin
            sum_reg   <= sum_next;
            carry_reg <= carry_next;
        end
    end

    // =========================================================================
    // Final Output Merge: KSA-32 (Combinational)
    // Resolves the deferred carry bits into the final 32-bit product
    // =========================================================================
    ksa_32bit u_ksa_final (
        .a   (sum_reg),
        .b   (carry_reg),
        .cin (1'b0),
        .sum (c_out),
        .cout()
    );

    // =========================================================================
    // Data forwarding
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= '0;
            b_out <= '0;
        end else begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end

endmodule