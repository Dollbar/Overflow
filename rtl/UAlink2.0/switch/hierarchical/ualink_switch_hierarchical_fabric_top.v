`timescale 1ns/1ps
`default_nettype none
// UALink分层Fabric组合顶层：Source Tile/Group/Core与Destination credit/Egress逐级直连。
// Destination eligibility当前是已呈现Core请求的注册提示，不能启动首包；本层仅输出匹配观测。
// Source选择使用注册Plane使能，真实接纳始终由逐级ready与Destination credit账本决定。
module ualink_switch_hierarchical_fabric_top #(
 parameter integer C_NUM_GROUPS=1,parameter integer C_TILES_PER_GROUP=1,
 parameter integer C_INGRESS_PER_TILE=32,parameter integer C_BANKS_PER_TILE=8,
 parameter integer C_NUM_PLANES=1,parameter integer C_PORTS_PER_TILE=32,
 parameter integer C_NUM_CLASSES=4,parameter integer C_NUM_VC=4,
 parameter integer C_NUM_VOQS=C_NUM_GROUPS*C_TILES_PER_GROUP*C_PORTS_PER_TILE*C_NUM_CLASSES,
 parameter integer C_QUEUE_DEPTH=8,
 parameter integer C_DATA_WIDTH=512,parameter integer C_META_WIDTH=128,
 parameter integer C_DST_ID_WIDTH=12,parameter integer C_DST_COUNT=4096,
 parameter integer C_PORT_WIDTH=10,parameter integer C_PORT_COUNT=32,
 parameter integer C_QUEUE_WIDTH=7,parameter integer C_COUNT_WIDTH=5,
 parameter integer C_INGRESS_WIDTH=5,parameter integer C_BANK_WIDTH=3,
 parameter integer C_CLASS_WIDTH=2,parameter integer C_ADDR_WIDTH=3,
 parameter integer C_POLICY_WIDTH=8,parameter integer C_EPOCH_WIDTH=8,
 parameter integer C_TILE_WIDTH=2,parameter integer C_SOURCE_WIDTH=5,
 parameter integer C_PLANE_WIDTH=5,parameter integer C_OWNER_WIDTH=6,
 parameter integer C_RESOURCE_WIDTH=9,parameter integer C_GENERATION_WIDTH=8,
 parameter integer C_SLOT_WIDTH=11,parameter integer C_BANK_SLOT_WIDTH=2,
 parameter integer C_ACCOUNT_WIDTH=15,
 parameter integer C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH,
 parameter integer C_CREDIT_COUNT_WIDTH=3,parameter integer C_CREDIT_CAPACITY=4,
 parameter integer C_EGRESS_QUEUE_DEPTH=4,parameter integer C_EGRESS_COUNT_WIDTH=3,
 parameter integer C_TIMEOUT_CYCLES=1024,parameter integer C_TIMEOUT_WIDTH=11,
 parameter integer C_HINT_SEQUENCE_WIDTH=20,parameter integer C_HINT_TIME_WIDTH=32,
 parameter integer C_HINT_TTL_CYCLES=1024,parameter integer C_HINT_REFRESH_CYCLES=512,
 parameter integer C_LANES=C_TILES_PER_GROUP*C_BANKS_PER_TILE,
 parameter integer C_INPUTS=C_NUM_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE,
 parameter integer C_RELEASE_PORTS=C_TILES_PER_GROUP*C_PORTS_PER_TILE,
 parameter integer C_TOTAL_PORTS=C_NUM_GROUPS*C_RELEASE_PORTS,
 parameter integer C_RESOURCES=C_TILES_PER_GROUP*C_PORTS_PER_TILE*C_NUM_CLASSES,
 parameter integer C_REQUESTERS=C_LANES+C_NUM_PLANES,
 parameter integer C_ACCOUNTS=C_REQUESTERS*C_RESOURCES,
 parameter integer C_FABRIC_META_WIDTH=C_META_WIDTH+3+10+C_POLICY_WIDTH+C_EPOCH_WIDTH+C_COUNT_WIDTH
)(
 input wire i_clk,input wire i_rstn,
 // 已通过DL/TL commit barrier的Source ingress，顺序为Group/Tile/Ingress。
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
 // Route/Identity shadow窗口广播到所有Source Tile；管理层必须在commit前给出shadow合法性。
 input wire i_route_shadow_write,input wire [C_DST_ID_WIDTH-1:0] i_route_shadow_dst_id,
 input wire i_route_shadow_valid,input wire [C_PORT_WIDTH-1:0] i_route_shadow_global_port,
 input wire [C_POLICY_WIDTH-1:0] i_route_shadow_policy,input wire i_identity_shadow_write,
 input wire [C_PORT_WIDTH-1:0] i_identity_shadow_global_port,input wire i_identity_shadow_active,
 input wire [2:0] i_identity_shadow_group,input wire [1:0] i_identity_shadow_tile,
 input wire [4:0] i_identity_shadow_local_port,input wire [7:0] i_identity_shadow_station,
 input wire [3:0] i_identity_shadow_lane_mask,input wire [2:0] i_identity_shadow_service_units,
 input wire [1:0] i_station_active_mode,input wire i_route_commit_request,input wire i_shadow_illegal,
 // Plane管理使能在本层寄存，作为可启动首包的path-enable，不宣称为Destination credit。
 input wire [C_NUM_PLANES-1:0] i_plane_enable,
 // Logical Port真实链路与信用门控。
 input wire [C_TOTAL_PORTS-1:0] i_port_active,input wire [C_TOTAL_PORTS-1:0] i_upli_credit,
 input wire [C_TOTAL_PORTS-1:0] i_tl_credit,input wire [C_TOTAL_PORTS-1:0] i_link_up,
 output wire [C_TOTAL_PORTS-1:0] o_head_valid,output wire [C_TOTAL_PORTS-1:0] o_valid,input wire [C_TOTAL_PORTS-1:0] i_ready,
 output wire [C_TOTAL_PORTS*C_DATA_WIDTH-1:0] o_data,
 output wire [C_TOTAL_PORTS*C_META_WIDTH-1:0] o_meta,
 output wire [C_TOTAL_PORTS*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_TOTAL_PORTS*2-1:0] o_original_vc,output wire [C_TOTAL_PORTS-1:0] o_pool,
 output wire [C_TOTAL_PORTS-1:0] o_sop,output wire [C_TOTAL_PORTS-1:0] o_eop,
 output wire [C_TOTAL_PORTS*C_PORT_WIDTH-1:0] o_global_port_id,
 output wire [C_TOTAL_PORTS*3-1:0] o_src_group,output wire [C_TOTAL_PORTS*10-1:0] o_src_port,
 output wire [C_TOTAL_PORTS*C_POLICY_WIDTH-1:0] o_route_policy,
 output wire [C_TOTAL_PORTS*C_EPOCH_WIDTH-1:0] o_route_epoch,
 output wire [C_TOTAL_PORTS*C_COUNT_WIDTH-1:0] o_packet_flits,
 // Release path可被管理复位停住；token/account保持到真实ledger归还握手。
 input wire [C_TOTAL_PORTS-1:0] i_release_path_enable,
 output wire [C_TOTAL_PORTS-1:0] o_release_valid,output wire [C_TOTAL_PORTS-1:0] o_release_ready,
 output wire [C_TOTAL_PORTS*C_ACCOUNT_WIDTH-1:0] o_release_account,
 output wire [C_TOTAL_PORTS*C_TOKEN_WIDTH-1:0] o_release_token,
 // Advisory带标签匹配观测；这些位不参与首包授权。
 output wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] o_advisory_valid,
 output wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] o_advisory_match,
 output wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] o_advisory_mismatch,
 output wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] o_advisory_stale,
 // Source lane逐Plane的真实cache hint与受控probe观测。
 output wire [C_NUM_GROUPS*C_LANES*C_NUM_PLANES-1:0] o_source_hint_eligible,
 output wire [C_NUM_GROUPS*C_LANES*C_NUM_PLANES-1:0] o_source_hint_used,
 output wire [C_NUM_GROUPS*C_LANES*C_NUM_PLANES-1:0] o_source_probe_path,
 output wire [C_NUM_GROUPS-1:0] o_credit_hint_pending,
 output wire [C_NUM_GROUPS-1:0] o_credit_hint_error,
 // 全Fabric原子Route提交与RAS状态。
 output wire o_new_sop_admission,output wire o_quiesce_request,output wire o_commit_pulse,
 output wire o_commit_pending,output wire [C_EPOCH_WIDTH-1:0] o_active_epoch,
 output wire o_all_empty,output wire [C_TIMEOUT_WIDTH-1:0] o_commit_wait_cycles,
 output wire o_timeout_error,output wire o_inactive_group_error,
 output wire [C_NUM_GROUPS*C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] o_effective_free,
 output wire [C_NUM_GROUPS*C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_queue_occupancy,
 output wire [C_NUM_GROUPS*C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_credit_issued,
 output wire [C_NUM_GROUPS*C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_credit_occupied,
 output wire [3:0] o_destination_return_error_event_level,
 output wire o_ingress_queue_overflow_event_level,
 output wire o_ingress_queue_underflow_event_level,
 output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&
  (C_TILES_PER_GROUP>=1)&&(C_TILES_PER_GROUP<=4)&&(C_NUM_PLANES>=1)&&(C_NUM_PLANES<=32)&&
  (C_PORT_COUNT>=1)&&(C_PORT_COUNT<=32)&&(C_TOTAL_PORTS>=1)&&(C_TOTAL_PORTS<=32)&&
  (C_LANES==C_TILES_PER_GROUP*C_BANKS_PER_TILE)&&
  (C_INPUTS==C_NUM_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE)&&
  (C_RELEASE_PORTS==C_TILES_PER_GROUP*C_PORTS_PER_TILE)&&
  (C_TOTAL_PORTS==C_NUM_GROUPS*C_RELEASE_PORTS)&&(C_PORT_WIDTH==10)&&
  ((C_NUM_VOQS==8*C_TILES_PER_GROUP*C_NUM_CLASSES)||
   (C_NUM_VOQS==C_NUM_GROUPS*C_TILES_PER_GROUP*C_PORTS_PER_TILE*C_NUM_CLASSES))&&(C_NUM_VC==4);

 wire [C_NUM_GROUPS*C_LANES-1:0] source_local_valid,source_local_ready;
 wire [C_NUM_GROUPS*C_LANES*C_DATA_WIDTH-1:0] source_local_data;
 wire [C_NUM_GROUPS*C_LANES*C_META_WIDTH-1:0] source_local_meta;
 wire [C_NUM_GROUPS*C_LANES*3-1:0] source_local_group;
 wire [C_NUM_GROUPS*C_LANES*C_TILE_WIDTH-1:0] source_local_tile;
 wire [C_NUM_GROUPS*C_LANES*5-1:0] source_local_port;
 wire [C_NUM_GROUPS*C_LANES*C_CLASS_WIDTH-1:0] source_local_class;
 wire [C_NUM_GROUPS*C_LANES*10-1:0] source_local_src_port;
 wire [C_NUM_GROUPS*C_LANES*2-1:0] source_local_vc;
 wire [C_NUM_GROUPS*C_LANES-1:0] source_local_pool,source_local_sop,source_local_eop;
 wire [C_NUM_GROUPS*C_LANES*C_POLICY_WIDTH-1:0] source_local_policy;
 wire [C_NUM_GROUPS*C_LANES*C_EPOCH_WIDTH-1:0] source_local_epoch;
 wire [C_NUM_GROUPS*C_LANES*C_COUNT_WIDTH-1:0] source_local_flits;
 wire [8*C_NUM_PLANES-1:0] source_remote_valid,source_remote_ready;
 wire [8*C_NUM_PLANES*C_DATA_WIDTH-1:0] source_remote_data;
 wire [8*C_NUM_PLANES*C_META_WIDTH-1:0] source_remote_meta;
 wire [8*C_NUM_PLANES*3-1:0] source_remote_group,source_remote_src_group;
 wire [8*C_NUM_PLANES*C_TILE_WIDTH-1:0] source_remote_tile;
 wire [8*C_NUM_PLANES*5-1:0] source_remote_port;
 wire [8*C_NUM_PLANES*C_CLASS_WIDTH-1:0] source_remote_class;
 wire [8*C_NUM_PLANES*10-1:0] source_remote_src_port;
 wire [8*C_NUM_PLANES*2-1:0] source_remote_vc;
 wire [8*C_NUM_PLANES-1:0] source_remote_pool,source_remote_sop,source_remote_eop;
 wire [8*C_NUM_PLANES*C_POLICY_WIDTH-1:0] source_remote_policy;
 wire [8*C_NUM_PLANES*C_EPOCH_WIDTH-1:0] source_remote_epoch;
 wire [8*C_NUM_PLANES*C_COUNT_WIDTH-1:0] source_remote_flits;
 wire [C_NUM_GROUPS-1:0] source_quiescent,source_config_error,source_error;
 wire [8*C_NUM_PLANES-1:0] core_route_error,core_protocol_error,core_owner_valid;
 wire source_core_quiescent,source_all_quiescent,source_matrix_config,source_matrix_error;
 reg [C_NUM_PLANES-1:0] plane_enable_q;
 wire [C_NUM_GROUPS*C_LANES*C_NUM_PLANES-1:0] source_plane_path_enable;
 wire [C_NUM_GROUPS*C_LANES-1:0] source_hint_valid,source_hint_sop;
 wire [C_NUM_GROUPS*C_LANES*3-1:0] source_hint_group;
 wire [C_NUM_GROUPS*C_LANES*C_TILE_WIDTH-1:0] source_hint_tile;
 wire [C_NUM_GROUPS*C_LANES*5-1:0] source_hint_port;
 wire [C_NUM_GROUPS*C_LANES*C_CLASS_WIDTH-1:0] source_hint_class;
 wire credit_hint_config_error;

 wire [C_NUM_GROUPS*C_LANES*C_FABRIC_META_WIDTH-1:0] destination_local_meta;
 wire [C_NUM_GROUPS*C_NUM_PLANES*C_FABRIC_META_WIDTH-1:0] destination_core_meta;
 wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] destination_core_ready;
 wire [C_NUM_GROUPS*C_NUM_PLANES*C_PLANE_WIDTH-1:0] destination_core_context;
 wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] advisory_valid;
 wire [C_NUM_GROUPS*C_NUM_PLANES*C_TILE_WIDTH-1:0] advisory_tile;
 wire [C_NUM_GROUPS*C_NUM_PLANES*5-1:0] advisory_port;
 wire [C_NUM_GROUPS*C_NUM_PLANES*C_CLASS_WIDTH-1:0] advisory_class;
 wire [C_NUM_GROUPS*C_EPOCH_WIDTH-1:0] advisory_epoch;
 wire [C_TOTAL_PORTS*C_FABRIC_META_WIDTH-1:0] destination_meta;
 wire [C_TOTAL_PORTS*C_PORT_WIDTH-1:0] destination_compact_global_port;
 wire [C_NUM_GROUPS*C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] credit_free;
 wire [C_NUM_GROUPS*C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] credit_issued,credit_occupied;
 wire [C_NUM_GROUPS-1:0] destination_quiescent,destination_error;
 wire [C_NUM_GROUPS-1:0] destination_return_malformed_event_level;
 wire [C_NUM_GROUPS-1:0] destination_return_duplicate_event_level;
 wire [C_NUM_GROUPS-1:0] destination_return_stale_event_level;
 wire [C_NUM_GROUPS-1:0] destination_return_wrong_port_event_level;
 wire destination_config_error;
 wire supervisor_config_error,supervisor_error,commit_error,body_drain_enable;
 wire credit_nonquiescent=(|credit_issued)||(|credit_occupied);
 reg inactive_group_error_q;
 wire inactive_group_write=i_identity_shadow_write&&i_identity_shadow_active&&
  (C_NUM_GROUPS<8)&&(i_identity_shadow_group>=C_NUM_GROUPS[2:0]);
 // Source matrix当前仅汇总导出shadow/RAS错误；任何此类错误均阻止active image切换。
 wire shadow_or_config_illegal=i_shadow_illegal||inactive_group_error_q||(|source_error)||source_matrix_config||
  destination_config_error||!CONFIG_LEGAL;

 always @(posedge i_clk) begin
  if(!i_rstn) begin
   plane_enable_q<={C_NUM_PLANES{1'b0}};
   inactive_group_error_q<=1'b0;
  end else begin
   plane_enable_q<=i_plane_enable;
   if(inactive_group_write)inactive_group_error_q<=1'b1;
  end
 end
 assign o_inactive_group_error=inactive_group_error_q;
 genvar group_index,lane_index,plane_index,port_index;

 switch_source_core_matrix #(
  .C_NUM_SOURCE_GROUPS(C_NUM_GROUPS),.C_TILES_PER_GROUP(C_TILES_PER_GROUP),
  .C_INGRESS_PER_TILE(C_INGRESS_PER_TILE),.C_BANKS_PER_TILE(C_BANKS_PER_TILE),
  .C_NUM_PLANES(C_NUM_PLANES),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VOQS(C_NUM_VOQS),
  .C_QUEUE_DEPTH(C_QUEUE_DEPTH),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),
  .C_DST_ID_WIDTH(C_DST_ID_WIDTH),.C_DST_COUNT(C_DST_COUNT),.C_PORT_WIDTH(C_PORT_WIDTH),
  .C_PORT_COUNT(C_PORT_COUNT),.C_QUEUE_WIDTH(C_QUEUE_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),
  .C_INGRESS_WIDTH(C_INGRESS_WIDTH),.C_BANK_WIDTH(C_BANK_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),
  .C_ADDR_WIDTH(C_ADDR_WIDTH),.C_POLICY_WIDTH(C_POLICY_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
  .C_PORTS_PER_TILE(C_PORTS_PER_TILE),.C_TILE_WIDTH(C_TILE_WIDTH),.C_SOURCE_WIDTH(C_SOURCE_WIDTH))u_source_core(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(i_valid),.o_ready(o_ready),
  .i_committed(i_committed),.i_data(i_data),.i_meta(i_meta),.i_dst_id(i_dst_id),.i_class(i_class),
  .i_src_port(i_src_port),.i_vc(i_vc),.i_pool(i_pool),.i_sop(i_sop),.i_eop(i_eop),
  .i_packet_flits(i_packet_flits),.i_route_shadow_write(i_route_shadow_write),
  .i_route_shadow_dst_id(i_route_shadow_dst_id),.i_route_shadow_valid(i_route_shadow_valid),
  .i_route_shadow_global_port(i_route_shadow_global_port),.i_route_shadow_policy(i_route_shadow_policy),
  .i_identity_shadow_write(i_identity_shadow_write),.i_identity_shadow_global_port(i_identity_shadow_global_port),
  .i_identity_shadow_active(i_identity_shadow_active),.i_identity_shadow_group(i_identity_shadow_group),
  .i_identity_shadow_tile(i_identity_shadow_tile),.i_identity_shadow_local_port(i_identity_shadow_local_port),
  .i_identity_shadow_station(i_identity_shadow_station),.i_identity_shadow_lane_mask(i_identity_shadow_lane_mask),
  .i_identity_shadow_service_units(i_identity_shadow_service_units),.i_station_active_mode(i_station_active_mode),
  .i_external_commit_pulse(o_commit_pulse),.i_external_active_epoch(o_active_epoch),
  .i_external_admission_enable(o_new_sop_admission),.i_external_quiesce_request(o_quiesce_request),
  .i_external_commit_pending(o_commit_pending),.i_plane_eligible(source_plane_path_enable),
  .o_hint_source_valid(source_hint_valid),.o_hint_source_sop(source_hint_sop),
  .o_hint_source_dst_group(source_hint_group),.o_hint_source_dst_tile(source_hint_tile),
  .o_hint_source_dst_port(source_hint_port),.o_hint_source_class(source_hint_class),
  .o_local_valid(source_local_valid),.i_local_ready(source_local_ready),.o_local_data(source_local_data),
  .o_local_meta(source_local_meta),.o_local_dst_group(source_local_group),.o_local_dst_tile(source_local_tile),
  .o_local_dst_port(source_local_port),.o_local_class(source_local_class),
  .o_local_src_port(source_local_src_port),.o_local_vc(source_local_vc),.o_local_pool(source_local_pool),
  .o_local_route_policy(source_local_policy),.o_local_route_epoch(source_local_epoch),
  .o_local_packet_flits(source_local_flits),.o_local_sop(source_local_sop),.o_local_eop(source_local_eop),
  .o_remote_valid(source_remote_valid),.i_remote_ready(source_remote_ready),.o_remote_data(source_remote_data),
  .o_remote_meta(source_remote_meta),.o_remote_dst_group(source_remote_group),.o_remote_dst_tile(source_remote_tile),
  .o_remote_dst_port(source_remote_port),.o_remote_class(source_remote_class),
  .o_remote_src_group(source_remote_src_group),.o_remote_src_port(source_remote_src_port),
  .o_remote_vc(source_remote_vc),.o_remote_pool(source_remote_pool),
  .o_remote_route_policy(source_remote_policy),.o_remote_route_epoch(source_remote_epoch),
  .o_remote_packet_flits(source_remote_flits),.o_remote_sop(source_remote_sop),.o_remote_eop(source_remote_eop),
  .o_source_quiescent(source_quiescent),.o_source_config_error(source_config_error),
  .o_source_error(source_error),.o_core_route_error(core_route_error),
  .o_core_protocol_error(core_protocol_error),.o_core_owner_valid(core_owner_valid),
  .o_queue_overflow_event_level(o_ingress_queue_overflow_event_level),
  .o_queue_underflow_event_level(o_ingress_queue_underflow_event_level),
  .o_occupancy(o_queue_occupancy),
  .o_core_quiescent(source_core_quiescent),.o_quiescent(source_all_quiescent),
  .o_config_error(source_matrix_config),.o_error(source_matrix_error));

 // 同域V1组合；i_record_*是后续替换为async FIFO的明确边界。
 switch_source_credit_hint_fabric #(
  .C_NUM_SOURCE_GROUPS(C_NUM_GROUPS),.C_SOURCES_PER_GROUP(C_LANES),.C_NUM_PLANES(C_NUM_PLANES),
  .C_TILES(C_TILES_PER_GROUP),.C_PORTS_PER_TILE(C_PORTS_PER_TILE),.C_NUM_CLASSES(C_NUM_CLASSES),
  .C_NUM_RESOURCES(C_RESOURCES),.C_COUNT_WIDTH(C_CREDIT_COUNT_WIDTH),.C_TILE_WIDTH(C_TILE_WIDTH),
  .C_CLASS_WIDTH(C_CLASS_WIDTH),.C_PLANE_WIDTH(C_PLANE_WIDTH),.C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),
  .C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_SEQUENCE_WIDTH(C_HINT_SEQUENCE_WIDTH),.C_TIME_WIDTH(C_HINT_TIME_WIDTH),
  .C_TTL_CYCLES(C_HINT_TTL_CYCLES),.C_REFRESH_CYCLES(C_HINT_REFRESH_CYCLES))u_credit_hints(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_source_valid(source_hint_valid),
  .i_source_sop(source_hint_sop),.i_source_dst_group(source_hint_group),.i_source_dst_tile(source_hint_tile),
  .i_source_dst_port(source_hint_port),.i_source_class(source_hint_class),.i_plane_enable(plane_enable_q),
  .i_epoch(o_active_epoch),.i_effective_free(o_effective_free),
  .i_record_forward_enable(!o_quiesce_request),.i_record_sink_enable(1'b1),
  .o_plane_eligible(source_plane_path_enable),.o_using_hint(o_source_hint_used),
  .o_probe_path(o_source_probe_path),.o_group_pending(o_credit_hint_pending),
  .o_group_error(o_credit_hint_error),.o_config_error(credit_hint_config_error));
 assign o_source_hint_eligible=source_plane_path_enable;

 // Source local与remote sideband统一装入opaque meta，直到最终Port再无损解包。
 generate
  for(group_index=0;group_index<C_NUM_GROUPS;group_index=group_index+1)begin:g_meta_group
   for(lane_index=0;lane_index<C_LANES;lane_index=lane_index+1)begin:g_local_meta
    localparam integer LOCAL_INDEX=group_index*C_LANES+lane_index;
    assign destination_local_meta[LOCAL_INDEX*C_FABRIC_META_WIDTH+:C_FABRIC_META_WIDTH]={
     source_local_epoch[LOCAL_INDEX*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
     source_local_policy[LOCAL_INDEX*C_POLICY_WIDTH+:C_POLICY_WIDTH],
     source_local_flits[LOCAL_INDEX*C_COUNT_WIDTH+:C_COUNT_WIDTH],group_index[2:0],
     source_local_src_port[LOCAL_INDEX*10+:10],source_local_meta[LOCAL_INDEX*C_META_WIDTH+:C_META_WIDTH]};
   end
   for(plane_index=0;plane_index<C_NUM_PLANES;plane_index=plane_index+1)begin:g_core_meta
    localparam integer REMOTE_INDEX=group_index*C_NUM_PLANES+plane_index;
    assign destination_core_meta[REMOTE_INDEX*C_FABRIC_META_WIDTH+:C_FABRIC_META_WIDTH]={
     source_remote_epoch[REMOTE_INDEX*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
     source_remote_policy[REMOTE_INDEX*C_POLICY_WIDTH+:C_POLICY_WIDTH],
     source_remote_flits[REMOTE_INDEX*C_COUNT_WIDTH+:C_COUNT_WIDTH],
     source_remote_src_group[REMOTE_INDEX*3+:3],
     source_remote_src_port[REMOTE_INDEX*10+:10],source_remote_meta[REMOTE_INDEX*C_META_WIDTH+:C_META_WIDTH]};
    assign destination_core_context[REMOTE_INDEX*C_PLANE_WIDTH+:C_PLANE_WIDTH]=plane_index[C_PLANE_WIDTH-1:0];
    assign o_advisory_match[REMOTE_INDEX]=advisory_valid[REMOTE_INDEX]&&source_remote_valid[REMOTE_INDEX]&&
     !o_advisory_stale[REMOTE_INDEX]&&
     (advisory_tile[REMOTE_INDEX*C_TILE_WIDTH+:C_TILE_WIDTH]==source_remote_tile[REMOTE_INDEX*C_TILE_WIDTH+:C_TILE_WIDTH])&&
     (advisory_port[REMOTE_INDEX*5+:5]==source_remote_port[REMOTE_INDEX*5+:5])&&
     (advisory_class[REMOTE_INDEX*C_CLASS_WIDTH+:C_CLASS_WIDTH]==source_remote_class[REMOTE_INDEX*C_CLASS_WIDTH+:C_CLASS_WIDTH]);
    assign o_advisory_stale[REMOTE_INDEX]=advisory_valid[REMOTE_INDEX]&&
     (advisory_epoch[group_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]!=o_active_epoch);
    assign o_advisory_mismatch[REMOTE_INDEX]=advisory_valid[REMOTE_INDEX]&&source_remote_valid[REMOTE_INDEX]&&
     !o_advisory_match[REMOTE_INDEX];
   end
  end
 endgenerate
 assign o_advisory_valid=advisory_valid;
 assign source_remote_ready={{((8-C_NUM_GROUPS)*C_NUM_PLANES){1'b0}},destination_core_ready};

 switch_destination_pipeline #(
  .C_NUM_GROUPS(C_NUM_GROUPS),.C_PLANES(C_NUM_PLANES),.C_TILES(C_TILES_PER_GROUP),
  .C_BANK_LANES(C_BANKS_PER_TILE),.C_PORTS_PER_TILE(C_PORTS_PER_TILE),
  .C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_FABRIC_META_WIDTH),.C_TILE_WIDTH(C_TILE_WIDTH),
  .C_CLASS_WIDTH(C_CLASS_WIDTH),.C_VC_WIDTH(2),.C_COUNT_WIDTH(C_COUNT_WIDTH),
  .C_CORE_CONTEXT_WIDTH(C_PLANE_WIDTH),.C_PLANE_WIDTH(C_PLANE_WIDTH),.C_OWNER_WIDTH(C_OWNER_WIDTH),
  .C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
  .C_GENERATION_WIDTH(C_GENERATION_WIDTH),.C_SLOT_WIDTH(C_SLOT_WIDTH),
  .C_BANK_SLOT_WIDTH(C_BANK_SLOT_WIDTH),.C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_TOKEN_WIDTH(C_TOKEN_WIDTH),
  .C_CREDIT_COUNT_WIDTH(C_CREDIT_COUNT_WIDTH),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VC(C_NUM_VC),
  .C_CAPACITY(C_CREDIT_CAPACITY),.C_QUEUE_DEPTH(C_EGRESS_QUEUE_DEPTH),
  .C_QUEUE_COUNT_WIDTH(C_EGRESS_COUNT_WIDTH),.C_GLOBAL_PORT_WIDTH(C_PORT_WIDTH),
  .C_LANES(C_LANES),.C_REQUESTERS(C_REQUESTERS),.C_RESOURCES(C_RESOURCES),
  .C_ACCOUNTS(C_ACCOUNTS),.C_RELEASE_PORTS(C_RELEASE_PORTS),.C_TOTAL_PORTS(C_TOTAL_PORTS),
  .C_TOTAL_TILES(C_NUM_GROUPS*C_TILES_PER_GROUP))u_destination(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_epoch(o_active_epoch),
  .i_local_valid(source_local_valid),.o_local_ready(source_local_ready),.i_local_data(source_local_data),
  .i_local_meta(destination_local_meta),.i_local_dst_group(source_local_group),
  .i_local_dst_tile(source_local_tile),.i_local_dst_port(source_local_port),.i_local_class(source_local_class),
  .i_local_original_vc(source_local_vc),.i_local_pool(source_local_pool),
  .i_local_packet_flits(source_local_flits),.i_local_sop(source_local_sop),.i_local_eop(source_local_eop),
  .i_core_valid(source_remote_valid[C_NUM_GROUPS*C_NUM_PLANES-1:0]),.o_core_ready(destination_core_ready),
  .i_core_data(source_remote_data[C_NUM_GROUPS*C_NUM_PLANES*C_DATA_WIDTH-1:0]),
  .i_core_meta(destination_core_meta),
  .i_core_dst_group(source_remote_group[C_NUM_GROUPS*C_NUM_PLANES*3-1:0]),
  .i_core_dst_tile(source_remote_tile[C_NUM_GROUPS*C_NUM_PLANES*C_TILE_WIDTH-1:0]),
  .i_core_dst_port(source_remote_port[C_NUM_GROUPS*C_NUM_PLANES*5-1:0]),
  .i_core_class(source_remote_class[C_NUM_GROUPS*C_NUM_PLANES*C_CLASS_WIDTH-1:0]),
  .i_core_packet_flits(source_remote_flits[C_NUM_GROUPS*C_NUM_PLANES*C_COUNT_WIDTH-1:0]),
  .i_core_context(destination_core_context),
  .i_core_original_vc(source_remote_vc[C_NUM_GROUPS*C_NUM_PLANES*2-1:0]),
  .i_core_pool(source_remote_pool[C_NUM_GROUPS*C_NUM_PLANES-1:0]),
  .i_core_sop(source_remote_sop[C_NUM_GROUPS*C_NUM_PLANES-1:0]),
  .i_core_eop(source_remote_eop[C_NUM_GROUPS*C_NUM_PLANES-1:0]),
  .o_core_registered_eligibility(advisory_valid),.o_core_eligibility_dst_tile(advisory_tile),
  .o_core_eligibility_dst_port(advisory_port),.o_core_eligibility_class(advisory_class),
  .o_core_eligibility_epoch(advisory_epoch),.i_port_active(i_port_active),.i_upli_credit(i_upli_credit),
  .i_tl_credit(i_tl_credit),.i_link_up(i_link_up),.o_head_valid(o_head_valid),.o_valid(o_valid),.i_ready(i_ready),
  .o_data(o_data),.o_meta(destination_meta),.o_class(o_class),.o_original_vc(o_original_vc),
  .o_pool(o_pool),.o_sop(o_sop),.o_eop(o_eop),.o_global_port_id(destination_compact_global_port),
  .i_release_path_enable(i_release_path_enable),.o_release_valid(o_release_valid),
  .o_release_ready(o_release_ready),.o_release_account(o_release_account),.o_release_token(o_release_token),
 .o_free(credit_free),.o_effective_free(o_effective_free),.o_issued(credit_issued),.o_occupied(credit_occupied),
  .o_group_quiescent(destination_quiescent),.o_group_error(destination_error),
  .o_return_malformed_event_level(destination_return_malformed_event_level),
  .o_return_duplicate_event_level(destination_return_duplicate_event_level),
  .o_return_stale_event_level(destination_return_stale_event_level),
  .o_return_wrong_port_event_level(destination_return_wrong_port_event_level),
 .o_config_error(destination_config_error));
 assign o_credit_issued=credit_issued;
 assign o_credit_occupied=credit_occupied;
 assign o_destination_return_error_event_level={|destination_return_wrong_port_event_level,
  |destination_return_stale_event_level,|destination_return_duplicate_event_level,
  |destination_return_malformed_event_level};

 generate for(port_index=0;port_index<C_TOTAL_PORTS;port_index=port_index+1)begin:g_output_meta
  localparam integer OUTPUT_GROUP=port_index/C_RELEASE_PORTS;
  localparam integer OUTPUT_GROUP_LOCAL=port_index%C_RELEASE_PORTS;
  localparam integer OUTPUT_TILE=OUTPUT_GROUP_LOCAL/C_PORTS_PER_TILE;
  localparam integer OUTPUT_LOCAL_PORT=OUTPUT_GROUP_LOCAL%C_PORTS_PER_TILE;
  // 端口vector可按缩小profile紧凑展开，但协议GlobalPortID始终保持3b Group/2b Tile/5b local稳定编码。
  assign o_global_port_id[port_index*C_PORT_WIDTH+:C_PORT_WIDTH]=
   {OUTPUT_GROUP[2:0],OUTPUT_TILE[1:0],OUTPUT_LOCAL_PORT[4:0]};
  assign {o_route_epoch[port_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
   o_route_policy[port_index*C_POLICY_WIDTH+:C_POLICY_WIDTH],
   o_packet_flits[port_index*C_COUNT_WIDTH+:C_COUNT_WIDTH],o_src_group[port_index*3+:3],
   o_src_port[port_index*10+:10],o_meta[port_index*C_META_WIDTH+:C_META_WIDTH]}=
   destination_meta[port_index*C_FABRIC_META_WIDTH+:C_FABRIC_META_WIDTH];
 end endgenerate

 switch_fabric_quiesce_commit_supervisor #(
  .C_FRONTEND_COMPONENTS(C_NUM_GROUPS),.C_SOURCE_TILE_COMPONENTS(C_NUM_GROUPS),
  .C_GROUP_CORE_COMPONENTS(1),.C_DESTINATION_COMPONENTS(C_NUM_GROUPS),
  .C_CREDIT_COMPONENTS(1),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
  .C_TIMEOUT_CYCLES(C_TIMEOUT_CYCLES),.C_TIMEOUT_WIDTH(C_TIMEOUT_WIDTH))u_commit_supervisor(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_commit_request(i_route_commit_request),
  .i_shadow_illegal(shadow_or_config_illegal),.i_frontend_busy(~source_quiescent),
  .i_source_tile_busy(~source_quiescent),.i_group_core_busy(~source_core_quiescent),
  .i_destination_busy(~destination_quiescent),
  // credit hint是无所有权的后台优化流；route epoch负责隔离commit前的旧提示。
  .i_credit_nonquiescent(credit_nonquiescent),
  .o_new_sop_admission(o_new_sop_admission),.o_body_drain_enable(body_drain_enable),
  .o_quiesce_request(o_quiesce_request),.o_commit_pulse(o_commit_pulse),.o_pending(o_commit_pending),
  .o_all_empty(o_all_empty),.o_epoch(o_active_epoch),.o_wait_cycles(o_commit_wait_cycles),
  .o_timeout_error(o_timeout_error),.o_commit_error(commit_error),
  .o_config_error(supervisor_config_error),.o_error(supervisor_error));

 assign o_config_error=!CONFIG_LEGAL||source_matrix_config||destination_config_error||credit_hint_config_error||supervisor_config_error;
 assign o_error=o_config_error||inactive_group_error_q||source_matrix_error||(|destination_error)||
  (|o_credit_hint_error)||supervisor_error||
  (|core_route_error)||(|core_protocol_error)||(unused_status&1'b0);
 wire unused_status=^{1'b0,source_local_src_port,core_owner_valid,source_all_quiescent,
  body_drain_enable,commit_error,credit_free,source_config_error,source_error,
  source_remote_data,source_remote_meta,source_remote_group,source_remote_src_group,
  source_remote_tile,source_remote_port,source_remote_class,source_remote_src_port,
  source_remote_vc,source_remote_pool,source_remote_sop,source_remote_eop,
  source_remote_policy,source_remote_epoch,source_remote_flits,destination_compact_global_port,1'b0};
endmodule
`default_nettype wire
