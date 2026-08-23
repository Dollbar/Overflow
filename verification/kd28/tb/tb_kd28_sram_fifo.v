`timescale 1ns/1ps // Define simulation time units for the KD28 self-checking testbench.
`default_nettype none // Reject accidental implicit nets in the KD28 testbench.

module tb_kd28_sram_fifo; // Define the self-checking KD28 SRAM and FIFO testbench.
    reg clk; // Drive the shared SRAM and synchronous FIFO clock.
    reg async_write_clk; // Drive the asynchronous FIFO write clock.
    reg async_read_clk; // Drive the asynchronous FIFO read clock.
    reg sync_rst_n; // Drive the synchronous FIFO active-low asynchronous reset.
    reg async_write_rst_n; // Drive the asynchronous FIFO write-domain reset.
    reg async_read_rst_n; // Drive the asynchronous FIFO read-domain reset.
    reg sp_cs; // Drive single-port chip select.
    reg sp_we; // Drive single-port write enable.
    reg [7:0] sp_addr; // Drive the single-port word address.
    reg [31:0] sp_wdata; // Drive single-port write data.
    reg [3:0] sp_wmask; // Drive single-port byte write enables.
    wire [31:0] sp_rdata; // Observe single-port registered read data.
    reg sdp_wcs; // Drive simple-dual-port write chip select.
    reg [7:0] sdp_waddr; // Drive the simple-dual-port write address.
    reg [31:0] sdp_wdata; // Drive simple-dual-port write data.
    reg [3:0] sdp_wmask; // Drive simple-dual-port byte write enables.
    reg sdp_rcs; // Drive simple-dual-port read chip select.
    reg [7:0] sdp_raddr; // Drive the simple-dual-port read address.
    wire [31:0] sdp_rdata; // Observe simple-dual-port registered read data.
    reg tdp_acs; // Drive true-dual-port port A chip select.
    reg tdp_awe; // Drive true-dual-port port A write enable.
    reg [4:0] tdp_aaddr; // Drive the true-dual-port port A address.
    reg [31:0] tdp_awdata; // Drive true-dual-port port A write data.
    reg [3:0] tdp_awmask; // Drive true-dual-port port A byte write enables.
    wire [31:0] tdp_ardata; // Observe true-dual-port port A read data.
    reg tdp_bcs; // Drive true-dual-port port B chip select.
    reg tdp_bwe; // Drive true-dual-port port B write enable.
    reg [4:0] tdp_baddr; // Drive the true-dual-port port B address.
    reg [31:0] tdp_bwdata; // Drive true-dual-port port B write data.
    reg [3:0] tdp_bwmask; // Drive true-dual-port port B byte write enables.
    wire [31:0] tdp_brdata; // Observe true-dual-port port B read data.
    reg [23:0] sync_write_data; // Drive the parameterized synchronous FIFO payload.
    reg sync_write_valid; // Drive synchronous FIFO producer validity.
    wire sync_write_ready; // Observe synchronous FIFO producer readiness.
    wire [23:0] sync_read_data; // Observe synchronous FIFO consumer payload.
    wire sync_read_valid; // Observe synchronous FIFO consumer validity.
    reg sync_read_ready; // Drive synchronous FIFO consumer readiness.
    reg [15:0] async_write_data; // Drive the parameterized asynchronous FIFO payload.
    reg async_write_valid; // Drive asynchronous FIFO producer validity.
    wire async_write_ready; // Observe asynchronous FIFO producer readiness.
    wire [15:0] async_read_data; // Observe asynchronous FIFO consumer payload.
    wire async_read_valid; // Observe asynchronous FIFO consumer validity.
    reg async_read_ready; // Drive asynchronous FIFO consumer readiness.
    integer errors; // Count all detected self-check failures.
    integer expected; // Hold the expected FIFO sequence number.
    integer timeout_count; // Bound each ready-valid wait loop.

    always #5 clk = ~clk; // Generate the shared 100 MHz-equivalent simulation clock.
    always #4 async_write_clk = ~async_write_clk; // Generate the faster asynchronous write clock.
    always #7 async_read_clk = ~async_read_clk; // Generate the slower asynchronous read clock.

    KD28_SRAM_SP_256X32 u_sp ( // Instantiate a fixed KD28 single-port cell for masked-write checks.
        .CLK(clk), // Connect the shared test clock.
        .CS(sp_cs), // Connect single-port chip select.
        .WE(sp_we), // Connect single-port write enable.
        .A(sp_addr), // Connect the single-port address.
        .D(sp_wdata), // Connect single-port write data.
        .WM(sp_wmask), // Connect single-port byte write enables.
        .Q(sp_rdata) // Observe single-port registered read data.
    ); // End the fixed KD28 single-port instance.

    KD28_SRAM_SDP_256X32 u_sdp ( // Instantiate a fixed KD28 simple-dual-port cell.
        .WCLK(clk), // Connect the shared test clock to the write port.
        .WCS(sdp_wcs), // Connect simple-dual-port write chip select.
        .WA(sdp_waddr), // Connect the simple-dual-port write address.
        .D(sdp_wdata), // Connect simple-dual-port write data.
        .WM(sdp_wmask), // Connect simple-dual-port byte write enables.
        .RCLK(clk), // Connect the shared test clock to the read port.
        .RCS(sdp_rcs), // Connect simple-dual-port read chip select.
        .RA(sdp_raddr), // Connect the simple-dual-port read address.
        .Q(sdp_rdata) // Observe simple-dual-port registered read data.
    ); // End the fixed KD28 simple-dual-port instance.

    KD28_SRAM_TDP_32X32 u_tdp ( // Instantiate a fixed KD28 true-dual-port cell.
        .CLK(clk), // Connect the shared test clock.
        .ACS(tdp_acs), // Connect port A chip select.
        .AWE(tdp_awe), // Connect port A write enable.
        .AA(tdp_aaddr), // Connect the port A address.
        .AD(tdp_awdata), // Connect port A write data.
        .AWM(tdp_awmask), // Connect port A byte write enables.
        .AQ(tdp_ardata), // Observe port A registered read data.
        .BCS(tdp_bcs), // Connect port B chip select.
        .BWE(tdp_bwe), // Connect port B write enable.
        .BA(tdp_baddr), // Connect the port B address.
        .BD(tdp_bwdata), // Connect port B write data.
        .BWM(tdp_bwmask), // Connect port B byte write enables.
        .BQ(tdp_brdata) // Observe port B registered read data.
    ); // End the fixed KD28 true-dual-port instance.

    kd28_sync_fifo #( // Instantiate a non-power-of-two KD28 synchronous FIFO.
        .DATA_WIDTH(24), // Verify a three-byte payload width.
        .DEPTH(5) // Verify exact non-power-of-two capacity handling.
    ) u_sync_fifo ( // Bind the synchronous FIFO ready-valid channels.
        .clk_i(clk), // Connect the shared FIFO clock.
        .rst_n_i(sync_rst_n), // Connect the active-low FIFO reset.
        .write_data_i(sync_write_data), // Connect producer payload data.
        .write_valid_i(sync_write_valid), // Connect producer validity.
        .write_ready_o(sync_write_ready), // Observe producer readiness.
        .read_data_o(sync_read_data), // Observe consumer payload data.
        .read_valid_o(sync_read_valid), // Observe consumer validity.
        .read_ready_i(sync_read_ready) // Connect consumer readiness.
    ); // End the synchronous FIFO instance.

    kd28_async_fifo #( // Instantiate a dual-clock KD28 asynchronous FIFO.
        .DATA_WIDTH(16), // Verify a two-byte payload width.
        .DEPTH(8) // Verify an eight-word Gray-pointer capacity.
    ) u_async_fifo ( // Bind the asynchronous FIFO ready-valid channels.
        .write_clk_i(async_write_clk), // Connect the producer-domain clock.
        .write_rst_n_i(async_write_rst_n), // Connect the producer-domain reset.
        .write_data_i(async_write_data), // Connect producer payload data.
        .write_valid_i(async_write_valid), // Connect producer validity.
        .write_ready_o(async_write_ready), // Observe producer readiness.
        .read_clk_i(async_read_clk), // Connect the consumer-domain clock.
        .read_rst_n_i(async_read_rst_n), // Connect the consumer-domain reset.
        .read_data_o(async_read_data), // Observe consumer payload data.
        .read_valid_o(async_read_valid), // Observe consumer validity.
        .read_ready_i(async_read_ready) // Connect consumer readiness.
    ); // End the asynchronous FIFO instance.

    initial begin // Execute deterministic SRAM and FIFO verification stimulus.
        clk = 1'b0; // Initialize the shared clock low.
        async_write_clk = 1'b0; // Initialize the asynchronous write clock low.
        async_read_clk = 1'b0; // Initialize the asynchronous read clock low.
        sync_rst_n = 1'b0; // Hold the synchronous FIFO in reset.
        async_write_rst_n = 1'b0; // Hold the asynchronous write domain in reset.
        async_read_rst_n = 1'b0; // Hold the asynchronous read domain in reset.
        sp_cs = 1'b0; // Disable the single-port SRAM initially.
        sp_we = 1'b0; // Select the single-port read mode initially.
        sp_addr = 8'd0; // Clear the single-port address.
        sp_wdata = 32'd0; // Clear single-port write data.
        sp_wmask = 4'd0; // Disable all single-port byte writes.
        sdp_wcs = 1'b0; // Disable the simple-dual-port write port initially.
        sdp_waddr = 8'd0; // Clear the simple-dual-port write address.
        sdp_wdata = 32'd0; // Clear simple-dual-port write data.
        sdp_wmask = 4'd0; // Disable all simple-dual-port byte writes.
        sdp_rcs = 1'b0; // Disable the simple-dual-port read port initially.
        sdp_raddr = 8'd0; // Clear the simple-dual-port read address.
        tdp_acs = 1'b0; // Disable true-dual-port port A initially.
        tdp_awe = 1'b0; // Select true-dual-port port A read mode initially.
        tdp_aaddr = 5'd0; // Clear the true-dual-port port A address.
        tdp_awdata = 32'd0; // Clear true-dual-port port A write data.
        tdp_awmask = 4'd0; // Disable all true-dual-port port A byte writes.
        tdp_bcs = 1'b0; // Disable true-dual-port port B initially.
        tdp_bwe = 1'b0; // Select true-dual-port port B read mode initially.
        tdp_baddr = 5'd0; // Clear the true-dual-port port B address.
        tdp_bwdata = 32'd0; // Clear true-dual-port port B write data.
        tdp_bwmask = 4'd0; // Disable all true-dual-port port B byte writes.
        sync_write_data = 24'd0; // Clear synchronous FIFO producer data.
        sync_write_valid = 1'b0; // Deassert synchronous FIFO producer validity.
        sync_read_ready = 1'b0; // Deassert synchronous FIFO consumer readiness.
        async_write_data = 16'd0; // Clear asynchronous FIFO producer data.
        async_write_valid = 1'b0; // Deassert asynchronous FIFO producer validity.
        async_read_ready = 1'b0; // Deassert asynchronous FIFO consumer readiness.
        errors = 0; // Clear the self-check failure count.
        expected = 0; // Clear the expected sequence value.
        timeout_count = 0; // Clear the bounded wait counter.

        repeat (3) @(posedge clk); // Hold resets across several shared-clock edges.
        sync_rst_n = 1'b1; // Release the synchronous FIFO reset.
        repeat (3) @(posedge async_write_clk); // Hold the asynchronous write reset across local edges.
        async_write_rst_n = 1'b1; // Release the asynchronous write-domain reset.
        repeat (3) @(posedge async_read_clk); // Hold the asynchronous read reset across local edges.
        async_read_rst_n = 1'b1; // Release the asynchronous read-domain reset.

        @(negedge clk); // Align the first SRAM write away from the active edge.
        sp_cs = 1'b1; // Enable the full-word single-port write.
        sp_we = 1'b1; // Select single-port write mode.
        sp_addr = 8'd7; // Select the directed single-port test address.
        sp_wdata = 32'hdeadbeef; // Provide the baseline single-port word.
        sp_wmask = 4'b1111; // Enable every baseline byte write.
        @(negedge clk); // Wait until the baseline write has committed.
        sp_wdata = 32'h00001234; // Provide replacement data for the low bytes.
        sp_wmask = 4'b0011; // Enable only the low two byte lanes.
        @(negedge clk); // Wait until the masked write has committed.
        sp_we = 1'b0; // Select single-port read mode.
        sp_wmask = 4'b0000; // Disable all byte writes during the read.
        @(negedge clk); // Wait until the registered read data is visible.
        sp_cs = 1'b0; // Disable the single-port SRAM after the read.
        if (sp_rdata !== 32'hdead1234) begin // Check active-high byte-mask behavior.
            $display("KD28_FAIL sp expected=dead1234 observed=%08x", sp_rdata); // Report the single-port mismatch.
            errors = errors + 1; // Count the single-port failure.
        end // End the single-port data check.

        sdp_wcs = 1'b1; // Enable a simple-dual-port write.
        sdp_waddr = 8'd19; // Select the directed simple-dual-port address.
        sdp_wdata = 32'h13579bdf; // Provide simple-dual-port test data.
        sdp_wmask = 4'b1111; // Enable every simple-dual-port byte lane.
        @(negedge clk); // Wait until the simple-dual-port write has committed.
        sdp_wcs = 1'b0; // Disable the simple-dual-port write port.
        sdp_rcs = 1'b1; // Enable a simple-dual-port registered read.
        sdp_raddr = 8'd19; // Read the address written by the other port.
        @(negedge clk); // Wait until the simple-dual-port read data is visible.
        sdp_rcs = 1'b0; // Disable the simple-dual-port read port.
        if (sdp_rdata !== 32'h13579bdf) begin // Check independent write and read port behavior.
            $display("KD28_FAIL sdp expected=13579bdf observed=%08x", sdp_rdata); // Report the simple-dual-port mismatch.
            errors = errors + 1; // Count the simple-dual-port failure.
        end // End the simple-dual-port data check.

        tdp_acs = 1'b1; // Enable a true-dual-port port A write.
        tdp_awe = 1'b1; // Select port A write mode.
        tdp_aaddr = 5'd3; // Select the directed port A address.
        tdp_awdata = 32'ha5a55a5a; // Provide the port A test word.
        tdp_awmask = 4'b1111; // Enable every port A byte lane.
        tdp_bcs = 1'b1; // Enable a concurrent true-dual-port port B write.
        tdp_bwe = 1'b1; // Select port B write mode.
        tdp_baddr = 5'd9; // Select a distinct directed port B address.
        tdp_bwdata = 32'h55aa33cc; // Provide the port B test word.
        tdp_bwmask = 4'b1111; // Enable every port B byte lane.
        @(negedge clk); // Wait until both noncolliding writes have committed.
        tdp_awe = 1'b0; // Select port A read mode.
        tdp_bwe = 1'b0; // Select port B read mode.
        @(negedge clk); // Wait until both registered read words are visible.
        tdp_acs = 1'b0; // Disable true-dual-port port A.
        tdp_bcs = 1'b0; // Disable true-dual-port port B.
        if (tdp_ardata !== 32'ha5a55a5a || tdp_brdata !== 32'h55aa33cc) begin // Check independent true-dual-port words.
            $display("KD28_FAIL tdp a=%08x b=%08x", tdp_ardata, tdp_brdata); // Report the true-dual-port mismatch.
            errors = errors + 1; // Count the true-dual-port failure.
        end // End the true-dual-port data check.

        for (expected = 1; expected <= 5; expected = expected + 1) begin // Fill the exact five-word synchronous FIFO capacity.
            @(negedge clk); // Align producer stimulus away from the active edge.
            if (!sync_write_ready) begin // Require capacity before every expected accepted write.
                $display("KD28_FAIL sync FIFO became full before word %0d", expected); // Report premature backpressure.
                errors = errors + 1; // Count the synchronous FIFO capacity failure.
            end // End the premature-full check.
            sync_write_data = expected; // Drive the ordered synchronous FIFO payload.
            sync_write_valid = 1'b1; // Assert producer validity for one transfer.
            @(negedge clk); // Wait until the producer transfer has occurred.
            sync_write_valid = 1'b0; // Deassert producer validity after one transfer.
        end // End the synchronous FIFO fill loop.
        @(negedge clk); // Allow occupancy backpressure to settle.
        if (sync_write_ready) begin // Require exact backpressure at five stored words.
            $display("KD28_FAIL sync FIFO did not assert full backpressure"); // Report incorrect exact-depth behavior.
            errors = errors + 1; // Count the synchronous FIFO full failure.
        end // End the exact-depth full check.
        for (expected = 1; expected <= 5; expected = expected + 1) begin // Drain and verify the synchronous FIFO order.
            timeout_count = 0; // Reset the bounded output wait counter.
            while (!sync_read_valid && timeout_count < 20) begin // Wait for the registered SRAM-backed output.
                @(negedge clk); // Sample output validity between active edges.
                timeout_count = timeout_count + 1; // Advance the bounded wait counter.
            end // End the synchronous FIFO output wait.
            if (!sync_read_valid || sync_read_data !== expected[23:0]) begin // Check output validity and ordering.
                $display("KD28_FAIL sync FIFO expected=%0d valid=%0b data=%0d", expected, sync_read_valid, sync_read_data); // Report the synchronous FIFO mismatch.
                errors = errors + 1; // Count the synchronous FIFO data failure.
            end // End the synchronous FIFO data check.
            sync_read_ready = 1'b1; // Accept the checked synchronous FIFO word.
            @(posedge clk); // Cross an active edge so the consumer transfer is guaranteed to occur.
            @(negedge clk); // Return stimulus changes to the inactive clock edge.
            sync_read_ready = 1'b0; // Deassert consumer readiness between words.
        end // End the synchronous FIFO drain loop.

        for (expected = 1; expected <= 8; expected = expected + 1) begin // Fill the complete eight-word asynchronous FIFO capacity.
            @(negedge async_write_clk); // Align producer stimulus away from the write edge.
            if (!async_write_ready) begin // Require capacity before every expected accepted write.
                $display("KD28_FAIL async FIFO became full before word %0d", expected); // Report premature asynchronous backpressure.
                errors = errors + 1; // Count the asynchronous FIFO capacity failure.
            end // End the asynchronous FIFO premature-full check.
            async_write_data = 16'h4000 + expected; // Drive the ordered asynchronous FIFO payload.
            async_write_valid = 1'b1; // Assert asynchronous producer validity for one transfer.
            @(negedge async_write_clk); // Wait until the producer transfer has occurred.
            async_write_valid = 1'b0; // Deassert asynchronous producer validity after one transfer.
        end // End the asynchronous FIFO fill loop.
        repeat (4) @(posedge async_write_clk); // Allow the synchronized read pointer state to settle.
        if (async_write_ready) begin // Require conservative full backpressure after eight accepted words.
            $display("KD28_FAIL async FIFO did not assert full backpressure"); // Report incorrect Gray-pointer full behavior.
            errors = errors + 1; // Count the asynchronous FIFO full failure.
        end // End the asynchronous FIFO full check.
        for (expected = 1; expected <= 8; expected = expected + 1) begin // Check each SRAM word before asynchronous draining.
            if (u_async_fifo.u_storage.gen_depth_bank[0].gen_width_lane[0].gen_sdp_256x32.u_sram.u_model.memory[expected-1][15:0] !== (16'h4000 + expected)) begin // Require data inside the selected fixed KD28 macro instance.
                $display("KD28_FAIL async fixed SRAM address=%0d expected=%04x data=%04x", expected-1, 16'h4000 + expected, u_async_fifo.u_storage.gen_depth_bank[0].gen_width_lane[0].gen_sdp_256x32.u_sram.u_model.memory[expected-1][15:0]); // Report a fixed-macro storage mismatch.
                errors = errors + 1; // Count the asynchronous storage failure.
            end // End the asynchronous storage word check.
        end // End the asynchronous storage content loop.
        for (expected = 1; expected <= 8; expected = expected + 1) begin // Drain and verify asynchronous FIFO ordering.
            timeout_count = 0; // Reset the bounded asynchronous output wait counter.
            while (!async_read_valid && timeout_count < 40) begin // Wait for pointer synchronization and registered SRAM output.
                @(negedge async_read_clk); // Sample output validity between read-clock edges.
                timeout_count = timeout_count + 1; // Advance the bounded wait counter.
            end // End the asynchronous FIFO output wait.
            if (!async_read_valid || async_read_data !== (16'h4000 + expected)) begin // Check asynchronous output validity and ordering.
                $display("KD28_FAIL async FIFO expected=%04x valid=%0b data=%04x", 16'h4000 + expected, async_read_valid, async_read_data); // Report the asynchronous FIFO mismatch.
                errors = errors + 1; // Count the asynchronous FIFO data failure.
            end // End the asynchronous FIFO data check.
            async_read_ready = 1'b1; // Accept the checked asynchronous FIFO word.
            @(posedge async_read_clk); // Cross an active edge so the consumer transfer is guaranteed to occur.
            @(negedge async_read_clk); // Return stimulus changes to the inactive read-clock edge.
            async_read_ready = 1'b0; // Deassert asynchronous consumer readiness between words.
        end // End the asynchronous FIFO drain loop.

        if (errors == 0) begin // Select the explicit successful terminal path.
            $display("[RTL_SIM PASS] kd28_sram_fifo"); // Emit the stable KD28 regression pass signature.
        end else begin // Select the explicit failing terminal path.
            $display("[RTL_SIM FAIL] kd28_sram_fifo errors=%0d", errors); // Emit the total self-check failure count.
            $fatal(1); // Return a nonzero simulator status for any mismatch.
        end // End the terminal result selection.
        $finish; // Terminate the successful deterministic regression.
    end // End the deterministic verification process.

    initial begin // Enforce a global watchdog against a hung ready-valid sequence.
        #20000; // Bound the complete regression to twenty simulated microseconds.
        $display("[RTL_SIM FAIL] kd28_sram_fifo timeout"); // Report a stable timeout signature.
        $fatal(1); // Return a nonzero simulator status after watchdog expiry.
    end // End the watchdog process.

endmodule // End the tb_kd28_sram_fifo testbench.

`default_nettype wire // Restore implicit-net behavior after the KD28 testbench.
