`include "kdlink_defs.vh"
module formal_route_stage_scale;
    (* gclk *) reg clk;
    (* anyconst *) reg [7:0] destination_domain;
    reg past_valid;
    reg [3:0] cycle_q;
    reg [639:0] ingress_flit_d;
    wire rst_n;
    wire ingress_valid;
    wire [7:0] egress_valid0;
    wire [7:0] egress_valid1;
    wire [7:0] egress_valid2;
    wire [5119:0] egress_flit0;
    wire [5119:0] egress_flit1;
    wire [5119:0] egress_flit2;
    wire [7:0] expected0;
    wire [7:0] expected1;
    wire [7:0] expected2;
    wire chain_valid1;
    wire chain_valid2;
    wire ready0;
    wire ready1;
    wire ready2;
    wire [639:0] chain_flit1;
    wire [639:0] chain_flit2;
    initial begin
        past_valid = 1'b0;
        cycle_q = 4'd0;
    end
    assign rst_n = past_valid;
    assign ingress_valid = cycle_q == 4'd2;
    assign expected0 = 8'b1 << destination_domain[7:6];
    assign expected1 = 8'b1 << destination_domain[5:3];
    assign expected2 = 8'b1 << destination_domain[2:0];
    assign chain_valid1 = |egress_valid0;
    assign chain_valid2 = |egress_valid1;
    assign chain_flit1 = egress_flit0[639:0] | egress_flit0[1279:640] | egress_flit0[1919:1280] | egress_flit0[2559:1920] | egress_flit0[3199:2560] | egress_flit0[3839:3200] | egress_flit0[4479:3840] | egress_flit0[5119:4480];
    assign chain_flit2 = egress_flit1[639:0] | egress_flit1[1279:640] | egress_flit1[1919:1280] | egress_flit1[2559:1920] | egress_flit1[3199:2560] | egress_flit1[3839:3200] | egress_flit1[4479:3840] | egress_flit1[5119:4480];
    always @(*) begin
        ingress_flit_d = 640'd0;
        ingress_flit_d[515:512] = `KDL_ROUTE_SCHEMA;
        ingress_flit_d[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
        ingress_flit_d[527:525] = `KDL_VC_ROLE_ESCAPE;
        ingress_flit_d[529] = 1'b1;
        ingress_flit_d[530] = 1'b1;
        ingress_flit_d[536:532] = 5'd1;
        ingress_flit_d[541:537] = 5'd2;
        ingress_flit_d[606:600] = 7'd64;
        ingress_flit_d[7:0] = 8'd0;
        ingress_flit_d[15:8] = destination_domain;
        ingress_flit_d[20:16] = 5'd1;
        ingress_flit_d[25:21] = 5'd2;
        ingress_flit_d[33:26] = 8'd9;
        ingress_flit_d[41:34] = 8'd4;
        ingress_flit_d[46:45] = 2'b11;
        ingress_flit_d[54:50] = 5'd1;
        ingress_flit_d[130:67] = 64'h1;
    end
    kdlink_route_stage #(.DOMAIN_COUNT(256), .STAGE_INDEX(0)) u_stage0 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff),
        .ingress_valid_i(ingress_valid), .ingress_ready_o(ready0), .ingress_flit_i(ingress_flit_d),
        .egress_valid_o(egress_valid0), .egress_ready_i({8{ready1}}), .egress_flit_o(egress_flit0),
        .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(256), .STAGE_INDEX(1)) u_stage1 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff),
        .ingress_valid_i(chain_valid1), .ingress_ready_o(ready1), .ingress_flit_i(chain_flit1),
        .egress_valid_o(egress_valid1), .egress_ready_i({8{ready2}}), .egress_flit_o(egress_flit1),
        .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    kdlink_route_stage #(.DOMAIN_COUNT(256), .STAGE_INDEX(2)) u_stage2 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(8'hff),
        .ingress_valid_i(chain_valid2), .ingress_ready_o(ready2), .ingress_flit_i(chain_flit2),
        .egress_valid_o(egress_valid2), .egress_ready_i(8'hff), .egress_flit_o(egress_flit2),
        .route_active_o(), .selected_egress_o(), .final_stage_o(), .protocol_error_o(), .escape_violation_o()
    );
    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) cycle_q <= 4'd0;
        else begin
            cycle_q <= cycle_q + 1'b1;
            if (ingress_valid) begin
                assert (egress_valid0 == expected0);
                assert (egress_valid1 == expected1);
                assert (egress_valid2 == expected2);
                assert (ready0 && ready1 && ready2);
                assert (egress_flit0[destination_domain[7:6]*640 + 34 +: 8] == 8'd3);
                assert (egress_flit1[destination_domain[5:3]*640 + 34 +: 8] == 8'd2);
                assert (egress_flit2[destination_domain[2:0]*640 + 34 +: 8] == 8'd1);
            end
        end
    end
endmodule
