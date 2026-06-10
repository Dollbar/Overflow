module formal_coverage_reachability;
    (* gclk *) reg clk;
    reg past_valid;
    wire rst_n;
    (* anyseq *) reg [639:0] domain_flit;
    (* anyseq *) reg domain_valid;
    (* anyseq *) reg [7:0] local_domain;
    (* anyseq *) reg local_ready;
    (* anyseq *) reg remote_ready;
    (* anyseq *) reg descriptor_valid;
    (* anyseq *) reg [2:0] descriptor_opcode;
    (* anyseq *) reg [14:0] descriptor_destination_domain;
    (* anyseq *) reg group_found;
    (* anyseq *) reg [7:0] group_child_mask;
    (* anyseq *) reg [31:0] group_local_member_mask;
    (* anyseq *) reg [20:0] group_subtree_member_count;
    (* anyseq *) reg [2:0] group_level;
    (* anyseq *) reg command_ready;
    (* anyseq *) reg link_enable;
    (* anyseq *) reg [7:0] link_epoch;
    (* anyseq *) reg [2:0] rx_credit_vc;
    (* anyseq *) reg [5:0] link_events;
    (* anyseq *) reg event_ready;
    (* anyseq *) reg fp_valid;
    (* anyseq *) reg [31:0] fp_a;
    (* anyseq *) reg [31:0] fp_b;

    initial past_valid = 1'b0;
    assign rst_n = past_valid;

    always @(posedge clk) past_valid <= 1'b1;

    kdlink_domain_adapter u_domain_adapter (
        .clk_i(clk), .rst_n_i(rst_n), .local_domain_i(local_domain),
        .ingress_valid_i(domain_valid), .ingress_ready_o(), .ingress_flit_i(domain_flit),
        .local_valid_o(), .local_ready_i(local_ready), .local_flit_o(),
        .remote_valid_o(), .remote_ready_i(remote_ready), .remote_flit_o(),
        .protocol_error_o()
    );

    kdlink_collective_tree_ctrl u_collective_tree (
        .clk_i(clk), .rst_n_i(rst_n), .descriptor_valid_i(descriptor_valid),
        .descriptor_ready_o(), .descriptor_opcode_i(descriptor_opcode),
        .descriptor_group_id_i(32'd0), .descriptor_transaction_id_i(64'd0),
        .descriptor_topology_epoch_i(16'd0),
        .descriptor_destination_domain_i(descriptor_destination_domain),
        .group_found_i(group_found), .group_child_mask_i(group_child_mask),
        .group_local_member_mask_i(group_local_member_mask),
        .group_subtree_member_count_i(group_subtree_member_count),
        .group_root_endpoint_i(20'd0), .group_level_i(group_level),
        .command_valid_o(), .command_ready_i(command_ready), .command_phase_o(),
        .command_opcode_o(), .command_child_o(), .command_local_member_mask_o(),
        .command_group_id_o(), .command_transaction_id_o(),
        .command_topology_epoch_o(), .command_subtree_member_count_o(),
        .command_root_endpoint_o(), .busy_o(), .descriptor_error_o()
    );

    kdlink_link_manager #(.KEEPALIVE_CYCLES(2), .TIMEOUT_CYCLES(3)) u_link_manager (
        .clk_i(clk), .rst_n_i(rst_n), .enable_i(link_enable), .peer_node_i(5'd1),
        .link_epoch_i(link_epoch), .rx_activity_i(link_events[0]),
        .rx_credit_valid_i(link_events[1]), .rx_credit_vc_i(rx_credit_vc),
        .rx_init_ack_i(link_events[2]), .rx_keepalive_ack_i(link_events[3]),
        .rx_link_reset_i(link_events[4]), .event_valid_o(), .event_ready_i(event_ready),
        .event_type_o(), .event_vc_o(), .event_dst_node_o(), .event_credit_total_o(),
        .event_status_o(), .link_up_o(), .reinitialize_o(), .state_o()
    );

    coll_fp32_add_lane u_fp32_lane (
        .clk_i(clk), .rst_n_i(rst_n), .valid_i(fp_valid), .a_i(fp_a), .b_i(fp_b),
        .valid_o(), .result_o()
    );
endmodule
