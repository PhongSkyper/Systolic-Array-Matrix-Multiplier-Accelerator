// =============================================================================
// FILE     : delay_line.sv
// GROUP    : systolic
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Parameterised shift-register delay line for diagonal input
//            skewing in the systolic array.
//
// PARAMETERS :
//   WIDTH — data width in bits     (default 8)
//   DEPTH — number of pipeline stages (default 1)
//             DEPTH=0 → combinational wire-through (no FFs instantiated)
//             DEPTH>0 → chain of DEPTH registered stages
//
// USAGE in systolic_array_top :
//   DLY_A[i] delays row    i of A by i cycles  (DEPTH=i)
//   DLY_B[j] delays column j of B by j cycles  (DEPTH=j)
//   This diagonal skew ensures A[r][k] and B[k][c] arrive at PE[r][c]
//   on the same clock cycle during computation.
//
// NOTE : en is always tied to 1'b1 in the array — the skew registers
//        must run freely regardless of the controller en_all signal.
//
// SYNTHESIS NOTE — (* ramstyle = "logic" *) :
//   Without this attribute, Quartus infers shift-register chains with
//   DEPTH >= 3 as altshift_taps → altsyncram (Block RAM or MLAB).
//   Block RAM has higher output-register delay than plain LUT FFs, which
//   caused DLY_B[3..7] to dominate the critical path report:
//     delay_line (RAM output) → pe.mul_reg  ~8.06 ns  → Fmax ~71 MHz
//
//   Forcing "logic" keeps every stage as a plain flip-flop chain:
//     delay_line (FF  output) → pe.mul_reg  ~3–4 ns  (expected after fix)
//
//   Trade-off: uses ALM registers instead of free Block RAM bits.
//   Register cost:  DLY_A[0..7] + DLY_B[0..7] = 448 FFs total  (<7% increase).
// =============================================================================
`timescale 1ns/1ps

module delay_line #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 1
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             en,
    input  logic [WIDTH-1:0] d_in,
    output logic [WIDTH-1:0] d_out
);
    generate
        if (DEPTH == 0) begin : NO_DELAY
            assign d_out = d_in;
        end else begin : SHIFT_CHAIN
            // (* ramstyle = "logic" *) forces Quartus to implement this
            // shift register as a chain of plain flip-flops (ALM registers)
            // instead of inferring altshift_taps / altsyncram (Block RAM).
            (* ramstyle = "logic" *)
            logic [WIDTH-1:0] pipe [0:DEPTH];

            assign pipe[0] = d_in;
            assign d_out   = pipe[DEPTH];

            genvar k;
            for (k = 0; k < DEPTH; k++) begin : STAGE
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n)   pipe[k+1] <= '0;
                    else if (en)  pipe[k+1] <= pipe[k];
                end
            end
        end
    endgenerate

endmodule
