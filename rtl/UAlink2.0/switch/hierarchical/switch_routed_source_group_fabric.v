`timescale 1ns/1ps
`default_nettype none
// Source侧组合层：Route/Identity -> 每Tile独立VOQ/bank -> Source Group ->
// local/plane registered elastic boundary。Tile×bank lane在Source Group之前保持并行。
module switch_routed_source_group_fabric #(
 parameter integer C_TILES_PER_GROUP=4,parameter integer C_INGRESS_PER_TILE=32,
 parameter integer C_BANKS_PER_TILE=8,parameter integer C_NUM_GROUPS=8,
 parameter integer C_NUM_PLANES=32,parameter integer C_NUM_CLASSES=2,
 parameter integer C_NUM_VOQS=64,parameter integer C_QUEUE_DEPTH=8,
 parameter integer C_DATA_WIDTH=512,parameter integer C_META_WIDTH=32,
 parameter integer C_DST_ID_WIDTH=12,parameter integer C_DST_COUNT=4096,
 parameter integer C_PORT_WIDTH=10,parameter integer C_PORT_COUNT=1024,
 parameter integer C_QUEUE_WIDTH=6,parameter integer C_COUNT_WIDTH=4,
 parameter integer C_INGRESS_WIDTH=5,parameter integer C_BANK_WIDTH=3,
 parameter integer C_CLASS_WIDTH=1,parameter integer C_ADDR_WIDTH=3,
 parameter integer C_POLICY_WIDTH=8,parameter integer C_EPOCH_WIDTH=8,
 parameter integer C_PORTS_PER_TILE=32,parameter integer C_LOCAL_GROUP=0,
 parameter integer C_ACTIVE_GROUPS=C_NUM_GROUPS,
 parameter integer C_TILE_WIDTH=2,parameter integer C_SOURCE_WIDTH=5,
 parameter integer C_PLANE_INDEX_WIDTH=(C_NUM_PLANES<=2)?1:(C_NUM_PLANES<=4)?2:(C_NUM_PLANES<=8)?3:(C_NUM_PLANES<=16)?4:5,
 parameter integer C_LANES=C_TILES_PER_GROUP*C_BANKS_PER_TILE,
 parameter integer C_INPUTS=C_TILES_PER_GROUP*C_INGRESS_PER_TILE
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_INPUTS-1:0] i_valid,output wire [C_INPUTS-1:0] o_ready,
 input wire [C_INPUTS-1:0] i_committed,
 input wire [C_INPUTS*C_DATA_WIDTH-1:0] i_data,
 input wire [C_INPUTS*C_META_WIDTH-1:0] i_meta,
 input wire [C_INPUTS*C_DST_ID_WIDTH-1:0] i_dst_id,
 input wire [C_INPUTS*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_INPUTS*10-1:0] i_src_port,input wire [C_INPUTS*2-1:0] i_vc,
 input wire [C_INPUTS-1:0] i_pool,input wire [C_INPUTS-1:0] i_sop,
 input wire [C_INPUTS-1:0] i_eop,
 input wire [C_INPUTS*C_COUNT_WIDTH-1:0] i_packet_flits,
 input wire i_route_shadow_write,input wire [C_DST_ID_WIDTH-1:0] i_route_shadow_dst_id,
 input wire i_route_shadow_valid,input wire [C_PORT_WIDTH-1:0] i_route_shadow_global_port,
 input wire [C_POLICY_WIDTH-1:0] i_route_shadow_policy,input wire i_identity_shadow_write,
 input wire [C_PORT_WIDTH-1:0] i_identity_shadow_global_port,input wire i_identity_shadow_active,
 input wire [2:0] i_identity_shadow_group,input wire [1:0] i_identity_shadow_tile,
 input wire [4:0] i_identity_shadow_local_port,input wire [7:0] i_identity_shadow_station,
 input wire [3:0] i_identity_shadow_lane_mask,input wire [2:0] i_identity_shadow_service_units,
 input wire [1:0] i_station_active_mode,input wire i_external_commit_pulse,
 input wire [C_EPOCH_WIDTH-1:0] i_external_active_epoch,
 input wire i_external_admission_enable,input wire i_external_quiesce_request,
 input wire i_external_commit_pending,
 input wire [C_LANES*C_NUM_PLANES-1:0] i_plane_eligible,
 // Plane选择前的当前Core VOQ head标签，供外部credit hint cache逐资源查询。
 output wire [C_LANES-1:0] o_hint_source_valid,output wire [C_LANES-1:0] o_hint_source_sop,
 output wire [C_LANES*3-1:0] o_hint_source_dst_group,
 output wire [C_LANES*C_TILE_WIDTH-1:0] o_hint_source_dst_tile,
 output wire [C_LANES*5-1:0] o_hint_source_dst_port,
 output wire [C_LANES*C_CLASS_WIDTH-1:0] o_hint_source_class,
 output wire [C_LANES-1:0] o_local_valid,input wire [C_LANES-1:0] i_local_ready,
 output wire [C_LANES*C_DATA_WIDTH-1:0] o_local_data,
 output wire [C_LANES*C_META_WIDTH-1:0] o_local_meta,
 output wire [C_LANES*3-1:0] o_local_dst_group,
 output wire [C_LANES*C_TILE_WIDTH-1:0] o_local_dst_tile,
 output wire [C_LANES*5-1:0] o_local_dst_port,
 output wire [C_LANES*C_CLASS_WIDTH-1:0] o_local_class,
 output wire [C_LANES*10-1:0] o_local_src_port,
 output wire [C_LANES*2-1:0] o_local_vc,output wire [C_LANES-1:0] o_local_pool,
 output wire [C_LANES*C_POLICY_WIDTH-1:0] o_local_route_policy,
 output wire [C_LANES*C_EPOCH_WIDTH-1:0] o_local_route_epoch,
 output wire [C_LANES*C_COUNT_WIDTH-1:0] o_local_packet_flits,
 output wire [C_LANES-1:0] o_local_sop,output wire [C_LANES-1:0] o_local_eop,
 output wire [C_NUM_PLANES-1:0] o_plane_valid,input wire [C_NUM_PLANES-1:0] i_plane_ready,
 output wire [C_NUM_PLANES*C_DATA_WIDTH-1:0] o_plane_data,
 output wire [C_NUM_PLANES*C_META_WIDTH-1:0] o_plane_meta,
 output wire [C_NUM_PLANES*3-1:0] o_plane_dst_group,
 output wire [C_NUM_PLANES*C_TILE_WIDTH-1:0] o_plane_dst_tile,
 output wire [C_NUM_PLANES*5-1:0] o_plane_dst_port,
 output wire [C_NUM_PLANES*C_CLASS_WIDTH-1:0] o_plane_class,
 output wire [C_NUM_PLANES*10-1:0] o_plane_src_port,
 output wire [C_NUM_PLANES*2-1:0] o_plane_vc,output wire [C_NUM_PLANES-1:0] o_plane_pool,
 output wire [C_NUM_PLANES*C_POLICY_WIDTH-1:0] o_plane_route_policy,
 output wire [C_NUM_PLANES*C_EPOCH_WIDTH-1:0] o_plane_route_epoch,
 output wire [C_NUM_PLANES*C_COUNT_WIDTH-1:0] o_plane_packet_flits,
 output wire [C_NUM_PLANES-1:0] o_plane_sop,output wire [C_NUM_PLANES-1:0] o_plane_eop,
 output wire o_admission_enable,output wire o_quiesce_request,output wire o_commit_pending,
 output wire [C_EPOCH_WIDTH-1:0] o_active_epoch,output wire o_active_route_bank,
 output wire o_active_identity_bank,output wire o_shadow_illegal,
 output wire o_bank_mismatch_error,output wire o_group_quiescent,output wire o_quiescent,
 output wire o_queue_overflow_event_level,output wire o_queue_underflow_event_level,
 output wire [C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_occupancy,
 output wire o_config_error,output wire o_error
);
 localparam integer C_TILE_META_WIDTH=C_META_WIDTH+C_COUNT_WIDTH;
 localparam integer C_CONTEXT_WIDTH=C_META_WIDTH+C_COUNT_WIDTH+C_CLASS_WIDTH+10+2+1+
  C_POLICY_WIDTH+C_EPOCH_WIDTH;
 localparam integer C_BOUNDARY_WIDTH=C_DATA_WIDTH+C_CONTEXT_WIDTH+3+C_TILE_WIDTH+5+2;
 localparam CONFIG_LEGAL=(C_LANES==C_TILES_PER_GROUP*C_BANKS_PER_TILE)&&
  (C_INPUTS==C_TILES_PER_GROUP*C_INGRESS_PER_TILE)&&(C_NUM_PLANES>=1)&&
  (C_NUM_PLANES<=32)&&(C_CONTEXT_WIDTH>=1)&&(C_BOUNDARY_WIDTH<=65536);

 wire [C_INPUTS*C_TILE_META_WIDTH-1:0] tile_meta_in;
 wire [C_LANES-1:0] routed_local_valid,routed_local_ready;
 wire [C_LANES-1:0] routed_core_valid,routed_core_ready;
 wire [C_LANES*C_DATA_WIDTH-1:0] routed_data;
 wire [C_LANES*C_TILE_META_WIDTH-1:0] routed_meta;
 wire [C_LANES*3-1:0] routed_group;
 wire [C_LANES*2-1:0] routed_tile;
 wire [C_LANES*5-1:0] routed_port;
 wire [C_LANES*C_CLASS_WIDTH-1:0] routed_class;
 wire [C_LANES*10-1:0] routed_src;
 wire [C_LANES*2-1:0] routed_vc;
 wire [C_LANES-1:0] routed_pool,routed_sop,routed_eop;
 wire [C_LANES*C_POLICY_WIDTH-1:0] routed_policy;
 wire [C_LANES*C_EPOCH_WIDTH-1:0] routed_epoch;
 wire [C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH-1:0] routed_occupancy;
 wire [C_TILES_PER_GROUP-1:0] routed_tile_quiescent,routed_tile_error;
 wire routed_quiescent,routed_config_error,routed_error;

 wire [C_LANES*C_CONTEXT_WIDTH-1:0] group_meta_in;
 wire [C_LANES*C_TILE_WIDTH-1:0] group_tile_in;
 wire [C_LANES-1:0] local_raw_valid,local_raw_ready,local_raw_sop,local_raw_eop;
 wire [C_LANES*C_DATA_WIDTH-1:0] local_raw_data;
 wire [C_LANES*C_CONTEXT_WIDTH-1:0] local_raw_meta;
 wire [C_LANES*3-1:0] local_raw_group;
 wire [C_LANES*C_TILE_WIDTH-1:0] local_raw_tile;
 wire [C_LANES*5-1:0] local_raw_port;
 wire [C_NUM_PLANES-1:0] plane_raw_valid,plane_raw_ready,plane_raw_sop,plane_raw_eop;
 wire [C_NUM_PLANES*C_DATA_WIDTH-1:0] plane_raw_data;
 wire [C_NUM_PLANES*C_CONTEXT_WIDTH-1:0] plane_raw_meta;
 wire [C_NUM_PLANES*3-1:0] plane_raw_group;
 wire [C_NUM_PLANES*C_TILE_WIDTH-1:0] plane_raw_tile;
 wire [C_NUM_PLANES*5-1:0] plane_raw_port;
 wire group_config_error,group_error,group_internal_quiescent;
 wire [C_LANES-1:0] local_slice_quiescent,local_slice_config,local_slice_error;
 wire [C_NUM_PLANES-1:0] plane_slice_quiescent,plane_slice_config,plane_slice_error;
 wire [C_LANES*C_NUM_PLANES-1:0] ordered_plane_eligible;
 wire [C_LANES*C_PLANE_INDEX_WIDTH-1:0] ordered_affinity_plane;
 wire ordered_filter_config_error,ordered_filter_error;

 genvar input_gen,lane_gen,plane_gen;
 generate for(input_gen=0;input_gen<C_INPUTS;input_gen=input_gen+1)begin:g_input_meta
  assign tile_meta_in[input_gen*C_TILE_META_WIDTH+:C_TILE_META_WIDTH]=
   {i_sop[input_gen]?i_packet_flits[input_gen*C_COUNT_WIDTH+:C_COUNT_WIDTH]:{C_COUNT_WIDTH{1'b0}},
    i_meta[input_gen*C_META_WIDTH+:C_META_WIDTH]};
 end endgenerate

 switch_routed_source_group #(
  .C_TILES_PER_GROUP(C_TILES_PER_GROUP),.C_INGRESS_PER_TILE(C_INGRESS_PER_TILE),
  .C_BANKS_PER_TILE(C_BANKS_PER_TILE),.C_NUM_GROUPS(C_NUM_GROUPS),
  .C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VOQS(C_NUM_VOQS),.C_QUEUE_DEPTH(C_QUEUE_DEPTH),
  .C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_TILE_META_WIDTH),.C_DST_ID_WIDTH(C_DST_ID_WIDTH),
  .C_DST_COUNT(C_DST_COUNT),.C_PORT_WIDTH(C_PORT_WIDTH),.C_PORT_COUNT(C_PORT_COUNT),
  .C_QUEUE_WIDTH(C_QUEUE_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_INGRESS_WIDTH(C_INGRESS_WIDTH),
  .C_BANK_WIDTH(C_BANK_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_ADDR_WIDTH(C_ADDR_WIDTH),
  .C_POLICY_WIDTH(C_POLICY_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
  .C_PORTS_PER_TILE(C_PORTS_PER_TILE),.C_ACTIVE_GROUPS(C_ACTIVE_GROUPS),.C_LOCAL_GROUP(C_LOCAL_GROUP)) u_routed(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(i_valid),.o_ready(o_ready),
  .i_committed(i_committed),.i_data(i_data),.i_meta(tile_meta_in),.i_dst_id(i_dst_id),
  .i_class(i_class),.i_src_port(i_src_port),.i_vc(i_vc),.i_pool(i_pool),.i_sop(i_sop),.i_eop(i_eop),
  .i_packet_flits(i_packet_flits),.i_route_shadow_write(i_route_shadow_write),
  .i_route_shadow_dst_id(i_route_shadow_dst_id),.i_route_shadow_valid(i_route_shadow_valid),
  .i_route_shadow_global_port(i_route_shadow_global_port),.i_route_shadow_policy(i_route_shadow_policy),
  .i_identity_shadow_write(i_identity_shadow_write),.i_identity_shadow_global_port(i_identity_shadow_global_port),
  .i_identity_shadow_active(i_identity_shadow_active),.i_identity_shadow_group(i_identity_shadow_group),
  .i_identity_shadow_tile(i_identity_shadow_tile),.i_identity_shadow_local_port(i_identity_shadow_local_port),
  .i_identity_shadow_station(i_identity_shadow_station),.i_identity_shadow_lane_mask(i_identity_shadow_lane_mask),
  .i_identity_shadow_service_units(i_identity_shadow_service_units),.i_station_active_mode(i_station_active_mode),
  .i_external_commit_pulse(i_external_commit_pulse),.i_external_active_epoch(i_external_active_epoch),
  .i_external_admission_enable(i_external_admission_enable),.i_external_quiesce_request(i_external_quiesce_request),
  .i_external_commit_pending(i_external_commit_pending),.o_admission_enable(o_admission_enable),
  .o_quiesce_request(o_quiesce_request),.o_commit_pending(o_commit_pending),.o_active_epoch(o_active_epoch),
  .o_active_route_bank(o_active_route_bank),.o_active_identity_bank(o_active_identity_bank),
  .o_local_valid(routed_local_valid),.i_local_ready(routed_local_ready),.o_core_valid(routed_core_valid),
  .i_core_ready(routed_core_ready),.o_data(routed_data),.o_meta(routed_meta),.o_dst_group(routed_group),
  .o_dst_tile(routed_tile),.o_dst_port(routed_port),.o_class(routed_class),.o_src_port(routed_src),
  .o_vc(routed_vc),.o_pool(routed_pool),.o_route_policy(routed_policy),.o_route_epoch(routed_epoch),
 .o_sop(routed_sop),.o_eop(routed_eop),.o_occupancy(routed_occupancy),
  .o_tile_quiescent(routed_tile_quiescent),.o_tile_error(routed_tile_error),
  .o_shadow_illegal(o_shadow_illegal),.o_bank_mismatch_error(o_bank_mismatch_error),
  .o_queue_overflow_event_level(o_queue_overflow_event_level),
  .o_queue_underflow_event_level(o_queue_underflow_event_level),
  .o_quiescent(routed_quiescent),.o_config_error(routed_config_error),.o_error(routed_error));
 assign o_occupancy=routed_occupancy;

 generate for(lane_gen=0;lane_gen<C_LANES;lane_gen=lane_gen+1)begin:g_pack
  assign group_meta_in[lane_gen*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH]={
   routed_epoch[lane_gen*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
   routed_policy[lane_gen*C_POLICY_WIDTH+:C_POLICY_WIDTH],routed_pool[lane_gen],
   routed_vc[lane_gen*2+:2],routed_src[lane_gen*10+:10],
   routed_class[lane_gen*C_CLASS_WIDTH+:C_CLASS_WIDTH],
   routed_meta[lane_gen*C_TILE_META_WIDTH+C_META_WIDTH+:C_COUNT_WIDTH],
   routed_meta[lane_gen*C_TILE_META_WIDTH+:C_META_WIDTH]};
  assign group_tile_in[lane_gen*C_TILE_WIDTH+:C_TILE_WIDTH]=
   routed_tile[lane_gen*2+:C_TILE_WIDTH];
 end endgenerate

 // 所有普通Transit流在一个Route epoch内使用确定性Plane亲和。
 // 绑定Plane暂时无credit/disabled时只背压；只有quiescent后的新epoch允许显式resequence。
 switch_ordered_plane_filter #(
  .C_SOURCES(C_LANES),.C_PLANES(C_NUM_PLANES),.C_TILE_WIDTH(C_TILE_WIDTH),
  .C_CLASS_WIDTH(C_CLASS_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
  .C_PLANE_INDEX_WIDTH(C_PLANE_INDEX_WIDTH)) u_ordered_plane_filter(
  .i_valid(routed_core_valid),.i_sop(routed_sop),.i_eligible(i_plane_eligible),
  .i_src_port(routed_src),.i_dst_group(routed_group),.i_dst_tile(group_tile_in),
  .i_dst_port(routed_port),.i_class(routed_class),.i_original_vc(routed_vc),
  .i_pool(routed_pool),.i_route_epoch(routed_epoch),.o_eligible(ordered_plane_eligible),
  .o_affinity_plane(ordered_affinity_plane),.o_config_error(ordered_filter_config_error),
  .o_error(ordered_filter_error));

 switch_group_multi_lane #(.C_TILES(C_TILES_PER_GROUP),.C_BANK_LANES(C_BANKS_PER_TILE),
  .C_PLANES(C_NUM_PLANES),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_CONTEXT_WIDTH),
  .C_TILE_WIDTH(C_TILE_WIDTH),.C_SOURCE_WIDTH(C_SOURCE_WIDTH),.C_GROUP_ID(C_LOCAL_GROUP),
  .C_NUM_GROUPS(C_NUM_GROUPS)) u_group(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_local_valid(routed_local_valid),
  .o_local_ready(routed_local_ready),.i_local_data(routed_data),.i_local_meta(group_meta_in),
  .i_local_dst_group(routed_group),.i_local_dst_tile(group_tile_in),.i_local_dst_port(routed_port),
  .i_local_sop(routed_sop),.i_local_eop(routed_eop),.i_core_valid(routed_core_valid),
  .o_core_ready(routed_core_ready),.i_core_data(routed_data),.i_core_meta(group_meta_in),
  .i_core_dst_group(routed_group),.i_core_dst_tile(group_tile_in),.i_core_dst_port(routed_port),
  .i_core_sop(routed_sop),.i_core_eop(routed_eop),.i_plane_eligible(ordered_plane_eligible),
  .o_local_lane_valid(local_raw_valid),.i_local_lane_ready(local_raw_ready),
  .o_local_lane_data(local_raw_data),.o_local_lane_meta(local_raw_meta),
  .o_local_lane_dst_group(local_raw_group),.o_local_lane_dst_tile(local_raw_tile),
  .o_local_lane_dst_port(local_raw_port),.o_local_lane_sop(local_raw_sop),.o_local_lane_eop(local_raw_eop),
  .o_plane_valid(plane_raw_valid),.i_plane_ready(plane_raw_ready),.o_plane_data(plane_raw_data),
  .o_plane_meta(plane_raw_meta),.o_plane_dst_group(plane_raw_group),.o_plane_dst_tile(plane_raw_tile),
  .o_plane_dst_port(plane_raw_port),.o_plane_sop(plane_raw_sop),.o_plane_eop(plane_raw_eop),
  .o_config_error(group_config_error),.o_error(group_error),.o_quiescent(group_internal_quiescent));

 assign o_hint_source_valid=routed_core_valid;
 assign o_hint_source_sop=routed_sop;
 assign o_hint_source_dst_group=routed_group;
 assign o_hint_source_dst_tile=group_tile_in;
 assign o_hint_source_dst_port=routed_port;
 assign o_hint_source_class=routed_class;

 // local和plane各lane独立注册，不引入跨lane merge或全芯片组合ready。
 generate for(lane_gen=0;lane_gen<C_LANES;lane_gen=lane_gen+1)begin:g_local_boundary
  wire [C_BOUNDARY_WIDTH-1:0] payload_in,payload_out;
  assign payload_in={local_raw_group[lane_gen*3+:3],local_raw_tile[lane_gen*C_TILE_WIDTH+:C_TILE_WIDTH],
   local_raw_port[lane_gen*5+:5],local_raw_sop[lane_gen],local_raw_eop[lane_gen],
   local_raw_meta[lane_gen*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH],local_raw_data[lane_gen*C_DATA_WIDTH+:C_DATA_WIDTH]};
  switch_fabric_elastic_slice #(.C_PAYLOAD_WIDTH(C_BOUNDARY_WIDTH)) u_slice(
   .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(local_raw_valid[lane_gen]),
   .o_ready(local_raw_ready[lane_gen]),.i_payload(payload_in),.o_valid(o_local_valid[lane_gen]),
   .i_ready(i_local_ready[lane_gen]),.o_payload(payload_out),.o_quiescent(local_slice_quiescent[lane_gen]),
   .o_config_error(local_slice_config[lane_gen]),.o_error(local_slice_error[lane_gen]));
  assign {o_local_dst_group[lane_gen*3+:3],o_local_dst_tile[lane_gen*C_TILE_WIDTH+:C_TILE_WIDTH],
   o_local_dst_port[lane_gen*5+:5],o_local_sop[lane_gen],o_local_eop[lane_gen],
   o_local_route_epoch[lane_gen*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
   o_local_route_policy[lane_gen*C_POLICY_WIDTH+:C_POLICY_WIDTH],o_local_pool[lane_gen],
   o_local_vc[lane_gen*2+:2],o_local_src_port[lane_gen*10+:10],
   o_local_class[lane_gen*C_CLASS_WIDTH+:C_CLASS_WIDTH],
   o_local_packet_flits[lane_gen*C_COUNT_WIDTH+:C_COUNT_WIDTH],
   o_local_meta[lane_gen*C_META_WIDTH+:C_META_WIDTH],o_local_data[lane_gen*C_DATA_WIDTH+:C_DATA_WIDTH]}=payload_out;
 end
 for(plane_gen=0;plane_gen<C_NUM_PLANES;plane_gen=plane_gen+1)begin:g_plane_boundary
  wire [C_BOUNDARY_WIDTH-1:0] payload_in,payload_out;
  assign payload_in={plane_raw_group[plane_gen*3+:3],plane_raw_tile[plane_gen*C_TILE_WIDTH+:C_TILE_WIDTH],
   plane_raw_port[plane_gen*5+:5],plane_raw_sop[plane_gen],plane_raw_eop[plane_gen],
   plane_raw_meta[plane_gen*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH],plane_raw_data[plane_gen*C_DATA_WIDTH+:C_DATA_WIDTH]};
  switch_fabric_elastic_slice #(.C_PAYLOAD_WIDTH(C_BOUNDARY_WIDTH)) u_slice(
   .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(plane_raw_valid[plane_gen]),
   .o_ready(plane_raw_ready[plane_gen]),.i_payload(payload_in),.o_valid(o_plane_valid[plane_gen]),
   .i_ready(i_plane_ready[plane_gen]),.o_payload(payload_out),.o_quiescent(plane_slice_quiescent[plane_gen]),
   .o_config_error(plane_slice_config[plane_gen]),.o_error(plane_slice_error[plane_gen]));
  assign {o_plane_dst_group[plane_gen*3+:3],o_plane_dst_tile[plane_gen*C_TILE_WIDTH+:C_TILE_WIDTH],
   o_plane_dst_port[plane_gen*5+:5],o_plane_sop[plane_gen],o_plane_eop[plane_gen],
   o_plane_route_epoch[plane_gen*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
   o_plane_route_policy[plane_gen*C_POLICY_WIDTH+:C_POLICY_WIDTH],o_plane_pool[plane_gen],
   o_plane_vc[plane_gen*2+:2],o_plane_src_port[plane_gen*10+:10],
   o_plane_class[plane_gen*C_CLASS_WIDTH+:C_CLASS_WIDTH],
   o_plane_packet_flits[plane_gen*C_COUNT_WIDTH+:C_COUNT_WIDTH],
   o_plane_meta[plane_gen*C_META_WIDTH+:C_META_WIDTH],o_plane_data[plane_gen*C_DATA_WIDTH+:C_DATA_WIDTH]}=payload_out;
 end endgenerate

 assign o_group_quiescent=group_internal_quiescent;
 assign o_quiescent=CONFIG_LEGAL&&routed_quiescent&&group_internal_quiescent&&
  (&local_slice_quiescent)&&(&plane_slice_quiescent);
 assign o_config_error=!CONFIG_LEGAL||routed_config_error||group_config_error||
  ordered_filter_config_error||(|local_slice_config)||(|plane_slice_config);
 assign o_error=o_config_error||routed_error||group_error||(|routed_tile_error)||
  ordered_filter_error||(|local_slice_error)||(|plane_slice_error);
 wire unused_ok=&{1'b0,ordered_affinity_plane,routed_occupancy,routed_tile_quiescent,routed_tile,1'b0};
endmodule
`default_nettype wire
