// =============================================================================
// FILE     : fifo_sync_structured.sv
// GROUP    : primitives
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Single-clock synchronous FIFO with parameterised width and depth.
//            Used as the RX-FIFO and TX-FIFO inside uart_top.
//
// PARAMETERS :
//   W — data width in bits         (default 8)
//   L — FIFO depth in entries      (default 8 — keep as power-of-2)
//
// INTERFACE :
//   write_en / data_in   push when write_en=1 and !full
//   read_en  / data_out  pop  when read_en=1  and !empty  (1-cycle latency)
//   full / empty         combinational status flags
//
// BEHAVIOUR :
//   • Simultaneous valid read + write: both happen, count unchanged.
//   • Pointer wrap is implicit — $clog2(L)-bit counters wrap naturally
//     when L is a power of 2.
//
// FIX vs original :
//   Pointer and count widths now derived from L via $clog2 so the module
//   scales correctly for any power-of-2 depth without manual adjustment.
// =============================================================================
`timescale 1ns/1ps

module fifo_sync_structured #(
    parameter int W = 8,   // Data width (bits)
    parameter int L = 8    // FIFO depth  (entries) — must be power-of-2
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         write_en,
    input  logic         read_en,
    input  logic [W-1:0] data_in,
    output logic [W-1:0] data_out,
    output logic         full,
    output logic         empty
);
    // -------------------------------------------------------------------------
    // Storage and control
    //   cnt    : entry count, 0 .. L  → needs $clog2(L)+1 bits
    //   wr_ptr / rd_ptr : circular pointers, 0 .. L-1 → $clog2(L) bits
    // -------------------------------------------------------------------------
    localparam int PTR_W = $clog2(L);      // e.g. 3 for L=8, 4 for L=16
    localparam int CNT_W = PTR_W + 1;      // one extra bit for full/empty

    logic [W-1:0]     mem    [0:L-1];
    logic [CNT_W-1:0] cnt;
    logic [PTR_W-1:0] wr_ptr, rd_ptr;

    assign empty = (cnt == '0);
    assign full  = (cnt == L[CNT_W-1:0]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= '0;
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            data_out <= '0;
        end else begin
            // Write port
            if (write_en && !full) begin
                mem[wr_ptr] <= data_in;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            // Read port (registered output — 1-cycle read latency)
            if (read_en && !empty) begin
                data_out <= mem[rd_ptr];
                rd_ptr   <= rd_ptr + 1'b1;
            end
            // Entry counter
            if      (write_en && !full  && !(read_en  && !empty)) cnt <= cnt + 1'b1;
            else if (read_en  && !empty && !(write_en && !full))  cnt <= cnt - 1'b1;
            // Simultaneous valid R+W: count unchanged (both branches false)
        end
    end
endmodule
