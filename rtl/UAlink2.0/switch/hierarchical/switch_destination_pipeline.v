`timescale 1ns/1ps
`default_nettype none
// 目标侧完整组合：独立Destination Group账本取得真实slot，再进入逐Tile/Port出口队列。
// 每个Port的registered release hold直接回到所属Group ledger；token不截断，也不跨Group重算。
module switch_destination_pipeline #(
 parameter integer C_NUM_GROUPS=8,C_PLANES=32,C_TILES=4,C_BANK_LANES=8,C_PORTS_PER_TILE=32,
 parameter integer C_DATA_WIDTH=256,C_META_WIDTH=128,C_TILE_WIDTH=2,C_CLASS_WIDTH=2,C_VC_WIDTH=2,
 parameter integer C_COUNT_WIDTH=5,C_CORE_CONTEXT_WIDTH=5,C_PLANE_WIDTH=5,C_OWNER_WIDTH=6,C_RESOURCE_WIDTH=9,
 parameter integer C_EPOCH_WIDTH=4,C_GENERATION_WIDTH=8,C_SLOT_WIDTH=11,C_BANK_SLOT_WIDTH=2,
 parameter integer C_ACCOUNT_WIDTH=15,C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH,
 parameter integer C_CREDIT_COUNT_WIDTH=3,C_NUM_CLASSES=4,C_NUM_VC=4,C_CAPACITY=4,
 parameter integer C_QUEUE_DEPTH=4,C_QUEUE_COUNT_WIDTH=3,C_GLOBAL_PORT_WIDTH=10,
 parameter integer C_LANES=C_TILES*C_BANK_LANES,parameter integer C_REQUESTERS=C_LANES+C_PLANES,
 parameter integer C_RESOURCES=C_TILES*C_PORTS_PER_TILE*C_NUM_CLASSES,
 parameter integer C_ACCOUNTS=C_REQUESTERS*C_RESOURCES,parameter integer C_RELEASE_PORTS=C_TILES*C_PORTS_PER_TILE,
 parameter integer C_TOTAL_PORTS=C_NUM_GROUPS*C_RELEASE_PORTS,parameter integer C_TOTAL_TILES=C_NUM_GROUPS*C_TILES
)(
 input wire i_clk,input wire i_rstn,input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 // Group-major local Tile-bank请求，全部已经通过ingress commit barrier。
 input wire [C_NUM_GROUPS*C_LANES-1:0] i_local_valid,output wire [C_NUM_GROUPS*C_LANES-1:0] o_local_ready,
 input wire [C_NUM_GROUPS*C_LANES*C_DATA_WIDTH-1:0] i_local_data,input wire [C_NUM_GROUPS*C_LANES*C_META_WIDTH-1:0] i_local_meta,
 input wire [C_NUM_GROUPS*C_LANES*3-1:0] i_local_dst_group,input wire [C_NUM_GROUPS*C_LANES*C_TILE_WIDTH-1:0] i_local_dst_tile,
 input wire [C_NUM_GROUPS*C_LANES*5-1:0] i_local_dst_port,input wire [C_NUM_GROUPS*C_LANES*C_CLASS_WIDTH-1:0] i_local_class,
 input wire [C_NUM_GROUPS*C_LANES*C_VC_WIDTH-1:0] i_local_original_vc,input wire [C_NUM_GROUPS*C_LANES-1:0] i_local_pool,
 input wire [C_NUM_GROUPS*C_LANES*C_COUNT_WIDTH-1:0] i_local_packet_flits,
 input wire [C_NUM_GROUPS*C_LANES-1:0] i_local_sop,input wire [C_NUM_GROUPS*C_LANES-1:0] i_local_eop,
 // 每个Destination Group的原始Core Plane请求；plane context保持到credit account统计。
 input wire [C_NUM_GROUPS*C_PLANES-1:0] i_core_valid,output wire [C_NUM_GROUPS*C_PLANES-1:0] o_core_ready,
 input wire [C_NUM_GROUPS*C_PLANES*C_DATA_WIDTH-1:0] i_core_data,input wire [C_NUM_GROUPS*C_PLANES*C_META_WIDTH-1:0] i_core_meta,
 input wire [C_NUM_GROUPS*C_PLANES*3-1:0] i_core_dst_group,input wire [C_NUM_GROUPS*C_PLANES*C_TILE_WIDTH-1:0] i_core_dst_tile,
 input wire [C_NUM_GROUPS*C_PLANES*5-1:0] i_core_dst_port,input wire [C_NUM_GROUPS*C_PLANES*C_CLASS_WIDTH-1:0] i_core_class,
 input wire [C_NUM_GROUPS*C_PLANES*C_COUNT_WIDTH-1:0] i_core_packet_flits,
 input wire [C_NUM_GROUPS*C_PLANES*C_CORE_CONTEXT_WIDTH-1:0] i_core_context,
 input wire [C_NUM_GROUPS*C_PLANES*C_VC_WIDTH-1:0] i_core_original_vc,input wire [C_NUM_GROUPS*C_PLANES-1:0] i_core_pool,
 input wire [C_NUM_GROUPS*C_PLANES-1:0] i_core_sop,input wire [C_NUM_GROUPS*C_PLANES-1:0] i_core_eop,
 // 注册eligibility仅作为Source plane选择提示，传输仍以ready/valid为准。
 output wire [C_NUM_GROUPS*C_PLANES-1:0] o_core_registered_eligibility,
 output wire [C_NUM_GROUPS*C_PLANES*C_TILE_WIDTH-1:0] o_core_eligibility_dst_tile,
 output wire [C_NUM_GROUPS*C_PLANES*5-1:0] o_core_eligibility_dst_port,
 output wire [C_NUM_GROUPS*C_PLANES*C_CLASS_WIDTH-1:0] o_core_eligibility_class,
 output wire [C_NUM_GROUPS*C_EPOCH_WIDTH-1:0] o_core_eligibility_epoch,
 // 最终Logical Port门控和逐Port输出。
 input wire [C_TOTAL_PORTS-1:0] i_port_active,input wire [C_TOTAL_PORTS-1:0] i_upli_credit,
 input wire [C_TOTAL_PORTS-1:0] i_tl_credit,input wire [C_TOTAL_PORTS-1:0] i_link_up,
 output wire [C_TOTAL_PORTS-1:0] o_head_valid,output wire [C_TOTAL_PORTS-1:0] o_valid,input wire [C_TOTAL_PORTS-1:0] i_ready,
 output wire [C_TOTAL_PORTS*C_DATA_WIDTH-1:0] o_data,output wire [C_TOTAL_PORTS*C_META_WIDTH-1:0] o_meta,
 output wire [C_TOTAL_PORTS*C_CLASS_WIDTH-1:0] o_class,output wire [C_TOTAL_PORTS*C_VC_WIDTH-1:0] o_original_vc,
 output wire [C_TOTAL_PORTS-1:0] o_pool,output wire [C_TOTAL_PORTS-1:0] o_sop,output wire [C_TOTAL_PORTS-1:0] o_eop,
 output wire [C_TOTAL_PORTS*C_GLOBAL_PORT_WIDTH-1:0] o_global_port_id,
 // release enable允许分层reset/诊断停住归还；停住时egress registered hold保存完整身份。
 input wire [C_TOTAL_PORTS-1:0] i_release_path_enable,
 output wire [C_TOTAL_PORTS-1:0] o_release_valid,output wire [C_TOTAL_PORTS-1:0] o_release_ready,
 output wire [C_TOTAL_PORTS*C_ACCOUNT_WIDTH-1:0] o_release_account,
 output wire [C_TOTAL_PORTS*C_TOKEN_WIDTH-1:0] o_release_token,
 // 账本、quiescent与严重错误供全Fabric supervisor/CSR观察。
 output wire [C_NUM_GROUPS*C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] o_free,
 output wire [C_NUM_GROUPS*C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] o_effective_free,
 output wire [C_NUM_GROUPS*C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_issued,
 output wire [C_NUM_GROUPS*C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_occupied,
 output wire [C_NUM_GROUPS-1:0] o_group_quiescent,output wire [C_NUM_GROUPS-1:0] o_group_error,
 output wire [C_NUM_GROUPS-1:0] o_return_malformed_event_level,
 output wire [C_NUM_GROUPS-1:0] o_return_duplicate_event_level,
 output wire [C_NUM_GROUPS-1:0] o_return_stale_event_level,
 output wire [C_NUM_GROUPS-1:0] o_return_wrong_port_event_level,
 output wire o_config_error
);
 wire [C_NUM_GROUPS*C_LANES-1:0] credited_valid,credited_ready;
 wire [C_NUM_GROUPS*C_LANES*C_DATA_WIDTH-1:0] credited_data;
 wire [C_NUM_GROUPS*C_LANES*C_META_WIDTH-1:0] credited_meta;
 wire [C_NUM_GROUPS*C_LANES*3-1:0] credited_group;
 wire [C_NUM_GROUPS*C_LANES*C_TILE_WIDTH-1:0] credited_tile;
 wire [C_NUM_GROUPS*C_LANES*5-1:0] credited_port;
 wire [C_NUM_GROUPS*C_LANES*C_CLASS_WIDTH-1:0] credited_class;
 wire [C_NUM_GROUPS*C_LANES*C_VC_WIDTH-1:0] credited_vc;
 wire [C_NUM_GROUPS*C_LANES-1:0] credited_pool,credited_sop,credited_eop;
 wire [C_NUM_GROUPS*C_LANES*C_ACCOUNT_WIDTH-1:0] credited_account;
 wire [C_NUM_GROUPS*C_LANES*C_TOKEN_WIDTH-1:0] credited_token;
 wire [C_TOTAL_PORTS-1:0] egress_release_valid,ledger_release_ready,effective_release_ready;
 wire [C_TOTAL_PORTS*C_ACCOUNT_WIDTH-1:0] egress_release_account;
 wire [C_TOTAL_PORTS*C_TOKEN_WIDTH-1:0] egress_release_token;
 wire [C_NUM_GROUPS-1:0] ledger_quiescent,ledger_error;
 wire [C_TOTAL_TILES-1:0] tile_quiescent,tile_error;
 // Group/Tile标签由已验证的destination fabric消费；保留静态连接以便lint检查完整位宽。
 wire ignored_route_tags=^{credited_group,credited_tile};

 assign effective_release_ready=ledger_release_ready&i_release_path_enable;
 assign o_release_valid=egress_release_valid;
 assign o_release_ready=effective_release_ready;
 assign o_release_account=egress_release_account;
 assign o_release_token=egress_release_token;

 switch_destination_group_array #(.C_NUM_GROUPS(C_NUM_GROUPS),.C_PLANES(C_PLANES),.C_TILES(C_TILES),
  .C_BANK_LANES(C_BANK_LANES),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),.C_TILE_WIDTH(C_TILE_WIDTH),
  .C_CLASS_WIDTH(C_CLASS_WIDTH),.C_VC_WIDTH(C_VC_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),
  .C_CORE_CONTEXT_WIDTH(C_CORE_CONTEXT_WIDTH),.C_PLANE_WIDTH(C_PLANE_WIDTH),.C_OWNER_WIDTH(C_OWNER_WIDTH),
  .C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_GENERATION_WIDTH(C_GENERATION_WIDTH),
  .C_SLOT_WIDTH(C_SLOT_WIDTH),.C_BANK_SLOT_WIDTH(C_BANK_SLOT_WIDTH),.C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),
  .C_TOKEN_WIDTH(C_TOKEN_WIDTH),.C_CREDIT_COUNT_WIDTH(C_CREDIT_COUNT_WIDTH),.C_DST_LOCALS(C_PORTS_PER_TILE),
  .C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VC(C_NUM_VC),.C_CAPACITY(C_CAPACITY),.C_LANES(C_LANES),
  .C_REQUESTERS(C_REQUESTERS),.C_RESOURCES(C_RESOURCES),.C_ACCOUNTS(C_ACCOUNTS),.C_RELEASE_PORTS(C_RELEASE_PORTS))u_groups(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_epoch(i_epoch),.i_local_valid(i_local_valid),.o_local_ready(o_local_ready),
  .i_local_data(i_local_data),.i_local_meta(i_local_meta),.i_local_dst_group(i_local_dst_group),
  .i_local_dst_tile(i_local_dst_tile),.i_local_dst_port(i_local_dst_port),.i_local_class(i_local_class),
  .i_local_original_vc(i_local_original_vc),.i_local_pool(i_local_pool),.i_local_packet_flits(i_local_packet_flits),
  .i_local_sop(i_local_sop),.i_local_eop(i_local_eop),
  .i_core_valid(i_core_valid),.o_core_ready(o_core_ready),.i_core_data(i_core_data),.i_core_meta(i_core_meta),
  .i_core_dst_group(i_core_dst_group),.i_core_dst_tile(i_core_dst_tile),.i_core_dst_port(i_core_dst_port),
  .i_core_class(i_core_class),.i_core_packet_flits(i_core_packet_flits),.i_core_context(i_core_context),
  .i_core_original_vc(i_core_original_vc),.i_core_pool(i_core_pool),.i_core_sop(i_core_sop),.i_core_eop(i_core_eop),
  .o_valid(credited_valid),.i_ready(credited_ready),.o_data(credited_data),.o_meta(credited_meta),
  .o_dst_group(credited_group),.o_dst_tile(credited_tile),.o_dst_port(credited_port),.o_class(credited_class),
  .o_original_vc(credited_vc),.o_pool(credited_pool),.o_account(credited_account),.o_token(credited_token),
  .o_sop(credited_sop),.o_eop(credited_eop),.o_core_registered_eligibility(o_core_registered_eligibility),
  .o_core_eligibility_dst_tile(o_core_eligibility_dst_tile),.o_core_eligibility_dst_port(o_core_eligibility_dst_port),
  .o_core_eligibility_class(o_core_eligibility_class),.o_core_eligibility_epoch(o_core_eligibility_epoch),
  .i_release_valid(egress_release_valid&i_release_path_enable),.o_release_ready(ledger_release_ready),
  .i_release_token(egress_release_token),.o_free(o_free),.o_effective_free(o_effective_free),
  .o_issued(o_issued),.o_occupied(o_occupied),
  .o_group_quiescent(ledger_quiescent),.o_group_error(ledger_error),
  .o_return_malformed_event_level(o_return_malformed_event_level),
  .o_return_duplicate_event_level(o_return_duplicate_event_level),
  .o_return_stale_event_level(o_return_stale_event_level),
  .o_return_wrong_port_event_level(o_return_wrong_port_event_level));

 switch_destination_egress_array #(.C_NUM_GROUPS(C_NUM_GROUPS),.C_TILES(C_TILES),.C_BANK_LANES(C_BANK_LANES),
  .C_PORTS_PER_TILE(C_PORTS_PER_TILE),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VC(C_NUM_VC),
  .C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),.C_PORT_WIDTH(5),.C_CLASS_WIDTH(C_CLASS_WIDTH),
  .C_VC_WIDTH(C_VC_WIDTH),.C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_TOKEN_WIDTH(C_TOKEN_WIDTH),
  .C_QUEUE_DEPTH(C_QUEUE_DEPTH),.C_COUNT_WIDTH(C_QUEUE_COUNT_WIDTH),.C_GLOBAL_PORT_WIDTH(C_GLOBAL_PORT_WIDTH),
  .C_LANES_PER_GROUP(C_LANES),.C_TOTAL_TILES(C_TOTAL_TILES),.C_TOTAL_PORTS(C_TOTAL_PORTS),
  .C_RELEASE_PORTS_PER_GROUP(C_RELEASE_PORTS))u_egress(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(credited_valid),.o_ready(credited_ready),.i_data(credited_data),
  .i_meta(credited_meta),.i_dst_port(credited_port),.i_class(credited_class),.i_original_vc(credited_vc),
  .i_pool(credited_pool),.i_sop(credited_sop),.i_eop(credited_eop),.i_account(credited_account),.i_token(credited_token),
  .i_port_active(i_port_active),.i_upli_credit(i_upli_credit),.i_tl_credit(i_tl_credit),.i_link_up(i_link_up),
  .o_head_valid(o_head_valid),.o_valid(o_valid),.i_ready(i_ready),.o_data(o_data),.o_meta(o_meta),.o_class(o_class),
  .o_original_vc(o_original_vc),.o_pool(o_pool),.o_sop(o_sop),.o_eop(o_eop),.o_global_port_id(o_global_port_id),
  .o_release_valid(egress_release_valid),.i_release_ready(effective_release_ready),
  .o_release_account(egress_release_account),.o_release_token(egress_release_token),
  .o_tile_quiescent(tile_quiescent),.o_tile_error(tile_error),.o_config_error(o_config_error));

 // 每个Group只有其自身Tile与ledger同时为空才可参与route commit。
 genvar group_index;
 generate for(group_index=0;group_index<C_NUM_GROUPS;group_index=group_index+1)begin:g_status
  assign o_group_quiescent[group_index]=ledger_quiescent[group_index]&
   (&tile_quiescent[group_index*C_TILES+:C_TILES]);
  assign o_group_error[group_index]=ledger_error[group_index]|
   (|tile_error[group_index*C_TILES+:C_TILES])|o_config_error|(ignored_route_tags&1'b0);
 end endgenerate
endmodule
`default_nettype wire
