// =============================================================================
// FILE     : uart_tx.sv
// GROUP    : uart
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : 8N1 UART Transmitter with 16× oversampling.
//
// OPERATION :
//   IDLE  — TX line held high (marking).  Waits for tx_start_i pulse.
//   START — Drives TX low for 16 sample ticks (one start bit).
//   DATA  — Shifts out b_reg[0] for 16 ticks per bit, LSB first.
//           After each bit, b_reg is right-shifted by 1.
//   STOP  — Drives TX high for 16 ticks; asserts tx_done_o for 1 cycle.
//
// DEPENDENCIES :
//   pkg/uart_pkg.sv        (uart_pkg::state_t)
//   primitives/adders.sv   (adder_4bit_struct, adder_3bit_struct)
// =============================================================================
`timescale 1ns/1ps

module uart_tx
    import uart_pkg::*;
(
    input  logic       clk_i,
    input  logic       rst_i,        // Synchronous reset, active-high
    input  logic       s_tick_i,
    input  logic       tx_start_i,
    input  logic [7:0] data_i,
    output logic       tx_done_o,
    output logic       tx_o
);
    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    state_t     state_reg, state_next;
    logic [3:0] s_cnt_reg, s_cnt_next, s_cnt_plus1;
    logic [2:0] n_cnt_reg, n_cnt_next, n_cnt_plus1;
    logic [7:0] b_reg, b_next;
    logic       tx_next;
    logic       unused_c1, unused_c2;

    logic s_is_15, n_is_7;
    assign s_is_15 = s_cnt_reg[3] & s_cnt_reg[2] & s_cnt_reg[1] & s_cnt_reg[0];
    assign n_is_7  = n_cnt_reg[2] & n_cnt_reg[1] & n_cnt_reg[0];

    // -------------------------------------------------------------------------
    // Structural incrementers
    // -------------------------------------------------------------------------
    adder_4bit_struct u_add_s (
        .a(s_cnt_reg), .b(4'b0001), .ci(1'b0),
        .sum(s_cnt_plus1), .co(unused_c1)
    );
    adder_3bit_struct u_add_n (
        .a(n_cnt_reg), .b(3'b001), .ci(1'b0),
        .sum(n_cnt_plus1), .co(unused_c2)
    );

    // -------------------------------------------------------------------------
    // Next-state / output logic (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        state_next = state_reg;
        s_cnt_next = s_cnt_reg;
        n_cnt_next = n_cnt_reg;
        b_next     = b_reg;
        tx_next    = 1'b1;
        tx_done_o  = 1'b0;

        case (state_reg)
            IDLE: begin
                tx_next = 1'b1;
                if (tx_start_i) begin
                    state_next = START;
                    s_cnt_next = 4'b0;
                    b_next     = data_i;
                end
            end
            START: begin
                tx_next = 1'b0;
                if (s_tick_i) begin
                    if (s_is_15) begin
                        state_next = DATA;
                        s_cnt_next = 4'b0;
                        n_cnt_next = 3'b0;
                    end else
                        s_cnt_next = s_cnt_plus1;
                end
            end
            DATA: begin
                tx_next = b_reg[0];
                if (s_tick_i) begin
                    if (s_is_15) begin
                        s_cnt_next = 4'b0;
                        b_next     = {1'b0, b_reg[7:1]};
                        if (n_is_7) state_next = STOP;
                        else        n_cnt_next = n_cnt_plus1;
                    end else
                        s_cnt_next = s_cnt_plus1;
                end
            end
            STOP: begin
                tx_next = 1'b1;
                if (s_tick_i) begin
                    if (s_is_15) begin
                        state_next = IDLE;
                        tx_done_o  = 1'b1;
                    end else
                        s_cnt_next = s_cnt_plus1;
                end
            end
            default: state_next = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // State and data registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_reg <= IDLE;
            s_cnt_reg <= 4'b0;
            n_cnt_reg <= 3'b0;
            b_reg     <= 8'b0;
            tx_o      <= 1'b1;
        end else begin
            state_reg <= state_next;
            s_cnt_reg <= s_cnt_next;
            n_cnt_reg <= n_cnt_next;
            b_reg     <= b_next;
            tx_o      <= tx_next;
        end
    end

endmodule
