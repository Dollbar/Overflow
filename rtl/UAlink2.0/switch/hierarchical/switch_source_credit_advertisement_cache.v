`timescale 1ns/1ps
`default_nettype none
// Source侧credit广告cache：保存可能延迟的hint，不生成/消费token，也不替代Destination admission握手。
module switch_source_credit_advertisement_cache #(
 parameter integer C_NUM_GROUPS=8,C_NUM_PLANES=32,C_NUM_RESOURCES=512,C_COUNT_WIDTH=3,
 parameter integer C_GROUP_WIDTH=3,C_PLANE_WIDTH=5,C_RESOURCE_WIDTH=9,C_EPOCH_WIDTH=4,C_SEQUENCE_WIDTH=20,
 parameter integer C_TIME_WIDTH=32,C_TTL_CYCLES=1024,C_ENABLE_GENERATION_WIDTH=8,
 parameter integer C_ENTRIES=C_NUM_GROUPS*C_NUM_PLANES*C_NUM_RESOURCES
)(
 input wire i_clk,input wire i_rstn,input wire [C_NUM_GROUPS-1:0] i_group_enable,
 input wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] i_plane_enable,input wire [C_NUM_GROUPS*C_EPOCH_WIDTH-1:0] i_group_epoch,
 input wire i_advert_valid,output wire o_advert_ready,input wire i_advert_available,input wire i_advert_invalidate,
 input wire [C_GROUP_WIDTH-1:0] i_advert_group,input wire [C_PLANE_WIDTH-1:0] i_advert_plane,
 input wire [C_RESOURCE_WIDTH-1:0] i_advert_resource,input wire [C_COUNT_WIDTH-1:0] i_advert_free,
 input wire [C_EPOCH_WIDTH-1:0] i_advert_epoch,input wire [C_SEQUENCE_WIDTH-1:0] i_advert_sequence,
 input wire i_query_valid,output wire o_query_ready,input wire [C_GROUP_WIDTH-1:0] i_query_group,
 input wire [C_PLANE_WIDTH-1:0] i_query_plane,input wire [C_RESOURCE_WIDTH-1:0] i_query_resource,
 output reg o_result_valid,input wire i_result_ready,output reg o_hint_valid,output reg o_hint_available,
 output reg [C_COUNT_WIDTH-1:0] o_hint_free,output reg [C_EPOCH_WIDTH-1:0] o_hint_epoch,
 output reg [C_SEQUENCE_WIDTH-1:0] o_hint_sequence,output reg o_probe_allowed,output reg o_query_error,
 output reg o_stale_record_error,output reg o_malformed_record_error,output reg o_generation_exhausted,
 output wire o_config_error
);
 function width_encodes;input integer width_value;input integer count_value;
  begin if(width_value<1||width_value>30||count_value<1)width_encodes=0;else width_encodes=((32'd1<<width_value)>=count_value);end endfunction
 function sequence_newer;input [C_SEQUENCE_WIDTH-1:0] new_value,old_value;reg [C_SEQUENCE_WIDTH-1:0] delta;
  begin delta=new_value-old_value;sequence_newer=(delta!={C_SEQUENCE_WIDTH{1'b0}})&&!delta[C_SEQUENCE_WIDTH-1];end endfunction
 function integer clog2;input integer value;integer work;begin work=value-1;clog2=0;while(work>0)begin clog2=clog2+1;work=work>>1;end if(clog2<1)clog2=1;end endfunction
 localparam CONFIG_LEGAL=(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&(C_NUM_PLANES>=1)&&(C_NUM_PLANES<=32)&&
  (C_NUM_RESOURCES>=1)&&(C_NUM_RESOURCES<=4096)&&(C_COUNT_WIDTH>=1)&&(C_SEQUENCE_WIDTH>=2)&&
  (C_TIME_WIDTH>=2)&&(C_TIME_WIDTH<=32)&&(C_ENABLE_GENERATION_WIDTH>=2)&&
  width_encodes(C_GROUP_WIDTH,C_NUM_GROUPS)&&width_encodes(C_PLANE_WIDTH,C_NUM_PLANES)&&
  width_encodes(C_RESOURCE_WIDTH,C_NUM_RESOURCES)&&(C_ENTRIES==C_NUM_GROUPS*C_NUM_PLANES*C_NUM_RESOURCES)&&
  ((C_TTL_CYCLES==0)||(C_TTL_CYCLES<(32'd1<<(C_TIME_WIDTH-1))));
 localparam [C_TIME_WIDTH-1:0] TTL_COUNT=C_TTL_CYCLES[C_TIME_WIDTH-1:0];
 reg entry_valid[0:C_ENTRIES-1],entry_available[0:C_ENTRIES-1];
 reg [C_COUNT_WIDTH-1:0] entry_free[0:C_ENTRIES-1];
 reg [C_EPOCH_WIDTH-1:0] entry_epoch[0:C_ENTRIES-1];
 reg [C_SEQUENCE_WIDTH-1:0] entry_sequence[0:C_ENTRIES-1];
 reg [C_TIME_WIDTH-1:0] entry_update_time[0:C_ENTRIES-1];
 reg [C_ENABLE_GENERATION_WIDTH-1:0] entry_enable_generation[0:C_ENTRIES-1];
 reg [C_TIME_WIDTH-1:0] time_q;
 reg [C_NUM_GROUPS*C_NUM_PLANES-1:0] enable_previous_q,enable_generation_usable_q;
 reg [C_ENABLE_GENERATION_WIDTH-1:0] enable_generation_q[0:C_NUM_GROUPS*C_NUM_PLANES-1];
 localparam C_ENTRY_WIDTH=clog2(C_ENTRIES);
 integer advert_group_value,advert_plane_value,advert_resource_value;
 integer query_group_value,query_plane_value,query_resource_value,reset_index,enable_index;
 reg [C_ENTRY_WIDTH-1:0] advert_entry,query_entry;
 reg advert_legal,query_legal,current_enable,query_entry_fresh,query_entry_valid;
 reg [C_TIME_WIDTH-1:0] query_age;
 assign o_config_error=!CONFIG_LEGAL;
 assign o_advert_ready=i_rstn&&CONFIG_LEGAL;
 assign o_query_ready=i_rstn&&CONFIG_LEGAL&&(!o_result_valid||i_result_ready);

 always @(*)begin
  advert_group_value=0;advert_plane_value=0;advert_resource_value=0;advert_entry=0;
  advert_group_value[C_GROUP_WIDTH-1:0]=i_advert_group;advert_plane_value[C_PLANE_WIDTH-1:0]=i_advert_plane;
  advert_resource_value[C_RESOURCE_WIDTH-1:0]=i_advert_resource;
  advert_legal=(advert_group_value<C_NUM_GROUPS)&&(advert_plane_value<C_NUM_PLANES)&&(advert_resource_value<C_NUM_RESOURCES);
  // 合法性比较保证线性索引小于C_ENTRIES；这里显式接受integer算术到最小地址宽度的缩窄。
  /* verilator lint_off WIDTHTRUNC */
  if(advert_legal)advert_entry=(advert_group_value*C_NUM_PLANES+advert_plane_value)*C_NUM_RESOURCES+advert_resource_value;
  /* verilator lint_on WIDTHTRUNC */
  query_group_value=0;query_plane_value=0;query_resource_value=0;query_entry=0;
  query_group_value[C_GROUP_WIDTH-1:0]=i_query_group;query_plane_value[C_PLANE_WIDTH-1:0]=i_query_plane;
  query_resource_value[C_RESOURCE_WIDTH-1:0]=i_query_resource;
  query_legal=(query_group_value<C_NUM_GROUPS)&&(query_plane_value<C_NUM_PLANES)&&(query_resource_value<C_NUM_RESOURCES);
  /* verilator lint_off WIDTHTRUNC */
  if(query_legal)query_entry=(query_group_value*C_NUM_PLANES+query_plane_value)*C_NUM_RESOURCES+query_resource_value;
  /* verilator lint_on WIDTHTRUNC */
  current_enable=1'b0;query_age=0;query_entry_fresh=1'b0;query_entry_valid=1'b0;
  if(query_legal)begin
   current_enable=i_group_enable[query_group_value]&&i_plane_enable[query_group_value*C_NUM_PLANES+query_plane_value];
   query_age=time_q-entry_update_time[query_entry];
   query_entry_fresh=(C_TTL_CYCLES==0)||(query_age<=TTL_COUNT);
   query_entry_valid=current_enable&&enable_generation_usable_q[query_group_value*C_NUM_PLANES+query_plane_value]&&
    entry_valid[query_entry]&&query_entry_fresh&&
    (entry_epoch[query_entry]==i_group_epoch[query_group_value*C_EPOCH_WIDTH+:C_EPOCH_WIDTH])&&
    (entry_enable_generation[query_entry]==enable_generation_q[query_group_value*C_NUM_PLANES+query_plane_value]);
  end
 end

 always @(posedge i_clk)begin
  if(!i_rstn)begin
   o_result_valid<=0;o_hint_valid<=0;o_hint_available<=0;o_hint_free<=0;o_hint_epoch<=0;o_hint_sequence<=0;o_probe_allowed<=0;o_query_error<=0;
   o_stale_record_error<=0;o_malformed_record_error<=0;o_generation_exhausted<=0;time_q<=0;
   enable_previous_q<=0;enable_generation_usable_q<={C_NUM_GROUPS*C_NUM_PLANES{1'b1}};
   for(reset_index=0;reset_index<C_ENTRIES;reset_index=reset_index+1)begin entry_valid[reset_index]<=0;entry_available[reset_index]<=0;entry_free[reset_index]<=0;entry_epoch[reset_index]<=0;entry_sequence[reset_index]<=0;entry_update_time[reset_index]<=0;entry_enable_generation[reset_index]<=0;end
   for(reset_index=0;reset_index<C_NUM_GROUPS*C_NUM_PLANES;reset_index=reset_index+1)enable_generation_q[reset_index]<=0;
  end else begin
   time_q<=time_q+1'b1;
   if(o_result_valid&&i_result_ready)o_result_valid<=0;
   for(enable_index=0;enable_index<C_NUM_GROUPS*C_NUM_PLANES;enable_index=enable_index+1)begin
    if(enable_previous_q[enable_index]!=(i_group_enable[enable_index/C_NUM_PLANES]&&i_plane_enable[enable_index]))begin
     enable_previous_q[enable_index]<=i_group_enable[enable_index/C_NUM_PLANES]&&i_plane_enable[enable_index];
     if(enable_generation_q[enable_index]=={C_ENABLE_GENERATION_WIDTH{1'b1}})begin enable_generation_usable_q[enable_index]<=0;o_generation_exhausted<=1;end
     else enable_generation_q[enable_index]<=enable_generation_q[enable_index]+1'b1;
    end
   end
   if(i_advert_valid&&o_advert_ready)begin
    if(!advert_legal||(i_advert_available==i_advert_invalidate))o_malformed_record_error<=1;
    else if(i_advert_epoch!=i_group_epoch[advert_group_value*C_EPOCH_WIDTH+:C_EPOCH_WIDTH])o_stale_record_error<=1;
    else if(!entry_valid[advert_entry]||(entry_epoch[advert_entry]!=i_advert_epoch)||sequence_newer(i_advert_sequence,entry_sequence[advert_entry]))begin
     entry_valid[advert_entry]<=1;entry_available[advert_entry]<=i_advert_available;entry_free[advert_entry]<=i_advert_free;
     entry_epoch[advert_entry]<=i_advert_epoch;entry_sequence[advert_entry]<=i_advert_sequence;entry_update_time[advert_entry]<=time_q;
     entry_enable_generation[advert_entry]<=enable_generation_q[advert_group_value*C_NUM_PLANES+advert_plane_value];
    end else o_stale_record_error<=1;
   end
   if(i_query_valid&&o_query_ready)begin
    o_result_valid<=1;o_query_error<=!query_legal;o_hint_valid<=query_entry_valid;
    o_hint_available<=query_entry_valid&&entry_available[query_entry];o_hint_free<=query_entry_valid?entry_free[query_entry]:0;
    o_hint_epoch<=query_entry_valid?entry_epoch[query_entry]:0;o_hint_sequence<=query_entry_valid?entry_sequence[query_entry]:0;
    // enabled但无有效hint时允许一次探测，冷启动、TTL过期或丢广告不会形成永久死锁。
    o_probe_allowed<=query_legal&&current_enable&&(!query_entry_valid||entry_available[query_entry]);
   end
  end
 end
endmodule
`default_nettype wire
