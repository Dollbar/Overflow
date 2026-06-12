`timescale 1ns/1ps
`default_nettype none
// 已完成route/identity/commit的多入口Tile集成层；不重复查表，也不拥有下游credit账本。
module switch_tile_multi_ingress #(
 parameter integer C_INGRESS_PORTS=4,parameter integer C_NUM_BANKS=2,
 parameter integer C_NUM_GROUPS=2,parameter integer C_TILES=2,parameter integer C_NUM_CLASSES=2,
 parameter integer C_PORTS_PER_TILE=32,parameter integer C_ACTIVE_GROUPS=C_NUM_GROUPS,
 parameter integer C_NUM_VOQS=8,parameter integer C_QUEUE_DEPTH=4,
 parameter integer C_DATA_WIDTH=32,parameter integer C_META_WIDTH=8,
 parameter integer C_QUEUE_WIDTH=3,parameter integer C_COUNT_WIDTH=3,
 parameter integer C_INGRESS_WIDTH=2,parameter integer C_BANK_WIDTH=1,
 parameter integer C_CLASS_WIDTH=1,parameter integer C_ADDR_WIDTH=2,
 parameter integer C_POLICY_WIDTH=4,parameter integer C_EPOCH_WIDTH=4,
 parameter integer C_LOCAL_GROUP=0
)(
 input wire i_clk,input wire i_rstn,input wire [C_INGRESS_PORTS-1:0] i_valid,
 output wire [C_INGRESS_PORTS-1:0] o_ready,
 input wire [C_INGRESS_PORTS*C_DATA_WIDTH-1:0] i_data,
 input wire [C_INGRESS_PORTS*C_META_WIDTH-1:0] i_meta,
 input wire [C_INGRESS_PORTS*3-1:0] i_dst_group,input wire [C_INGRESS_PORTS*2-1:0] i_dst_tile,
 input wire [C_INGRESS_PORTS*5-1:0] i_dst_port,
 input wire [C_INGRESS_PORTS*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_INGRESS_PORTS*10-1:0] i_src_port,input wire [C_INGRESS_PORTS*2-1:0] i_vc,
 input wire [C_INGRESS_PORTS-1:0] i_pool,
 input wire [C_INGRESS_PORTS*C_POLICY_WIDTH-1:0] i_route_policy,
 input wire [C_INGRESS_PORTS*C_EPOCH_WIDTH-1:0] i_route_epoch,
 input wire [C_INGRESS_PORTS-1:0] i_sop,input wire [C_INGRESS_PORTS-1:0] i_eop,
 input wire [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
 output wire [C_NUM_BANKS-1:0] o_local_valid,input wire [C_NUM_BANKS-1:0] i_local_ready,
 output wire [C_NUM_BANKS-1:0] o_core_valid,input wire [C_NUM_BANKS-1:0] i_core_ready,
 output wire [C_NUM_BANKS*C_DATA_WIDTH-1:0] o_data,
 output wire [C_NUM_BANKS*C_META_WIDTH-1:0] o_meta,
 output wire [C_NUM_BANKS*3-1:0] o_dst_group,output wire [C_NUM_BANKS*2-1:0] o_dst_tile,
 output wire [C_NUM_BANKS*5-1:0] o_dst_port,
 output wire [C_NUM_BANKS*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_NUM_BANKS*10-1:0] o_src_port,output wire [C_NUM_BANKS*2-1:0] o_vc,
 output wire [C_NUM_BANKS-1:0] o_pool,
 output wire [C_NUM_BANKS*C_POLICY_WIDTH-1:0] o_route_policy,
 output wire [C_NUM_BANKS*C_EPOCH_WIDTH-1:0] o_route_epoch,
 output wire [C_NUM_BANKS-1:0] o_sop,output wire [C_NUM_BANKS-1:0] o_eop,
 output wire [C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_occupancy,
 output wire o_overflow_event_level,output wire o_underflow_event_level,
 output wire o_config_error,output wire o_error,output wire o_quiescent
);
 localparam integer C_PACK_WIDTH=C_META_WIDTH+3+2+5+C_CLASS_WIDTH+10+2+1+C_POLICY_WIDTH+C_EPOCH_WIDTH;
 localparam integer C_COARSE_VOQS=C_NUM_GROUPS*C_TILES*C_NUM_CLASSES;
 localparam integer C_PORT_VOQS=C_ACTIVE_GROUPS*C_TILES*C_PORTS_PER_TILE*C_NUM_CLASSES;
 localparam C_PORT_GRAINED=(C_NUM_VOQS==C_PORT_VOQS);
 localparam [2:0] C_LOCAL_GROUP_VALUE=C_LOCAL_GROUP[2:0];
 localparam CONFIG_LEGAL=(C_INGRESS_PORTS>=1)&&(C_INGRESS_PORTS<=32)&&
  (C_NUM_BANKS>=1)&&(C_NUM_BANKS<=32)&&(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&
  (C_TILES>=1)&&(C_TILES<=4)&&(C_ACTIVE_GROUPS>=1)&&(C_ACTIVE_GROUPS<=C_NUM_GROUPS)&&
  (C_PORTS_PER_TILE>=1)&&(C_PORTS_PER_TILE<=32)&&(C_NUM_CLASSES>=1)&&
  ((C_NUM_VOQS==C_COARSE_VOQS)||C_PORT_GRAINED)&&((1<<C_QUEUE_WIDTH)>=C_NUM_VOQS)&&
  ((1<<C_BANK_WIDTH)==C_NUM_BANKS)&&((1<<C_INGRESS_WIDTH)>=C_INGRESS_PORTS)&&
  (C_LOCAL_GROUP>=0)&&(C_LOCAL_GROUP<C_NUM_GROUPS);
 wire [C_INGRESS_PORTS-1:0] route_legal,buffer_valid,buffer_ready;
 reg [C_INGRESS_PORTS*C_QUEUE_WIDTH-1:0] queue_bus;
 wire [C_INGRESS_PORTS*C_PACK_WIDTH-1:0] packed_input;
 wire [C_NUM_BANKS*C_PACK_WIDTH-1:0] buffer_packed_output;
 wire [C_NUM_BANKS*C_DATA_WIDTH-1:0] buffer_data;
 reg [C_NUM_BANKS-1:0] dequeue_request,dequeue_ready;
 reg [C_NUM_BANKS*C_QUEUE_WIDTH-1:0] dequeue_queue;
 wire [C_NUM_BANKS-1:0] dequeue_valid,dequeue_sop,dequeue_eop;
 wire [C_NUM_VOQS*C_COUNT_WIDTH-1:0] reserved_unused;
 wire [C_NUM_BANKS-1:0] bank_conflict_unused;wire [C_INGRESS_PORTS-1:0] retry_unused;
 wire [15:0] total_occupancy_unused,total_reserved_unused;
 wire buffer_protocol_error,buffer_overflow_error,buffer_underflow_error,buffer_config_error,buffer_error;
 wire buffer_quiescent;
 reg protocol_error_q;
 reg [C_NUM_BANKS-1:0] select_valid_q;
 reg [C_NUM_BANKS*C_QUEUE_WIDTH-1:0] select_queue_q;
 reg [C_NUM_BANKS*C_QUEUE_WIDTH-1:0] rr_queue_q;
 reg [C_NUM_BANKS-1:0] output_valid_q,output_sop_q,output_eop_q;
 reg [C_NUM_BANKS*C_DATA_WIDTH-1:0] output_data_q;
 reg [C_NUM_BANKS*C_PACK_WIDTH-1:0] output_packed_q;
 wire [C_NUM_BANKS-1:0] output_accept;
 integer queue_input_index,queue_number,schedule_bank_index,scan_offset,scan_queue;
 integer state_input_index,state_bank_index;
 integer input_group_value,input_tile_value,input_port_value,input_class_value;
 reg found_queue;
 genvar pack_index,out_index;
 generate for(pack_index=0;pack_index<C_INGRESS_PORTS;pack_index=pack_index+1)begin:g_pack
  assign route_legal[pack_index]=({{29{1'b0}},i_dst_group[pack_index*3+:3]}<C_ACTIVE_GROUPS)&&
   ({{30{1'b0}},i_dst_tile[pack_index*2+:2]}<C_TILES)&&
   ({{27{1'b0}},i_dst_port[pack_index*5+:5]}<C_PORTS_PER_TILE)&&
   ({{(32-C_CLASS_WIDTH){1'b0}},i_class[pack_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]}<C_NUM_CLASSES);
  assign packed_input[pack_index*C_PACK_WIDTH+:C_PACK_WIDTH]={
   i_route_epoch[pack_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH],
   i_route_policy[pack_index*C_POLICY_WIDTH+:C_POLICY_WIDTH],i_pool[pack_index],
   i_vc[pack_index*2+:2],i_src_port[pack_index*10+:10],
   i_class[pack_index*C_CLASS_WIDTH+:C_CLASS_WIDTH],i_dst_port[pack_index*5+:5],
   i_dst_tile[pack_index*2+:2],i_dst_group[pack_index*3+:3],i_meta[pack_index*C_META_WIDTH+:C_META_WIDTH]};
 end endgenerate
 assign buffer_valid=i_valid&route_legal&{C_INGRESS_PORTS{CONFIG_LEGAL}};
 assign o_ready=buffer_ready&route_legal&{C_INGRESS_PORTS{CONFIG_LEGAL}};
 always @(*)begin
  queue_bus={(C_INGRESS_PORTS*C_QUEUE_WIDTH){1'b0}};
  for(queue_input_index=0;queue_input_index<C_INGRESS_PORTS;queue_input_index=queue_input_index+1)begin
   queue_number=0;input_group_value=0;input_tile_value=0;input_port_value=0;input_class_value=0;
   if(route_legal[queue_input_index])begin
    input_group_value={{29{1'b0}},i_dst_group[queue_input_index*3+:3]};
    input_tile_value={{30{1'b0}},i_dst_tile[queue_input_index*2+:2]};
    input_port_value={{27{1'b0}},i_dst_port[queue_input_index*5+:5]};
    input_class_value={{(32-C_CLASS_WIDTH){1'b0}},i_class[queue_input_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]};
    // Port-grained模式以local port为最低维，使queue%bank与Group local的dst_port%bank一致。
    // 不同class仍有独立VOQ，同时避免无资源冲突流量在两级bank映射间持续交叉。
    if(C_PORT_GRAINED)
     queue_number=(((input_group_value*C_TILES)+input_tile_value)*C_NUM_CLASSES+input_class_value)*C_PORTS_PER_TILE+input_port_value;
    else queue_number=((input_group_value*C_TILES)+input_tile_value)*C_NUM_CLASSES+input_class_value;
   end
   if(queue_number<C_NUM_VOQS)queue_bus[queue_input_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]=queue_number[C_QUEUE_WIDTH-1:0];
  end
 end
 // 每bank独立扫描本bank VOQ；选择在首次展示时锁定，直到该packet的EOP真实握手。
 always @(*)begin
  dequeue_request={C_NUM_BANKS{1'b0}};dequeue_queue={(C_NUM_BANKS*C_QUEUE_WIDTH){1'b0}};
  scan_offset=0;scan_queue=0;
  for(schedule_bank_index=0;schedule_bank_index<C_NUM_BANKS;schedule_bank_index=schedule_bank_index+1)begin
   found_queue=1'b0;
   // Packet owner允许相邻beat之间存在合法bubble；队列暂空时保持owner等待，不能发出空读并误报underflow。
   if(select_valid_q[schedule_bank_index])begin
    if(o_occupancy[select_queue_q[schedule_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]*C_COUNT_WIDTH+:C_COUNT_WIDTH]!=0)begin
     dequeue_request[schedule_bank_index]=1'b1;
     dequeue_queue[schedule_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]=select_queue_q[schedule_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH];end
   end else for(scan_offset=0;scan_offset<C_NUM_VOQS;scan_offset=scan_offset+1)begin
    scan_queue={{(32-C_QUEUE_WIDTH){1'b0}},rr_queue_q[schedule_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]}+scan_offset;
    if(scan_queue>=C_NUM_VOQS)scan_queue=scan_queue-C_NUM_VOQS;
    if(!found_queue&&(scan_queue%C_NUM_BANKS)==schedule_bank_index&&
       o_occupancy[scan_queue*C_COUNT_WIDTH+:C_COUNT_WIDTH]!=0)begin
      found_queue=1'b1;dequeue_request[schedule_bank_index]=1'b1;
      dequeue_queue[schedule_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]=scan_queue[C_QUEUE_WIDTH-1:0];end
   end
  end
 end
 generate for(out_index=0;out_index<C_NUM_BANKS;out_index=out_index+1)begin:g_unpack
  assign o_data[out_index*C_DATA_WIDTH+:C_DATA_WIDTH]=output_data_q[out_index*C_DATA_WIDTH+:C_DATA_WIDTH];
  assign o_meta[out_index*C_META_WIDTH+:C_META_WIDTH]=output_packed_q[out_index*C_PACK_WIDTH+:C_META_WIDTH];
  assign o_dst_group[out_index*3+:3]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+:3];
  assign o_dst_tile[out_index*2+:2]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+3+:2];
  assign o_dst_port[out_index*5+:5]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+5+:5];
  assign o_class[out_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+10+:C_CLASS_WIDTH];
  assign o_src_port[out_index*10+:10]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+10+C_CLASS_WIDTH+:10];
  assign o_vc[out_index*2+:2]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+20+C_CLASS_WIDTH+:2];
  assign o_pool[out_index]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+22+C_CLASS_WIDTH];
  assign o_route_policy[out_index*C_POLICY_WIDTH+:C_POLICY_WIDTH]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+23+C_CLASS_WIDTH+:C_POLICY_WIDTH];
  assign o_route_epoch[out_index*C_EPOCH_WIDTH+:C_EPOCH_WIDTH]=output_packed_q[out_index*C_PACK_WIDTH+C_META_WIDTH+23+C_CLASS_WIDTH+C_POLICY_WIDTH+:C_EPOCH_WIDTH];
  assign o_local_valid[out_index]=output_valid_q[out_index]&&(o_dst_group[out_index*3+:3]==C_LOCAL_GROUP_VALUE);
  assign o_core_valid[out_index]=output_valid_q[out_index]&&(o_dst_group[out_index*3+:3]!=C_LOCAL_GROUP_VALUE);
  assign output_accept[out_index]=(o_local_valid[out_index]&&i_local_ready[out_index])||
   (o_core_valid[out_index]&&i_core_ready[out_index]);
 end endgenerate
 always @(*)begin
  dequeue_ready=~output_valid_q|output_accept;
 end
 assign o_sop=output_sop_q;assign o_eop=output_eop_q;
 assign o_config_error=!CONFIG_LEGAL|buffer_config_error;
 assign o_error=o_config_error|protocol_error_q|buffer_error|buffer_protocol_error|
  buffer_overflow_error|buffer_underflow_error;
 assign o_quiescent=CONFIG_LEGAL&&buffer_quiescent&&!(|select_valid_q)&&!(|output_valid_q);
 always @(posedge i_clk)begin
  if(!i_rstn)begin protocol_error_q<=1'b0;select_valid_q<={C_NUM_BANKS{1'b0}};
   select_queue_q<={(C_NUM_BANKS*C_QUEUE_WIDTH){1'b0}};rr_queue_q<={(C_NUM_BANKS*C_QUEUE_WIDTH){1'b0}};
   output_valid_q<={C_NUM_BANKS{1'b0}};output_sop_q<={C_NUM_BANKS{1'b0}};output_eop_q<={C_NUM_BANKS{1'b0}};
   output_data_q<={(C_NUM_BANKS*C_DATA_WIDTH){1'b0}};output_packed_q<={(C_NUM_BANKS*C_PACK_WIDTH){1'b0}};end
  else begin
   for(state_input_index=0;state_input_index<C_INGRESS_PORTS;state_input_index=state_input_index+1)
    if(i_valid[state_input_index]&&!route_legal[state_input_index])protocol_error_q<=1'b1;
   for(state_bank_index=0;state_bank_index<C_NUM_BANKS;state_bank_index=state_bank_index+1)begin
    if(dequeue_valid[state_bank_index]&&dequeue_ready[state_bank_index])begin
     output_valid_q[state_bank_index]<=1'b1;output_data_q[state_bank_index*C_DATA_WIDTH+:C_DATA_WIDTH]
      <=buffer_data[state_bank_index*C_DATA_WIDTH+:C_DATA_WIDTH];
     output_packed_q[state_bank_index*C_PACK_WIDTH+:C_PACK_WIDTH]
      <=buffer_packed_output[state_bank_index*C_PACK_WIDTH+:C_PACK_WIDTH];
     output_sop_q[state_bank_index]<=dequeue_sop[state_bank_index];output_eop_q[state_bank_index]<=dequeue_eop[state_bank_index];
    end else if(output_accept[state_bank_index])output_valid_q[state_bank_index]<=1'b0;
    if(dequeue_valid[state_bank_index])begin
    if(!select_valid_q[state_bank_index]&&!dequeue_ready[state_bank_index])begin select_valid_q[state_bank_index]<=1'b1;
     select_queue_q[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]<=dequeue_queue[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH];end
    else if(dequeue_ready[state_bank_index])begin
     if(dequeue_eop[state_bank_index])begin select_valid_q[state_bank_index]<=1'b0;
      if(({{(32-C_QUEUE_WIDTH){1'b0}},dequeue_queue[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]}+C_NUM_BANKS)>=C_NUM_VOQS)
       rr_queue_q[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]<=state_bank_index[C_QUEUE_WIDTH-1:0];
      else rr_queue_q[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]
       <=dequeue_queue[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]+C_NUM_BANKS[C_QUEUE_WIDTH-1:0];
     end else begin select_valid_q[state_bank_index]<=1'b1;
      select_queue_q[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]<=dequeue_queue[state_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH];end
    end
    end
   end
  end
 end
 switch_tile_multi_ingress_buffer #(.C_INGRESS_PORTS(C_INGRESS_PORTS),.C_NUM_BANKS(C_NUM_BANKS),
  .C_NUM_VOQS(C_NUM_VOQS),.C_QUEUE_DEPTH(C_QUEUE_DEPTH),.C_DATA_WIDTH(C_DATA_WIDTH),
  .C_META_WIDTH(C_PACK_WIDTH),.C_QUEUE_WIDTH(C_QUEUE_WIDTH),.C_ADDR_WIDTH(C_ADDR_WIDTH),
  .C_COUNT_WIDTH(C_COUNT_WIDTH),.C_INGRESS_WIDTH(C_INGRESS_WIDTH),.C_BANK_WIDTH(C_BANK_WIDTH)) u_buffer(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(buffer_valid),.o_ready(buffer_ready),.i_data(i_data),
  .i_meta(packed_input),.i_queue(queue_bus),.i_sop(i_sop),.i_eop(i_eop),.i_packet_flits(i_packet_flits),
  .i_dequeue_request(dequeue_request),.i_dequeue_queue(dequeue_queue),.o_dequeue_valid(dequeue_valid),
  .i_dequeue_ready(dequeue_ready),.o_dequeue_data(buffer_data),.o_dequeue_meta(buffer_packed_output),
  .o_dequeue_sop(dequeue_sop),.o_dequeue_eop(dequeue_eop),.o_bank_conflict(bank_conflict_unused),
  .o_retry(retry_unused),.o_occupancy(o_occupancy),.o_reserved(reserved_unused),
  .o_total_occupancy(total_occupancy_unused),.o_total_reserved(total_reserved_unused),
  .o_protocol_error(buffer_protocol_error),.o_overflow_error(buffer_overflow_error),
  .o_underflow_error(buffer_underflow_error),.o_overflow_event_level(o_overflow_event_level),
  .o_underflow_event_level(o_underflow_event_level),.o_config_error(buffer_config_error),
  .o_error(buffer_error),.o_quiescent(buffer_quiescent));
endmodule
`default_nettype wire
