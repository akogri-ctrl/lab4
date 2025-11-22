`timescale 1ps/100fs
module GCN_TB
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
    parameter NUM_OF_NODES = 6,			 
    parameter COO_NUM_OF_COLS = 6,			
    parameter COO_NUM_OF_ROWS = 2,			
    parameter COO_BW = $clog2(COO_NUM_OF_COLS),
    parameter MAX_ADDRESS_WIDTH = 2,
    parameter HALF_CLOCK_CYCLE = 5
)
();



  string feature_filename = "../Data/feature_data.txt"; // modify the path to the files to match your case
  string weight_filename = "../Data/weight_data.txt";
  string coo_filename = "../Data/coo_data.txt";
  string gold_address_filename = "../Data/gold_address.txt";

  logic read_enable;
  logic write_enable;
  logic [DOT_PROD_WIDTH-1:0] wm_fm_dot_product;
  logic [WEIGHT_WIDTH-1:0] input_data [0:WEIGHT_ROWS-1];

  logic [ADDRESS_WIDTH-1:0] read_addres_mem;
  logic [FEATURE_WIDTH - 1:0] feature_matrix_mem [0:FEATURE_ROWS - 1][0:FEATURE_COLS - 1];
  logic [WEIGHT_WIDTH - 1:0] weight_matrix_mem [0:WEIGHT_COLS - 1][0:WEIGHT_ROWS - 1];
  logic [COO_BW - 1:0] coo_matrix_mem [0:COO_NUM_OF_ROWS - 1][0:COO_NUM_OF_COLS - 1];
  logic [COO_BW - 1:0] col_address;

  logic [DOT_PROD_WIDTH - 1:0] fm_wm_out_TB [0:FEATURE_ROWS-1][0:WEIGHT_COLS-1];
  logic [MAX_ADDRESS_WIDTH - 1:0] max_addi_answer_final [0:FEATURE_ROWS - 1];
  logic [MAX_ADDRESS_WIDTH - 1:0] gold_output_addr [0:FEATURE_ROWS - 1];


  initial $readmemb(feature_filename, feature_matrix_mem);
  initial $readmemb(weight_filename, weight_matrix_mem);
  initial $readmemb(coo_filename, coo_matrix_mem);
  initial $readmemb(gold_address_filename, gold_output_addr);


always @(read_addres_mem or read_enable) begin
	if (read_enable) begin
		if(read_addres_mem >= 10'b10_0000_0000) begin
			input_data = feature_matrix_mem[read_addres_mem - 10'b10_0000_0000];
		end 
		else begin
			input_data = weight_matrix_mem[read_addres_mem];
		end 
	end
end 

	logic clk;		// Clock
	logic rst;		// Dut Reset
	logic start;		// Start Signal: This is asserted in the testbench
	logic done;		// All the Calculations are done

	// Clock Generator
        initial begin
            clk <= '0;
            forever #(HALF_CLOCK_CYCLE) clk <= ~clk;
        end

	// VCD dump for waveform viewing
	initial begin
		$dumpfile("current_output.vcd");
		$dumpvars(0, GCN_TB);
	end

	initial begin
		#100000;
		$display("Simulation Time Expired");

		$finish;
	end 

	// Debug monitor - track writes
	int write_count = 0;
	always @(posedge clk) begin
		if (GCN_DUT.enable_write_fm_wm_prod) begin
			write_count++;
			$display("Time=%0t: WRITE to FM_WM[%0d][%0d] = %0d",
				$time,
				GCN_DUT.feature_count,
				GCN_DUT.weight_count,
				GCN_DUT.dot_product_result);
		end
	end

	// Debug monitor - final values
	initial begin
		wait (done === 1'b1);
		#10;
		$display("\n=== Total FM_WM writes: %0d (expected 18) ===", write_count);
		$display("\n=== FM_WM Memory (Transformation Results) ===");
		for (int row = 0; row < 6; row++) begin
			$display("Row %0d: [%0d, %0d, %0d]",
				row,
				GCN_DUT.fm_wm_memory_inst.mem[row][0],
				GCN_DUT.fm_wm_memory_inst.mem[row][1],
				GCN_DUT.fm_wm_memory_inst.mem[row][2]);
		end
		$display("\n=== Scratch Pad (Weight Column) ===");
		$display("First 10 values: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
			GCN_DUT.weight_col_stored[0],
			GCN_DUT.weight_col_stored[1],
			GCN_DUT.weight_col_stored[2],
			GCN_DUT.weight_col_stored[3],
			GCN_DUT.weight_col_stored[4],
			GCN_DUT.weight_col_stored[5],
			GCN_DUT.weight_col_stored[6],
			GCN_DUT.weight_col_stored[7],
			GCN_DUT.weight_col_stored[8],
			GCN_DUT.weight_col_stored[9]);
		$display("\n=== FM_WM_ADJ Memory (Aggregation Results) ===");
		for (int row = 0; row < 6; row++) begin
			$display("Node %0d: [%0d, %0d, %0d] -> argmax=%0d (expected=%0d)",
				row,
				GCN_DUT.fm_wm_adj_memory_inst.mem[row][0],
				GCN_DUT.fm_wm_adj_memory_inst.mem[row][1],
				GCN_DUT.fm_wm_adj_memory_inst.mem[row][2],
				max_addi_answer_final[row],
				gold_output_addr[row]);
		end
		$display("\nAgg state: %0d, Class state: %0d", GCN_DUT.agg_state, GCN_DUT.class_state);
		$display("=====================================\n");
	end

	initial begin
		start = 1'b0;
		rst = 1'b1;
		// Reset the DUT
		repeat(3) begin
			#HALF_CLOCK_CYCLE;
			rst = ~rst;
		end
                start = 1'b1;
		$display("Start signal asserted at time %0t", $time);

		wait (done === 1'b1);
		$display("Done signal detected at time %0t", $time);
		#21

		check_for_correct_address(max_addi_answer_final, gold_output_addr);
		$finish;
 	end


GCN GCN_DUT
(
  .clk(clk),
  .reset(rst),
  .start(start),
  .data_in(input_data),
  .coo_in({coo_matrix_mem[0][col_address], coo_matrix_mem[1][col_address]}), 

  .coo_address(col_address),
  .read_address(read_addres_mem),
  .enable_read(read_enable),
  .done(done),
  .max_addi_answer(max_addi_answer_final)
); 


	// This function loops through the address matrix, from the dut and the gold values, to make sure that the correct values have been computed
	function void check_for_correct_address(input logic [MAX_ADDRESS_WIDTH - 1:0] dut_output_addr [0:FEATURE_ROWS - 1],
						input logic [MAX_ADDRESS_WIDTH - 1:0] gold_output_addr [0:FEATURE_ROWS - 1]);

		foreach (dut_output_addr[address]) begin

			$display("max_addi_answer[%0d]     DUT: %d       GOLD: %d ", address, dut_output_addr[address], gold_output_addr[address]);
			assert(dut_output_addr[address] === gold_output_addr[address]) else $error("!!!ERROR: The above address outputs are Conflicting");


		end
		$display("\n");

	endfunction

endmodule 
