###############################################################################
# FILE   : sta.tcl
# TOOL   : Cadence Tempus
# PDK    : GPDK045 - full 8-corner MMMC
# DESIGN : system_top
#
# ANALYSIS VIEWS:
#   Setup views (4): slow process x {vdd1v0, vdd1v2} x {lvt, hvt}
#   Hold  views (4): fast process x {vdd1v0, vdd1v2} x {lvt, hvt}
#
# USAGE:
#   cd <project>/syn
#   tempus -f sta.tcl |& tee sta.log
###############################################################################

set DESIGN  "system_top"
set LIB_DIR "../lib/gpdk045/gpdk045_lib"
set OUT_DIR "./outputs"
set RPT_DIR "./reports/sta"

file mkdir $RPT_DIR

###############################################################################
# 1. Read netlist and SDC from synthesis
###############################################################################
read_netlist ${OUT_DIR}/${DESIGN}_netlist.v
read_sdc     ${OUT_DIR}/${DESIGN}_syn.sdc
link_design  $DESIGN

###############################################################################
# 2. Define library sets — 8 corners
###############################################################################
create_library_set -name libs_slow_vdd1v2_lvt \
    -timing ${LIB_DIR}/slow_vdd1v2_basicCells_lvt.lib

create_library_set -name libs_slow_vdd1v2_hvt \
    -timing ${LIB_DIR}/slow_vdd1v2_basicCells_hvt.lib

create_library_set -name libs_slow_vdd1v0_lvt \
    -timing ${LIB_DIR}/slow_vdd1v0_basicCells_lvt.lib

create_library_set -name libs_slow_vdd1v0_hvt \
    -timing ${LIB_DIR}/slow_vdd1v0_basicCells_hvt.lib

create_library_set -name libs_fast_vdd1v2_lvt \
    -timing ${LIB_DIR}/fast_vdd1v2_basicCells_lvt.lib

create_library_set -name libs_fast_vdd1v2_hvt \
    -timing ${LIB_DIR}/fast_vdd1v2_basicCells_hvt.lib

create_library_set -name libs_fast_vdd1v0_lvt \
    -timing ${LIB_DIR}/fast_vdd1v0_basicCells_lvt.lib

create_library_set -name libs_fast_vdd1v0_hvt \
    -timing ${LIB_DIR}/fast_vdd1v0_basicCells_hvt.lib

###############################################################################
# 3. RC corner (no parasitics at gate level — use default)
###############################################################################
create_rc_corner -name rc_typ -T 25

###############################################################################
# 4. Delay corners
###############################################################################
create_delay_corner -name dc_slow_vdd1v2_lvt \
    -library_set libs_slow_vdd1v2_lvt -rc_corner rc_typ

create_delay_corner -name dc_slow_vdd1v2_hvt \
    -library_set libs_slow_vdd1v2_hvt -rc_corner rc_typ

create_delay_corner -name dc_slow_vdd1v0_lvt \
    -library_set libs_slow_vdd1v0_lvt -rc_corner rc_typ

create_delay_corner -name dc_slow_vdd1v0_hvt \
    -library_set libs_slow_vdd1v0_hvt -rc_corner rc_typ

create_delay_corner -name dc_fast_vdd1v2_lvt \
    -library_set libs_fast_vdd1v2_lvt -rc_corner rc_typ

create_delay_corner -name dc_fast_vdd1v2_hvt \
    -library_set libs_fast_vdd1v2_hvt -rc_corner rc_typ

create_delay_corner -name dc_fast_vdd1v0_lvt \
    -library_set libs_fast_vdd1v0_lvt -rc_corner rc_typ

create_delay_corner -name dc_fast_vdd1v0_hvt \
    -library_set libs_fast_vdd1v0_hvt -rc_corner rc_typ

###############################################################################
# 5. Constraint mode (same SDC for all corners)
###############################################################################
create_constraint_mode -name func \
    -sdc_files ${OUT_DIR}/${DESIGN}_syn.sdc

###############################################################################
# 6. Analysis views — 4 setup + 4 hold
###############################################################################
# Setup views (slow = worst-case propagation delay)
create_analysis_view -name view_setup_slow_vdd1v2_lvt \
    -constraint_mode func -delay_corner dc_slow_vdd1v2_lvt

create_analysis_view -name view_setup_slow_vdd1v2_hvt \
    -constraint_mode func -delay_corner dc_slow_vdd1v2_hvt

create_analysis_view -name view_setup_slow_vdd1v0_lvt \
    -constraint_mode func -delay_corner dc_slow_vdd1v0_lvt

create_analysis_view -name view_setup_slow_vdd1v0_hvt \
    -constraint_mode func -delay_corner dc_slow_vdd1v0_hvt

# Hold views (fast = best-case propagation delay, hardest hold)
create_analysis_view -name view_hold_fast_vdd1v2_lvt \
    -constraint_mode func -delay_corner dc_fast_vdd1v2_lvt

create_analysis_view -name view_hold_fast_vdd1v2_hvt \
    -constraint_mode func -delay_corner dc_fast_vdd1v2_hvt

create_analysis_view -name view_hold_fast_vdd1v0_lvt \
    -constraint_mode func -delay_corner dc_fast_vdd1v0_lvt

create_analysis_view -name view_hold_fast_vdd1v0_hvt \
    -constraint_mode func -delay_corner dc_fast_vdd1v0_hvt

# Activate all views
set_analysis_view \
    -setup [list \
        view_setup_slow_vdd1v2_lvt \
        view_setup_slow_vdd1v2_hvt \
        view_setup_slow_vdd1v0_lvt \
        view_setup_slow_vdd1v0_hvt \
    ] \
    -hold [list \
        view_hold_fast_vdd1v2_lvt \
        view_hold_fast_vdd1v2_hvt \
        view_hold_fast_vdd1v0_lvt \
        view_hold_fast_vdd1v0_hvt \
    ]

###############################################################################
# 7. Run timing update
###############################################################################
update_timing -full

###############################################################################
# 8. Reports — setup (4 corners)
###############################################################################
foreach view {
    view_setup_slow_vdd1v2_lvt
    view_setup_slow_vdd1v2_hvt
    view_setup_slow_vdd1v0_lvt
    view_setup_slow_vdd1v0_hvt
} {
    report_timing \
        -view       $view \
        -max_paths  10 \
        -path_type  full \
        > ${RPT_DIR}/setup_${view}.rpt

    # Violations only
    report_timing \
        -view              $view \
        -slack_lesser_than 0 \
        -max_paths         50 \
        > ${RPT_DIR}/viol_setup_${view}.rpt
}

###############################################################################
# 9. Reports — hold (4 corners)
###############################################################################
foreach view {
    view_hold_fast_vdd1v2_lvt
    view_hold_fast_vdd1v2_hvt
    view_hold_fast_vdd1v0_lvt
    view_hold_fast_vdd1v0_hvt
} {
    report_timing \
        -view       $view \
        -early \
        -max_paths  10 \
        -path_type  full \
        > ${RPT_DIR}/hold_${view}.rpt

    report_timing \
        -view              $view \
        -early \
        -slack_lesser_than 0 \
        -max_paths         50 \
        > ${RPT_DIR}/viol_hold_${view}.rpt
}

###############################################################################
# 10. Summary reports
###############################################################################
report_clock_timing -type summary > ${RPT_DIR}/clock_summary.rpt
report_area                       > ${RPT_DIR}/area.rpt
report_power                      > ${RPT_DIR}/power.rpt

###############################################################################
# 11. Screen summary — worst slack per corner
###############################################################################
puts "\n============================================"
puts "  STA SUMMARY — WORST SLACK PER CORNER"
puts "============================================"
puts "\n-- SETUP corners --"
foreach view {
    view_setup_slow_vdd1v2_lvt
    view_setup_slow_vdd1v2_hvt
    view_setup_slow_vdd1v0_lvt
    view_setup_slow_vdd1v0_hvt
} {
    puts "\n$view:"
    report_timing -view $view -max_paths 1
}

puts "\n-- HOLD corners --"
foreach view {
    view_hold_fast_vdd1v2_lvt
    view_hold_fast_vdd1v2_hvt
    view_hold_fast_vdd1v0_lvt
    view_hold_fast_vdd1v0_hvt
} {
    puts "\n$view:"
    report_timing -view $view -early -max_paths 1
}

puts "\n============================================"
puts "  Reports saved to: ${RPT_DIR}/"
puts "============================================\n"