`default_nettype none
// Station TL线上Flow-Control桥：validated RX由真实tl_credit_events分类，普通事务原样分流；
// 本地normal与tl_credit_publish输出经逐Port注册仲裁后送Link，只有Link真实握手才扣TX账本或退休FC快照。
module switch_station_tl_flow_control_bridge #(
 parameter integer C_NUM_STATIONS=256,parameter integer C_CREDIT_WIDTH=8,parameter integer C_FAIR_BOUND=8,
 parameter integer C_PACKET_BOUNDARY_ENABLE=0,
 parameter integer C_PORTS=C_NUM_STATIONS*4,parameter integer C_SLOTS=20
)(
 input wire i_clk,input wire i_rstn,input wire [C_NUM_STATIONS*2-1:0] i_station_mode,
 input wire [C_PORTS-1:0] i_port_link_up,input wire [C_PORTS-1:0] i_port_link_reset,
 input wire [C_PORTS-1:0] i_rx_valid,output wire [C_PORTS-1:0] o_rx_ready,input wire [C_PORTS-1:0] i_rx_validated,
 input wire [C_PORTS*512-1:0] i_rx_flit,input wire [C_PORTS*2-1:0] i_rx_msg,
 output wire [C_PORTS-1:0] o_normal_rx_valid,input wire [C_PORTS-1:0] i_normal_rx_ready,
 output wire [C_PORTS*512-1:0] o_normal_rx_flit,output wire [C_PORTS*2-1:0] o_normal_rx_msg,
 input wire [C_PORTS-1:0] i_normal_tx_valid,output wire [C_PORTS-1:0] o_normal_tx_ready,
 input wire [C_PORTS*512-1:0] i_normal_tx_flit,input wire [C_PORTS*2-1:0] i_normal_tx_msg,input wire [C_PORTS*80-1:0] i_normal_tx_demands,
 input wire [C_PORTS-1:0] i_normal_tx_sop,input wire [C_PORTS-1:0] i_normal_tx_eop,
 output wire [C_PORTS-1:0] o_link_tx_valid,input wire [C_PORTS-1:0] i_link_tx_ready,
 output wire [C_PORTS*512-1:0] o_link_tx_flit,output wire [C_PORTS*2-1:0] o_link_tx_msg,output wire [C_PORTS-1:0] o_link_tx_is_fc,
 output wire [C_PORTS-1:0] o_link_tx_sop,output wire [C_PORTS-1:0] o_link_tx_eop,
 input wire [C_PORTS-1:0] i_rx_start,input wire [C_PORTS-1:0] i_rx_shared,input wire [C_PORTS*C_SLOTS*C_CREDIT_WIDTH-1:0] i_rx_capacities,
 input wire [C_PORTS-1:0] i_rx_retire_valid,input wire [C_PORTS*80-1:0] i_rx_releases,
 output wire [C_PORTS-1:0] o_rx_start_ready,output wire [C_PORTS-1:0] o_rx_start_taken,
 output wire [C_PORTS-1:0] o_rx_retire_ready,output wire [C_PORTS-1:0] o_rx_retire_taken,
 output wire [C_PORTS-1:0] o_active_logical_ports,output wire [C_PORTS-1:0] o_operational_ports,
 output wire [C_PORTS-1:0] o_tx_initialized,output wire [C_PORTS*C_SLOTS*(C_CREDIT_WIDTH+1)-1:0] o_tx_available,
 output wire [C_PORTS-1:0] o_rx_initialized,output wire [C_PORTS*C_SLOTS*(C_CREDIT_WIDTH+1)-1:0] o_rx_pending,
 output wire o_tx_underflow_event_level,output wire o_tx_overflow_event_level,
 output reg o_invalid_rx_error,output reg o_starvation_error,output wire o_credit_error,output wire o_ras_error
);
 localparam CONFIG_LEGAL=(C_CREDIT_WIDTH==8)&&(C_PORTS==C_NUM_STATIONS*4)&&(C_SLOTS==20)&&(C_FAIR_BOUND>=1)&&(C_FAIR_BOUND<=256)&&((C_PACKET_BOUNDARY_ENABLE==0)||(C_PACKET_BOUNDARY_ENABLE==1));
 localparam [7:0] C_FAIR_LAST=C_FAIR_BOUND[7:0]-8'd1;
 wire [C_PORTS*160-1:0] decoded_grants;wire [C_PORTS*2-1:0] decoded_nop,decoded_init,decoded_shared,decoded_poison;
 wire [C_PORTS-1:0] event_legal,credit_event_legal,sequence_legal,fc_event,normal_event,rx_handshake,decode_observation,context_observation;
 wire [C_PORTS*3-1:0] sequence_lower,sequence_upper;
 wire [C_PORTS-1:0] array_tx_admit,array_tx_taken,array_tx_shared,array_rx_active;
 wire [C_PORTS-1:0] array_fc_valid,array_fc_taken,array_fc_complete,array_fc_shared;
 wire [C_PORTS*512-1:0] array_fc_flit;wire [C_PORTS*2-1:0] array_fc_msg;wire [C_PORTS*32-1:0] array_fc_word;
 wire [C_PORTS*C_SLOTS*(C_CREDIT_WIDTH+1)-1:0] unused_tx_capacity;
 wire inactive_error,tx_underflow,tx_overflow,tx_credit_error,rx_credit_error,mode_error,array_ras;
 reg [C_PORTS-1:0] slot_valid_q,slot_fc_q,slot_sop_q,slot_eop_q,normal_packet_open_q,prefer_fc_q;reg [C_PORTS*512-1:0] slot_flit_q;
 reg [C_PORTS*2-1:0] slot_msg_q;reg [C_PORTS*80-1:0] slot_demands_q;reg [C_PORTS*8-1:0] normal_wait_q,fc_wait_q;
 wire [C_PORTS*80-1:0] selected_demands;wire [C_PORTS-1:0] array_tx_send,array_fc_send;
 wire [C_PORTS-1:0] choose_fc,choose_normal,slot_transfer,capture_window,fc_capture_safe,normal_capture_admit,normal_packet_hold;
 // 只计算“旧normal本拍真实发送后，新normal是否仍有余额”。计数状态仍只存在于
 // tl_credit_ledger；该函数不生成、保存或消费信用。shared模式沿用账本的Req/Rsp Data Pool合并规则。
 function post_send_normal_fit;
  input [79:0] old_demands;input [79:0] new_demands;
  input [C_SLOTS*(C_CREDIT_WIDTH+1)-1:0] available;input shared_mode;
  integer account;reg [C_CREDIT_WIDTH:0] combined;begin post_send_normal_fit=1'b1;combined=0;
   for(account=0;account<C_SLOTS;account=account+1)begin
    if(shared_mode&&(account==10))combined={{(C_CREDIT_WIDTH-3){1'b0}},old_demands[10*4+:4]}+{{(C_CREDIT_WIDTH-3){1'b0}},old_demands[15*4+:4]}+{{(C_CREDIT_WIDTH-3){1'b0}},new_demands[10*4+:4]}+{{(C_CREDIT_WIDTH-3){1'b0}},new_demands[15*4+:4]};
    else if(shared_mode&&(account==15))combined=0;
    else combined={{(C_CREDIT_WIDTH-3){1'b0}},old_demands[account*4+:4]}+{{(C_CREDIT_WIDTH-3){1'b0}},new_demands[account*4+:4]};
    if(combined>available[account*(C_CREDIT_WIDTH+1)+:C_CREDIT_WIDTH+1])post_send_normal_fit=1'b0;
   end
  end
 endfunction
 genvar p;
 generate
  if(!CONFIG_LEGAL)begin:gen_invalid switch_station_tl_flow_control_bridge_parameters_invalid Invalid_Inst();end
  for(p=0;p<C_PORTS;p=p+1)begin:gen_decode
   wire [1:0] nop_evt,init_evt,shared_evt,poison_evt;wire [2:0] req_count;wire [3:0]rsp_count;wire [7:0]starts,req_starts,rsp_starts;
   wire structure_valid;
   wire sequence_taken,sequence_rejected;wire [6:0] sequence_pending;wire [72:0] sequence_be;
   wire derived_control;
   // Link只提供validated 512b TL Flit与M0/M1。Control/Data类别必须由真实有序
   // TL内容自行派生；不得依赖Full-IP并不存在的测试侧带i_rx_control。
   tl_sequence u_sequence(.i_clk(i_clk),.i_rstn(i_rstn&&o_operational_ports[p]),
    .i_commit(rx_handshake[p]&&i_rx_validated[p]&&event_legal[p]),.i_auth(1'b0),
    .i_lower(i_rx_flit[p*512+:256]),.i_msg(i_rx_msg[p*2+:2]),
    .i_type0(i_rx_flit[p*512+:8]),.i_type1(i_rx_flit[p*512+256+:8]),
    .o_allowed(sequence_legal[p]),.o_taken(sequence_taken),.o_rejected(sequence_rejected),
    .o_lower(sequence_lower[p*3+:3]),.o_upper(sequence_upper[p*3+:3]),
    .o_pending(sequence_pending),.o_be(sequence_be));
   assign derived_control=(sequence_lower[p*3+:3]==3'd0);
   tl_control_decode u_control(i_rx_flit[p*512+:256],structure_valid,req_count,rsp_count,starts,req_starts,rsp_starts);
   tl_credit_events u_events(.i_lower(i_rx_flit[p*512+:256]),.i_upper(i_rx_flit[p*512+256+:256]),.i_msg(i_rx_msg[p*2+:2]),
    .i_control(derived_control),.o_valid(credit_event_legal[p]),.o_grants(decoded_grants[p*160+:160]),.o_nop(nop_evt),.o_init(init_evt),.o_shared(shared_evt),.o_poison(poison_evt));
   assign event_legal[p]=sequence_legal[p]&&credit_event_legal[p];
   assign decoded_nop[p*2+:2]=nop_evt;assign decoded_init[p*2+:2]=init_evt;assign decoded_shared[p*2+:2]=shared_evt;assign decoded_poison[p*2+:2]=poison_evt;
   assign fc_event[p]=event_legal[p]&&((|decoded_grants[p*160+:160])||(|init_evt)||(|nop_evt)||(derived_control&&(req_count==0)&&(rsp_count==0)));
   assign normal_event[p]=event_legal[p]&&!(|poison_evt)&&!(|init_evt)&&!(|nop_evt)&&
    (!derived_control||(req_count!=0)||(rsp_count!=0)||(sequence_upper[p*3+:3]==3'd1)||(sequence_upper[p*3+:3]==3'd2));
   // RX分类只依赖本Port的validated输入与下游事务接收能力，不读取TX信用状态。
   // 这样peer grant的解码/入账不会经TX allowed再反馈到同拍RX ready。
   assign o_rx_ready[p]=o_operational_ports[p]?
    ((!i_rx_validated[p]||!event_legal[p]||(!fc_event[p]&&!normal_event[p]))?1'b1:
     (normal_event[p]?i_normal_rx_ready[p]:1'b1)):1'b0;
   assign o_normal_rx_valid[p]=o_operational_ports[p]&&i_rx_valid[p]&&i_rx_validated[p]&&event_legal[p]&&normal_event[p];
   assign rx_handshake[p]=i_rx_valid[p]&&o_rx_ready[p];
   assign o_normal_rx_flit[p*512+:512]=i_rx_flit[p*512+:512];assign o_normal_rx_msg[p*2+:2]=i_rx_msg[p*2+:2];
   assign slot_transfer[p]=slot_valid_q[p]&&i_link_tx_ready[p];
   assign capture_window[p]=!slot_valid_q[p]||slot_transfer[p];
   // FC publisher在退休沿后才推进快照。旧slot若正发送FC，同拍禁止重捕当前旧快照；
   // 可改抓normal，下一拍再看到publisher推进后的新FC。
   assign fc_capture_safe[p]=array_fc_valid[p]&&!(slot_transfer[p]&&slot_fc_q[p]);
   assign normal_capture_admit[p]=(slot_transfer[p]&&!slot_fc_q[p])?
    post_send_normal_fit(slot_demands_q[p*80+:80],i_normal_tx_demands[p*80+:80],o_tx_available[p*C_SLOTS*(C_CREDIT_WIDTH+1)+:C_SLOTS*(C_CREDIT_WIDTH+1)],array_tx_shared[p]):array_tx_admit[p];
   // normal包的owner由真实Link握手更新。SOP发送同沿即可保护refill body；
   // EOP发送同沿解除保护，使等待的FC可以无气泡接替。
   assign normal_packet_hold[p]=(C_PACKET_BOUNDARY_ENABLE!=0)&&
    ((normal_packet_open_q[p]&&!(slot_transfer[p]&&!slot_fc_q[p]&&slot_eop_q[p]))||
     (slot_transfer[p]&&!slot_fc_q[p]&&slot_sop_q[p]&&!slot_eop_q[p]));
   assign choose_fc[p]=capture_window[p]&&fc_capture_safe[p]&&!normal_packet_hold[p]&&
    (!i_normal_tx_valid[p]||!normal_capture_admit[p]||prefer_fc_q[p]);
   assign choose_normal[p]=capture_window[p]&&i_normal_tx_valid[p]&&normal_capture_admit[p]&&!choose_fc[p];
   // normal ready不依赖本源valid；RR仅在另一路已有FC且本轮明确优先FC时屏蔽normal。
   assign o_normal_tx_ready[p]=o_operational_ports[p]&&capture_window[p]&&normal_capture_admit[p]&&
    (normal_packet_hold[p]||!fc_capture_safe[p]||!prefer_fc_q[p]);
   // 捕获前使用候选需求；捕获后必须以寄存需求完成真实Link握手扣账。
   assign selected_demands[p*80+:80]=(slot_valid_q[p]&&!slot_fc_q[p])?slot_demands_q[p*80+:80]:i_normal_tx_demands[p*80+:80];
   assign array_tx_send[p]=o_operational_ports[p]&&slot_valid_q[p]&&!slot_fc_q[p]&&i_link_tx_ready[p];
   assign array_fc_send[p]=o_operational_ports[p]&&slot_valid_q[p]&&slot_fc_q[p]&&i_link_tx_ready[p];
   assign o_link_tx_valid[p]=slot_valid_q[p];assign o_link_tx_is_fc[p]=slot_valid_q[p]&&slot_fc_q[p];
   assign o_link_tx_sop[p]=slot_valid_q[p]&&slot_sop_q[p];assign o_link_tx_eop[p]=slot_valid_q[p]&&slot_eop_q[p];
   assign o_link_tx_flit[p*512+:512]=slot_flit_q[p*512+:512];assign o_link_tx_msg[p*2+:2]=slot_msg_q[p*2+:2];
   assign decode_observation[p]=structure_valid^(^starts)^(^req_starts)^(^rsp_starts)^sequence_taken^sequence_rejected^(^sequence_pending)^(^sequence_be);
   assign context_observation[p]=array_tx_taken[p]^array_fc_taken[p]^array_fc_complete[p]^array_fc_shared[p]^(^array_fc_word[p*32+:32]);
 end
 endgenerate
 integer q;
 wire [C_PORTS-1:0] peer_fc_valid=rx_handshake&i_rx_validated&event_legal&fc_event;
 wire [C_PORTS-1:0] peer_fc_finish;wire [C_PORTS-1:0] peer_fc_shared;
 generate for(p=0;p<C_PORTS;p=p+1)begin:gen_peer
  assign peer_fc_finish[p]=|decoded_init[p*2+:2];assign peer_fc_shared[p]=|decoded_shared[p*2+:2];
 end endgenerate
 switch_station_tl_credit_array #(.C_NUM_STATIONS(C_NUM_STATIONS),.C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_PORTS(C_PORTS),.C_SLOTS(C_SLOTS))u_context(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_station_mode(i_station_mode),.i_port_link_up(i_port_link_up),.i_port_link_reset(i_port_link_reset),
  .i_tx_fc_valid(peer_fc_valid),.i_tx_fc_finish(peer_fc_finish),.i_tx_fc_shared(peer_fc_shared),.i_tx_fc_grants(decoded_grants),
  .i_tx_send(array_tx_send),.i_tx_demands(selected_demands),.i_rx_start(i_rx_start),.i_rx_shared(i_rx_shared),.i_rx_capacities(i_rx_capacities),
  .i_rx_retire_valid(i_rx_retire_valid),.i_rx_releases(i_rx_releases),.i_rx_fc_send(array_fc_send),
  .o_active_logical_ports(o_active_logical_ports),.o_operational_ports(o_operational_ports),.o_tx_candidate_admit(array_tx_admit),
  .o_tx_taken(array_tx_taken),.o_tx_initialized(o_tx_initialized),.o_tx_shared(array_tx_shared),.o_tx_capacity(unused_tx_capacity),.o_tx_available(o_tx_available),
  .o_rx_start_ready(o_rx_start_ready),.o_rx_start_taken(o_rx_start_taken),.o_rx_retire_ready(o_rx_retire_ready),.o_rx_retire_taken(o_rx_retire_taken),
  .o_rx_fc_valid(array_fc_valid),.o_rx_fc_taken(array_fc_taken),.o_rx_fc_complete(array_fc_complete),.o_rx_fc_shared(array_fc_shared),
  .o_rx_fc_word(array_fc_word),.o_rx_fc_flit(array_fc_flit),.o_rx_fc_msg(array_fc_msg),.o_rx_active(array_rx_active),.o_rx_initialized(o_rx_initialized),.o_rx_pending(o_rx_pending),
  .o_tx_underflow_event_level(o_tx_underflow_event_level),.o_tx_overflow_event_level(o_tx_overflow_event_level),
  .o_inactive_event_error(inactive_error),.o_tx_underflow_error(tx_underflow),.o_tx_overflow_error(tx_overflow),.o_tx_credit_error(tx_credit_error),
  .o_rx_credit_error(rx_credit_error),.o_illegal_mode_error(mode_error),.o_ras_error(array_ras));
 always @(posedge i_clk)begin
  if(!i_rstn)begin slot_valid_q<=0;slot_fc_q<=0;slot_sop_q<=0;slot_eop_q<=0;normal_packet_open_q<=0;prefer_fc_q<=0;slot_flit_q<=0;slot_msg_q<=0;slot_demands_q<=0;normal_wait_q<=0;fc_wait_q<=0;o_invalid_rx_error<=0;o_starvation_error<=0;end
  else begin
   for(q=0;q<C_PORTS;q=q+1)begin
    if(!o_operational_ports[q])begin slot_valid_q[q]<=0;slot_fc_q[q]<=0;slot_sop_q[q]<=0;slot_eop_q[q]<=0;normal_packet_open_q[q]<=0;prefer_fc_q[q]<=0;normal_wait_q[q*8+:8]<=0;fc_wait_q[q*8+:8]<=0;end
    else begin
     if(!i_normal_tx_valid[q]||!array_tx_admit[q])normal_wait_q[q*8+:8]<=0;
     if(!array_fc_valid[q])fc_wait_q[q*8+:8]<=0;
     if(slot_transfer[q])begin
      prefer_fc_q[q]<=!slot_fc_q[q];
      if((C_PACKET_BOUNDARY_ENABLE!=0)&&!slot_fc_q[q])begin
       if(slot_eop_q[q])normal_packet_open_q[q]<=0;
       else if(slot_sop_q[q])normal_packet_open_q[q]<=1;
      end
      if(i_normal_tx_valid[q]&&normal_capture_admit[q]&&slot_fc_q[q])begin if(normal_wait_q[q*8+:8]>=C_FAIR_LAST)o_starvation_error<=1;else normal_wait_q[q*8+:8]<=normal_wait_q[q*8+:8]+1'b1;end else normal_wait_q[q*8+:8]<=0;
      if(array_fc_valid[q]&&!slot_fc_q[q])begin if(fc_wait_q[q*8+:8]>=C_FAIR_LAST)o_starvation_error<=1;else fc_wait_q[q*8+:8]<=fc_wait_q[q*8+:8]+1'b1;end else fc_wait_q[q*8+:8]<=0;
     end
     if(choose_fc[q]||choose_normal[q])begin
      slot_valid_q[q]<=1;slot_fc_q[q]<=choose_fc[q];slot_sop_q[q]<=choose_fc[q]?1'b1:((C_PACKET_BOUNDARY_ENABLE!=0)?i_normal_tx_sop[q]:1'b1);slot_eop_q[q]<=choose_fc[q]?1'b1:((C_PACKET_BOUNDARY_ENABLE!=0)?i_normal_tx_eop[q]:1'b1);slot_flit_q[q*512+:512]<=choose_fc[q]?array_fc_flit[q*512+:512]:i_normal_tx_flit[q*512+:512];
      slot_msg_q[q*2+:2]<=choose_fc[q]?array_fc_msg[q*2+:2]:i_normal_tx_msg[q*2+:2];slot_demands_q[q*80+:80]<=i_normal_tx_demands[q*80+:80];
     end else if(slot_transfer[q])slot_valid_q[q]<=0;
     end
    end
   if(|(i_rx_valid&o_rx_ready&(~i_rx_validated|~event_legal|(~fc_event&~normal_event))))o_invalid_rx_error<=1;
  end
 end
 wire unused_context=^(array_tx_shared^array_rx_active)^inactive_error^tx_underflow^tx_overflow^mode_error^(^decode_observation)^(^context_observation)^(^decoded_nop)^(^decoded_poison);
 assign o_credit_error=tx_credit_error|rx_credit_error;assign o_ras_error=!CONFIG_LEGAL|o_invalid_rx_error|o_starvation_error|array_ras|(unused_context&1'b0);
endmodule
`default_nettype wire
