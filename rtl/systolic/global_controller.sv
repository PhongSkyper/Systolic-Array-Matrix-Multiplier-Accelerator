// =============================================================================
// FILE     : global_controller.sv
// GROUP    : systolic
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Moore FSM controller for one matrix-multiplication operation.
//
// TIMING MODEL (output-stationary, N×N array, v4.0) :
//   TOTAL_CYCLES = 3*N + 3
// =============================================================================
`timescale 1ns/1ps

module global_controller #(
    parameter int N = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic en_all_bus  [0:N-1][0:N-1],
    output logic clear_pe_bus[0:N-1][0:N-1],
    output logic done
);
    typedef enum logic [1:0] {
        S_IDLE    = 2'd0,
        S_INIT    = 2'd1,
        S_COMPUTE = 2'd2,
        S_DONE    = 2'd3
    } state_t;

    state_t current_state, next_state;

    localparam int TOTAL_CYCLES = 3 * N + 3;

    logic [7:0] counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= S_IDLE;
        else        current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            S_IDLE    : if (start)                                  next_state = S_INIT;
            S_INIT    :                                             next_state = S_COMPUTE;
            S_COMPUTE : if (counter >= TOTAL_CYCLES - 1)            next_state = S_DONE;
            S_DONE    :                                             next_state = S_IDLE;
            default   :                                             next_state = S_IDLE;
        endcase
    end

    logic en_all_comb;
    logic clear_pe_comb;

    always_comb begin
        en_all_comb   = 1'b0;
        clear_pe_comb = 1'b0;
        done          = 1'b0;
        case (current_state)
            S_INIT    : clear_pe_comb = 1'b1;
            S_COMPUTE : en_all_comb   = 1'b1;
            S_DONE    : done          = 1'b1;
            default   : ;
        endcase
    end

    genvar r, c;
    generate
        for (r = 0; r < N; r++) begin : EN_ROW
            for (c = 0; c < N; c++) begin : EN_COL
                (* keep *) always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) en_all_bus[r][c] <= 1'b0;
                    else        en_all_bus[r][c] <= en_all_comb;
                end
            end
        end
    endgenerate

    generate
        for (r = 0; r < N; r++) begin : CLR_ROW
            for (c = 0; c < N; c++) begin : CLR_COL
                (* keep *) always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) clear_pe_bus[r][c] <= 1'b0;
                    else        clear_pe_bus[r][c] <= clear_pe_comb;
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            counter <= 8'd0;
        else if (current_state == S_COMPUTE)
            counter <= counter + 8'd1;
        else
            counter <= 8'd0;
    end

endmodule