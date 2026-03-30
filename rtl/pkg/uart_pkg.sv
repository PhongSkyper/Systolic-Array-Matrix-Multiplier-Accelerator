// =============================================================================
// FILE     : uart_pkg.sv
// GROUP    : pkg
// PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
//
// PURPOSE  : Shared constants and type definitions for the UART subsystem.
//            Must be compiled FIRST — all uart_rx / uart_tx modules import it.
//
// CONTENTS :
//   - BAUD_DIVISOR  : baud-rate generator terminal count
//   - CNT_WIDTH     : bit-width of the baud counter
//   - state_t       : one-hot FSM state encoding (IDLE / START / DATA / STOP)
//
// UART CONFIG : 50 MHz clock, 9600 baud, 16× oversampling
//   BAUD_DIVISOR = 50_000_000 / (9600 × 16) = 325.52 → 325
// =============================================================================
`timescale 1ns/1ps
package uart_pkg;
    // -------------------------------------------------------------------------
    // Baud-rate generator
    //   Counter counts 0 → BAUD_DIVISOR-1 (325 steps), then resets.
    //   One s_tick pulse is produced every 325 clock cycles ≈ 6.51 µs.
    // -------------------------------------------------------------------------
    localparam int BAUD_DIVISOR = 325;
    localparam int CNT_WIDTH    = 9;     // ceil(log2(325)) = 9
    // -------------------------------------------------------------------------
    // One-hot FSM state type (shared by uart_rx and uart_tx)
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE  = 4'b0001,   // Line idle — TX high, RX waiting for start bit
        START = 4'b0010,   // Start bit detected / being transmitted
        DATA  = 4'b0100,   // Shifting 8 data bits (LSB first)
        STOP  = 4'b1000    // Stop bit being checked / transmitted
    } state_t;
endpackage
