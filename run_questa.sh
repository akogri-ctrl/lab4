#!/bin/bash
# Questa/ModelSim Simulation Script for GCN Lab4
# Mentor Graphics Questa or ModelSim

echo "========================================="
echo "GCN Lab4 - Questa/ModelSim Simulation"
echo "========================================="

# Clean previous builds
rm -rf work *.wlf transcript *.log *.vcd

# Create work library
echo "Creating work library..."
vlib work
vmap work work

# Compile all RTL files
echo "Compiling RTL files..."
vlog -sv \
    -timescale=1ps/100fs \
    +acc \
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
vsim -c -do "run -all; quit -f" GCN_TB

if [ $? -ne 0 ]; then
    echo "ERROR: Simulation failed!"
    exit 1
fi

echo "========================================="
echo "Simulation completed successfully!"
echo "Check current_output.vcd for waveforms"
echo "========================================="
