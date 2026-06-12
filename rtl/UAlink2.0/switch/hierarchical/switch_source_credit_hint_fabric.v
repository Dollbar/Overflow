`timescale 1ns/1ps
`default_nettype none
// 同一Fabric时钟域内，把Destination effective-free广告转换为各Source lane的Plane提示。
// 提示不拥有credit/token；最终发送仍以Core/Destination ready握手为唯一授权。
module switch_source_credit_hint_fabric #(
 parameter integer C_NUM_SOURCE_GROUPS=8,C_SOURCES_PER_GROUP=32,C_NUM_PLANES=32,
 parameter integer C_TILES=4,C_PORTS_PER_TILE=32,C_NUM_CLASSES=4,
 parameter integer C_NUM_RESOURCES=C_TILES*C_PORTS_PER_TILE*C_NUM_CLASSES,
 parameter integer C_COUNT_WIDTH=3,C_TILE_WIDTH=2,C_CLASS_WIDTH=2,
 parameter integer C_PLANE_WIDTH=5,C_RESOURCE_WIDTH=9,C_EPOCH_WIDTH=8,
 parameter integer C_SEQUENCE_WIDTH=20,C_TIME_WIDTH=32,C_TTL_CYCLES=1024,
 parameter integer C_ENABLE_GENERATION_WIDTH=8,C_REFRESH_CYCLES=512,
 parameter integer C_PAIRS_PER_GROUP=C_SOURCES_PER_GROUP*C_NUM_PLANES
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_NUM_SOURCE_GROUPS*C_SOURCES_PER_GROUP-1:0] i_source_valid,
 input wire [C_NUM_SOURCE_GROUPS*C_SOURCES_PER_GROUP-1:0] i_source_sop,
 input wire [C_NUM_SOURCE_GROUPS*C_SOURCES_PER_GROUP*3-1:0] i_source_dst_group,
 input wire [C_NUM_SOURCE_GROUPS*C_SOURCES_PER_GROUP*C_TILE_WIDTH-1:0] i_source_dst_tile,
 input wire [C_NUM_SOURCE_GROUPS*C_SOURCES_PER_GROUP*5-1:0] i_source_dst_port,
 input wire [C_NUM_SOURCE_GROUPS*C_SOURCES_PER_GROUP*C_CLASS_WIDTH-1:0] i_source_class,
 input wire [C_NUM_PLANES-1:0] i_plane_enable,input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 input wire [C_NUM_SOURCE_GROUPS*C_NUM_RESOURCES*C_COUNT_WIDTH-1:0] i_effective_free,
 input wire i_record_forward_enable,input wire i_record_sink_enable,
 output wire [C_NUM_SOURCE_GROUPS*C_PAIRS_PER_GROUP-1:0] o_plane_eligible,
 output wire [C_NUM_SOURCE_GROUPS*C_PAIRS_PER_GROUP-1:0] o_using_hint,
 output wire [C_NUM_SOURCE_GROUPS*C_PAIRS_PER_GROUP-1:0] o_probe_path,
 output wire [C_NUM_SOURCE_GROUPS-1:0] o_group_pending,
 output wire [C_NUM_SOURCE_GROUPS-1:0] o_group_error,output wire o_config_error
);
 function width_encodes;input integer width_value,count_value;
  begin width_encodes=(width_value>=1)&&(width_value<=30)&&(count_value>=1)&&
   ((32'd1<<width_value)>=count_value);end
 endfunction
 localparam CONFIG_LEGAL=(C_NUM_SOURCE_GROUPS>=1)&&(C_NUM_SOURCE_GROUPS<=8)&&
  (C_SOURCES_PER_GROUP>=1)&&(C_SOURCES_PER_GROUP<=32)&&
  (C_NUM_PLANES>=1)&&(C_NUM_PLANES<=32)&&(C_TILES>=1)&&(C_TILES<=4)&&
  (C_PORTS_PER_TILE>=1)&&(C_PORTS_PER_TILE<=32)&&(C_NUM_CLASSES>=1)&&
  (C_NUM_RESOURCES==C_TILES*C_PORTS_PER_TILE*C_NUM_CLASSES)&&
  (C_PAIRS_PER_GROUP==C_SOURCES_PER_GROUP*C_NUM_PLANES)&&
  width_encodes(C_TILE_WIDTH,C_TILES)&&width_encodes(C_CLASS_WIDTH,C_NUM_CLASSES)&&
  width_encodes(C_PLANE_WIDTH,C_NUM_PLANES)&&width_encodes(C_RESOURCE_WIDTH,C_NUM_RESOURCES)&&
  (C_SEQUENCE_WIDTH>=2)&&(C_SEQUENCE_WIDTH<=30)&&
  (C_NUM_SOURCE_GROUPS*C_NUM_RESOURCES<(32'd1<<(C_SEQUENCE_WIDTH-1)));
 localparam integer C_TOTAL_SOURCES=C_NUM_SOURCE_GROUPS*C_SOURCES_PER_GROUP;
 wire [C_NUM_SOURCE_GROUPS-1:0] group_online={C_NUM_SOURCE_GROUPS{1'b1}};
 wire [C_NUM_SOURCE_GROUPS-1:0] destination_resource_enable;
 wire [C_NUM_SOURCE_GROUPS*C_EPOCH_WIDTH-1:0] group_epoch;
 // Core路由字段固定为3-bit/8-slot namespace；adapter使用完整namespace避免动态窄向量索引。
 wire [7:0] adapter_group_online;
 wire [8*C_EPOCH_WIDTH-1:0] adapter_group_epoch;
 reg [C_TOTAL_SOURCES*C_RESOURCE_WIDTH-1:0] source_resource;
 reg [C_TOTAL_SOURCES-1:0] source_route_legal;
 reg [C_NUM_SOURCE_GROUPS-1:0] route_error_q;
 integer source_index,group_value,tile_value,port_value,class_value,resource_value,state_index;
 always @(*)begin
  source_resource=0;source_route_legal=0;group_value=0;tile_value=0;port_value=0;class_value=0;resource_value=0;
  for(source_index=0;source_index<C_TOTAL_SOURCES;source_index=source_index+1)begin
   group_value=0;tile_value=0;port_value=0;class_value=0;
   group_value[2:0]=i_source_dst_group[source_index*3+:3];
   tile_value[C_TILE_WIDTH-1:0]=i_source_dst_tile[source_index*C_TILE_WIDTH+:C_TILE_WIDTH];
   port_value[4:0]=i_source_dst_port[source_index*5+:5];
   class_value[C_CLASS_WIDTH-1:0]=i_source_class[source_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];
   resource_value=(tile_value*C_PORTS_PER_TILE+port_value)*C_NUM_CLASSES+class_value;
   if((group_value<C_NUM_SOURCE_GROUPS)&&(tile_value<C_TILES)&&(port_value<C_PORTS_PER_TILE)&&
      (class_value<C_NUM_CLASSES)&&(resource_value<C_NUM_RESOURCES))begin
    source_route_legal[source_index]=1'b1;
    source_resource[source_index*C_RESOURCE_WIDTH+:C_RESOURCE_WIDTH]=resource_value[C_RESOURCE_WIDTH-1:0];
   end
  end
 end
 always @(posedge i_clk)begin
  if(!i_rstn)route_error_q<=0;
  else for(state_index=0;state_index<C_TOTAL_SOURCES;state_index=state_index+1)
   if(i_source_valid[state_index]&&i_source_sop[state_index]&&!source_route_legal[state_index])
    route_error_q[state_index/C_SOURCES_PER_GROUP]<=1'b1;
 end
 // physical effective-free与Plane无关：单一advertiser仅扫描Group×Resource。
 // record原子广播到各Source Group私有cache，Source本地再按plane-enable展开。
 localparam integer C_RECORD_WIDTH=3+3+1+C_RESOURCE_WIDTH+C_COUNT_WIDTH+C_EPOCH_WIDTH+C_SEQUENCE_WIDTH;
 wire advert_valid,advert_ready,advert_available,advert_invalidate,advert_last,advert_config;
 wire [2:0] advert_group;wire advert_plane;
 wire [C_RESOURCE_WIDTH-1:0] advert_resource;wire [C_COUNT_WIDTH-1:0] advert_free;
 wire [C_EPOCH_WIDTH-1:0] advert_epoch;wire [C_SEQUENCE_WIDTH-1:0] advert_sequence;
 wire [C_RECORD_WIDTH-1:0] record_input,record_output;wire record_input_ready,record_valid,record_ready;
 wire record_idle,record_config,record_error;
 wire [C_NUM_SOURCE_GROUPS-1:0] cache_advert_ready;
 assign record_input={advert_last,advert_available,advert_invalidate,advert_group,advert_plane,
  advert_resource,advert_free,advert_epoch,advert_sequence};
 assign advert_ready=i_record_forward_enable?record_input_ready:1'b1;
 assign record_ready=i_record_sink_enable&&(&cache_advert_ready);
 switch_proactive_credit_advertiser #(.C_NUM_GROUPS(C_NUM_SOURCE_GROUPS),.C_NUM_PLANES(1),
  .C_NUM_RESOURCES(C_NUM_RESOURCES),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_GROUP_WIDTH(3),
  .C_PLANE_WIDTH(1),.C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
  .C_SEQUENCE_WIDTH(C_SEQUENCE_WIDTH))u_shared_advertiser(.i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),
  .i_group_online(group_online),.i_plane_enable(destination_resource_enable),.i_group_epoch(group_epoch),
  .i_resource_free(i_effective_free),.o_advert_valid(advert_valid),.i_advert_ready(advert_ready),
  .o_advert_available(advert_available),.o_advert_invalidate(advert_invalidate),.o_dst_group(advert_group),
  .o_plane_id(advert_plane),.o_resource_id(advert_resource),.o_free_count(advert_free),.o_epoch(advert_epoch),
  .o_sequence(advert_sequence),.o_sweep_last(advert_last),.o_config_error(advert_config));
 switch_fabric_elastic_slice #(.C_PAYLOAD_WIDTH(C_RECORD_WIDTH))u_record_boundary(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_valid(advert_valid&&i_record_forward_enable),
  .o_ready(record_input_ready),.i_payload(record_input),.o_valid(record_valid),.i_ready(record_ready),
  .o_payload(record_output),.o_quiescent(record_idle),.o_config_error(record_config),.o_error(record_error));
 wire record_last,record_available,record_invalidate;wire [2:0] record_group;
 wire record_plane;wire [C_RESOURCE_WIDTH-1:0] record_resource;
 wire [C_COUNT_WIDTH-1:0] record_free;wire [C_EPOCH_WIDTH-1:0] record_epoch;
 wire [C_SEQUENCE_WIDTH-1:0] record_sequence;
 assign {record_last,record_available,record_invalidate,record_group,record_plane,record_resource,
  record_free,record_epoch,record_sequence}=record_output;

 genvar group_index,plane_index,lane_index;
 generate
  for(group_index=0;group_index<C_NUM_SOURCE_GROUPS;group_index=group_index+1)begin:g_group
   wire [C_SOURCES_PER_GROUP-1:0] raw_eligible,raw_hint,raw_probe;
   wire cache_query_valid,cache_query_ready,cache_result_valid,cache_result_ready;
   wire cache_hint_valid,cache_hint_available,cache_probe,cache_query_error,cache_stale,cache_bad,cache_generr,cache_config;
   wire [2:0] cache_query_group;wire cache_query_plane;
   wire [C_RESOURCE_WIDTH-1:0] cache_query_resource;wire [C_COUNT_WIDTH-1:0] cache_hint_free;
   wire [C_EPOCH_WIDTH-1:0] cache_hint_epoch;wire [C_SEQUENCE_WIDTH-1:0] cache_hint_sequence;
   wire adapter_idle,adapter_protocol,adapter_config;
   switch_source_credit_advertisement_cache #(.C_NUM_GROUPS(C_NUM_SOURCE_GROUPS),.C_NUM_PLANES(1),
    .C_NUM_RESOURCES(C_NUM_RESOURCES),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_GROUP_WIDTH(3),
    .C_PLANE_WIDTH(1),.C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
    .C_SEQUENCE_WIDTH(C_SEQUENCE_WIDTH),.C_TIME_WIDTH(C_TIME_WIDTH),.C_TTL_CYCLES(C_TTL_CYCLES),
    .C_ENABLE_GENERATION_WIDTH(C_ENABLE_GENERATION_WIDTH),
    .C_ENTRIES(C_NUM_SOURCE_GROUPS*C_NUM_RESOURCES))u_cache(
    .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_group_enable(group_online),
    .i_plane_enable(destination_resource_enable),.i_group_epoch(group_epoch),
    .i_advert_valid(record_valid&&i_record_sink_enable),.o_advert_ready(cache_advert_ready[group_index]),
    .i_advert_available(record_available),.i_advert_invalidate(record_invalidate),.i_advert_group(record_group),
    .i_advert_plane(record_plane),.i_advert_resource(record_resource),.i_advert_free(record_free),
    .i_advert_epoch(record_epoch),.i_advert_sequence(record_sequence),.i_query_valid(cache_query_valid),
    .o_query_ready(cache_query_ready),.i_query_group(cache_query_group),.i_query_plane(cache_query_plane),
    .i_query_resource(cache_query_resource),.o_result_valid(cache_result_valid),
    .i_result_ready(cache_result_ready),.o_hint_valid(cache_hint_valid),.o_hint_available(cache_hint_available),
    .o_hint_free(cache_hint_free),.o_hint_epoch(cache_hint_epoch),.o_hint_sequence(cache_hint_sequence),
    .o_probe_allowed(cache_probe),.o_query_error(cache_query_error),.o_stale_record_error(cache_stale),
    .o_malformed_record_error(cache_bad),.o_generation_exhausted(cache_generr),.o_config_error(cache_config));
   switch_source_plane_hint_adapter #(.C_SOURCES(C_SOURCES_PER_GROUP),.C_PLANES(1),
    .C_NUM_GROUPS(8),.C_NUM_RESOURCES(C_NUM_RESOURCES),.C_GROUP_WIDTH(3),
    .C_PLANE_WIDTH(1),.C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),
    .C_TIME_WIDTH(C_TIME_WIDTH),.C_REFRESH_CYCLES(C_REFRESH_CYCLES),.C_PAIR_COUNT(C_SOURCES_PER_GROUP))u_adapter(
    .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),
    .i_source_valid(i_source_valid[group_index*C_SOURCES_PER_GROUP+:C_SOURCES_PER_GROUP]),
    .i_source_sop(i_source_sop[group_index*C_SOURCES_PER_GROUP+:C_SOURCES_PER_GROUP]),
    .i_source_dst_group(i_source_dst_group[group_index*C_SOURCES_PER_GROUP*3+:C_SOURCES_PER_GROUP*3]),
    .i_source_resource(source_resource[group_index*C_SOURCES_PER_GROUP*C_RESOURCE_WIDTH+:C_SOURCES_PER_GROUP*C_RESOURCE_WIDTH]),
    .i_group_enable(adapter_group_online),.i_plane_enable(|i_plane_enable),.i_group_epoch(adapter_group_epoch),
    .o_plane_eligible(raw_eligible),.o_using_hint(raw_hint),.o_probe_path(raw_probe),
    .o_cache_query_valid(cache_query_valid),.i_cache_query_ready(cache_query_ready),
    .o_cache_query_group(cache_query_group),.o_cache_query_plane(cache_query_plane),
    .o_cache_query_resource(cache_query_resource),.i_cache_result_valid(cache_result_valid),
    .o_cache_result_ready(cache_result_ready),.i_cache_hint_valid(cache_hint_valid),
    .i_cache_hint_available(cache_hint_available),.i_cache_probe_allowed(cache_probe),
    .i_cache_hint_epoch(cache_hint_epoch),.o_quiescent(adapter_idle),
    .o_protocol_error(adapter_protocol),.o_config_error(adapter_config));
   // advertiser是持续后台扫描，不拥有packet/credit/token，不能阻塞Fabric quiescence。
   // pending只表示该Source Group仍有cache查询；epoch变化会使提交前的旧结果自然失配。
   assign o_group_pending[group_index]=!adapter_idle;
   wire ignored_cache=^{cache_hint_free,cache_hint_sequence,cache_stale,record_last,record_idle};
   assign o_group_error[group_index]=route_error_q[group_index]|record_error|cache_query_error|cache_bad|
    cache_generr|adapter_protocol|cache_config|adapter_config|(ignored_cache&1'b0);
   for(lane_index=0;lane_index<C_SOURCES_PER_GROUP;lane_index=lane_index+1)begin:g_lane
    for(plane_index=0;plane_index<C_NUM_PLANES;plane_index=plane_index+1)begin:g_plane
     localparam integer PAIR_INDEX=lane_index*C_NUM_PLANES+plane_index;
     localparam integer GLOBAL_PAIR=group_index*C_PAIRS_PER_GROUP+PAIR_INDEX;
     assign o_plane_eligible[GLOBAL_PAIR]=raw_eligible[lane_index]&i_plane_enable[plane_index]&
      source_route_legal[group_index*C_SOURCES_PER_GROUP+lane_index];
     assign o_using_hint[GLOBAL_PAIR]=raw_hint[lane_index]&i_plane_enable[plane_index]&
      source_route_legal[group_index*C_SOURCES_PER_GROUP+lane_index];
     assign o_probe_path[GLOBAL_PAIR]=raw_probe[lane_index]&i_plane_enable[plane_index]&
      source_route_legal[group_index*C_SOURCES_PER_GROUP+lane_index];
    end
   end
  end
  for(group_index=0;group_index<C_NUM_SOURCE_GROUPS;group_index=group_index+1)begin:g_epoch
   assign group_epoch[group_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]=i_epoch;
   assign destination_resource_enable[group_index]=|i_plane_enable;
  end
  for(group_index=0;group_index<8;group_index=group_index+1)begin:g_namespace
   if(group_index<C_NUM_SOURCE_GROUPS)begin:g_active
    assign adapter_group_online[group_index]=1'b1;
    assign adapter_group_epoch[group_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]=i_epoch;
   end else begin:g_inactive
    assign adapter_group_online[group_index]=1'b0;
    assign adapter_group_epoch[group_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]=0;
   end
  end
 endgenerate
 assign o_config_error=!CONFIG_LEGAL|advert_config|record_config;
endmodule
`default_nettype wire
