`timescale 1ns/1ps
`default_nettype none

// 已通过UPLI整包原子准入的typed envelope到native TL pack边界。
// 四通道reservation向量顺序为Request、OrigData、ReadRsp、WriteRsp。
// 本层不拥有或扣减信用；它保存准入事务owner并验证所有body严格属于该预约。
module switch_admitted_upli_tl_packer #(
    parameter integer C_PORTS = 4,
    parameter integer C_COUNT_WIDTH = 4,
    parameter integer C_OWNER_MASK_WIDTH = 17,
    parameter integer C_OWNER_TOKEN_WIDTH = 18
) (
    input  wire                             i_clk,
    input  wire                             i_rstn,
    input  wire [C_PORTS-1:0]               i_admitted_valid,
    output wire [C_PORTS-1:0]               o_admitted_ready,
    input  wire [C_PORTS*512-1:0]           i_data,
    input  wire [C_PORTS*128-1:0]           i_meta,
    input  wire [C_PORTS*2-1:0]             i_class,
    input  wire [C_PORTS*2-1:0]             i_tl_msg,
    input  wire [C_PORTS*2-1:0]             i_original_upli_vc,
    input  wire [C_PORTS-1:0]               i_original_upli_pool,
    input  wire [C_PORTS*10-1:0]            i_source_port,
    input  wire [C_PORTS*10-1:0]            i_dst_port,
    input  wire [C_PORTS-1:0]               i_sop,
    input  wire [C_PORTS-1:0]               i_eop,
    input  wire [C_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
    input  wire [C_PORTS-1:0]               i_provenance_valid,
    input  wire [C_PORTS-1:0]               i_reserved_body,
    input  wire [C_PORTS*4-1:0]             i_demand_valid,
    input  wire [C_PORTS*8-1:0]             i_demand_vc,
    input  wire [C_PORTS*4-1:0]             i_demand_pool,
    input  wire [C_PORTS*12-1:0]            i_demand_count,
    input  wire [C_PORTS*C_OWNER_MASK_WIDTH-1:0] i_owner_valid,
    input  wire [C_PORTS*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH-1:0] i_owner_tokens,
    output wire [C_PORTS-1:0]               o_tl_valid,
    input  wire [C_PORTS-1:0]               i_tl_ready,
    output wire [C_PORTS*512-1:0]           o_tl_data,
    output wire [C_PORTS*2-1:0]             o_tl_msg,
    output wire [C_PORTS*80-1:0]            o_tl_demands,
    output wire [C_PORTS-1:0]               o_tl_sop,
    output wire [C_PORTS-1:0]               o_tl_eop,
    output wire [C_PORTS*10-1:0]            o_tl_source_port,
    output wire [C_PORTS*C_OWNER_MASK_WIDTH-1:0] o_tl_owner_valid,
    output wire [C_PORTS*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH-1:0] o_tl_owner_tokens,
    output wire [C_PORTS-1:0]               o_busy,
    output wire [C_PORTS-1:0]               o_error,
    output wire                              o_config_error
);
    localparam C_CONFIG_LEGAL =
        (C_PORTS >= 1) && (C_PORTS <= 1024) && (C_COUNT_WIDTH == 4) &&
        (C_OWNER_MASK_WIDTH >= 1) && (C_OWNER_MASK_WIDTH <= 32) &&
        (C_OWNER_TOKEN_WIDTH >= 1) && (C_OWNER_TOKEN_WIDTH <= 64);

    wire [C_PORTS-1:0] inner_ready;
    wire [C_PORTS-1:0] inner_error;
    wire [C_PORTS-1:0] contract_legal;
    wire [C_PORTS-1:0] inner_candidate_valid;
    wire [C_PORTS-1:0] accepted;
    wire [C_PORTS-1:0] inner_tl_valid;
    wire [C_PORTS-1:0] inner_tl_ready;
    wire [C_PORTS-1:0] inner_tl_sop;
    wire [C_PORTS-1:0] inner_tl_eop;
    wire               inner_config_error;

    genvar port_gen;
    generate
        if (!C_CONFIG_LEGAL) begin : g_invalid_parameters
            switch_admitted_upli_tl_packer_parameters_invalid Invalid_Inst();
        end
        for (port_gen = 0; port_gen < C_PORTS; port_gen = port_gen + 1) begin : g_contract
            wire [127:0] candidate_meta;
            wire [1:0] candidate_class;
            wire [1:0] candidate_vc;
            wire candidate_pool;
            wire [9:0] candidate_source;
            wire [9:0] candidate_dst;
            wire [3:0] candidate_flits;
            wire [3:0] candidate_demand_valid;
            wire [7:0] candidate_demand_vc;
            wire [3:0] candidate_demand_pool;
            wire [11:0] candidate_demand_count;
            wire [5:0] request_command;
            wire [1:0] request_num;
            wire response_read;
            wire [1:0] response_length;
            wire request_shape;
            wire response_shape;
            wire request_read;
            wire request_write_plain;
            wire request_write;
            wire response_write;
            wire [3:0] header_demand_valid;
            wire [11:0] header_demand_count;
            wire header_demand_accounts_match;
            wire header_shape_legal;
            wire body_shape_legal;
            wire tl_final_fire;
            wire retire_owner_available;
            wire [C_OWNER_MASK_WIDTH-1:0] candidate_owner_valid;
            wire [C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH-1:0] candidate_owner_tokens;

            reg owner_valid_q;
            reg [3:0] owner_remaining_q;
            reg [3:0] owner_packet_flits_q;
            reg [1:0] owner_class_q;
            reg [1:0] owner_vc_q;
            reg owner_pool_q;
            reg [127:0] owner_meta_q;
            reg [9:0] owner_source_q;
            reg [9:0] owner_dst_q;
            reg contract_error_q;
            reg retire_owner_valid_q;
            reg [9:0] retire_source_q;
            reg [C_OWNER_MASK_WIDTH-1:0] retire_mask_q;
            reg [C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH-1:0] retire_tokens_q;

            assign candidate_meta = i_meta[port_gen*128 +: 128];
            assign candidate_class = i_class[port_gen*2 +: 2];
            assign candidate_vc = i_original_upli_vc[port_gen*2 +: 2];
            assign candidate_pool = i_original_upli_pool[port_gen];
            assign candidate_source = i_source_port[port_gen*10 +: 10];
            assign candidate_dst = i_dst_port[port_gen*10 +: 10];
            assign candidate_flits = i_packet_flits[port_gen*C_COUNT_WIDTH +: C_COUNT_WIDTH];
            assign candidate_demand_valid = i_demand_valid[port_gen*4 +: 4];
            assign candidate_demand_vc = i_demand_vc[port_gen*8 +: 8];
            assign candidate_demand_pool = i_demand_pool[port_gen*4 +: 4];
            assign candidate_demand_count = i_demand_count[port_gen*12 +: 12];
            assign candidate_owner_valid =
                i_owner_valid[port_gen*C_OWNER_MASK_WIDTH +: C_OWNER_MASK_WIDTH];
            assign candidate_owner_tokens =
                i_owner_tokens[port_gen*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH +:
                    C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH];
            assign request_command = i_data[port_gen*512+118 +: 6];
            assign request_num = i_data[port_gen*512 +: 2];
            assign response_read = i_data[port_gen*512+37];
            assign response_length = i_data[port_gen*512+44 +: 2];
            assign request_shape = (i_data[port_gen*512+128 +: 384] == 384'd0) &&
                (i_data[port_gen*512+124 +: 4] == 4'd1) &&
                (i_data[port_gen*512+116 +: 2] == candidate_vc);
            assign response_shape = (i_data[port_gen*512+64 +: 448] == 448'd0) &&
                (i_data[port_gen*512+60 +: 4] == 4'd2) &&
                (i_data[port_gen*512+58 +: 2] == candidate_vc) &&
                (i_data[port_gen*512+14 +: 2] == 2'd0);

            assign request_read = request_shape && (candidate_class == 2'd0) &&
                (request_command == 6'd3) && (request_num == 2'd0) &&
                (candidate_flits == 4'd1) && i_eop[port_gen];
            assign request_write = request_shape && (candidate_class == 2'd0) &&
                (request_command == 6'd41) &&
                (candidate_flits == ({2'd0, request_num}+4'd2)) && !i_eop[port_gen];
            assign request_write_plain = request_shape && (candidate_class == 2'd0) &&
                (request_command == 6'd40) &&
                (candidate_flits == ({2'd0, request_num}+4'd3)) && !i_eop[port_gen];
            assign response_write = response_shape && (candidate_class == 2'd1) &&
                !response_read && (response_length == 2'd0) &&
                (i_data[port_gen*512+42 +: 2] == 2'd0) &&
                !i_data[port_gen*512+36] && (candidate_flits == 4'd1) && i_eop[port_gen];

            assign header_demand_valid = request_read ? 4'b0001 :
                ((request_write || request_write_plain) ? 4'b0011 :
                ((response_shape && candidate_class == 2'd1 && response_read &&
                  candidate_flits == ({2'd0, response_length}+4'd2) && !i_eop[port_gen]) ? 4'b0100 :
                (response_write ? 4'b1000 : 4'b0000)));
            assign header_demand_count = request_read ? 12'h001 :
                ((request_write || request_write_plain) ?
                    {6'd0, (candidate_flits[2:0]-(request_write_plain ? 3'd2 : 3'd1)), 3'd1} :
                ((response_shape && candidate_class == 2'd1 && response_read &&
                  candidate_flits == ({2'd0, response_length}+4'd2) && !i_eop[port_gen]) ?
                    {3'd0, (candidate_flits[2:0]-3'd1), 6'd0} :
                (response_write ? 12'h200 : 12'd0)));

            // 每个被预约通道必须使用路由策略已经选择的同一个VC/Pool账户。
            assign header_demand_accounts_match =
                ((candidate_demand_valid[0] == 1'b0) ||
                    ((candidate_demand_vc[1:0] == candidate_vc) &&
                     (candidate_demand_pool[0] == candidate_pool))) &&
                ((candidate_demand_valid[1] == 1'b0) ||
                    ((candidate_demand_vc[3:2] == candidate_vc) &&
                     (candidate_demand_pool[1] == candidate_pool))) &&
                ((candidate_demand_valid[2] == 1'b0) ||
                    ((candidate_demand_vc[5:4] == candidate_vc) &&
                     (candidate_demand_pool[2] == candidate_pool))) &&
                ((candidate_demand_valid[3] == 1'b0) ||
                    ((candidate_demand_vc[7:6] == candidate_vc) &&
                     (candidate_demand_pool[3] == candidate_pool)));

            assign tl_final_fire = o_tl_valid[port_gen] && i_tl_ready[port_gen] &&
                inner_tl_eop[port_gen];
            assign retire_owner_available = !retire_owner_valid_q || tl_final_fire;
            assign header_shape_legal = i_sop[port_gen] && !owner_valid_q &&
                (|candidate_owner_valid) &&
                (i_tl_msg[port_gen*2 +: 2] == 2'd0) &&
                !i_reserved_body[port_gen] && (header_demand_valid != 4'd0) &&
                (candidate_demand_valid == header_demand_valid) &&
                (candidate_demand_count == header_demand_count) &&
                header_demand_accounts_match;
            assign body_shape_legal = !i_sop[port_gen] && owner_valid_q &&
                (i_tl_msg[port_gen*2 +: 2] == 2'd0) &&
                i_reserved_body[port_gen] && (candidate_demand_valid == 4'd0) &&
                (candidate_demand_vc == 8'd0) && (candidate_demand_pool == 4'd0) &&
                (candidate_demand_count == 12'd0) &&
                (candidate_class == owner_class_q) && (candidate_vc == owner_vc_q) &&
                (candidate_pool == owner_pool_q) && (candidate_meta == owner_meta_q) &&
                (candidate_source == owner_source_q) && (candidate_dst == owner_dst_q) &&
                (candidate_owner_valid == retire_mask_q) &&
                (candidate_owner_tokens == retire_tokens_q) &&
                (candidate_flits == owner_packet_flits_q) &&
                (i_eop[port_gen] == (owner_remaining_q == 4'd1));

            assign contract_legal[port_gen] = i_provenance_valid[port_gen] &&
                (header_shape_legal || body_shape_legal);
            // A following legal SOP may be held while the previous packet's
            // final native TL beat retires.  Keep it away from the inner
            // repacker until the descriptor retirement slot is available;
            // otherwise a normal ready/valid stall looks like a nested SOP.
            assign inner_candidate_valid[port_gen] = i_admitted_valid[port_gen] &&
                contract_legal[port_gen] &&
                (!i_sop[port_gen] || retire_owner_available);
            assign o_admitted_ready[port_gen] = C_CONFIG_LEGAL &&
                !contract_error_q && contract_legal[port_gen] &&
                (!i_sop[port_gen] || retire_owner_available) && inner_ready[port_gen];
            assign accepted[port_gen] = i_admitted_valid[port_gen] && o_admitted_ready[port_gen];
            assign inner_tl_ready[port_gen] = i_tl_ready[port_gen] && retire_owner_valid_q;
            assign o_tl_valid[port_gen] = inner_tl_valid[port_gen] && retire_owner_valid_q;
            assign o_error[port_gen] = !C_CONFIG_LEGAL || contract_error_q || inner_error[port_gen];
            assign o_tl_sop[port_gen] = o_tl_valid[port_gen] && inner_tl_sop[port_gen];
            assign o_tl_eop[port_gen] = o_tl_valid[port_gen] && inner_tl_eop[port_gen];
            assign o_tl_source_port[port_gen*10 +: 10] =
                o_tl_valid[port_gen] ? retire_source_q : 10'd0;
            assign o_tl_owner_valid[port_gen*C_OWNER_MASK_WIDTH +: C_OWNER_MASK_WIDTH] =
                o_tl_valid[port_gen] ? retire_mask_q : {C_OWNER_MASK_WIDTH{1'b0}};
            assign o_tl_owner_tokens[
                port_gen*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH +:
                C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH] = o_tl_valid[port_gen] ?
                    retire_tokens_q : {(C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH){1'b0}};

            always @(posedge i_clk) begin
                if (!i_rstn) begin
                    owner_valid_q <= 1'b0;
                    owner_remaining_q <= 4'd0;
                    owner_packet_flits_q <= 4'd0;
                    owner_class_q <= 2'd0;
                    owner_vc_q <= 2'd0;
                    owner_pool_q <= 1'b0;
                    owner_meta_q <= 128'd0;
                    owner_source_q <= 10'd0;
                    owner_dst_q <= 10'd0;
                    contract_error_q <= 1'b0;
                    retire_owner_valid_q <= 1'b0;
                    retire_source_q <= 10'd0;
                    retire_mask_q <= {C_OWNER_MASK_WIDTH{1'b0}};
                    retire_tokens_q <= {(C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH){1'b0}};
                end else if (C_CONFIG_LEGAL) begin
                    if (i_admitted_valid[port_gen] && !contract_legal[port_gen]) begin
                        contract_error_q <= 1'b1;
                    end
                    if (inner_tl_valid[port_gen] && !retire_owner_valid_q) begin
                        contract_error_q <= 1'b1;
                    end
                    if (tl_final_fire) begin
                        retire_owner_valid_q <= 1'b0;
                    end
                    if (accepted[port_gen]) begin
                        if (i_sop[port_gen]) begin
                            owner_valid_q <= !i_eop[port_gen];
                            owner_remaining_q <= i_eop[port_gen] ? 4'd0 : candidate_flits-4'd1;
                            owner_packet_flits_q <= candidate_flits;
                            owner_class_q <= candidate_class;
                            owner_vc_q <= candidate_vc;
                            owner_pool_q <= candidate_pool;
                            owner_meta_q <= candidate_meta;
                            owner_source_q <= candidate_source;
                            owner_dst_q <= candidate_dst;
                            retire_owner_valid_q <= 1'b1;
                            retire_source_q <= candidate_source;
                            retire_mask_q <= candidate_owner_valid;
                            retire_tokens_q <= candidate_owner_tokens;
                        end else if (owner_remaining_q == 4'd1) begin
                            owner_valid_q <= 1'b0;
                            owner_remaining_q <= 4'd0;
                        end else begin
                            owner_remaining_q <= owner_remaining_q-4'd1;
                        end
                    end
                end
            end
        end
    endgenerate

    switch_fabric_tl_native_repacker #(
        .C_PORTS(C_PORTS),
        .C_COUNT_WIDTH(C_COUNT_WIDTH)
    ) u_repacker (
        .i_clk(i_clk),
        .i_rstn(i_rstn && C_CONFIG_LEGAL),
        .i_valid(inner_candidate_valid),
        .o_ready(inner_ready),
        .i_data(i_data),
        .i_meta(i_meta),
        .i_class(i_class),
        .i_original_vc(i_original_upli_vc),
        .i_original_pool(i_original_upli_pool),
        .i_source_port(i_source_port),
        .i_dst_port(i_dst_port),
        .i_sop(i_sop),
        .i_eop(i_eop),
        .i_packet_flits(i_packet_flits),
        .o_tl_valid(inner_tl_valid),
        .i_tl_ready(inner_tl_ready),
        .o_tl_data(o_tl_data),
        .o_tl_msg(o_tl_msg),
        .o_tl_demands(o_tl_demands),
        .o_tl_sop(inner_tl_sop),
        .o_tl_eop(inner_tl_eop),
        .o_busy(o_busy),
        .o_error(inner_error),
        .o_config_error(inner_config_error)
    );

    assign o_config_error = !C_CONFIG_LEGAL || inner_config_error;
endmodule

`default_nettype wire
