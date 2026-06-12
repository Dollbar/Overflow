`timescale 1ns/1ps
`default_nettype none
// Source Group到Core Plane组合矩阵：每个Group保留Tile×bank并行入口，并把Group×Plane转置到Plane×8输入。
module switch_source_core_matrix #(
 parameter integer C_NUM_SOURCE_GROUPS=8,parameter integer C_TILES_PER_GROUP=4,
 parameter integer C_INGRESS_PER_TILE=32,parameter integer C_BANKS_PER_TILE=8,
 parameter integer C_NUM_PLANES=32,parameter integer C_NUM_CLASSES=2,
 parameter integer C_NUM_VOQS=64,parameter integer C_QUEUE_DEPTH=8,
 parameter integer C_DATA_WIDTH=512,parameter integer C_META_WIDTH=32,
 parameter integer C_DST_ID_WIDTH=12,parameter integer C_DST_COUNT=4096,
 parameter integer C_PORT_WIDTH=10,parameter integer C_PORT_COUNT=1024,
 parameter integer C_QUEUE_WIDTH=6,parameter integer C_COUNT_WIDTH=4,
 parameter integer C_INGRESS_WIDTH=5,parameter integer C_BANK_WIDTH=3,
 parameter integer C_CLASS_WIDTH=1,parameter integer C_ADDR_WIDTH=3,
 parameter integer C_POLICY_WIDTH=8,parameter integer C_EPOCH_WIDTH=8,
 parameter integer C_PORTS_PER_TILE=32,parameter integer C_TILE_WIDTH=2,
 parameter integer C_SOURCE_WIDTH=5
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_valid,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] o_ready,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_committed,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_DATA_WIDTH-1:0] i_data,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_META_WIDTH-1:0] i_meta,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_DST_ID_WIDTH-1:0] i_dst_id,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE*10-1:0] i_src_port,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE*2-1:0] i_vc,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_pool,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_sop,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE-1:0] i_eop,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE*C_COUNT_WIDTH-1:0] i_packet_flits,
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
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_NUM_PLANES-1:0] i_plane_eligible,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_hint_source_valid,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_hint_source_sop,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*3-1:0] o_hint_source_dst_group,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_TILE_WIDTH-1:0] o_hint_source_dst_tile,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*5-1:0] o_hint_source_dst_port,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_CLASS_WIDTH-1:0] o_hint_source_class,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_local_valid,
 input wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] i_local_ready,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_DATA_WIDTH-1:0] o_local_data,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_META_WIDTH-1:0] o_local_meta,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*3-1:0] o_local_dst_group,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_TILE_WIDTH-1:0] o_local_dst_tile,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*5-1:0] o_local_dst_port,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_CLASS_WIDTH-1:0] o_local_class,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*10-1:0] o_local_src_port,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*2-1:0] o_local_vc,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_local_pool,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_POLICY_WIDTH-1:0] o_local_route_policy,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_EPOCH_WIDTH-1:0] o_local_route_epoch,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE*C_COUNT_WIDTH-1:0] o_local_packet_flits,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_local_sop,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_BANKS_PER_TILE-1:0] o_local_eop,
 output wire [8*C_NUM_PLANES-1:0] o_remote_valid,input wire [8*C_NUM_PLANES-1:0] i_remote_ready,
 output wire [8*C_NUM_PLANES*C_DATA_WIDTH-1:0] o_remote_data,
 output wire [8*C_NUM_PLANES*C_META_WIDTH-1:0] o_remote_meta,
 output wire [8*C_NUM_PLANES*3-1:0] o_remote_dst_group,
 output wire [8*C_NUM_PLANES*C_TILE_WIDTH-1:0] o_remote_dst_tile,
 output wire [8*C_NUM_PLANES*5-1:0] o_remote_dst_port,
 output wire [8*C_NUM_PLANES*C_CLASS_WIDTH-1:0] o_remote_class,
 output wire [8*C_NUM_PLANES*3-1:0] o_remote_src_group,
 output wire [8*C_NUM_PLANES*10-1:0] o_remote_src_port,
 output wire [8*C_NUM_PLANES*2-1:0] o_remote_vc,
 output wire [8*C_NUM_PLANES-1:0] o_remote_pool,
 output wire [8*C_NUM_PLANES*C_POLICY_WIDTH-1:0] o_remote_route_policy,
 output wire [8*C_NUM_PLANES*C_EPOCH_WIDTH-1:0] o_remote_route_epoch,
 output wire [8*C_NUM_PLANES*C_COUNT_WIDTH-1:0] o_remote_packet_flits,
 output wire [8*C_NUM_PLANES-1:0] o_remote_sop,output wire [8*C_NUM_PLANES-1:0] o_remote_eop,
 output wire [C_NUM_SOURCE_GROUPS-1:0] o_source_quiescent,
 output wire [C_NUM_SOURCE_GROUPS-1:0] o_source_config_error,
 output wire [C_NUM_SOURCE_GROUPS-1:0] o_source_error,
 output wire o_queue_overflow_event_level,output wire o_queue_underflow_event_level,
 output wire [8*C_NUM_PLANES-1:0] o_core_route_error,
 output wire [8*C_NUM_PLANES-1:0] o_core_protocol_error,
 output wire [8*C_NUM_PLANES-1:0] o_core_owner_valid,
 output wire [C_NUM_SOURCE_GROUPS*C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_occupancy,
 output wire o_core_quiescent,output wire o_quiescent,output wire o_config_error,output wire o_error
);
 localparam integer C_INPUTS_PER_GROUP=C_TILES_PER_GROUP*C_INGRESS_PER_TILE;
 localparam integer C_LANES_PER_GROUP=C_TILES_PER_GROUP*C_BANKS_PER_TILE;
 localparam integer C_CORE_META_WIDTH=C_META_WIDTH+3+3+C_TILE_WIDTH+5+C_CLASS_WIDTH+10+2+1+
  C_POLICY_WIDTH+C_EPOCH_WIDTH+C_COUNT_WIDTH;
 localparam integer C_REMOTE_PAYLOAD_WIDTH=C_DATA_WIDTH+C_CORE_META_WIDTH+2;
 localparam CONFIG_LEGAL=(C_NUM_SOURCE_GROUPS>=1)&&(C_NUM_SOURCE_GROUPS<=8)&&
  (C_TILES_PER_GROUP>=1)&&(C_TILES_PER_GROUP<=4)&&(C_INGRESS_PER_TILE>=1)&&
  (C_BANKS_PER_TILE>=1)&&(C_NUM_PLANES>=1)&&(C_NUM_PLANES<=32)&&
  (C_TILE_WIDTH>=1)&&(C_CORE_META_WIDTH>=1)&&(C_REMOTE_PAYLOAD_WIDTH<=65536);

 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES-1:0] source_plane_valid;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES-1:0] source_plane_ready;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*C_DATA_WIDTH-1:0] source_plane_data;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*C_META_WIDTH-1:0] source_plane_meta;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*3-1:0] source_plane_group;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*C_TILE_WIDTH-1:0] source_plane_tile;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*5-1:0] source_plane_port;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*C_CLASS_WIDTH-1:0] source_plane_class;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*10-1:0] source_plane_src;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*2-1:0] source_plane_vc;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES-1:0] source_plane_pool;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*C_POLICY_WIDTH-1:0] source_plane_policy;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*C_EPOCH_WIDTH-1:0] source_plane_epoch;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES*C_COUNT_WIDTH-1:0] source_plane_flits;
 wire [C_NUM_SOURCE_GROUPS*C_NUM_PLANES-1:0] source_plane_sop,source_plane_eop;
 wire [C_NUM_SOURCE_GROUPS-1:0] source_admission,source_quiesce_request,source_commit_pending;
 wire [C_NUM_SOURCE_GROUPS*C_EPOCH_WIDTH-1:0] source_active_epoch;
 wire [C_NUM_SOURCE_GROUPS-1:0] source_route_bank,source_identity_bank,source_shadow_illegal;
 wire [C_NUM_SOURCE_GROUPS-1:0] source_bank_mismatch,source_group_quiescent;
 wire [C_NUM_SOURCE_GROUPS-1:0] source_queue_overflow_event_level,source_queue_underflow_event_level;

 wire core_path_config_error,core_path_error,core_path_quiescent;

 genvar source_group_index,plane_index,unused_group_index,destination_group_index;
 generate
  for(source_group_index=0;source_group_index<C_NUM_SOURCE_GROUPS;source_group_index=source_group_index+1)begin:g_source_group
   wire unused_admission,unused_quiesce_request,unused_commit_pending,unused_route_bank,unused_identity_bank;
   wire unused_shadow_illegal,unused_bank_mismatch,unused_group_quiescent;
   wire [C_EPOCH_WIDTH-1:0] unused_epoch;
   switch_routed_source_group_fabric #(
    .C_TILES_PER_GROUP(C_TILES_PER_GROUP),.C_INGRESS_PER_TILE(C_INGRESS_PER_TILE),
    .C_BANKS_PER_TILE(C_BANKS_PER_TILE),.C_NUM_GROUPS(8),.C_NUM_PLANES(C_NUM_PLANES),
    .C_ACTIVE_GROUPS(C_NUM_SOURCE_GROUPS),
    .C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VOQS(C_NUM_VOQS),.C_QUEUE_DEPTH(C_QUEUE_DEPTH),
    .C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),.C_DST_ID_WIDTH(C_DST_ID_WIDTH),
    .C_DST_COUNT(C_DST_COUNT),.C_PORT_WIDTH(C_PORT_WIDTH),.C_PORT_COUNT(C_PORT_COUNT),
    .C_QUEUE_WIDTH(C_QUEUE_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_INGRESS_WIDTH(C_INGRESS_WIDTH),
    .C_BANK_WIDTH(C_BANK_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_ADDR_WIDTH(C_ADDR_WIDTH),
    .C_POLICY_WIDTH(C_POLICY_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_PORTS_PER_TILE(C_PORTS_PER_TILE),
    .C_LOCAL_GROUP(source_group_index),.C_TILE_WIDTH(C_TILE_WIDTH),.C_SOURCE_WIDTH(C_SOURCE_WIDTH),
    .C_LANES(C_LANES_PER_GROUP),.C_INPUTS(C_INPUTS_PER_GROUP)) u_source_group(
    .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),
    .i_valid(i_valid[source_group_index*C_INPUTS_PER_GROUP+:C_INPUTS_PER_GROUP]),
    .o_ready(o_ready[source_group_index*C_INPUTS_PER_GROUP+:C_INPUTS_PER_GROUP]),
    .i_committed(i_committed[source_group_index*C_INPUTS_PER_GROUP+:C_INPUTS_PER_GROUP]),
    .i_data(i_data[source_group_index*C_INPUTS_PER_GROUP*C_DATA_WIDTH+:C_INPUTS_PER_GROUP*C_DATA_WIDTH]),
    .i_meta(i_meta[source_group_index*C_INPUTS_PER_GROUP*C_META_WIDTH+:C_INPUTS_PER_GROUP*C_META_WIDTH]),
    .i_dst_id(i_dst_id[source_group_index*C_INPUTS_PER_GROUP*C_DST_ID_WIDTH+:C_INPUTS_PER_GROUP*C_DST_ID_WIDTH]),
    .i_class(i_class[source_group_index*C_INPUTS_PER_GROUP*C_CLASS_WIDTH+:C_INPUTS_PER_GROUP*C_CLASS_WIDTH]),
    .i_src_port(i_src_port[source_group_index*C_INPUTS_PER_GROUP*10+:C_INPUTS_PER_GROUP*10]),
    .i_vc(i_vc[source_group_index*C_INPUTS_PER_GROUP*2+:C_INPUTS_PER_GROUP*2]),
    .i_pool(i_pool[source_group_index*C_INPUTS_PER_GROUP+:C_INPUTS_PER_GROUP]),
    .i_sop(i_sop[source_group_index*C_INPUTS_PER_GROUP+:C_INPUTS_PER_GROUP]),
    .i_eop(i_eop[source_group_index*C_INPUTS_PER_GROUP+:C_INPUTS_PER_GROUP]),
    .i_packet_flits(i_packet_flits[source_group_index*C_INPUTS_PER_GROUP*C_COUNT_WIDTH+:C_INPUTS_PER_GROUP*C_COUNT_WIDTH]),
    .i_route_shadow_write(i_route_shadow_write),.i_route_shadow_dst_id(i_route_shadow_dst_id),
    .i_route_shadow_valid(i_route_shadow_valid),.i_route_shadow_global_port(i_route_shadow_global_port),
    .i_route_shadow_policy(i_route_shadow_policy),.i_identity_shadow_write(i_identity_shadow_write),
    .i_identity_shadow_global_port(i_identity_shadow_global_port),.i_identity_shadow_active(i_identity_shadow_active),
    .i_identity_shadow_group(i_identity_shadow_group),.i_identity_shadow_tile(i_identity_shadow_tile),
    .i_identity_shadow_local_port(i_identity_shadow_local_port),.i_identity_shadow_station(i_identity_shadow_station),
    .i_identity_shadow_lane_mask(i_identity_shadow_lane_mask),.i_identity_shadow_service_units(i_identity_shadow_service_units),
    .i_station_active_mode(i_station_active_mode),.i_external_commit_pulse(i_external_commit_pulse),
    .i_external_active_epoch(i_external_active_epoch),.i_external_admission_enable(i_external_admission_enable),
    .i_external_quiesce_request(i_external_quiesce_request),.i_external_commit_pending(i_external_commit_pending),
    .i_plane_eligible(i_plane_eligible[source_group_index*C_LANES_PER_GROUP*C_NUM_PLANES+:C_LANES_PER_GROUP*C_NUM_PLANES]),
    .o_hint_source_valid(o_hint_source_valid[source_group_index*C_LANES_PER_GROUP+:C_LANES_PER_GROUP]),
    .o_hint_source_sop(o_hint_source_sop[source_group_index*C_LANES_PER_GROUP+:C_LANES_PER_GROUP]),
    .o_hint_source_dst_group(o_hint_source_dst_group[source_group_index*C_LANES_PER_GROUP*3+:C_LANES_PER_GROUP*3]),
    .o_hint_source_dst_tile(o_hint_source_dst_tile[source_group_index*C_LANES_PER_GROUP*C_TILE_WIDTH+:C_LANES_PER_GROUP*C_TILE_WIDTH]),
    .o_hint_source_dst_port(o_hint_source_dst_port[source_group_index*C_LANES_PER_GROUP*5+:C_LANES_PER_GROUP*5]),
    .o_hint_source_class(o_hint_source_class[source_group_index*C_LANES_PER_GROUP*C_CLASS_WIDTH+:C_LANES_PER_GROUP*C_CLASS_WIDTH]),
    .o_local_valid(o_local_valid[source_group_index*C_LANES_PER_GROUP+:C_LANES_PER_GROUP]),
    .i_local_ready(i_local_ready[source_group_index*C_LANES_PER_GROUP+:C_LANES_PER_GROUP]),
    .o_local_data(o_local_data[source_group_index*C_LANES_PER_GROUP*C_DATA_WIDTH+:C_LANES_PER_GROUP*C_DATA_WIDTH]),
    .o_local_meta(o_local_meta[source_group_index*C_LANES_PER_GROUP*C_META_WIDTH+:C_LANES_PER_GROUP*C_META_WIDTH]),
    .o_local_dst_group(o_local_dst_group[source_group_index*C_LANES_PER_GROUP*3+:C_LANES_PER_GROUP*3]),
    .o_local_dst_tile(o_local_dst_tile[source_group_index*C_LANES_PER_GROUP*C_TILE_WIDTH+:C_LANES_PER_GROUP*C_TILE_WIDTH]),
    .o_local_dst_port(o_local_dst_port[source_group_index*C_LANES_PER_GROUP*5+:C_LANES_PER_GROUP*5]),
    .o_local_class(o_local_class[source_group_index*C_LANES_PER_GROUP*C_CLASS_WIDTH+:C_LANES_PER_GROUP*C_CLASS_WIDTH]),
    .o_local_src_port(o_local_src_port[source_group_index*C_LANES_PER_GROUP*10+:C_LANES_PER_GROUP*10]),
    .o_local_vc(o_local_vc[source_group_index*C_LANES_PER_GROUP*2+:C_LANES_PER_GROUP*2]),
    .o_local_pool(o_local_pool[source_group_index*C_LANES_PER_GROUP+:C_LANES_PER_GROUP]),
    .o_local_route_policy(o_local_route_policy[source_group_index*C_LANES_PER_GROUP*C_POLICY_WIDTH+:C_LANES_PER_GROUP*C_POLICY_WIDTH]),
    .o_local_route_epoch(o_local_route_epoch[source_group_index*C_LANES_PER_GROUP*C_EPOCH_WIDTH+:C_LANES_PER_GROUP*C_EPOCH_WIDTH]),
    .o_local_packet_flits(o_local_packet_flits[source_group_index*C_LANES_PER_GROUP*C_COUNT_WIDTH+:C_LANES_PER_GROUP*C_COUNT_WIDTH]),
    .o_local_sop(o_local_sop[source_group_index*C_LANES_PER_GROUP+:C_LANES_PER_GROUP]),
    .o_local_eop(o_local_eop[source_group_index*C_LANES_PER_GROUP+:C_LANES_PER_GROUP]),
    .o_plane_valid(source_plane_valid[source_group_index*C_NUM_PLANES+:C_NUM_PLANES]),
    .i_plane_ready(source_plane_ready[source_group_index*C_NUM_PLANES+:C_NUM_PLANES]),
    .o_plane_data(source_plane_data[source_group_index*C_NUM_PLANES*C_DATA_WIDTH+:C_NUM_PLANES*C_DATA_WIDTH]),
    .o_plane_meta(source_plane_meta[source_group_index*C_NUM_PLANES*C_META_WIDTH+:C_NUM_PLANES*C_META_WIDTH]),
    .o_plane_dst_group(source_plane_group[source_group_index*C_NUM_PLANES*3+:C_NUM_PLANES*3]),
    .o_plane_dst_tile(source_plane_tile[source_group_index*C_NUM_PLANES*C_TILE_WIDTH+:C_NUM_PLANES*C_TILE_WIDTH]),
    .o_plane_dst_port(source_plane_port[source_group_index*C_NUM_PLANES*5+:C_NUM_PLANES*5]),
    .o_plane_class(source_plane_class[source_group_index*C_NUM_PLANES*C_CLASS_WIDTH+:C_NUM_PLANES*C_CLASS_WIDTH]),
    .o_plane_src_port(source_plane_src[source_group_index*C_NUM_PLANES*10+:C_NUM_PLANES*10]),
    .o_plane_vc(source_plane_vc[source_group_index*C_NUM_PLANES*2+:C_NUM_PLANES*2]),
    .o_plane_pool(source_plane_pool[source_group_index*C_NUM_PLANES+:C_NUM_PLANES]),
    .o_plane_route_policy(source_plane_policy[source_group_index*C_NUM_PLANES*C_POLICY_WIDTH+:C_NUM_PLANES*C_POLICY_WIDTH]),
    .o_plane_route_epoch(source_plane_epoch[source_group_index*C_NUM_PLANES*C_EPOCH_WIDTH+:C_NUM_PLANES*C_EPOCH_WIDTH]),
    .o_plane_packet_flits(source_plane_flits[source_group_index*C_NUM_PLANES*C_COUNT_WIDTH+:C_NUM_PLANES*C_COUNT_WIDTH]),
    .o_plane_sop(source_plane_sop[source_group_index*C_NUM_PLANES+:C_NUM_PLANES]),
    .o_plane_eop(source_plane_eop[source_group_index*C_NUM_PLANES+:C_NUM_PLANES]),
    .o_admission_enable(unused_admission),.o_quiesce_request(unused_quiesce_request),
    .o_commit_pending(unused_commit_pending),.o_active_epoch(unused_epoch),
    .o_active_route_bank(unused_route_bank),.o_active_identity_bank(unused_identity_bank),
    .o_shadow_illegal(unused_shadow_illegal),.o_bank_mismatch_error(unused_bank_mismatch),
    .o_queue_overflow_event_level(source_queue_overflow_event_level[source_group_index]),
    .o_queue_underflow_event_level(source_queue_underflow_event_level[source_group_index]),
    .o_group_quiescent(unused_group_quiescent),.o_quiescent(o_source_quiescent[source_group_index]),
    .o_occupancy(o_occupancy[source_group_index*C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH+:C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH]),
    .o_config_error(o_source_config_error[source_group_index]),.o_error(o_source_error[source_group_index]));
   assign source_admission[source_group_index]=unused_admission;
   assign source_quiesce_request[source_group_index]=unused_quiesce_request;
   assign source_commit_pending[source_group_index]=unused_commit_pending;
   assign source_active_epoch[source_group_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]=unused_epoch;
   assign source_route_bank[source_group_index]=unused_route_bank;
   assign source_identity_bank[source_group_index]=unused_identity_bank;
   assign source_shadow_illegal[source_group_index]=unused_shadow_illegal;
   assign source_bank_mismatch[source_group_index]=unused_bank_mismatch;
   assign source_group_quiescent[source_group_index]=unused_group_quiescent;
  end
  if(C_NUM_SOURCE_GROUPS>1)begin:g_core_enabled
   wire [8*C_NUM_PLANES-1:0] core_input_valid,core_input_ready,core_input_sop,core_input_eop;
   wire [8*C_NUM_PLANES*C_DATA_WIDTH-1:0] core_input_data;
   wire [8*C_NUM_PLANES*C_CORE_META_WIDTH-1:0] core_input_meta;
   wire [8*C_NUM_PLANES*3-1:0] core_input_group;
   wire [8*C_NUM_PLANES-1:0] core_output_valid,core_output_ready,core_output_sop,core_output_eop;
   wire [8*C_NUM_PLANES*C_DATA_WIDTH-1:0] core_output_data;
   wire [8*C_NUM_PLANES*C_CORE_META_WIDTH-1:0] core_output_meta;
   wire [8*C_NUM_PLANES-1:0] remote_slice_quiescent,remote_slice_config,remote_slice_error;
   // 把source-major的每Group逐Plane输出转置为Core要求的plane-major、每Plane八个source槽。
   for(plane_index=0;plane_index<C_NUM_PLANES;plane_index=plane_index+1)begin:g_plane_map
    for(source_group_index=0;source_group_index<C_NUM_SOURCE_GROUPS;source_group_index=source_group_index+1)begin:g_active_source
     localparam integer SOURCE_INDEX=source_group_index*C_NUM_PLANES+plane_index;
     localparam integer CORE_INDEX=plane_index*8+source_group_index;
     assign core_input_valid[CORE_INDEX]=source_plane_valid[SOURCE_INDEX];
     assign core_input_sop[CORE_INDEX]=source_plane_sop[SOURCE_INDEX];
     assign core_input_eop[CORE_INDEX]=source_plane_eop[SOURCE_INDEX];
     assign source_plane_ready[SOURCE_INDEX]=core_input_ready[CORE_INDEX];
     assign core_input_data[CORE_INDEX*C_DATA_WIDTH+:C_DATA_WIDTH]=source_plane_data[SOURCE_INDEX*C_DATA_WIDTH+:C_DATA_WIDTH];
     assign core_input_group[CORE_INDEX*3+:3]=source_plane_group[SOURCE_INDEX*3+:3];
     assign core_input_meta[CORE_INDEX*C_CORE_META_WIDTH+:C_CORE_META_WIDTH]={source_group_index[2:0],
      source_plane_group[SOURCE_INDEX*3+:3],source_plane_tile[SOURCE_INDEX*C_TILE_WIDTH+:C_TILE_WIDTH],
      source_plane_port[SOURCE_INDEX*5+:5],source_plane_class[SOURCE_INDEX*C_CLASS_WIDTH+:C_CLASS_WIDTH],
      source_plane_src[SOURCE_INDEX*10+:10],source_plane_vc[SOURCE_INDEX*2+:2],source_plane_pool[SOURCE_INDEX],
      source_plane_policy[SOURCE_INDEX*C_POLICY_WIDTH+:C_POLICY_WIDTH],
      source_plane_epoch[SOURCE_INDEX*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
      source_plane_flits[SOURCE_INDEX*C_COUNT_WIDTH+:C_COUNT_WIDTH],
      source_plane_meta[SOURCE_INDEX*C_META_WIDTH+:C_META_WIDTH]};
    end
    for(unused_group_index=C_NUM_SOURCE_GROUPS;unused_group_index<8;unused_group_index=unused_group_index+1)begin:g_unused_source
     localparam integer CORE_INDEX=plane_index*8+unused_group_index;
     assign core_input_valid[CORE_INDEX]=1'b0;
     assign core_input_sop[CORE_INDEX]=1'b0;
     assign core_input_eop[CORE_INDEX]=1'b0;
     assign core_input_data[CORE_INDEX*C_DATA_WIDTH+:C_DATA_WIDTH]={C_DATA_WIDTH{1'b0}};
     assign core_input_group[CORE_INDEX*3+:3]=3'd0;
     assign core_input_meta[CORE_INDEX*C_CORE_META_WIDTH+:C_CORE_META_WIDTH]={C_CORE_META_WIDTH{1'b0}};
    end
   end

   switch_core_plane_array #(.C_NUM_PLANES(C_NUM_PLANES),.C_DATA_WIDTH(C_DATA_WIDTH),
    .C_META_WIDTH(C_CORE_META_WIDTH)) u_core(
    .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(core_input_valid),
    .i_route_valid(core_input_valid),.o_ready(core_input_ready),.i_data(core_input_data),
    .i_meta(core_input_meta),.i_dst_group(core_input_group),.i_sop(core_input_sop),.i_eop(core_input_eop),
    .o_valid(core_output_valid),.i_ready(core_output_ready),.o_data(core_output_data),
    .o_meta(core_output_meta),.o_sop(core_output_sop),.o_eop(core_output_eop),
    .o_route_error(o_core_route_error),.o_protocol_error(o_core_protocol_error),
    .o_owner_valid(o_core_owner_valid),.o_quiescent(o_core_quiescent));

   // Core出口使用独立elastic slice；外部顺序改为destination-major，再由Destination Group逐Plane消费。
   for(destination_group_index=0;destination_group_index<8;destination_group_index=destination_group_index+1)begin:g_destination
    for(plane_index=0;plane_index<C_NUM_PLANES;plane_index=plane_index+1)begin:g_output_plane
     localparam integer CORE_INDEX=plane_index*8+destination_group_index;
     localparam integer REMOTE_INDEX=destination_group_index*C_NUM_PLANES+plane_index;
     wire [C_REMOTE_PAYLOAD_WIDTH-1:0] slice_input,slice_output;
     wire [C_CORE_META_WIDTH-1:0] unpacked_meta;
     assign slice_input={core_output_sop[CORE_INDEX],core_output_eop[CORE_INDEX],
      core_output_meta[CORE_INDEX*C_CORE_META_WIDTH+:C_CORE_META_WIDTH],
      core_output_data[CORE_INDEX*C_DATA_WIDTH+:C_DATA_WIDTH]};
     switch_fabric_elastic_slice #(.C_PAYLOAD_WIDTH(C_REMOTE_PAYLOAD_WIDTH)) u_output_slice(
      .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(core_output_valid[CORE_INDEX]),
      .o_ready(core_output_ready[CORE_INDEX]),.i_payload(slice_input),.o_valid(o_remote_valid[REMOTE_INDEX]),
      .i_ready(i_remote_ready[REMOTE_INDEX]),.o_payload(slice_output),
      .o_quiescent(remote_slice_quiescent[REMOTE_INDEX]),
      .o_config_error(remote_slice_config[REMOTE_INDEX]),.o_error(remote_slice_error[REMOTE_INDEX]));
     assign {o_remote_sop[REMOTE_INDEX],o_remote_eop[REMOTE_INDEX],unpacked_meta,
      o_remote_data[REMOTE_INDEX*C_DATA_WIDTH+:C_DATA_WIDTH]}=slice_output;
     assign {o_remote_src_group[REMOTE_INDEX*3+:3],o_remote_dst_group[REMOTE_INDEX*3+:3],
      o_remote_dst_tile[REMOTE_INDEX*C_TILE_WIDTH+:C_TILE_WIDTH],o_remote_dst_port[REMOTE_INDEX*5+:5],
      o_remote_class[REMOTE_INDEX*C_CLASS_WIDTH+:C_CLASS_WIDTH],o_remote_src_port[REMOTE_INDEX*10+:10],
      o_remote_vc[REMOTE_INDEX*2+:2],o_remote_pool[REMOTE_INDEX],
      o_remote_route_policy[REMOTE_INDEX*C_POLICY_WIDTH+:C_POLICY_WIDTH],
      o_remote_route_epoch[REMOTE_INDEX*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
      o_remote_packet_flits[REMOTE_INDEX*C_COUNT_WIDTH+:C_COUNT_WIDTH],
      o_remote_meta[REMOTE_INDEX*C_META_WIDTH+:C_META_WIDTH]}=unpacked_meta;
    end
   end
   assign core_path_config_error=|remote_slice_config;
   assign core_path_error=|remote_slice_error;
   assign core_path_quiescent=&remote_slice_quiescent;
  end else begin:g_single_group_core_bypass
   // 单Group只有local destination；保持固定Core ABI为零，且不实例化Core owner/crossbar/slice状态。
   wire unused_core_inputs=^{1'b0,i_remote_ready,source_plane_valid,source_plane_data,
    source_plane_meta,source_plane_group,source_plane_tile,source_plane_port,source_plane_class,
    source_plane_src,source_plane_vc,source_plane_pool,source_plane_policy,source_plane_epoch,
    source_plane_flits,source_plane_sop,source_plane_eop,1'b0};
   assign source_plane_ready={C_NUM_PLANES{1'b0}};
   assign o_remote_valid={(8*C_NUM_PLANES){1'b0}};
   assign o_remote_data={(8*C_NUM_PLANES*C_DATA_WIDTH){1'b0}};
   assign o_remote_meta={(8*C_NUM_PLANES*C_META_WIDTH){1'b0}};
   assign o_remote_dst_group={(8*C_NUM_PLANES*3){1'b0}};
   assign o_remote_dst_tile={(8*C_NUM_PLANES*C_TILE_WIDTH){1'b0}};
   assign o_remote_dst_port={(8*C_NUM_PLANES*5){1'b0}};
   assign o_remote_class={(8*C_NUM_PLANES*C_CLASS_WIDTH){1'b0}};
   assign o_remote_src_group={(8*C_NUM_PLANES*3){1'b0}};
   assign o_remote_src_port={(8*C_NUM_PLANES*10){1'b0}};
   assign o_remote_vc={(8*C_NUM_PLANES*2){1'b0}};
   assign o_remote_pool={(8*C_NUM_PLANES){1'b0}};
   assign o_remote_route_policy={(8*C_NUM_PLANES*C_POLICY_WIDTH){1'b0}};
   assign o_remote_route_epoch={(8*C_NUM_PLANES*C_EPOCH_WIDTH){1'b0}};
   assign o_remote_packet_flits={(8*C_NUM_PLANES*C_COUNT_WIDTH){1'b0}};
   assign o_remote_sop={(8*C_NUM_PLANES){1'b0}};
   assign o_remote_eop={(8*C_NUM_PLANES){1'b0}};
   assign o_core_route_error={(8*C_NUM_PLANES){1'b0}};
   assign o_core_protocol_error={(8*C_NUM_PLANES){1'b0}};
   assign o_core_owner_valid={(8*C_NUM_PLANES){1'b0}};
   assign o_core_quiescent=CONFIG_LEGAL;
   assign core_path_config_error=1'b0;
   assign core_path_error=unused_core_inputs&1'b0;
   assign core_path_quiescent=1'b1;
  end
 endgenerate
 assign o_queue_overflow_event_level=|source_queue_overflow_event_level;
 assign o_queue_underflow_event_level=|source_queue_underflow_event_level;

 assign o_config_error=!CONFIG_LEGAL||(|o_source_config_error)||core_path_config_error;
 assign o_error=o_config_error||(|o_source_error)||(|o_core_route_error)||
  (|o_core_protocol_error)||core_path_error;
 assign o_quiescent=CONFIG_LEGAL&&(&o_source_quiescent)&&o_core_quiescent&&core_path_quiescent;
 wire unused_status=&{1'b0,source_admission,source_quiesce_request,source_commit_pending,
  source_active_epoch,source_route_bank,source_identity_bank,source_shadow_illegal,
  source_bank_mismatch,source_group_quiescent,1'b0};
endmodule
`default_nettype wire
