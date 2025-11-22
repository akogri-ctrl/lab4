#!/bin/bash
# VCS Simulation Script for GCN Lab4
# Synopsys VCS-MX

echo "========================================="
echo "GCN Lab4 - VCS Simulation"
echo "========================================="

# Clean previous builds
rm -rf csrc simv* *.log *.vpd *.vcd

# Compile all RTL files with VCS
echo "Compiling RTL files..."
vcs -sverilog -full64 \
    +v2k \
    -timescale=1ps/100fs \
    -debug_access+all \
    -kdb \
    +vcs+vcdpluson \
    -o simv \
    "Starter RTL Code/DFF.sv" \
    "Starter RTL Code/DotProduct.sv" \
    "Starter RTL Code/Argmax.sv" \
    "Starter RTL Code/Scratch_Pad.sv" \
    "Starter RTL Code/Matrix_FM_WM_Memory.sv" \
    "Starter RTL Code/Matrix_FM_WM_ADJ_Memory.sv" \
    "Starter RTL Code/Transformation_FSM.sv" \
    "Starter RTL Code/GCN.sv" \
    "Testbench/GCN_TB.sv"

if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed!"
    exit 1
fi

echo "Compilation successful!"

# Run simulation
echo "Running simulation..."
./simv

if [ $? -ne 0 ]; then
    echo "ERROR: Simulation failed!"
    exit 1
fi

echo "========================================="
echo "Simulation completed successfully!"
echo "Check current_output.vcd for waveforms"
echo "========================================="
