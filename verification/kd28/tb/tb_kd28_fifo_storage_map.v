`timescale 1ns/1ps // Define simulation time units for fixed-macro storage mapping tests.
`default_nettype none // Reject accidental implicit nets in the mapping testbench.

module kd28_fifo_storage_map_case #( // Exercise one logical configuration through its selected fixed macro array.
    parameter CASE_ID = 0, // Identify this configuration in deterministic failure messages.
    parameter DATA_WIDTH = 24, // Set the logical word width for this mapping case.
    parameter DEPTH = 5, // Set the logical word depth for this mapping case.
    parameter ADDR_WIDTH = 3 // Set the matching logical address width.
) ( // Begin the per-configuration completion interface.
    output reg done_o, // Indicate this independent mapping test has completed.
    output reg failed_o // Indicate this independent mapping test observed a mismatch.
); // End the per-configuration completion interface.
    reg write_clk; // Generate the independent fixed SRAM write clock.
    reg read_clk; // Generate the independent fixed SRAM read clock.
    reg write_cs; // Enable one directed logical write.
    reg [ADDR_WIDTH-1:0] write_addr; // Select a directed logical write address.
    reg [DATA_WIDTH-1:0] write_data; // Drive one directed logical write word.
    reg read_cs; // Enable one directed registered logical read.
    reg [ADDR_WIDTH-1:0] read_addr; // Select a directed logical read address.
    wire [DATA_WIDTH-1:0] read_data; // Observe the mapped registered read result.
    reg [DATA_WIDTH-1:0] first_word; // Retain the expected word at logical address zero.
    reg [DATA_WIDTH-1:0] last_word; // Retain the expected word at the final logical address.

    kd28_fifo_sdp_storage_map #( // Instantiate the fixed KD28 SRAM mapping under test.
        .DATA_WIDTH(DATA_WIDTH), // Select this case's logical word width.
        .DEPTH(DEPTH), // Select this case's logical word depth.
        .ADDR_WIDTH(ADDR_WIDTH) // Select this case's logical address width.
    ) u_dut ( // Bind independent clocks and directed memory controls.
        .write_clk_i(write_clk), // Drive the independent write clock.
        .write_cs_i(write_cs), // Drive the logical write enable.
        .write_addr_i(write_addr), // Drive the logical write address.
        .write_data_i(write_data), // Drive the logical write payload.
        .read_clk_i(read_clk), // Drive the independent read clock.
        .read_cs_i(read_cs), // Drive the logical read enable.
        .read_addr_i(read_addr), // Drive the logical read address.
        .read_data_o(read_data) // Observe the logical registered read result.
    ); // End the fixed-macro storage mapper instance.

    initial begin // Generate the independent write clock.
        write_clk = 1'b0; // Start the write clock low.
        forever #5 write_clk = ~write_clk; // Toggle the write clock every five nanoseconds.
    end // End the write clock generator.

    initial begin // Generate an unrelated independent read clock.
        read_clk = 1'b0; // Start the read clock low.
        forever #7 read_clk = ~read_clk; // Toggle the read clock every seven nanoseconds.
    end // End the read clock generator.

    initial begin // Execute two-address directed mapping checks.
        done_o = 1'b0; // Mark this mapping case incomplete.
        failed_o = 1'b0; // Clear this mapping case failure flag.
        write_cs = 1'b0; // Disable writes before directed stimulus.
        write_addr = {ADDR_WIDTH{1'b0}}; // Initialize the write address to zero.
        write_data = {DATA_WIDTH{1'b0}}; // Initialize write data to zero.
        read_cs = 1'b0; // Disable reads before directed stimulus.
        read_addr = {ADDR_WIDTH{1'b0}}; // Initialize the read address to zero.
        first_word = {DATA_WIDTH{1'b1}}; // Use all ones to expose lost width lanes.
        last_word = {DATA_WIDTH{1'b0}}; // Start the bank-boundary word cleared.
        last_word[DATA_WIDTH-1] = 1'b1; // Mark the uppermost logical bit for width-tiling coverage.
        last_word[0] = 1'b1; // Mark the lowermost logical bit for lane-order coverage.
        #3; // Offset directed stimulus from both active clock edges.
        @(negedge write_clk); // Align the first write away from its active edge.
        write_addr = {ADDR_WIDTH{1'b0}}; // Select logical address zero.
        write_data = first_word; // Drive the first directed word.
        write_cs = 1'b1; // Enable the first complete-word write.
        @(negedge write_clk); // Cross one active write edge.
        write_cs = 1'b0; // Disable the first directed write.
        write_addr = DEPTH - 1; // Select the final logical address across any depth banks.
        write_data = last_word; // Drive the bank and width boundary pattern.
        write_cs = 1'b1; // Enable the final-address write.
        @(negedge write_clk); // Cross one active write edge.
        write_cs = 1'b0; // Disable directed writes after both words are stored.
        @(negedge read_clk); // Align the first read away from its active edge.
        read_addr = {ADDR_WIDTH{1'b0}}; // Select logical address zero for reading.
        read_cs = 1'b1; // Enable the first registered read.
        @(negedge read_clk); // Cross one active read edge and sample its registered result.
        read_cs = 1'b0; // Disable the first directed read.
        if (read_data !== first_word) begin // Require all logical width lanes from address zero.
            $display("KD28_FAIL storage map case=%0d first expected=%x data=%x", CASE_ID, first_word, read_data); // Report the first-address mapping mismatch.
            failed_o = 1'b1; // Record the first-address failure.
        end // End the first-address result check.
        read_addr = DEPTH - 1; // Select the final logical address for reading.
        read_cs = 1'b1; // Enable the final-address registered read.
        @(negedge read_clk); // Cross one active read edge and sample its registered result.
        read_cs = 1'b0; // Disable directed reads after both checks.
        if (read_data !== last_word) begin // Require correct bank and width selection at the final address.
            $display("KD28_FAIL storage map case=%0d last expected=%x data=%x", CASE_ID, last_word, read_data); // Report the final-address mapping mismatch.
            failed_o = 1'b1; // Record the final-address failure.
        end // End the final-address result check.
        done_o = 1'b1; // Mark this mapping case complete.
    end // End the directed mapping check process.
endmodule // End the reusable mapping test case.

module tb_kd28_fifo_storage_map; // Coordinate all fixed SDP macro class mapping checks.
    wire [3:0] case_done; // Collect completion from every mapping configuration.
    wire [3:0] case_failed; // Collect failures from every mapping configuration.

    kd28_fifo_storage_map_case #(.CASE_ID(0), .DATA_WIDTH(24), .DEPTH(5), .ADDR_WIDTH(3)) u_256x32_case (.done_o(case_done[0]), .failed_o(case_failed[0])); // Exercise the 256x32 fixed macro class.
    kd28_fifo_storage_map_case #(.CASE_ID(1), .DATA_WIDTH(40), .DEPTH(300), .ADDR_WIDTH(9)) u_512x64_case (.done_o(case_done[1]), .failed_o(case_failed[1])); // Exercise the 512x64 fixed macro class.
    kd28_fifo_storage_map_case #(.CASE_ID(2), .DATA_WIDTH(72), .DEPTH(600), .ADDR_WIDTH(10)) u_1024x128_case (.done_o(case_done[2]), .failed_o(case_failed[2])); // Exercise the 1024x128 fixed macro class.
    kd28_fifo_storage_map_case #(.CASE_ID(3), .DATA_WIDTH(264), .DEPTH(4096), .ADDR_WIDTH(12)) u_banked_2048x256_case (.done_o(case_done[3]), .failed_o(case_failed[3])); // Exercise two depth banks and two width lanes of 2048x256 macros.

    initial begin // Report one deterministic aggregate test result.
        wait (&case_done); // Wait until all independent clocks complete their mapping checks.
        if (|case_failed) begin // Select the aggregate failure path.
            $display("[RTL_SIM FAIL] kd28_fifo_storage_map cases=%b", case_failed); // Report the failing mapping configurations.
            $fatal(1); // Return a nonzero simulator status after any mapping mismatch.
        end else begin // Select the aggregate successful path.
            $display("[RTL_SIM PASS] kd28_fifo_storage_map"); // Emit the stable fixed-macro mapping pass signature.
        end // End the aggregate result selection.
        $finish; // Terminate the successful mapping regression.
    end // End the aggregate result process.

    initial begin // Enforce a global watchdog against missing mapping completion.
        #20000; // Bound every independent mapping case to twenty microseconds.
        $display("[RTL_SIM FAIL] kd28_fifo_storage_map timeout"); // Report the stable mapping timeout signature.
        $fatal(1); // Return a nonzero simulator status after watchdog expiry.
    end // End the mapping watchdog process.
endmodule // End the fixed-macro storage mapping testbench.

`default_nettype wire // Restore implicit-net behavior after the mapping testbench.
