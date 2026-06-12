`timescale 1ns/1ps
`default_nettype none
// Post-credit pairwise merge：每条Tile-bank lane在local与remote requester间独立RR，并把account/token送往Tile egress。
module switch_destination_local_remote_merge #(
 parameter integer C_LANES=32,parameter integer C_TILES=4,parameter integer C_BANK_LANES=8,
 parameter integer C_DATA_WIDTH=256,parameter integer C_META_WIDTH=128,parameter integer C_TILE_WIDTH=2,
 parameter integer C_CLASS_WIDTH=2,parameter integer C_VC_WIDTH=2,parameter integer C_ACCOUNT_WIDTH=12,
 parameter integer C_TOKEN_WIDTH=12,parameter integer C_NUM_CLASSES=4,parameter integer C_NUM_VC=4,
 parameter integer C_NUM_GROUPS=8,parameter integer C_GROUP_ID=0
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_LANES-1:0] i_local_valid,output reg [C_LANES-1:0] o_local_ready,
 input wire [C_LANES*C_DATA_WIDTH-1:0] i_local_data,input wire [C_LANES*C_META_WIDTH-1:0] i_local_meta,
 input wire [C_LANES*3-1:0] i_local_dst_group,input wire [C_LANES*C_TILE_WIDTH-1:0] i_local_dst_tile,
 input wire [C_LANES*5-1:0] i_local_dst_port,input wire [C_LANES*C_CLASS_WIDTH-1:0] i_local_class,
 input wire [C_LANES*C_VC_WIDTH-1:0] i_local_original_vc,input wire [C_LANES-1:0] i_local_pool,
 input wire [C_LANES*C_ACCOUNT_WIDTH-1:0] i_local_account,input wire [C_LANES*C_TOKEN_WIDTH-1:0] i_local_token,
 input wire [C_LANES-1:0] i_local_sop,input wire [C_LANES-1:0] i_local_eop,
 input wire [C_LANES-1:0] i_remote_valid,output reg [C_LANES-1:0] o_remote_ready,
 input wire [C_LANES*C_DATA_WIDTH-1:0] i_remote_data,input wire [C_LANES*C_META_WIDTH-1:0] i_remote_meta,
 input wire [C_LANES*3-1:0] i_remote_dst_group,input wire [C_LANES*C_TILE_WIDTH-1:0] i_remote_dst_tile,
 input wire [C_LANES*5-1:0] i_remote_dst_port,input wire [C_LANES*C_CLASS_WIDTH-1:0] i_remote_class,
 input wire [C_LANES*C_VC_WIDTH-1:0] i_remote_original_vc,input wire [C_LANES-1:0] i_remote_pool,
 input wire [C_LANES*C_ACCOUNT_WIDTH-1:0] i_remote_account,input wire [C_LANES*C_TOKEN_WIDTH-1:0] i_remote_token,
 input wire [C_LANES-1:0] i_remote_sop,input wire [C_LANES-1:0] i_remote_eop,
 output reg [C_LANES-1:0] o_valid,input wire [C_LANES-1:0] i_ready,
 output reg [C_LANES*C_DATA_WIDTH-1:0] o_data,output reg [C_LANES*C_META_WIDTH-1:0] o_meta,
 output reg [C_LANES*3-1:0] o_dst_group,output reg [C_LANES*C_TILE_WIDTH-1:0] o_dst_tile,
 output reg [C_LANES*5-1:0] o_dst_port,output reg [C_LANES*C_CLASS_WIDTH-1:0] o_class,
 output reg [C_LANES*C_VC_WIDTH-1:0] o_original_vc,output reg [C_LANES-1:0] o_pool,
 output reg [C_LANES*C_ACCOUNT_WIDTH-1:0] o_account,output reg [C_LANES*C_TOKEN_WIDTH-1:0] o_token,
 output reg [C_LANES-1:0] o_sop,output reg [C_LANES-1:0] o_eop,
 output wire o_config_error,output reg o_protocol_error,output wire o_error,output wire o_quiescent
);
 function can_encode;input integer width;input integer count;integer capacity;integer bit_index;begin capacity=1;for(bit_index=0;bit_index<width;bit_index=bit_index+1)capacity=capacity*2;can_encode=(width>=1)&&(width<=30)&&(count>=1)&&(capacity>=count);end endfunction
 localparam CONFIG_LEGAL=(C_LANES==C_TILES*C_BANK_LANES)&&(C_LANES>=1)&&(C_LANES<=32)&&(C_TILES>=1)&&(C_TILES<=4)&&(C_BANK_LANES>=1)&&(C_BANK_LANES<=8)&&can_encode(C_TILE_WIDTH,C_TILES)&&can_encode(C_CLASS_WIDTH,C_NUM_CLASSES)&&can_encode(C_VC_WIDTH,C_NUM_VC)&&(C_ACCOUNT_WIDTH>=1)&&(C_ACCOUNT_WIDTH<=30)&&(C_TOKEN_WIDTH>=1)&&(C_TOKEN_WIDTH<=30)&&(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&(C_GROUP_ID>=0)&&(C_GROUP_ID<C_NUM_GROUPS)&&(C_DATA_WIDTH>0)&&(C_META_WIDTH>0);
 localparam [2:0] C_GROUP_VALUE=C_GROUP_ID[2:0];
 reg [C_LANES-1:0] local_active_q,remote_active_q,owner_valid_q,owner_source_q,hold_valid_q,hold_source_q,rr_q;
 reg [C_LANES*3-1:0] local_group_q,remote_group_q;reg [C_LANES*C_TILE_WIDTH-1:0] local_tile_q,remote_tile_q;
 reg [C_LANES*5-1:0] local_port_q,remote_port_q;reg [C_LANES*C_CLASS_WIDTH-1:0] local_class_q,remote_class_q;
 reg [C_LANES*C_VC_WIDTH-1:0] local_vc_q,remote_vc_q;reg [C_LANES-1:0] local_pool_q,remote_pool_q;
 reg [C_LANES*C_ACCOUNT_WIDTH-1:0] local_account_q,remote_account_q;
 reg [C_LANES-1:0] local_legal,remote_legal,selected_valid,selected_source;
 integer lane_index,local_tile_value,local_port_value,local_class_value,local_vc_value,local_destination;
 integer remote_tile_value,remote_port_value,remote_class_value,remote_vc_value,remote_destination,state_lane;
 assign o_config_error=!CONFIG_LEGAL;assign o_error=o_config_error|o_protocol_error;
 assign o_quiescent=CONFIG_LEGAL&&!(|local_active_q)&&!(|remote_active_q)&&!(|owner_valid_q)&&!(|hold_valid_q);
 always @(*) begin
  local_legal=0;remote_legal=0;local_tile_value=0;local_port_value=0;local_class_value=0;local_vc_value=0;local_destination=0;remote_tile_value=0;remote_port_value=0;remote_class_value=0;remote_vc_value=0;remote_destination=0;
  for(lane_index=0;lane_index<C_LANES;lane_index=lane_index+1) begin
   if(local_active_q[lane_index])local_legal[lane_index]=!i_local_sop[lane_index]&&(i_local_dst_group[lane_index*3+:3]==local_group_q[lane_index*3+:3])&&(i_local_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH]==local_tile_q[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH])&&(i_local_dst_port[lane_index*5+:5]==local_port_q[lane_index*5+:5])&&(i_local_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]==local_class_q[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH])&&(i_local_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH]==local_vc_q[lane_index*C_VC_WIDTH+:C_VC_WIDTH])&&(i_local_pool[lane_index]==local_pool_q[lane_index])&&(i_local_account[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]==local_account_q[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]);
   else begin local_tile_value=0;local_port_value=0;local_class_value=0;local_vc_value=0;local_tile_value[C_TILE_WIDTH-1:0]=i_local_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH];local_port_value[4:0]=i_local_dst_port[lane_index*5+:5];local_class_value[C_CLASS_WIDTH-1:0]=i_local_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];local_vc_value[C_VC_WIDTH-1:0]=i_local_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH];local_destination=local_tile_value*C_BANK_LANES+(local_port_value%C_BANK_LANES);local_legal[lane_index]=i_local_sop[lane_index]&&(i_local_dst_group[lane_index*3+:3]==C_GROUP_VALUE)&&(local_tile_value<C_TILES)&&(local_class_value<C_NUM_CLASSES)&&(local_vc_value<C_NUM_VC)&&(local_destination==lane_index);end
   if(remote_active_q[lane_index])remote_legal[lane_index]=!i_remote_sop[lane_index]&&(i_remote_dst_group[lane_index*3+:3]==remote_group_q[lane_index*3+:3])&&(i_remote_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH]==remote_tile_q[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH])&&(i_remote_dst_port[lane_index*5+:5]==remote_port_q[lane_index*5+:5])&&(i_remote_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]==remote_class_q[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH])&&(i_remote_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH]==remote_vc_q[lane_index*C_VC_WIDTH+:C_VC_WIDTH])&&(i_remote_pool[lane_index]==remote_pool_q[lane_index])&&(i_remote_account[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]==remote_account_q[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]);
   else begin remote_tile_value=0;remote_port_value=0;remote_class_value=0;remote_vc_value=0;remote_tile_value[C_TILE_WIDTH-1:0]=i_remote_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH];remote_port_value[4:0]=i_remote_dst_port[lane_index*5+:5];remote_class_value[C_CLASS_WIDTH-1:0]=i_remote_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];remote_vc_value[C_VC_WIDTH-1:0]=i_remote_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH];remote_destination=remote_tile_value*C_BANK_LANES+(remote_port_value%C_BANK_LANES);remote_legal[lane_index]=i_remote_sop[lane_index]&&(i_remote_dst_group[lane_index*3+:3]==C_GROUP_VALUE)&&(remote_tile_value<C_TILES)&&(remote_class_value<C_NUM_CLASSES)&&(remote_vc_value<C_NUM_VC)&&(remote_destination==lane_index);end
  end
 end
 always @(*) begin
  o_local_ready=0;o_remote_ready=0;o_valid=0;o_data=0;o_meta=0;o_dst_group=0;o_dst_tile=0;o_dst_port=0;o_class=0;o_original_vc=0;o_pool=0;o_account=0;o_token=0;o_sop=0;o_eop=0;selected_valid=0;selected_source=0;
  for(lane_index=0;lane_index<C_LANES;lane_index=lane_index+1) begin
   if(owner_valid_q[lane_index])begin selected_valid[lane_index]=1'b1;selected_source[lane_index]=owner_source_q[lane_index];end
   else if(hold_valid_q[lane_index])begin selected_valid[lane_index]=1'b1;selected_source[lane_index]=hold_source_q[lane_index];end
   else if(i_local_valid[lane_index]&&local_legal[lane_index]&&i_remote_valid[lane_index]&&remote_legal[lane_index])begin selected_valid[lane_index]=1'b1;selected_source[lane_index]=rr_q[lane_index];end
   else if(i_local_valid[lane_index]&&local_legal[lane_index])begin selected_valid[lane_index]=1'b1;selected_source[lane_index]=1'b0;end
   else if(i_remote_valid[lane_index]&&remote_legal[lane_index])begin selected_valid[lane_index]=1'b1;selected_source[lane_index]=1'b1;end
   if(selected_valid[lane_index]&&!selected_source[lane_index])begin o_valid[lane_index]=i_local_valid[lane_index]&&local_legal[lane_index]&&CONFIG_LEGAL;o_data[lane_index*C_DATA_WIDTH+:C_DATA_WIDTH]=i_local_data[lane_index*C_DATA_WIDTH+:C_DATA_WIDTH];o_meta[lane_index*C_META_WIDTH+:C_META_WIDTH]=i_local_meta[lane_index*C_META_WIDTH+:C_META_WIDTH];o_dst_group[lane_index*3+:3]=i_local_dst_group[lane_index*3+:3];o_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH]=i_local_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH];o_dst_port[lane_index*5+:5]=i_local_dst_port[lane_index*5+:5];o_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]=i_local_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];o_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH]=i_local_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH];o_pool[lane_index]=i_local_pool[lane_index];o_account[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]=i_local_account[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];o_token[lane_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]=i_local_token[lane_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];o_sop[lane_index]=i_local_sop[lane_index];o_eop[lane_index]=i_local_eop[lane_index];o_local_ready[lane_index]=o_valid[lane_index]&&i_ready[lane_index];end
   else if(selected_valid[lane_index])begin o_valid[lane_index]=i_remote_valid[lane_index]&&remote_legal[lane_index]&&CONFIG_LEGAL;o_data[lane_index*C_DATA_WIDTH+:C_DATA_WIDTH]=i_remote_data[lane_index*C_DATA_WIDTH+:C_DATA_WIDTH];o_meta[lane_index*C_META_WIDTH+:C_META_WIDTH]=i_remote_meta[lane_index*C_META_WIDTH+:C_META_WIDTH];o_dst_group[lane_index*3+:3]=i_remote_dst_group[lane_index*3+:3];o_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH]=i_remote_dst_tile[lane_index*C_TILE_WIDTH+:C_TILE_WIDTH];o_dst_port[lane_index*5+:5]=i_remote_dst_port[lane_index*5+:5];o_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]=i_remote_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];o_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH]=i_remote_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH];o_pool[lane_index]=i_remote_pool[lane_index];o_account[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]=i_remote_account[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];o_token[lane_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]=i_remote_token[lane_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];o_sop[lane_index]=i_remote_sop[lane_index];o_eop[lane_index]=i_remote_eop[lane_index];o_remote_ready[lane_index]=o_valid[lane_index]&&i_ready[lane_index];end
  end
  if(!i_rstn||!CONFIG_LEGAL)begin o_valid=0;o_local_ready=0;o_remote_ready=0;end
 end
 always @(posedge i_clk) begin
  if(!i_rstn)begin local_active_q<=0;remote_active_q<=0;owner_valid_q<=0;owner_source_q<=0;hold_valid_q<=0;hold_source_q<=0;rr_q<=0;o_protocol_error<=0;local_group_q<=0;remote_group_q<=0;local_tile_q<=0;remote_tile_q<=0;local_port_q<=0;remote_port_q<=0;local_class_q<=0;remote_class_q<=0;local_vc_q<=0;remote_vc_q<=0;local_pool_q<=0;remote_pool_q<=0;local_account_q<=0;remote_account_q<=0;end
  else begin
   if(!CONFIG_LEGAL)o_protocol_error<=1'b1;
   for(state_lane=0;state_lane<C_LANES;state_lane=state_lane+1)begin
    if(i_local_valid[state_lane]&&!local_legal[state_lane])o_protocol_error<=1'b1;if(i_remote_valid[state_lane]&&!remote_legal[state_lane])o_protocol_error<=1'b1;
    if(o_local_ready[state_lane])begin if(!local_active_q[state_lane])begin local_active_q[state_lane]<=!i_local_eop[state_lane];local_group_q[state_lane*3+:3]<=i_local_dst_group[state_lane*3+:3];local_tile_q[state_lane*C_TILE_WIDTH+:C_TILE_WIDTH]<=i_local_dst_tile[state_lane*C_TILE_WIDTH+:C_TILE_WIDTH];local_port_q[state_lane*5+:5]<=i_local_dst_port[state_lane*5+:5];local_class_q[state_lane*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_local_class[state_lane*C_CLASS_WIDTH+:C_CLASS_WIDTH];local_vc_q[state_lane*C_VC_WIDTH+:C_VC_WIDTH]<=i_local_original_vc[state_lane*C_VC_WIDTH+:C_VC_WIDTH];local_pool_q[state_lane]<=i_local_pool[state_lane];local_account_q[state_lane*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=i_local_account[state_lane*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];end else if(i_local_eop[state_lane])local_active_q[state_lane]<=1'b0;end
    if(o_remote_ready[state_lane])begin if(!remote_active_q[state_lane])begin remote_active_q[state_lane]<=!i_remote_eop[state_lane];remote_group_q[state_lane*3+:3]<=i_remote_dst_group[state_lane*3+:3];remote_tile_q[state_lane*C_TILE_WIDTH+:C_TILE_WIDTH]<=i_remote_dst_tile[state_lane*C_TILE_WIDTH+:C_TILE_WIDTH];remote_port_q[state_lane*5+:5]<=i_remote_dst_port[state_lane*5+:5];remote_class_q[state_lane*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_remote_class[state_lane*C_CLASS_WIDTH+:C_CLASS_WIDTH];remote_vc_q[state_lane*C_VC_WIDTH+:C_VC_WIDTH]<=i_remote_original_vc[state_lane*C_VC_WIDTH+:C_VC_WIDTH];remote_pool_q[state_lane]<=i_remote_pool[state_lane];remote_account_q[state_lane*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=i_remote_account[state_lane*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];end else if(i_remote_eop[state_lane])remote_active_q[state_lane]<=1'b0;end
    if(owner_valid_q[state_lane])begin if(o_valid[state_lane]&&i_ready[state_lane]&&o_eop[state_lane])begin owner_valid_q[state_lane]<=1'b0;rr_q[state_lane]<=~owner_source_q[state_lane];end end
    else if(hold_valid_q[state_lane])begin if(o_valid[state_lane]&&i_ready[state_lane])begin hold_valid_q[state_lane]<=1'b0;if(o_eop[state_lane])rr_q[state_lane]<=~hold_source_q[state_lane];else begin owner_valid_q[state_lane]<=1'b1;owner_source_q[state_lane]<=hold_source_q[state_lane];end end end
    else if(selected_valid[state_lane]&&o_valid[state_lane])begin if(!i_ready[state_lane])begin hold_valid_q[state_lane]<=1'b1;hold_source_q[state_lane]<=selected_source[state_lane];end else if(o_eop[state_lane])rr_q[state_lane]<=~selected_source[state_lane];else begin owner_valid_q[state_lane]<=1'b1;owner_source_q[state_lane]<=selected_source[state_lane];end end
   end
  end
 end
endmodule
`default_nettype wire
