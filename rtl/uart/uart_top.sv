// =============================================================================
// FILE     : uart_top.sv
// GROUP    : uart
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : UART peripheral wrapper — integrates baud-rate generator,
//            uart_rx, uart_tx, two 8-entry FIFOs, and a TX controller FSM.
//
// BLOCK DIAGRAM :
//
//                 ┌──────────────────────────────────────────┐
//   rx ──────────►│ uart_rx ──► RX FIFO (8×8b) ──► rx_dout │
//                 │                                          │
//                 │   Baud-Rate Generator (9-bit counter)    │
//                 │                                          │
//   tx_din ──────►│ TX FIFO (8×8b) ──► TX Ctrl ──► uart_tx │──► tx
//                 └──────────────────────────────────────────┘
//
// BAUD-RATE GENERATOR :
//   9-bit counter increments each clock.
//   Terminal count = BAUD_DIVISOR - 1 = 324.
//   s_tick asserted for one clock when counter reaches 324, then resets.
//   → s_tick frequency = 50 MHz / 325 = 153,846 Hz = 9600 × 16 ✓
//
// TX CONTROLLER FSM :
//   T_IDLE      — Monitor TX FIFO; pop a byte when available.
//   T_READ      — 1-cycle wait for FIFO registered-output to settle.
//   T_START_TX  — Assert tx_start_i to uart_tx for one cycle.
//   T_WAIT_DONE — Hold until uart_tx asserts tx_done_o.
//
// DEPENDENCIES :
//   pkg/uart_pkg.sv
//   primitives/adders.sv               (adder_9bit_struct)
//   primitives/fifo_sync_structured.sv
//   uart/uart_rx.sv
//   uart/uart_tx.sv
// =============================================================================
`timescale 1ns/1ps

module uart_top
    import uart_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic       tx,
    // TX-FIFO write port
    input  logic [7:0] tx_din,
    input  logic       tx_wr,
    output logic       tx_full,
    // RX-FIFO read port
    output logic [7:0] rx_dout,
    input  logic       rx_rd,
    output logic       rx_empty
);
    logic rst;
    assign rst = ~rst_n;   // uart_rx / uart_tx use active-high reset

    // =========================================================================
    // Baud-Rate Generator
    // =========================================================================
    logic [CNT_WIDTH-1:0] baud_cnt;
    logic                 s_tick;
    logic [CNT_WIDTH-1:0] baud_cnt_plus1;
    logic                 baud_cnt_cout;

    adder_9bit_struct u_add_baud (
        .a(baud_cnt), .b(9'b000_000_001), .ci(1'b0),
        .sum(baud_cnt_plus1), .co(baud_cnt_cout)
    );

    assign s_tick = (baud_cnt == CNT_WIDTH'(BAUD_DIVISOR - 1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      baud_cnt <= '0;
        else if (s_tick) baud_cnt <= '0;
        else             baud_cnt <= baud_cnt_plus1;
    end

    // =========================================================================
    // RX Path : uart_rx → RX FIFO
    // =========================================================================
    logic [7:0] rx_data_raw;
    logic       rx_done;
    logic       rx_fifo_full;

    uart_rx u_rx (
        .clk_i    (clk),
        .rst_i    (rst),
        .s_tick_i (s_tick),
        .rx_i     (rx),
        .dout_o   (rx_data_raw),
        .rx_done_o(rx_done)
    );

    fifo_sync_structured #(.W(8), .L(8)) u_rx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .write_en(rx_done),
        .read_en (rx_rd),
        .data_in (rx_data_raw),
        .data_out(rx_dout),
        .full    (rx_fifo_full),
        .empty   (rx_empty)
    );

    // =========================================================================
    // TX Path : TX FIFO → TX Controller FSM → uart_tx
    // =========================================================================
    logic [7:0] tx_fifo_dout;
    logic       tx_fifo_empty;
    logic       tx_fifo_rd;
    logic       tx_start;
    logic       tx_done;

    fifo_sync_structured #(.W(8), .L(8)) u_tx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .write_en(tx_wr),
        .read_en (tx_fifo_rd),
        .data_in (tx_din),
        .data_out(tx_fifo_dout),
        .full    (tx_full),
        .empty   (tx_fifo_empty)
    );

    uart_tx u_tx (
        .clk_i     (clk),
        .rst_i     (rst),
        .s_tick_i  (s_tick),
        .tx_start_i(tx_start),
        .data_i    (tx_fifo_dout),
        .tx_done_o (tx_done),
        .tx_o      (tx)
    );

    // =========================================================================
    // TX Controller FSM
    // =========================================================================
    typedef enum logic [1:0] {
        T_IDLE      = 2'd0,
        T_READ      = 2'd1,
        T_START_TX  = 2'd2,
        T_WAIT_DONE = 2'd3
    } tx_ctrl_t;

    tx_ctrl_t t_state, t_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) t_state <= T_IDLE;
        else        t_state <= t_next;
    end

    always_comb begin
        t_next     = t_state;
        tx_fifo_rd = 1'b0;
        tx_start   = 1'b0;
        case (t_state)
            T_IDLE: begin
                if (!tx_fifo_empty) begin
                    tx_fifo_rd = 1'b1;
                    t_next     = T_READ;
                end
            end
            T_READ:      t_next   = T_START_TX;
            T_START_TX: begin
                tx_start = 1'b1;
                t_next   = T_WAIT_DONE;
            end
            T_WAIT_DONE: if (tx_done) t_next = T_IDLE;
            default:     t_next   = T_IDLE;
        endcase
    end

endmodule
