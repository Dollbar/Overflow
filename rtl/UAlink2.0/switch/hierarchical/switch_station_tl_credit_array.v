`default_nettype none
// Switch逐Logical Port TL信用上下文：TX使用唯一tl_credit_ledger，RX退休发布使用唯一tl_credit_publish。
// 二十槽顺序保持Request CMD、Response CMD、Request Data、Response Data，每类均为Pool+VC0..3；80b向量为每槽四位。
module switch_station_tl_credit_array #(
 parameter integer C_NUM_STATIONS=256,parameter integer C_CREDIT_WIDTH=8,
 parameter integer C_PORTS=C_NUM_STATIONS*4,parameter integer C_SLOTS=20
)(
 input wire i_clk,input wire i_rstn,input wire [C_NUM_STATIONS*2-1:0] i_station_mode,
 input wire [C_PORTS-1:0] i_port_link_up,input wire [C_PORTS-1:0] i_port_link_reset,
 input wire [C_PORTS-1:0] i_tx_fc_valid,input wire [C_PORTS-1:0] i_tx_fc_finish,input wire [C_PORTS-1:0] i_tx_fc_shared,
 input wire [C_PORTS*C_SLOTS*C_CREDIT_WIDTH-1:0] i_tx_fc_grants,
 input wire [C_PORTS-1:0] i_tx_send,input wire [C_PORTS*80-1:0] i_tx_demands,
 input wire [C_PORTS-1:0] i_rx_start,input wire [C_PORTS-1:0] i_rx_shared,
 input wire [C_PORTS*C_SLOTS*C_CREDIT_WIDTH-1:0] i_rx_capacities,
 input wire [C_PORTS-1:0] i_rx_retire_valid,input wire [C_PORTS*80-1:0] i_rx_releases,input wire [C_PORTS-1:0] i_rx_fc_send,
 output wire [C_PORTS-1:0] o_active_logical_ports,output wire [C_PORTS-1:0] o_operational_ports,
 output wire [C_PORTS-1:0] o_tx_candidate_admit,output wire [C_PORTS-1:0] o_tx_taken,output wire [C_PORTS-1:0] o_tx_initialized,output wire [C_PORTS-1:0] o_tx_shared,
 output wire [C_PORTS*C_SLOTS*(C_CREDIT_WIDTH+1)-1:0] o_tx_capacity,output wire [C_PORTS*C_SLOTS*(C_CREDIT_WIDTH+1)-1:0] o_tx_available,
 output wire [C_PORTS-1:0] o_rx_start_ready,output wire [C_PORTS-1:0] o_rx_start_taken,
 output wire [C_PORTS-1:0] o_rx_retire_ready,output wire [C_PORTS-1:0] o_rx_retire_taken,
 output wire [C_PORTS-1:0] o_rx_fc_valid,output wire [C_PORTS-1:0] o_rx_fc_taken,output wire [C_PORTS-1:0] o_rx_fc_complete,
 output wire [C_PORTS-1:0] o_rx_fc_shared,output wire [C_PORTS*32-1:0] o_rx_fc_word,
 output wire [C_PORTS*512-1:0] o_rx_fc_flit,output wire [C_PORTS*2-1:0] o_rx_fc_msg,
 output wire [C_PORTS-1:0] o_rx_active,output wire [C_PORTS-1:0] o_rx_initialized,output wire [C_PORTS*C_SLOTS*(C_CREDIT_WIDTH+1)-1:0] o_rx_pending,
 output wire o_tx_underflow_event_level,output wire o_tx_overflow_event_level,
 output reg o_inactive_event_error,output reg o_tx_underflow_error,output reg o_tx_overflow_error,
 output wire o_tx_credit_error,output reg o_rx_credit_error,output reg o_illegal_mode_error,output wire o_ras_error
);
 localparam CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&(C_CREDIT_WIDTH>=4)&&(C_CREDIT_WIDTH<=16)&&(C_PORTS==C_NUM_STATIONS*4)&&(C_SLOTS==20);
 reg [C_NUM_STATIONS*2-1:0] registered_mode_q;wire [C_NUM_STATIONS-1:0] mode_change,illegal_mode;
 wire [C_PORTS-1:0] tx_receive_error,tx_allowed,rx_config_error,rx_release_error;
 wire [C_PORTS-1:0] inactive_now;
 genvar s,p,a;
 generate
  if(!CONFIG_LEGAL)begin:gen_invalid switch_station_tl_credit_array_parameters_invalid Invalid_Inst();end
  for(s=0;s<C_NUM_STATIONS;s=s+1)begin:gen_station
   assign mode_change[s]=i_rstn&&(registered_mode_q[s*2+:2]!=i_station_mode[s*2+:2]);
   assign illegal_mode[s]=i_station_mode[s*2+:2]==2'd3;
  end
 endgenerate
 always @(posedge i_clk)begin if(!i_rstn)registered_mode_q<={C_NUM_STATIONS*2{1'b0}};else registered_mode_q<=i_station_mode;end
 generate for(p=0;p<C_PORTS;p=p+1)begin:gen_port
  localparam integer STATION=p/4;localparam integer SLOT=p%4;
  wire [1:0] station_mode;wire mode_active,context_rstn;wire [C_SLOTS*C_CREDIT_WIDTH-1:0] demand_ext;
  wire ledger_shared;wire pub_active,pub_done,pub_shared;wire pub_valid,pub_taken,pub_complete;wire [31:0]pub_word;
  wire [48+C_SLOTS*(C_CREDIT_WIDTH+1):0] unused_pub_state;
  assign station_mode=i_station_mode[STATION*2+:2];
  assign mode_active=(station_mode==2'd0)?(SLOT==0):((station_mode==2'd1)?((SLOT==0)||(SLOT==2)):(station_mode==2'd2));
  assign context_rstn=i_rstn&&mode_active&&i_port_link_up[p]&&!i_port_link_reset[p]&&!mode_change[STATION];
  assign o_active_logical_ports[p]=mode_active;assign o_operational_ports[p]=context_rstn;
  for(a=0;a<C_SLOTS;a=a+1)begin:gen_demand
   assign demand_ext[a*C_CREDIT_WIDTH+:C_CREDIT_WIDTH]={{(C_CREDIT_WIDTH-4){1'b0}},i_tx_demands[(p*C_SLOTS+a)*4+:4]};
  end
  tl_credit_ledger #(.WIDTH(C_CREDIT_WIDTH))u_tx_owner(
   .i_clk(i_clk),.i_rstn(context_rstn),.i_commit(context_rstn),.i_receive(i_tx_fc_valid[p]&&context_rstn),
   .i_send(i_tx_send[p]&&context_rstn),.i_finish(i_tx_fc_finish[p]),.i_shared(i_tx_fc_shared[p]),
   .i_grants(i_tx_fc_grants[p*C_SLOTS*C_CREDIT_WIDTH+:C_SLOTS*C_CREDIT_WIDTH]),.i_demands(demand_ext),
   .o_allowed(tx_allowed[p]),.o_taken(o_tx_taken[p]),.o_receive_error(tx_receive_error[p]),
   .o_capacity(o_tx_capacity[p*C_SLOTS*(C_CREDIT_WIDTH+1)+:C_SLOTS*(C_CREDIT_WIDTH+1)]),
   .o_available(o_tx_available[p*C_SLOTS*(C_CREDIT_WIDTH+1)+:C_SLOTS*(C_CREDIT_WIDTH+1)]),
   .o_done(o_tx_initialized[p]),.o_shared(ledger_shared));
  assign o_tx_shared[p]=ledger_shared;
  assign o_tx_candidate_admit[p]=context_rstn&&tx_allowed[p];
  tl_credit_publish #(.WIDTH(C_CREDIT_WIDTH))u_rx_owner(
   .i_clk(i_clk),.i_rstn(context_rstn),.i_start(i_rx_start[p]&&context_rstn),.i_shared(i_rx_shared[p]),
   .i_capacities(i_rx_capacities[p*C_SLOTS*C_CREDIT_WIDTH+:C_SLOTS*C_CREDIT_WIDTH]),
   .o_start_ready(o_rx_start_ready[p]),.o_start_taken(o_rx_start_taken[p]),.o_config_error(rx_config_error[p]),
   .i_release_valid(i_rx_retire_valid[p]&&context_rstn),.i_releases(i_rx_releases[p*80+:80]),
   .o_release_ready(o_rx_retire_ready[p]),.o_release_taken(o_rx_retire_taken[p]),.i_send(i_rx_fc_send[p]&&context_rstn),
   .o_valid(pub_valid),.o_taken(pub_taken),.o_complete(pub_complete),.o_shared(pub_shared),.o_word(pub_word),
   .o_active(pub_active),.o_done(pub_done),.o_pending(o_rx_pending[p*C_SLOTS*(C_CREDIT_WIDTH+1)+:C_SLOTS*(C_CREDIT_WIDTH+1)]),.o_state(unused_pub_state));
  assign o_rx_fc_valid[p]=context_rstn&&pub_valid;assign o_rx_fc_taken[p]=pub_taken;assign o_rx_fc_complete[p]=pub_valid&&pub_complete;
  wire unused_state_observation;assign unused_state_observation=^unused_pub_state;
  assign o_rx_fc_shared[p]=pub_valid&&pub_shared;assign o_rx_fc_word[p*32+:32]=pub_word^{32{unused_state_observation&1'b0}};
  assign o_rx_fc_flit[p*512+:512]=!pub_valid?512'd0:(pub_complete?{247'd0,pub_shared,8'd1,256'd0}:{480'd0,pub_word});
  assign o_rx_fc_msg[p*2+:2]=(pub_valid&&pub_complete)?2'd2:2'd0;assign o_rx_active[p]=pub_active;assign o_rx_initialized[p]=pub_done;
  assign rx_release_error[p]=i_rx_retire_valid[p]&&context_rstn&&!o_rx_retire_ready[p];
  assign inactive_now[p]=!context_rstn&&(i_tx_fc_valid[p]||i_tx_send[p]||i_rx_start[p]||i_rx_retire_valid[p]||i_rx_fc_send[p]);
 end endgenerate
 assign o_tx_underflow_event_level=|(i_tx_send&~tx_allowed&o_operational_ports);
 assign o_tx_overflow_event_level=|(tx_receive_error&o_tx_initialized);
 assign o_tx_credit_error=o_tx_underflow_error|o_tx_overflow_error;
 always @(posedge i_clk)begin
  if(!i_rstn)begin o_inactive_event_error<=0;o_tx_underflow_error<=0;o_tx_overflow_error<=0;o_rx_credit_error<=0;o_illegal_mode_error<=0;end
  else begin
   if(|inactive_now)o_inactive_event_error<=1;
   if(o_tx_underflow_event_level)o_tx_underflow_error<=1;
   if(|tx_receive_error)o_tx_overflow_error<=1;
   if(|rx_config_error||(|rx_release_error))o_rx_credit_error<=1;
   if(|illegal_mode)o_illegal_mode_error<=1;
  end
 end
 assign o_ras_error=o_inactive_event_error|o_tx_credit_error|o_rx_credit_error|o_illegal_mode_error;
endmodule
`default_nettype wire
