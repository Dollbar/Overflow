`timescale 1ps/1ps
`default_nettype none
// Switch Station逐Logical Port的UPLI多通道原子准入边界。
// demand_valid低至高依次为Request、OrigData、ReadRsp、WriteRsp；每个置位通道
// 同时携带自己的VC/Pool/count，语义decoder必须显式给出，模块不从TL class猜测通道。
// 已预约body由i_pre_reserved标识，不再次扣账；任意其它零需求候选失败关闭。
module switch_station_upli_multi_channel_admission #(
 parameter integer C_NUM_STATIONS=256,
 parameter integer C_CREDIT_WIDTH=4,
 parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY=8,
 parameter integer C_INIT_COUNT_WIDTH=4,
 parameter integer C_INIT_CYCLES=2,
 parameter integer C_PORTS=C_NUM_STATIONS*4,
 parameter integer C_CHANNELS=4,
 parameter integer C_BANKS=C_PORTS*C_CHANNELS
)(
 input wire i_clk,input wire i_rstn,input wire[C_NUM_STATIONS*2-1:0] i_station_mode,
 input wire[C_PORTS-1:0] i_port_link_up,input wire[C_PORTS-1:0] i_port_link_reset,
 input wire[C_BANKS-1:0] i_credit_connected,input wire[C_BANKS-1:0] i_beats_connected,
 input wire[C_BANKS-1:0] i_credit_valid,input wire[C_BANKS-1:0] i_credit_pool,
 input wire[C_BANKS*2-1:0] i_credit_vc,input wire[C_BANKS*2-1:0] i_credit_num,input wire[C_BANKS-1:0] i_credit_init_done,
 input wire[C_PORTS-1:0] i_candidate_valid,output wire[C_PORTS-1:0] o_candidate_ready,input wire[C_PORTS-1:0] i_pre_reserved,
 input wire[C_BANKS-1:0] i_demand_valid,input wire[C_BANKS-1:0] i_demand_pool,input wire[C_BANKS*2-1:0] i_demand_vc,input wire[C_BANKS*3-1:0] i_demand_count,
 output wire[C_PORTS-1:0] o_admitted_valid,input wire[C_PORTS-1:0] i_admitted_ready,output wire[C_PORTS-1:0] o_admitted_fire,
 output wire[C_PORTS-1:0] o_candidate_eligible,output wire[C_PORTS-1:0] o_active_logical_ports,output wire[C_PORTS-1:0] o_operational_ports,
 output wire[C_BANKS-1:0] o_init_confirmed,output wire[C_BANKS*5*C_CREDIT_WIDTH-1:0] o_balances,
 output wire o_credit_error_event_level,
 output reg o_invalid_demand_error,output reg o_inactive_candidate_error,output reg o_credit_error,output reg o_illegal_mode_error,output wire o_ras_error
);
 localparam CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&(C_CREDIT_WIDTH>=3)&&(C_CREDIT_WIDTH<=16)&&(C_PORTS==C_NUM_STATIONS*4)&&(C_CHANNELS==4)&&(C_BANKS==C_PORTS*4);
 reg[C_NUM_STATIONS*2-1:0] registered_mode_q;wire[C_NUM_STATIONS-1:0] mode_change,illegal_mode;
 wire[C_BANKS-1:0] bank_error_pulse,channel_fit;wire[C_PORTS-1:0] all_demands_fit,port_return_present,candidate_fire,inactive_candidate_now,invalid_demand_now;
 genvar s,p,c;
 generate
  if(!CONFIG_LEGAL)begin:g_bad switch_station_upli_multi_channel_admission_parameters_invalid Invalid_Inst();end
  for(s=0;s<C_NUM_STATIONS;s=s+1)begin:g_mode
   assign mode_change[s]=i_rstn&&(registered_mode_q[s*2+:2]!=i_station_mode[s*2+:2]);
   assign illegal_mode[s]=i_station_mode[s*2+:2]==2'd3;
  end
 endgenerate
 always @(posedge i_clk)begin if(!i_rstn)registered_mode_q<=0;else registered_mode_q<=i_station_mode;end
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_port
  localparam integer C_STATION=p/4;localparam integer C_SLOT=p%4;
  wire[1:0] port_mode=i_station_mode[C_STATION*2+:2];
  wire mode_active=(port_mode==2'd0)?(C_SLOT==0):((port_mode==2'd1)?((C_SLOT==0)||(C_SLOT==2)):(port_mode==2'd2));
  wire context_rstn=i_rstn&&(port_mode!=2'd3)&&mode_active&&i_port_link_up[p]&&!i_port_link_reset[p]&&!mode_change[C_STATION];
  wire[3:0] port_demands=i_demand_valid[p*4+:4];wire[11:0] port_counts=i_demand_count[p*12+:12];
  wire demand_shape_legal=((port_demands[0]&&(port_counts[2:0]>=3'd1)&&(port_counts[2:0]<=3'd4))||(!port_demands[0]&&(port_counts[2:0]==3'd0)))&&
   ((port_demands[1]&&(port_counts[5:3]>=3'd1)&&(port_counts[5:3]<=3'd4))||(!port_demands[1]&&(port_counts[5:3]==3'd0)))&&
   ((port_demands[2]&&(port_counts[8:6]>=3'd1)&&(port_counts[8:6]<=3'd4))||(!port_demands[2]&&(port_counts[8:6]==3'd0)))&&
   ((port_demands[3]&&(port_counts[11:9]>=3'd1)&&(port_counts[11:9]<=3'd4))||(!port_demands[3]&&(port_counts[11:9]==3'd0)))&&
   (i_pre_reserved[p]?!(|port_demands):(|port_demands));
  assign o_active_logical_ports[p]=(port_mode!=2'd3)&&mode_active;
  assign o_operational_ports[p]=context_rstn;
  assign port_return_present[p]=|i_credit_valid[p*4+:4];
  assign all_demands_fit[p]=(&channel_fit[p*4+:4])&&(|port_demands);
  // 同Port任一credit return沿串行化候选，避免一个bank因坏return拒绝整沿而其他
  // demanded bank已经扣减。合法return下一沿更新余额后重新参与准入，不做旁路。
  assign o_candidate_eligible[p]=context_rstn&&demand_shape_legal&&(i_pre_reserved[p]||all_demands_fit[p])&&(!port_return_present[p]||i_pre_reserved[p]);
  assign o_admitted_valid[p]=i_candidate_valid[p]&&o_candidate_eligible[p];
  assign o_candidate_ready[p]=o_candidate_eligible[p]&&i_admitted_ready[p];
  assign candidate_fire[p]=o_admitted_valid[p]&&i_admitted_ready[p];
  assign o_admitted_fire[p]=candidate_fire[p];
  assign inactive_candidate_now[p]=i_candidate_valid[p]&&!context_rstn;
  assign invalid_demand_now[p]=i_candidate_valid[p]&&context_rstn&&!demand_shape_legal;
  for(c=0;c<4;c=c+1)begin:g_channel
   localparam integer C_BANK=p*4+c;
   wire[3:0] bank_init;wire[5*C_CREDIT_WIDTH-1:0] bank_balances;
   wire[2:0] demand_account=i_demand_pool[C_BANK]?3'd4:{1'b0,i_demand_vc[C_BANK*2+:2]};wire[2:0] demand_count=i_demand_count[C_BANK*3+:3];
   wire demanded=i_demand_valid[C_BANK];
   // channel_fit只是沿前查询；真正余额改变仍完全属于唯一upli_credit_bank。
   assign channel_fit[C_BANK]=!demanded||(i_credit_connected[C_BANK]&&i_beats_connected[C_BANK]&&o_init_confirmed[C_BANK]&&
    ({3'b000,o_balances[(C_BANK*5*C_CREDIT_WIDTH)+(demand_account*C_CREDIT_WIDTH)+:C_CREDIT_WIDTH]}>={{C_CREDIT_WIDTH{1'b0}},demand_count}));
   upli_credit_bank #(.C_NUM_PORTS(1),.C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY),.C_INIT_COUNT_WIDTH(C_INIT_COUNT_WIDTH),.C_INIT_CYCLES(C_INIT_CYCLES))u_owner(
    .i_clk(i_clk),.i_rstn(context_rstn),.i_credit_connected(i_credit_connected[C_BANK]),.i_beats_connected(i_beats_connected[C_BANK]),
    .i_credit_valid({3'b000,i_credit_valid[C_BANK]&&context_rstn}),.i_credit_pool({3'b000,i_credit_pool[C_BANK]}),
    .i_credit_vc({6'b000000,i_credit_vc[C_BANK*2+:2]}),.i_credit_num({6'b000000,i_credit_num[C_BANK*2+:2]}),
    .i_credit_init_done({3'b000,i_credit_init_done[C_BANK]&&context_rstn}),
    .i_send_valid(candidate_fire[p]&&demanded),.i_send_num(demand_count),.i_send_port(2'd0),.i_send_vc(i_demand_vc[C_BANK*2+:2]),.i_send_pool(i_demand_pool[C_BANK]),
    .o_balances(bank_balances),.o_init_confirmed(bank_init),.o_error(bank_error_pulse[C_BANK]));
   assign o_balances[C_BANK*5*C_CREDIT_WIDTH+:5*C_CREDIT_WIDTH]=bank_balances;
   assign o_init_confirmed[C_BANK]=bank_init[0]^(^bank_init[3:1]&1'b0);
  end
 end endgenerate
 assign o_credit_error_event_level=|bank_error_pulse;
 always @(posedge i_clk)begin
  if(!i_rstn)begin o_invalid_demand_error<=0;o_inactive_candidate_error<=0;o_credit_error<=0;o_illegal_mode_error<=0;end
  else begin
   if(|invalid_demand_now)o_invalid_demand_error<=1;
   if(|inactive_candidate_now)o_inactive_candidate_error<=1;
   if(o_credit_error_event_level)o_credit_error<=1;
   if(|illegal_mode)o_illegal_mode_error<=1;
  end
 end
 assign o_ras_error=!CONFIG_LEGAL|o_invalid_demand_error|o_inactive_candidate_error|o_credit_error|o_illegal_mode_error;
endmodule
`default_nettype wire
