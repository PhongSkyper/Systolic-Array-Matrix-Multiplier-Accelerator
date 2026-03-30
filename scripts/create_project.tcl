# =============================================================================
# FILE     : create_project.tcl
# PROJECT  : 8×8 Systolic Matrix Multiplier with UART Interface
# TARGET   : Terasic DE10-Standard (Cyclone V 5CSXFC6D6F31C6N)
#
# PURPOSE  : Quartus Prime Lite project creation script.
#            Run from the project root:
#              quartus_sh -t scripts/create_project.tcl
# =============================================================================

package require ::quartus::project

set PROJECT_NAME  "systolic_matmul"
set DEVICE        "5CSXFC6D6F31C6N"
set TOP_MODULE    "system_top"

# Create project
project_new $PROJECT_NAME -overwrite

# Device assignment
set_global_assignment -name FAMILY          "Cyclone V"
set_global_assignment -name DEVICE          $DEVICE
set_global_assignment -name TOP_LEVEL_ENTITY $TOP_MODULE

# -----------------------------------------------------------------------------
# Source files — in dependency order
# -----------------------------------------------------------------------------
set_global_assignment -name SYSTEMVERILOG_FILE rtl/pkg/uart_pkg.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/primitives/gates.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/primitives/adders.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/primitives/fifo_sync_structured.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/primitives/ksa_32bit.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/multiplier/booth_wallace_8x8.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/systolic/delay_line.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/systolic/pe.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/systolic/global_controller.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/systolic/systolic_array_top.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/uart/uart_rx.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/uart/uart_tx.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/uart/uart_top.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/top/system_top.sv

# SDC constraints
set_global_assignment -name SDC_FILE constraints/system_top.sdc

# -----------------------------------------------------------------------------
# Pin assignments (DE10-Standard)
# -----------------------------------------------------------------------------
set_location_assignment PIN_AF14 -to clk         ;# 50 MHz clock
set_location_assignment PIN_AJ4  -to rst_n        ;# KEY[0]
set_location_assignment PIN_AA14 -to rx           ;# GPIO UART RX
set_location_assignment PIN_AA15 -to tx           ;# GPIO UART TX
set_location_assignment PIN_AJ6  -to is_signed    ;# SW[0]

# -----------------------------------------------------------------------------
# Compilation settings
# -----------------------------------------------------------------------------
set_global_assignment -name OPTIMIZATION_MODE        "Balanced"
set_global_assignment -name FITTER_EFFORT            "Standard Fit"
set_global_assignment -name ENABLE_SIGNALTAP          OFF
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"

set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files

# Save and close
project_close
