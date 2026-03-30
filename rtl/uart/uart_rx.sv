// =============================================================================
// FILE     : uart_rx.sv
// GROUP    : uart
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : 8N1 UART Receiver with 16× oversampling.
//
// OPERATION :
//   IDLE  — Wait for RX to go low (start-bit falling edge).
//   START — Count 8 sample ticks to reach the centre of the start bit.
//   DATA  — Sample each of the 8 data bits at tick 15 (centre of bit cell).
//           Bits shifted in LSB-first into b_reg.
//   STOP  — Wait one full bit period; assert rx_done_o for one clock
//           when the stop bit is confirmed.
//
// TIMING :
//   Each bit cell = 16 s_tick pulses.
//   Start-bit centre sampled at tick 7 (mid-point).
//   Subsequent bits sampled at every 16th tick thereafter.
//
// DEPENDENCIES :
//   pkg/uart_pkg.sv            (uart_pkg::state_t)
//   primitives/adders.sv       (adder_4bit_struct, adder_3bit_struct,
//                               synchronizer)
// =============================================================================
`timescale 1ns/1ps

module uart_rx
    import uart_pkg::*;
(
    input  logic       clk_i,
    input  logic       rst_i,       // Synchronous reset, active-high
    input  logic       s_tick_i,
    input  logic       rx_i,        // UART RX pin (asynchronous)
    output logic [7:0] dout_o,
    output logic       rx_done_o
);
    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    state_t     state_reg, state_next;
    logic       rx_sync;
    logic [3:0] s_cnt_reg, s_cnt_next, s_cnt_plus1;
    logic [2:0] n_cnt_reg, n_cnt_next, n_cnt_plus1;
    logic [7:0] b_reg, b_next;
    logic       unused_c1, unused_c2;

    // Combinational terminal-count decoders
    logic s_is_7, s_is_15, n_is_7;
    assign s_is_7  = ~s_cnt_reg[3] & s_cnt_reg[2] & s_cnt_reg[1] & s_cnt_reg[0];
    assign s_is_15 =  s_cnt_reg[3] & s_cnt_reg[2] & s_cnt_reg[1] & s_cnt_reg[0];
    assign n_is_7  =  n_cnt_reg[2] & n_cnt_reg[1] & n_cnt_reg[0];

    // -------------------------------------------------------------------------
    // 2-FF synchronizer for the asynchronous RX pin
    // -------------------------------------------------------------------------
    synchronizer u_sync (
        .clk(clk_i), .rst_n(~rst_i),
        .in_async(rx_i), .out_sync(rx_sync)
    );

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
        rx_done_o  = 1'b0;

        case (state_reg)
            IDLE: begin
                if (!rx_sync) begin
                    state_next = START;
                    s_cnt_next = 4'b0;
                end
            end
            START: begin
                if (s_tick_i) begin
                    if (s_is_7) begin
                        state_next = DATA;
                        s_cnt_next = 4'b0;
                        n_cnt_next = 3'b0;
                    end else
                        s_cnt_next = s_cnt_plus1;
                end
            end
            DATA: begin
                if (s_tick_i) begin
                    if (s_is_15) begin
                        s_cnt_next = 4'b0;
                        b_next     = {rx_sync, b_reg[7:1]};   // LSB-first
                        if (n_is_7) state_next = STOP;
                        else        n_cnt_next = n_cnt_plus1;
                    end else
                        s_cnt_next = s_cnt_plus1;
                end
            end
            STOP: begin
                if (s_tick_i) begin
                    if (s_is_15) begin
                        state_next = IDLE;
                        rx_done_o  = 1'b1;
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
        end else begin
            state_reg <= state_next;
            s_cnt_reg <= s_cnt_next;
            n_cnt_reg <= n_cnt_next;
            b_reg     <= b_next;
        end
    end

    assign dout_o = b_reg;

endmodule
