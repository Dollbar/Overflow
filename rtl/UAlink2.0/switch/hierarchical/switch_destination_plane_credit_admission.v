`timescale 1ns/1ps
`default_nettype none
// 在Destination Group lane仲裁前按原始Core plane取得目的slot。
// local requester与Core plane共享唯一banked ledger，因此同一物理slot不会被两条路径重复发行。
module switch_destination_plane_credit_admission #(
 parameter integer C_LOCAL_REQUESTERS=32,C_PLANES=32,C_DATA_WIDTH=256,C_META_WIDTH=128,
 parameter integer C_TILE_WIDTH=2,C_LOCAL_WIDTH=5,C_CLASS_WIDTH=2,C_CONTEXT_WIDTH=6,
 parameter integer C_EPOCH_WIDTH=4,C_GENERATION_WIDTH=8,C_SLOT_WIDTH=11,C_BANK_SLOT_WIDTH=2,
 parameter integer C_ACCOUNT_WIDTH=15,C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH,
 parameter integer C_CREDIT_COUNT_WIDTH=3,C_TILES=4,C_DST_LOCALS=32,C_CLASSES=4,C_CAPACITY=4,
 parameter integer C_PACKET_COUNT_WIDTH=5,
 parameter integer C_REQUESTERS=C_LOCAL_REQUESTERS+C_PLANES,parameter integer C_REQUESTER_WIDTH=6,parameter integer C_RESOURCE_WIDTH=9,
 parameter integer C_RESOURCES=C_TILES*C_DST_LOCALS*C_CLASSES,
 parameter integer C_ACCOUNTS=C_REQUESTERS*C_RESOURCES,parameter integer C_RELEASE_PORTS=C_TILES*C_DST_LOCALS
)(
 input wire i_clk,input wire i_rstn,input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 input wire [C_LOCAL_REQUESTERS-1:0] i_local_valid,output wire [C_LOCAL_REQUESTERS-1:0] o_local_ready,
 input wire [C_LOCAL_REQUESTERS*C_DATA_WIDTH-1:0] i_local_data,input wire [C_LOCAL_REQUESTERS*C_META_WIDTH-1:0] i_local_meta,
 input wire [C_LOCAL_REQUESTERS*C_TILE_WIDTH-1:0] i_local_dst_tile,
 input wire [C_LOCAL_REQUESTERS*C_LOCAL_WIDTH-1:0] i_local_dst_local,
 input wire [C_LOCAL_REQUESTERS*C_CLASS_WIDTH-1:0] i_local_class,
 input wire [C_LOCAL_REQUESTERS*C_PACKET_COUNT_WIDTH-1:0] i_local_packet_flits,
 input wire [C_LOCAL_REQUESTERS-1:0] i_local_sop,input wire [C_LOCAL_REQUESTERS-1:0] i_local_eop,
 output wire [C_LOCAL_REQUESTERS-1:0] o_local_valid,input wire [C_LOCAL_REQUESTERS-1:0] i_local_ready,
 output wire [C_LOCAL_REQUESTERS*C_DATA_WIDTH-1:0] o_local_data,output wire [C_LOCAL_REQUESTERS*C_META_WIDTH-1:0] o_local_meta,
 output wire [C_LOCAL_REQUESTERS*C_TILE_WIDTH-1:0] o_local_dst_tile,
 output wire [C_LOCAL_REQUESTERS*C_LOCAL_WIDTH-1:0] o_local_dst_local,
 output wire [C_LOCAL_REQUESTERS*C_CLASS_WIDTH-1:0] o_local_class,
 output wire [C_LOCAL_REQUESTERS-1:0] o_local_sop,output wire [C_LOCAL_REQUESTERS-1:0] o_local_eop,
 output wire [C_LOCAL_REQUESTERS*C_ACCOUNT_WIDTH-1:0] o_local_account,
 output wire [C_LOCAL_REQUESTERS*C_TOKEN_WIDTH-1:0] o_local_token,
 input wire [C_PLANES-1:0] i_core_valid,output wire [C_PLANES-1:0] o_core_ready,
 input wire [C_PLANES*C_DATA_WIDTH-1:0] i_core_data,input wire [C_PLANES*C_META_WIDTH-1:0] i_core_meta,
 input wire [C_PLANES*C_TILE_WIDTH-1:0] i_core_dst_tile,input wire [C_PLANES*C_LOCAL_WIDTH-1:0] i_core_dst_local,
 input wire [C_PLANES*C_CLASS_WIDTH-1:0] i_core_class,input wire [C_PLANES*C_CONTEXT_WIDTH-1:0] i_core_context,
 input wire [C_PLANES*C_PACKET_COUNT_WIDTH-1:0] i_core_packet_flits,
 input wire [C_PLANES-1:0] i_core_sop,input wire [C_PLANES-1:0] i_core_eop,
 output wire [C_PLANES-1:0] o_core_valid,input wire [C_PLANES-1:0] i_core_ready,
 output wire [C_PLANES*C_DATA_WIDTH-1:0] o_core_data,output wire [C_PLANES*C_META_WIDTH-1:0] o_core_meta,
 output wire [C_PLANES*C_TILE_WIDTH-1:0] o_core_dst_tile,output wire [C_PLANES*C_LOCAL_WIDTH-1:0] o_core_dst_local,
 output wire [C_PLANES*C_CLASS_WIDTH-1:0] o_core_class,output wire [C_PLANES*C_CONTEXT_WIDTH-1:0] o_core_context,
 output wire [C_PLANES-1:0] o_core_sop,output wire [C_PLANES-1:0] o_core_eop,
 output wire [C_PLANES*C_ACCOUNT_WIDTH-1:0] o_core_account,output wire [C_PLANES*C_TOKEN_WIDTH-1:0] o_core_token,
 output reg [C_PLANES-1:0] o_core_registered_eligibility,
 output reg [C_PLANES*C_TILE_WIDTH-1:0] o_core_eligibility_dst_tile,
 output reg [C_PLANES*C_LOCAL_WIDTH-1:0] o_core_eligibility_dst_local,
 output reg [C_PLANES*C_CLASS_WIDTH-1:0] o_core_eligibility_class,
 output reg [C_EPOCH_WIDTH-1:0] o_core_eligibility_epoch,
 input wire [C_RELEASE_PORTS-1:0] i_release_valid,output wire [C_RELEASE_PORTS-1:0] o_release_ready,
 input wire [C_RELEASE_PORTS*C_TOKEN_WIDTH-1:0] i_release_token,
 output wire [C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] o_free,
 output reg [C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] o_effective_free,
 output wire [C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_issued,
 output wire [C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] o_occupied,
 output wire o_quiescent,output wire o_error,
 output wire o_return_malformed_event_level,output wire o_return_duplicate_event_level,
 output wire o_return_stale_event_level,output wire o_return_wrong_port_event_level
);
 wire [C_REQUESTERS-1:0] raw_valid,stage_i_valid,stage_i_ready,stage_o_valid,stage_o_ready,stage_i_sop,stage_i_eop,stage_o_sop,stage_o_eop;
 wire [C_REQUESTERS*C_DATA_WIDTH-1:0] stage_i_data,stage_o_data;wire [C_REQUESTERS*C_META_WIDTH-1:0] stage_i_meta,stage_o_meta;
 wire [C_REQUESTERS*C_TILE_WIDTH-1:0] stage_i_tile,stage_o_tile;
 wire [C_REQUESTERS*C_LOCAL_WIDTH-1:0] stage_i_local,stage_o_local;
 wire [C_REQUESTERS*C_CLASS_WIDTH-1:0] stage_i_class,stage_o_class;
 wire [C_REQUESTERS*C_CONTEXT_WIDTH-1:0] stage_i_owner,stage_o_owner;
 wire [C_REQUESTERS-1:0] stage_i_slice,stage_o_slice;
 wire [C_REQUESTERS*C_ACCOUNT_WIDTH-1:0] stage_o_account;wire [C_REQUESTERS*C_TOKEN_WIDTH-1:0] stage_o_token;wire stage_error,stage_idle;
 wire [C_REQUESTERS*C_PACKET_COUNT_WIDTH-1:0] stage_i_packet_flits;
 reg [C_REQUESTERS-1:0] owner_allowed,invalid_body,invalid_packet;
 reg [C_REQUESTERS*C_RESOURCE_WIDTH-1:0] request_resource;
 reg [C_RESOURCES-1:0] resource_owner_valid_q;
 reg [C_REQUESTER_WIDTH-1:0] resource_owner_q[0:C_RESOURCES-1];reg ownership_error;
 reg [C_CONTEXT_WIDTH-1:0] resource_context_q[0:C_RESOURCES-1];
 reg [C_PACKET_COUNT_WIDTH-1:0] resource_remaining_q[0:C_RESOURCES-1];
 reg reservation_underflow_now,reservation_underflow_error;
 integer requester_index,resource_index,tile_value,local_value,class_value,packet_value,free_value;
 integer state_resource,state_requester,effective_resource,physical_count,reserved_count;
 assign raw_valid={i_core_valid,i_local_valid};assign stage_i_valid=raw_valid&owner_allowed;
 assign {o_core_ready,o_local_ready}=stage_i_ready&owner_allowed;
 assign stage_i_data={i_core_data,i_local_data};assign stage_i_meta={i_core_meta,i_local_meta};assign stage_i_tile={i_core_dst_tile,i_local_dst_tile};
 assign stage_i_local={i_core_dst_local,i_local_dst_local};assign stage_i_class={i_core_class,i_local_class};
 assign stage_i_sop={i_core_sop,i_local_sop};assign stage_i_eop={i_core_eop,i_local_eop};assign stage_i_slice=0;
 // local与Core SOP都携带完整长度；body固定传零并消费SOP留下的预约。
 assign stage_i_packet_flits={i_core_packet_flits,i_local_packet_flits};
 // effective_free扣除已预约但尚未向真实ledger发行的body beat；异常时饱和为0并报告RAS。
 always @(*)begin
  o_effective_free=0;reservation_underflow_now=1'b0;physical_count=0;reserved_count=0;
  for(effective_resource=0;effective_resource<C_RESOURCES;effective_resource=effective_resource+1)begin
   physical_count=0;reserved_count=0;
   physical_count[C_CREDIT_COUNT_WIDTH-1:0]=
    o_free[effective_resource*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH];
   reserved_count[C_PACKET_COUNT_WIDTH-1:0]=resource_remaining_q[effective_resource];
   if(physical_count>=reserved_count)
    o_effective_free[effective_resource*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH]=
     o_free[effective_resource*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH]-
     reserved_count[C_CREDIT_COUNT_WIDTH-1:0];
   else begin
    o_effective_free[effective_resource*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH]=0;
    reservation_underflow_now=1'b1;
   end
  end
 end
 // 每个目的资源在一个packet期间只接受原requester；避免body bubble时竞争者占走唯一slot形成死锁。
 always @(*)begin
  owner_allowed=0;invalid_body=0;invalid_packet=0;request_resource=0;
  resource_index=0;tile_value=0;local_value=0;class_value=0;packet_value=0;free_value=0;
  for(requester_index=0;requester_index<C_REQUESTERS;requester_index=requester_index+1)begin
   tile_value=0;local_value=0;class_value=0;
   tile_value[C_TILE_WIDTH-1:0]=stage_i_tile[requester_index*C_TILE_WIDTH+:C_TILE_WIDTH];
   local_value[C_LOCAL_WIDTH-1:0]=stage_i_local[requester_index*C_LOCAL_WIDTH+:C_LOCAL_WIDTH];
   class_value[C_CLASS_WIDTH-1:0]=stage_i_class[requester_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];
   packet_value=0;
   packet_value[C_PACKET_COUNT_WIDTH-1:0]=stage_i_packet_flits[requester_index*C_PACKET_COUNT_WIDTH+:C_PACKET_COUNT_WIDTH];
   resource_index=(tile_value*C_DST_LOCALS+local_value)*C_CLASSES+class_value;
   request_resource[requester_index*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]=resource_index[C_RESOURCE_WIDTH-1:0];
   if(resource_index<C_RESOURCES)begin
    free_value=0;
    free_value[C_CREDIT_COUNT_WIDTH-1:0]=o_free[resource_index*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH];
    if(stage_i_sop[requester_index])begin
     invalid_packet[requester_index]=(packet_value<1)||(packet_value>C_CAPACITY)||
      (stage_i_eop[requester_index]!=(packet_value==1));
     owner_allowed[requester_index]=!resource_owner_valid_q[resource_index]&&
      !invalid_packet[requester_index]&&(free_value>=packet_value);
    end else begin
     owner_allowed[requester_index]=resource_owner_valid_q[resource_index]&&
      (resource_owner_q[resource_index]==requester_index[C_REQUESTER_WIDTH-1:0])&&
      (resource_context_q[resource_index]==stage_i_owner[requester_index*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH]);
     invalid_packet[requester_index]=(packet_value!=0)||(resource_remaining_q[resource_index]==0)||
      (stage_i_eop[requester_index]!=(resource_remaining_q[resource_index]==1));
     owner_allowed[requester_index]=owner_allowed[requester_index]&&!invalid_packet[requester_index];
     invalid_body[requester_index]=!owner_allowed[requester_index];
    end
   end
  end
 end
 always @(posedge i_clk)begin
  if(!i_rstn)begin resource_owner_valid_q<=0;ownership_error<=0;reservation_underflow_error<=0;
   for(state_resource=0;state_resource<C_RESOURCES;state_resource=state_resource+1)begin
   resource_owner_q[state_resource]<=0;resource_context_q[state_resource]<=0;resource_remaining_q[state_resource]<=0;end end
  else begin
   if(|(raw_valid&(invalid_body|invalid_packet)))ownership_error<=1'b1;
   if(reservation_underflow_now)reservation_underflow_error<=1'b1;
   for(state_requester=0;state_requester<C_REQUESTERS;state_requester=state_requester+1)if(stage_i_valid[state_requester]&&stage_i_ready[state_requester])begin
    if(stage_i_sop[state_requester]&&!stage_i_eop[state_requester])begin
     resource_owner_valid_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]<=1'b1;
     resource_owner_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]<=state_requester[C_REQUESTER_WIDTH-1:0];
     resource_context_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]<=
      stage_i_owner[state_requester*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH];
     resource_remaining_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]<=
      stage_i_packet_flits[state_requester*C_PACKET_COUNT_WIDTH+:C_PACKET_COUNT_WIDTH]-1'b1;
    end else if(!stage_i_sop[state_requester]&&stage_i_eop[state_requester])begin
     resource_owner_valid_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]<=1'b0;
     resource_remaining_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]<=0;
    end else if(!stage_i_sop[state_requester])
     resource_remaining_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]<=
      resource_remaining_q[request_resource[state_requester*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]]-1'b1;
   end
  end
 end
 genvar g;
 generate for(g=0;g<C_LOCAL_REQUESTERS;g=g+1)begin:g_local_owner
  assign stage_i_owner[g*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH]=g[C_CONTEXT_WIDTH-1:0];
 end for(g=0;g<C_PLANES;g=g+1)begin:g_core_owner
  assign stage_i_owner[(C_LOCAL_REQUESTERS+g)*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH]=i_core_context[g*C_CONTEXT_WIDTH+:C_CONTEXT_WIDTH];
 end endgenerate
 assign o_local_valid=stage_o_valid[0+:C_LOCAL_REQUESTERS];assign stage_o_ready[0+:C_LOCAL_REQUESTERS]=i_local_ready;
 assign o_local_data=stage_o_data[0+:C_LOCAL_REQUESTERS*C_DATA_WIDTH];assign o_local_meta=stage_o_meta[0+:C_LOCAL_REQUESTERS*C_META_WIDTH];
 assign o_local_dst_tile=stage_o_tile[0+:C_LOCAL_REQUESTERS*C_TILE_WIDTH];assign o_local_dst_local=stage_o_local[0+:C_LOCAL_REQUESTERS*C_LOCAL_WIDTH];
 assign o_local_class=stage_o_class[0+:C_LOCAL_REQUESTERS*C_CLASS_WIDTH];assign o_local_sop=stage_o_sop[0+:C_LOCAL_REQUESTERS];
 assign o_local_eop=stage_o_eop[0+:C_LOCAL_REQUESTERS];assign o_local_account=stage_o_account[0+:C_LOCAL_REQUESTERS*C_ACCOUNT_WIDTH];
 assign o_local_token=stage_o_token[0+:C_LOCAL_REQUESTERS*C_TOKEN_WIDTH];
 assign o_core_valid=stage_o_valid[C_LOCAL_REQUESTERS+:C_PLANES];assign stage_o_ready[C_LOCAL_REQUESTERS+:C_PLANES]=i_core_ready;
 assign o_core_data=stage_o_data[C_LOCAL_REQUESTERS*C_DATA_WIDTH+:C_PLANES*C_DATA_WIDTH];
 assign o_core_meta=stage_o_meta[C_LOCAL_REQUESTERS*C_META_WIDTH+:C_PLANES*C_META_WIDTH];
 assign o_core_dst_tile=stage_o_tile[C_LOCAL_REQUESTERS*C_TILE_WIDTH+:C_PLANES*C_TILE_WIDTH];
 assign o_core_dst_local=stage_o_local[C_LOCAL_REQUESTERS*C_LOCAL_WIDTH+:C_PLANES*C_LOCAL_WIDTH];
 assign o_core_class=stage_o_class[C_LOCAL_REQUESTERS*C_CLASS_WIDTH+:C_PLANES*C_CLASS_WIDTH];
 assign o_core_context=stage_o_owner[C_LOCAL_REQUESTERS*C_CONTEXT_WIDTH+:C_PLANES*C_CONTEXT_WIDTH];
 assign o_core_sop=stage_o_sop[C_LOCAL_REQUESTERS+:C_PLANES];assign o_core_eop=stage_o_eop[C_LOCAL_REQUESTERS+:C_PLANES];
 assign o_core_account=stage_o_account[C_LOCAL_REQUESTERS*C_ACCOUNT_WIDTH+:C_PLANES*C_ACCOUNT_WIDTH];
 assign o_core_token=stage_o_token[C_LOCAL_REQUESTERS*C_TOKEN_WIDTH+:C_PLANES*C_TOKEN_WIDTH];
 // eligibility是上一周期真实issue-ready的注册观察值，只能用于选择提示；传输仍必须等待o_core_ready握手。
 always @(posedge i_clk)begin
  if(!i_rstn)begin o_core_registered_eligibility<=0;o_core_eligibility_dst_tile<=0;o_core_eligibility_dst_local<=0;
   o_core_eligibility_class<=0;o_core_eligibility_epoch<=0;end
  else begin o_core_registered_eligibility<=stage_i_ready[C_LOCAL_REQUESTERS+:C_PLANES]&owner_allowed[C_LOCAL_REQUESTERS+:C_PLANES];
   o_core_eligibility_dst_tile<=i_core_dst_tile;o_core_eligibility_dst_local<=i_core_dst_local;
   o_core_eligibility_class<=i_core_class;o_core_eligibility_epoch<=i_epoch;end
 end
 switch_destination_credit_stage #(.C_USE_BANKED_LEDGER(1),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),
  .C_REQUESTERS(C_REQUESTERS),.C_SLICES(1),.C_TILES(C_TILES),.C_DST_LOCALS(C_DST_LOCALS),.C_CLASSES(C_CLASSES),
  .C_CAPACITY(C_CAPACITY),.C_REQUESTER_WIDTH(C_REQUESTER_WIDTH),.C_OWNER_WIDTH(C_CONTEXT_WIDTH),.C_SLICE_WIDTH(1),
  .C_TILE_WIDTH(C_TILE_WIDTH),.C_LOCAL_WIDTH(C_LOCAL_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
  .C_GENERATION_WIDTH(C_GENERATION_WIDTH),.C_SLOT_WIDTH(C_SLOT_WIDTH),.C_BANK_SLOT_WIDTH(C_BANK_SLOT_WIDTH),
  .C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_COUNT_WIDTH(C_CREDIT_COUNT_WIDTH),.C_RESOURCES(C_RESOURCES),.C_ACCOUNTS(C_ACCOUNTS),
  .C_RELEASE_PORTS(C_RELEASE_PORTS),.C_TOKEN_WIDTH(C_TOKEN_WIDTH))u_stage(.i_clk(i_clk),.i_rstn(i_rstn),.i_epoch(i_epoch),
  .i_valid(stage_i_valid),.o_ready(stage_i_ready),.i_data(stage_i_data),.i_meta(stage_i_meta),.i_dst_slice(stage_i_slice),
  .i_dst_tile(stage_i_tile),.i_dst_local(stage_i_local),.i_class(stage_i_class),.i_owner_id(stage_i_owner),.i_sop(stage_i_sop),
  .i_eop(stage_i_eop),.o_valid(stage_o_valid),.i_ready(stage_o_ready),.o_data(stage_o_data),.o_meta(stage_o_meta),
  .o_dst_slice(stage_o_slice),.o_dst_tile(stage_o_tile),.o_dst_local(stage_o_local),.o_class(stage_o_class),
  .o_owner_id(stage_o_owner),.o_sop(stage_o_sop),.o_eop(stage_o_eop),.o_account(stage_o_account),.o_token(stage_o_token),
  .i_release_valid(i_release_valid),.o_release_ready(o_release_ready),.i_release_token(i_release_token),.o_free(o_free),
  .o_issued(o_issued),.o_occupied(o_occupied),.o_quiescent(stage_idle),.o_error(stage_error),
  .o_return_malformed_event_level(o_return_malformed_event_level),
  .o_return_duplicate_event_level(o_return_duplicate_event_level),
  .o_return_stale_event_level(o_return_stale_event_level),
  .o_return_wrong_port_event_level(o_return_wrong_port_event_level));
 wire ignored_status=^{stage_o_slice,stage_o_owner[0+:C_LOCAL_REQUESTERS*C_CONTEXT_WIDTH]};
 assign o_quiescent=stage_idle&~(|resource_owner_valid_q);
 assign o_error=stage_error|ownership_error|reservation_underflow_error|(ignored_status&1'b0);
endmodule
`default_nettype wire
