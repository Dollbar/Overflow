`timescale 1ns/1ps
`default_nettype none
// Source Group复制多个独立banked Tile；管理shadow/commit广播，业务输出保持Tile×bank并行而不做提前merge。
module switch_routed_source_group #(
 parameter integer C_TILES_PER_GROUP=4,parameter integer C_INGRESS_PER_TILE=32,parameter integer C_BANKS_PER_TILE=8,
 parameter integer C_NUM_GROUPS=8,parameter integer C_NUM_CLASSES=2,parameter integer C_NUM_VOQS=64,
 parameter integer C_QUEUE_DEPTH=8,parameter integer C_DATA_WIDTH=512,parameter integer C_META_WIDTH=32,
 parameter integer C_DST_ID_WIDTH=12,parameter integer C_DST_COUNT=4096,parameter integer C_PORT_WIDTH=10,
 parameter integer C_PORT_COUNT=1024,parameter integer C_QUEUE_WIDTH=6,parameter integer C_COUNT_WIDTH=4,
 parameter integer C_INGRESS_WIDTH=5,parameter integer C_BANK_WIDTH=3,parameter integer C_CLASS_WIDTH=1,
 parameter integer C_ADDR_WIDTH=3,parameter integer C_POLICY_WIDTH=8,parameter integer C_EPOCH_WIDTH=8,
 parameter integer C_PORTS_PER_TILE=32,parameter integer C_ACTIVE_GROUPS=C_NUM_GROUPS,
 parameter integer C_LOCAL_GROUP=0
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_valid,
 output wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] o_ready,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_committed,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_DATA_WIDTH-1:0] i_data,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_META_WIDTH-1:0] i_meta,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_DST_ID_WIDTH-1:0] i_dst_id,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE*10-1:0] i_src_port,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE*2-1:0] i_vc,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_pool,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_sop,input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_eop,
 input wire [C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_COUNT_WIDTH-1:0] i_packet_flits,
 input wire i_route_shadow_write,input wire [C_DST_ID_WIDTH-1:0] i_route_shadow_dst_id,
 input wire i_route_shadow_valid,input wire [C_PORT_WIDTH-1:0] i_route_shadow_global_port,
 input wire [C_POLICY_WIDTH-1:0] i_route_shadow_policy,input wire i_identity_shadow_write,
 input wire [C_PORT_WIDTH-1:0] i_identity_shadow_global_port,input wire i_identity_shadow_active,
 input wire [2:0] i_identity_shadow_group,input wire [1:0] i_identity_shadow_tile,
 input wire [4:0] i_identity_shadow_local_port,input wire [7:0] i_identity_shadow_station,
 input wire [3:0] i_identity_shadow_lane_mask,input wire [2:0] i_identity_shadow_service_units,
 input wire [1:0] i_station_active_mode,input wire i_external_commit_pulse,
 input wire [C_EPOCH_WIDTH-1:0] i_external_active_epoch,input wire i_external_admission_enable,
 input wire i_external_quiesce_request,input wire i_external_commit_pending,
 output wire o_admission_enable,output wire o_quiesce_request,output wire o_commit_pending,
 output wire [C_EPOCH_WIDTH-1:0] o_active_epoch,output wire o_active_route_bank,output wire o_active_identity_bank,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_local_valid,
 input wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] i_local_ready,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_core_valid,
 input wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] i_core_ready,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_DATA_WIDTH-1:0] o_data,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_META_WIDTH-1:0] o_meta,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*3-1:0] o_dst_group,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*2-1:0] o_dst_tile,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*5-1:0] o_dst_port,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*10-1:0] o_src_port,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*2-1:0] o_vc,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_pool,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_POLICY_WIDTH-1:0] o_route_policy,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_EPOCH_WIDTH-1:0] o_route_epoch,
 output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_sop,output wire [C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_eop,
 output wire [C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_occupancy,
 output wire [C_TILES_PER_GROUP-1:0] o_tile_quiescent,output wire [C_TILES_PER_GROUP-1:0] o_tile_error,
 output wire o_queue_overflow_event_level,output wire o_queue_underflow_event_level,
 output wire o_shadow_illegal,output wire o_bank_mismatch_error,output wire o_quiescent,
 output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=(C_TILES_PER_GROUP>=1)&&(C_TILES_PER_GROUP<=4)&&(C_INGRESS_PER_TILE>=1)&&
  (C_INGRESS_PER_TILE<=32)&&(C_BANKS_PER_TILE>=1)&&(C_BANKS_PER_TILE<=32);
 wire [C_TILES_PER_GROUP-1:0] tile_admission,tile_quiesce,tile_pending,tile_route_bank,tile_identity_bank;
 wire [C_TILES_PER_GROUP-1:0] tile_shadow_illegal,tile_route_error,tile_config_error,tile_combined_error;
 wire [C_TILES_PER_GROUP-1:0] tile_queue_overflow_event_level,tile_queue_underflow_event_level;
 wire [C_TILES_PER_GROUP*C_EPOCH_WIDTH-1:0] tile_epoch;wire banks_consistent,epoch_consistent;
 genvar tile_index;
 generate for(tile_index=0;tile_index<C_TILES_PER_GROUP;tile_index=tile_index+1)begin:g_tile
  switch_routed_source_tile #(.C_INGRESS_PORTS(C_INGRESS_PER_TILE),.C_NUM_BANKS(C_BANKS_PER_TILE),
   .C_NUM_GROUPS(C_NUM_GROUPS),.C_TILES(C_TILES_PER_GROUP),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VOQS(C_NUM_VOQS),
   .C_QUEUE_DEPTH(C_QUEUE_DEPTH),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),
   .C_DST_ID_WIDTH(C_DST_ID_WIDTH),.C_DST_COUNT(C_DST_COUNT),.C_PORT_WIDTH(C_PORT_WIDTH),.C_PORT_COUNT(C_PORT_COUNT),
   .C_QUEUE_WIDTH(C_QUEUE_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_INGRESS_WIDTH(C_INGRESS_WIDTH),
   .C_BANK_WIDTH(C_BANK_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_ADDR_WIDTH(C_ADDR_WIDTH),
   .C_POLICY_WIDTH(C_POLICY_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_PORTS_PER_TILE(C_PORTS_PER_TILE),
   .C_ACTIVE_GROUPS(C_ACTIVE_GROUPS),
   .C_LOCAL_GROUP(C_LOCAL_GROUP)) u_tile(
   .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),
   .i_valid(i_valid[tile_index*C_INGRESS_PER_TILE+:C_INGRESS_PER_TILE]),
   .o_ready(o_ready[tile_index*C_INGRESS_PER_TILE+:C_INGRESS_PER_TILE]),
   .i_committed(i_committed[tile_index*C_INGRESS_PER_TILE+:C_INGRESS_PER_TILE]),
   .i_data(i_data[tile_index*C_INGRESS_PER_TILE*C_DATA_WIDTH+:C_INGRESS_PER_TILE*C_DATA_WIDTH]),
   .i_meta(i_meta[tile_index*C_INGRESS_PER_TILE*C_META_WIDTH+:C_INGRESS_PER_TILE*C_META_WIDTH]),
   .i_dst_id(i_dst_id[tile_index*C_INGRESS_PER_TILE*C_DST_ID_WIDTH+:C_INGRESS_PER_TILE*C_DST_ID_WIDTH]),
   .i_class(i_class[tile_index*C_INGRESS_PER_TILE*C_CLASS_WIDTH+:C_INGRESS_PER_TILE*C_CLASS_WIDTH]),
   .i_src_port(i_src_port[tile_index*C_INGRESS_PER_TILE*10+:C_INGRESS_PER_TILE*10]),
   .i_vc(i_vc[tile_index*C_INGRESS_PER_TILE*2+:C_INGRESS_PER_TILE*2]),
   .i_pool(i_pool[tile_index*C_INGRESS_PER_TILE+:C_INGRESS_PER_TILE]),
   .i_sop(i_sop[tile_index*C_INGRESS_PER_TILE+:C_INGRESS_PER_TILE]),.i_eop(i_eop[tile_index*C_INGRESS_PER_TILE+:C_INGRESS_PER_TILE]),
   .i_packet_flits(i_packet_flits[tile_index*C_INGRESS_PER_TILE*C_COUNT_WIDTH+:C_INGRESS_PER_TILE*C_COUNT_WIDTH]),
   .i_route_shadow_write(i_route_shadow_write),.i_route_shadow_dst_id(i_route_shadow_dst_id),
   .i_route_shadow_valid(i_route_shadow_valid),.i_route_shadow_global_port(i_route_shadow_global_port),
   .i_route_shadow_policy(i_route_shadow_policy),.i_identity_shadow_write(i_identity_shadow_write),
   .i_identity_shadow_global_port(i_identity_shadow_global_port),.i_identity_shadow_active(i_identity_shadow_active),
   .i_identity_shadow_group(i_identity_shadow_group),.i_identity_shadow_tile(i_identity_shadow_tile),
   .i_identity_shadow_local_port(i_identity_shadow_local_port),.i_identity_shadow_station(i_identity_shadow_station),
   .i_identity_shadow_lane_mask(i_identity_shadow_lane_mask),.i_identity_shadow_service_units(i_identity_shadow_service_units),
   .i_station_active_mode(i_station_active_mode),.i_external_commit_pulse(i_external_commit_pulse),
   .i_external_active_epoch(i_external_active_epoch),.i_external_admission_enable(i_external_admission_enable&&banks_consistent&&epoch_consistent),
   .i_external_quiesce_request(i_external_quiesce_request),.i_external_commit_pending(i_external_commit_pending),
   .o_admission_enable(tile_admission[tile_index]),.o_quiesce_request(tile_quiesce[tile_index]),
   .o_commit_pending(tile_pending[tile_index]),.o_active_epoch(tile_epoch[tile_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]),
   .o_active_route_bank(tile_route_bank[tile_index]),.o_active_identity_bank(tile_identity_bank[tile_index]),
   .o_local_valid(o_local_valid[tile_index*C_BANKS_PER_TILE+:C_BANKS_PER_TILE]),
   .i_local_ready(i_local_ready[tile_index*C_BANKS_PER_TILE+:C_BANKS_PER_TILE]),
   .o_core_valid(o_core_valid[tile_index*C_BANKS_PER_TILE+:C_BANKS_PER_TILE]),
   .i_core_ready(i_core_ready[tile_index*C_BANKS_PER_TILE+:C_BANKS_PER_TILE]),
   .o_data(o_data[tile_index*C_BANKS_PER_TILE*C_DATA_WIDTH+:C_BANKS_PER_TILE*C_DATA_WIDTH]),
   .o_meta(o_meta[tile_index*C_BANKS_PER_TILE*C_META_WIDTH+:C_BANKS_PER_TILE*C_META_WIDTH]),
   .o_dst_group(o_dst_group[tile_index*C_BANKS_PER_TILE*3+:C_BANKS_PER_TILE*3]),
   .o_dst_tile(o_dst_tile[tile_index*C_BANKS_PER_TILE*2+:C_BANKS_PER_TILE*2]),
   .o_dst_port(o_dst_port[tile_index*C_BANKS_PER_TILE*5+:C_BANKS_PER_TILE*5]),
   .o_class(o_class[tile_index*C_BANKS_PER_TILE*C_CLASS_WIDTH+:C_BANKS_PER_TILE*C_CLASS_WIDTH]),
   .o_src_port(o_src_port[tile_index*C_BANKS_PER_TILE*10+:C_BANKS_PER_TILE*10]),
   .o_vc(o_vc[tile_index*C_BANKS_PER_TILE*2+:C_BANKS_PER_TILE*2]),
   .o_pool(o_pool[tile_index*C_BANKS_PER_TILE+:C_BANKS_PER_TILE]),
   .o_route_policy(o_route_policy[tile_index*C_BANKS_PER_TILE*C_POLICY_WIDTH+:C_BANKS_PER_TILE*C_POLICY_WIDTH]),
   .o_route_epoch(o_route_epoch[tile_index*C_BANKS_PER_TILE*C_EPOCH_WIDTH+:C_BANKS_PER_TILE*C_EPOCH_WIDTH]),
   .o_sop(o_sop[tile_index*C_BANKS_PER_TILE+:C_BANKS_PER_TILE]),.o_eop(o_eop[tile_index*C_BANKS_PER_TILE+:C_BANKS_PER_TILE]),
   .o_occupancy(o_occupancy[tile_index*C_NUM_VOQS*C_COUNT_WIDTH+:C_NUM_VOQS*C_COUNT_WIDTH]),
   .o_shadow_illegal(tile_shadow_illegal[tile_index]),.o_quiescent(o_tile_quiescent[tile_index]),
   .o_route_error(tile_route_error[tile_index]),.o_tile_error(o_tile_error[tile_index]),
   .o_queue_overflow_event_level(tile_queue_overflow_event_level[tile_index]),
   .o_queue_underflow_event_level(tile_queue_underflow_event_level[tile_index]),
   .o_config_error(tile_config_error[tile_index]),.o_error(tile_combined_error[tile_index]));
 end endgenerate
 assign banks_consistent=(tile_route_bank=={C_TILES_PER_GROUP{tile_route_bank[0]}})&&
  (tile_identity_bank=={C_TILES_PER_GROUP{tile_identity_bank[0]}});
 assign epoch_consistent=(tile_epoch=={C_TILES_PER_GROUP{i_external_active_epoch}});
 assign o_active_route_bank=tile_route_bank[0];assign o_active_identity_bank=tile_identity_bank[0];
 assign o_active_epoch=i_external_active_epoch;assign o_admission_enable=i_external_admission_enable&&banks_consistent&&epoch_consistent;
 assign o_quiesce_request=i_external_quiesce_request;assign o_commit_pending=i_external_commit_pending;
 assign o_shadow_illegal=|tile_shadow_illegal;assign o_bank_mismatch_error=!banks_consistent||!epoch_consistent;
 assign o_queue_overflow_event_level=|tile_queue_overflow_event_level;
 assign o_queue_underflow_event_level=|tile_queue_underflow_event_level;
 assign o_config_error=!CONFIG_LEGAL||(|tile_config_error);assign o_quiescent=CONFIG_LEGAL&&(&o_tile_quiescent);
 assign o_error=o_config_error||o_shadow_illegal||o_bank_mismatch_error||(|tile_route_error)||(|o_tile_error)||(|tile_combined_error);
 wire unused_ok=&{1'b0,tile_admission,tile_quiesce,tile_pending,1'b0};
endmodule
`default_nettype wire
