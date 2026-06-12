`timescale 1ns/1ps
`default_nettype none
// Destination Group将Core plane分发到Tile×bank lane；account仅透明携带，真实credit仍归下游ledger。
module switch_destination_group_multi_lane #(
 parameter integer C_PLANES=32,parameter integer C_TILES=4,parameter integer C_BANK_LANES=8,
 parameter integer C_DATA_WIDTH=256,parameter integer C_META_WIDTH=128,
 parameter integer C_TILE_WIDTH=2,parameter integer C_CLASS_WIDTH=2,
 parameter integer C_COUNT_WIDTH=5,parameter integer C_ACCOUNT_WIDTH=12,
 parameter integer C_PLANE_WIDTH=5,parameter integer C_NUM_CLASSES=4,
 parameter integer C_NUM_GROUPS=8,parameter integer C_GROUP_ID=0
)(
 input wire i_clk,input wire i_rstn,input wire [C_PLANES-1:0] i_valid,output reg [C_PLANES-1:0] o_ready,
 input wire [C_PLANES*C_DATA_WIDTH-1:0] i_data,input wire [C_PLANES*C_META_WIDTH-1:0] i_meta,
 input wire [C_PLANES*3-1:0] i_dst_group,input wire [C_PLANES*C_TILE_WIDTH-1:0] i_dst_tile,
 input wire [C_PLANES*5-1:0] i_dst_port,input wire [C_PLANES*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_PLANES*C_COUNT_WIDTH-1:0] i_packet_flits,input wire [C_PLANES*C_ACCOUNT_WIDTH-1:0] i_account,
 input wire [C_PLANES-1:0] i_sop,input wire [C_PLANES-1:0] i_eop,
 output reg [C_TILES*C_BANK_LANES-1:0] o_valid,input wire [C_TILES*C_BANK_LANES-1:0] i_ready,
 output reg [C_TILES*C_BANK_LANES*C_DATA_WIDTH-1:0] o_data,
 output reg [C_TILES*C_BANK_LANES*C_META_WIDTH-1:0] o_meta,
 output reg [C_TILES*C_BANK_LANES*3-1:0] o_dst_group,
 output reg [C_TILES*C_BANK_LANES*C_TILE_WIDTH-1:0] o_dst_tile,
 output reg [C_TILES*C_BANK_LANES*5-1:0] o_dst_port,
 output reg [C_TILES*C_BANK_LANES*C_CLASS_WIDTH-1:0] o_class,
 output reg [C_TILES*C_BANK_LANES*C_COUNT_WIDTH-1:0] o_packet_flits,
 output reg [C_TILES*C_BANK_LANES*C_ACCOUNT_WIDTH-1:0] o_account,
 output reg [C_TILES*C_BANK_LANES-1:0] o_sop,output reg [C_TILES*C_BANK_LANES-1:0] o_eop,
 output wire o_config_error,output reg o_protocol_error,output wire o_error,output wire o_quiescent
);
 localparam integer C_OUTPUTS=C_TILES*C_BANK_LANES;
 localparam [C_PLANE_WIDTH-1:0] C_LAST_PLANE=C_PLANES[C_PLANE_WIDTH-1:0]-1'b1;
 function can_encode;
  input integer width;input integer count;integer capacity;integer bit_index;
  begin capacity=1;for(bit_index=0;bit_index<width;bit_index=bit_index+1)capacity=capacity*2;
   can_encode=(width>=1)&&(width<=30)&&(count>=1)&&(capacity>=count);end
 endfunction
 localparam CONFIG_LEGAL=(C_PLANES>=1)&&(C_PLANES<=32)&&(C_TILES>=1)&&(C_TILES<=4)&&
  (C_BANK_LANES>=1)&&(C_BANK_LANES<=8)&&(C_NUM_CLASSES>=1)&&(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&
  can_encode(C_PLANE_WIDTH,C_PLANES)&&can_encode(C_TILE_WIDTH,C_TILES)&&
  can_encode(C_CLASS_WIDTH,C_NUM_CLASSES)&&(C_COUNT_WIDTH>=1)&&(C_COUNT_WIDTH<=30)&&
  (C_ACCOUNT_WIDTH>=1)&&(C_ACCOUNT_WIDTH<=30)&&(C_DATA_WIDTH>0)&&(C_META_WIDTH>0)&&
  (C_GROUP_ID>=0)&&(C_GROUP_ID<C_NUM_GROUPS);
 reg [C_PLANES-1:0] input_active_q;reg [C_PLANES*C_COUNT_WIDTH-1:0] input_remaining_q;
 reg [C_PLANES*3-1:0] input_group_q;reg [C_PLANES*C_TILE_WIDTH-1:0] input_tile_q;
 reg [C_PLANES*5-1:0] input_port_q;reg [C_PLANES*C_CLASS_WIDTH-1:0] input_class_q;
 reg [C_PLANES*C_ACCOUNT_WIDTH-1:0] input_account_q;
 reg [C_OUTPUTS-1:0] owner_valid_q,hold_valid_q,selected_valid;
 reg [C_PLANE_WIDTH-1:0] owner_plane_q [0:C_OUTPUTS-1];
 reg [C_PLANE_WIDTH-1:0] hold_plane_q [0:C_OUTPUTS-1];
 reg [C_PLANE_WIDTH-1:0] rr_q [0:C_OUTPUTS-1];
 reg [C_PLANE_WIDTH-1:0] selected_plane [0:C_OUTPUTS-1];
 reg [C_PLANES-1:0] input_legal;integer legal_index,output_index,scan_index,plane_value,destination_value,state_input;
 integer legal_group_value,legal_tile_value,legal_class_value,route_tile_value,route_port_value;
 genvar state_output;
 assign o_config_error=!CONFIG_LEGAL;assign o_error=o_config_error|o_protocol_error;
 assign o_quiescent=CONFIG_LEGAL&&!(|input_active_q)&&!(|owner_valid_q)&&!(|hold_valid_q);
 // 输入相位检查同时锁定packet的route/class/account，畸形拍不会参与仲裁。
 always @(*)begin
  input_legal={C_PLANES{1'b0}};legal_group_value=0;legal_tile_value=0;legal_class_value=0;
  for(legal_index=0;legal_index<C_PLANES;legal_index=legal_index+1)begin
   if(input_active_q[legal_index])input_legal[legal_index]=!i_sop[legal_index]&&
    (i_packet_flits[legal_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]==0)&&
    (i_dst_group[legal_index*3+:3]==input_group_q[legal_index*3+:3])&&
    (i_dst_tile[legal_index*C_TILE_WIDTH+:C_TILE_WIDTH]==input_tile_q[legal_index*C_TILE_WIDTH+:C_TILE_WIDTH])&&
    (i_dst_port[legal_index*5+:5]==input_port_q[legal_index*5+:5])&&
    (i_class[legal_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]==input_class_q[legal_index*C_CLASS_WIDTH+:C_CLASS_WIDTH])&&
    (i_account[legal_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]==input_account_q[legal_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH])&&
    ((input_remaining_q[legal_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]==1)==i_eop[legal_index]);
   else begin
    legal_group_value=0;legal_tile_value=0;legal_class_value=0;
    legal_group_value[2:0]=i_dst_group[legal_index*3+:3];
    legal_tile_value[C_TILE_WIDTH-1:0]=i_dst_tile[legal_index*C_TILE_WIDTH+:C_TILE_WIDTH];
    legal_class_value[C_CLASS_WIDTH-1:0]=i_class[legal_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];
    input_legal[legal_index]=i_sop[legal_index]&&(legal_group_value<C_NUM_GROUPS)&&(legal_group_value==C_GROUP_ID)&&
    (legal_tile_value<C_TILES)&&(legal_class_value<C_NUM_CLASSES)&&
    (i_packet_flits[legal_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]!=0)&&
    ((i_packet_flits[legal_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]==1)==i_eop[legal_index]);
   end
  end
 end
 always @(*)begin
  o_ready={C_PLANES{1'b0}};o_valid={C_OUTPUTS{1'b0}};o_data={(C_OUTPUTS*C_DATA_WIDTH){1'b0}};
  o_meta={(C_OUTPUTS*C_META_WIDTH){1'b0}};o_dst_group={(C_OUTPUTS*3){1'b0}};
  o_dst_tile={(C_OUTPUTS*C_TILE_WIDTH){1'b0}};o_dst_port={(C_OUTPUTS*5){1'b0}};
  o_class={(C_OUTPUTS*C_CLASS_WIDTH){1'b0}};o_packet_flits={(C_OUTPUTS*C_COUNT_WIDTH){1'b0}};
  o_account={(C_OUTPUTS*C_ACCOUNT_WIDTH){1'b0}};o_sop={C_OUTPUTS{1'b0}};o_eop={C_OUTPUTS{1'b0}};
  selected_valid={C_OUTPUTS{1'b0}};scan_index=0;plane_value=0;destination_value=0;route_port_value=0;route_tile_value=0;
  for(output_index=0;output_index<C_OUTPUTS;output_index=output_index+1)begin
   selected_plane[output_index]={C_PLANE_WIDTH{1'b0}};
   if(owner_valid_q[output_index])begin selected_valid[output_index]=1'b1;selected_plane[output_index]=owner_plane_q[output_index];end
   else if(hold_valid_q[output_index])begin selected_valid[output_index]=1'b1;selected_plane[output_index]=hold_plane_q[output_index];end
   else for(scan_index=0;scan_index<C_PLANES;scan_index=scan_index+1)begin
    plane_value=0;plane_value[C_PLANE_WIDTH-1:0]=rr_q[output_index];plane_value=plane_value+scan_index;
    if(plane_value>=C_PLANES)plane_value=plane_value-C_PLANES;
    route_tile_value=0;route_port_value=0;
    route_tile_value[C_TILE_WIDTH-1:0]=i_dst_tile[plane_value*C_TILE_WIDTH+:C_TILE_WIDTH];
    route_port_value[4:0]=i_dst_port[plane_value*5+:5];
    destination_value=route_tile_value*C_BANK_LANES+(route_port_value%C_BANK_LANES);
    if(!selected_valid[output_index]&&i_valid[plane_value]&&input_legal[plane_value]&&i_sop[plane_value]&&destination_value==output_index)begin selected_valid[output_index]=1'b1;selected_plane[output_index]=plane_value[C_PLANE_WIDTH-1:0];end
   end
   if(selected_valid[output_index])begin
    o_valid[output_index]=i_valid[selected_plane[output_index]]&&input_legal[selected_plane[output_index]]&&CONFIG_LEGAL;
    o_data[output_index*C_DATA_WIDTH+:C_DATA_WIDTH]=i_data[selected_plane[output_index]*C_DATA_WIDTH+:C_DATA_WIDTH];
    o_meta[output_index*C_META_WIDTH+:C_META_WIDTH]=i_meta[selected_plane[output_index]*C_META_WIDTH+:C_META_WIDTH];
    o_dst_group[output_index*3+:3]=i_dst_group[selected_plane[output_index]*3+:3];
    o_dst_tile[output_index*C_TILE_WIDTH+:C_TILE_WIDTH]=i_dst_tile[selected_plane[output_index]*C_TILE_WIDTH+:C_TILE_WIDTH];
    o_dst_port[output_index*5+:5]=i_dst_port[selected_plane[output_index]*5+:5];
    o_class[output_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]=i_class[selected_plane[output_index]*C_CLASS_WIDTH+:C_CLASS_WIDTH];
    o_packet_flits[output_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=i_packet_flits[selected_plane[output_index]*C_COUNT_WIDTH+:C_COUNT_WIDTH];
    o_account[output_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]=i_account[selected_plane[output_index]*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];
    o_sop[output_index]=i_sop[selected_plane[output_index]];o_eop[output_index]=i_eop[selected_plane[output_index]];
    o_ready[selected_plane[output_index]]=i_ready[output_index]&&o_valid[output_index];
   end
  end
  if(!i_rstn||!CONFIG_LEGAL)begin o_valid={C_OUTPUTS{1'b0}};o_ready={C_PLANES{1'b0}};end
 end
 generate for(state_output=0;state_output<C_OUTPUTS;state_output=state_output+1)begin:g_output_owner
  always @(posedge i_clk)begin
   if(!i_rstn)begin owner_valid_q[state_output]<=1'b0;hold_valid_q[state_output]<=1'b0;owner_plane_q[state_output]<={C_PLANE_WIDTH{1'b0}};hold_plane_q[state_output]<={C_PLANE_WIDTH{1'b0}};rr_q[state_output]<={C_PLANE_WIDTH{1'b0}};end
   else if(owner_valid_q[state_output])begin if(o_valid[state_output]&&i_ready[state_output]&&o_eop[state_output])begin owner_valid_q[state_output]<=1'b0;if(owner_plane_q[state_output]==C_LAST_PLANE)rr_q[state_output]<={C_PLANE_WIDTH{1'b0}};else rr_q[state_output]<=owner_plane_q[state_output]+1'b1;end end
   else if(hold_valid_q[state_output])begin if(o_valid[state_output]&&i_ready[state_output])begin hold_valid_q[state_output]<=1'b0;if(o_eop[state_output])begin if(hold_plane_q[state_output]==C_LAST_PLANE)rr_q[state_output]<={C_PLANE_WIDTH{1'b0}};else rr_q[state_output]<=hold_plane_q[state_output]+1'b1;end else begin owner_valid_q[state_output]<=1'b1;owner_plane_q[state_output]<=hold_plane_q[state_output];end end end
   else if(selected_valid[state_output]&&o_valid[state_output])begin if(!i_ready[state_output])begin hold_valid_q[state_output]<=1'b1;hold_plane_q[state_output]<=selected_plane[state_output];end else if(o_eop[state_output])begin if(selected_plane[state_output]==C_LAST_PLANE)rr_q[state_output]<={C_PLANE_WIDTH{1'b0}};else rr_q[state_output]<=selected_plane[state_output]+1'b1;end else begin owner_valid_q[state_output]<=1'b1;owner_plane_q[state_output]<=selected_plane[state_output];end end
  end
 end endgenerate
 always @(posedge i_clk)begin
  if(!i_rstn)begin o_protocol_error<=1'b0;input_active_q<={C_PLANES{1'b0}};input_remaining_q<={(C_PLANES*C_COUNT_WIDTH){1'b0}};input_group_q<={(C_PLANES*3){1'b0}};input_tile_q<={(C_PLANES*C_TILE_WIDTH){1'b0}};input_port_q<={(C_PLANES*5){1'b0}};input_class_q<={(C_PLANES*C_CLASS_WIDTH){1'b0}};input_account_q<={(C_PLANES*C_ACCOUNT_WIDTH){1'b0}};end
  else begin
   if(!CONFIG_LEGAL)o_protocol_error<=1'b1;
   for(state_input=0;state_input<C_PLANES;state_input=state_input+1)begin
    if(i_valid[state_input]&&!input_legal[state_input])o_protocol_error<=1'b1;
    if(i_valid[state_input]&&o_ready[state_input])begin
     if(!input_active_q[state_input])begin input_active_q[state_input]<=!i_eop[state_input];input_remaining_q[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]<=i_packet_flits[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]-1'b1;input_group_q[state_input*3+:3]<=i_dst_group[state_input*3+:3];input_tile_q[state_input*C_TILE_WIDTH+:C_TILE_WIDTH]<=i_dst_tile[state_input*C_TILE_WIDTH+:C_TILE_WIDTH];input_port_q[state_input*5+:5]<=i_dst_port[state_input*5+:5];input_class_q[state_input*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_class[state_input*C_CLASS_WIDTH+:C_CLASS_WIDTH];input_account_q[state_input*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=i_account[state_input*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];end
     else if(i_eop[state_input])begin input_active_q[state_input]<=1'b0;input_remaining_q[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]<={C_COUNT_WIDTH{1'b0}};end
     else input_remaining_q[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]<=input_remaining_q[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]-1'b1;
    end
   end
  end
 end
endmodule
`default_nettype wire
