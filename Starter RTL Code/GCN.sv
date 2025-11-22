`timescale 1ps/100fs

module GCN
  #(parameter FEATURE_COLS = 96,
    parameter WEIGHT_ROWS = 96,
    parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter FEATURE_WIDTH = 5,
    parameter WEIGHT_WIDTH = 5,
    parameter DOT_PROD_WIDTH = 16,
    parameter ADDRESS_WIDTH = 13,
    parameter COUNTER_WEIGHT_WIDTH = $clog2(WEIGHT_COLS),
    parameter COUNTER_FEATURE_WIDTH = $clog2(FEATURE_ROWS),
    parameter MAX_ADDRESS_WIDTH = 2,
    parameter NUM_OF_NODES = 6,			 
    parameter COO_NUM_OF_COLS = 6,			
    parameter COO_NUM_OF_ROWS = 2,			
    parameter COO_BW = $clog2(COO_NUM_OF_COLS)	
)
(
  input logic clk,	// Clock
  input logic reset,	// Reset 
  input logic start,
  input logic [WEIGHT_WIDTH-1:0] data_in [0:WEIGHT_ROWS-1], //FM and WM Data
  input logic [COO_BW - 1:0] coo_in [0:1], //row 0 and row 1 of the COO Stream

  output logic [COO_BW - 1:0] coo_address, // The column of the COO Matrix 
  output logic [ADDRESS_WIDTH-1:0] read_address, // The Address to read the FM and WM Data
  output logic enable_read, // Enabling the Read of the FM and WM Data
  output logic done, // Done signal indicating that all the calculations have been completed
  output logic [MAX_ADDRESS_WIDTH - 1:0] max_addi_answer [0:FEATURE_ROWS - 1] // The answer to the argmax and matrix multiplication 
);

  // ============================================================================
  // INTERNAL SIGNALS DECLARATION
  // ============================================================================

  // --- Registered inputs (boundary flip-flops) ---
  logic start_reg;
  logic [WEIGHT_WIDTH-1:0] data_in_reg [0:WEIGHT_ROWS-1];
  logic [COO_BW-1:0] coo_in_reg [0:1];

  // --- Registered outputs (boundary flip-flops) ---
  logic [COO_BW-1:0] coo_address_reg;
  logic [ADDRESS_WIDTH-1:0] read_address_reg;
  logic enable_read_reg;
  logic done_reg;
  logic [MAX_ADDRESS_WIDTH-1:0] max_addi_answer_reg [0:FEATURE_ROWS-1];

  // --- Internal signals for datapath ---
  logic [COUNTER_WEIGHT_WIDTH-1:0] weight_count;    // Counter: 0 to 2 (weight columns)
  logic [COUNTER_FEATURE_WIDTH-1:0] feature_count;  // Counter: 0 to 5 (feature rows)
  logic [COO_BW-1:0] coo_count;                     // Counter: 0 to 5 (COO edges)

  // --- Signals from Transformation FSM ---
  logic enable_write_fm_wm_prod;  // Enable writing FM x WM product to memory
  logic enable_read_internal;      // Internal enable read from FSM
  logic enable_write;              // Generic write enable
  logic enable_scratch_pad;        // Enable scratch pad to store weight column
  logic enable_weight_counter;     // Enable weight counter increment
  logic enable_feature_counter;    // Enable feature counter increment
  logic read_feature_or_weight;    // 0 = weight, 1 = feature
  logic done_internal;             // Internal done signal from FSM

  // --- Signals for scratch pad (stores one weight column) ---
  logic [WEIGHT_WIDTH-1:0] weight_col_stored [0:WEIGHT_ROWS-1];

  // --- Signals for dot product computation ---
  logic [DOT_PROD_WIDTH-1:0] dot_product_result;

  // --- Signals for FM_WM memory (transformation results) ---
  logic [DOT_PROD_WIDTH-1:0] fm_wm_row_out [0:WEIGHT_COLS-1];

  // --- Signals for aggregation ---
  logic [DOT_PROD_WIDTH-1:0] fm_wm_adj_row_out [0:WEIGHT_COLS-1];
  logic [DOT_PROD_WIDTH-1:0] aggregated_values [0:WEIGHT_COLS-1];
  logic [COO_BW-1:0] src_node, dst_node;
  logic enable_aggregation;

  // Aggregation state machine types and signals
  typedef enum logic [1:0] {
    AGG_IDLE,
    AGG_ACTIVE,
    AGG_DONE
  } agg_state_t;
  agg_state_t agg_state, agg_next_state;

  // --- Signals for argmax (classification) ---
  // Classification state machine types and signals
  typedef enum logic [1:0] {
    CLASS_IDLE,
    CLASS_ACTIVE,
    CLASS_DONE
  } class_state_t;
  class_state_t class_state, class_next_state;
  logic [COO_BW-1:0] class_count;

  // --- Address generation ---
  logic [ADDRESS_WIDTH-1:0] read_address_internal;


  // ============================================================================
  // INPUT BOUNDARY FLIP-FLOPS
  // Purpose: Register all inputs to avoid combinational paths at module boundary
  // ============================================================================

  always_ff @(posedge clk) begin
    start_reg <= start;
    data_in_reg <= data_in;
    coo_in_reg <= coo_in;
  end


  // ============================================================================
  // OUTPUT BOUNDARY FLIP-FLOPS
  // Purpose: Register all outputs to avoid combinational paths at module boundary
  // ============================================================================

  // Control signals are combinational for proper timing
  assign read_address = read_address_reg;
  assign enable_read = enable_read_reg;
  assign coo_address = coo_address_reg;

  // Data outputs are registered
  always_ff @(posedge clk or posedge reset)
    if (reset) begin
      done <= 1'b0;
      for (int i = 0; i < FEATURE_ROWS; i++)
        max_addi_answer[i] <= 2'b00;
    end else begin
      done <= done_reg;
      max_addi_answer <= max_addi_answer_reg;
    end


  // ============================================================================
  // COUNTERS
  // Purpose: Track current weight column, feature row, and COO edge
  // ============================================================================

  // Weight counter: 0 to 2 (3 weight columns)
  always_ff @(posedge clk or posedge reset)
    if (reset)
      weight_count <= {COUNTER_WEIGHT_WIDTH{1'b0}};
    else if (enable_weight_counter)
      weight_count <= weight_count + 1;

  // Feature counter: 0 to 5 (6 feature rows)
  // Reset to 0 when moving to next weight column
  always_ff @(posedge clk or posedge reset)
    if (reset)
      feature_count <= {COUNTER_FEATURE_WIDTH{1'b0}};
    else if (enable_weight_counter)
      feature_count <= {COUNTER_FEATURE_WIDTH{1'b0}};
    else if (enable_feature_counter)
      feature_count <= feature_count + 1;

  // COO counter: 0 to 5 (6 edges in adjacency matrix)
  // This counter is used during aggregation phase (after transformation)
  always_ff @(posedge clk or posedge reset)
    if (reset)
      coo_count <= {COO_BW{1'b0}};
    else if (enable_aggregation && coo_count < COO_NUM_OF_COLS - 1)
      coo_count <= coo_count + 1;


  // ============================================================================
  // ADDRESS GENERATOR
  // Purpose: Generate correct addresses for reading weight and feature matrices
  // Weight addresses: 0, 1, 2 (three columns)
  // Feature addresses: 512, 513, 514, 515, 516, 517 (six rows, offset by 512)
  // ============================================================================

  always_comb begin
    if (read_feature_or_weight) begin
      // Reading feature matrix: address = 512 + feature_count
      // 512 = 2^9, so set bit 9 and add feature_count
      read_address_internal = 13'd512 + {{(ADDRESS_WIDTH-COUNTER_FEATURE_WIDTH){1'b0}}, feature_count};
    end else begin
      // Reading weight matrix: address = weight_count
      read_address_internal = {{(ADDRESS_WIDTH-COUNTER_WEIGHT_WIDTH){1'b0}}, weight_count};
    end
  end

  // Control signals go directly to output (no extra registration for timing)
  assign read_address_reg = read_address_internal;
  assign enable_read_reg = enable_read_internal;
  assign coo_address_reg = coo_count;


  // ============================================================================
  // SUB-MODULE INSTANTIATIONS
  // ============================================================================

  // --- Transformation FSM: Controls the overall computation flow ---
  Transformation_FSM #(
    .WEIGHT_COLS(WEIGHT_COLS),
    .FEATURE_ROWS(FEATURE_ROWS),
    .COUNTER_WEIGHT_WIDTH(COUNTER_WEIGHT_WIDTH),
    .COUNTER_FEATURE_WIDTH(COUNTER_FEATURE_WIDTH)
  ) fsm_inst (
    .clk(clk),
    .reset(reset),
    .start(start_reg),
    .weight_count(weight_count),
    .feature_count(feature_count),
    .enable_write_fm_wm_prod(enable_write_fm_wm_prod),
    .enable_read(enable_read_internal),
    .enable_write(enable_write),
    .enable_scratch_pad(enable_scratch_pad),
    .enable_weight_counter(enable_weight_counter),
    .enable_feature_counter(enable_feature_counter),
    .read_feature_or_weight(read_feature_or_weight),
    .done(done_internal)
  );

  // --- Scratch Pad: Stores one column of weight matrix for reuse ---
  Scratch_Pad #(
    .WEIGHT_ROWS(WEIGHT_ROWS),
    .WEIGHT_WIDTH(WEIGHT_WIDTH)
  ) scratch_pad_inst (
    .clk(clk),
    .reset(reset),
    .write_enable(enable_scratch_pad),
    .weight_col_in(data_in_reg),
    .weight_col_out(weight_col_stored)
  );

  // --- Dot Product Unit: Computes feature_row · weight_column ---
  DotProduct #(
    .NUM_ELEMENTS(WEIGHT_ROWS),
    .ELEMENT_WIDTH(WEIGHT_WIDTH),
    .OUTPUT_WIDTH(DOT_PROD_WIDTH)
  ) dot_product_inst (
    .a(data_in_reg),           // Feature row (when reading features)
    .b(weight_col_stored),     // Weight column (from scratch pad)
    .result(dot_product_result)
  );

  // --- FM_WM Memory: Stores transformation results (6x3 matrix) ---
  Matrix_FM_WM_Memory #(
    .FEATURE_ROWS(FEATURE_ROWS),
    .WEIGHT_COLS(WEIGHT_COLS),
    .DOT_PROD_WIDTH(DOT_PROD_WIDTH)
  ) fm_wm_memory_inst (
    .clk(clk),
    .rst(reset),
    .write_row(feature_count),
    .write_col(weight_count),
    .read_row(src_node),  // Will be used during aggregation
    .wr_en(enable_write_fm_wm_prod),
    .fm_wm_in(dot_product_result),
    .fm_wm_row_out(fm_wm_row_out)
  );

  // --- FM_WM_ADJ Memory: Stores aggregation results (6x3 matrix) ---
  // Mux for read address: use class_count during classification, dst_node during aggregation
  logic [COO_BW-1:0] fm_wm_adj_read_addr;
  assign fm_wm_adj_read_addr = (class_state == CLASS_ACTIVE) ? class_count : dst_node;

  Matrix_FM_WM_ADJ_Memory #(
    .FEATURE_ROWS(FEATURE_ROWS),
    .WEIGHT_COLS(WEIGHT_COLS),
    .DOT_PROD_WIDTH(DOT_PROD_WIDTH)
  ) fm_wm_adj_memory_inst (
    .clk(clk),
    .rst(reset),
    .write_row(dst_node),
    .read_row(fm_wm_adj_read_addr),  // Read different rows during classification
    .wr_en(enable_aggregation),
    .fm_wm_adj_row_in(aggregated_values),
    .fm_wm_adj_out(fm_wm_adj_row_out)
  );

  // --- Argmax Module: Single instance used for all nodes ---
  logic [MAX_ADDRESS_WIDTH-1:0] argmax_result;

  Argmax #(
    .VALUE_WIDTH(DOT_PROD_WIDTH),
    .INDEX_WIDTH(MAX_ADDRESS_WIDTH)
  ) argmax_inst (
    .value0(fm_wm_adj_row_out[0]),
    .value1(fm_wm_adj_row_out[1]),
    .value2(fm_wm_adj_row_out[2]),
    .max_index(argmax_result)
  );


  // ============================================================================
  // AGGREGATION LOGIC
  // Purpose: Perform sparse matrix aggregation using COO format
  // After transformation phase completes, aggregate features based on graph edges
  // For each edge (src, dst): FM_WM_ADJ[dst] += FM_WM[src]
  // ============================================================================

  // Decode COO inputs to get source and destination nodes
  assign src_node = coo_in_reg[0];
  assign dst_node = coo_in_reg[1];

  // Enable aggregation after transformation is done
  // Simple state machine: start aggregation when FSM done, aggregate 6 edges
  // (State machine types declared in internal signals section above)

  always_ff @(posedge clk or posedge reset)
    if (reset)
      agg_state <= AGG_IDLE;
    else
      agg_state <= agg_next_state;

  always_comb begin
    agg_next_state = agg_state;
    enable_aggregation = 1'b0;

    case (agg_state)
      AGG_IDLE: begin
        if (done_internal) begin
          agg_next_state = AGG_ACTIVE;
        end
      end

      AGG_ACTIVE: begin
        enable_aggregation = 1'b1;
        if (coo_count == COO_NUM_OF_COLS - 1) begin
          agg_next_state = AGG_DONE;
        end
      end

      AGG_DONE: begin
        enable_aggregation = 1'b0;
      end
    endcase
  end

  // Compute aggregated values: FM_WM_ADJ[dst] + FM_WM[src]
  always_comb begin
    for (int i = 0; i < WEIGHT_COLS; i++) begin
      aggregated_values[i] = fm_wm_adj_row_out[i] + fm_wm_row_out[i];
    end
  end


  // ============================================================================
  // CLASSIFICATION (ARGMAX) OUTPUT
  // Purpose: After aggregation, apply argmax to each node's features
  // ============================================================================

  // Read each row of FM_WM_ADJ and compute argmax
  // We need to sequence through all 6 nodes to compute argmax for each
  // (State machine types and signals declared in internal signals section above)

  always_ff @(posedge clk or posedge reset)
    if (reset) begin
      class_state <= CLASS_IDLE;
      class_count <= {COO_BW{1'b0}};
    end else begin
      class_state <= class_next_state;
      if (class_state == CLASS_ACTIVE)
        class_count <= class_count + 1;
    end

  always_comb begin
    class_next_state = class_state;

    case (class_state)
      CLASS_IDLE: begin
        if (agg_state == AGG_DONE) begin
          class_next_state = CLASS_ACTIVE;
        end
      end

      CLASS_ACTIVE: begin
        if (class_count == FEATURE_ROWS - 1) begin
          class_next_state = CLASS_DONE;
        end
      end

      CLASS_DONE: begin
        // Stay in done state
      end
    endcase
  end

  // Capture argmax results for each node
  always_ff @(posedge clk or posedge reset)
    if (reset) begin
      for (int i = 0; i < FEATURE_ROWS; i++)
        max_addi_answer_reg[i] <= 2'b00;
    end else if (class_state == CLASS_ACTIVE)
      max_addi_answer_reg[class_count] <= argmax_result;

  // Final done signal
  assign done_reg = (class_state == CLASS_DONE);

endmodule
