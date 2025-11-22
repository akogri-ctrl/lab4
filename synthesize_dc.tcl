# Design Compiler Synthesis Script for GCN Lab4
# Synopsys Design Compiler

# ============================================================================
# SETUP
# ============================================================================

# Set design name
set DESIGN_NAME "GCN"

# Set search paths (MODIFY THESE FOR YOUR SETUP)
set_app_var search_path ". [get_unix_variable SYNOPSYS]/libraries/syn"
set_app_var target_library "asap7sc7p5t_AO_RVT_TT_nldm_201020.db"
set_app_var link_library "* $target_library"

# ============================================================================
# READ RTL FILES
# ============================================================================

puts "Reading RTL files..."

# Read all SystemVerilog files in order
read_file -format sverilog {
    "Starter RTL Code/DFF.sv"
    "Starter RTL Code/DotProduct.sv"
    "Starter RTL Code/Argmax.sv"
    "Starter RTL Code/Scratch_Pad.sv"
    "Starter RTL Code/Matrix_FM_WM_Memory.sv"
    "Starter RTL Code/Matrix_FM_WM_ADJ_Memory.sv"
    "Starter RTL Code/Transformation_FSM.sv"
    "Starter RTL Code/GCN.sv"
}

# Set current design
current_design $DESIGN_NAME

# Link the design
puts "Linking design..."
link

# ============================================================================
# APPLY CONSTRAINTS
# ============================================================================

puts "Reading constraints..."
read_sdc GCN_new.sdc

# Additional constraints
set_max_area 0
set_max_fanout 16 [current_design]

# ============================================================================
# COMPILE
# ============================================================================

puts "Compiling design..."
compile_ultra -gate_clock

# ============================================================================
# REPORTS
# ============================================================================

puts "Generating reports..."

report_timing -transition_time -nets -attributes -nosplit > reports/timing.rpt
report_area -hierarchy > reports/area.rpt
report_power -hierarchy > reports/power.rpt
report_constraint -all_violators > reports/constraints.rpt
report_qor > reports/qor.rpt

# ============================================================================
# WRITE OUTPUT FILES
# ============================================================================

puts "Writing output files..."

# Create outputs directory if it doesn't exist
file mkdir outputs

# Write netlist
write -format verilog -hierarchy -output outputs/${DESIGN_NAME}_syn.v
write -format ddc -hierarchy -output outputs/${DESIGN_NAME}_syn.ddc

# Write SDF for post-synthesis simulation
write_sdf outputs/${DESIGN_NAME}_syn.sdf

# Write SDC for APR
write_sdc outputs/${DESIGN_NAME}_syn.sdc

puts "========================================="
puts "Synthesis completed successfully!"
puts "Check reports/ directory for reports"
puts "Check outputs/ directory for netlists"
puts "========================================="

exit
