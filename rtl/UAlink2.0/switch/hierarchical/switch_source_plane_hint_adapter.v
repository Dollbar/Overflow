`timescale 1ns/1ps
`default_nettype none
// 将单读口广告cache接到Source Group的source×plane eligibility矩阵。
// 本模块只缓存“可尝试”提示；真实发送仍必须经过Plane下游ready和Destination token admission。
module switch_source_plane_hint_adapter #(
 parameter integer C_SOURCES=32,C_PLANES=32,C_NUM_GROUPS=8,C_NUM_RESOURCES=512,
 parameter integer C_GROUP_WIDTH=3,C_PLANE_WIDTH=5,C_RESOURCE_WIDTH=9,C_EPOCH_WIDTH=4,
 parameter integer C_TIME_WIDTH=16,C_REFRESH_CYCLES=512,
 parameter integer C_PAIR_COUNT=C_SOURCES*C_PLANES,
 parameter integer C_PAIR_WIDTH=(C_PAIR_COUNT<=2)?1:(C_PAIR_COUNT<=4)?2:(C_PAIR_COUNT<=8)?3:(C_PAIR_COUNT<=16)?4:
  (C_PAIR_COUNT<=32)?5:(C_PAIR_COUNT<=64)?6:(C_PAIR_COUNT<=128)?7:(C_PAIR_COUNT<=256)?8:(C_PAIR_COUNT<=512)?9:10
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_SOURCES-1:0] i_source_valid,input wire [C_SOURCES-1:0] i_source_sop,
 input wire [C_SOURCES*C_GROUP_WIDTH-1:0] i_source_dst_group,
 input wire [C_SOURCES*C_RESOURCE_WIDTH-1:0] i_source_resource,
 input wire [C_NUM_GROUPS-1:0] i_group_enable,input wire [C_PLANES-1:0] i_plane_enable,
 input wire [C_NUM_GROUPS*C_EPOCH_WIDTH-1:0] i_group_epoch,
 output reg [C_PAIR_COUNT-1:0] o_plane_eligible,output reg [C_PAIR_COUNT-1:0] o_using_hint,
 output reg [C_PAIR_COUNT-1:0] o_probe_path,
 output reg o_cache_query_valid,input wire i_cache_query_ready,
 output reg [C_GROUP_WIDTH-1:0] o_cache_query_group,output reg [C_PLANE_WIDTH-1:0] o_cache_query_plane,
 output reg [C_RESOURCE_WIDTH-1:0] o_cache_query_resource,
 input wire i_cache_result_valid,output wire o_cache_result_ready,input wire i_cache_hint_valid,
 input wire i_cache_hint_available,input wire i_cache_probe_allowed,input wire [C_EPOCH_WIDTH-1:0] i_cache_hint_epoch,
 output wire o_quiescent,output reg o_protocol_error,output wire o_config_error
);
 function width_encodes;input integer width_value,count_value;begin width_encodes=(width_value>=1)&&(width_value<=30)&&(count_value>=1)&&((32'd1<<width_value)>=count_value);end endfunction
 localparam CONFIG_LEGAL=(C_SOURCES>=1)&&(C_SOURCES<=32)&&(C_PLANES>=1)&&(C_PLANES<=32)&&
  (C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&(C_NUM_RESOURCES>=1)&&(C_NUM_RESOURCES<=4096)&&
  (C_PAIR_COUNT==C_SOURCES*C_PLANES)&&width_encodes(C_GROUP_WIDTH,C_NUM_GROUPS)&&
  width_encodes(C_PLANE_WIDTH,C_PLANES)&&width_encodes(C_RESOURCE_WIDTH,C_NUM_RESOURCES)&&
  width_encodes(C_PAIR_WIDTH,C_PAIR_COUNT)&&(C_TIME_WIDTH>=2)&&(C_REFRESH_CYCLES>0)&&
  (C_REFRESH_CYCLES<(32'd1<<(C_TIME_WIDTH-1)));
 localparam [C_TIME_WIDTH-1:0] REFRESH_LIMIT=C_REFRESH_CYCLES[C_TIME_WIDTH-1:0];
 reg [C_PAIR_COUNT-1:0] record_valid_q,record_permit_q,record_hint_q;
 reg [C_PAIR_COUNT*C_GROUP_WIDTH-1:0] record_group_q;
 reg [C_PAIR_COUNT*C_RESOURCE_WIDTH-1:0] record_resource_q;
 reg [C_PAIR_COUNT*C_EPOCH_WIDTH-1:0] record_epoch_q;
 reg [C_PAIR_COUNT*C_TIME_WIDTH-1:0] record_time_q;
 reg [C_TIME_WIDTH-1:0] time_q;
 reg pending_q;reg [C_PAIR_WIDTH-1:0] pending_pair_q;reg [C_GROUP_WIDTH-1:0] pending_group_q;
 reg [C_PLANE_WIDTH-1:0] pending_plane_q;reg [C_RESOURCE_WIDTH-1:0] pending_resource_q;
 reg [C_EPOCH_WIDTH-1:0] pending_epoch_q;
 reg selected_query;reg [C_PAIR_WIDTH-1:0] selected_pair;
 reg pair_match,pair_enabled,pair_fresh;reg [C_TIME_WIDTH-1:0] pair_age;
 integer pair_index,source_index,group_value,resource_value,reset_index;
 // plane_index来自pair%C_PLANES，合法范围已由CONFIG_LEGAL限制；高位integer仅用于数组寻址。
 /* verilator lint_off UNUSEDSIGNAL */
 integer plane_index;
 /* verilator lint_on UNUSEDSIGNAL */
 assign o_cache_result_ready=i_rstn&&CONFIG_LEGAL&&pending_q;
 assign o_quiescent=!pending_q&&!o_cache_query_valid;
 assign o_config_error=!CONFIG_LEGAL;
 // 未命中、TTL过期或epoch变化时fail-open允许探测；有效的unavailable提示才临时屏蔽该Plane。
 always @(*) begin
  o_plane_eligible=0;o_using_hint=0;o_probe_path=0;o_cache_query_valid=0;
  o_cache_query_group=0;o_cache_query_plane=0;o_cache_query_resource=0;
  selected_query=0;selected_pair=0;pair_match=0;pair_enabled=0;pair_fresh=0;pair_age=0;
  source_index=0;plane_index=0;group_value=0;resource_value=0;
  for(pair_index=0;pair_index<C_PAIR_COUNT;pair_index=pair_index+1)begin
   source_index=pair_index/C_PLANES;plane_index=pair_index%C_PLANES;group_value=0;resource_value=0;
   group_value[C_GROUP_WIDTH-1:0]=i_source_dst_group[source_index*C_GROUP_WIDTH+:C_GROUP_WIDTH];
   resource_value[C_RESOURCE_WIDTH-1:0]=i_source_resource[source_index*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH];
   pair_enabled=1'b0;if((group_value<C_NUM_GROUPS)&&(resource_value<C_NUM_RESOURCES))
    pair_enabled=i_group_enable[group_value]&&i_plane_enable[plane_index];
   pair_age=time_q-record_time_q[pair_index*C_TIME_WIDTH+:C_TIME_WIDTH];pair_fresh=(pair_age<=REFRESH_LIMIT);
   pair_match=1'b0;if((group_value<C_NUM_GROUPS)&&(resource_value<C_NUM_RESOURCES))pair_match=record_valid_q[pair_index]&&pair_fresh&&
    (record_group_q[pair_index*C_GROUP_WIDTH+:C_GROUP_WIDTH]==i_source_dst_group[source_index*C_GROUP_WIDTH+:C_GROUP_WIDTH])&&
    (record_resource_q[pair_index*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]==i_source_resource[source_index*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH])&&
    (record_epoch_q[pair_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]==i_group_epoch[group_value*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]);
   if(i_source_valid[source_index]&&i_source_sop[source_index]&&pair_enabled)begin
    if(pair_match)begin o_plane_eligible[pair_index]=record_permit_q[pair_index];o_using_hint[pair_index]=record_hint_q[pair_index];
     o_probe_path[pair_index]=record_permit_q[pair_index]&&!record_hint_q[pair_index];end
    else begin o_plane_eligible[pair_index]=1'b1;o_probe_path[pair_index]=1'b1;end
    if(!pending_q&&!selected_query&&!pair_match)begin selected_query=1;o_cache_query_valid=1;
     selected_pair=pair_index[C_PAIR_WIDTH-1:0];o_cache_query_group=i_source_dst_group[source_index*C_GROUP_WIDTH+:C_GROUP_WIDTH];
     o_cache_query_plane=plane_index[C_PLANE_WIDTH-1:0];o_cache_query_resource=i_source_resource[source_index*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH];end
   end
  end
  if(!i_rstn||!CONFIG_LEGAL||pending_q)o_cache_query_valid=0;
 end
 always @(posedge i_clk)begin
  if(!i_rstn)begin record_valid_q<=0;record_permit_q<=0;record_hint_q<=0;record_group_q<=0;record_resource_q<=0;
   record_epoch_q<=0;record_time_q<=0;time_q<=0;pending_q<=0;pending_pair_q<=0;pending_group_q<=0;pending_plane_q<=0;pending_resource_q<=0;pending_epoch_q<=0;o_protocol_error<=0;end
  else begin
   time_q<=time_q+1'b1;
   // disabled路径立即失效，重新enable后先探测再刷新，不能复用旧generation提示。
   for(reset_index=0;reset_index<C_PAIR_COUNT;reset_index=reset_index+1)begin
    if(!i_plane_enable[reset_index%C_PLANES])record_valid_q[reset_index]<=1'b0;
    else if(record_valid_q[reset_index]&&
     !i_group_enable[record_group_q[reset_index*C_GROUP_WIDTH+:C_GROUP_WIDTH]])record_valid_q[reset_index]<=1'b0;
   end
   if(o_cache_query_valid&&i_cache_query_ready)begin pending_q<=1'b1;pending_pair_q<=selected_pair;
    pending_group_q<=o_cache_query_group;pending_plane_q<=o_cache_query_plane;pending_resource_q<=o_cache_query_resource;
    pending_epoch_q<=i_group_epoch[o_cache_query_group*C_EPOCH_WIDTH+:C_EPOCH_WIDTH];end
   if(i_cache_result_valid&&o_cache_result_ready)begin
    pending_q<=1'b0;
    // pending期间disable的路径不能在重新enable后复活旧结果。
    record_valid_q[pending_pair_q]<=i_group_enable[pending_group_q]&&i_plane_enable[pending_plane_q];
    record_permit_q[pending_pair_q]<=i_cache_hint_valid?i_cache_hint_available:i_cache_probe_allowed;
    record_hint_q[pending_pair_q]<=i_cache_hint_valid;
    record_group_q[pending_pair_q*C_GROUP_WIDTH+:C_GROUP_WIDTH]<=pending_group_q;
    record_resource_q[pending_pair_q*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]<=pending_resource_q;
    record_epoch_q[pending_pair_q*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]<=i_cache_hint_valid?i_cache_hint_epoch:pending_epoch_q;
    record_time_q[pending_pair_q*C_TIME_WIDTH+:C_TIME_WIDTH]<=time_q;
   end else if(i_cache_result_valid&&!pending_q)o_protocol_error<=1'b1;
  end
 end
endmodule
`default_nettype wire
