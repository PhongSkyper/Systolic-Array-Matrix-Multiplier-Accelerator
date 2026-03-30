# =============================================================================
# FILE     : system_top.sdc
# PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
# TARGET   : Terasic DE10-Standard (Cyclone V 5CSXFC6D6F31C6N)
#
# CLOCK    : 50 MHz system clock on PIN_AF14
# TARGET   : Fmax ≥ 125 MHz (8 ns budget per pipeline stage)
#
# PIPELINE STAGE BUDGETS :
#   Stage 1a (Booth+PPG+Align)  : ~2–3 ns
#   Stage 1b (Wallace Tree)     : ~3–4 ns
#   Stage 1c (KSA-16)           : ~2–3 ns
#   Stage 2  (KSA-32 Accum)     : ~3–4 ns
# =============================================================================

# -----------------------------------------------------------------------------
# Primary clock — 50 MHz on DE10-Standard
# -----------------------------------------------------------------------------
create_clock -name clk -period 20.000 [get_ports clk]

# -----------------------------------------------------------------------------
# Generated / virtual clocks
# (No PLLs in this design — single clock domain)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Input delays
#   UART RX is asynchronous; the 2-FF synchronizer in uart_rx handles
#   metastability. Constrain as false path after the synchronizer output.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports rx]
set_input_delay  -clock clk -max 2.0 [get_ports {is_signed rst_n}]
set_input_delay  -clock clk -min 0.5 [get_ports {is_signed rst_n}]

# -----------------------------------------------------------------------------
# Output delays
# -----------------------------------------------------------------------------
set_output_delay -clock clk -max 2.0 [get_ports tx]
set_output_delay -clock clk -min 0.5 [get_ports tx]

# -----------------------------------------------------------------------------
# Multicycle paths
#   The delay_line skew registers at DEPTH=0 are combinational wires;
#   DEPTH > 0 stages are single-cycle (no multicycle paths in this design).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# False paths
#   is_signed is a static configuration input — set once before operation.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports is_signed]

# -----------------------------------------------------------------------------
# Clock uncertainty (jitter budget for Cyclone V internal oscillator)
# -----------------------------------------------------------------------------
set_clock_uncertainty -setup 0.2 [get_clocks clk]
set_clock_uncertainty -hold  0.1 [get_clocks clk]

# -----------------------------------------------------------------------------
# Derive PLL clocks (none in this design — placeholder for future PLL use)
# -----------------------------------------------------------------------------
# derive_pll_clocks
derive_clock_uncertainty
