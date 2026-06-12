`timescale 1ns/1ps
`default_nettype none
// 周期扫描Destination真实free计数，在没有任何业务请求时也向Source发布Group/Plane/Resource可用性。
// 广告仅是可能延迟的提示，不预留slot、不生成token；Destination admission的ready/token始终是唯一授权。
module switch_proactive_credit_advertiser #(
 parameter integer C_NUM_GROUPS=8,C_NUM_PLANES=32,C_NUM_RESOURCES=512,C_COUNT_WIDTH=3,
 parameter integer C_GROUP_WIDTH=3,C_PLANE_WIDTH=5,C_RESOURCE_WIDTH=9,C_EPOCH_WIDTH=4,C_SEQUENCE_WIDTH=20
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_NUM_GROUPS-1:0] i_group_online,
 input wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] i_plane_enable,
 input wire [C_NUM_GROUPS*C_EPOCH_WIDTH-1:0] i_group_epoch,
 input wire [C_NUM_GROUPS*C_NUM_RESOURCES*C_COUNT_WIDTH-1:0] i_resource_free,
 output reg o_advert_valid,input wire i_advert_ready,
 output reg o_advert_available,output reg o_advert_invalidate,
 output reg [C_GROUP_WIDTH-1:0] o_dst_group,output reg [C_PLANE_WIDTH-1:0] o_plane_id,
 output reg [C_RESOURCE_WIDTH-1:0] o_resource_id,output reg [C_COUNT_WIDTH-1:0] o_free_count,
 output reg [C_EPOCH_WIDTH-1:0] o_epoch,output reg [C_SEQUENCE_WIDTH-1:0] o_sequence,
 output reg o_sweep_last,output wire o_config_error
);
 function width_encodes;
  input integer width_value;input integer count_value;
  begin if(width_value<1||width_value>30||count_value<1)width_encodes=0;else width_encodes=((32'd1<<width_value)>=count_value);end
 endfunction
 localparam CONFIG_LEGAL=(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&(C_NUM_PLANES>=1)&&(C_NUM_PLANES<=32)&&
  (C_NUM_RESOURCES>=1)&&(C_NUM_RESOURCES<=4096)&&(C_COUNT_WIDTH>=1)&&(C_EPOCH_WIDTH>=1)&&(C_SEQUENCE_WIDTH>=1)&&
  width_encodes(C_GROUP_WIDTH,C_NUM_GROUPS)&&width_encodes(C_PLANE_WIDTH,C_NUM_PLANES)&&
  width_encodes(C_RESOURCE_WIDTH,C_NUM_RESOURCES);
 localparam [C_GROUP_WIDTH:0] GROUP_LIMIT=C_NUM_GROUPS[C_GROUP_WIDTH:0];
 localparam [C_PLANE_WIDTH:0] PLANE_LIMIT=C_NUM_PLANES[C_PLANE_WIDTH:0];
 localparam [C_RESOURCE_WIDTH:0] RESOURCE_LIMIT=C_NUM_RESOURCES[C_RESOURCE_WIDTH:0];
 reg [C_GROUP_WIDTH-1:0] scan_group_q;
 reg [C_PLANE_WIDTH-1:0] scan_plane_q;
 reg [C_RESOURCE_WIDTH-1:0] scan_resource_q;
 reg [C_SEQUENCE_WIDTH-1:0] next_sequence_q;
 integer selected_group,selected_plane,selected_resource,selected_flat_resource;
 reg [C_COUNT_WIDTH-1:0] selected_free;
 reg [C_EPOCH_WIDTH-1:0] selected_epoch;
 reg selected_available;
 assign o_config_error=!CONFIG_LEGAL;

 // 只读当前ledger free image。输出寄存后即使free/epoch变化或链路反压也保持原广告快照。
 always @(*) begin
  selected_group=0;selected_plane=0;selected_resource=0;selected_flat_resource=0;
  selected_group[C_GROUP_WIDTH-1:0]=scan_group_q;
  selected_plane[C_PLANE_WIDTH-1:0]=scan_plane_q;
  selected_resource[C_RESOURCE_WIDTH-1:0]=scan_resource_q;
  selected_flat_resource=selected_group*C_NUM_RESOURCES+selected_resource;
  selected_free=i_resource_free[selected_flat_resource*C_COUNT_WIDTH+:C_COUNT_WIDTH];
  selected_epoch=i_group_epoch[selected_group*C_EPOCH_WIDTH+:C_EPOCH_WIDTH];
  selected_available=i_group_online[selected_group]&&i_plane_enable[selected_group*C_NUM_PLANES+selected_plane]&&
   (selected_free!={C_COUNT_WIDTH{1'b0}});
 end

 // Resource为最内层扫描项；每个被Source接纳的record都有单调sequence，整轮末项显式标记。
 always @(posedge i_clk) begin
  if(!i_rstn)begin
   o_advert_valid<=0;o_advert_available<=0;o_advert_invalidate<=0;o_dst_group<=0;o_plane_id<=0;o_resource_id<=0;
   o_free_count<=0;o_epoch<=0;o_sequence<=0;o_sweep_last<=0;scan_group_q<=0;scan_plane_q<=0;scan_resource_q<=0;next_sequence_q<=0;
  end else if(!o_advert_valid||i_advert_ready)begin
   o_advert_valid<=CONFIG_LEGAL;o_advert_available<=selected_available;o_advert_invalidate<=!selected_available;
   o_dst_group<=scan_group_q;o_plane_id<=scan_plane_q;o_resource_id<=scan_resource_q;o_free_count<=selected_free;
   o_epoch<=selected_epoch;o_sequence<=next_sequence_q;
   o_sweep_last<=({1'b0,scan_group_q}==(GROUP_LIMIT-1'b1))&&({1'b0,scan_plane_q}==(PLANE_LIMIT-1'b1))&&
    ({1'b0,scan_resource_q}==(RESOURCE_LIMIT-1'b1));
   next_sequence_q<=next_sequence_q+1'b1;
   if({1'b0,scan_resource_q}==(RESOURCE_LIMIT-1'b1))begin
    scan_resource_q<=0;
    if({1'b0,scan_plane_q}==(PLANE_LIMIT-1'b1))begin
     scan_plane_q<=0;if({1'b0,scan_group_q}==(GROUP_LIMIT-1'b1))scan_group_q<=0;else scan_group_q<=scan_group_q+1'b1;
    end else scan_plane_q<=scan_plane_q+1'b1;
   end else scan_resource_q<=scan_resource_q+1'b1;
  end
 end
endmodule
`default_nettype wire
