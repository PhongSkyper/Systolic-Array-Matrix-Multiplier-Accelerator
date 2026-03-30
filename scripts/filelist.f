# =============================================================================
# FILE     : filelist.f
# PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
# TARGET   : Terasic DE10-Standard (Cyclone V 5CSXFC6D6F31C6N)
#
# PURPOSE  : Ordered file list for Xcelium / VCS / ModelSim compilation.
#            Files MUST be compiled in this exact order (top-to-bottom)
#            to satisfy package and module dependency requirements.
#
# USAGE (Xcelium) :
#   xrun -64bit -sv -f filelist.f -access +rwc
# =============================================================================

# 1. Package — must be compiled first (all UART modules import uart_pkg)
/home/yellow/ee3165_23/systolic_array_8x8/rtl/pkg/uart_pkg.sv

# 2. Gate-level primitives
/home/yellow/ee3165_23/systolic_array_8x8/rtl/primitives/gates.sv

# 3. Structural adders + synchronizer
/home/yellow/ee3165_23/systolic_array_8x8/rtl/primitives/adders.sv

# 4. Synchronous FIFO
/home/yellow/ee3165_23/systolic_array_8x8/rtl/primitives/fifo_sync_structured.sv

# 5. Kogge-Stone 32-bit adder
/home/yellow/ee3165_23/systolic_array_8x8/rtl/primitives/ksa_32bit.sv

# 6. Booth-Wallace 8×8 multiplier
/home/yellow/ee3165_23/systolic_array_8x8/rtl/multiplier/booth_wallace_8x8.sv

# 7. Delay line (skew registers for systolic array input)
/home/yellow/ee3165_23/systolic_array_8x8/rtl/systolic/delay_line.sv

# 8. Processing Element (CSA Architecture)
/home/yellow/ee3165_23/systolic_array_8x8/rtl/systolic/pe.sv

# 9. Global controller (Moore FSM + RTL fanout tree)
/home/yellow/ee3165_23/systolic_array_8x8/rtl/systolic/global_controller.sv

# 10. Systolic array top (8×8 PE array + delay lines + controller)
/home/yellow/ee3165_23/systolic_array_8x8/rtl/systolic/systolic_array_top.sv

# 11. UART Receiver
/home/yellow/ee3165_23/systolic_array_8x8/rtl/uart/uart_rx.sv

# 12. UART Transmitter
/home/yellow/ee3165_23/systolic_array_8x8/rtl/uart/uart_tx.sv

# 13. UART top (baud gen + FIFOs + TX FSM)
/home/yellow/ee3165_23/systolic_array_8x8/rtl/uart/uart_top.sv

# 14. Chip top (UART ↔ systolic array FSM)
/home/yellow/ee3165_23/systolic_array_8x8/rtl/top/system_top.sv

# 15. Testbench (Chạy mô phỏng thì uncomment dòng dưới và trỏ đúng tên file)
/home/yellow/ee3165_23/systolic_array_8x8/tb/tb_systolic_direct.sv