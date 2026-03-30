###############################################################################
# FILE   : synth.tcl
# TOOL   : Cadence Genus 21+
# PDK    : GPDK045 (45nm)
# DESIGN : system_top
# PURPOSE: Auto-sweep 8 PVT Corners, generating isolated reports/netlists
###############################################################################

set DESIGN   "system_top"
set RTL_DIR  "../rtl"
set LIB_DIR  "../lib/gpdk045/gpdk045_lib"
set RPT_DIR  "./reports"
set OUT_DIR  "./outputs"

# Danh sách 8 corners cần quét
set corners {
    slow_vdd1v0_basicCells_lvt
    slow_vdd1v0_basicCells_hvt
    slow_vdd1v2_basicCells_lvt
    slow_vdd1v2_basicCells_hvt
    fast_vdd1v2_basicCells_lvt
    fast_vdd1v2_basicCells_hvt
    fast_vdd1v0_basicCells_lvt
    fast_vdd1v0_basicCells_hvt
}

# Vòng lặp chạy tổng hợp cho từng corner
foreach corner $corners {
    puts "\n========================================================================="
    puts "  STARTING SYNTHESIS FOR CORNER: $corner"
    puts "=========================================================================\n"

    # 1. Tạo thư mục riêng cho corner hiện tại
    set C_RPT_DIR "${RPT_DIR}/${corner}"
    set C_OUT_DIR "${OUT_DIR}/${corner}"
    file mkdir $C_RPT_DIR
    file mkdir $C_OUT_DIR

    # 2. Xóa sạch thiết kế cũ trong RAM để tránh đụng độ module khi lặp lại
    catch { delete_obj [get_db designs *] }

    # 3. Nạp duy nhất 1 file thư viện của corner hiện tại
    set_db library "${LIB_DIR}/${corner}.lib"

    # 4. Đọc RTL
    read_hdl -sv ${RTL_DIR}/pkg/uart_pkg.sv
    read_hdl -sv ${RTL_DIR}/primitives/gates.sv
    read_hdl -sv ${RTL_DIR}/primitives/adders.sv
    read_hdl -sv ${RTL_DIR}/primitives/fifo_sync_structured.sv
    read_hdl -sv ${RTL_DIR}/primitives/ksa_32bit.sv
    read_hdl -sv ${RTL_DIR}/multiplier/booth_wallace_8x8.sv
    read_hdl -sv ${RTL_DIR}/systolic/delay_line.sv
    read_hdl -sv ${RTL_DIR}/systolic/pe.sv
    read_hdl -sv ${RTL_DIR}/systolic/global_controller.sv
    read_hdl -sv ${RTL_DIR}/systolic/systolic_array_top.sv
    read_hdl -sv ${RTL_DIR}/uart/uart_rx.sv
    read_hdl -sv ${RTL_DIR}/uart/uart_tx.sv
    read_hdl -sv ${RTL_DIR}/uart/uart_top.sv
    read_hdl -sv ${RTL_DIR}/top/system_top.sv

    # 5. Elaborate
    elaborate $DESIGN

    # 6. Ràng buộc thời gian (Timing Constraints)
    set CLOCK_PERIOD 20.0
    create_clock -name clk -period $CLOCK_PERIOD [get_ports clk]
    set_clock_uncertainty 0.5 [get_clocks clk]
    
    set_false_path -from [get_ports rst_n]
    set_false_path -from [get_ports rx]
    set_false_path -from [get_ports is_signed]
    set_false_path -to   [get_ports tx]

    # 7. Effort (Mức độ tối ưu)
    set_db syn_generic_effort medium
    set_db syn_map_effort     medium
    set_db syn_opt_effort     medium

    # 8. Chạy Synthesis
    syn_generic
    syn_map
    syn_opt

    # 9. Xuất Reports vào thư mục riêng
    report_timing > ${C_RPT_DIR}/setup_timing.rpt
    report_area   > ${C_RPT_DIR}/area.rpt
    report_power  > ${C_RPT_DIR}/power.rpt
    report_gates  > ${C_RPT_DIR}/gates.rpt
    report_qor    > ${C_RPT_DIR}/qor.rpt

    # 10. Xuất Netlist và file SDC vào thư mục riêng
    write_hdl  > ${C_OUT_DIR}/${DESIGN}_netlist.v
    write_sdc  > ${C_OUT_DIR}/${DESIGN}_syn.sdc
    write_db     ${C_OUT_DIR}/${DESIGN}_syn.db

    puts "\n>> COMPLETED CORNER: $corner"
    puts ">> Reports saved in: $C_RPT_DIR"
    puts ">> Netlist saved in: $C_OUT_DIR\n"
}

puts "\n========================================================================="
puts "  ALL 8 CORNERS SYNTHESIZED SUCCESSFULLY!"
puts "=========================================================================\n"
exit