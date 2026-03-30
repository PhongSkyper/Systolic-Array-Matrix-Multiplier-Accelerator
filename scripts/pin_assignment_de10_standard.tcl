# =============================================================================
# FILE     : pin_assignment_de10_standard.tcl
# PROJECT  : 8x8 Systolic Matrix Multiplier with UART Interface
# TARGET   : Terasic DE10-Standard (Cyclone V 5CSXFC6D6F31C6N)
#
# PIN MAPPING (chọn từ GPIO header vì UART không có port riêng trên board):
#   clk       → PIN_AF14  (CLOCK_50 — onboard 50MHz oscillator)
#   rst_n     → PIN_AA14  (KEY[0]   — push button, active LOW, tự debounce)
#   is_signed → PIN_AB12  (SW[0]    — slide switch: UP=1 signed, DOWN=0 unsigned)
#   rx        → PIN_AH17  (GPIO_0[0] — dùng GPIO header, nối với USB-UART TX)
#   tx        → PIN_AG16  (GPIO_0[1] — dùng GPIO header, nối với USB-UART RX)
#
# CÁP NỐI UART (USB-UART converter như CP2102 hoặc FT232):
#   UART TX (máy tính) → GPIO_0[0] (PIN_AH17) — board nhận
#   UART RX (máy tính) → GPIO_0[1] (PIN_AG16) — board gửi
#   GND converter      → GND trên GPIO header (PIN 30 hoặc 12)
#   KHÔNG nối VCC — board tự có nguồn
#
# HOW TO RUN :
#   Quartus Tcl Console: source pin_assignment_de10_standard.tcl
#   Hoặc: Tools → Tcl Scripts → chọn file này → Run
# =============================================================================

package require ::quartus::project

# Kiểm tra project đã mở chưa
if {[is_project_open]} {
    puts "Project is open. Applying pin assignments..."
} else {
    puts "ERROR: No project open. Open your Quartus project first."
    return
}

# =============================================================================
# CLOCK
# =============================================================================
set_location_assignment PIN_AF14 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

# =============================================================================
# RESET — KEY[0], active LOW (nhấn = reset)
# =============================================================================
set_location_assignment PIN_AA14 -to rst_n
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rst_n

# =============================================================================
# CONFIG SWITCH — SW[0]
#   UP   (logic 1) = signed mode
#   DOWN (logic 0) = unsigned mode
# =============================================================================
set_location_assignment PIN_AB12 -to is_signed
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to is_signed

# =============================================================================
# UART — GPIO_0 Header (JP1 trên board)
#   Nhìn vào header JP1, đếm từ pin 1 (góc có dấu tam giác):
#   Pin 1  = GPIO_0[0] = AH17 → rx  (nối với TX của USB-UART)
#   Pin 3  = GPIO_0[1] = AG16 → tx  (nối với RX của USB-UART)
#   Pin 30 = GND             → GND của USB-UART
# =============================================================================
set_location_assignment PIN_AH17 -to rx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rx
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to rx

set_location_assignment PIN_AG16 -to tx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to tx

# =============================================================================
# TIMING DRIVEN COMPILE SETTINGS (optional nhưng recommended)
# =============================================================================
set_global_assignment -name TIMING_ANALYZER_MULTICORNER_ANALYSIS ON
set_global_assignment -name SMART_RECOMPILE ON

puts "Pin assignments applied successfully."
puts ""
puts "Summary:"
puts "  clk       -> PIN_AF14 (CLOCK_50)"
puts "  rst_n     -> PIN_AA14 (KEY\[0\])"
puts "  is_signed -> PIN_AB12 (SW\[0\])"
puts "  rx        -> PIN_AH17 (GPIO_0\[0\] / JP1 pin 1)"
puts "  tx        -> PIN_AG16 (GPIO_0\[1\] / JP1 pin 3)"
puts ""
puts "UART wiring:"
puts "  USB-UART TX  ->  GPIO_0\[0\] (PIN_AH17)"
puts "  USB-UART RX  ->  GPIO_0\[1\] (PIN_AG16)"
puts "  USB-UART GND ->  JP1 GND (pin 30)"