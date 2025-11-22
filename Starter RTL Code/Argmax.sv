// Argmax Module
// Finds the index of the maximum value among 3 inputs
// Used for classification: outputs genre index (0=Action, 1=Humor, 2=Family)
// Author: Lab4 Implementation
// Date: 2025-11-22

module Argmax
  #(parameter VALUE_WIDTH = 16,           // Bit width of input values
    parameter INDEX_WIDTH = 2)            // Bit width of output index (2 bits for 0-2)
  (
    input  logic [VALUE_WIDTH-1:0] value0,   // First value (index 0)
    input  logic [VALUE_WIDTH-1:0] value1,   // Second value (index 1)
    input  logic [VALUE_WIDTH-1:0] value2,   // Third value (index 2)
    output logic [INDEX_WIDTH-1:0] max_index // Index of maximum value
  );

  // Combinational logic to find maximum
  always_comb begin
    // Default to index 0
    max_index = 2'b00;

    // Compare and find the maximum
    if (value1 > value0 && value1 >= value2) begin
      max_index = 2'b01;  // value1 is maximum
    end
    else if (value2 > value0 && value2 > value1) begin
      max_index = 2'b10;  // value2 is maximum
    end
    else begin
      max_index = 2'b00;  // value0 is maximum (or tie goes to lowest index)
    end
  end

endmodule
