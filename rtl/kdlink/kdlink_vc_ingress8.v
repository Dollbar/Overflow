module kdlink_vc_ingress8 #( // Declare the eight-VC CDC ingress and packet-aware arbiter.
    parameter integer FIFO_ADDR_BITS = 7 // Set the depth of each independently clocked VC queue.
) ( // Begin the module port list.
    input wire core_clk_i, // Receive source traffic in the core clock domain.
    input wire core_rst_n_i, // Apply the active-low core-domain reset.
    input wire core_valid_i, // Qualify one core-domain flit body.
    output wire core_ready_o, // Report space in the selected VC queue.
    input wire [2:0] core_vc_i, // Select the VC queue for the incoming flit.
    input wire [607:0] core_body_i, // Carry the 96-bit header and 512-bit payload body.
    input wire phy_clk_i, // Arbitrate queued traffic in the PHY clock domain.
    input wire phy_rst_n_i, // Apply the active-low PHY-domain reset.
    input wire [7:0] admit_i, // Qualify VCs that currently own at least one credit.
    input wire service_enable_i, // Permit normal ingress service when replay is idle.
    output wire phy_valid_o, // Qualify the selected packet body.
    input wire phy_ready_i, // Accept the selected packet body.
    output wire [2:0] phy_vc_o, // Identify the selected VC.
    output wire [607:0] phy_body_o, // Present the selected body without modification.
    output reg packet_error_o, // Latch malformed SOP or VC metadata observations.
    output wire cdc_error_o, // Report any queue overflow or underflow observation.
    output wire [7:0] audit_pending_vc_o, // Expose queue-head presence for protocol verification and debug.
    output wire audit_packet_locked_o, // Expose active packet ownership for protocol verification and debug.
    output wire [2:0] audit_packet_vc_o, // Expose the active packet owner VC for protocol verification and debug.
    output wire [3:0] audit_packet_flit_count_o // Expose the bounded active packet length for protocol verification and debug.
); // End the module port list.
    wire [7:0] queue_write_ready; // Collect write readiness from every VC FIFO.
    wire [7:0] queue_read_valid; // Collect head validity from every VC FIFO.
    reg [7:0] queue_read_ready; // Pop only the selected and accepted VC FIFO.
    wire [7:0] queue_overflow; // Collect impossible overflow observations.
    wire [7:0] queue_underflow; // Collect impossible underflow observations.
    wire [607:0] queue_read_data [0:7]; // Hold the independent PHY-domain FIFO heads.
    reg winner_valid_d; // Mark a currently eligible arbitration winner.
    reg [2:0] winner_vc_d; // Hold the currently selected VC index.
    reg [607:0] winner_body_d; // Hold the currently selected flit body.
    reg packet_locked_q; // Retain one VC from packet SOP through EOP.
    reg [2:0] packet_vc_q; // Remember the VC that owns the active packet.
    reg [3:0] packet_flit_count_q; // Count accepted flits in the active packet up to the protocol limit.
    reg [1:0] data_rr_q; // Point to the next round-robin data VC among VC1 through VC4.
    reg [2:0] data_candidate; // Form a data VC candidate during arbitration.
    integer queue_index; // Iterate over the eight queue instances and ready bits.
    integer data_offset; // Search the four data VCs from the round-robin pointer.
    wire winner_fire; // Mark an accepted PHY-domain flit.
    wire winner_sop; // Extract SOP from the selected header.
    wire winner_eop; // Extract EOP from the selected header.
    wire winner_vc_matches_header; // Check that queue selection matches header metadata.

    assign core_ready_o = queue_write_ready[core_vc_i]; // Backpressure only the selected source VC.
    assign phy_valid_o = winner_valid_d && service_enable_i; // Suppress normal traffic during replay service.
    assign phy_vc_o = winner_vc_d; // Export the registered-state-derived winner index.
    assign phy_body_o = winner_body_d; // Export the selected queue head.
    assign winner_fire = phy_valid_o && phy_ready_i; // Consume a flit only on a complete handshake.
    assign winner_sop = winner_body_d[529]; // Read the SOP field from the canonical header position.
    assign winner_eop = winner_body_d[530]; // Read the EOP field from the canonical header position.
    assign winner_vc_matches_header = winner_body_d[527:525] == winner_vc_d; // Validate per-VC enqueue metadata.
    assign cdc_error_o = (|queue_overflow) || (|queue_underflow); // Combine all FIFO protocol errors.
    assign audit_pending_vc_o = queue_read_valid; // Report synchronized queue-head presence without affecting admission.
    assign audit_packet_locked_o = packet_locked_q; // Report whether packet ownership is retained.
    assign audit_packet_vc_o = packet_vc_q; // Report the retained packet owner VC.
    assign audit_packet_flit_count_o = packet_flit_count_q; // Report accepted flits in the retained packet.

    genvar vc_index; // Declare the generate-loop VC index.
    generate // Instantiate one CDC FIFO for each virtual channel.
        for (vc_index = 0; vc_index < 8; vc_index = vc_index + 1) begin : g_vc_fifo // Build one isolated queue.
            coll_async_fifo #( // Configure the shared asynchronous FIFO implementation.
                .WIDTH(608), // Store the complete replayable body in every entry.
                .ADDR_W(FIFO_ADDR_BITS) // Apply the configured per-VC queue depth.
            ) u_vc_fifo ( // Instantiate the selected virtual-channel FIFO.
                .write_clk_i(core_clk_i), // Use the core clock for source writes.
                .write_rst_n_i(core_rst_n_i), // Reset the write-side state with the core reset.
                .write_data_i(core_body_i), // Broadcast data while qualifying only one queue.
                .write_valid_i(core_valid_i && (core_vc_i == vc_index[2:0])), // Enqueue the selected VC.
                .write_ready_o(queue_write_ready[vc_index]), // Return independent queue capacity.
                .read_clk_i(phy_clk_i), // Use the PHY clock for arbitration reads.
                .read_rst_n_i(phy_rst_n_i), // Reset the read-side state with the PHY reset.
                .read_data_o(queue_read_data[vc_index]), // Expose this VC head to the arbiter.
                .read_valid_o(queue_read_valid[vc_index]), // Qualify this VC head.
                .read_ready_i(queue_read_ready[vc_index]), // Pop only after the selected transfer.
                .overflow_o(queue_overflow[vc_index]), // Report illegal write-side overflow.
                .underflow_o(queue_underflow[vc_index]) // Report illegal read-side underflow.
            ); // Complete this virtual-channel FIFO instance.
        end // Complete the generated VC FIFO body.
    endgenerate // Complete all eight FIFO instances.

    always @(*) begin // Select a packet owner from eligible queue heads.
        winner_valid_d = 1'b0; // Default to no eligible winner.
        winner_vc_d = 3'd0; // Default the selected VC index.
        winner_body_d = 608'd0; // Default the selected body.
        data_candidate = 3'd1; // Default the temporary data candidate.
        data_offset = 0; // Default the procedural search index for latch-free synthesis diagnostics.
        if (packet_locked_q) begin // Preserve packet ownership until its EOP is accepted.
            if (queue_read_valid[packet_vc_q] && admit_i[packet_vc_q]) begin // Check owner eligibility.
                winner_valid_d = 1'b1; // Qualify the locked packet owner.
                winner_vc_d = packet_vc_q; // Retain the locked VC.
                winner_body_d = queue_read_data[packet_vc_q]; // Present the next packet flit.
            end // Complete locked-owner eligibility handling.
        end else if (queue_read_valid[3'd7] && admit_i[3'd7]) begin // Give management traffic first priority.
            winner_valid_d = 1'b1; // Qualify management traffic.
            winner_vc_d = 3'd7; // Select the management VC.
            winner_body_d = queue_read_data[3'd7]; // Present the management head.
        end else if (queue_read_valid[3'd6] && admit_i[3'd6]) begin // Give explicit replay traffic next priority.
            winner_valid_d = 1'b1; // Qualify replay traffic.
            winner_vc_d = 3'd6; // Select the replay VC.
            winner_body_d = queue_read_data[3'd6]; // Present the replay head.
        end else if (queue_read_valid[3'd5] && admit_i[3'd5]) begin // Give control traffic third priority.
            winner_valid_d = 1'b1; // Qualify control traffic.
            winner_vc_d = 3'd5; // Select the control VC.
            winner_body_d = queue_read_data[3'd5]; // Present the control head.
        end else if (queue_read_valid[3'd0] && admit_i[3'd0]) begin // Preserve the deterministic escape service.
            winner_valid_d = 1'b1; // Qualify escape traffic.
            winner_vc_d = 3'd0; // Select the escape VC.
            winner_body_d = queue_read_data[3'd0]; // Present the escape head.
        end else begin // Round-robin arbitrate ordinary data traffic.
            for (data_offset = 0; data_offset < 4; data_offset = data_offset + 1) begin // Search every data VC.
                data_candidate = {1'b0, data_rr_q + data_offset[1:0]} + 3'd1; // Map modulo-four order to VC1-VC4.
                if (!winner_valid_d && queue_read_valid[data_candidate] && admit_i[data_candidate]) begin // Capture one winner.
                    winner_valid_d = 1'b1; // Qualify the first eligible data VC.
                    winner_vc_d = data_candidate; // Save the chosen data VC.
                    winner_body_d = queue_read_data[data_candidate]; // Present the chosen queue head.
                end // Complete one data-candidate check.
            end // Complete the bounded data-VC search.
        end // Complete arbitration policy selection.
    end // Complete combinational arbitration.

    always @(*) begin // Generate exactly one FIFO pop for an accepted winner.
        queue_read_ready = 8'd0; // Default every VC pop signal low.
        for (queue_index = 0; queue_index < 8; queue_index = queue_index + 1) begin // Decode the winner index.
            if (winner_fire && (winner_vc_d == queue_index[2:0])) queue_read_ready[queue_index] = 1'b1; // Pop the winner.
        end // Complete the one-hot pop decode.
    end // Complete FIFO read-ready generation.

    always @(posedge phy_clk_i or negedge phy_rst_n_i) begin // Track packet ownership and fairness state.
        if (!phy_rst_n_i) begin // Reset all PHY-domain arbitration state.
            packet_locked_q <= 1'b0; // Release any packet owner.
            packet_vc_q <= 3'd0; // Clear the remembered owner index.
            packet_flit_count_q <= 4'd0; // Clear the active packet length counter.
            data_rr_q <= 2'd0; // Begin data arbitration at VC1.
            packet_error_o <= 1'b0; // Clear the sticky packet-format error.
        end else begin // Update arbitration state after accepted transfers.
            if (winner_fire) begin // Inspect only a transferred flit.
                if (!winner_vc_matches_header) packet_error_o <= 1'b1; // Detect inconsistent VC metadata.
                if (!packet_locked_q && !winner_sop) packet_error_o <= 1'b1; // Require SOP at packet acquisition.
                if (packet_locked_q && winner_sop) packet_error_o <= 1'b1; // Reject a second SOP inside a packet.
                if (!packet_locked_q && winner_sop && !winner_eop) begin // Acquire a multi-flit packet.
                    packet_locked_q <= 1'b1; // Hold this VC across the packet body.
                    packet_vc_q <= winner_vc_d; // Remember the packet owner.
                    packet_flit_count_q <= 4'd1; // Count the accepted SOP as the first packet flit.
                end // Complete packet acquisition.
                if (packet_locked_q && winner_eop) begin // Release ownership at a valid packet terminator.
                    packet_locked_q <= 1'b0; // Permit a new arbitration winner after EOP.
                    packet_flit_count_q <= 4'd0; // Clear the completed packet length.
                end else if (packet_locked_q && packet_flit_count_q == 4'd15) begin // Reject a missing EOP on the sixteenth transfer.
                    packet_locked_q <= 1'b0; // Release the malformed packet owner after the sixteenth flit.
                    packet_flit_count_q <= 4'd0; // Clear the malformed packet length state.
                    packet_error_o <= 1'b1; // Report the missing EOP at the protocol packet-length limit.
                end else if (packet_locked_q) begin // Count another accepted body flit.
                    packet_flit_count_q <= packet_flit_count_q + 1'b1; // Advance the bounded packet length.
                end // Complete packet termination and length handling.
                if (winner_eop && (winner_vc_d >= 3'd1) && (winner_vc_d <= 3'd4)) begin // Advance data fairness.
                    data_rr_q <= winner_vc_d[1:0]; // Start after the completed data VC on the next arbitration.
                end // Complete data round-robin advancement.
            end // Complete accepted-flit state handling.
        end // Complete active-state arbitration updates.
    end // Complete the PHY-domain sequential process.
endmodule // Complete the eight-VC ingress module.
