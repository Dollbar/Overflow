`timescale 1ns/1ps
`default_nettype none
// 可复用Source Tile：共享indexed Route/Identity表先冻结packet route，再进入banked VOQ Tile。
// 本层不拥有全Fabric commit状态或credit账本；external supervisor必须同时提供commit pulse、epoch与admission gate。
module switch_routed_source_tile #(
 parameter integer C_INGRESS_PORTS=32,parameter integer C_NUM_BANKS=8,
 parameter integer C_NUM_GROUPS=8,parameter integer C_TILES=4,parameter integer C_NUM_CLASSES=2,
 parameter integer C_NUM_VOQS=64,parameter integer C_QUEUE_DEPTH=8,
 parameter integer C_DATA_WIDTH=512,parameter integer C_META_WIDTH=32,
 parameter integer C_DST_ID_WIDTH=12,parameter integer C_DST_COUNT=4096,
 parameter integer C_PORT_WIDTH=10,parameter integer C_PORT_COUNT=1024,
 parameter integer C_QUEUE_WIDTH=6,parameter integer C_COUNT_WIDTH=4,
 parameter integer C_INGRESS_WIDTH=5,parameter integer C_BANK_WIDTH=3,
 parameter integer C_CLASS_WIDTH=1,parameter integer C_ADDR_WIDTH=3,
 parameter integer C_POLICY_WIDTH=8,parameter integer C_EPOCH_WIDTH=8,
 parameter integer C_PORTS_PER_TILE=32,parameter integer C_ACTIVE_GROUPS=C_NUM_GROUPS,
 parameter integer C_LOCAL_GROUP=0
)(
 input wire i_clk,input wire i_rstn,input wire [C_INGRESS_PORTS-1:0] i_valid,
 output wire [C_INGRESS_PORTS-1:0] o_ready,input wire [C_INGRESS_PORTS-1:0] i_committed,
 input wire [C_INGRESS_PORTS*C_DATA_WIDTH-1:0] i_data,input wire [C_INGRESS_PORTS*C_META_WIDTH-1:0] i_meta,
 input wire [C_INGRESS_PORTS*C_DST_ID_WIDTH-1:0] i_dst_id,
 input wire [C_INGRESS_PORTS*C_CLASS_WIDTH-1:0] i_class,input wire [C_INGRESS_PORTS*10-1:0] i_src_port,
 input wire [C_INGRESS_PORTS*2-1:0] i_vc,input wire [C_INGRESS_PORTS-1:0] i_pool,
 input wire [C_INGRESS_PORTS-1:0] i_sop,input wire [C_INGRESS_PORTS-1:0] i_eop,
 input wire [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
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
 output wire [C_NUM_BANKS-1:0] o_local_valid,input wire [C_NUM_BANKS-1:0] i_local_ready,
 output wire [C_NUM_BANKS-1:0] o_core_valid,input wire [C_NUM_BANKS-1:0] i_core_ready,
 output wire [C_NUM_BANKS*C_DATA_WIDTH-1:0] o_data,output wire [C_NUM_BANKS*C_META_WIDTH-1:0] o_meta,
 output wire [C_NUM_BANKS*3-1:0] o_dst_group,output wire [C_NUM_BANKS*2-1:0] o_dst_tile,
 output wire [C_NUM_BANKS*5-1:0] o_dst_port,output wire [C_NUM_BANKS*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_NUM_BANKS*10-1:0] o_src_port,output wire [C_NUM_BANKS*2-1:0] o_vc,
 output wire [C_NUM_BANKS-1:0] o_pool,output wire [C_NUM_BANKS*C_POLICY_WIDTH-1:0] o_route_policy,
 output wire [C_NUM_BANKS*C_EPOCH_WIDTH-1:0] o_route_epoch,output wire [C_NUM_BANKS-1:0] o_sop,
 output wire [C_NUM_BANKS-1:0] o_eop,output wire [C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_occupancy,
 output wire o_shadow_illegal,output wire o_quiescent,output wire o_route_error,
 output wire o_queue_overflow_event_level,output wire o_queue_underflow_event_level,
 output wire o_tile_error,output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=((C_NUM_VOQS==C_NUM_GROUPS*C_TILES*C_NUM_CLASSES)||
  (C_NUM_VOQS==C_ACTIVE_GROUPS*C_TILES*C_PORTS_PER_TILE*C_NUM_CLASSES))&&
  (C_INGRESS_PORTS>=1)&&(C_INGRESS_PORTS<=32)&&(C_NUM_BANKS>=1)&&(C_NUM_BANKS<=32);
 wire [C_INGRESS_PORTS-1:0] route_valid,route_ready;wire [C_INGRESS_PORTS*C_DATA_WIDTH-1:0] route_data;
 wire [C_INGRESS_PORTS*C_META_WIDTH-1:0] route_meta;wire [C_INGRESS_PORTS*3-1:0] route_group;
 wire [C_INGRESS_PORTS*2-1:0] route_tile,route_vc;wire [C_INGRESS_PORTS*5-1:0] route_port;
 wire [C_INGRESS_PORTS*C_CLASS_WIDTH-1:0] route_class;wire [C_INGRESS_PORTS*10-1:0] route_src;
 wire [C_INGRESS_PORTS-1:0] route_pool,route_sop,route_eop;wire [C_INGRESS_PORTS*C_POLICY_WIDTH-1:0] route_policy;
 wire [C_INGRESS_PORTS*C_EPOCH_WIDTH-1:0] route_epoch;wire [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] route_flits;
 wire [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] tile_flits;genvar flit_lane;
 wire frontend_quiescent,frontend_commit_error,tile_quiescent,tile_config_error,tile_path_error;
 switch_multi_ingress_route_frontend #(.C_INGRESS_PORTS(C_INGRESS_PORTS),.C_DATA_WIDTH(C_DATA_WIDTH),
  .C_META_WIDTH(C_META_WIDTH),.C_DST_ID_WIDTH(C_DST_ID_WIDTH),.C_DST_COUNT(C_DST_COUNT),.C_PORT_WIDTH(C_PORT_WIDTH),
  .C_PORT_COUNT(C_PORT_COUNT),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),
  .C_POLICY_WIDTH(C_POLICY_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_NUM_GROUPS(C_NUM_GROUPS),
  .C_TILES_PER_GROUP(C_TILES),.C_PORTS_PER_TILE(C_PORTS_PER_TILE),.C_EXTERNAL_COMMIT(1)) u_route_frontend(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(i_valid),.o_ready(o_ready),.i_committed(i_committed),
  .i_data(i_data),.i_meta(i_meta),.i_dst_id(i_dst_id),.i_class(i_class),.i_src_port(i_src_port),.i_vc(i_vc),
  .i_pool(i_pool),.i_sop(i_sop),.i_eop(i_eop),.i_packet_flits(i_packet_flits),.o_valid(route_valid),
  .i_ready(route_ready),.o_data(route_data),.o_meta(route_meta),.o_dst_group(route_group),.o_dst_tile(route_tile),
  .o_dst_port(route_port),.o_class(route_class),.o_src_port(route_src),.o_vc(route_vc),.o_pool(route_pool),
  .o_route_policy(route_policy),.o_route_epoch(route_epoch),.o_sop(route_sop),.o_eop(route_eop),
  .o_packet_flits(route_flits),.i_route_shadow_write(i_route_shadow_write),.i_route_shadow_dst_id(i_route_shadow_dst_id),
  .i_route_shadow_valid(i_route_shadow_valid),.i_route_shadow_global_port(i_route_shadow_global_port),
  .i_route_shadow_policy(i_route_shadow_policy),.i_identity_shadow_write(i_identity_shadow_write),
  .i_identity_shadow_global_port(i_identity_shadow_global_port),.i_identity_shadow_active(i_identity_shadow_active),
  .i_identity_shadow_group(i_identity_shadow_group),.i_identity_shadow_tile(i_identity_shadow_tile),
  .i_identity_shadow_local_port(i_identity_shadow_local_port),.i_identity_shadow_station(i_identity_shadow_station),
  .i_identity_shadow_lane_mask(i_identity_shadow_lane_mask),.i_identity_shadow_service_units(i_identity_shadow_service_units),
  .i_station_active_mode(i_station_active_mode),.i_commit_request(1'b0),.i_external_commit_pulse(i_external_commit_pulse),
  .i_external_active_epoch(i_external_active_epoch),.i_external_admission_enable(i_external_admission_enable),
  .i_external_quiesce_request(i_external_quiesce_request),.i_external_commit_pending(i_external_commit_pending),
  .o_admission_enable(o_admission_enable),.o_quiesce_request(o_quiesce_request),.o_commit_pending(o_commit_pending),
  .o_active_epoch(o_active_epoch),.o_quiescent(frontend_quiescent),.o_active_route_bank(o_active_route_bank),
  .o_active_identity_bank(o_active_identity_bank),.o_commit_error(frontend_commit_error),.o_route_error(o_route_error),
  .o_shadow_illegal(o_shadow_illegal));
 // Frontend为整个packet冻结长度；Tile reservation合同只允许SOP携带长度，body必须归零。
 generate for(flit_lane=0;flit_lane<C_INGRESS_PORTS;flit_lane=flit_lane+1)begin:g_tile_flits
  assign tile_flits[flit_lane*C_COUNT_WIDTH+:C_COUNT_WIDTH]=route_sop[flit_lane]?
   route_flits[flit_lane*C_COUNT_WIDTH+:C_COUNT_WIDTH]:{C_COUNT_WIDTH{1'b0}};
 end endgenerate
 switch_tile_multi_ingress #(.C_INGRESS_PORTS(C_INGRESS_PORTS),.C_NUM_BANKS(C_NUM_BANKS),
  .C_NUM_GROUPS(C_NUM_GROUPS),.C_TILES(C_TILES),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VOQS(C_NUM_VOQS),
  .C_PORTS_PER_TILE(C_PORTS_PER_TILE),
  .C_ACTIVE_GROUPS(C_ACTIVE_GROUPS),
  .C_QUEUE_DEPTH(C_QUEUE_DEPTH),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),
  .C_QUEUE_WIDTH(C_QUEUE_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_INGRESS_WIDTH(C_INGRESS_WIDTH),
  .C_BANK_WIDTH(C_BANK_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_ADDR_WIDTH(C_ADDR_WIDTH),
  .C_POLICY_WIDTH(C_POLICY_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_LOCAL_GROUP(C_LOCAL_GROUP)) u_source_tile(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(route_valid),.o_ready(route_ready),.i_data(route_data),
  .i_meta(route_meta),.i_dst_group(route_group),.i_dst_tile(route_tile),.i_dst_port(route_port),.i_class(route_class),
  .i_src_port(route_src),.i_vc(route_vc),.i_pool(route_pool),.i_route_policy(route_policy),.i_route_epoch(route_epoch),
  .i_sop(route_sop),.i_eop(route_eop),.i_packet_flits(tile_flits),.o_local_valid(o_local_valid),
  .i_local_ready(i_local_ready),.o_core_valid(o_core_valid),.i_core_ready(i_core_ready),.o_data(o_data),.o_meta(o_meta),
  .o_dst_group(o_dst_group),.o_dst_tile(o_dst_tile),.o_dst_port(o_dst_port),.o_class(o_class),.o_src_port(o_src_port),
  .o_vc(o_vc),.o_pool(o_pool),.o_route_policy(o_route_policy),.o_route_epoch(o_route_epoch),.o_sop(o_sop),.o_eop(o_eop),
  .o_occupancy(o_occupancy),.o_overflow_event_level(o_queue_overflow_event_level),
  .o_underflow_event_level(o_queue_underflow_event_level),
  .o_config_error(tile_config_error),.o_error(tile_path_error),.o_quiescent(tile_quiescent));
 assign o_tile_error=tile_path_error;assign o_config_error=!CONFIG_LEGAL|tile_config_error;
 assign o_quiescent=CONFIG_LEGAL&&frontend_quiescent&&tile_quiescent;
 assign o_error=o_config_error|o_route_error|o_tile_error|frontend_commit_error;
endmodule
`default_nettype wire
