#!/usr/bin/env bash
# =============================================================================
# FILE     : sim.sh
# PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
#
# PURPOSE  : One-shot ModelSim / QuestaSim compile + simulate script.
#            Run from the project root directory:
#              chmod +x scripts/sim.sh
#              ./scripts/sim.sh
#
# REQUIRES : vlog / vsim on PATH (ModelSim or QuestaSim)
# =============================================================================

set -e

WORK_LIB=work
TB_TOP=tb_system_top          # Change to target testbench module name
SIM_TIME="+10000us"

echo "============================================================"
echo "  Compiling RTL"
echo "============================================================"

vlib $WORK_LIB 2>/dev/null || true
vmap work $WORK_LIB

# Compile in dependency order
vlog -sv -work $WORK_LIB \
    rtl/pkg/uart_pkg.sv \
    rtl/primitives/gates.sv \
    rtl/primitives/adders.sv \
    rtl/primitives/fifo_sync_structured.sv \
    rtl/primitives/ksa_32bit.sv \
    rtl/multiplier/booth_wallace_8x8.sv \
    rtl/systolic/delay_line.sv \
    rtl/systolic/pe.sv \
    rtl/systolic/global_controller.sv \
    rtl/systolic/systolic_array_top.sv \
    rtl/uart/uart_rx.sv \
    rtl/uart/uart_tx.sv \
    rtl/uart/uart_top.sv \
    rtl/top/system_top.sv \
    sim/tb/${TB_TOP}.sv

echo ""
echo "============================================================"
echo "  Running simulation : $TB_TOP"
echo "============================================================"

vsim -batch -do "
    vsim -t 1ns work.$TB_TOP;
    run $SIM_TIME;
    quit -f
" 2>&1 | tee sim/sim.log

echo ""
echo "Simulation complete. Log: sim/sim.log"

rm -rf $WORK_LIB
vlib $WORK_LIB
vmap work $WORK_LIB
