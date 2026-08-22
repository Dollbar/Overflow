`include "kdlink_defs.vh" // Import the canonical reverse-control message encodings.
module kdlink_link_manager #( // Declare the autonomous reverse-channel link manager.
    parameter [15:0] INITIAL_CREDITS = 16'd64, // Advertise the receive capacity of every VC.
    parameter integer KEEPALIVE_CYCLES = 1024, // Set the idle interval between heartbeat words.
    parameter integer TIMEOUT_CYCLES = 8192 // Set the maximum interval without peer activity.
) ( // Begin the module port list.
    input wire clk_i, // Run all management state in the PHY clock domain.
    input wire rst_n_i, // Apply the active-low PHY-domain reset.
    input wire enable_i, // Enable autonomous link establishment and monitoring.
    input wire [4:0] peer_node_i, // Identify the directly connected peer endpoint.
    input wire [7:0] link_epoch_i, // Receive the system-owned link generation identifier.
    input wire rx_activity_i, // Observe any accepted reverse-control word from the peer.
    input wire rx_credit_valid_i, // Observe one accepted cumulative-credit word.
    input wire [2:0] rx_credit_vc_i, // Identify the advertised credit VC.
    input wire rx_init_ack_i, // Observe peer initialization completion.
    input wire rx_keepalive_ack_i, // Observe a peer heartbeat.
    input wire rx_link_reset_i, // Observe a peer-requested link reset.
    output reg event_valid_o, // Request one management reverse-control word.
    input wire event_ready_i, // Accept the requested management word.
    output reg [3:0] event_type_o, // Select the reverse-control message type.
    output reg [2:0] event_vc_o, // Select the advertised VC for credit messages.
    output wire [4:0] event_dst_node_o, // Address every management word to the direct peer.
    output reg [15:0] event_credit_total_o, // Carry the initial cumulative credit grant.
    output reg [7:0] event_status_o, // Report the current management state.
    output reg link_up_o, // Qualify user traffic after bilateral initialization.
    output reg reinitialize_o, // Pulse when all epoch-local reliability state must be cleared.
    output wire [2:0] state_o // Export the management state for verification and status.
); // End the module port list.
    localparam [2:0] STATE_DOWN = 3'd0; // Hold the disabled link state.
    localparam [2:0] STATE_CREDIT = 3'd1; // Advertise initial capacity for all eight VCs.
    localparam [2:0] STATE_INIT = 3'd2; // Announce local initialization completion.
    localparam [2:0] STATE_WAIT = 3'd3; // Wait for peer credits and initialization.
    localparam [2:0] STATE_UP = 3'd4; // Carry user traffic and monitor liveness.
    localparam [2:0] STATE_RESET = 3'd5; // Transmit a link-reset request before restarting.
    localparam integer KEEPALIVE_WIDTH = $clog2(KEEPALIVE_CYCLES + 1); // Size the heartbeat counter.
    localparam integer TIMEOUT_WIDTH = $clog2(TIMEOUT_CYCLES + 1); // Size the peer watchdog counter.
    reg [2:0] state_q; // Hold the current link-management state.
    reg [2:0] credit_vc_q; // Walk through the eight initial credit advertisements.
    reg [7:0] peer_credit_seen_q; // Remember each peer VC credit advertisement.
    reg peer_init_seen_q; // Remember peer initialization across local states.
    reg [7:0] observed_epoch_q; // Detect an externally advanced link epoch.
    reg [KEEPALIVE_WIDTH-1:0] keepalive_count_q; // Count idle operational cycles.
    reg [TIMEOUT_WIDTH-1:0] timeout_count_q; // Count cycles without accepted peer control.
    wire event_fire; // Mark acceptance of the current management event.
    wire epoch_changed; // Detect a system-owned epoch transition.
    wire peer_activity; // Combine all accepted peer control indications.

    assign event_dst_node_o = peer_node_i; // Direct every link-local event to the configured peer.
    assign state_o = state_q; // Expose the current state without an additional register stage.
    assign event_fire = event_valid_o && event_ready_i; // Advance only after event acceptance.
    assign epoch_changed = observed_epoch_q != link_epoch_i; // Compare the active and observed epochs.
    assign peer_activity = rx_activity_i || rx_credit_valid_i || rx_init_ack_i || // Combine general activity.
        rx_keepalive_ack_i || rx_link_reset_i; // Include explicit heartbeat and reset events.

    always @(*) begin // Encode the management event associated with the current state.
        event_valid_o = 1'b0; // Default to no management event.
        event_type_o = `KDL_REVERSE_TYPE_CREDIT; // Default the event type to credit.
        event_vc_o = credit_vc_q; // Default to the current credit-advertisement VC.
        event_credit_total_o = INITIAL_CREDITS; // Advertise the complete receive capacity.
        event_status_o = {5'd0, state_q}; // Report the current state in the status byte.
        case (state_q) // Select one management word per active management phase.
            STATE_CREDIT: begin // Emit one initial credit word for each VC.
                event_valid_o = 1'b1; // Keep the credit request asserted until accepted.
                event_type_o = `KDL_REVERSE_TYPE_CREDIT; // Encode cumulative-credit update.
            end // Complete initial credit event encoding.
            STATE_INIT: begin // Announce local initialization after all credits are advertised.
                event_valid_o = 1'b1; // Keep the initialization request asserted until accepted.
                event_type_o = `KDL_REVERSE_TYPE_INIT_ACK; // Use the bilateral initialization word.
                event_vc_o = `KDL_VC_ROLE_MANAGEMENT; // Mark the management VC role.
                event_credit_total_o = 16'd0; // Do not attach a credit grant to INIT_ACK.
            end // Complete initialization event encoding.
            STATE_UP: begin // Emit a heartbeat only when the keepalive interval expires.
                if (keepalive_count_q == KEEPALIVE_CYCLES[KEEPALIVE_WIDTH-1:0]) begin // Check heartbeat due.
                    event_valid_o = 1'b1; // Request a registered reverse heartbeat.
                    event_type_o = `KDL_REVERSE_TYPE_KEEPALIVE_ACK; // Encode the symmetric heartbeat.
                    event_vc_o = `KDL_VC_ROLE_MANAGEMENT; // Mark the management VC role.
                    event_credit_total_o = 16'd0; // Do not modify data credits.
                end // Complete heartbeat-due encoding.
            end // Complete operational event encoding.
            STATE_RESET: begin // Notify the peer before restarting local negotiation.
                event_valid_o = 1'b1; // Keep the reset request asserted until accepted.
                event_type_o = `KDL_REVERSE_TYPE_LINK_RESET; // Encode a link-local reset request.
                event_vc_o = `KDL_VC_ROLE_MANAGEMENT; // Mark the management VC role.
                event_credit_total_o = 16'd0; // Do not attach a credit update to reset.
            end // Complete reset event encoding.
            default: begin // Emit no event in disabled and peer-wait states.
                event_valid_o = 1'b0; // Preserve an idle reverse-management source.
            end // Complete the default event selection.
        endcase // Complete management-event selection.
    end // Complete combinational event encoding.

    always @(posedge clk_i or negedge rst_n_i) begin // Update autonomous management state.
        if (!rst_n_i) begin // Reset link state and all peer observations.
            state_q <= STATE_DOWN; // Begin with user traffic disabled.
            credit_vc_q <= 3'd0; // Begin initial credit advertisement at VC0.
            peer_credit_seen_q <= 8'd0; // Forget all peer credit advertisements.
            peer_init_seen_q <= 1'b0; // Forget peer initialization.
            observed_epoch_q <= link_epoch_i; // Capture the reset-time system epoch.
            keepalive_count_q <= {KEEPALIVE_WIDTH{1'b0}}; // Clear the heartbeat interval.
            timeout_count_q <= {TIMEOUT_WIDTH{1'b0}}; // Clear the peer watchdog.
            link_up_o <= 1'b0; // Block user traffic while reset is active.
            reinitialize_o <= 1'b0; // Clear the reliability-reset pulse.
        end else begin // Process enabled link management.
            reinitialize_o <= 1'b0; // Default to no reliability-state reset pulse.
            if (rx_credit_valid_i) peer_credit_seen_q[rx_credit_vc_i] <= 1'b1; // Record peer VC capacity.
            if (rx_init_ack_i) peer_init_seen_q <= 1'b1; // Record peer initialization.
            if (peer_activity) timeout_count_q <= {TIMEOUT_WIDTH{1'b0}}; // Refresh the peer watchdog.
            else if ((state_q == STATE_UP) && (timeout_count_q < TIMEOUT_CYCLES[TIMEOUT_WIDTH-1:0])) begin // Count idle cycles.
                timeout_count_q <= timeout_count_q + 1'b1; // Advance toward a liveness timeout.
            end // Complete watchdog advancement.
            if (state_q == STATE_UP) begin // Maintain the periodic heartbeat counter while operational.
                if (event_fire && (event_type_o == `KDL_REVERSE_TYPE_KEEPALIVE_ACK)) begin // Accept heartbeat.
                    keepalive_count_q <= {KEEPALIVE_WIDTH{1'b0}}; // Restart the heartbeat interval.
                end else if (keepalive_count_q < KEEPALIVE_CYCLES[KEEPALIVE_WIDTH-1:0]) begin // Count to due.
                    keepalive_count_q <= keepalive_count_q + 1'b1; // Advance the heartbeat interval.
                end // Complete heartbeat advancement.
            end else begin // Hold the heartbeat counter clear outside operational state.
                keepalive_count_q <= {KEEPALIVE_WIDTH{1'b0}}; // Clear non-operational heartbeat state.
            end // Complete heartbeat-state selection.

            if (!enable_i) begin // Give administrative disable highest priority.
                state_q <= STATE_DOWN; // Return to the disabled state.
                credit_vc_q <= 3'd0; // Restart any future credit advertisement at VC0.
                peer_credit_seen_q <= 8'd0; // Forget peer negotiation state.
                peer_init_seen_q <= 1'b0; // Forget peer initialization state.
                link_up_o <= 1'b0; // Block user traffic immediately.
                timeout_count_q <= {TIMEOUT_WIDTH{1'b0}}; // Clear the peer watchdog.
            end else if (epoch_changed) begin // Restart when the system advances the link epoch.
                observed_epoch_q <= link_epoch_i; // Adopt the new system-owned epoch.
                state_q <= STATE_CREDIT; // Restart bilateral credit negotiation.
                credit_vc_q <= 3'd0; // Begin with VC0.
                peer_credit_seen_q <= 8'd0; // Reject observations from the prior epoch.
                peer_init_seen_q <= 1'b0; // Reject initialization from the prior epoch.
                link_up_o <= 1'b0; // Block payload during renegotiation.
                reinitialize_o <= 1'b1; // Clear all epoch-local reliability state.
            end else if (rx_link_reset_i) begin // Honor a valid peer reset request.
                state_q <= STATE_CREDIT; // Restart bilateral credit negotiation.
                credit_vc_q <= 3'd0; // Begin with VC0.
                peer_credit_seen_q <= 8'd0; // Clear peer capacity observations.
                peer_init_seen_q <= 1'b0; // Clear peer initialization state.
                link_up_o <= 1'b0; // Block payload during restart.
                reinitialize_o <= 1'b1; // Clear all link-local reliability state.
            end else begin // Execute the current management phase.
                case (state_q) // Advance the finite-state machine on accepted events.
                    STATE_DOWN: begin // Start negotiation when administratively enabled.
                        state_q <= STATE_CREDIT; // Enter initial credit advertisement.
                        credit_vc_q <= 3'd0; // Begin with VC0.
                        peer_credit_seen_q <= 8'd0; // Start with no peer capacity observations.
                        peer_init_seen_q <= 1'b0; // Start with no peer initialization.
                        link_up_o <= 1'b0; // Keep payload blocked.
                        reinitialize_o <= 1'b1; // Initialize all link-local reliability state.
                    end // Complete disabled-state handling.
                    STATE_CREDIT: begin // Advertise all eight receive queues.
                        if (event_fire) begin // Advance after one credit word is accepted.
                            if (credit_vc_q == 3'd7) begin // Detect the final VC advertisement.
                                credit_vc_q <= 3'd0; // Prepare for a future restart.
                                state_q <= STATE_INIT; // Announce local initialization next.
                            end else begin // Continue through the remaining VCs.
                                credit_vc_q <= credit_vc_q + 1'b1; // Select the next VC.
                            end // Complete credit-index advancement.
                        end // Complete credit-event acceptance handling.
                    end // Complete credit-advertisement state handling.
                    STATE_INIT: begin // Send the bilateral initialization marker.
                        if (event_fire) state_q <= STATE_WAIT; // Wait for complete peer negotiation.
                    end // Complete initialization state handling.
                    STATE_WAIT: begin // Observe all peer grants and peer initialization.
                        if ((peer_credit_seen_q == 8'hff) && peer_init_seen_q) begin // Check bilateral completion.
                            state_q <= STATE_UP; // Enter operational state.
                            link_up_o <= 1'b1; // Permit queued payload traffic.
                            timeout_count_q <= {TIMEOUT_WIDTH{1'b0}}; // Start a fresh liveness window.
                        end // Complete peer-negotiation completion handling.
                    end // Complete peer-wait state handling.
                    STATE_UP: begin // Monitor the operational link.
                        if (timeout_count_q == TIMEOUT_CYCLES[TIMEOUT_WIDTH-1:0]) begin // Detect peer silence.
                            state_q <= STATE_RESET; // Request link reset before renegotiation.
                            link_up_o <= 1'b0; // Stop new payload transmission.
                        end // Complete timeout handling.
                    end // Complete operational-state handling.
                    STATE_RESET: begin // Transmit one link reset request.
                        if (event_fire) begin // Restart only after the reset word is accepted.
                            state_q <= STATE_CREDIT; // Re-advertise receive capacity.
                            credit_vc_q <= 3'd0; // Begin again with VC0.
                            peer_credit_seen_q <= 8'd0; // Clear peer capacity observations.
                            peer_init_seen_q <= 1'b0; // Clear peer initialization state.
                            reinitialize_o <= 1'b1; // Clear all link-local reliability state.
                        end // Complete reset-event acceptance handling.
                    end // Complete reset state handling.
                    default: begin // Recover from an illegal state encoding.
                        state_q <= STATE_DOWN; // Return to the safe disabled state.
                        link_up_o <= 1'b0; // Block payload after state corruption.
                        reinitialize_o <= 1'b1; // Clear reliability state before reuse.
                    end // Complete illegal-state recovery.
                endcase // Complete state-machine selection.
            end // Complete management priority selection.
        end // Complete active management processing.
    end // Complete the sequential management process.
endmodule // Complete the autonomous link manager.
