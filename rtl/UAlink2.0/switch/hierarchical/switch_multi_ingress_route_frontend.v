`timescale 1ns/1ps
`default_nettype none
// 共享Route/identity active image的多入口包级前端；只接纳已经commit的内部flit。
// 每路拥有独立packet owner和一拍输出弹性槽，输出ABI可直接连接switch_tile_multi_ingress。
// LOOKUP_PORTS描述逻辑多读口；综合后采用物理复制或bank化仍待目标SRAM宏与时序流程决定。
module switch_multi_ingress_route_frontend #(
 parameter integer C_INGRESS_PORTS=32,parameter integer C_DATA_WIDTH=512,parameter integer C_META_WIDTH=32,
 parameter integer C_DST_ID_WIDTH=12,parameter integer C_DST_COUNT=4096,
 parameter integer C_PORT_WIDTH=10,parameter integer C_PORT_COUNT=1024,
 parameter integer C_CLASS_WIDTH=1,parameter integer C_COUNT_WIDTH=4,
 parameter integer C_POLICY_WIDTH=8,parameter integer C_EPOCH_WIDTH=8,
 parameter integer C_NUM_GROUPS=8,parameter integer C_TILES_PER_GROUP=4,parameter integer C_PORTS_PER_TILE=32,
 parameter integer C_EXTERNAL_COMMIT=0 // 置1时由全Fabric supervisor唯一持有pending/epoch并直接切换双表。
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_INGRESS_PORTS-1:0] i_valid,output wire [C_INGRESS_PORTS-1:0] o_ready,
 input wire [C_INGRESS_PORTS-1:0] i_committed,
 input wire [C_INGRESS_PORTS*C_DATA_WIDTH-1:0] i_data,
 input wire [C_INGRESS_PORTS*C_META_WIDTH-1:0] i_meta,
 input wire [C_INGRESS_PORTS*C_DST_ID_WIDTH-1:0] i_dst_id,
 input wire [C_INGRESS_PORTS*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_INGRESS_PORTS*10-1:0] i_src_port,input wire [C_INGRESS_PORTS*2-1:0] i_vc,
 input wire [C_INGRESS_PORTS-1:0] i_pool,input wire [C_INGRESS_PORTS-1:0] i_sop,input wire [C_INGRESS_PORTS-1:0] i_eop,
 input wire [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
 output wire [C_INGRESS_PORTS-1:0] o_valid,input wire [C_INGRESS_PORTS-1:0] i_ready,
 output wire [C_INGRESS_PORTS*C_DATA_WIDTH-1:0] o_data,
 output wire [C_INGRESS_PORTS*C_META_WIDTH-1:0] o_meta,
 output wire [C_INGRESS_PORTS*3-1:0] o_dst_group,output wire [C_INGRESS_PORTS*2-1:0] o_dst_tile,
 output wire [C_INGRESS_PORTS*5-1:0] o_dst_port,
 output wire [C_INGRESS_PORTS*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_INGRESS_PORTS*10-1:0] o_src_port,output wire [C_INGRESS_PORTS*2-1:0] o_vc,
 output wire [C_INGRESS_PORTS-1:0] o_pool,
 output wire [C_INGRESS_PORTS*C_POLICY_WIDTH-1:0] o_route_policy,
 output wire [C_INGRESS_PORTS*C_EPOCH_WIDTH-1:0] o_route_epoch,
 output wire [C_INGRESS_PORTS-1:0] o_sop,output wire [C_INGRESS_PORTS-1:0] o_eop,
 output wire [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] o_packet_flits,
 input wire i_route_shadow_write,input wire [C_DST_ID_WIDTH-1:0] i_route_shadow_dst_id,
 input wire i_route_shadow_valid,input wire [C_PORT_WIDTH-1:0] i_route_shadow_global_port,
 input wire [C_POLICY_WIDTH-1:0] i_route_shadow_policy,
 input wire i_identity_shadow_write,input wire [C_PORT_WIDTH-1:0] i_identity_shadow_global_port,
 input wire i_identity_shadow_active,input wire [2:0] i_identity_shadow_group,input wire [1:0] i_identity_shadow_tile,
 input wire [4:0] i_identity_shadow_local_port,input wire [7:0] i_identity_shadow_station,
 input wire [3:0] i_identity_shadow_lane_mask,input wire [2:0] i_identity_shadow_service_units,
 input wire [1:0] i_station_active_mode,input wire i_commit_request,
 input wire i_external_commit_pulse, // external模式下同沿原子切换Route与Identity active bank。
 input wire [C_EPOCH_WIDTH-1:0] i_external_active_epoch, // external supervisor持有的唯一active epoch。
 input wire i_external_admission_enable, // external模式下全Fabric排空期间禁止新SOP。
 input wire i_external_quiesce_request,input wire i_external_commit_pending, // external CSR状态透传。
 output wire o_admission_enable,output wire o_quiesce_request,output wire o_commit_pending,
 output wire [C_EPOCH_WIDTH-1:0] o_active_epoch,output wire o_quiescent,
 output wire o_active_route_bank,output wire o_active_identity_bank,
 output wire o_commit_error,output wire o_route_error,output wire o_shadow_illegal
);
 localparam CONFIG_LEGAL=(C_INGRESS_PORTS>=1)&&(C_INGRESS_PORTS<=32)&&(C_DST_ID_WIDTH>=1)&&(C_DST_ID_WIDTH<=16)&&
  (C_PORT_WIDTH>=1)&&(C_PORT_WIDTH<=10)&&(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&
  (C_TILES_PER_GROUP>=1)&&(C_TILES_PER_GROUP<=4)&&(C_PORTS_PER_TILE>=1)&&(C_PORTS_PER_TILE<=32)&&
  ((C_EXTERNAL_COMMIT==0)||(C_EXTERNAL_COMMIT==1));
 localparam [2:0] C_NUM_GROUPS_VALUE=C_NUM_GROUPS[2:0];
 localparam [1:0] C_TILES_PER_GROUP_VALUE=C_TILES_PER_GROUP[1:0];
 localparam [0:0] EXTERNAL_COMMIT_ENABLED=(C_EXTERNAL_COMMIT==1); // 收窄模式常量，消除integer参与逻辑门控的宽度歧义。
 wire [C_INGRESS_PORTS-1:0] table_route_valid,table_identity_active,coordinate_legal,input_legal,input_accept;
 wire [C_INGRESS_PORTS*C_PORT_WIDTH-1:0] table_global_port;
 wire [C_INGRESS_PORTS*C_POLICY_WIDTH-1:0] table_policy;
 wire [C_INGRESS_PORTS*3-1:0] table_group;wire [C_INGRESS_PORTS*2-1:0] table_tile;
 wire [C_INGRESS_PORTS*5-1:0] table_local_port;
 wire shadow_illegal,identity_illegal_error,commit_pulse;
 wire internal_admission_enable,internal_quiesce_request,internal_commit_pending,internal_commit_pulse;
 wire [C_EPOCH_WIDTH-1:0] internal_active_epoch;wire internal_commit_error;
 reg [C_INGRESS_PORTS-1:0] owner_valid_q,output_valid_q;
 reg [C_INGRESS_PORTS*C_DST_ID_WIDTH-1:0] owner_dst_q;
 reg [C_INGRESS_PORTS*3-1:0] owner_group_q,output_group_q;
 reg [C_INGRESS_PORTS*2-1:0] owner_tile_q,output_tile_q,output_vc_q;
 reg [C_INGRESS_PORTS*5-1:0] owner_port_q,output_port_q;
 reg [C_INGRESS_PORTS*C_CLASS_WIDTH-1:0] owner_class_q,output_class_q;
 reg [C_INGRESS_PORTS*C_POLICY_WIDTH-1:0] owner_policy_q,output_policy_q;
 reg [C_INGRESS_PORTS*C_EPOCH_WIDTH-1:0] owner_epoch_q,output_epoch_q;
 reg [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] owner_flits_q,output_flits_q;
 reg [C_INGRESS_PORTS*C_DATA_WIDTH-1:0] output_data_q;
 reg [C_INGRESS_PORTS*C_META_WIDTH-1:0] output_meta_q;
 reg [C_INGRESS_PORTS*10-1:0] output_src_q;reg [C_INGRESS_PORTS-1:0] output_pool_q,output_sop_q,output_eop_q;
 reg route_error_q;integer lane;
 genvar g;
 generate for(g=0;g<C_INGRESS_PORTS;g=g+1)begin:g_lane
  wire group_legal,tile_legal;
  if(C_NUM_GROUPS==8)begin:g_all_groups assign group_legal=1'b1;end
  else begin:g_limited_groups assign group_legal=table_group[g*3+:3]<C_NUM_GROUPS_VALUE;end
  if(C_TILES_PER_GROUP==4)begin:g_all_tiles assign tile_legal=1'b1;end
  else begin:g_limited_tiles assign tile_legal=table_tile[g*2+:2]<C_TILES_PER_GROUP_VALUE;end
  assign coordinate_legal[g]=group_legal&&tile_legal;
  assign input_legal[g]=CONFIG_LEGAL&&i_committed[g]&&
   (owner_valid_q[g]?(!i_sop[g]&&(i_dst_id[g*C_DST_ID_WIDTH+:C_DST_ID_WIDTH]==owner_dst_q[g*C_DST_ID_WIDTH+:C_DST_ID_WIDTH])):
    (i_sop[g]&&o_admission_enable&&table_route_valid[g]&&table_identity_active[g]&&coordinate_legal[g]));
  assign o_ready[g]=i_rstn&&input_legal[g]&&(!output_valid_q[g]||i_ready[g]);
  assign input_accept[g]=i_valid[g]&&o_ready[g];
 end endgenerate
 assign o_valid=output_valid_q;assign o_data=output_data_q;assign o_meta=output_meta_q;
 assign o_dst_group=output_group_q;assign o_dst_tile=output_tile_q;assign o_dst_port=output_port_q;
 assign o_class=output_class_q;assign o_src_port=output_src_q;assign o_vc=output_vc_q;assign o_pool=output_pool_q;
 assign o_route_policy=output_policy_q;assign o_route_epoch=output_epoch_q;
 assign o_sop=output_sop_q;assign o_eop=output_eop_q;assign o_packet_flits=output_flits_q;
 assign o_quiescent=(owner_valid_q=={C_INGRESS_PORTS{1'b0}})&&(output_valid_q=={C_INGRESS_PORTS{1'b0}});
 assign o_route_error=!CONFIG_LEGAL|identity_illegal_error|route_error_q;
 assign o_shadow_illegal=shadow_illegal; // external supervisor据此禁止非法shadow原子切换。
 assign commit_pulse=EXTERNAL_COMMIT_ENABLED?i_external_commit_pulse:internal_commit_pulse;
 assign o_active_epoch=EXTERNAL_COMMIT_ENABLED?i_external_active_epoch:internal_active_epoch;
 assign o_admission_enable=EXTERNAL_COMMIT_ENABLED?i_external_admission_enable:internal_admission_enable;
 assign o_quiesce_request=EXTERNAL_COMMIT_ENABLED?i_external_quiesce_request:internal_quiesce_request;
 assign o_commit_pending=EXTERNAL_COMMIT_ENABLED?i_external_commit_pending:internal_commit_pending;
 assign o_commit_error=EXTERNAL_COMMIT_ENABLED?1'b0:internal_commit_error;
 switch_route_commit #(.EPOCH_WIDTH(C_EPOCH_WIDTH)) u_commit(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL&&!EXTERNAL_COMMIT_ENABLED),
  .i_commit_request(i_commit_request&&!EXTERNAL_COMMIT_ENABLED),.i_inflight_empty(o_quiescent),
  .i_shadow_illegal(shadow_illegal),.o_admission_enable(internal_admission_enable),
  .o_quiesce_request(internal_quiesce_request),.o_commit_pulse(internal_commit_pulse),
  .o_pending(internal_commit_pending),.o_epoch(internal_active_epoch),.o_commit_error(internal_commit_error));
 /* verilator lint_off PINCONNECTEMPTY */
 switch_route_sram #(.DST_ID_WIDTH(C_DST_ID_WIDTH),.DST_COUNT(C_DST_COUNT),.PORT_WIDTH(C_PORT_WIDTH),
  .POLICY_WIDTH(C_POLICY_WIDTH),.EPOCH_WIDTH(C_EPOCH_WIDTH),.LOOKUP_PORTS(C_INGRESS_PORTS)) u_route(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_shadow_write(i_route_shadow_write),.i_shadow_dst_id(i_route_shadow_dst_id),
  .i_shadow_valid(i_route_shadow_valid),.i_shadow_global_port(i_route_shadow_global_port),.i_shadow_policy(i_route_shadow_policy),
  .i_commit(commit_pulse),.i_route_epoch(o_active_epoch),.i_lookup_dst_id({C_DST_ID_WIDTH{1'b0}}),
  .i_packet_sop(1'b0),.i_packet_eop(1'b0),.i_packet_accept(1'b0),.o_lookup_valid(),
  .o_lookup_global_port(),.o_lookup_policy(),.o_lookup_epoch(),
  .o_packet_active(),.o_active_bank(o_active_route_bank),.i_lookup_dst_id_vec(i_dst_id),
  .o_lookup_valid_vec(table_route_valid),.o_lookup_global_port_vec(table_global_port),.o_lookup_policy_vec(table_policy));
 switch_port_identity_table #(.PORT_WIDTH(C_PORT_WIDTH),.PORT_COUNT(C_PORT_COUNT),.LOOKUP_PORTS(C_INGRESS_PORTS),
  .NUM_GROUPS(C_NUM_GROUPS),.TILES_PER_GROUP(C_TILES_PER_GROUP),.PORTS_PER_TILE(C_PORTS_PER_TILE)) u_identity(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_shadow_write(i_identity_shadow_write),
  .i_shadow_global_port(i_identity_shadow_global_port),.i_shadow_active(i_identity_shadow_active),
  .i_shadow_group(i_identity_shadow_group),.i_shadow_tile(i_identity_shadow_tile),.i_shadow_local_port(i_identity_shadow_local_port),
  .i_shadow_station(i_identity_shadow_station),.i_shadow_lane_mask(i_identity_shadow_lane_mask),
  .i_shadow_service_units(i_identity_shadow_service_units),.i_station_active_mode(i_station_active_mode),.i_commit(commit_pulse),
  .i_lookup_global_port({C_PORT_WIDTH{1'b0}}),.o_lookup_active(),.o_lookup_group(),
  .o_lookup_tile(),.o_lookup_local_port(),.o_lookup_station(),
  .o_lookup_lane_mask(),.o_lookup_service_units(),.o_active_bitmap(),
  .o_shadow_illegal(shadow_illegal),.o_illegal_map_error(identity_illegal_error),.o_active_bank(o_active_identity_bank),
  .i_lookup_global_port_vec(table_global_port),.o_lookup_active_vec(table_identity_active),
  .o_lookup_group_vec(table_group),.o_lookup_tile_vec(table_tile),.o_lookup_local_port_vec(table_local_port));
 /* verilator lint_on PINCONNECTEMPTY */
 always @(posedge i_clk)begin
  if(!i_rstn)begin owner_valid_q<={C_INGRESS_PORTS{1'b0}};output_valid_q<={C_INGRESS_PORTS{1'b0}};route_error_q<=1'b0;
   owner_dst_q<=0;owner_group_q<=0;owner_tile_q<=0;owner_port_q<=0;owner_class_q<=0;owner_policy_q<=0;owner_epoch_q<=0;owner_flits_q<=0;
   output_data_q<=0;output_meta_q<=0;output_group_q<=0;output_tile_q<=0;output_port_q<=0;output_class_q<=0;
   output_src_q<=0;output_vc_q<=0;output_pool_q<=0;output_policy_q<=0;output_epoch_q<=0;output_sop_q<=0;output_eop_q<=0;output_flits_q<=0;end
  else begin
   if(!CONFIG_LEGAL)route_error_q<=1'b1;
   for(lane=0;lane<C_INGRESS_PORTS;lane=lane+1)begin
    // 合法SOP在全Fabric quiesce期间可以保持valid等待，纯粹的admission反压不得误记Route错误。
    // 已有owner的坏body，或开放准入时的未commit/miss/inactive/坏SOP仍必须fail-closed并诊断。
    if(i_valid[lane]&&!input_legal[lane]&&(owner_valid_q[lane]||o_admission_enable))route_error_q<=1'b1;
    if(output_valid_q[lane]&&i_ready[lane]&&!input_accept[lane])output_valid_q[lane]<=1'b0;
    if(input_accept[lane])begin
     output_valid_q[lane]<=1'b1;output_data_q[lane*C_DATA_WIDTH+:C_DATA_WIDTH]<=i_data[lane*C_DATA_WIDTH+:C_DATA_WIDTH];
     output_meta_q[lane*C_META_WIDTH+:C_META_WIDTH]<=i_meta[lane*C_META_WIDTH+:C_META_WIDTH];
     output_src_q[lane*10+:10]<=i_src_port[lane*10+:10];output_vc_q[lane*2+:2]<=i_vc[lane*2+:2];output_pool_q[lane]<=i_pool[lane];
     output_sop_q[lane]<=i_sop[lane];output_eop_q[lane]<=i_eop[lane];
     if(owner_valid_q[lane])begin output_group_q[lane*3+:3]<=owner_group_q[lane*3+:3];output_tile_q[lane*2+:2]<=owner_tile_q[lane*2+:2];
      output_port_q[lane*5+:5]<=owner_port_q[lane*5+:5];output_class_q[lane*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=owner_class_q[lane*C_CLASS_WIDTH+:C_CLASS_WIDTH];
      output_policy_q[lane*C_POLICY_WIDTH+:C_POLICY_WIDTH]<=owner_policy_q[lane*C_POLICY_WIDTH+:C_POLICY_WIDTH];
      output_epoch_q[lane*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]<=owner_epoch_q[lane*C_EPOCH_WIDTH+:C_EPOCH_WIDTH];
      output_flits_q[lane*C_COUNT_WIDTH+:C_COUNT_WIDTH]<=owner_flits_q[lane*C_COUNT_WIDTH+:C_COUNT_WIDTH];end
     else begin output_group_q[lane*3+:3]<=table_group[lane*3+:3];output_tile_q[lane*2+:2]<=table_tile[lane*2+:2];
      output_port_q[lane*5+:5]<=table_local_port[lane*5+:5];output_class_q[lane*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_class[lane*C_CLASS_WIDTH+:C_CLASS_WIDTH];
      output_policy_q[lane*C_POLICY_WIDTH+:C_POLICY_WIDTH]<=table_policy[lane*C_POLICY_WIDTH+:C_POLICY_WIDTH];
      output_epoch_q[lane*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]<=o_active_epoch;output_flits_q[lane*C_COUNT_WIDTH+:C_COUNT_WIDTH]<=i_packet_flits[lane*C_COUNT_WIDTH+:C_COUNT_WIDTH];
      owner_dst_q[lane*C_DST_ID_WIDTH+:C_DST_ID_WIDTH]<=i_dst_id[lane*C_DST_ID_WIDTH+:C_DST_ID_WIDTH];
      owner_group_q[lane*3+:3]<=table_group[lane*3+:3];owner_tile_q[lane*2+:2]<=table_tile[lane*2+:2];owner_port_q[lane*5+:5]<=table_local_port[lane*5+:5];
      owner_class_q[lane*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_class[lane*C_CLASS_WIDTH+:C_CLASS_WIDTH];owner_policy_q[lane*C_POLICY_WIDTH+:C_POLICY_WIDTH]<=table_policy[lane*C_POLICY_WIDTH+:C_POLICY_WIDTH];
      owner_epoch_q[lane*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]<=o_active_epoch;
      owner_flits_q[lane*C_COUNT_WIDTH+:C_COUNT_WIDTH]<=i_packet_flits[lane*C_COUNT_WIDTH+:C_COUNT_WIDTH];end
     if(!owner_valid_q[lane])owner_valid_q[lane]<=!i_eop[lane];else if(i_eop[lane])owner_valid_q[lane]<=1'b0;
    end
   end
  end
 end
endmodule
`default_nettype wire
