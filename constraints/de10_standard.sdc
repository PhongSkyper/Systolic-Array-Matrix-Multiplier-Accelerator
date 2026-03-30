# =============================================================================
# FILE     : system_top.sdc
# PROJECT  : 8x8 Systolic Matrix Multiplier with UART Interface
# TARGET   : Terasic DE10-Standard (Cyclone V 5CSXFC6D6F31C6N)
# TOOL     : Quartus Prime Lite 25.1
#
# HOW TO USE :
#   Quartus: Assignments → Settings → Timing Analyzer → SDC Files → Add this file
#   Then run: Processing → Start → Start Timing Analysis
#
# REVISION HISTORY :
#   v1.0 — Initial constraints (50MHz clock, I/O delays, false paths)
#   v1.1 — Multicycle relaxation for TX FIFO RAM address and False path TX/RX
#   v2.0 — OVERCONSTRAINING applied. Clock period forced to 6.666ns (150MHz) 
#          to push Fitter for maximum performance (finding true Fmax).
# =============================================================================

# -----------------------------------------------------------------------------
# 1. PRIMARY CLOCK — OVERCONSTRAINED TO 150 MHz
# -----------------------------------------------------------------------------
create_clock -name {CLOCK_50} \
             -period 6.666   \
             -waveform {0.000 3.333} \
             [get_ports {clk}]

# -----------------------------------------------------------------------------
# 2. CLOCK UNCERTAINTY
# -----------------------------------------------------------------------------
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] \
                      -rise_to   [get_clocks {CLOCK_50}] \
                      -setup 0.170
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] \
                      -rise_to   [get_clocks {CLOCK_50}] \
                      -hold  0.170

# -----------------------------------------------------------------------------
# 3. ASYNC INPUTS — all declared as false paths
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {rx}]
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {is_signed}]

# -----------------------------------------------------------------------------
# 4. ASYNC OUTPUT — tx declared false path
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {tx}]

# -----------------------------------------------------------------------------
# 5. MULTICYCLE PATHS — TX FIFO address path (Relaxed Setup)
# -----------------------------------------------------------------------------

# tx_byte → TX FIFO write address / data
set_multicycle_path -setup -end -from [get_registers {*tx_byte*}] \
                    -to   [get_registers {*tx_fifo*}] 2
set_multicycle_path -hold  -end -from [get_registers {*tx_byte*}] \
                    -to   [get_registers {*tx_fifo*}] 1

# tx_row → TX FIFO write address
set_multicycle_path -setup -end -from [get_registers {*tx_row*}] \
                    -to   [get_registers {*tx_fifo*}] 2
set_multicycle_path -hold  -end -from [get_registers {*tx_row*}] \
                    -to   [get_registers {*tx_fifo*}] 1

# tx_col → TX FIFO write address
set_multicycle_path -setup -end -from [get_registers {*tx_col*}] \
                    -to   [get_registers {*tx_fifo*}] 2
set_multicycle_path -hold  -end -from [get_registers {*tx_col*}] \
                    -to   [get_registers {*tx_fifo*}] 1

# sum_reg (kết quả mảng CSA) → TX FIFO data input
set_multicycle_path -setup -end -from [get_registers {*sum_reg*}] \
                    -to   [get_registers {*tx_fifo*}] 2
set_multicycle_path -hold  -end -from [get_registers {*sum_reg*}] \
                    -to   [get_registers {*tx_fifo*}] 1

# carry_reg (kết quả mảng CSA) → TX FIFO data input
set_multicycle_path -setup -end -from [get_registers {*carry_reg*}] \
                    -to   [get_registers {*tx_fifo*}] 2
set_multicycle_path -hold  -end -from [get_registers {*carry_reg*}] \
                    -to   [get_registers {*tx_fifo*}] 1

# -----------------------------------------------------------------------------
# 6. DERIVED CLOCKS (Placeholder)
# -----------------------------------------------------------------------------
# create_generated_clock -name {clk_fast} \
#                        -source [get_pins {u_pll|inclk[0]}] \
#                        -multiply_by 2 \
#                        [get_pins {u_pll|outclk[0]}]