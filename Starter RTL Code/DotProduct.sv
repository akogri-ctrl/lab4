// Dot Product Module
// Computes the dot product of two 96-element vectors
// Each element is 5 bits, output is 16 bits
// Architecture: Combinational multipliers + adder tree
// Author: Lab4 Implementation
// Date: 2025-11-22

module DotProduct
  #(parameter NUM_ELEMENTS = 96,      // Number of elements in each vector
    parameter ELEMENT_WIDTH = 5,      // Bit width of each element
    parameter OUTPUT_WIDTH = 16)      // Bit width of output (accumulated sum)
  (
    input  logic [ELEMENT_WIDTH-1:0] a [0:NUM_ELEMENTS-1],  // First vector
    input  logic [ELEMENT_WIDTH-1:0] b [0:NUM_ELEMENTS-1],  // Second vector
    output logic [OUTPUT_WIDTH-1:0] result                  // Dot product result
  );

  // Internal signals for products
  logic [2*ELEMENT_WIDTH-1:0] products [0:NUM_ELEMENTS-1];  // 10-bit products

  // Generate multiplications for all pairs
  genvar i;
  generate
    for (i = 0; i < NUM_ELEMENTS; i++) begin : gen_multiply
      assign products[i] = a[i] * b[i];
    end
  endgenerate

  // Sum all products using a reduction
  // We need to be careful about bit widths to avoid overflow
  logic [OUTPUT_WIDTH-1:0] sum;

  always_comb begin
    sum = '0;  // Initialize to zero
    for (int j = 0; j < NUM_ELEMENTS; j++) begin
      sum = sum + products[j];
    end
  end

  assign result = sum;

endmodule
