// =============================================================================
// FILE     : systolic_array_top.sv
// GROUP    : systolic
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : N×N output-stationary systolic array — computes C = A × B.
//
// DATA FLOW :
//   • Row vectors of A enter from the left, propagate rightward via a_out.
//   • Column vectors of B enter from the top, propagate downward via b_out.
//   • Each PE[r][c] accumulates A[r][k] × B[k][c] over k = 0 .. N-1.
//   • Results are stable in result[r][c] when done=1.
//
// DIAGONAL SKEWING :
//   DLY_A[i] delays row    i of A by i cycles.
//   DLY_B[j] delays column j of B by j cycles.
//   After skewing, A[r][k] and B[k][c] arrive at PE[r][c] simultaneously
//   on COMPUTE cycle r + c + k.
//
// CONTROL WIRING (v4.0) :
//   global_controller outputs per-PE buses en_all_bus[r][c] and
//   clear_pe_bus[r][c]. Each PE[r][c] receives its own dedicated FF,
//   eliminating the high-fanout routing path on Quartus Lite.
//
// DEPENDENCIES :
//   systolic/global_controller.sv
//   systolic/delay_line.sv
//   systolic/pe.sv
// =============================================================================
`timescale 1ns/1ps

module systolic_array_top #(
    parameter int N         = 8,
    parameter int IN_WIDTH  = 8,
    parameter int ACC_WIDTH = 32
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic is_signed,
    input  logic [IN_WIDTH-1:0]  data_a [0:N-1],
    input  logic [IN_WIDTH-1:0]  data_b [0:N-1],
    output logic [ACC_WIDTH-1:0] result [0:N-1][0:N-1],
    output logic                 done
);
    // Per-PE control buses from controller (v4.0 RTL fanout tree)
    logic en_all_bus  [0:N-1][0:N-1];
    logic clear_pe_bus[0:N-1][0:N-1];

    // Controller
    global_controller #(.N(N)) u_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .en_all_bus   (en_all_bus),
        .clear_pe_bus (clear_pe_bus),
        .done         (done)
    );

    // Inter-PE data buses
    logic [IN_WIDTH-1:0] a_conn [0:N-1][0:N];
    logic [IN_WIDTH-1:0] b_conn [0:N]  [0:N-1];

    // Input skew delay lines — free-running (en=1'b1)
    genvar i;
    generate
        for (i = 0; i < N; i++) begin : DLY_A
            delay_line #(.WIDTH(IN_WIDTH), .DEPTH(i)) u_dly (
                .clk(clk), .rst_n(rst_n), .en(1'b1),
                .d_in(data_a[i]), .d_out(a_conn[i][0])
            );
        end
        for (i = 0; i < N; i++) begin : DLY_B
            delay_line #(.WIDTH(IN_WIDTH), .DEPTH(i)) u_dly (
                .clk(clk), .rst_n(rst_n), .en(1'b1),
                .d_in(data_b[i]), .d_out(b_conn[0][i])
            );
        end
    endgenerate

    // PE array — each PE wired to its own dedicated en/clear FF
    genvar r, c;
    generate
        for (r = 0; r < N; r++) begin : ROW
            for (c = 0; c < N; c++) begin : COL
                pe #(.IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pe (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .en       (en_all_bus  [r][c]),
                    .clear    (clear_pe_bus[r][c]),
                    .is_signed(is_signed),
                    .a_in (a_conn[r][c]),
                    .b_in (b_conn[r][c]),
                    .a_out(a_conn[r][c+1]),
                    .b_out(b_conn[r+1][c]),
                    .c_out(result[r][c])
                );
            end
        end
    endgenerate

endmodule
