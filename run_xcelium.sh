#!/bin/bash
# Xcelium Simulation Script for GCN Lab4
# Cadence Xcelium

echo "========================================="
echo "GCN Lab4 - Xcelium Simulation"
echo "========================================="

# Clean previous builds
rm -rf xcelium.d INCA_libs *.log *.history *.vcd

# Run simulation with xrun (compile + elaborate + simulate in one command)
echo "Running xrun..."
xrun -sv \
    -access +rwc \
    -timescale 1ps/100fs \
    -gui \
    -input @"simvision -input restore.tcl.svcf" \
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
    echo "ERROR: Simulation failed!"
    exit 1
fi

echo "========================================="
echo "Simulation completed successfully!"
echo "Check current_output.vcd for waveforms"
echo "========================================="
