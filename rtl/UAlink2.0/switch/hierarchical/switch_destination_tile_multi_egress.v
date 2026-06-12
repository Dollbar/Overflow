`timescale 1ns/1ps
`default_nettype none
// Destination Tile多入口出口：每个入口先注册，每个目的Port独立仲裁并复用成熟的Port/Class/VC队列叶模块。
// account/token作为opaque reservation身份逐拍保存；仅最终Port真实发送时生成release，账本仍由上游credit模块唯一拥有。
// 叶模块首次展示valid时，相邻Port context必须同步保留一次TL/UPLI发送credit；随后资格撤销不取消已展示beat，直到握手退休。
module switch_destination_tile_multi_egress #(
 parameter integer C_INGRESS_LANES=4,
 parameter integer C_NUM_PORTS=4,
 parameter integer C_NUM_CLASSES=2,
 parameter integer C_NUM_VC=4,
 parameter integer C_DATA_WIDTH=32,
 parameter integer C_META_WIDTH=16,
 parameter integer C_PORT_WIDTH=3,
 parameter integer C_CLASS_WIDTH=1,
 parameter integer C_VC_WIDTH=2,
 parameter integer C_ACCOUNT_WIDTH=8,
 parameter integer C_TOKEN_WIDTH=8,
 parameter integer C_QUEUE_DEPTH=4,
 parameter integer C_COUNT_WIDTH=3,
 parameter integer C_LANE_WIDTH=(C_INGRESS_LANES<=2)?1:(C_INGRESS_LANES<=4)?2:(C_INGRESS_LANES<=8)?3:(C_INGRESS_LANES<=16)?4:5,
 parameter integer C_PORT_INDEX_WIDTH=(C_NUM_PORTS<=2)?1:(C_NUM_PORTS<=4)?2:(C_NUM_PORTS<=8)?3:(C_NUM_PORTS<=16)?4:5,
 parameter integer C_PER_PORT_QUEUES=C_NUM_CLASSES*C_NUM_VC,
 parameter integer C_TOTAL_QUEUES=C_NUM_PORTS*C_PER_PORT_QUEUES
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_INGRESS_LANES-1:0] i_valid,output reg [C_INGRESS_LANES-1:0] o_ready,
 input wire [C_INGRESS_LANES*C_DATA_WIDTH-1:0] i_data,input wire [C_INGRESS_LANES*C_META_WIDTH-1:0] i_meta,
 input wire [C_INGRESS_LANES*C_PORT_WIDTH-1:0] i_dst_port,input wire [C_INGRESS_LANES*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_INGRESS_LANES*C_VC_WIDTH-1:0] i_original_vc,input wire [C_INGRESS_LANES-1:0] i_pool,
 input wire [C_INGRESS_LANES-1:0] i_sop,input wire [C_INGRESS_LANES-1:0] i_eop,
 input wire [C_INGRESS_LANES*C_ACCOUNT_WIDTH-1:0] i_credit_account,
 input wire [C_INGRESS_LANES*C_TOKEN_WIDTH-1:0] i_credit_token,
 input wire [C_NUM_PORTS-1:0] i_port_active,input wire [C_NUM_PORTS-1:0] i_upli_credit,
 input wire [C_NUM_PORTS-1:0] i_tl_credit,input wire [C_NUM_PORTS-1:0] i_link_up,
 output wire [C_NUM_PORTS-1:0] o_head_valid,output wire [C_NUM_PORTS-1:0] o_valid,input wire [C_NUM_PORTS-1:0] i_ready,
 output wire [C_NUM_PORTS*C_DATA_WIDTH-1:0] o_data,output wire [C_NUM_PORTS*C_META_WIDTH-1:0] o_meta,
 output wire [C_NUM_PORTS*C_PORT_WIDTH-1:0] o_dst_port,output wire [C_NUM_PORTS*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_NUM_PORTS*C_VC_WIDTH-1:0] o_original_vc,output wire [C_NUM_PORTS-1:0] o_pool,
 output wire [C_NUM_PORTS-1:0] o_sop,output wire [C_NUM_PORTS-1:0] o_eop,
 output wire [C_NUM_PORTS-1:0] o_release_valid,
 output wire [C_NUM_PORTS*C_ACCOUNT_WIDTH-1:0] o_release_account,
 output wire [C_NUM_PORTS*C_TOKEN_WIDTH-1:0] o_release_token,
 output wire [C_TOTAL_QUEUES*C_COUNT_WIDTH-1:0] o_queue_occupancy,output wire o_empty,output wire o_quiescent,
 output reg o_illegal_input_error,output reg o_inactive_dst_error,output reg o_protocol_error,
 output wire o_config_error,output wire o_error
);
 function width_encodes;
  input integer width_value;input integer count_value;
  begin if((width_value<1)||(width_value>30)||(count_value<1))width_encodes=0;else width_encodes=((32'd1<<width_value)>=count_value);end
 endfunction
 localparam integer C_LEAF_META_WIDTH=C_META_WIDTH+C_ACCOUNT_WIDTH+C_TOKEN_WIDTH;
 localparam [C_PORT_WIDTH:0] C_PORT_LIMIT=C_NUM_PORTS[C_PORT_WIDTH:0];
 localparam [C_CLASS_WIDTH:0] C_CLASS_LIMIT=C_NUM_CLASSES[C_CLASS_WIDTH:0];
 localparam [C_VC_WIDTH:0] C_VC_LIMIT=C_NUM_VC[C_VC_WIDTH:0];
 localparam [C_LANE_WIDTH:0] C_LANE_LIMIT=C_INGRESS_LANES[C_LANE_WIDTH:0];
 localparam CONFIG_LEGAL=(C_INGRESS_LANES>=1)&&(C_INGRESS_LANES<=32)&&(C_NUM_PORTS>=1)&&(C_NUM_PORTS<=32)&&
  (C_NUM_CLASSES>=1)&&(C_NUM_CLASSES<=4)&&(C_NUM_VC>=1)&&(C_NUM_VC<=8)&&(C_DATA_WIDTH>=1)&&(C_META_WIDTH>=1)&&
  (C_ACCOUNT_WIDTH>=1)&&(C_TOKEN_WIDTH>=1)&&(C_QUEUE_DEPTH>=2)&&width_encodes(C_LANE_WIDTH,C_INGRESS_LANES)&&
  width_encodes(C_PORT_INDEX_WIDTH,C_NUM_PORTS)&&
  width_encodes(C_PORT_WIDTH,C_NUM_PORTS)&&width_encodes(C_CLASS_WIDTH,C_NUM_CLASSES)&&width_encodes(C_VC_WIDTH,C_NUM_VC)&&
  width_encodes(C_COUNT_WIDTH,C_QUEUE_DEPTH+1)&&(C_PER_PORT_QUEUES==C_NUM_CLASSES*C_NUM_VC)&&
  (C_TOTAL_QUEUES==C_NUM_PORTS*C_PER_PORT_QUEUES);
 reg [C_INGRESS_LANES-1:0] slot_valid_q;
 reg [C_INGRESS_LANES*C_DATA_WIDTH-1:0] slot_data_q;
 reg [C_INGRESS_LANES*C_META_WIDTH-1:0] slot_meta_q;
 reg [C_INGRESS_LANES*C_PORT_WIDTH-1:0] slot_port_q;
 reg [C_INGRESS_LANES*C_CLASS_WIDTH-1:0] slot_class_q;
 reg [C_INGRESS_LANES*C_VC_WIDTH-1:0] slot_vc_q;
 reg [C_INGRESS_LANES-1:0] slot_pool_q,slot_sop_q,slot_eop_q;
 reg [C_INGRESS_LANES*C_ACCOUNT_WIDTH-1:0] slot_account_q;
 reg [C_INGRESS_LANES*C_TOKEN_WIDTH-1:0] slot_token_q;
 reg [C_INGRESS_LANES-1:0] lane_owner_q;
 reg [C_INGRESS_LANES*C_PORT_WIDTH-1:0] lane_port_q;
 reg [C_INGRESS_LANES*C_CLASS_WIDTH-1:0] lane_class_q;
 reg [C_INGRESS_LANES*C_VC_WIDTH-1:0] lane_vc_q;
 reg [C_INGRESS_LANES-1:0] lane_pool_q;
 reg [C_INGRESS_LANES*C_ACCOUNT_WIDTH-1:0] lane_account_q;
 reg [C_NUM_PORTS-1:0] port_owner_q,port_hold_q;
 reg [C_NUM_PORTS*C_LANE_WIDTH-1:0] port_owner_lane_q,port_hold_lane_q,port_rr_q;
 reg [C_NUM_PORTS-1:0] leaf_in_valid;
 wire [C_NUM_PORTS-1:0] leaf_in_ready;
 reg [C_NUM_PORTS*C_DATA_WIDTH-1:0] leaf_in_data;
 reg [C_NUM_PORTS*C_LEAF_META_WIDTH-1:0] leaf_in_meta;
 reg [C_NUM_PORTS*C_CLASS_WIDTH-1:0] leaf_in_class;
 reg [C_NUM_PORTS*C_VC_WIDTH-1:0] leaf_in_vc;
 reg [C_NUM_PORTS-1:0] leaf_in_pool,leaf_in_sop,leaf_in_eop;
 wire [C_NUM_PORTS*C_LEAF_META_WIDTH-1:0] leaf_out_meta;
 wire [C_NUM_PORTS-1:0] leaf_empty,leaf_illegal,leaf_inactive,leaf_protocol,leaf_error,leaf_dst_zero;
 reg [C_INGRESS_LANES-1:0] slot_pop;
 reg [C_NUM_PORTS*C_LANE_WIDTH-1:0] selected_lane;
 reg [C_NUM_PORTS-1:0] selected_valid;
 reg [C_LANE_WIDTH:0] scan_value;
 integer lane_index,port_index,scan_index,pop_port,reset_index;
 reg lane_legal,lane_phase_legal;
 wire [C_NUM_PORTS-1:0] output_fire=o_valid&i_ready;
 assign o_release_valid=output_fire;
 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error||o_illegal_input_error||o_inactive_dst_error||o_protocol_error||(|leaf_error)||(|leaf_illegal)||(|leaf_inactive)||(|leaf_protocol)||(|leaf_dst_zero);
 assign o_empty=(slot_valid_q=={C_INGRESS_LANES{1'b0}})&&(lane_owner_q=={C_INGRESS_LANES{1'b0}})&&
  (port_owner_q=={C_NUM_PORTS{1'b0}})&&(port_hold_q=={C_NUM_PORTS{1'b0}})&&(&leaf_empty);
 assign o_quiescent=o_empty;
 always @(*) begin
  o_ready={C_INGRESS_LANES{1'b0}};lane_legal=1'b0;lane_phase_legal=1'b0;lane_index=0;
  for(lane_index=0;lane_index<C_INGRESS_LANES;lane_index=lane_index+1) begin
   lane_legal=({1'b0,i_dst_port[lane_index*C_PORT_WIDTH+:C_PORT_WIDTH]}<C_PORT_LIMIT)&&
    ({1'b0,i_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]}<C_CLASS_LIMIT)&&
    ({1'b0,i_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH]}<C_VC_LIMIT);
   if(!lane_owner_q[lane_index])lane_phase_legal=i_sop[lane_index];
   else lane_phase_legal=!i_sop[lane_index]&&
    (i_dst_port[lane_index*C_PORT_WIDTH+:C_PORT_WIDTH]==lane_port_q[lane_index*C_PORT_WIDTH+:C_PORT_WIDTH])&&
    (i_class[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]==lane_class_q[lane_index*C_CLASS_WIDTH+:C_CLASS_WIDTH])&&
    (i_original_vc[lane_index*C_VC_WIDTH+:C_VC_WIDTH]==lane_vc_q[lane_index*C_VC_WIDTH+:C_VC_WIDTH])&&
    (i_pool[lane_index]==lane_pool_q[lane_index])&&
    (i_credit_account[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]==lane_account_q[lane_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]);
   // slot_pop允许同沿refill，入口在持续包体下达到每拍一beat；leaf ready不依赖本周期新输入，故无环。
   if(i_rstn&&CONFIG_LEGAL&&(!slot_valid_q[lane_index]||slot_pop[lane_index])&&lane_legal&&lane_phase_legal&&
      i_port_active[i_dst_port[lane_index*C_PORT_WIDTH+:C_PORT_INDEX_WIDTH]])o_ready[lane_index]=1'b1;
  end
 end
 always @(*) begin
  leaf_in_valid={C_NUM_PORTS{1'b0}};leaf_in_data=0;leaf_in_meta=0;leaf_in_class=0;leaf_in_vc=0;
  leaf_in_pool=0;leaf_in_sop=0;leaf_in_eop=0;selected_valid=0;selected_lane=0;
  scan_value=0;port_index=0;scan_index=0;
  for(port_index=0;port_index<C_NUM_PORTS;port_index=port_index+1) begin
   if(port_owner_q[port_index]) begin selected_valid[port_index]=1'b1;selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]=port_owner_lane_q[port_index*C_LANE_WIDTH+:C_LANE_WIDTH];end
   else if(port_hold_q[port_index]) begin selected_valid[port_index]=1'b1;selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]=port_hold_lane_q[port_index*C_LANE_WIDTH+:C_LANE_WIDTH];end
   else begin
    for(scan_index=0;scan_index<C_INGRESS_LANES;scan_index=scan_index+1) begin
     scan_value={1'b0,port_rr_q[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]}+scan_index[C_LANE_WIDTH:0];
     if(scan_value>=C_LANE_LIMIT)scan_value=scan_value-C_LANE_LIMIT;
     if(!selected_valid[port_index]&&slot_valid_q[scan_value[C_LANE_WIDTH-1:0]]&&slot_sop_q[scan_value[C_LANE_WIDTH-1:0]]&&
       (slot_port_q[scan_value[C_LANE_WIDTH-1:0]*C_PORT_WIDTH+:C_PORT_WIDTH]==port_index[C_PORT_WIDTH-1:0])) begin
      selected_valid[port_index]=1'b1;selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]=scan_value[C_LANE_WIDTH-1:0];
     end
    end
   end
   if(selected_valid[port_index]&&slot_valid_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]]) begin
    leaf_in_valid[port_index]=1'b1;
    leaf_in_data[port_index*C_DATA_WIDTH+:C_DATA_WIDTH]=slot_data_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]*C_DATA_WIDTH+:C_DATA_WIDTH];
    leaf_in_meta[port_index*C_LEAF_META_WIDTH+:C_LEAF_META_WIDTH]={slot_token_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]*C_TOKEN_WIDTH+:C_TOKEN_WIDTH],slot_account_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH],slot_meta_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]*C_META_WIDTH+:C_META_WIDTH]};
    leaf_in_class[port_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]=slot_class_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]*C_CLASS_WIDTH+:C_CLASS_WIDTH];
    leaf_in_vc[port_index*C_VC_WIDTH+:C_VC_WIDTH]=slot_vc_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]*C_VC_WIDTH+:C_VC_WIDTH];
    leaf_in_pool[port_index]=slot_pool_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]];
    leaf_in_sop[port_index]=slot_sop_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]];
    leaf_in_eop[port_index]=slot_eop_q[selected_lane[port_index*C_LANE_WIDTH+:C_LANE_WIDTH]];
   end
  end
 end
 always @(*) begin
  slot_pop={C_INGRESS_LANES{1'b0}};
  pop_port=0;
  for(pop_port=0;pop_port<C_NUM_PORTS;pop_port=pop_port+1)
   if(selected_valid[pop_port]&&leaf_in_valid[pop_port]&&leaf_in_ready[pop_port])
    slot_pop[selected_lane[pop_port*C_LANE_WIDTH+:C_LANE_WIDTH]]=1'b1;
 end
 always @(posedge i_clk) begin
  if(!i_rstn) begin
   slot_valid_q<=0;lane_owner_q<=0;lane_account_q<=0;port_owner_q<=0;port_hold_q<=0;port_owner_lane_q<=0;port_hold_lane_q<=0;port_rr_q<=0;
   o_illegal_input_error<=0;o_inactive_dst_error<=0;o_protocol_error<=0;
  end else begin
   for(reset_index=0;reset_index<C_INGRESS_LANES;reset_index=reset_index+1) begin
    if(slot_pop[reset_index])slot_valid_q[reset_index]<=1'b0;
    if(i_valid[reset_index]&&!o_ready[reset_index]&&(!slot_valid_q[reset_index]||slot_pop[reset_index])) begin
     if(({1'b0,i_dst_port[reset_index*C_PORT_WIDTH+:C_PORT_WIDTH]}>=C_PORT_LIMIT)||({1'b0,i_class[reset_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]}>=C_CLASS_LIMIT)||({1'b0,i_original_vc[reset_index*C_VC_WIDTH+:C_VC_WIDTH]}>=C_VC_LIMIT))o_illegal_input_error<=1'b1;
     else if(!i_port_active[i_dst_port[reset_index*C_PORT_WIDTH+:C_PORT_INDEX_WIDTH]])o_inactive_dst_error<=1'b1;
     else o_protocol_error<=1'b1;
    end
    if(i_valid[reset_index]&&o_ready[reset_index]) begin
     slot_valid_q[reset_index]<=1'b1;slot_data_q[reset_index*C_DATA_WIDTH+:C_DATA_WIDTH]<=i_data[reset_index*C_DATA_WIDTH+:C_DATA_WIDTH];slot_meta_q[reset_index*C_META_WIDTH+:C_META_WIDTH]<=i_meta[reset_index*C_META_WIDTH+:C_META_WIDTH];
     slot_port_q[reset_index*C_PORT_WIDTH+:C_PORT_WIDTH]<=i_dst_port[reset_index*C_PORT_WIDTH+:C_PORT_WIDTH];slot_class_q[reset_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_class[reset_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];slot_vc_q[reset_index*C_VC_WIDTH+:C_VC_WIDTH]<=i_original_vc[reset_index*C_VC_WIDTH+:C_VC_WIDTH];
     slot_pool_q[reset_index]<=i_pool[reset_index];slot_sop_q[reset_index]<=i_sop[reset_index];slot_eop_q[reset_index]<=i_eop[reset_index];slot_account_q[reset_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=i_credit_account[reset_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];slot_token_q[reset_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]<=i_credit_token[reset_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
     if(!lane_owner_q[reset_index])begin lane_port_q[reset_index*C_PORT_WIDTH+:C_PORT_WIDTH]<=i_dst_port[reset_index*C_PORT_WIDTH+:C_PORT_WIDTH];lane_class_q[reset_index*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_class[reset_index*C_CLASS_WIDTH+:C_CLASS_WIDTH];lane_vc_q[reset_index*C_VC_WIDTH+:C_VC_WIDTH]<=i_original_vc[reset_index*C_VC_WIDTH+:C_VC_WIDTH];lane_pool_q[reset_index]<=i_pool[reset_index];lane_account_q[reset_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=i_credit_account[reset_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];lane_owner_q[reset_index]<=!i_eop[reset_index];end
     else if(i_eop[reset_index])lane_owner_q[reset_index]<=1'b0;
    end
   end
   for(reset_index=0;reset_index<C_NUM_PORTS;reset_index=reset_index+1) begin
    if(selected_valid[reset_index]&&leaf_in_valid[reset_index]&&!leaf_in_ready[reset_index]&&!port_owner_q[reset_index])begin port_hold_q[reset_index]<=1'b1;port_hold_lane_q[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH]<=selected_lane[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH];end
    if(leaf_in_valid[reset_index]&&leaf_in_ready[reset_index]) begin
     port_hold_q[reset_index]<=1'b0;
     if(!port_owner_q[reset_index])begin port_owner_lane_q[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH]<=selected_lane[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH];port_owner_q[reset_index]<=!leaf_in_eop[reset_index];end
     else if(leaf_in_eop[reset_index])port_owner_q[reset_index]<=1'b0;
     if(leaf_in_eop[reset_index])begin if({1'b0,selected_lane[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH]}==(C_LANE_LIMIT-1'b1))port_rr_q[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH]<=0;else port_rr_q[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH]<=selected_lane[reset_index*C_LANE_WIDTH+:C_LANE_WIDTH]+1'b1;end
    end
   end
  end
 end
 genvar g;
 generate for(g=0;g<C_NUM_PORTS;g=g+1) begin:GEN_PORT
  switch_destination_tile_egress #(.C_NUM_PORTS(1),.C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VC(C_NUM_VC),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_LEAF_META_WIDTH),.C_PORT_WIDTH(1),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_VC_WIDTH(C_VC_WIDTH),.C_QUEUE_DEPTH(C_QUEUE_DEPTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_TOTAL_QUEUES(C_PER_PORT_QUEUES)) u_port(
   .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(leaf_in_valid[g]),.o_ready(leaf_in_ready[g]),.i_data(leaf_in_data[g*C_DATA_WIDTH+:C_DATA_WIDTH]),.i_meta(leaf_in_meta[g*C_LEAF_META_WIDTH+:C_LEAF_META_WIDTH]),.i_dst_port(1'b0),.i_class(leaf_in_class[g*C_CLASS_WIDTH+:C_CLASS_WIDTH]),.i_original_vc(leaf_in_vc[g*C_VC_WIDTH+:C_VC_WIDTH]),.i_pool(leaf_in_pool[g]),.i_sop(leaf_in_sop[g]),.i_eop(leaf_in_eop[g]),
   .i_port_active(i_port_active[g]),.i_upli_credit(i_upli_credit[g]),.i_tl_credit(i_tl_credit[g]),.i_link_up(i_link_up[g]),.o_head_valid(o_head_valid[g]),.o_valid(o_valid[g]),.i_ready(i_ready[g]),.o_data(o_data[g*C_DATA_WIDTH+:C_DATA_WIDTH]),.o_meta(leaf_out_meta[g*C_LEAF_META_WIDTH+:C_LEAF_META_WIDTH]),.o_dst_port(leaf_dst_zero[g]),.o_class(o_class[g*C_CLASS_WIDTH+:C_CLASS_WIDTH]),.o_original_vc(o_original_vc[g*C_VC_WIDTH+:C_VC_WIDTH]),.o_pool(o_pool[g]),.o_sop(o_sop[g]),.o_eop(o_eop[g]),.o_queue_occupancy(o_queue_occupancy[g*C_PER_PORT_QUEUES*C_COUNT_WIDTH+:C_PER_PORT_QUEUES*C_COUNT_WIDTH]),.o_empty(leaf_empty[g]),.o_illegal_dst_error(leaf_illegal[g]),.o_inactive_dst_error(leaf_inactive[g]),.o_protocol_error(leaf_protocol[g]),.o_error(leaf_error[g]));
  assign o_dst_port[g*C_PORT_WIDTH+:C_PORT_WIDTH]=g[C_PORT_WIDTH-1:0];
  assign o_meta[g*C_META_WIDTH+:C_META_WIDTH]=leaf_out_meta[g*C_LEAF_META_WIDTH+:C_META_WIDTH];
  assign o_release_account[g*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]=leaf_out_meta[g*C_LEAF_META_WIDTH+C_META_WIDTH+:C_ACCOUNT_WIDTH];
  assign o_release_token[g*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]=leaf_out_meta[g*C_LEAF_META_WIDTH+C_META_WIDTH+C_ACCOUNT_WIDTH+:C_TOKEN_WIDTH];
 end endgenerate
endmodule
`default_nettype wire
