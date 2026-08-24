`include "kdlink_defs.vh"
module formal_spine_escape;
    (* gclk *) reg clk;
    (* anyconst *) reg profile_eight;
    (* anyconst *) reg [2:0] destination_domain;
    reg past_valid;
    reg [3:0] cycle_q;
    reg [639:0] ingress_flit_d;
    wire rst_n;
    wire [3:0] domain_count;
    wire ingress_valid;
    wire ingress_ready;
    wire [7:0] egress_valid;
    wire [5119:0] egress_flit;
    wire route_active;
    wire [2:0] selected_egress;
    wire protocol_error;
    wire escape_violation;
    wire [7:0] expected_egress_mask;

    initial begin
        past_valid = 1'b0;
        cycle_q = 4'd0;
    end
    assign rst_n = past_valid;
    assign domain_count = profile_eight ? 4'd8 : 4'd4;
    assign ingress_valid = (cycle_q == 4'd2) || (cycle_q == 4'd3);
    assign expected_egress_mask = 8'b1 << destination_domain;

    always @(*) begin
        assume (profile_eight || destination_domain < 3'd4);
    end

    always @(*) begin
        ingress_flit_d = 640'd0;
        if (cycle_q == 4'd2) begin
            ingress_flit_d[515:512] = `KDL_ROUTE_SCHEMA;
            ingress_flit_d[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
            ingress_flit_d[527:525] = `KDL_VC_ROLE_ESCAPE;
            ingress_flit_d[529] = 1'b1;
            ingress_flit_d[530] = 1'b1;
            ingress_flit_d[536:532] = 5'd3;
            ingress_flit_d[541:537] = 5'd29;
            ingress_flit_d[544:542] = 3'd0;
            ingress_flit_d[569:558] = 12'h701;
            ingress_flit_d[593:582] = 12'd40;
            ingress_flit_d[606:600] = 7'd64;
            ingress_flit_d[7:0] = 8'd0;
            ingress_flit_d[15:8] = {5'd0, destination_domain};
            ingress_flit_d[20:16] = 5'd3;
            ingress_flit_d[25:21] = 5'd29;
            ingress_flit_d[33:26] = 8'd9;
            ingress_flit_d[41:34] = 8'd2;
            ingress_flit_d[44:42] = 3'd0;
            ingress_flit_d[46:45] = 2'b11;
            ingress_flit_d[49:47] = 3'd0;
            ingress_flit_d[54:50] = 5'd1;
            ingress_flit_d[66:55] = 12'd42;
            ingress_flit_d[130:67] = 64'h9000_0000_0000_0001;
            ingress_flit_d[162:131] = 32'h9000_0001;
            ingress_flit_d[165:163] = `KDL_VC_ROLE_ESCAPE;
        end else begin
            ingress_flit_d[515:512] = `KDL_SCHEMA_VERSION;
            ingress_flit_d[519:516] = `KDL_MESSAGE_TYPE_DATA;
            ingress_flit_d[527:525] = `KDL_VC_ROLE_ESCAPE;
            ingress_flit_d[529] = 1'b1;
            ingress_flit_d[530] = 1'b1;
            ingress_flit_d[536:532] = 5'd3;
            ingress_flit_d[541:537] = 5'd29;
            ingress_flit_d[544:542] = 3'd0;
            ingress_flit_d[569:558] = 12'h701;
            ingress_flit_d[593:582] = 12'd42;
            ingress_flit_d[606:600] = 7'd64;
        end
    end

    kdlink_spine_router u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .domain_count_i(domain_count),
        .active_domain_mask_i(8'hff), .ingress_valid_i(ingress_valid),
        .ingress_ready_o(ingress_ready), .ingress_flit_i(ingress_flit_d),
        .egress_valid_o(egress_valid), .egress_ready_i(8'hff),
        .egress_flit_o(egress_flit), .route_active_o(route_active),
        .selected_egress_o(selected_egress), .protocol_error_o(protocol_error),
        .escape_violation_o(escape_violation)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            cycle_q <= 4'd0;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            if ($past(past_valid)) begin
                if (egress_valid != 8'd0) begin
                    assert (egress_valid == expected_egress_mask);
                    assert ((egress_valid & ~expected_egress_mask) == 8'd0);
                    assert (ingress_ready);
                    if (ingress_flit_d[515:512] == `KDL_ROUTE_SCHEMA) begin
                        assert (egress_flit[destination_domain*640 + 34 +: 8] == 8'd1);
                        assert (egress_flit[destination_domain*640 + 47 +: 3] == 3'd0);
                    end
                end
                if (route_active) assert (selected_egress == destination_domain);
            end
        end
    end
endmodule
