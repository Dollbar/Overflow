`timescale 1ns/1ps
`default_nettype none
// Full-IP同域管理组合层。CSR与Fabric当前必须使用i_clk；异步管理总线需在本模块外做CDC。
// Route/Identity写命令直接进入production owner，管理层不复制active/shadow表或credit账本。
module ualink_switch_full_ip_managed_top #(
 parameter integer C_NUM_STATIONS=8,parameter integer C_NUM_GROUPS=1,
 parameter integer C_TILES_PER_GROUP=1,parameter integer C_INGRESS_PER_TILE=32,
 parameter integer C_BANKS_PER_TILE=8,parameter integer C_NUM_PLANES=1,
 parameter integer C_PORTS_PER_TILE=32,parameter integer C_DST_COUNT=4096,
 parameter integer C_PORT_COUNT=32,
 parameter integer C_NUM_VOQS=C_NUM_GROUPS*C_TILES_PER_GROUP*C_PORTS_PER_TILE*4,
 parameter integer C_BANK_WIDTH=3,parameter integer C_RETURN_BANKS=32,
 parameter integer C_CREDIT_WIDTH=8,parameter integer C_RX_TOKEN_WIDTH=18,
 parameter integer C_COUNT_WIDTH=4,parameter integer C_PORTS=C_NUM_STATIONS*4,
 parameter integer C_RESOURCES=C_TILES_PER_GROUP*C_PORTS_PER_TILE*4,
 parameter integer C_LANES=C_TILES_PER_GROUP*C_BANKS_PER_TILE,
 parameter integer C_ACCOUNTS=(C_LANES+C_NUM_PLANES)*C_RESOURCES,
 parameter integer C_TOTAL_RESOURCES=C_NUM_GROUPS*C_RESOURCES,
 parameter integer C_TOTAL_ACCOUNTS=C_NUM_GROUPS*C_ACCOUNTS,
 parameter integer C_QUEUE_ENTRIES=C_NUM_GROUPS*C_TILES_PER_GROUP*C_NUM_VOQS,
 parameter integer C_STATUS_RESOURCES=(C_TOTAL_RESOURCES>=C_QUEUE_ENTRIES)?C_TOTAL_RESOURCES:C_QUEUE_ENTRIES,
 parameter integer C_RELEASE_TIMEOUT_CYCLES=16,parameter integer C_RELEASE_TIMER_WIDTH=16,
 parameter integer C_FABRIC_TIMEOUT_CYCLES=1024,
 parameter integer C_STATION_INDEX_WIDTH=(C_NUM_STATIONS<=2)?1:(C_NUM_STATIONS<=4)?2:(C_NUM_STATIONS<=8)?3:(C_NUM_STATIONS<=16)?4:(C_NUM_STATIONS<=32)?5:(C_NUM_STATIONS<=64)?6:(C_NUM_STATIONS<=128)?7:8,
 parameter integer C_PORT_INDEX_WIDTH=(C_PORT_COUNT<=2)?1:(C_PORT_COUNT<=4)?2:(C_PORT_COUNT<=8)?3:(C_PORT_COUNT<=16)?4:(C_PORT_COUNT<=32)?5:(C_PORT_COUNT<=64)?6:(C_PORT_COUNT<=128)?7:(C_PORT_COUNT<=256)?8:(C_PORT_COUNT<=512)?9:10,
 parameter integer C_PLANE_INDEX_WIDTH=(C_NUM_PLANES<=2)?1:(C_NUM_PLANES<=4)?2:(C_NUM_PLANES<=8)?3:(C_NUM_PLANES<=16)?4:5,
 parameter integer C_ROUTE_INDEX_WIDTH=(C_DST_COUNT<=32)?5:(C_DST_COUNT<=64)?6:(C_DST_COUNT<=128)?7:(C_DST_COUNT<=256)?8:(C_DST_COUNT<=512)?9:(C_DST_COUNT<=1024)?10:(C_DST_COUNT<=2048)?11:12,
 parameter integer C_RESOURCE_INDEX_WIDTH=(C_STATUS_RESOURCES<=2)?1:(C_STATUS_RESOURCES<=4)?2:(C_STATUS_RESOURCES<=8)?3:(C_STATUS_RESOURCES<=16)?4:(C_STATUS_RESOURCES<=32)?5:(C_STATUS_RESOURCES<=64)?6:(C_STATUS_RESOURCES<=128)?7:(C_STATUS_RESOURCES<=256)?8:(C_STATUS_RESOURCES<=512)?9:(C_STATUS_RESOURCES<=1024)?10:(C_STATUS_RESOURCES<=2048)?11:12,
 parameter integer C_ACCOUNT_INDEX_WIDTH=(C_TOTAL_ACCOUNTS<=2)?1:(C_TOTAL_ACCOUNTS<=4)?2:(C_TOTAL_ACCOUNTS<=8)?3:(C_TOTAL_ACCOUNTS<=16)?4:(C_TOTAL_ACCOUNTS<=32)?5:(C_TOTAL_ACCOUNTS<=64)?6:(C_TOTAL_ACCOUNTS<=128)?7:(C_TOTAL_ACCOUNTS<=256)?8:(C_TOTAL_ACCOUNTS<=512)?9:(C_TOTAL_ACCOUNTS<=1024)?10:(C_TOTAL_ACCOUNTS<=2048)?11:(C_TOTAL_ACCOUNTS<=4096)?12:(C_TOTAL_ACCOUNTS<=8192)?13:(C_TOTAL_ACCOUNTS<=16384)?14:(C_TOTAL_ACCOUNTS<=32768)?15:(C_TOTAL_ACCOUNTS<=65536)?16:(C_TOTAL_ACCOUNTS<=131072)?17:18
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_csr_req_valid,output wire o_csr_req_ready,input wire i_csr_req_write,
 input wire[15:0] i_csr_req_addr,input wire[31:0] i_csr_req_wdata,
 output wire o_csr_rsp_valid,input wire i_csr_rsp_ready,output wire[31:0] o_csr_rsp_rdata,
 output wire o_csr_rsp_error,output wire o_csr_rsp_unsupported,
 input wire[C_PORTS-1:0] i_lane_up,
 input wire[C_PORTS-1:0] i_link_rx_frame_valid,output wire[C_PORTS-1:0] o_link_rx_frame_ready,
 input wire[C_PORTS*512-1:0] i_link_rx_frame_data,input wire[C_PORTS-1:0] i_link_rx_frame_sop,
 input wire[C_PORTS-1:0] i_link_rx_frame_eop,input wire[C_PORTS-1:0] i_link_rx_fec_complete,input wire[C_PORTS-1:0] i_link_rx_crc_ok,
 output wire[C_PORTS-1:0] o_link_control_valid,input wire[C_PORTS-1:0] i_link_control_ready,
 output wire[C_PORTS-1:0] o_link_control_replay_request,output wire[C_PORTS*9-1:0] o_link_control_target,
 output wire[C_PORTS-1:0] o_crc_frame_valid,input wire[C_PORTS-1:0] i_crc_frame_ready,
 output wire[C_PORTS*512-1:0] o_crc_frame_data,output wire[C_PORTS-1:0] o_crc_frame_sop,output wire[C_PORTS-1:0] o_crc_frame_eop,
 output wire[C_PORTS*9-1:0] o_crc_frame_sequence,output wire[C_PORTS-1:0] o_crc_frame_replay,
 output wire[C_PORTS-1:0] o_crc_required,output wire[C_PORTS-1:0] o_physical_valid,output wire[C_PORTS*8-1:0] o_tx_resident_count,
 input wire[C_PORTS*4-1:0] i_upli_credit_connected,input wire[C_PORTS*4-1:0] i_upli_beats_connected,
 input wire[C_PORTS*4-1:0] i_upli_credit_valid,input wire[C_PORTS*4-1:0] i_upli_credit_pool,
 input wire[C_PORTS*8-1:0] i_upli_credit_vc,input wire[C_PORTS*8-1:0] i_upli_credit_num,input wire[C_PORTS*4-1:0] i_upli_credit_init_done,
 output wire[C_PORTS-1:0] o_upli_credit_candidate_ready,
 input wire[C_PORTS-1:0] i_tl_rx_start,input wire[C_PORTS-1:0] i_tl_rx_shared,input wire[C_PORTS*20*C_CREDIT_WIDTH-1:0] i_tl_rx_capacities,
 input wire[C_PORTS-1:0] i_release_path_enable,input wire[C_PORTS-1:0] i_egress_flush,
 output wire[C_NUM_STATIONS*2-1:0] o_station_active_mode,output wire[C_PORTS-1:0] o_port_active,
 output wire[C_PORTS*10-1:0] o_global_port_id,output wire[C_PORTS-1:0] o_rx_release_valid,
 output wire[C_PORTS*C_RX_TOKEN_WIDTH-1:0] o_rx_release_token,output wire[C_PORTS*80-1:0] o_rx_release_vector,
 output wire[C_PORTS-1:0] o_upli_mapping_unsupported,
 output wire o_route_commit_ready,output wire o_route_commit_rejected,output wire o_quiescent,
 output wire o_release_stall_active,output wire o_release_timeout_sticky,
 output wire[31:0] o_release_stall_cycles,output wire[31:0] o_release_timeout_count,
 output wire[C_PORTS-1:0] o_observe_ingress_committed_valid,
 output wire[C_PORTS-1:0] o_observe_ingress_committed_ready,
 output wire[C_PORTS-1:0] o_observe_egress_retired_valid,
 output wire[C_PORTS-1:0] o_observe_egress_retired_ready,
 output wire o_management_error,output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=8)&&(C_PORTS==C_NUM_STATIONS*4)&&
  (C_PORT_COUNT>=C_PORTS)&&(C_PORT_COUNT<=32)&&(C_STATUS_RESOURCES<=(1<<C_RESOURCE_INDEX_WIDTH))&&
  (C_TOTAL_ACCOUNTS<=(1<<C_ACCOUNT_INDEX_WIDTH))&&
  (C_FABRIC_TIMEOUT_CYCLES>=1)&&(C_FABRIC_TIMEOUT_CYCLES<=2047);
 localparam integer C_PHYSICAL_PORT_INDEX_WIDTH=(C_PORTS<=2)?1:(C_PORTS<=4)?2:(C_PORTS<=8)?3:(C_PORTS<=16)?4:(C_PORTS<=32)?5:(C_PORTS<=64)?6:(C_PORTS<=128)?7:(C_PORTS<=256)?8:(C_PORTS<=512)?9:10;
 reg[C_NUM_STATIONS*2-1:0] requested_mode_q;
 reg[C_PORTS-1:0] port_enable_q;reg[C_NUM_PLANES-1:0] plane_enable_q;
 reg route_snapshot_valid_q,identity_snapshot_valid_q;reg[31:0] route_snapshot_q,identity_snapshot_q;
 reg[C_ROUTE_INDEX_WIDTH-1:0] route_snapshot_index_q;reg[C_PORT_INDEX_WIDTH-1:0] identity_snapshot_index_q;
 reg command_error_q;
 wire station_mode_write,port_enable_write,plane_enable_write,route_shadow_write,identity_shadow_write,atomic_commit;
 wire[C_STATION_INDEX_WIDTH-1:0] station_index;wire[1:0] station_mode;
 wire[C_PORT_INDEX_WIDTH-1:0] port_index,identity_index;wire port_enable;
 wire[C_PHYSICAL_PORT_INDEX_WIDTH-1:0] physical_port_index=port_index[C_PHYSICAL_PORT_INDEX_WIDTH-1:0];
 wire[31:0] physical_port_ordinal={{(32-C_PHYSICAL_PORT_INDEX_WIDTH){1'b0}},physical_port_index};
 reg[9:0] status_expected_global;integer status_group_scan,status_tile_scan,status_local_scan;
 always @(*)begin
  status_expected_global=10'd0;
  for(status_group_scan=0;status_group_scan<C_NUM_GROUPS;status_group_scan=status_group_scan+1)
   for(status_tile_scan=0;status_tile_scan<C_TILES_PER_GROUP;status_tile_scan=status_tile_scan+1)
    for(status_local_scan=0;status_local_scan<C_PORTS_PER_TILE;status_local_scan=status_local_scan+1)
     if(physical_port_ordinal==((status_group_scan*C_TILES_PER_GROUP+status_tile_scan)*C_PORTS_PER_TILE+status_local_scan))
      status_expected_global={status_group_scan[2:0],status_tile_scan[1:0],status_local_scan[4:0]};
 end
 wire[9:0] identity_global_value={{(10-C_PORT_INDEX_WIDTH){1'b0}},identity_index};
 wire[31:0] identity_physical_ordinal=(({{29{1'b0}},identity_global_value[9:7]}*C_TILES_PER_GROUP)+
  {{30{1'b0}},identity_global_value[6:5]})*C_PORTS_PER_TILE+{{27{1'b0}},identity_global_value[4:0]};
 wire identity_physical_valid=identity_physical_ordinal<C_PORTS;
 wire[C_PHYSICAL_PORT_INDEX_WIDTH-1:0] identity_physical_index=identity_physical_ordinal[C_PHYSICAL_PORT_INDEX_WIDTH-1:0];
 wire[C_PLANE_INDEX_WIDTH-1:0] plane_index;wire plane_enable;
 wire[C_ROUTE_INDEX_WIDTH-1:0] route_index;wire[31:0] route_shadow_wdata,identity_shadow_wdata;
 wire query_valid,query_ready;wire[2:0] query_kind;wire[31:0] query_index,query_data;
 wire release_timeout_w1c,release_counter_w1c,csr_error_sticky,unsupported_security;
 wire[C_PORT_INDEX_WIDTH-1:0] release_first_port;
 wire[C_NUM_STATIONS-1:0] mgmt_station_busy,mgmt_station_quiescent,mgmt_station_error;
 wire[C_PORTS-1:0] mgmt_release_valid,mgmt_release_ready;
 wire[C_TOTAL_RESOURCES*3-1:0] mgmt_resource_free_raw;
 wire[C_QUEUE_ENTRIES*C_COUNT_WIDTH-1:0] mgmt_queue_occupancy_raw;
 wire[C_STATUS_RESOURCES*3-1:0] mgmt_resource_free=
  {{((C_STATUS_RESOURCES-C_TOTAL_RESOURCES)*3){1'b0}},mgmt_resource_free_raw};
 wire[C_STATUS_RESOURCES*C_COUNT_WIDTH-1:0] mgmt_queue_occupancy=
  {{((C_STATUS_RESOURCES-C_QUEUE_ENTRIES)*C_COUNT_WIDTH){1'b0}},mgmt_queue_occupancy_raw};
 wire[C_TOTAL_ACCOUNTS*3-1:0] mgmt_credit_issued,mgmt_credit_occupied;
 wire[7:0] mgmt_route_epoch;wire mgmt_route_pending,mgmt_fabric_timeout_error;wire[10:0] mgmt_commit_wait;
 wire[31:0] fabric_timeout_limit=C_FABRIC_TIMEOUT_CYCLES;
 wire fabric_timeout_event;
 reg fabric_timeout_episode_q;
 wire[0:0] fabric_timeout_sticky;
 wire[31:0] fabric_timeout_counter;
 wire fabric_timeout_serious_error;
 wire mgmt_upli_credit_error_event_level;
 reg upli_credit_error_episode_q;
 wire upli_credit_error_event;
 wire[0:0] upli_credit_error_sticky;
 wire[31:0] upli_credit_error_counter;
 wire upli_credit_error_serious_error;
 wire[1:0] mgmt_tl_credit_error_event_level;
 reg[1:0] tl_credit_error_episode_q;
 wire[1:0] tl_credit_error_event;
 wire[1:0] tl_credit_error_sticky;
 wire[63:0] tl_credit_error_counters;
 wire tl_credit_error_serious_error;
 wire[3:0] mgmt_destination_return_error_event_level;
 reg[3:0] destination_return_error_episode_q;
 wire[3:0] destination_return_error_event;
 wire[3:0] destination_return_error_sticky;
 wire[127:0] destination_return_error_counters;
 wire destination_return_error_serious_error;
 wire[1:0] mgmt_ingress_queue_error_event_level;
 reg[1:0] ingress_queue_error_episode_q;
 wire[1:0] ingress_queue_error_event;
 wire[1:0] ingress_queue_error_sticky;
 wire[63:0] ingress_queue_error_counters;
 wire ingress_queue_error_serious_error;
 wire[C_NUM_STATIONS*2-1:0] requested_mode_effective;
 wire[C_NUM_STATIONS-1:0] station_commit_pulse;
 wire[C_PORTS-1:0] managed_link_reset;
 wire[31:0] station_status,port_status,route_shadow_status,route_active_status,identity_shadow_status,identity_active_status,plane_status;
 reg[31:0] ras_status[0:31];integer ras_i;
 wire[32*32-1:0] ras_status_flat;
 genvar s;
 generate for(s=0;s<C_NUM_STATIONS;s=s+1)begin:g_mode_mux
  assign requested_mode_effective[s*2+:2]=(station_mode_write&&(station_index==s))?station_mode:requested_mode_q[s*2+:2];
  assign station_commit_pulse[s]=station_mode_write&&(station_index==s);
 end endgenerate
 assign managed_link_reset=~port_enable_q;
 assign station_status={28'd0,mgmt_station_error[station_index],mgmt_station_quiescent[station_index],mgmt_station_busy[station_index],o_port_active[station_index*4]};
 assign port_status={27'd0,o_global_port_id[physical_port_index*10+:10]==status_expected_global,i_lane_up[physical_port_index],o_port_active[physical_port_index],port_enable_q[physical_port_index],managed_link_reset[physical_port_index]};
 assign route_shadow_status=(route_snapshot_valid_q&&(route_snapshot_index_q==route_index))?route_snapshot_q:32'd0;
 assign route_active_status={16'd0,mgmt_route_epoch,5'd0,o_route_commit_ready,mgmt_route_pending,route_snapshot_valid_q};
 assign identity_shadow_status=(identity_snapshot_valid_q&&(identity_snapshot_index_q==identity_index))?identity_snapshot_q:32'd0;
 assign identity_active_status={21'd0,identity_physical_valid?o_global_port_id[identity_physical_index*10+:10]:10'd0,
  identity_physical_valid&&o_port_active[identity_physical_index]};
 assign plane_status={30'd0,plane_enable_q[plane_index],!mgmt_fabric_timeout_error};
 generate for(s=0;s<32;s=s+1)begin:g_ras_flat assign ras_status_flat[s*32+:32]=ras_status[s];end endgenerate
 always @(*)begin
  for(ras_i=0;ras_i<32;ras_i=ras_i+1)ras_status[ras_i]=32'd0;
  ras_status[0]={31'd0,o_error};ras_status[1]={31'd0,o_config_error};ras_status[2]={31'd0,o_route_commit_rejected};
  ras_status[3]={31'd0,mgmt_fabric_timeout_error};ras_status[4]={31'd0,|mgmt_station_error};
  ras_status[5]={31'd0,o_release_timeout_sticky};ras_status[6]=o_release_timeout_count;ras_status[7]=o_release_stall_cycles;
  ras_status[8]=fabric_timeout_counter;
  ras_status[9]={31'd0,upli_credit_error_sticky[0]};
  ras_status[10]=upli_credit_error_counter;
  ras_status[11]={31'd0,tl_credit_error_sticky[0]};
  ras_status[12]=tl_credit_error_counters[31:0];
  ras_status[13]={31'd0,tl_credit_error_sticky[1]};
  ras_status[14]=tl_credit_error_counters[63:32];
  ras_status[15]={31'd0,destination_return_error_sticky[0]};
  ras_status[16]=destination_return_error_counters[31:0];
  ras_status[17]={31'd0,destination_return_error_sticky[1]};
  ras_status[18]=destination_return_error_counters[63:32];
  ras_status[19]={31'd0,destination_return_error_sticky[2]};
  ras_status[20]=destination_return_error_counters[95:64];
  ras_status[21]={31'd0,destination_return_error_sticky[3]};
  ras_status[22]=destination_return_error_counters[127:96];
  ras_status[23]={31'd0,ingress_queue_error_sticky[0]};
  ras_status[24]=ingress_queue_error_counters[31:0];
  ras_status[25]={31'd0,ingress_queue_error_sticky[1]};
  ras_status[26]=ingress_queue_error_counters[63:32];
 end
 assign fabric_timeout_event=mgmt_route_pending&&!fabric_timeout_episode_q&&
  ({21'd0,mgmt_commit_wait}==fabric_timeout_limit);
 always @(posedge i_clk)begin
  if(!i_rstn)begin requested_mode_q<=0;port_enable_q<=0;plane_enable_q<=0;route_snapshot_valid_q<=0;identity_snapshot_valid_q<=0;
   route_snapshot_q<=0;identity_snapshot_q<=0;route_snapshot_index_q<=0;identity_snapshot_index_q<=0;command_error_q<=0;end
  else begin
   if(station_mode_write)requested_mode_q[station_index*2+:2]<=station_mode;
   // CSR仅在已验证索引后产生write pulse，因此这里不会对非法动态索引寻址。
   if(port_enable_write)port_enable_q[physical_port_index]<=port_enable;
   if(plane_enable_write)plane_enable_q[plane_index]<=plane_enable;
   if(route_shadow_write)begin route_snapshot_valid_q<=1;route_snapshot_q<=route_shadow_wdata;route_snapshot_index_q<=route_index;end
   if(identity_shadow_write)begin identity_snapshot_valid_q<=1;identity_snapshot_q<=identity_shadow_wdata;identity_snapshot_index_q<=identity_index;end
   if(atomic_commit&&mgmt_route_pending)command_error_q<=1;
  end
 end
 assign destination_return_error_event=mgmt_destination_return_error_event_level&
  ~destination_return_error_episode_q;
 always @(posedge i_clk)begin
  if(!i_rstn)destination_return_error_episode_q<=4'b0000;
  else destination_return_error_episode_q<=mgmt_destination_return_error_event_level;
 end
 always @(posedge i_clk)begin
  if(!i_rstn)fabric_timeout_episode_q<=1'b0;
  else if(!mgmt_route_pending)fabric_timeout_episode_q<=1'b0;
  else if(fabric_timeout_event)fabric_timeout_episode_q<=1'b1;
 end
 assign upli_credit_error_event=mgmt_upli_credit_error_event_level&&!upli_credit_error_episode_q;
 always @(posedge i_clk)begin
  if(!i_rstn)upli_credit_error_episode_q<=1'b0;
  else upli_credit_error_episode_q<=mgmt_upli_credit_error_event_level;
 end
 assign tl_credit_error_event=mgmt_tl_credit_error_event_level&~tl_credit_error_episode_q;
 always @(posedge i_clk)begin
  if(!i_rstn)tl_credit_error_episode_q<=2'b00;
  else tl_credit_error_episode_q<=mgmt_tl_credit_error_event_level;
 end
 assign ingress_queue_error_event=mgmt_ingress_queue_error_event_level&
  ~ingress_queue_error_episode_q;
 always @(posedge i_clk)begin
  if(!i_rstn)ingress_queue_error_episode_q<=2'b00;
  else ingress_queue_error_episode_q<=mgmt_ingress_queue_error_event_level;
 end

 switch_ras_controller #(.C_NUM_EVENTS(1),.C_COUNTER_WIDTH(32))u_fabric_timeout_ras(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_event(fabric_timeout_event),.i_clear(1'b0),
  .o_sticky(fabric_timeout_sticky),.o_counters(fabric_timeout_counter),
  .o_serious_error(fabric_timeout_serious_error));

 switch_ras_controller #(.C_NUM_EVENTS(1),.C_COUNTER_WIDTH(32))u_upli_credit_ras(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_event(upli_credit_error_event),.i_clear(1'b0),
  .o_sticky(upli_credit_error_sticky),.o_counters(upli_credit_error_counter),
  .o_serious_error(upli_credit_error_serious_error));

 switch_ras_controller #(.C_NUM_EVENTS(2),.C_COUNTER_WIDTH(32))u_tl_credit_ras(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_event(tl_credit_error_event),.i_clear(2'b00),
  .o_sticky(tl_credit_error_sticky),.o_counters(tl_credit_error_counters),
  .o_serious_error(tl_credit_error_serious_error));

 switch_ras_controller #(.C_NUM_EVENTS(4),.C_COUNTER_WIDTH(32))u_destination_return_ras(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_event(destination_return_error_event),.i_clear(4'b0000),
  .o_sticky(destination_return_error_sticky),.o_counters(destination_return_error_counters),
  .o_serious_error(destination_return_error_serious_error));

 switch_ras_controller #(.C_NUM_EVENTS(2),.C_COUNTER_WIDTH(32))u_ingress_queue_ras(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_event(ingress_queue_error_event),.i_clear(2'b00),
  .o_sticky(ingress_queue_error_sticky),.o_counters(ingress_queue_error_counters),
  .o_serious_error(ingress_queue_error_serious_error));

 switch_fabric_status_query_backend #(.C_RESOURCES(C_STATUS_RESOURCES),.C_ACCOUNTS(C_TOTAL_ACCOUNTS),.C_RAS_COUNTERS(32),
  .C_RESOURCE_INDEX_WIDTH(C_RESOURCE_INDEX_WIDTH),.C_ACCOUNT_INDEX_WIDTH(C_ACCOUNT_INDEX_WIDTH),.C_RAS_INDEX_WIDTH(5),
  .C_CREDIT_COUNT_WIDTH(3),.C_QUEUE_COUNT_WIDTH(C_COUNT_WIDTH),.C_RESPONSE_LATENCY(1))u_query(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_enable(1'b1),.i_query_valid(query_valid),.o_query_ready(query_ready),
  .i_query_kind(query_kind),.i_query_index(query_index),.o_query_data(query_data),.i_resource_free(mgmt_resource_free),
  .i_queue_occupancy(mgmt_queue_occupancy),.i_account_issued(mgmt_credit_issued),.i_account_occupied(mgmt_credit_occupied),
  .i_ras_counters(ras_status_flat));

 switch_fabric_csr_window #(.C_NUM_STATIONS(C_NUM_STATIONS),.C_MAX_PORTS(C_PORT_COUNT),.C_PHYSICAL_PORTS(C_PORTS),.C_NUM_TILES(C_NUM_GROUPS*C_TILES_PER_GROUP),
  .C_NUM_GROUPS(C_NUM_GROUPS),.C_NUM_PLANES(C_NUM_PLANES),.C_ACTIVE_SERVICE_UNITS(C_PORTS),.C_ROUTE_ENTRIES(C_DST_COUNT),
  .C_RESOURCES(C_STATUS_RESOURCES),.C_ACCOUNTS(C_TOTAL_ACCOUNTS),.C_RAS_COUNTERS(32),
  .C_STATION_INDEX_WIDTH(C_STATION_INDEX_WIDTH),.C_PORT_INDEX_WIDTH(C_PORT_INDEX_WIDTH),.C_PLANE_INDEX_WIDTH(C_PLANE_INDEX_WIDTH),
  .C_ROUTE_INDEX_WIDTH(C_ROUTE_INDEX_WIDTH),.C_RESOURCE_INDEX_WIDTH(C_RESOURCE_INDEX_WIDTH),.C_ACCOUNT_INDEX_WIDTH(C_ACCOUNT_INDEX_WIDTH),
  .C_RAS_INDEX_WIDTH(5),.C_RELEASE_PORTS(C_PORTS),.C_RELEASE_INDEX_WIDTH(C_PORT_INDEX_WIDTH),
  .C_RELEASE_TIMEOUT_CYCLES(C_RELEASE_TIMEOUT_CYCLES),.C_RELEASE_TIMER_WIDTH(C_RELEASE_TIMER_WIDTH))u_csr(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_req_valid(i_csr_req_valid),.o_req_ready(o_csr_req_ready),.i_req_write(i_csr_req_write),
  .i_req_addr(i_csr_req_addr),.i_req_wdata(i_csr_req_wdata),.o_rsp_valid(o_csr_rsp_valid),.i_rsp_ready(i_csr_rsp_ready),
  .o_rsp_rdata(o_csr_rsp_rdata),.o_rsp_error(o_csr_rsp_error),.o_rsp_unsupported(o_csr_rsp_unsupported),
  .i_station_active_mode(o_station_active_mode[station_index*2+:2]),.i_station_status(station_status),.i_port_status(port_status),
  .i_route_shadow_data(route_shadow_status),.i_route_active_data(route_active_status),.i_route_pending(mgmt_route_pending),
  .i_identity_shadow_data(identity_shadow_status),.i_identity_active_data(identity_active_status),.i_plane_status(plane_status),
  .i_release_valid(mgmt_release_valid),.i_release_ready(mgmt_release_ready),.i_fabric_timeout_error(mgmt_fabric_timeout_error),
  .o_station_mode_write(station_mode_write),.o_station_index(station_index),.o_station_mode(station_mode),
  .o_port_enable_write(port_enable_write),.o_port_index(port_index),.o_port_enable(port_enable),
  .o_plane_enable_write(plane_enable_write),.o_plane_index(plane_index),.o_plane_enable(plane_enable),
  .o_route_shadow_write(route_shadow_write),.o_route_index(route_index),.o_route_shadow_wdata(route_shadow_wdata),
  .o_identity_shadow_write(identity_shadow_write),.o_identity_index(identity_index),.o_identity_shadow_wdata(identity_shadow_wdata),
  .o_atomic_commit(atomic_commit),.o_query_valid(query_valid),.i_query_ready(query_ready),.o_query_kind(query_kind),
  .o_query_index(query_index),.i_query_data(query_data),.o_release_stall_active(o_release_stall_active),
  .o_release_timeout_sticky(o_release_timeout_sticky),.o_release_stall_cycles(o_release_stall_cycles),
  .o_release_timeout_count(o_release_timeout_count),.o_release_first_port(release_first_port),
  .o_release_timeout_w1c(release_timeout_w1c),.o_release_counter_w1c(release_counter_w1c),
  .o_error_sticky(csr_error_sticky),.o_unsupported_security(unsupported_security));

 ualink_switch_full_ip_top #(.C_NUM_STATIONS(C_NUM_STATIONS),.C_NUM_GROUPS(C_NUM_GROUPS),.C_TILES_PER_GROUP(C_TILES_PER_GROUP),
  .C_INGRESS_PER_TILE(C_INGRESS_PER_TILE),.C_BANKS_PER_TILE(C_BANKS_PER_TILE),.C_NUM_PLANES(C_NUM_PLANES),
  .C_PORTS_PER_TILE(C_PORTS_PER_TILE),.C_DST_COUNT(C_DST_COUNT),.C_PORT_COUNT(C_PORT_COUNT),.C_NUM_VOQS(C_NUM_VOQS),
  .C_BANK_WIDTH(C_BANK_WIDTH),.C_RETURN_BANKS(C_RETURN_BANKS),.C_CREDIT_WIDTH(C_CREDIT_WIDTH),
  .C_FABRIC_TIMEOUT_CYCLES(C_FABRIC_TIMEOUT_CYCLES))u_full(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_enable(i_enable),.i_station_requested_mode(requested_mode_effective),
  .i_station_mode_commit(station_commit_pulse),.i_lane_up(i_lane_up),.i_port_link_reset(managed_link_reset),
  .i_link_rx_frame_valid(i_link_rx_frame_valid),.o_link_rx_frame_ready(o_link_rx_frame_ready),.i_link_rx_frame_data(i_link_rx_frame_data),
  .i_link_rx_frame_sop(i_link_rx_frame_sop),.i_link_rx_frame_eop(i_link_rx_frame_eop),.i_link_rx_fec_complete(i_link_rx_fec_complete),.i_link_rx_crc_ok(i_link_rx_crc_ok),
  .o_link_control_valid(o_link_control_valid),.i_link_control_ready(i_link_control_ready),.o_link_control_replay_request(o_link_control_replay_request),.o_link_control_target(o_link_control_target),
  .o_crc_frame_valid(o_crc_frame_valid),.i_crc_frame_ready(i_crc_frame_ready),.o_crc_frame_data(o_crc_frame_data),.o_crc_frame_sop(o_crc_frame_sop),.o_crc_frame_eop(o_crc_frame_eop),
  .o_crc_frame_sequence(o_crc_frame_sequence),.o_crc_frame_replay(o_crc_frame_replay),.o_crc_required(o_crc_required),.o_physical_valid(o_physical_valid),.o_tx_resident_count(o_tx_resident_count),
  .i_upli_credit_connected(i_upli_credit_connected),.i_upli_beats_connected(i_upli_beats_connected),.i_upli_credit_valid(i_upli_credit_valid),.i_upli_credit_pool(i_upli_credit_pool),
  .i_upli_credit_vc(i_upli_credit_vc),.i_upli_credit_num(i_upli_credit_num),.i_upli_credit_init_done(i_upli_credit_init_done),.o_upli_credit_candidate_ready(o_upli_credit_candidate_ready),
  .o_mgmt_upli_credit_error_event_level(mgmt_upli_credit_error_event_level),
  .o_mgmt_tl_credit_underflow_event_level(mgmt_tl_credit_error_event_level[0]),
  .o_mgmt_tl_credit_overflow_event_level(mgmt_tl_credit_error_event_level[1]),
  .o_mgmt_destination_return_error_event_level(mgmt_destination_return_error_event_level),
  .o_mgmt_ingress_queue_overflow_event_level(mgmt_ingress_queue_error_event_level[0]),
  .o_mgmt_ingress_queue_underflow_event_level(mgmt_ingress_queue_error_event_level[1]),
  .i_tl_rx_start(i_tl_rx_start),.i_tl_rx_shared(i_tl_rx_shared),.i_tl_rx_capacities(i_tl_rx_capacities),
  .i_route_shadow_write(route_shadow_write),.i_route_shadow_dst_id({{(12-C_ROUTE_INDEX_WIDTH){1'b0}},route_index}),
  .i_route_shadow_valid(route_shadow_wdata[0]),.i_route_shadow_global_port(route_shadow_wdata[10:1]),.i_route_shadow_policy(route_shadow_wdata[18:11]),
  .i_identity_shadow_write(identity_shadow_write),.i_identity_shadow_global_port({{(10-C_PORT_INDEX_WIDTH){1'b0}},identity_index}),.i_identity_shadow_active(identity_shadow_wdata[0]),
  .i_identity_shadow_group(identity_shadow_wdata[3:1]),.i_identity_shadow_tile(identity_shadow_wdata[5:4]),.i_identity_shadow_local_port(identity_shadow_wdata[10:6]),
  .i_identity_shadow_station(identity_shadow_wdata[18:11]),.i_identity_shadow_lane_mask(identity_shadow_wdata[22:19]),
  .i_identity_shadow_service_units(identity_shadow_wdata[25:23]),.i_identity_shadow_station_mode(identity_shadow_wdata[27:26]),
  .i_route_commit_request(atomic_commit),.i_shadow_illegal(1'b0),.i_plane_enable(plane_enable_q),
  .i_release_path_enable(i_release_path_enable),.i_egress_flush(i_egress_flush),.o_station_active_mode(o_station_active_mode),
  .o_port_active(o_port_active),.o_global_port_id(o_global_port_id),.o_rx_release_valid(o_rx_release_valid),.o_rx_release_token(o_rx_release_token),
  .o_rx_release_vector(o_rx_release_vector),.o_upli_mapping_unsupported(o_upli_mapping_unsupported),.o_route_commit_ready(o_route_commit_ready),
  .o_route_commit_rejected(o_route_commit_rejected),.o_quiescent(o_quiescent),.o_config_error(o_config_error),.o_error(o_error),
  .o_mgmt_route_epoch(mgmt_route_epoch),.o_mgmt_route_pending(mgmt_route_pending),.o_mgmt_commit_wait_cycles(mgmt_commit_wait),
  .o_mgmt_fabric_timeout_error(mgmt_fabric_timeout_error),.o_mgmt_station_busy(mgmt_station_busy),.o_mgmt_station_quiescent(mgmt_station_quiescent),
  .o_mgmt_station_error(mgmt_station_error),.o_mgmt_release_valid(mgmt_release_valid),.o_mgmt_release_ready(mgmt_release_ready),
  .o_mgmt_resource_free(mgmt_resource_free_raw),.o_mgmt_queue_occupancy(mgmt_queue_occupancy_raw),
  .o_mgmt_credit_issued(mgmt_credit_issued),.o_mgmt_credit_occupied(mgmt_credit_occupied),
  .o_observe_ingress_committed_valid(o_observe_ingress_committed_valid),
  .o_observe_ingress_committed_ready(o_observe_ingress_committed_ready),
  .o_observe_egress_retired_valid(o_observe_egress_retired_valid),
  .o_observe_egress_retired_ready(o_observe_egress_retired_ready));
 assign o_management_error=!CONFIG_LEGAL|csr_error_sticky|unsupported_security|command_error_q|o_release_timeout_sticky;
 wire unused=^{release_first_port,release_timeout_w1c,release_counter_w1c,mgmt_commit_wait,
  fabric_timeout_sticky,fabric_timeout_serious_error,upli_credit_error_serious_error,
  tl_credit_error_serious_error,destination_return_error_serious_error,
  ingress_queue_error_serious_error};
endmodule
`default_nettype wire
