`timescale 1ps/100fs

// Parameterized D Flip-Flop Module
// Used for I/O boundary registers to ensure no combinational paths
// Author: Lab4 Implementation
// Date: 2025-11-22

module DFF
  #(parameter WIDTH = 1)  // Bit width of the flip-flop
  (
    input  logic clk,                    // Clock signal
    input  logic reset,                  // Synchronous reset (active high)
    input  logic [WIDTH-1:0] d,          // Data input
    output logic [WIDTH-1:0] q           // Data output (registered)
  );

  // Synchronous reset flip-flop
  always_ff @(posedge clk) begin
    if (reset) begin
      q <= '0;  // Reset to all zeros
    end else begin
      q <= d;   // Normal operation: capture input
    end
  end

endmodule
