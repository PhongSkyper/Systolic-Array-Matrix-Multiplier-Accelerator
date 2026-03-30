// =============================================================================
// FILE     : system_top.sv
// GROUP    : top
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Chip top-level — connects uart_top and systolic_array_top via
//            a 3-phase control FSM.
//
// DATA PROTOCOL (UART) :
//   Host → FPGA : 2 × N × N bytes
//     Bytes 0 .. N²-1      : matrix A, row-major  (A[0][0], A[0][1], ...)
//     Bytes N² .. 2N²-1    : matrix B, row-major
//   FPGA → Host : N × N × 4 bytes
//     N² results, row-major, LSB-first (4 bytes per result)
//
// FSM PHASES :
//   ── Phase 1 : Receive ──────────────────────────────────────────────────
//   ST_IDLE        Reset all pointers; jump to ST_RX_CHECK.
//   ST_RX_CHECK    Poll RX FIFO; if not empty, issue read strobe.
//   ST_RX_WAIT1/2/3  Pipeline delay for FIFO registered output.
//   ST_RX_SAVE     Store byte into A_buf or B_buf; advance pointers.
//   ST_RX_WAIT4/5/6  Guard cycles before next RX read.
//
//   ── Phase 2 : Compute ──────────────────────────────────────────────────
//   ST_SYS_START   Assert sys_start one cycle; go to ST_SYS_PUMP.
//   ST_SYS_PUMP    Feed column-slice k of A and row-slice k of B.
//                  Runs N cycles (t_cnt = 0 .. N-1).
//   ST_SYS_CALC    Wait for sys_done from systolic_array_top.
//
//   ── Phase 3 : Transmit ─────────────────────────────────────────────────
//   ST_TX_CHECK    Write next byte into TX FIFO when space available.
//   ST_TX_WAIT1..5 Guard cycles for FIFO / uart_tx settling.
//   ST_TX_DONE     Advance tx_byte / tx_col / tx_row; loop or finish.
//
// BUG FIXES :
//   BUG 2 — Data pump starts SAME cycle as sys_start (ST_SYS_START →
//            ST_SYS_PUMP directly); global_controller IDLE→INIT→COMPUTE
//            timing aligned to first valid pump cycle.
//   BUG 3 — Consequence of BUG 2: pump covers exactly N slices (t_cnt 0..N-1).
//   BUG 7 — tx_din driven by always_comb; valid in SAME cycle as tx_wr.
//
// DEPENDENCIES :
//   pkg/uart_pkg.sv
//   uart/uart_top.sv
//   systolic/systolic_array_top.sv
// =============================================================================
`timescale 1ns/1ps

module system_top #(
    parameter int N         = 8,
    parameter int IN_WIDTH  = 8,
    parameter int ACC_WIDTH = 32
)(
    input  logic clk,
    input  logic rst_n,
    input  logic rx,
    input  logic is_signed,
    output logic tx
);
    import uart_pkg::*;

    // -------------------------------------------------------------------------
    // Compile-time helper : ceiling log2
    // -------------------------------------------------------------------------
    function automatic integer f_clog2(input integer n);
        integer v;
        begin
            v = n - 1;
            for (f_clog2 = 0; v > 0; f_clog2 = f_clog2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam int PTR_WIDTH        = f_clog2(N);
    localparam int BYTES_PER_RESULT = ACC_WIDTH / 8;
    localparam int TX_BYTE_W        = f_clog2(BYTES_PER_RESULT);

    // -------------------------------------------------------------------------
    // Sub-module I/O
    // -------------------------------------------------------------------------
    logic [7:0] rx_dout;
    logic       rx_rd, rx_empty;
    logic [7:0] tx_din;
    logic       tx_wr, tx_full;

    logic        sys_start, sys_done;
    logic [IN_WIDTH-1:0]  data_a [0:N-1];
    logic [IN_WIDTH-1:0]  data_b [0:N-1];
    logic [ACC_WIDTH-1:0] result [0:N-1][0:N-1];

    uart_top u_uart (
        .clk(clk), .rst_n(rst_n), .rx(rx), .tx(tx),
        .tx_din(tx_din), .tx_wr(tx_wr), .tx_full(tx_full),
        .rx_dout(rx_dout), .rx_rd(rx_rd), .rx_empty(rx_empty)
    );

    systolic_array_top #(.N(N), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_sys (
        .clk(clk), .rst_n(rst_n),
        .start(sys_start), .is_signed(is_signed),
        .data_a(data_a), .data_b(data_b),
        .result(result), .done(sys_done)
    );

    // -------------------------------------------------------------------------
    // On-chip matrix buffers
    // -------------------------------------------------------------------------
    logic [IN_WIDTH-1:0] A_buf [0:N-1][0:N-1];
    logic [IN_WIDTH-1:0] B_buf [0:N-1][0:N-1];

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    typedef enum logic [4:0] {
        ST_IDLE,
        // Phase 1 — receive
        ST_RX_CHECK, ST_RX_WAIT1, ST_RX_WAIT2, ST_RX_WAIT3, ST_RX_SAVE, ST_RX_WAIT4, ST_RX_WAIT5, ST_RX_WAIT6,
        // Phase 2 — compute
        ST_SYS_START, ST_SYS_WAIT1, ST_SYS_WAIT2, ST_SYS_WAIT3, ST_SYS_PUMP, ST_SYS_CALC,
        // Phase 3 — transmit
        ST_TX_CHECK, ST_TX_WAIT1, ST_TX_WAIT2, ST_TX_WAIT3, ST_TX_WAIT4, ST_TX_WAIT5, ST_TX_DONE
    } sys_state_t;
    sys_state_t state;

    // -------------------------------------------------------------------------
    // Datapath pointers
    // -------------------------------------------------------------------------
    logic [PTR_WIDTH-1:0] rx_row, rx_col;
    logic                 rx_mat;
    logic [PTR_WIDTH-1:0] t_cnt;
    logic [PTR_WIDTH-1:0] tx_row, tx_col;
    logic [TX_BYTE_W-1:0] tx_byte;

    // -------------------------------------------------------------------------
    // Combinational data feed to systolic array
    // -------------------------------------------------------------------------
    always_comb begin
        for (int ii = 0; ii < N; ii++) begin
            // CHỈ bơm dữ liệu thật khi đang ở ST_SYS_PUMP
            if (state == ST_SYS_PUMP) begin
                data_a[ii] = A_buf[ii][t_cnt];
                data_b[ii] = B_buf[t_cnt][ii];
            end else begin
                // BẮT BUỘC bơm số 0 trong mọi trạng thái khác (đặc biệt là lúc xả pipeline)
                data_a[ii] = '0;
                data_b[ii] = '0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // tx_din mux — selects correct byte lane of current result word
    // BUG 7 FIX: fully combinational so tx_din is valid when tx_wr asserts
    // -------------------------------------------------------------------------
    logic [ACC_WIDTH-1:0] cur_res;
    assign cur_res = result[tx_row][tx_col];

    always_comb begin
        tx_din = cur_res[7:0];
        for (int b = 0; b < BYTES_PER_RESULT; b++) begin
            if (tx_byte == TX_BYTE_W'(b))
                tx_din = cur_res[b*8 +: 8];
        end
    end

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            sys_start <= 1'b0;
            rx_rd     <= 1'b0;
            tx_wr     <= 1'b0;
            rx_row <= '0; rx_col <= '0; rx_mat <= 1'b0;
            t_cnt  <= '0;
            tx_row <= '0; tx_col <= '0; tx_byte <= '0;
        end else begin
            sys_start <= 1'b0;
            rx_rd     <= 1'b0;
            tx_wr     <= 1'b0;

            case (state)
                // ── IDLE ─────────────────────────────────────────────────────
                ST_IDLE: begin
                    rx_row <= '0; rx_col <= '0; rx_mat <= 1'b0;
                    tx_row <= '0; tx_col <= '0; tx_byte <= '0;
                    t_cnt  <= '0;
                    state  <= ST_RX_CHECK;
                end

                // ═════════════════════════════════════════════════════════════
                // PHASE 1 — Receive
                // ═════════════════════════════════════════════════════════════
                ST_RX_CHECK: begin
                    if (!rx_empty) begin
                        rx_rd <= 1'b1;
                        state <= ST_RX_WAIT1;
                    end
                end
                ST_RX_WAIT1: state <= ST_RX_WAIT2;
                ST_RX_WAIT2: state <= ST_RX_WAIT3;
                ST_RX_WAIT3: state <= ST_RX_SAVE;

                ST_RX_SAVE: begin
                    if (!rx_mat) A_buf[rx_row][rx_col] <= rx_dout;
                    else         B_buf[rx_row][rx_col] <= rx_dout;

                    if (rx_col == PTR_WIDTH'(N - 1)) begin
                        rx_col <= '0;
                        if (rx_row == PTR_WIDTH'(N - 1)) begin
                            rx_row <= '0;
                            if (rx_mat) state  <= ST_SYS_START;
                            else begin
                                rx_mat <= 1'b1;
                                state  <= ST_RX_WAIT4;
                            end
                        end else begin
                            rx_row <= rx_row + 1'b1;
                            state  <= ST_RX_WAIT4;
                        end
                    end else begin
                        rx_col <= rx_col + 1'b1;
                        state  <= ST_RX_WAIT4;
                    end
                end

                ST_RX_WAIT4: state <= ST_RX_WAIT5;
                ST_RX_WAIT5: state <= ST_RX_WAIT6;
                ST_RX_WAIT6: state <= ST_RX_CHECK;

                // ═════════════════════════════════════════════════════════════
                // PHASE 2 — Compute
                // ═════════════════════════════════════════════════════════════
                ST_SYS_START: begin
                    sys_start <= 1'b1;
                    t_cnt     <= '0;
                    state     <= ST_SYS_WAIT1;  // Nhảy sang chờ thay vì Pump ngay
                end
                
                // Delay 3 chu kỳ để tín hiệu en_all_bus kịp kích hoạt toàn mảng PE
                ST_SYS_WAIT1: state <= ST_SYS_WAIT2;
                ST_SYS_WAIT2: state <= ST_SYS_WAIT3;
                ST_SYS_WAIT3: state <= ST_SYS_PUMP;

                // Bơm N lát cắt (k=0 đến N-1)
                ST_SYS_PUMP: begin
                    if (t_cnt == PTR_WIDTH'(N - 1))
                        state <= ST_SYS_CALC;      
                    else
                        t_cnt <= t_cnt + 1'b1;
                end
                
                ST_SYS_CALC: begin
                    if (sys_done) state <= ST_TX_CHECK;
                end

                // ═════════════════════════════════════════════════════════════
                // PHASE 3 — Transmit
                // ═════════════════════════════════════════════════════════════
                ST_TX_CHECK: begin
                    if (!tx_full) begin
                        tx_wr <= 1'b1;
                        state <= ST_TX_WAIT1;
                    end
                end
                ST_TX_WAIT1: state <= ST_TX_WAIT2;
                ST_TX_WAIT2: state <= ST_TX_WAIT3;
                ST_TX_WAIT3: state <= ST_TX_WAIT4;
                ST_TX_WAIT4: state <= ST_TX_WAIT5;
                ST_TX_WAIT5: state <= ST_TX_DONE;

                ST_TX_DONE: begin
                    if (tx_byte == TX_BYTE_W'(BYTES_PER_RESULT - 1)) begin
                        tx_byte <= '0;
                        if (tx_col == PTR_WIDTH'(N - 1)) begin
                            tx_col <= '0;
                            if (tx_row == PTR_WIDTH'(N - 1)) begin
                                tx_row <= '0;
                                state  <= ST_IDLE;
                            end else begin
                                tx_row <= tx_row + 1'b1;
                                state  <= ST_TX_CHECK;
                            end
                        end else begin
                            tx_col <= tx_col + 1'b1;
                            state  <= ST_TX_CHECK;
                        end
                    end else begin
                        tx_byte <= tx_byte + 1'b1;
                        state   <= ST_TX_CHECK;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
