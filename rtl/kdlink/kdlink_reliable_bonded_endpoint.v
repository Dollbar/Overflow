module kdlink_reliable_bonded_endpoint #( // Declare the canonical two-slice reliable bonded endpoint.
    parameter [15:0] INITIAL_CREDITS = 16'd64, // Set each logical slice receive capacity.
    parameter integer REPLAY_SLOT_BITS = 9, // Set each logical slice replay-window size.
    parameter [15:0] REPLAY_TIMEOUT_CYCLES = 16'd4096, // Set ACK-loss replay timeout.
    parameter integer KEEPALIVE_CYCLES = 1024, // Set reverse-channel heartbeat interval.
    parameter integer LINK_TIMEOUT_CYCLES = 8192 // Set reverse-channel peer timeout.
) ( // Begin the bonded endpoint port list.
    input wire core_clk_i, // Receive and commit tensor traffic in the core domain.
    input wire core_rst_n_i, // Apply the active-low core-domain reset.
    input wire phy_clk_i, // Run both logical links and physical mapping in the PHY domain.
    input wire phy_rst_n_i, // Apply the active-low PHY-domain reset.
    input wire [4:0] local_node_i, // Identify the local NPU node.
    input wire [4:0] peer_node_i, // Identify the directly connected peer NPU node.
    input wire [7:0] link_epoch_i, // Receive the system-owned link epoch.
    input wire link_enable_i, // Enable bilateral link management.
    input wire [1:0] configured_slice_mask_i, // Enable each physical slice by configuration.
    input wire [1:0] slice_fault_i, // Remove failed physical slices from service.
    input wire [1:0] tx_valid_i, // Qualify one core flit for each logical slice.
    output wire [1:0] tx_ready_o, // Return independent logical-slice ingress capacity.
    input wire [191:0] tx_header_i, // Carry two canonical 96-bit headers.
    input wire [1023:0] tx_payload_i, // Carry two independent 512-bit payloads.
    input wire [13:0] tx_payload_bytes_i, // Carry two payload byte counts.
    output wire [1:0] rx_commit_valid_o, // Qualify committed exact-once logical-slice data.
    input wire [1:0] rx_commit_ready_i, // Accept committed data independently per logical slice.
    output wire [191:0] rx_commit_header_o, // Return two committed headers.
    output wire [1023:0] rx_commit_payload_o, // Return two committed payloads.
    output wire [13:0] rx_commit_payload_bytes_o, // Return two committed byte counts.
    output wire [1:0] rx_commit_last_o, // Mark the final flit of each committed packet.
    output wire [1:0] phy_forward_tx_valid_o, // Drive up to two physical forward flits.
    output wire [1279:0] phy_forward_tx_flit_o, // Drive the two physical forward interfaces.
    input wire [1:0] phy_forward_rx_valid_i, // Receive up to two physical forward flits.
    input wire [1279:0] phy_forward_rx_flit_i, // Receive the two physical forward interfaces.
    output wire [1:0] phy_reverse_tx_valid_o, // Drive up to two physical reverse words.
    output wire [255:0] phy_reverse_tx_word_o, // Drive the two physical reverse interfaces.
    input wire [1:0] phy_reverse_rx_valid_i, // Receive up to two physical reverse words.
    input wire [255:0] phy_reverse_rx_word_i, // Receive the two physical reverse interfaces.
    output wire [1:0] logical_link_up_o, // Report bilateral state for both logical slices.
    output wire [1:0] active_slice_mask_o, // Report configured and healthy physical slices.
    output wire degraded_o, // Report operation through exactly one physical slice.
    output wire link_down_o, // Report loss of all physical slices.
    output reg epoch_recovery_required_o, // Request a new epoch after the physical slice map changes.
    output reg mapping_error_o, // Latch an invalid or colliding physical-to-logical mapping.
    output wire reliability_error_o, // Combine endpoint credit replay protocol and CDC errors.
    output wire [2*(REPLAY_SLOT_BITS+1)-1:0] replay_occupancy_o // Report both replay occupancies.
); // End the bonded endpoint port list.
    wire [1:0] active_mask; // Hold the configured and healthy physical slice mask.
    wire any_active; // Mark at least one usable physical slice.
    wire [1:0] endpoint_forward_request; // Collect pre-packetizer service requests.
    reg [1:0] endpoint_forward_grant; // Grant packetizer input service per logical slice.
    wire [1:0] endpoint_reverse_request; // Collect pre-codec reverse service requests.
    reg [1:0] endpoint_reverse_grant; // Grant reverse-codec input service per logical slice.
    reg forward_rr_q; // Select the next logical forward stream in degraded mode.
    reg reverse_rr_q; // Select the next logical reverse stream in degraded mode.
    wire [1:0] endpoint_forward_valid; // Collect packetized logical-slice forward flits.
    wire [1279:0] endpoint_forward_flit; // Collect packetized logical-slice forward data.
    wire [1:0] endpoint_reverse_valid; // Collect encoded logical-slice reverse words.
    wire [255:0] endpoint_reverse_word; // Collect encoded logical-slice reverse data.
    wire [1:0] endpoint_forward_fifo_ready; // Report elastic output capacity per logical slice.
    wire [1:0] endpoint_forward_fifo_valid; // Qualify elastic forward FIFO heads.
    wire [1279:0] endpoint_forward_fifo_data; // Carry elastic forward FIFO heads.
    reg [1:0] endpoint_forward_fifo_pop; // Consume selected forward FIFO heads.
    wire [1:0] endpoint_reverse_fifo_ready; // Report elastic reverse capacity per logical slice.
    wire [1:0] endpoint_reverse_fifo_valid; // Qualify elastic reverse FIFO heads.
    wire [255:0] endpoint_reverse_fifo_data; // Carry elastic reverse FIFO heads.
    reg [1:0] endpoint_reverse_fifo_pop; // Consume selected reverse FIFO heads.
    reg [1:0] physical_forward_valid_d; // Form physical forward valid signals.
    reg [1279:0] physical_forward_flit_d; // Form physical forward flit signals.
    reg [1:0] physical_reverse_valid_d; // Form physical reverse valid signals.
    reg [255:0] physical_reverse_word_d; // Form physical reverse word signals.
    reg [1:0] logical_forward_rx_valid_d; // Route physical forward flits by logical packet identity.
    reg [1279:0] logical_forward_rx_flit_d; // Carry routed forward flits to logical endpoints.
    reg [1:0] logical_reverse_rx_valid_d; // Route physical reverse words by logical slice identity.
    reg [255:0] logical_reverse_rx_word_d; // Carry routed reverse words to logical endpoints.
    wire [1:0] endpoint_retry_exhausted; // Collect retry-budget exhaustion indications.
    wire [1:0] endpoint_credit_error; // Collect cumulative-credit errors.
    wire [1:0] endpoint_reverse_error; // Collect reverse-codec errors.
    wire [1:0] endpoint_protocol_error; // Collect packet and commit errors.
    wire [1:0] endpoint_cdc_error; // Collect explicit CDC FIFO errors.
    wire [1:0] forward_fifo_error; // Collect forward elastic FIFO errors.
    wire [1:0] reverse_fifo_error; // Collect reverse elastic FIFO errors.
    wire [1:0] forward_fifo_underflow; // Collect forward FIFO underflow diagnostics.
    wire [1:0] reverse_fifo_underflow; // Collect reverse FIFO underflow diagnostics.
    wire [19:0] forward_fifo_occupancy; // Observe both deep forward FIFO occupancies.
    wire [11:0] reverse_fifo_occupancy; // Observe both reverse FIFO occupancies.
    wire [255:0] endpoint_credit_count; // Observe both logical credit banks.
    wire [5:0] endpoint_link_state; // Observe both logical management states.
    wire [1:0] endpoint_replay_timeout; // Observe timeout-driven replay events.
    wire [1:0] endpoint_duplicate_drop; // Observe exact-once duplicate suppression.
    wire forward_grant_fire; // Mark one degraded-mode forward service grant.
    wire reverse_grant_fire; // Mark one degraded-mode reverse service grant.
    reg active_mask_valid_q; // Mark the first sampled physical slice map as initialized.
    reg [1:0] active_mask_q; // Remember the physical slice map for change detection.
    reg [7:0] recovery_epoch_q; // Remember the epoch in which the map change occurred.

    assign active_mask = configured_slice_mask_i & ~slice_fault_i; // Remove failed physical slices.
    assign any_active = |active_mask; // Detect a usable physical transport.
    assign active_slice_mask_o = active_mask; // Export the physical availability mask.
    assign degraded_o = active_mask[0] ^ active_mask[1]; // Detect single-slice operation.
    assign link_down_o = !any_active; // Detect total physical transport loss.
    assign forward_grant_fire = |(endpoint_forward_grant & endpoint_forward_request); // Observe scheduling.
    assign reverse_grant_fire = |(endpoint_reverse_grant & endpoint_reverse_request); // Observe scheduling.
    assign phy_forward_tx_valid_o = physical_forward_valid_d; // Export mapped forward valids.
    assign phy_forward_tx_flit_o = physical_forward_flit_d; // Export mapped forward flits.
    assign phy_reverse_tx_valid_o = physical_reverse_valid_d; // Export mapped reverse valids.
    assign phy_reverse_tx_word_o = physical_reverse_word_d; // Export mapped reverse words.
    assign reliability_error_o = (|endpoint_retry_exhausted) || (|endpoint_credit_error) || // Combine reliability failures.
        (|endpoint_reverse_error) || (|endpoint_protocol_error) || (|endpoint_cdc_error) || // Include endpoint errors.
        (|forward_fifo_error) || (|reverse_fifo_error) || (|forward_fifo_underflow) || // Include FIFO errors.
        (|reverse_fifo_underflow) || mapping_error_o; // Include bonded mapping errors.

    always @(*) begin // Schedule pre-codec logical traffic against available physical bandwidth.
        endpoint_forward_grant = 2'b00; // Default to no forward service grant.
        endpoint_reverse_grant = 2'b00; // Default to no reverse service grant.
        if (active_mask == 2'b11) begin // Preserve independent full-rate physical slices.
            endpoint_forward_grant = endpoint_forward_request; // Grant both independent forward pipelines.
            endpoint_reverse_grant = endpoint_reverse_request; // Grant both independent reverse pipelines.
        end else if (any_active) begin // Share one surviving physical slice.
            if (endpoint_forward_request == 2'b11) begin // Resolve simultaneous forward requests.
                endpoint_forward_grant[forward_rr_q] = 1'b1; // Grant the round-robin logical slice.
            end else begin // Pass a single forward request directly.
                endpoint_forward_grant = endpoint_forward_request; // Preserve the requesting logical slice.
            end // Complete degraded forward arbitration.
            if (endpoint_reverse_request == 2'b11) begin // Resolve simultaneous reverse requests.
                endpoint_reverse_grant[reverse_rr_q] = 1'b1; // Grant the round-robin logical slice.
            end else begin // Pass a single reverse request directly.
                endpoint_reverse_grant = endpoint_reverse_request; // Preserve the requesting logical slice.
            end // Complete degraded reverse arbitration.
        end // Complete physical-capacity scheduling.
    end // Complete pre-codec service arbitration.

    genvar logical_slice; // Declare the logical endpoint generate index.
    generate // Instantiate two complete canonical reliable endpoints.
        for (logical_slice = 0; logical_slice < 2; logical_slice = logical_slice + 1) begin : g_endpoint // Build one logical slice.
            kdlink_reliable_endpoint #( // Configure one canonical reliability instance.
                .INITIAL_CREDITS(INITIAL_CREDITS), // Apply the logical receive capacity.
                .REPLAY_SLOT_BITS(REPLAY_SLOT_BITS), // Apply the replay window size.
                .REPLAY_TIMEOUT_CYCLES(REPLAY_TIMEOUT_CYCLES), // Apply ACK-loss timeout.
                .KEEPALIVE_CYCLES(KEEPALIVE_CYCLES), // Apply heartbeat interval.
                .LINK_TIMEOUT_CYCLES(LINK_TIMEOUT_CYCLES) // Apply peer watchdog interval.
            ) u_endpoint ( // Instantiate the canonical logical slice endpoint.
                .core_clk_i(core_clk_i), .core_rst_n_i(core_rst_n_i), // Connect the core clock domain.
                .phy_clk_i(phy_clk_i), .phy_rst_n_i(phy_rst_n_i), // Connect the PHY clock domain.
                .local_node_i(local_node_i), .peer_node_i(peer_node_i), // Connect direct-link identities.
                .local_slice_i(logical_slice[0]), // Encode logical slice identity in reverse words.
                .link_enable_i(link_enable_i && any_active), // Manage both logical links over any healthy transport.
                .tx_service_grant_i(endpoint_forward_grant[logical_slice]), // Schedule forward CRC input.
                .reverse_service_grant_i(endpoint_reverse_grant[logical_slice]), // Schedule reverse-codec input.
                .link_epoch_i(link_epoch_i), // Apply the system-owned link epoch.
                .tx_valid_i(tx_valid_i[logical_slice]), .tx_ready_o(tx_ready_o[logical_slice]), // Connect core TX handshake.
                .tx_header_i(tx_header_i[logical_slice*96 +: 96]), // Connect the logical header.
                .tx_payload_i(tx_payload_i[logical_slice*512 +: 512]), // Connect the logical payload.
                .tx_payload_bytes_i(tx_payload_bytes_i[logical_slice*7 +: 7]), // Connect valid bytes.
                .rx_commit_valid_o(rx_commit_valid_o[logical_slice]), // Export committed logical data.
                .rx_commit_ready_i(rx_commit_ready_i[logical_slice]), // Accept committed logical data.
                .rx_commit_header_o(rx_commit_header_o[logical_slice*96 +: 96]), // Export committed header.
                .rx_commit_payload_o(rx_commit_payload_o[logical_slice*512 +: 512]), // Export committed payload.
                .rx_commit_payload_bytes_o(rx_commit_payload_bytes_o[logical_slice*7 +: 7]), // Export bytes.
                .rx_commit_last_o(rx_commit_last_o[logical_slice]), // Export packet completion.
                .phy_forward_tx_valid_o(endpoint_forward_valid[logical_slice]), // Capture packetized forward data.
                .phy_forward_tx_flit_o(endpoint_forward_flit[logical_slice*640 +: 640]), // Capture forward flit.
                .phy_forward_rx_valid_i(logical_forward_rx_valid_d[logical_slice]), // Route physical RX by packet identity.
                .phy_forward_rx_flit_i(logical_forward_rx_flit_d[logical_slice*640 +: 640]), // Route forward body.
                .phy_reverse_tx_valid_o(endpoint_reverse_valid[logical_slice]), // Capture encoded reverse data.
                .phy_reverse_tx_word_o(endpoint_reverse_word[logical_slice*128 +: 128]), // Capture reverse word.
                .phy_reverse_rx_valid_i(logical_reverse_rx_valid_d[logical_slice]), // Route reverse RX by slice ID.
                .phy_reverse_rx_word_i(logical_reverse_rx_word_d[logical_slice*128 +: 128]), // Route reverse word.
                .tx_credit_count_o(endpoint_credit_count[logical_slice*128 +: 128]), // Observe detailed credits.
                .replay_occupancy_o(replay_occupancy_o[logical_slice*(REPLAY_SLOT_BITS+1) +: (REPLAY_SLOT_BITS+1)]), // Export replay occupancy.
                .link_up_o(logical_link_up_o[logical_slice]), // Export logical link state.
                .link_state_o(endpoint_link_state[logical_slice*3 +: 3]), // Observe management state.
                .replay_timeout_o(endpoint_replay_timeout[logical_slice]), // Observe timeout replay.
                .tx_service_request_o(endpoint_forward_request[logical_slice]), // Export forward demand.
                .reverse_service_request_o(endpoint_reverse_request[logical_slice]), // Export reverse demand.
                .retry_exhausted_o(endpoint_retry_exhausted[logical_slice]), // Collect retry errors.
                .duplicate_drop_o(endpoint_duplicate_drop[logical_slice]), // Observe duplicate suppression.
                .credit_error_o(endpoint_credit_error[logical_slice]), // Collect reliability status.
                .reverse_error_o(endpoint_reverse_error[logical_slice]), // Collect reverse errors.
                .protocol_error_o(endpoint_protocol_error[logical_slice]), // Collect protocol errors.
                .cdc_error_o(endpoint_cdc_error[logical_slice]) // Collect CDC errors.
            ); // Complete the logical endpoint instance.

            coll_sync_fifo #(.WIDTH(640), .DEPTH(512), .ADDR_W(9), .COUNT_W(10)) u_forward_elastic ( // Buffer CRC pipeline drain.
                .clk_i(phy_clk_i), .rst_n_i(phy_rst_n_i), // Connect the PHY clock and reset.
                .push_data_i(endpoint_forward_flit[logical_slice*640 +: 640]), // Store one packetized flit.
                .push_valid_i(endpoint_forward_valid[logical_slice]), // Qualify packetizer output.
                .push_ready_o(endpoint_forward_fifo_ready[logical_slice]), // Report bonded elastic capacity.
                .pop_data_o(endpoint_forward_fifo_data[logical_slice*640 +: 640]), // Expose one logical head.
                .pop_valid_o(endpoint_forward_fifo_valid[logical_slice]), // Qualify one logical head.
                .pop_ready_i(endpoint_forward_fifo_pop[logical_slice]), // Consume after physical mapping.
                .occupancy_o(forward_fifo_occupancy[logical_slice*10 +: 10]), // Observe elastic occupancy.
                .overflow_o(forward_fifo_error[logical_slice]), // Report impossible overflow.
                .underflow_o(forward_fifo_underflow[logical_slice]) // Report impossible underflow.
            ); // Complete the forward elastic FIFO.

            coll_sync_fifo #(.WIDTH(128), .DEPTH(32), .ADDR_W(5), .COUNT_W(6)) u_reverse_elastic ( // Buffer reverse codec drain.
                .clk_i(phy_clk_i), .rst_n_i(phy_rst_n_i), // Connect the PHY clock and reset.
                .push_data_i(endpoint_reverse_word[logical_slice*128 +: 128]), // Store one encoded reverse word.
                .push_valid_i(endpoint_reverse_valid[logical_slice]), // Qualify reverse codec output.
                .push_ready_o(endpoint_reverse_fifo_ready[logical_slice]), // Report reverse elastic capacity.
                .pop_data_o(endpoint_reverse_fifo_data[logical_slice*128 +: 128]), // Expose one reverse head.
                .pop_valid_o(endpoint_reverse_fifo_valid[logical_slice]), // Qualify one reverse head.
                .pop_ready_i(endpoint_reverse_fifo_pop[logical_slice]), // Consume after physical mapping.
                .occupancy_o(reverse_fifo_occupancy[logical_slice*6 +: 6]), // Observe elastic occupancy.
                .overflow_o(reverse_fifo_error[logical_slice]), // Report impossible overflow.
                .underflow_o(reverse_fifo_underflow[logical_slice]) // Report impossible underflow.
            ); // Complete the reverse elastic FIFO.
        end // Complete one logical slice generate body.
    endgenerate // Complete both logical reliable endpoints.

    always @(*) begin // Map logical forward FIFO heads onto healthy physical slices.
        physical_forward_valid_d = 2'b00; // Default both physical forward links idle.
        physical_forward_flit_d = 1280'd0; // Default both physical forward flits clear.
        endpoint_forward_fifo_pop = 2'b00; // Default both logical FIFO heads retained.
        if (active_mask == 2'b11) begin // Use one-to-one full-bandwidth mapping.
            physical_forward_valid_d = endpoint_forward_fifo_valid; // Preserve independent valids.
            physical_forward_flit_d = endpoint_forward_fifo_data; // Preserve independent flits.
            endpoint_forward_fifo_pop = endpoint_forward_fifo_valid; // Consume every presented physical flit.
        end else if (active_mask == 2'b01) begin // Share physical slice zero.
            if (endpoint_forward_fifo_valid[forward_rr_q]) begin // Prefer the round-robin logical slice.
                physical_forward_valid_d[0] = 1'b1; // Qualify physical slice zero.
                physical_forward_flit_d[639:0] = endpoint_forward_fifo_data[forward_rr_q*640 +: 640]; // Select its flit.
                endpoint_forward_fifo_pop[forward_rr_q] = 1'b1; // Consume the selected logical head.
            end else if (endpoint_forward_fifo_valid[!forward_rr_q]) begin // Fall back to the other logical slice.
                physical_forward_valid_d[0] = 1'b1; // Qualify physical slice zero.
                physical_forward_flit_d[639:0] = endpoint_forward_fifo_data[(!forward_rr_q)*640 +: 640]; // Select fallback.
                endpoint_forward_fifo_pop[!forward_rr_q] = 1'b1; // Consume the fallback logical head.
            end // Complete physical-zero arbitration.
        end else if (active_mask == 2'b10) begin // Share physical slice one.
            if (endpoint_forward_fifo_valid[forward_rr_q]) begin // Prefer the round-robin logical slice.
                physical_forward_valid_d[1] = 1'b1; // Qualify physical slice one.
                physical_forward_flit_d[1279:640] = endpoint_forward_fifo_data[forward_rr_q*640 +: 640]; // Select its flit.
                endpoint_forward_fifo_pop[forward_rr_q] = 1'b1; // Consume the selected logical head.
            end else if (endpoint_forward_fifo_valid[!forward_rr_q]) begin // Fall back to the other logical slice.
                physical_forward_valid_d[1] = 1'b1; // Qualify physical slice one.
                physical_forward_flit_d[1279:640] = endpoint_forward_fifo_data[(!forward_rr_q)*640 +: 640]; // Select fallback.
                endpoint_forward_fifo_pop[!forward_rr_q] = 1'b1; // Consume the fallback logical head.
            end // Complete physical-one arbitration.
        end // Complete physical forward mapping selection.
    end // Complete physical forward mapping.

    always @(*) begin // Map logical reverse FIFO heads onto healthy physical slices.
        physical_reverse_valid_d = 2'b00; // Default both physical reverse links idle.
        physical_reverse_word_d = 256'd0; // Default both physical reverse words clear.
        endpoint_reverse_fifo_pop = 2'b00; // Default both logical reverse heads retained.
        if (active_mask == 2'b11) begin // Use one-to-one full-bandwidth mapping.
            physical_reverse_valid_d = endpoint_reverse_fifo_valid; // Preserve independent reverse valids.
            physical_reverse_word_d = endpoint_reverse_fifo_data; // Preserve independent reverse words.
            endpoint_reverse_fifo_pop = endpoint_reverse_fifo_valid; // Consume every presented reverse word.
        end else if (active_mask == 2'b01) begin // Share physical reverse slice zero.
            if (endpoint_reverse_fifo_valid[reverse_rr_q]) begin // Prefer the round-robin logical slice.
                physical_reverse_valid_d[0] = 1'b1; // Qualify physical slice zero.
                physical_reverse_word_d[127:0] = endpoint_reverse_fifo_data[reverse_rr_q*128 +: 128]; // Select word.
                endpoint_reverse_fifo_pop[reverse_rr_q] = 1'b1; // Consume the selected logical head.
            end else if (endpoint_reverse_fifo_valid[!reverse_rr_q]) begin // Fall back to the other logical slice.
                physical_reverse_valid_d[0] = 1'b1; // Qualify physical slice zero.
                physical_reverse_word_d[127:0] = endpoint_reverse_fifo_data[(!reverse_rr_q)*128 +: 128]; // Select fallback.
                endpoint_reverse_fifo_pop[!reverse_rr_q] = 1'b1; // Consume the fallback logical head.
            end // Complete physical-zero reverse arbitration.
        end else if (active_mask == 2'b10) begin // Share physical reverse slice one.
            if (endpoint_reverse_fifo_valid[reverse_rr_q]) begin // Prefer the round-robin logical slice.
                physical_reverse_valid_d[1] = 1'b1; // Qualify physical slice one.
                physical_reverse_word_d[255:128] = endpoint_reverse_fifo_data[reverse_rr_q*128 +: 128]; // Select word.
                endpoint_reverse_fifo_pop[reverse_rr_q] = 1'b1; // Consume the selected logical head.
            end else if (endpoint_reverse_fifo_valid[!reverse_rr_q]) begin // Fall back to the other logical slice.
                physical_reverse_valid_d[1] = 1'b1; // Qualify physical slice one.
                physical_reverse_word_d[255:128] = endpoint_reverse_fifo_data[(!reverse_rr_q)*128 +: 128]; // Select fallback.
                endpoint_reverse_fifo_pop[!reverse_rr_q] = 1'b1; // Consume the fallback logical head.
            end // Complete physical-one reverse arbitration.
        end // Complete physical reverse mapping selection.
    end // Complete physical reverse mapping.

    always @(*) begin // Route physical forward traffic to logical slices by packet-sequence parity.
        logical_forward_rx_valid_d = 2'b00; // Default both logical receivers idle.
        logical_forward_rx_flit_d = 1280'd0; // Default both logical receive flits clear.
        if (phy_forward_rx_valid_i[0]) begin // Decode physical slice zero when valid.
            logical_forward_rx_valid_d[phy_forward_rx_flit_i[582]] = 1'b1; // Select logical slice by sequence parity.
            logical_forward_rx_flit_d[phy_forward_rx_flit_i[582]*640 +: 640] = phy_forward_rx_flit_i[639:0]; // Route flit.
        end // Complete physical slice-zero routing.
        if (phy_forward_rx_valid_i[1] && !logical_forward_rx_valid_d[phy_forward_rx_flit_i[640+582]]) begin // Avoid collision.
            logical_forward_rx_valid_d[phy_forward_rx_flit_i[640+582]] = 1'b1; // Select logical slice by sequence parity.
            logical_forward_rx_flit_d[phy_forward_rx_flit_i[640+582]*640 +: 640] = phy_forward_rx_flit_i[1279:640]; // Route flit.
        end // Complete physical slice-one routing.
    end // Complete physical forward receive routing.

    always @(*) begin // Route reverse traffic to logical slices by the encoded slice identity.
        logical_reverse_rx_valid_d = 2'b00; // Default both logical reverse receivers idle.
        logical_reverse_rx_word_d = 256'd0; // Default both logical reverse words clear.
        if (phy_reverse_rx_valid_i[0]) begin // Decode physical reverse slice zero when valid.
            logical_reverse_rx_valid_d[phy_reverse_rx_word_i[14]] = 1'b1; // Select the encoded logical slice.
            logical_reverse_rx_word_d[phy_reverse_rx_word_i[14]*128 +: 128] = phy_reverse_rx_word_i[127:0]; // Route word.
        end // Complete physical reverse slice-zero routing.
        if (phy_reverse_rx_valid_i[1] && !logical_reverse_rx_valid_d[phy_reverse_rx_word_i[128+14]]) begin // Avoid collision.
            logical_reverse_rx_valid_d[phy_reverse_rx_word_i[128+14]] = 1'b1; // Select the encoded logical slice.
            logical_reverse_rx_word_d[phy_reverse_rx_word_i[128+14]*128 +: 128] = phy_reverse_rx_word_i[255:128]; // Route word.
        end // Complete physical reverse slice-one routing.
    end // Complete physical reverse receive routing.

    always @(posedge phy_clk_i or negedge phy_rst_n_i) begin // Update degraded-mode fairness and sticky mapping status.
        if (!phy_rst_n_i) begin // Reset bonded scheduling state.
            forward_rr_q <= 1'b0; // Begin forward arbitration at logical slice zero.
            reverse_rr_q <= 1'b0; // Begin reverse arbitration at logical slice zero.
            mapping_error_o <= 1'b0; // Clear the sticky mapping error.
            active_mask_valid_q <= 1'b0; // Defer map-change detection until the first active cycle.
            active_mask_q <= 2'b00; // Clear the remembered physical slice map.
            recovery_epoch_q <= 8'd0; // Clear the fault epoch snapshot.
            epoch_recovery_required_o <= 1'b0; // Clear the system epoch request.
        end else begin // Process physical mapping events.
            if (!active_mask_valid_q) begin // Capture the initial configured transport without declaring a fault.
                active_mask_valid_q <= 1'b1; // Mark the physical map initialized.
                active_mask_q <= active_mask; // Remember the initial usable slices.
            end else if (active_mask != active_mask_q) begin // Detect degradation recovery or reconfiguration.
                active_mask_q <= active_mask; // Track the new physical slice map.
                recovery_epoch_q <= link_epoch_i; // Associate stale link state with the current epoch.
                epoch_recovery_required_o <= 1'b1; // Require system-coordinated credit renegotiation.
            end else if (epoch_recovery_required_o && (link_epoch_i != recovery_epoch_q)) begin // Observe epoch ownership response.
                epoch_recovery_required_o <= 1'b0; // Clear only after the system advances the epoch.
            end // Complete epoch recovery request tracking.
            if (degraded_o && forward_grant_fire) forward_rr_q <= !forward_rr_q; // Alternate pre-codec grants.
            if (degraded_o && reverse_grant_fire) reverse_rr_q <= !reverse_rr_q; // Alternate reverse grants.
            if ((endpoint_forward_valid[0] && !endpoint_forward_fifo_ready[0]) || // Detect forward elastic overflow.
                (endpoint_forward_valid[1] && !endpoint_forward_fifo_ready[1]) || // Check both logical streams.
                (endpoint_reverse_valid[0] && !endpoint_reverse_fifo_ready[0]) || // Detect reverse elastic overflow.
                (endpoint_reverse_valid[1] && !endpoint_reverse_fifo_ready[1])) mapping_error_o <= 1'b1; // Latch overflow.
            if (phy_forward_rx_valid_i[0] && phy_forward_rx_valid_i[1] && // Detect same-logical forward collision.
                (phy_forward_rx_flit_i[582] == phy_forward_rx_flit_i[640+582])) mapping_error_o <= 1'b1; // Latch collision.
            if (phy_reverse_rx_valid_i[0] && phy_reverse_rx_valid_i[1] && // Detect same-logical reverse collision.
                (phy_reverse_rx_word_i[14] == phy_reverse_rx_word_i[128+14])) mapping_error_o <= 1'b1; // Latch collision.
        end // Complete active bonded status updates.
    end // Complete bonded scheduling sequential logic.
endmodule // Complete the canonical reliable bonded endpoint.
