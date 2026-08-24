`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_route_stage_profiles;
    reg clk;
    reg rst_n;
    reg ingress_valid;
    reg [639:0] ingress_flit;
    reg [7:0] destination_domain;
    wire [511:0] route_payload;
    wire [7:0] valid8_0;
    wire [7:0] valid16_0;
    wire [7:0] valid16_1;
    wire [7:0] valid32_0;
    wire [7:0] valid32_1;
    wire [7:0] valid64_0;
    wire [7:0] valid64_1;
    reg [639:0] context_flit;
    reg [639:0] data_flit;
    reg [4:0] packet_flit_count;
    wire error8_0;
    kdlink_route_context_encoder u_encoder (
        .source_domain_i(8'd0), .destination_domain_i(destination_domain),
        .source_node_i(5'd1), .destination_node_i(5'd2), .topology_epoch_i(8'd3),
        .domain_hop_limit_i(8'd3), .logical_plane_i(3'd0), .slice_mask_i(2'b11),
        .route_policy_i(3'd0), .packet_flit_count_i(packet_flit_count), .expected_packet_sequence_i(12'h123),
        .global_transaction_id_i(64'h456), .group_id_i(32'h789), .logical_vc_i(3'd0),
        .payload_o(route_payload)
    );
    kdlink_route_stage #(.DOMAIN_COUNT(8), .STAGE_INDEX(0)) u_8_0 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff), .ingress_valid_i(ingress_valid), .ingress_ready_o(), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid8_0), .egress_ready_i(8'hff), .egress_flit_o(), .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(error8_0), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(16), .STAGE_INDEX(0)) u_16_0 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff), .ingress_valid_i(ingress_valid), .ingress_ready_o(), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid16_0), .egress_ready_i(8'hff), .egress_flit_o(), .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(16), .STAGE_INDEX(1)) u_16_1 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff), .ingress_valid_i(ingress_valid), .ingress_ready_o(), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid16_1), .egress_ready_i(8'hff), .egress_flit_o(), .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(32), .STAGE_INDEX(0)) u_32_0 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff), .ingress_valid_i(ingress_valid), .ingress_ready_o(), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid32_0), .egress_ready_i(8'hff), .egress_flit_o(), .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(32), .STAGE_INDEX(1)) u_32_1 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff), .ingress_valid_i(ingress_valid), .ingress_ready_o(), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid32_1), .egress_ready_i(8'hff), .egress_flit_o(), .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(64), .STAGE_INDEX(0)) u_64_0 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff), .ingress_valid_i(ingress_valid), .ingress_ready_o(), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid64_0), .egress_ready_i(8'hff), .egress_flit_o(), .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(64), .STAGE_INDEX(1)) u_64_1 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff), .ingress_valid_i(ingress_valid), .ingress_ready_o(), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid64_1), .egress_ready_i(8'hff), .egress_flit_o(), .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    always #0.5 clk = ~clk;
    task automatic drive_profile(input [7:0] destination);
        begin
            destination_domain = destination;
            #0.1;
            context_flit = 640'd0;
            context_flit[511:0] = route_payload;
            context_flit[515:512] = `KDL_ROUTE_SCHEMA;
            context_flit[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
            context_flit[527:525] = 3'd0;
            context_flit[529] = 1'b1;
            context_flit[530] = 1'b1;
            context_flit[536:532] = 5'd1;
            context_flit[541:537] = 5'd2;
            context_flit[593:582] = 12'h123;
            context_flit[606:600] = 7'd64;
            @(negedge clk);
            ingress_flit = context_flit;
            ingress_valid = 1'b1;
            #0.1;
            if (destination < 16 && (valid16_0 != (8'b1 << destination[5:3]) || valid16_1 != (8'b1 << destination[2:0]))) $fatal(1, "sixteen-domain two-stage profile digit mismatch");
            if (destination < 32 && (valid32_0 != (8'b1 << destination[5:3]) || valid32_1 != (8'b1 << destination[2:0]))) $fatal(1, "thirty-two-domain two-stage profile digit mismatch");
            if (destination < 64 && (valid64_0 != (8'b1 << destination[5:3]) || valid64_1 != (8'b1 << destination[2:0]))) $fatal(1, "sixty-four-domain two-stage profile digit mismatch");
            @(negedge clk);
            data_flit = 640'd0;
            data_flit[515:512] = `KDL_SCHEMA_VERSION;
            data_flit[527:525] = 3'd0;
            data_flit[529] = 1'b1;
            data_flit[530] = 1'b1;
            data_flit[536:532] = 5'd1;
            data_flit[541:537] = 5'd2;
            data_flit[593:582] = 12'h123;
            data_flit[606:600] = 7'd1;
            ingress_flit = data_flit;
            @(negedge clk);
            ingress_valid = 1'b0;
        end
    endtask
    task automatic drive_invalid_packet_recovery;
        begin
            destination_domain = 8'd7;
            packet_flit_count = 5'd2;
            #0.1;
            context_flit = 640'd0;
            context_flit[511:0] = route_payload;
            context_flit[515:512] = `KDL_ROUTE_SCHEMA;
            context_flit[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
            context_flit[527:525] = 3'd0;
            context_flit[529] = 1'b1;
            context_flit[530] = 1'b1;
            context_flit[536:532] = 5'd1;
            context_flit[541:537] = 5'd2;
            context_flit[593:582] = 12'h123;
            context_flit[606:600] = 7'd64;
            @(negedge clk);
            ingress_flit = context_flit;
            ingress_valid = 1'b1;
            #0.1;
            if (valid8_0 != 8'h80) $fatal(1, "eight-domain single-stage route digit mismatch");
            @(negedge clk);
            data_flit = 640'd0;
            data_flit[515:512] = `KDL_SCHEMA_VERSION;
            data_flit[527:525] = 3'd0;
            data_flit[529] = 1'b1;
            data_flit[530] = 1'b0;
            data_flit[536:532] = 5'd1;
            data_flit[541:537] = 5'd2;
            data_flit[593:582] = 12'h124;
            data_flit[599:594] = 6'd0;
            data_flit[606:600] = 7'd64;
            ingress_flit = data_flit;
            @(negedge clk);
            data_flit[529] = 1'b0;
            data_flit[530] = 1'b1;
            data_flit[599:594] = 6'd1;
            data_flit[606:600] = 7'd1;
            ingress_flit = data_flit;
            @(negedge clk);
            ingress_valid = 1'b0;
            packet_flit_count = 5'd1;
            if (!error8_0) $fatal(1, "invalid packet identity did not raise protocol error");
        end
    endtask
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ingress_valid = 1'b0;
        ingress_flit = 640'd0;
        destination_domain = 8'd0;
        context_flit = 640'd0;
        data_flit = 640'd0;
        packet_flit_count = 5'd1;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        drive_profile(8'd15);
        drive_profile(8'd31);
        drive_profile(8'd63);
        drive_invalid_packet_recovery();
        $display("TB_KDLINK_ROUTE_STAGE_PROFILES_PASS");
        $finish;
    end
endmodule
