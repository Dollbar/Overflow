`timescale 1ns/1ps
`default_nettype none
// 有序流的Core Plane亲和过滤器。
// 同一个{源Port,目的,内部VN,原始VC/Pool,Route epoch}在一个Route epoch内只允许一个Plane。
// 绑定Plane的瞬时credit/enable撤销只形成背压；管理面必须在quiescent后改变epoch才能resequence。
module switch_ordered_plane_filter #(
 parameter integer C_SOURCES=32,
 parameter integer C_PLANES=32,
 parameter integer C_TILE_WIDTH=2,
 parameter integer C_CLASS_WIDTH=2,
 parameter integer C_EPOCH_WIDTH=8,
 parameter integer C_PLANE_INDEX_WIDTH=(C_PLANES<=2)?1:(C_PLANES<=4)?2:(C_PLANES<=8)?3:(C_PLANES<=16)?4:5
)(
 input wire [C_SOURCES-1:0] i_valid,
 input wire [C_SOURCES-1:0] i_sop,
 input wire [C_SOURCES*C_PLANES-1:0] i_eligible,
 input wire [C_SOURCES*10-1:0] i_src_port,
 input wire [C_SOURCES*3-1:0] i_dst_group,
 input wire [C_SOURCES*C_TILE_WIDTH-1:0] i_dst_tile,
 input wire [C_SOURCES*5-1:0] i_dst_port,
 input wire [C_SOURCES*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_SOURCES*2-1:0] i_original_vc,
 input wire [C_SOURCES-1:0] i_pool,
 input wire [C_SOURCES*C_EPOCH_WIDTH-1:0] i_route_epoch,
 output wire [C_SOURCES*C_PLANES-1:0] o_eligible,
 output wire [C_SOURCES*C_PLANE_INDEX_WIDTH-1:0] o_affinity_plane,
 output wire o_config_error,
 output wire o_error
);
 function width_encodes;
  input integer width_value;input integer count_value;
  begin
   if((width_value<1)||(width_value>30)||(count_value<1))width_encodes=0;
   else width_encodes=((32'd1<<width_value)>=count_value);
  end
 endfunction
 localparam CONFIG_LEGAL=(C_SOURCES>=1)&&(C_SOURCES<=32)&&(C_PLANES>=1)&&(C_PLANES<=32)&&
  (C_TILE_WIDTH>=1)&&(C_TILE_WIDTH<=30)&&(C_CLASS_WIDTH>=1)&&(C_CLASS_WIDTH<=30)&&
  (C_EPOCH_WIDTH>=1)&&(C_EPOCH_WIDTH<=30)&&width_encodes(C_PLANE_INDEX_WIDTH,C_PLANES);
 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error;

 function [31:0] flow_plane;
  input [9:0] source_port;
  input [2:0] destination_group;
  input [C_TILE_WIDTH-1:0] destination_tile;
  input [4:0] destination_port;
  input [C_CLASS_WIDTH-1:0] traffic_class;
  input [1:0] original_vc;
  input original_pool;
  input [C_EPOCH_WIDTH-1:0] route_epoch;
  reg [31:0] hash_value;
  begin
   // 不使用lane编号；Tile VOQ lane可随仲裁变化，协议flow identity必须来自保存的sideband。
   hash_value={{22{1'b0}},source_port};
   hash_value=hash_value+({{29{1'b0}},destination_group}*32'd13);
   hash_value=hash_value+({{(32-C_TILE_WIDTH){1'b0}},destination_tile}*32'd11);
   hash_value=hash_value+({{27{1'b0}},destination_port}*32'd7);
   hash_value=hash_value+({{(32-C_CLASS_WIDTH){1'b0}},traffic_class}*32'd5);
   hash_value=hash_value+({{30{1'b0}},original_vc}*32'd3);
   hash_value=hash_value+{{31{1'b0}},original_pool};
   hash_value=hash_value+({{(32-C_EPOCH_WIDTH){1'b0}},route_epoch}*32'd19);
   flow_plane=hash_value%C_PLANES;
  end
 endfunction

 genvar source_index,plane_index;
 generate
  for(source_index=0;source_index<C_SOURCES;source_index=source_index+1)begin:g_source
   wire [31:0] affinity_full;
   wire [C_PLANE_INDEX_WIDTH-1:0] affinity;
   assign affinity_full=flow_plane(
    i_src_port[source_index*10+:10],i_dst_group[source_index*3+:3],
    i_dst_tile[source_index*C_TILE_WIDTH+:C_TILE_WIDTH],i_dst_port[source_index*5+:5],
    i_class[source_index*C_CLASS_WIDTH+:C_CLASS_WIDTH],
    i_original_vc[source_index*2+:2],i_pool[source_index],
    i_route_epoch[source_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]);
   assign affinity=affinity_full[C_PLANE_INDEX_WIDTH-1:0];
   assign o_affinity_plane[source_index*C_PLANE_INDEX_WIDTH+:C_PLANE_INDEX_WIDTH]=affinity;
   for(plane_index=0;plane_index<C_PLANES;plane_index=plane_index+1)begin:g_plane
    assign o_eligible[source_index*C_PLANES+plane_index]=CONFIG_LEGAL&&i_valid[source_index]&&
     i_sop[source_index]&&i_eligible[source_index*C_PLANES+plane_index]&&
     (affinity_full==plane_index);
   end
  end
 endgenerate
endmodule
`default_nettype wire
