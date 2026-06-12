`timescale 1ns/1ps
`default_nettype none
// Source Group多lane汇聚；local保持Tile×bank并行，cross选择Core plane。
// 每个source在SOP真实接纳时冻结路径和route，直到EOP真实接纳；本模块不拥有credit账本。
module switch_group_multi_lane #(
 parameter integer C_TILES=4,parameter integer C_BANK_LANES=8,parameter integer C_PLANES=32,
 parameter integer C_DATA_WIDTH=256,parameter integer C_META_WIDTH=128,
 parameter integer C_TILE_WIDTH=2,parameter integer C_SOURCE_WIDTH=5,
 parameter integer C_GROUP_ID=0,parameter integer C_NUM_GROUPS=8
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_TILES*C_BANK_LANES-1:0] i_local_valid,output reg [C_TILES*C_BANK_LANES-1:0] o_local_ready,
 input wire [C_TILES*C_BANK_LANES*C_DATA_WIDTH-1:0] i_local_data,
 input wire [C_TILES*C_BANK_LANES*C_META_WIDTH-1:0] i_local_meta,
 input wire [C_TILES*C_BANK_LANES*3-1:0] i_local_dst_group,
 input wire [C_TILES*C_BANK_LANES*C_TILE_WIDTH-1:0] i_local_dst_tile,
 input wire [C_TILES*C_BANK_LANES*5-1:0] i_local_dst_port,
 input wire [C_TILES*C_BANK_LANES-1:0] i_local_sop,input wire [C_TILES*C_BANK_LANES-1:0] i_local_eop,
 input wire [C_TILES*C_BANK_LANES-1:0] i_core_valid,output wire [C_TILES*C_BANK_LANES-1:0] o_core_ready,
 input wire [C_TILES*C_BANK_LANES*C_DATA_WIDTH-1:0] i_core_data,
 input wire [C_TILES*C_BANK_LANES*C_META_WIDTH-1:0] i_core_meta,
 input wire [C_TILES*C_BANK_LANES*3-1:0] i_core_dst_group,
 input wire [C_TILES*C_BANK_LANES*C_TILE_WIDTH-1:0] i_core_dst_tile,
 input wire [C_TILES*C_BANK_LANES*5-1:0] i_core_dst_port,
 input wire [C_TILES*C_BANK_LANES-1:0] i_core_sop,input wire [C_TILES*C_BANK_LANES-1:0] i_core_eop,
 input wire [C_TILES*C_BANK_LANES*C_PLANES-1:0] i_plane_eligible,
 output reg [C_TILES*C_BANK_LANES-1:0] o_local_lane_valid,
 input wire [C_TILES*C_BANK_LANES-1:0] i_local_lane_ready,
 output reg [C_TILES*C_BANK_LANES*C_DATA_WIDTH-1:0] o_local_lane_data,
 output reg [C_TILES*C_BANK_LANES*C_META_WIDTH-1:0] o_local_lane_meta,
 output reg [C_TILES*C_BANK_LANES*3-1:0] o_local_lane_dst_group,
 output reg [C_TILES*C_BANK_LANES*C_TILE_WIDTH-1:0] o_local_lane_dst_tile,
 output reg [C_TILES*C_BANK_LANES*5-1:0] o_local_lane_dst_port,
 output reg [C_TILES*C_BANK_LANES-1:0] o_local_lane_sop,output reg [C_TILES*C_BANK_LANES-1:0] o_local_lane_eop,
 output wire [C_PLANES-1:0] o_plane_valid,input wire [C_PLANES-1:0] i_plane_ready,
 output wire [C_PLANES*C_DATA_WIDTH-1:0] o_plane_data,
 output wire [C_PLANES*C_META_WIDTH-1:0] o_plane_meta,
 output wire [C_PLANES*3-1:0] o_plane_dst_group,
 output wire [C_PLANES*C_TILE_WIDTH-1:0] o_plane_dst_tile,
 output wire [C_PLANES*5-1:0] o_plane_dst_port,
 output wire [C_PLANES-1:0] o_plane_sop,output wire [C_PLANES-1:0] o_plane_eop,
 output wire o_config_error,output wire o_error,output wire o_quiescent
);
 localparam integer C_SOURCES=C_TILES*C_BANK_LANES;
 localparam integer C_CORE_META_WIDTH=C_META_WIDTH+3+C_TILE_WIDTH+5;
 localparam [C_SOURCE_WIDTH-1:0] C_LAST_SOURCE=C_SOURCES[C_SOURCE_WIDTH-1:0]-1'b1;
 localparam CONFIG_LEGAL=(C_TILES>=1)&&(C_TILES<=4)&&(C_BANK_LANES>=1)&&(C_BANK_LANES<=8)&&
  (C_PLANES>=1)&&(C_PLANES<=32)&&(C_DATA_WIDTH>=1)&&(C_META_WIDTH>=1)&&
  (C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&(C_GROUP_ID>=0)&&(C_GROUP_ID<C_NUM_GROUPS)&&
  (C_TILE_WIDTH>=1)&&(C_TILE_WIDTH<=30)&&(C_SOURCE_WIDTH>=1)&&(C_SOURCE_WIDTH<=30)&&
  ((32'd1<<C_SOURCE_WIDTH)>=C_SOURCES)&&((32'd1<<C_TILE_WIDTH)>=C_TILES);

 // source级context是local/Core之间唯一packet路径owner。
 reg [C_SOURCES-1:0] packet_active_q,path_core_q;
 reg [2:0] packet_group_q[0:C_SOURCES-1];
 reg [C_TILE_WIDTH-1:0] packet_tile_q[0:C_SOURCES-1];
 reg [4:0] packet_port_q[0:C_SOURCES-1];
 wire [C_SOURCES-1:0] local_route_legal,core_route_legal,local_packet_legal,core_packet_legal;
 wire [C_SOURCES-1:0] local_valid_masked,core_valid_masked,local_fire,core_fire;
 wire [C_SOURCES-1:0] plane_source_ready;
 wire [C_SOURCES*3-1:0] local_group,core_group;
 wire [C_SOURCES*C_TILE_WIDTH-1:0] local_tile,core_tile;
 wire [C_SOURCES*5-1:0] local_port,core_port;

 // local目的lane各自保存仲裁owner；source_claimed禁止同源同拍复制。
 reg [C_SOURCES-1:0] selected_valid,source_claimed,owner_valid_q,hold_valid_q;
 reg [C_SOURCE_WIDTH-1:0] selected_source[0:C_SOURCES-1];
 reg [C_SOURCE_WIDTH-1:0] owner_source_q[0:C_SOURCES-1];
 reg [C_SOURCE_WIDTH-1:0] hold_source_q[0:C_SOURCES-1];
 reg [C_SOURCE_WIDTH-1:0] rr_q[0:C_SOURCES-1];
 reg protocol_error_q;
 wire plane_quiescent;
 wire [C_SOURCES*C_CORE_META_WIDTH-1:0] core_packed_in;
 wire [C_PLANES*C_CORE_META_WIDTH-1:0] core_packed_out;
 integer dst_index,scan_index,source_value,destination_value,ready_index,claim_index;
 integer protocol_index,packet_index;
 genvar source_gen,plane_gen,state_gen;

 generate for(source_gen=0;source_gen<C_SOURCES;source_gen=source_gen+1)begin:g_source
  assign local_route_legal[source_gen]=
   (i_local_dst_group[source_gen*3+:3]==C_GROUP_ID[2:0])&&
   ({{(32-C_TILE_WIDTH){1'b0}},i_local_dst_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH]}<C_TILES);
  assign core_route_legal[source_gen]=
   ({{29{1'b0}},i_core_dst_group[source_gen*3+:3]}<C_NUM_GROUPS)&&
   (i_core_dst_group[source_gen*3+:3]!=C_GROUP_ID[2:0])&&
   ({{(32-C_TILE_WIDTH){1'b0}},i_core_dst_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH]}<C_TILES);
  assign local_packet_legal[source_gen]=packet_active_q[source_gen]?
   (!path_core_q[source_gen]&&!i_local_sop[source_gen]&&
    i_local_dst_group[source_gen*3+:3]==packet_group_q[source_gen]&&
    i_local_dst_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH]==packet_tile_q[source_gen]&&
    i_local_dst_port[source_gen*5+:5]==packet_port_q[source_gen]):i_local_sop[source_gen];
  assign core_packet_legal[source_gen]=packet_active_q[source_gen]?
   (path_core_q[source_gen]&&!i_core_sop[source_gen]&&
    i_core_dst_group[source_gen*3+:3]==packet_group_q[source_gen]&&
    i_core_dst_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH]==packet_tile_q[source_gen]&&
    i_core_dst_port[source_gen*5+:5]==packet_port_q[source_gen]):i_core_sop[source_gen];
  assign local_group[source_gen*3+:3]=packet_active_q[source_gen]?packet_group_q[source_gen]:i_local_dst_group[source_gen*3+:3];
  assign local_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH]=packet_active_q[source_gen]?packet_tile_q[source_gen]:i_local_dst_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH];
  assign local_port[source_gen*5+:5]=packet_active_q[source_gen]?packet_port_q[source_gen]:i_local_dst_port[source_gen*5+:5];
  assign core_group[source_gen*3+:3]=packet_active_q[source_gen]?packet_group_q[source_gen]:i_core_dst_group[source_gen*3+:3];
  assign core_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH]=packet_active_q[source_gen]?packet_tile_q[source_gen]:i_core_dst_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH];
  assign core_port[source_gen*5+:5]=packet_active_q[source_gen]?packet_port_q[source_gen]:i_core_dst_port[source_gen*5+:5];
  assign core_packed_in[source_gen*C_CORE_META_WIDTH+:C_CORE_META_WIDTH]=
   {core_port[source_gen*5+:5],core_tile[source_gen*C_TILE_WIDTH+:C_TILE_WIDTH],
    core_group[source_gen*3+:3],i_core_meta[source_gen*C_META_WIDTH+:C_META_WIDTH]};
 end endgenerate
 assign local_valid_masked=i_local_valid&~i_core_valid&local_route_legal&local_packet_legal&{C_SOURCES{CONFIG_LEGAL}};
 assign core_valid_masked=i_core_valid&~i_local_valid&core_route_legal&core_packet_legal&{C_SOURCES{CONFIG_LEGAL}};
 assign local_fire=local_valid_masked&o_local_ready;
 assign core_fire=core_valid_masked&o_core_ready;
 assign o_core_ready=plane_source_ready&core_valid_masked;
 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error|protocol_error_q;

 always @(*)begin
  o_local_ready={C_SOURCES{1'b0}};o_local_lane_valid={C_SOURCES{1'b0}};
  o_local_lane_data={(C_SOURCES*C_DATA_WIDTH){1'b0}};o_local_lane_meta={(C_SOURCES*C_META_WIDTH){1'b0}};
  o_local_lane_dst_group={(C_SOURCES*3){1'b0}};o_local_lane_dst_tile={(C_SOURCES*C_TILE_WIDTH){1'b0}};
  o_local_lane_dst_port={(C_SOURCES*5){1'b0}};o_local_lane_sop={C_SOURCES{1'b0}};o_local_lane_eop={C_SOURCES{1'b0}};
  selected_valid={C_SOURCES{1'b0}};source_claimed={C_SOURCES{1'b0}};
  scan_index=0;source_value=0;destination_value=0;
  for(claim_index=0;claim_index<C_SOURCES;claim_index=claim_index+1)begin
   if(owner_valid_q[claim_index])source_claimed[owner_source_q[claim_index]]=1'b1;
   if(hold_valid_q[claim_index])source_claimed[hold_source_q[claim_index]]=1'b1;
  end
  for(dst_index=0;dst_index<C_SOURCES;dst_index=dst_index+1)begin
   selected_source[dst_index]={C_SOURCE_WIDTH{1'b0}};
   if(owner_valid_q[dst_index])begin selected_valid[dst_index]=1'b1;selected_source[dst_index]=owner_source_q[dst_index];end
   else if(hold_valid_q[dst_index])begin selected_valid[dst_index]=1'b1;selected_source[dst_index]=hold_source_q[dst_index];end
   else for(scan_index=0;scan_index<C_SOURCES;scan_index=scan_index+1)begin
    source_value={{(32-C_SOURCE_WIDTH){1'b0}},rr_q[dst_index]}+scan_index;
    if(source_value>=C_SOURCES)source_value=source_value-C_SOURCES;
    destination_value={{(32-C_TILE_WIDTH){1'b0}},local_tile[source_value*C_TILE_WIDTH+:C_TILE_WIDTH]}*C_BANK_LANES+
     ({{27{1'b0}},local_port[source_value*5+:5]}%C_BANK_LANES);
    if(!selected_valid[dst_index]&&!source_claimed[source_value]&&local_valid_masked[source_value]&&
       i_local_sop[source_value]&&destination_value==dst_index)begin
      selected_valid[dst_index]=1'b1;selected_source[dst_index]=source_value[C_SOURCE_WIDTH-1:0];
      source_claimed[source_value]=1'b1;
    end
   end
   if(selected_valid[dst_index])begin
    o_local_lane_valid[dst_index]=local_valid_masked[selected_source[dst_index]];
    o_local_lane_data[dst_index*C_DATA_WIDTH+:C_DATA_WIDTH]=i_local_data[selected_source[dst_index]*C_DATA_WIDTH+:C_DATA_WIDTH];
    o_local_lane_meta[dst_index*C_META_WIDTH+:C_META_WIDTH]=i_local_meta[selected_source[dst_index]*C_META_WIDTH+:C_META_WIDTH];
    o_local_lane_dst_group[dst_index*3+:3]=local_group[selected_source[dst_index]*3+:3];
    o_local_lane_dst_tile[dst_index*C_TILE_WIDTH+:C_TILE_WIDTH]=local_tile[selected_source[dst_index]*C_TILE_WIDTH+:C_TILE_WIDTH];
    o_local_lane_dst_port[dst_index*5+:5]=local_port[selected_source[dst_index]*5+:5];
    o_local_lane_sop[dst_index]=i_local_sop[selected_source[dst_index]];
    o_local_lane_eop[dst_index]=i_local_eop[selected_source[dst_index]];
   end
  end
  for(ready_index=0;ready_index<C_SOURCES;ready_index=ready_index+1)
   if(selected_valid[ready_index]&&o_local_lane_valid[ready_index])
    o_local_ready[selected_source[ready_index]]=i_local_lane_ready[ready_index];
  if(!i_rstn||!CONFIG_LEGAL)begin o_local_lane_valid={C_SOURCES{1'b0}};o_local_ready={C_SOURCES{1'b0}};end
 end

 generate for(state_gen=0;state_gen<C_SOURCES;state_gen=state_gen+1)begin:g_local_owner
  always @(posedge i_clk)begin
   if(!i_rstn)begin owner_valid_q[state_gen]<=1'b0;hold_valid_q[state_gen]<=1'b0;
    owner_source_q[state_gen]<={C_SOURCE_WIDTH{1'b0}};hold_source_q[state_gen]<={C_SOURCE_WIDTH{1'b0}};rr_q[state_gen]<={C_SOURCE_WIDTH{1'b0}};end
   else if(owner_valid_q[state_gen])begin
    if(o_local_lane_valid[state_gen]&&i_local_lane_ready[state_gen]&&o_local_lane_eop[state_gen])begin
     owner_valid_q[state_gen]<=1'b0;
     if(owner_source_q[state_gen]==C_LAST_SOURCE)rr_q[state_gen]<={C_SOURCE_WIDTH{1'b0}};
     else rr_q[state_gen]<=owner_source_q[state_gen]+1'b1;
    end
   end else if(hold_valid_q[state_gen])begin
    if(o_local_lane_valid[state_gen]&&i_local_lane_ready[state_gen])begin
     hold_valid_q[state_gen]<=1'b0;
     if(!o_local_lane_eop[state_gen])begin owner_valid_q[state_gen]<=1'b1;owner_source_q[state_gen]<=hold_source_q[state_gen];end
     else if(hold_source_q[state_gen]==C_LAST_SOURCE)rr_q[state_gen]<={C_SOURCE_WIDTH{1'b0}};
     else rr_q[state_gen]<=hold_source_q[state_gen]+1'b1;
    end
   end else if(selected_valid[state_gen]&&o_local_lane_valid[state_gen])begin
    if(!i_local_lane_ready[state_gen])begin hold_valid_q[state_gen]<=1'b1;hold_source_q[state_gen]<=selected_source[state_gen];end
    else if(!o_local_lane_eop[state_gen])begin owner_valid_q[state_gen]<=1'b1;owner_source_q[state_gen]<=selected_source[state_gen];end
    else if(selected_source[state_gen]==C_LAST_SOURCE)rr_q[state_gen]<={C_SOURCE_WIDTH{1'b0}};
    else rr_q[state_gen]<=selected_source[state_gen]+1'b1;
   end
  end
 end endgenerate

 switch_plane_selector #(.C_SOURCES(C_SOURCES),.C_PLANES(C_PLANES),.C_DATA_WIDTH(C_DATA_WIDTH),
  .C_META_WIDTH(C_CORE_META_WIDTH),.C_SOURCE_WIDTH(C_SOURCE_WIDTH))u_plane(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(core_valid_masked),.o_ready(plane_source_ready),
  .i_data(i_core_data),.i_meta(core_packed_in),.i_sop(i_core_sop),.i_eop(i_core_eop),
  .i_eligible(i_plane_eligible),.o_valid(o_plane_valid),.i_ready(i_plane_ready),
  .o_data(o_plane_data),.o_meta(core_packed_out),.o_sop(o_plane_sop),.o_eop(o_plane_eop),.o_quiescent(plane_quiescent));
 generate for(plane_gen=0;plane_gen<C_PLANES;plane_gen=plane_gen+1)begin:g_plane_unpack
  assign o_plane_meta[plane_gen*C_META_WIDTH+:C_META_WIDTH]=core_packed_out[plane_gen*C_CORE_META_WIDTH+:C_META_WIDTH];
  assign o_plane_dst_group[plane_gen*3+:3]=core_packed_out[plane_gen*C_CORE_META_WIDTH+C_META_WIDTH+:3];
  assign o_plane_dst_tile[plane_gen*C_TILE_WIDTH+:C_TILE_WIDTH]=core_packed_out[plane_gen*C_CORE_META_WIDTH+C_META_WIDTH+3+:C_TILE_WIDTH];
  assign o_plane_dst_port[plane_gen*5+:5]=core_packed_out[plane_gen*C_CORE_META_WIDTH+C_META_WIDTH+3+C_TILE_WIDTH+:5];
 end endgenerate

 always @(posedge i_clk)begin
  if(!i_rstn)begin packet_active_q<={C_SOURCES{1'b0}};path_core_q<={C_SOURCES{1'b0}};protocol_error_q<=1'b0;
   for(packet_index=0;packet_index<C_SOURCES;packet_index=packet_index+1)begin
    packet_group_q[packet_index]<=3'd0;packet_tile_q[packet_index]<={C_TILE_WIDTH{1'b0}};packet_port_q[packet_index]<=5'd0;
   end
  end else begin
   for(packet_index=0;packet_index<C_SOURCES;packet_index=packet_index+1)begin
    if(local_fire[packet_index])begin
     if(!packet_active_q[packet_index])begin path_core_q[packet_index]<=1'b0;
      packet_group_q[packet_index]<=i_local_dst_group[packet_index*3+:3];
      packet_tile_q[packet_index]<=i_local_dst_tile[packet_index*C_TILE_WIDTH+:C_TILE_WIDTH];
      packet_port_q[packet_index]<=i_local_dst_port[packet_index*5+:5];
      packet_active_q[packet_index]<=!i_local_eop[packet_index];
     end else if(i_local_eop[packet_index])packet_active_q[packet_index]<=1'b0;
    end else if(core_fire[packet_index])begin
     if(!packet_active_q[packet_index])begin path_core_q[packet_index]<=1'b1;
      packet_group_q[packet_index]<=i_core_dst_group[packet_index*3+:3];
      packet_tile_q[packet_index]<=i_core_dst_tile[packet_index*C_TILE_WIDTH+:C_TILE_WIDTH];
      packet_port_q[packet_index]<=i_core_dst_port[packet_index*5+:5];
      packet_active_q[packet_index]<=!i_core_eop[packet_index];
     end else if(i_core_eop[packet_index])packet_active_q[packet_index]<=1'b0;
    end
   end
   for(protocol_index=0;protocol_index<C_SOURCES;protocol_index=protocol_index+1)
    if((i_local_valid[protocol_index]&&i_core_valid[protocol_index])||
       (i_local_valid[protocol_index]&&(!local_route_legal[protocol_index]||!local_packet_legal[protocol_index]))||
       (i_core_valid[protocol_index]&&(!core_route_legal[protocol_index]||!core_packet_legal[protocol_index])))
      protocol_error_q<=1'b1;
  end
 end
 assign o_quiescent=CONFIG_LEGAL&&plane_quiescent&&!(|packet_active_q)&&!(|owner_valid_q)&&!(|hold_valid_q);
endmodule
`default_nettype wire
