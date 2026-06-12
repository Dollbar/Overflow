`timescale 1ns/1ps
`default_nettype none
// 目的Group信用Fabric：local与Core流量共享唯一目的资源账本，credit后按Tile×bank lane合并。
// 本模块保持每个lane独立；不会把全部Tile流量提前收敛成单一仲裁点。
module switch_destination_group_credit_fabric #(
 parameter integer C_PLANES=32,C_TILES=4,C_BANK_LANES=8,
 parameter integer C_DATA_WIDTH=256,C_META_WIDTH=128,C_TILE_WIDTH=2,C_CLASS_WIDTH=2,C_VC_WIDTH=2,
 parameter integer C_COUNT_WIDTH=5,C_CORE_CONTEXT_WIDTH=5,C_PLANE_WIDTH=5,C_OWNER_WIDTH=6,C_RESOURCE_WIDTH=9,
 parameter integer C_EPOCH_WIDTH=4,C_GENERATION_WIDTH=8,C_SLOT_WIDTH=11,C_BANK_SLOT_WIDTH=2,
 parameter integer C_ACCOUNT_WIDTH=15,C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH,
 parameter integer C_CREDIT_COUNT_WIDTH=3,C_DST_LOCALS=32,C_NUM_CLASSES=4,C_NUM_VC=4,C_CAPACITY=4,
 parameter integer C_NUM_GROUPS=8,C_GROUP_ID=0,
 parameter integer C_LANES=C_TILES*C_BANK_LANES,parameter integer C_REQUESTERS=C_LANES+C_PLANES,
 parameter integer C_RESOURCES=C_TILES*C_DST_LOCALS*C_NUM_CLASSES,
 parameter integer C_ACCOUNTS=C_REQUESTERS*C_RESOURCES,parameter integer C_RELEASE_PORTS=C_TILES*C_DST_LOCALS
)(
 input wire i_clk,input wire i_rstn,input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 input wire [C_LANES-1:0] i_local_valid,output wire [C_LANES-1:0] o_local_ready,
 input wire [C_LANES*C_DATA_WIDTH-1:0] i_local_data,input wire [C_LANES*C_META_WIDTH-1:0] i_local_meta,
 input wire [C_LANES*3-1:0] i_local_dst_group,input wire [C_LANES*C_TILE_WIDTH-1:0] i_local_dst_tile,
 input wire [C_LANES*5-1:0] i_local_dst_port,input wire [C_LANES*C_CLASS_WIDTH-1:0] i_local_class,
 input wire [C_LANES*C_VC_WIDTH-1:0] i_local_original_vc,input wire [C_LANES-1:0] i_local_pool,
 input wire [C_LANES*C_COUNT_WIDTH-1:0] i_local_packet_flits,
 input wire [C_LANES-1:0] i_local_sop,input wire [C_LANES-1:0] i_local_eop,
 input wire [C_PLANES-1:0] i_core_valid,output wire [C_PLANES-1:0] o_core_ready,
 input wire [C_PLANES*C_DATA_WIDTH-1:0] i_core_data,input wire [C_PLANES*C_META_WIDTH-1:0] i_core_meta,
 input wire [C_PLANES*3-1:0] i_core_dst_group,input wire [C_PLANES*C_TILE_WIDTH-1:0] i_core_dst_tile,
 input wire [C_PLANES*5-1:0] i_core_dst_port,input wire [C_PLANES*C_CLASS_WIDTH-1:0] i_core_class,
 input wire [C_PLANES*C_COUNT_WIDTH-1:0] i_core_packet_flits,
 input wire [C_PLANES*C_CORE_CONTEXT_WIDTH-1:0] i_core_context,
 input wire [C_PLANES*C_VC_WIDTH-1:0] i_core_original_vc,input wire [C_PLANES-1:0] i_core_pool,
 input wire [C_PLANES-1:0] i_core_sop,input wire [C_PLANES-1:0] i_core_eop,
 output wire [C_PLANES-1:0] o_core_registered_eligibility,
 output wire [C_PLANES*C_TILE_WIDTH-1:0] o_core_eligibility_dst_tile,
 output wire [C_PLANES*5-1:0] o_core_eligibility_dst_port,
 output wire [C_PLANES*C_CLASS_WIDTH-1:0] o_core_eligibility_class,
 output wire [C_EPOCH_WIDTH-1:0] o_core_eligibility_epoch,
 output wire [C_LANES-1:0] o_valid,input wire [C_LANES-1:0] i_ready,
 output wire [C_LANES*C_DATA_WIDTH-1:0] o_data,output wire [C_LANES*C_META_WIDTH-1:0] o_meta,
 output wire [C_LANES*3-1:0] o_dst_group,output wire [C_LANES*C_TILE_WIDTH-1:0] o_dst_tile,
 output wire [C_LANES*5-1:0] o_dst_port,output wire [C_LANES*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_LANES*C_VC_WIDTH-1:0] o_original_vc,output wire [C_LANES-1:0] o_pool,
 output wire [C_LANES*C_ACCOUNT_WIDTH-1:0] o_account,output wire [C_LANES*C_TOKEN_WIDTH-1:0] o_token,
 output wire [C_LANES-1:0] o_sop,output wire [C_LANES-1:0] o_eop,
 input wire [C_RELEASE_PORTS-1:0] i_release_valid,output wire [C_RELEASE_PORTS-1:0] o_release_ready,
 input wire [C_RELEASE_PORTS*C_TOKEN_WIDTH-1:0] i_release_token,
 output wire [C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] o_free,
 output wire [C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] o_effective_free,
 output wire [C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_issued,
 output wire [C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_occupied,
 output wire o_quiescent,output wire o_error,
 output wire o_return_malformed_event_level,output wire o_return_duplicate_event_level,
 output wire o_return_stale_event_level,output wire o_return_wrong_port_event_level
);
 localparam integer C_PACKED_META=C_META_WIDTH+C_VC_WIDTH+1+C_CORE_CONTEXT_WIDTH+3+C_COUNT_WIDTH;
 localparam integer C_LOCAL_PAYLOAD=C_DATA_WIDTH+C_PACKED_META+C_TILE_WIDTH+5+C_CLASS_WIDTH+2;
 wire [C_LANES-1:0] local_pre_valid,local_pre_ready,local_input_ready,local_slice_idle,local_slice_cfg,local_slice_err;
 wire [C_LANES*C_DATA_WIDTH-1:0] local_data;wire [C_LANES*C_PACKED_META-1:0] local_meta;
 wire [C_LANES*C_TILE_WIDTH-1:0] local_tile;
 wire [C_LANES*5-1:0] local_port;wire [C_LANES*C_CLASS_WIDTH-1:0] local_class;wire [C_LANES-1:0] local_sop,local_eop;
 reg [C_LANES-1:0] local_active_q;reg local_protocol_error;integer li,ltmp,lptmp,lctmp,lvtmp;
 reg [C_LANES-1:0] local_legal;
 reg [C_LANES*3-1:0] local_group_q;reg [C_LANES*C_TILE_WIDTH-1:0] local_tile_q;
 reg [C_LANES*5-1:0] local_port_q;reg [C_LANES*C_CLASS_WIDTH-1:0] local_class_q;
 reg [C_LANES*C_VC_WIDTH-1:0] local_vc_q;reg [C_LANES-1:0] local_pool_q;
 // local包在进入弹性槽前验证lane映射并冻结包级字段；故障拍不消耗目的credit。
 always @(*) begin
  local_legal=0;ltmp=0;lptmp=0;lctmp=0;lvtmp=0;
  for(li=0;li<C_LANES;li=li+1) begin
   ltmp=0;lptmp=0;lctmp=0;lvtmp=0;
   ltmp[C_TILE_WIDTH-1:0]=i_local_dst_tile[li*C_TILE_WIDTH+:C_TILE_WIDTH];lptmp[4:0]=i_local_dst_port[li*5+:5];
   lctmp[C_CLASS_WIDTH-1:0]=i_local_class[li*C_CLASS_WIDTH+:C_CLASS_WIDTH];lvtmp[C_VC_WIDTH-1:0]=i_local_original_vc[li*C_VC_WIDTH+:C_VC_WIDTH];
   if(local_active_q[li]) local_legal[li]=!i_local_sop[li]&&
    (i_local_dst_group[li*3+:3]==local_group_q[li*3+:3])&&
    (i_local_dst_tile[li*C_TILE_WIDTH+:C_TILE_WIDTH]==local_tile_q[li*C_TILE_WIDTH+:C_TILE_WIDTH])&&
    (i_local_dst_port[li*5+:5]==local_port_q[li*5+:5])&&
    (i_local_class[li*C_CLASS_WIDTH+:C_CLASS_WIDTH]==local_class_q[li*C_CLASS_WIDTH+:C_CLASS_WIDTH])&&
    (i_local_original_vc[li*C_VC_WIDTH+:C_VC_WIDTH]==local_vc_q[li*C_VC_WIDTH+:C_VC_WIDTH])&&
    (i_local_pool[li]==local_pool_q[li]);
   else local_legal[li]=i_local_sop[li]&&(i_local_dst_group[li*3+:3]==C_GROUP_ID[2:0])&&
    (ltmp<C_TILES)&&(lptmp<C_DST_LOCALS)&&(lctmp<C_NUM_CLASSES)&&(lvtmp<C_NUM_VC)&&
    ((ltmp*C_BANK_LANES+(lptmp%C_BANK_LANES))==li);
  end
 end
 always @(posedge i_clk) begin
  if(!i_rstn) begin local_active_q<=0;local_protocol_error<=0;local_group_q<=0;local_tile_q<=0;local_port_q<=0;local_class_q<=0;local_vc_q<=0;local_pool_q<=0;end
  else for(li=0;li<C_LANES;li=li+1) begin
   if(i_local_valid[li]&&!local_legal[li])local_protocol_error<=1'b1;
   if(i_local_valid[li]&&o_local_ready[li]&&local_legal[li]) begin
    if(!local_active_q[li]) begin local_active_q[li]<=!i_local_eop[li];local_group_q[li*3+:3]<=i_local_dst_group[li*3+:3];
     local_tile_q[li*C_TILE_WIDTH+:C_TILE_WIDTH]<=i_local_dst_tile[li*C_TILE_WIDTH+:C_TILE_WIDTH];local_port_q[li*5+:5]<=i_local_dst_port[li*5+:5];
     local_class_q[li*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_local_class[li*C_CLASS_WIDTH+:C_CLASS_WIDTH];
     local_vc_q[li*C_VC_WIDTH+:C_VC_WIDTH]<=i_local_original_vc[li*C_VC_WIDTH+:C_VC_WIDTH];local_pool_q[li]<=i_local_pool[li];end
    else if(i_local_eop[li])local_active_q[li]<=1'b0;
   end
  end
 end
 genvar g;
 generate for(g=0;g<C_LANES;g=g+1) begin:g_local_slice
  wire [C_LOCAL_PAYLOAD-1:0] pin,pout;
  assign pin={i_local_dst_tile[g*C_TILE_WIDTH+:C_TILE_WIDTH],i_local_dst_port[g*5+:5],
   i_local_class[g*C_CLASS_WIDTH+:C_CLASS_WIDTH],i_local_sop[g],i_local_eop[g],
   i_local_packet_flits[g*C_COUNT_WIDTH+:C_COUNT_WIDTH],{(3+C_CORE_CONTEXT_WIDTH){1'b0}},i_local_pool[g],
   i_local_original_vc[g*C_VC_WIDTH+:C_VC_WIDTH],i_local_meta[g*C_META_WIDTH+:C_META_WIDTH],i_local_data[g*C_DATA_WIDTH+:C_DATA_WIDTH]};
  switch_fabric_elastic_slice #(.C_PAYLOAD_WIDTH(C_LOCAL_PAYLOAD))u_slice(.i_clk(i_clk),.i_rstn(i_rstn),
   .i_valid(i_local_valid[g]&local_legal[g]),.o_ready(local_input_ready[g]),.i_payload(pin),.o_valid(local_pre_valid[g]),
   .i_ready(local_pre_ready[g]),.o_payload(pout),.o_quiescent(local_slice_idle[g]),.o_config_error(local_slice_cfg[g]),.o_error(local_slice_err[g]));
  assign {local_tile[g*C_TILE_WIDTH+:C_TILE_WIDTH],local_port[g*5+:5],local_class[g*C_CLASS_WIDTH+:C_CLASS_WIDTH],
   local_sop[g],local_eop[g],local_meta[g*C_PACKED_META+:C_PACKED_META],local_data[g*C_DATA_WIDTH+:C_DATA_WIDTH]}=pout;
 end endgenerate
 assign o_local_ready=local_input_ready&local_legal;
 // Core与local先按原始requester进入同一账本；Core account/token随后穿过Destination Group路由。
 wire [C_PLANES*C_PACKED_META-1:0] core_admit_meta;
 genvar plane_index;
 generate for(plane_index=0;plane_index<C_PLANES;plane_index=plane_index+1)begin:g_core_admit_meta
  assign core_admit_meta[plane_index*C_PACKED_META+:C_PACKED_META]={i_core_packet_flits[plane_index*C_COUNT_WIDTH+:C_COUNT_WIDTH],
   i_core_dst_group[plane_index*3+:3],i_core_context[plane_index*C_CORE_CONTEXT_WIDTH+:C_CORE_CONTEXT_WIDTH],i_core_pool[plane_index],
   i_core_original_vc[plane_index*C_VC_WIDTH+:C_VC_WIDTH],i_core_meta[plane_index*C_META_WIDTH+:C_META_WIDTH]};
 end endgenerate
 wire [C_LANES-1:0] credit_local_valid,credit_local_ready;wire [C_LANES*C_DATA_WIDTH-1:0] credit_local_data;
 wire [C_LANES*C_PACKED_META-1:0] credit_local_meta;wire [C_LANES*C_TILE_WIDTH-1:0] credit_local_tile;
 wire [C_LANES*5-1:0] credit_local_port;wire [C_LANES*C_CLASS_WIDTH-1:0] credit_local_class;
 wire [C_LANES-1:0] credit_local_sop,credit_local_eop;wire [C_LANES*C_ACCOUNT_WIDTH-1:0] credit_local_account;
 wire [C_LANES*C_TOKEN_WIDTH-1:0] credit_local_token;
 wire [C_LANES*C_COUNT_WIDTH-1:0] local_admit_flits;
 wire [C_PLANES-1:0] credit_core_valid,credit_core_ready;wire [C_PLANES*C_DATA_WIDTH-1:0] credit_core_data;
 wire [C_PLANES*C_PACKED_META-1:0] credit_core_meta;wire [C_PLANES*C_TILE_WIDTH-1:0] credit_core_tile;
 wire [C_PLANES*5-1:0] credit_core_port;wire [C_PLANES*C_CLASS_WIDTH-1:0] credit_core_class;
 wire [C_PLANES*C_CORE_CONTEXT_WIDTH-1:0] credit_core_context;wire [C_PLANES-1:0] credit_core_sop,credit_core_eop;
 wire [C_PLANES*C_ACCOUNT_WIDTH-1:0] credit_core_account;wire [C_PLANES*C_TOKEN_WIDTH-1:0] credit_core_token;
 wire credit_idle,credit_error;
 generate for(g=0;g<C_LANES;g=g+1)begin:g_local_admit_flits
  assign local_admit_flits[g*C_COUNT_WIDTH+:C_COUNT_WIDTH]=
   local_meta[g*C_PACKED_META+C_META_WIDTH+C_VC_WIDTH+1+C_CORE_CONTEXT_WIDTH+3+:C_COUNT_WIDTH];
 end endgenerate
 switch_destination_plane_credit_admission #(.C_LOCAL_REQUESTERS(C_LANES),.C_PLANES(C_PLANES),.C_DATA_WIDTH(C_DATA_WIDTH),
  .C_META_WIDTH(C_PACKED_META),.C_TILE_WIDTH(C_TILE_WIDTH),.C_LOCAL_WIDTH(5),.C_CLASS_WIDTH(C_CLASS_WIDTH),
  .C_CONTEXT_WIDTH(C_CORE_CONTEXT_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_GENERATION_WIDTH(C_GENERATION_WIDTH),
  .C_SLOT_WIDTH(C_SLOT_WIDTH),.C_BANK_SLOT_WIDTH(C_BANK_SLOT_WIDTH),.C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_TOKEN_WIDTH(C_TOKEN_WIDTH),
  .C_CREDIT_COUNT_WIDTH(C_CREDIT_COUNT_WIDTH),.C_TILES(C_TILES),.C_DST_LOCALS(C_DST_LOCALS),.C_CLASSES(C_NUM_CLASSES),
  .C_PACKET_COUNT_WIDTH(C_COUNT_WIDTH),
  .C_CAPACITY(C_CAPACITY),.C_REQUESTERS(C_REQUESTERS),.C_REQUESTER_WIDTH(C_OWNER_WIDTH),.C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),.C_RESOURCES(C_RESOURCES),
  .C_ACCOUNTS(C_ACCOUNTS),.C_RELEASE_PORTS(C_RELEASE_PORTS))u_plane_credit(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_epoch(i_epoch),.i_local_valid(local_pre_valid),.o_local_ready(local_pre_ready),
  .i_local_data(local_data),.i_local_meta(local_meta),.i_local_dst_tile(local_tile),.i_local_dst_local(local_port),
  .i_local_class(local_class),.i_local_packet_flits(local_admit_flits),
  .i_local_sop(local_sop),.i_local_eop(local_eop),.o_local_valid(credit_local_valid),
  .i_local_ready(credit_local_ready),.o_local_data(credit_local_data),.o_local_meta(credit_local_meta),
  .o_local_dst_tile(credit_local_tile),.o_local_dst_local(credit_local_port),.o_local_class(credit_local_class),
  .o_local_sop(credit_local_sop),.o_local_eop(credit_local_eop),.o_local_account(credit_local_account),.o_local_token(credit_local_token),
  .i_core_valid(i_core_valid),.o_core_ready(o_core_ready),.i_core_data(i_core_data),.i_core_meta(core_admit_meta),
  .i_core_dst_tile(i_core_dst_tile),.i_core_dst_local(i_core_dst_port),.i_core_class(i_core_class),.i_core_context(i_core_context),
  .i_core_packet_flits(i_core_packet_flits),
  .i_core_sop(i_core_sop),.i_core_eop(i_core_eop),.o_core_valid(credit_core_valid),.i_core_ready(credit_core_ready),
  .o_core_data(credit_core_data),.o_core_meta(credit_core_meta),.o_core_dst_tile(credit_core_tile),.o_core_dst_local(credit_core_port),
  .o_core_class(credit_core_class),.o_core_context(credit_core_context),.o_core_sop(credit_core_sop),.o_core_eop(credit_core_eop),
  .o_core_account(credit_core_account),.o_core_token(credit_core_token),.o_core_registered_eligibility(o_core_registered_eligibility),
  .o_core_eligibility_dst_tile(o_core_eligibility_dst_tile),.o_core_eligibility_dst_local(o_core_eligibility_dst_port),
  .o_core_eligibility_class(o_core_eligibility_class),.o_core_eligibility_epoch(o_core_eligibility_epoch),
  .i_release_valid(i_release_valid),.o_release_ready(o_release_ready),.i_release_token(i_release_token),
  .o_free(o_free),.o_effective_free(o_effective_free),.o_issued(o_issued),.o_occupied(o_occupied),
  .o_quiescent(credit_idle),.o_error(credit_error),
  .o_return_malformed_event_level(o_return_malformed_event_level),
  .o_return_duplicate_event_level(o_return_duplicate_event_level),
  .o_return_stale_event_level(o_return_stale_event_level),
  .o_return_wrong_port_event_level(o_return_wrong_port_event_level));
 localparam integer C_DGROUP_META=C_PACKED_META+C_TOKEN_WIDTH;
 wire [C_PLANES*C_DGROUP_META-1:0] credit_core_dgroup_meta;
 generate for(plane_index=0;plane_index<C_PLANES;plane_index=plane_index+1)begin:g_credit_core_pack
  assign credit_core_dgroup_meta[plane_index*C_DGROUP_META+:C_DGROUP_META]={credit_core_token[plane_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH],
   credit_core_meta[plane_index*C_PACKED_META+:C_PACKED_META]};
 end endgenerate
 wire [C_LANES-1:0] remote_raw_valid,remote_raw_ready,remote_valid,remote_ready,remote_slice_idle,remote_slice_cfg,remote_slice_err;
 wire [C_LANES*C_DATA_WIDTH-1:0] remote_raw_data,remote_data;wire [C_LANES*C_DGROUP_META-1:0] remote_raw_meta,remote_meta;
 wire [C_LANES*3-1:0] remote_raw_group;wire [C_LANES*C_TILE_WIDTH-1:0] remote_raw_tile,remote_tile;
 wire [C_LANES*5-1:0] remote_raw_port,remote_port;wire [C_LANES*C_CLASS_WIDTH-1:0] remote_raw_class,remote_class;
 wire [C_LANES*C_COUNT_WIDTH-1:0] remote_raw_flits;wire [C_LANES*C_ACCOUNT_WIDTH-1:0] remote_raw_account,remote_account;
 wire [C_LANES-1:0] remote_raw_sop,remote_raw_eop,remote_sop,remote_eop;wire dgroup_cfg,dgroup_protocol,dgroup_error,dgroup_idle;
 wire [C_PLANES*3-1:0] admitted_group;wire [C_PLANES*C_COUNT_WIDTH-1:0] admitted_flits;
 generate for(plane_index=0;plane_index<C_PLANES;plane_index=plane_index+1)begin:g_admitted_route
  assign admitted_group[plane_index*3+:3]=credit_core_meta[plane_index*C_PACKED_META+C_META_WIDTH+C_VC_WIDTH+1+C_CORE_CONTEXT_WIDTH+:3];
  assign admitted_flits[plane_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=credit_core_meta[plane_index*C_PACKED_META+C_META_WIDTH+C_VC_WIDTH+1+C_CORE_CONTEXT_WIDTH+3+:C_COUNT_WIDTH];
 end endgenerate
 switch_destination_group_multi_lane #(.C_PLANES(C_PLANES),.C_TILES(C_TILES),.C_BANK_LANES(C_BANK_LANES),.C_DATA_WIDTH(C_DATA_WIDTH),
  .C_META_WIDTH(C_DGROUP_META),.C_TILE_WIDTH(C_TILE_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),
  .C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_PLANE_WIDTH(C_PLANE_WIDTH),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_GROUPS(C_NUM_GROUPS),.C_GROUP_ID(C_GROUP_ID))u_destination_group(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(credit_core_valid),.o_ready(credit_core_ready),.i_data(credit_core_data),.i_meta(credit_core_dgroup_meta),
  .i_dst_group(admitted_group),.i_dst_tile(credit_core_tile),.i_dst_port(credit_core_port),.i_class(credit_core_class),
  .i_packet_flits(admitted_flits),.i_account(credit_core_account),.i_sop(credit_core_sop),.i_eop(credit_core_eop),
  .o_valid(remote_raw_valid),.i_ready(remote_raw_ready),.o_data(remote_raw_data),.o_meta(remote_raw_meta),.o_dst_group(remote_raw_group),
  .o_dst_tile(remote_raw_tile),.o_dst_port(remote_raw_port),.o_class(remote_raw_class),.o_packet_flits(remote_raw_flits),
  .o_account(remote_raw_account),.o_sop(remote_raw_sop),.o_eop(remote_raw_eop),.o_config_error(dgroup_cfg),
  .o_protocol_error(dgroup_protocol),.o_error(dgroup_error),.o_quiescent(dgroup_idle));
 localparam integer C_REMOTE_PAYLOAD2=C_DATA_WIDTH+C_DGROUP_META+C_TILE_WIDTH+5+C_CLASS_WIDTH+C_ACCOUNT_WIDTH+2;
 generate for(g=0;g<C_LANES;g=g+1)begin:g_remote_credit_slice
  wire [C_REMOTE_PAYLOAD2-1:0] pin,pout;
  assign pin={remote_raw_tile[g*C_TILE_WIDTH+:C_TILE_WIDTH],remote_raw_port[g*5+:5],remote_raw_class[g*C_CLASS_WIDTH+:C_CLASS_WIDTH],
   remote_raw_account[g*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH],remote_raw_sop[g],remote_raw_eop[g],
   remote_raw_meta[g*C_DGROUP_META+:C_DGROUP_META],remote_raw_data[g*C_DATA_WIDTH+:C_DATA_WIDTH]};
  switch_fabric_elastic_slice #(.C_PAYLOAD_WIDTH(C_REMOTE_PAYLOAD2))u_slice(.i_clk(i_clk),.i_rstn(i_rstn),.i_valid(remote_raw_valid[g]),
   .o_ready(remote_raw_ready[g]),.i_payload(pin),.o_valid(remote_valid[g]),.i_ready(remote_ready[g]),.o_payload(pout),
   .o_quiescent(remote_slice_idle[g]),.o_config_error(remote_slice_cfg[g]),.o_error(remote_slice_err[g]));
  assign {remote_tile[g*C_TILE_WIDTH+:C_TILE_WIDTH],remote_port[g*5+:5],remote_class[g*C_CLASS_WIDTH+:C_CLASS_WIDTH],
   remote_account[g*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH],remote_sop[g],remote_eop[g],remote_meta[g*C_DGROUP_META+:C_DGROUP_META],
   remote_data[g*C_DATA_WIDTH+:C_DATA_WIDTH]}=pout;
 end endgenerate
 wire [C_LANES*C_META_WIDTH-1:0] merge_local_meta,merge_remote_meta;wire [C_LANES*C_VC_WIDTH-1:0] merge_local_vc,merge_remote_vc;
 wire [C_LANES-1:0] merge_local_pool,merge_remote_pool;wire [C_LANES*C_TOKEN_WIDTH-1:0] remote_token;
 generate for(g=0;g<C_LANES;g=g+1)begin:g_merge_unpack
  assign merge_local_meta[g*C_META_WIDTH+:C_META_WIDTH]=credit_local_meta[g*C_PACKED_META+:C_META_WIDTH];
  assign merge_local_vc[g*C_VC_WIDTH+:C_VC_WIDTH]=credit_local_meta[g*C_PACKED_META+C_META_WIDTH+:C_VC_WIDTH];
  assign merge_local_pool[g]=credit_local_meta[g*C_PACKED_META+C_META_WIDTH+C_VC_WIDTH];
  assign merge_remote_meta[g*C_META_WIDTH+:C_META_WIDTH]=remote_meta[g*C_DGROUP_META+:C_META_WIDTH];
  assign merge_remote_vc[g*C_VC_WIDTH+:C_VC_WIDTH]=remote_meta[g*C_DGROUP_META+C_META_WIDTH+:C_VC_WIDTH];
  assign merge_remote_pool[g]=remote_meta[g*C_DGROUP_META+C_META_WIDTH+C_VC_WIDTH];
  assign remote_token[g*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]=remote_meta[g*C_DGROUP_META+C_PACKED_META+:C_TOKEN_WIDTH];
 end endgenerate
 wire merge_cfg,merge_protocol,merge_error,merge_idle;
 switch_destination_local_remote_merge #(.C_LANES(C_LANES),.C_TILES(C_TILES),.C_BANK_LANES(C_BANK_LANES),.C_DATA_WIDTH(C_DATA_WIDTH),
  .C_META_WIDTH(C_META_WIDTH),.C_TILE_WIDTH(C_TILE_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_VC_WIDTH(C_VC_WIDTH),
  .C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_TOKEN_WIDTH(C_TOKEN_WIDTH),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VC(C_NUM_VC),
  .C_NUM_GROUPS(C_NUM_GROUPS),.C_GROUP_ID(C_GROUP_ID))u_merge(.i_clk(i_clk),.i_rstn(i_rstn),
  .i_local_valid(credit_local_valid),.o_local_ready(credit_local_ready),.i_local_data(credit_local_data),.i_local_meta(merge_local_meta),
  .i_local_dst_group({C_LANES{C_GROUP_ID[2:0]}}),.i_local_dst_tile(credit_local_tile),.i_local_dst_port(credit_local_port),
  .i_local_class(credit_local_class),.i_local_original_vc(merge_local_vc),.i_local_pool(merge_local_pool),
  .i_local_account(credit_local_account),.i_local_token(credit_local_token),.i_local_sop(credit_local_sop),.i_local_eop(credit_local_eop),
  .i_remote_valid(remote_valid),.o_remote_ready(remote_ready),.i_remote_data(remote_data),.i_remote_meta(merge_remote_meta),
  .i_remote_dst_group({C_LANES{C_GROUP_ID[2:0]}}),.i_remote_dst_tile(remote_tile),.i_remote_dst_port(remote_port),
  .i_remote_class(remote_class),.i_remote_original_vc(merge_remote_vc),.i_remote_pool(merge_remote_pool),
  .i_remote_account(remote_account),.i_remote_token(remote_token),.i_remote_sop(remote_sop),.i_remote_eop(remote_eop),
  .o_valid(o_valid),.i_ready(i_ready),.o_data(o_data),.o_meta(o_meta),.o_dst_group(o_dst_group),.o_dst_tile(o_dst_tile),
  .o_dst_port(o_dst_port),.o_class(o_class),.o_original_vc(o_original_vc),.o_pool(o_pool),.o_account(o_account),.o_token(o_token),
  .o_sop(o_sop),.o_eop(o_eop),.o_config_error(merge_cfg),.o_protocol_error(merge_protocol),.o_error(merge_error),.o_quiescent(merge_idle));
 assign o_quiescent=credit_idle&dgroup_idle&(&local_slice_idle)&(&remote_slice_idle)&merge_idle&~(|local_active_q);
 wire ignored_status=^{remote_raw_group,remote_raw_flits,credit_core_context};
 assign o_error=local_protocol_error|credit_error|dgroup_cfg|dgroup_protocol|dgroup_error|(|local_slice_cfg)|(|local_slice_err)|
  (|remote_slice_cfg)|(|remote_slice_err)|merge_cfg|merge_protocol|merge_error|(ignored_status&1'b0);
endmodule
`default_nettype wire
